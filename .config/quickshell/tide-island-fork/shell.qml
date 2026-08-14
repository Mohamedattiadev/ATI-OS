import QtQuick
import Quickshell
import Quickshell.Io
import IslandBackend

// FORK: the circular theme-change reveal — REQUIREMENTS.md item 5.
import "qml/theme"
// FORK: ForkConfig and IslandTheme live here — see the ForkConfig block below.
import "qml/common"
// FORK: the standalone ring OSD — see showRingOsd().
import "qml/osd"
// FORK: qtile's TreeTab panel as a left sidebar — see the treeTab block near
// the bottom of this file, and the long header in TreeTabSidebar.qml.
import "qml/treetab"
// FORK: HyprlandData, the shared `hyprctl clients` feed. Owned here rather
// than by the sidebar so it exists once per machine and not once per output.
import "qml/workspace"

Scope {
    id: shellRoot

    readonly property bool screenRecordingActive: SystemServices.screenRecordingActive
    property bool focusEnabled: false
    property bool nightLightEnabled: false
    property bool shuttingDown: false

    // ---- NIGHT LIGHT, OWNED HERE AND NOT BY THE CONTROL CENTRE ----
    //
    // The two Processes used to live in ControlCenterLayer, which is loaded
    // only while the control-centre panel is on screen. That made the only
    // route to night light a click on a tile inside a panel you have to open
    // first — so it could not be bound to a key, and it could not be driven
    // by a script, which is the rule about a control whose bugs can only be
    // found by the user. It also meant the action's owner was a thing that
    // may never have been instantiated.
    //
    // The layer still draws the row and still owns the row's busy/notify
    // behaviour; it just asks this for the actual work. See
    // ControlCenterLayer.toggleNightLight and its nightLightController.
    property int nightLightTemperature: 4500
    property bool nightLightBusy: false

    // ok: the command ran. enabled: what the state is now. message: why not,
    // when ok is false. Emitted for BOTH routes, so the control centre shows
    // the same notification whether you clicked the tile or called the IPC.
    signal nightLightResult(bool ok, bool enabled, string message)

    readonly property bool hyprlandNightLight: CompositorBackend.compositor === "hyprland"

    function setNightLight(enabled) {
        if (nightLightBusy)
            return;
        if (enabled === nightLightEnabled) {
            // Not a no-op silently: a caller that asked for the state it is
            // already in gets a truthful answer rather than nothing at all.
            nightLightResult(true, nightLightEnabled, "");
            return;
        }

        nightLightBusy = true;
        if (enabled)
            nightLightEnableProcess.running = true;
        else
            nightLightDisableProcess.running = true;
    }

    function toggleNightLight() {
        setNightLight(!nightLightEnabled);
    }

    function setNightLightTemperature(kelvin) {
        // Clamped to what hyprsunset will accept. Out-of-range values are
        // rejected by the daemon with a non-zero exit, which would surface
        // as "unavailable" and send you looking for a missing package.
        const clamped = Math.max(1000, Math.min(20000, Math.round(kelvin)));
        nightLightTemperature = clamped;
        if (nightLightEnabled && !nightLightBusy) {
            nightLightBusy = true;
            nightLightEnableProcess.running = true;
        }
    }
    property bool islandAutoHideRuntimeEnabled: true

    readonly property var userConfig: UserConfig

    function forEachWindow(callback) {
        const windows = panelVariants.instances ? panelVariants.instances : [];
        for (let index = 0; index < windows.length; index++) {
            const window = windows[index];
            if (window)
                callback(window);
        }
    }

    function showNotificationAll(notification) {
        if (focusEnabled)
            return;

        shellRoot.forEachWindow((window) => {
            if (window && window.showNotification)
                window.showNotification(notification);
        });
    }

    function anyOverviewOpen() {
        if (CompositorBackend.compositor === "niri")
            return false;

        const windows = panelVariants.instances ? panelVariants.instances : [];
        for (let index = 0; index < windows.length; index++) {
            const window = windows[index];
            if (window && window.overviewPhase !== "closed")
                return true;
        }

        return false;
    }

    function prepareOverviewAll() {
        if (CompositorBackend.compositor === "niri")
            return;

        shellRoot.forEachWindow((window) => window.prepareOverview());
    }

    function cancelPreparedOverviewAll() {
        if (CompositorBackend.compositor === "niri")
            return;

        shellRoot.forEachWindow((window) => window.cancelPreparedOverview());
    }

    function openOverviewAll() {
        if (CompositorBackend.compositor === "niri")
            return;

        shellRoot.forEachWindow((window) => window.openOverview());
    }

    function closeOverviewAll() {
        if (CompositorBackend.compositor === "niri")
            return;

        shellRoot.forEachWindow((window) => window.closeOverview());
    }

    function toggleOverviewAll() {
        if (CompositorBackend.compositor === "niri")
            return;

        if (shellRoot.anyOverviewOpen())
            shellRoot.closeOverviewAll();
        else
            shellRoot.openOverviewAll();
    }

    function anyIslandShown() {
        const windows = panelVariants.instances ? panelVariants.instances : [];
        for (let index = 0; index < windows.length; index++) {
            const window = windows[index];
            if (window && window.autoHideTargetVisible)
                return true;
        }

        return false;
    }

    function showIslandAll() {
        shellRoot.forEachWindow((window) => {
            if (window && window.showIslandWindow)
                window.showIslandWindow();
        });
    }

    function hideIslandAll() {
        shellRoot.forEachWindow((window) => {
            if (window && window.hideIslandWindow)
                window.hideIslandWindow();
        });
    }

    function toggleIslandAll() {
        if (shellRoot.anyIslandShown())
            shellRoot.hideIslandAll();
        else
            shellRoot.showIslandAll();
    }

    function refreshIslandAutoHideAll() {
        shellRoot.forEachWindow((window) => {
            if (window && window.refreshAutoHideWindow)
                window.refreshAutoHideWindow();
        });
    }

    function refreshOverviewWallpaperCaches(wallpaperPath) {
        shellRoot.forEachWindow((window) => {
            if (window
                    && wallpaperPath !== undefined
                    && wallpaperPath !== null
                    && String(wallpaperPath) !== "") {
                window.wallpaperPickerActiveWallpaper = String(wallpaperPath);
            }
            if (window && window.prewarmWallpaperCache)
                window.prewarmWallpaperCache();
        });
    }

    function forFocusedWindow(callback) {
        const windows = panelVariants.instances ? panelVariants.instances : [];
        let fallbackWindow = null;
        for (let index = 0; index < windows.length; index++) {
            const window = windows[index];
            if (window && !fallbackWindow)
                fallbackWindow = window;
            if (window && window.monitorFocused) {
                callback(window);
                return;
            }
        }

        if (fallbackWindow)
            callback(fallbackWindow);
    }

    // FORK: REQUIREMENTS.md item 5, the circular theme-change animation.
    //
    // It lives in shellRoot rather than inside the theme picker because the
    // picker is a Loader that UNLOADS when the island leaves the picker
    // state — and the very first thing a theme change does is close the
    // picker. An animation owned by the thing that triggers it would be
    // destroyed on frame one.
    function startThemeTransition(themeName) {
        if (!themeName)
            return;

        // FORK SETTING, forkThemeTransitionEnabled. Off applies the theme
        // DIRECTLY — theme-apply repaints the desktop in stages, which is
        // the unanimated behaviour the settings row describes and which was
        // previously unreachable because nothing read the switch.
        //
        // The early return has to run theme-apply itself rather than just
        // skipping: begin() is what invokes it behind the frozen screenshot,
        // so returning without it would make the toggle mean "do not change
        // the theme at all".
        // Same absolute path the overlay uses (see ThemeTransitionWindow's
        // themeApplyPath below) and NOT a bare "theme-apply": Quickshell is
        // started by the compositor, so its PATH is the session's, and
        // ~/.dotfiles/.config/AtiScriptsV1 is not on it.
        if (forkConfig && !forkConfig.themeTransitionEnabled) {
            themeApplyDirect.command = [
                Quickshell.env("HOME") + "/.dotfiles/.config/AtiScriptsV1/theme-apply",
                String(themeName)];
            themeApplyDirect.running = true;
            return;
        }

        const windows = themeTransitionVariants.instances
            ? themeTransitionVariants.instances : [];
        if (windows.length === 0)
            return;
        for (let index = 0; index < windows.length; index++) {
            if (windows[index])
                windows[index].begin(String(themeName));
        }
    }

    // Only the first screen's overlay runs theme-apply, so only it learns when
    // theme-apply has finished — and since the fix for the sixth trap that is
    // the event the whole sweep now waits on. Without this relay every other
    // output would sit on a frozen screenshot until its 12 s cap fired, long
    // after its neighbour had revealed. noteThemeApplied() is idempotent, so
    // relaying to the emitter as well is free and keeps this one loop.
    //
    // This machine has ONE output, so the relay is unreachable in daily use and
    // would rot silently. It was checked by making a second one for the test —
    // `hyprctl output create headless`, removed again after — which is enough
    // for Quickshell to build a second overlay window: both mapped (112 ms and
    // 180 ms) and both unmapped on the same poll at 5998 ms. Without the relay
    // the second would have held its frozen frame until its own 12 s cap.
    function relayThemeApplied() {
        const windows = themeTransitionVariants.instances
            ? themeTransitionVariants.instances : [];
        for (let index = 0; index < windows.length; index++) {
            if (windows[index])
                windows[index].noteThemeApplied();
        }
    }

    Variants {
        id: themeTransitionVariants

        model: Quickshell.screens

        ThemeTransitionWindow {
            required property var modelData

            screen: modelData
            outputName: modelData && modelData.name !== undefined
                ? String(modelData.name) : ""
            themeApplyPath: Quickshell.env("HOME")
                + "/.dotfiles/.config/AtiScriptsV1/theme-apply"
            // Only the first screen's overlay runs theme-apply; see the note
            // in ThemeTransitionWindow.qml. Compared by identity against the
            // screen list rather than by an index property, because Variants
            // gives no index.
            ownsThemeApply: Quickshell.screens.length === 0
                || modelData === Quickshell.screens[0]

            onThemeApplied: shellRoot.relayThemeApplied()
        }
    }

    Process {
        id: nightLightEnableProcess
        command: [
            "sh",
            "-c",
            shellRoot.hyprlandNightLight
                ? "temp=\"$1\"\n"
                    + "if ! command -v hyprsunset >/dev/null 2>&1; then exit 127; fi\n"
                    + "if hyprctl hyprsunset temperature \"$temp\" >/dev/null 2>&1; then exit 0; fi\n"
                    + "if ! command -v pgrep >/dev/null 2>&1 || ! pgrep -x hyprsunset >/dev/null 2>&1; then\n"
                    + "  if command -v setsid >/dev/null 2>&1; then\n"
                    + "    setsid hyprsunset >/dev/null 2>&1 < /dev/null &\n"
                    + "  else\n"
                    + "    nohup hyprsunset >/dev/null 2>&1 < /dev/null &\n"
                    + "  fi\n"
                    + "fi\n"
                    + "i=0\n"
                    + "while [ \"$i\" -lt 24 ]; do\n"
                    + "  if hyprctl hyprsunset temperature \"$temp\" >/dev/null 2>&1; then exit 0; fi\n"
                    + "  i=$((i + 1))\n"
                    + "  sleep 0.04\n"
                    + "done\n"
                    // ---- NO gammastep FALLBACK ON HYPRLAND. IT CANNOT WORK ----
                    //
                    // There was one here. It was not merely dead — it was
                    // actively worse than nothing, and it is why night light
                    // looked finished while doing nothing at all.
                    //
                    // Hyprland 0.56.2 does not implement wlr-gamma-control,
                    // so gammastep has no output it can touch. Measured:
                    //
                    //     $ gammastep -P -O 4500
                    //     Warning: Zero outputs support gamma adjustment.
                    //     Warning: 1/1 output(s) do not support gamma
                    //              adjustment.
                    //
                    // and it then HANGS rather than exiting — the earlier
                    // note here recorded "exits 0", which is wrong and is
                    // worth correcting because it changes the consequence.
                    // The old branch backgrounded that command and then
                    // `exit 0`, so the row reported "Night Light enabled",
                    // the screen never changed, and a stuck gammastep was
                    // left behind every time the fallback was reached.
                    //
                    // gammastep stays INSTALLED and declared: qtile drives it
                    // under X11 with `-m randr` (config.py `_nightlight_on`),
                    // where randr gamma works. It is this Wayland path that
                    // is impossible, not the tool. hyprsunset uses Hyprland's
                    // own CTM protocol, which is why it works here.
                    + "exit 127"
                : "temp=\"$1\"\n"
                    + "if ! command -v gammastep >/dev/null 2>&1; then exit 127; fi\n"
                    + "pkill -x gammastep >/dev/null 2>&1\n"
                    + "if command -v setsid >/dev/null 2>&1; then\n"
                    + "  setsid gammastep -m wayland -O \"$temp\" >/dev/null 2>&1 < /dev/null &\n"
                    + "else\n"
                    + "  nohup gammastep -m wayland -O \"$temp\" >/dev/null 2>&1 < /dev/null &\n"
                    + "fi\n"
                    + "exit 0",
            "tide-night-light",
            shellRoot.nightLightTemperature.toString()
        ]
        running: false

        onExited: function(exitCode) {
            shellRoot.nightLightBusy = false;
            if (exitCode === 0) {
                shellRoot.nightLightEnabled = true;
                shellRoot.nightLightResult(true, true, "");
                return;
            }

            shellRoot.nightLightEnabled = false;
            shellRoot.nightLightResult(false, false,
                // Names ONE package, and the right one for the compositor you
                // are actually running. It named both until hyprsunset was
                // measured: on Hyprland gammastep is not a second thing that
                // would have worked, it is a thing that cannot work, and
                // offering it sends you to install a package and find the
                // button still dead.
                shellRoot.hyprlandNightLight
                    ? "Install hyprsunset to use Night Light on Hyprland."
                    : "Install gammastep to use Night Light.");
        }
    }

    Process {
        id: nightLightDisableProcess
        command: [
            "sh",
            "-c",
            // Both backends are cleared regardless of which one enabled it.
            // The two lines are the two compositor cases — `identity` is the
            // hyprsunset one, the pkill is a non-Hyprland session on
            // gammastep — and running the inapplicable one costs nothing.
            //
            // `identity` rather than killing the hyprsunset daemon: it clears
            // the filter and leaves the daemon up, so the next enable is one
            // IPC call instead of a spawn plus a wait loop.
            //
            // `pkill -x`, never `pkill -f`: -f matches this script's own
            // command line, which is how a pkill takes down the shell that
            // ran it.
            //
            // NOTE, because it looks like a state query and is not:
            // `hyprctl hyprsunset temperature` reports the last temperature
            // REQUESTED, not the one in effect. After `identity` it still
            // answers 3000 (measured). There is no "is the filter on" query
            // in hyprsunset 0.4.0, so nightLightEnabled is the state of
            // record and nothing should try to re-derive it from the daemon.
            "hyprctl hyprsunset identity >/dev/null 2>&1 || true\n"
                + "pkill -x gammastep >/dev/null 2>&1 || true\n"
                + "exit 0"
        ]
        running: false

        onExited: function(exitCode) {
            // No failure branch. Turning night light OFF cannot fail for want
            // of a tool: the script clears hyprsunset if it is there and
            // kills gammastep if it is there, and either missing is the same
            // as either already being off. It exits 0 unconditionally.
            shellRoot.nightLightBusy = false;
            shellRoot.nightLightEnabled = false;
            shellRoot.nightLightResult(true, false, "");
        }
    }

    // FORK: night light over IPC.
    //
    // Same two reasons as toggleFocus below it. It makes night light
    // BINDABLE — until now the only route was a tile inside a panel you had
    // to open first — and it makes it TESTABLE, which matters more here than
    // anywhere else in this shell: the effect is a colour transform applied
    // at SCANOUT, so `grim` cannot see it (measured: a 3000K filter moved the
    // captured blue mean by 0.2%, against the ~40% a real warm shift is).
    // Verifying the visible result needs the user's eyes either way, but
    // driving the code path and reading the state back does not have to.
    IpcHandler {
        target: "nightlight"

        function on() {
            shellRoot.setNightLight(true);
        }

        function off() {
            shellRoot.setNightLight(false);
        }

        function toggle() {
            shellRoot.toggleNightLight();
        }

        // TYPED, and not optional. An IpcHandler function with an untyped
        // parameter is dropped from the IPC surface entirely — it does not
        // error and does not warn, `qs ipc show` simply does not list it.
        // That trap has cost this shell four calls now.
        function temperature(kelvin: int) {
            shellRoot.setNightLightTemperature(kelvin);
        }

        // Readable state, so a script can assert rather than assume.
        function status(): string {
            return (shellRoot.nightLightEnabled ? "on" : "off")
                + " " + shellRoot.nightLightTemperature + "K"
                + (shellRoot.nightLightBusy ? " busy" : "");
        }
    }

    IpcHandler {
        target: "overview"

        function toggle() {
            shellRoot.toggleOverviewAll();
        }

        function open() {
            shellRoot.openOverviewAll();
        }

        function close() {
            shellRoot.closeOverviewAll();
        }

        function refreshWallpaperCache() {
            shellRoot.refreshOverviewWallpaperCaches();
        }
    }

    IpcHandler {
        target: "island"

        function show() {
            shellRoot.showIslandAll();
        }

        function open() {
            shellRoot.showIslandAll();
        }

        function reveal() {
            shellRoot.showIslandAll();
        }

        function hide() {
            shellRoot.hideIslandAll();
        }

        function toggle() {
            shellRoot.toggleIslandAll();
        }

        function enableAutoHide() {
            shellRoot.islandAutoHideRuntimeEnabled = true;
            shellRoot.refreshIslandAutoHideAll();
        }

        function disableAutoHide() {
            shellRoot.islandAutoHideRuntimeEnabled = false;
            shellRoot.showIslandAll();
        }

    }

    IpcHandler {
        target: "tide"

        // ---- FOCUS OVER IPC, FOR TWO REASONS ----
        //
        // The first is that it makes Focus BINDABLE. Until now the only way
        // to reach do-not-disturb was to open the control centre and click a
        // tile, which is a lot of ceremony for the one control you reach for
        // when you are already trying to concentrate. `tide toggleFocus` is
        // a keybinding.
        //
        // The second is that it makes Focus TESTABLE, and that is not a
        // luxury here. Focus was reported broken and could not be driven
        // from outside the shell at all: there was no IPC, and synthesising
        // a keystroke into the control centre is forbidden. So the only
        // available evidence was reading the code, which said it was fine.
        // A control with no way in from a script is a control whose bugs can
        // only be found by the user.
        //
        // The parameter is TYPED. An IpcHandler function with an untyped
        // parameter is accepted by Quickshell and arrives `undefined`, which
        // for a bool means every call reads as false — setFocus(true) would
        // silently turn Focus OFF. That trap is written up on showPicker and
        // showText and has now cost this shell three calls.
        function setFocus(enabled: bool) {
            shellRoot.focusEnabled = enabled;
        }

        function toggleFocus() {
            shellRoot.focusEnabled = !shellRoot.focusEnabled;
        }

        function showClock() {
            shellRoot.forFocusedWindow((window) => window.showClockWindow());
        }

        function showCustom() {
            shellRoot.forFocusedWindow((window) => window.showCustomInfoWindow());
        }

        function showLyrics() {
            shellRoot.forFocusedWindow((window) => window.showLyricsWindow());
        }

        function swipeRight() {
            shellRoot.forFocusedWindow((window) => window.swipeRightWindow());
        }

        function swipeLeft() {
            shellRoot.forFocusedWindow((window) => window.swipeLeftWindow());
        }

        function togglePlayer() {
            shellRoot.forFocusedWindow((window) => window.togglePlayerWindow());
        }

        function toggleControlCenter() {
            shellRoot.forFocusedWindow((window) => window.toggleControlCenterWindow());
        }

        function toggleNotificationCenter() {
            shellRoot.forFocusedWindow((window) => window.toggleNotificationCenterWindow());
        }

        // The KEYBOARD route to dismissing a notification, and it has to be
        // IPC rather than a `Keys.onPressed` anywhere in the notch.
        //
        // The notification layer takes no keyboard focus and must not: the
        // shell would be stealing the keyboard from whatever you were typing
        // in, every time a message arrived. So there is no focused surface to
        // press Escape into, and the only key that can reach a shell which is
        // not focused is a COMPOSITOR bind. `$alt N` calls this.
        //
        // It matters more since urgency landed: a critical notification does
        // not auto-expire, by design, so without a reachable dismiss it would
        // sit in the notch until something else replaced it. Right-clicking
        // the capsule does the same thing for a hand already on the mouse.
        function dismissNotification() {
            shellRoot.forEachWindow((window) => {
                if (window && window.dismissNotificationWindow)
                    window.dismissNotificationWindow();
            });
        }

        // Invoke the notification's Nth action from outside, for the same
        // reason dismiss is out here: the capsule has no keyboard focus to
        // press a key into, so a compositor bind is the only route. 0 is the
        // first action, which for almost every sender is the "default" one —
        // the thing clicking the card in any other shell would do.
        //
        // Unbound in binds.conf on purpose for now. It exists because the UI
        // path is a mouse click on a button that is only drawn when the
        // capsule is expanded, and a feature reachable one way only is a
        // feature half the shell's own rules reject. Phase 3 is where the
        // keyboard story gets decided panel by panel; this is the seam it
        // will bind to.
        // `index: int` and not a bare `index`, which is not a style
        // preference: an IpcHandler function with an UNTYPED parameter is
        // dropped from the IPC surface entirely. It does not error, it does
        // not warn — `qs ipc show` simply does not list it, and calling it
        // reports an unknown function. Written untyped first, and the only
        // symptom was an action round-trip that produced no ActionInvoked.
        function notificationAction(index: int) {
            shellRoot.forEachWindow((window) => {
                if (window && window.notificationActionWindow)
                    window.notificationActionWindow(index);
            });
        }

        function toggleWallpaperPicker() {
            shellRoot.forFocusedWindow((window) => window.toggleWallpaperPickerWindow());
        }

        function toggleApplicationLauncher() {
            shellRoot.forFocusedWindow((window) => window.toggleApplicationLauncherWindow());
        }

        // FORK: the theme switcher, one of the island states DESIGN-SPEC.md
        // lists and upstream does not have. Bound in hypr/binds.conf
        // alongside toggleWallpaperPicker.
        // FORK: qtile's DisplayPopup, ported. Bound to alt+4 in
        // hypr/binds.conf, which is the key it had in qtile.
        // FORK: qtile's WifiPopup and BluetoothPopup keys, landing straight
        // in the control centre's own lists. See openConnectivityPanelWindow.
        // FORK: the chord heads-up display, driven by
        // hypr/scripts/submap-indicator.sh off Hyprland's event socket.
        //
        // Only the mode NAME crosses the IPC. The rows are fetched by the
        // panel itself — the reason is written up at length in
        // qml/island/ModeKeysLayer.qml, and it is that Quickshell's IPC
        // splits arguments on whitespace in a way shell quoting does not
        // survive.
        //
        // The parameter is typed for the reason in FORK-NOTES.md: an
        // untyped IPC parameter is silently not passed at all, arrives
        // `undefined`, and the handler then clears the very thing it was
        // called to show.
        function showModeKeys(name: string) {
            shellRoot.forEachWindow((window) => window.showModeKeysWindow(name));
        }

        function clearModeKeys() {
            shellRoot.forEachWindow((window) => window.clearModeKeysWindow());
        }

        // FORK: qtile's CheatSheet-Mode, which was on rofi until now.
        // `which` is hypr | vim | fish — one word, so it is safe across an
        // IPC that splits on whitespace (see ModeKeysLayer.qml for what
        // happens when an argument is not).
        //
        // forFocusedWindow, not forEachWindow: this panel takes an
        // exclusive keyboard grab, and two of them on two monitors would
        // be two grabs competing for the same keystrokes. The mode-keys
        // HUD goes on every screen precisely because it takes no grab.
        function showCheatsheet(which: string) {
            shellRoot.forFocusedWindow((window) => window.toggleCheatsheetWindow(which));
        }

        // Explicit close. `showCheatsheet` toggles on the sheet — pressing
        // the chord's `v` while the WM sheet is open switches to vim, and
        // only the same sheet again means "I am done" — which is right for
        // a keybinding and wrong for a script, because a toggle whose phase
        // you have to know is a toggle that goes out of phase. This says
        // shut, and means it whatever state the panel is in.
        function hideCheatsheet() {
            shellRoot.forFocusedWindow((window) => window.hideCheatsheetWindow());
        }

        // FORK: the tour, over IPC.
        //
        // `page` is TYPED and required. An untyped parameter is dropped
        // from the IPC surface without a word, and an int one that arrives
        // undefined would read as 0 — which for this call means "silently
        // reopened at page one" rather than an error, the most annoying
        // possible failure for the one control whose job is to be
        // re-readable at the page you wanted.
        //
        // forFocusedWindow, not forEachWindow: the layer takes a keyboard
        // grab, and two grabs on two monitors would compete for the same
        // keystrokes. Same reason as showCheatsheet above.
        function showOnboarding(page: int) {
            shellRoot.forFocusedWindow((window) => window.showOnboardingWindow(page));
        }

        function hideOnboarding() {
            shellRoot.forFocusedWindow((window) => window.hideOnboardingWindow());
        }

        function toggleWifiPanel() {
            shellRoot.forFocusedWindow((window) => window.openConnectivityPanelWindow("wifi"));
        }

        function toggleBluetoothPanel() {
            shellRoot.forFocusedWindow((window) => window.openConnectivityPanelWindow("bluetooth"));
        }

        function toggleDisplayPanel() {
            shellRoot.forFocusedWindow((window) => window.toggleDisplayPanelWindow());
        }

        // FORK: qtile's AudioPopup, ported. Bound to alt+3 in hypr/binds.conf,
        // which is the key it had in qtile. Deliberately NOT folded into
        // toggleControlCenter: the control centre's Sound row is the volume of
        // the default sink, and this is everything else — which output is the
        // default, per-application volume and routing, card profiles, ports.
        function toggleAudioPanel() {
            shellRoot.forFocusedWindow((window) => window.toggleAudioPanelWindow());
        }

        // FORK: the system monitor — CPU, memory and disk. Bound to $mod+`
        // in hypr/binds.conf, which is the key qtile's "toggle 2nd system
        // widget box" had; that binding's own comment named disk usage as a
        // content gap it was standing in for, and this closes it.
        //
        // forFocusedWindow, like every other panel here: it takes an
        // exclusive keyboard grab to read j/k, and two of them on two
        // monitors would be two grabs competing for the same keystrokes.
        //
        // A TOGGLE, like its neighbours — calling it twice closes the panel.
        // That is also what makes it safe as a single key: the same press
        // that opened it puts it away.
        function toggleSysmon() {
            shellRoot.forFocusedWindow((window) => window.toggleSysmonPanelWindow());
        }

        // FORK: qtile's WifiQR — `s` inside its WiFi chord. Bound to SHIFT+S
        // in the rofi submap, beside the `n` that opens the network list.
        function toggleWifiQr() {
            shellRoot.forFocusedWindow((window) => window.toggleWifiQrWindow());
        }

        function toggleThemePicker() {
            shellRoot.forFocusedWindow((window) => window.toggleThemePickerWindow());
        }

        // FORK: the states DESIGN-SPEC.md's "states of the one shape" listed
        // and nothing answered — calendar, power menu, settings. The spec's
        // fourth, the polkit prompt, is deliberately not among them.
        //
        // `forFocusedWindow`, like every other panel here and unlike the
        // chord HUD's `forEachWindow`: these take a keyboard grab and read
        // their own keys, so exactly one screen may own one. The HUD is the
        // deliberate exception because it is a picture that grabs nothing.
        function toggleCalendar() {
            shellRoot.forFocusedWindow((window) => window.toggleCalendarWindow());
        }

        function togglePowerMenu() {
            shellRoot.forFocusedWindow((window) => window.togglePowerMenuWindow());
        }

        function toggleSettings() {
            shellRoot.forFocusedWindow((window) => window.toggleSettingsWindow());
        }

        // FORK: the generic list picker — one panel behind what were three
        // separate rofi menus (close a window, kill a process, go to a
        // workspace). `which` is the menu name understood by
        // hypr/scripts/island-picker.py: windows | processes | workspaces.
        //
        // The parameter is typed, and it is NOT decoration. Quickshell
        // marshals IPC arguments by declared type, so `function
        // showPicker(which)` would accept the call and arrive with
        // `undefined` — the panel would then open on the string "undefined",
        // island-picker.py would answer `unknown menu undefined`, and the
        // failure would look like a broken script rather than a missing
        // annotation. The same trap is written up on showText below and in
        // FORK-NOTES.md; it has now cost this shell three separate calls.
        //
        // One word, so it also survives the OTHER IPC trap: arguments are
        // split on whitespace in a way shell quoting does not survive. See
        // qml/island/ModeKeysLayer.qml.
        //
        // forFocusedWindow, like every panel that reads its own keys: this
        // one takes an exclusive keyboard grab, and two of them on two
        // monitors would be two grabs competing for the same keystrokes.
        function showPicker(which: string) {
            shellRoot.forFocusedWindow((window) => window.showPickerWindow(which));
        }

        function clearPicker() {
            shellRoot.forEachWindow((window) => window.clearPickerWindow());
        }

        // `showPolkitPrompt` and `clearPolkitPrompt` were registered here and
        // are deliberately gone. They routed to an island state that had no
        // renderer, so calling the first one threw a ReferenceError and left
        // the island invisible on the Overlay layer above everything. The
        // full reasoning, including why building the panel would not have
        // helped, is in DynamicIslandWindow.qml below clearPickerWindow.
        //
        // The short version: this shell never registered as a polkit agent
        // on D-Bus, so the prompt had no transaction to answer, and
        // polkit-kde-authentication-agent-1 (hypr/autostart.conf:23) already
        // does the job correctly.
        //
        // An IPC function is a promise that something will happen. Leaving
        // these registered but broken is worse than not having them: a
        // caller gets a success and no prompt.
        // FORK: apply a theme THROUGH the circular reveal. This is what the
        // theme picker calls instead of running theme-apply itself, and it is
        // exposed on the IPC so `theme-toggle` (the rofi picker, which the
        // qtile session shares) can get the same animation later.
        function applyThemeAnimated(theme: string) {
            shellRoot.startThemeTransition(theme);
        }

        // FORK: arbitrary text in the island, which upstream has no way to
        // do — its `showCustom()` takes no arguments and renders the config's
        // own item list.
        //
        // The parameter MUST be declared with a type. Quickshell's IPC
        // marshals arguments by declared type and an untyped parameter is
        // simply not passed, so `function showText(text)` would accept the
        // call, arrive with undefined, and clear the indicator instead of
        // setting it — succeeding loudly at doing the opposite.
        //
        // Persistent on purpose: it stays until clearText, and survives any
        // transient OSD that interrupts it. hypr/scripts/submap-indicator.sh
        // is the first consumer.
        function showText(text: string) {
            shellRoot.forEachWindow((window) => {
                if (window && window.showModeIndicatorWindow)
                    window.showModeIndicatorWindow("", text);
            });
        }

        function showTextWithIcon(icon: string, text: string) {
            shellRoot.forEachWindow((window) => {
                if (window && window.showModeIndicatorWindow)
                    window.showModeIndicatorWindow(icon, text);
            });
        }

        function clearText() {
            shellRoot.forEachWindow((window) => {
                if (window && window.clearModeIndicatorWindow)
                    window.clearModeIndicatorWindow();
            });
        }
    }

    // The island's own notification server — qml/common/NotificationService.
    //
    // This used to be `target: SystemServices` and
    // `onNotificationReceived(appName, summary, body)`, a spy signal that
    // WATCHED the bus while dunst served it. Both drew every notification,
    // simultaneously, in two design languages; and three strings could not
    // express dismiss, urgency, actions or replace no matter what was built
    // on top of them. See the file header for the whole argument and for
    // the bus-ownership hazard.
    Connections {
        target: NotificationService

        function onPosted(notification) {
            shellRoot.showNotificationAll(notification);
        }
    }

    Component.onDestruction: {
        shuttingDown = true;
    }

    Component.onCompleted: {
        SystemServices.ensureUserConfigAvailable();
        SystemServices.requestScreenRecordingSnapshot();

        // Force the palette singleton to construct HERE, before any window
        // exists, rather than lazily on whichever binding happens to read a
        // colour first.
        //
        // A QML singleton is built on first access. Every colour in the
        // shell now comes from this object, so "first access" would be a
        // paint binding, and the shell would draw one frame in the doomone
        // fallback before repainting in the real theme — a visible flash of
        // the wrong palette across the entire UI, not just the notch.
        //
        // `preload: true` on its FileView does NOT cover this; measured, a
        // probe still reported the fallback on a read 16 ms in, then the
        // real palette from the next one. With this line the same probe was
        // correct on its first read. One statement, and it is the whole fix.
        void IslandTheme.themeName;
    }

    // ---- THE FORK'S OWN SETTINGS, FINALLY CONNECTED TO SOMETHING ----
    //
    // qml/common/ForkConfig.qml was written, documented and never
    // instantiated. Not once, anywhere — the only occurrences of the name
    // in the tree were two comments in SettingsLayer.qml describing what it
    // would do. So every `fork*` key in userconfig.json was inert, and the
    // settings panel offered four switches that changed nothing:
    //
    //   forkNotchMode              DynamicIslandWindow kept its hardcoded
    //                              `property bool notchModeEnabled: true`,
    //                              the literal ForkConfig was written to
    //                              replace. Its comment claims it is
    //                              "toggled live over IPC (island
    //                              setNotchMode)"; there is no such IPC.
    //   forkModeKeysEnabled        the name appears nowhere outside
    //   forkRestingEqEnabled       ForkConfig.qml itself.
    //   forkThemeTransitionEnabled
    //
    // That is the same failure REQUIREMENTS.md already records once for the
    // polkit row — a control that describes behaviour it does not have —
    // except it was four rows rather than one, and they were the four the
    // panel presented as its working half. Instantiated here, once for the
    // whole shell rather than per screen, because it is a file watcher and
    // every DynamicIslandWindow would otherwise open its own on the same
    // path.
    ForkConfig { id: forkConfig }
    readonly property var forkSettings: forkConfig

    // ---- THE STANDALONE RING OSD ----
    //
    // State lives HERE rather than in DynamicIslandWindow because the ring
    // is a different window, and QML ids do not cross component files. The
    // island calls up into showRingOsd(); the ring windows bind down to
    // these three properties. One state for all monitors on purpose — a
    // volume change is a machine-wide event and showing it on the focused
    // screen only means it appears wherever the pointer happens to be.
    property string ringOsdIcon: ""
    property real ringOsdProgress: 0
    property bool ringOsdShown: false
    // The true percentage, which is NOT ringOsdProgress * 100 whenever the
    // sink is boosted past 100%: progress is clamped for the arc, this is
    // not. -1 means the caller had no raw value and the label falls back to
    // progress. See the transientRequested signal in IslandSystemState.qml.
    property real ringOsdRawPercent: -1

    function showRingOsd(icon, progress, rawPercent) {
        shellRoot.ringOsdIcon = String(icon || "");
        shellRoot.ringOsdProgress = Math.max(0, Math.min(1, Number(progress)));
        shellRoot.ringOsdRawPercent = (rawPercent === undefined) ? -1 : Number(rawPercent);
        shellRoot.ringOsdShown = true;
        // restart(), not start(): holding a volume key fires this many times
        // a second, and a Timer that is already running ignores start(),
        // so the OSD would vanish 1.4 s after the FIRST keypress while the
        // level was still moving.
        ringOsdHideTimer.restart();
    }

    Timer {
        id: ringOsdHideTimer
        interval: 1400
        repeat: false
        onTriggered: shellRoot.ringOsdShown = false
    }

    // ---- THE SCREEN CORNERS ----
    //
    // Per-output through Variants, exactly like the island, the ring OSD, the
    // TreeTab sidebar and the theme transition — the four surfaces the second-
    // monitor audit verified are per-output by construction. A single
    // full-screen corner surface would put four corners on the primary output
    // and none anywhere else.
    //
    // No properties to pass: the shape comes from Metrics and the colour from
    // the IslandTheme singleton, and its hide-on-fullscreen behaviour is the
    // Top layer rather than a state anything here would have to feed it. See
    // qml/osd/ScreenCornersWindow.qml.
    // FORK SETTING, forkScreenCornersEnabled, and it gates the MODEL rather
    // than each window's `visible`. An invisible layer-shell surface is still
    // a surface: it is mapped, it is in the compositor's list, and this one
    // spans the whole output. Emptying the model destroys them, so "off"
    // costs one comparison per screen and nothing else. Defaults off — see
    // ForkConfig.qml for the measurement that decided that.
    Variants {
        id: screenCornerVariants
        model: forkConfig.screenCornersEnabled ? Quickshell.screens : []

        ScreenCornersWindow {
            required property var modelData
            screen: modelData
        }
    }

    Variants {
        id: ringOsdVariants
        model: Quickshell.screens

        RingOsdWindow {
            required property var modelData

            screen: modelData
            shellRootController: shellRoot
            iconText: shellRoot.ringOsdIcon
            progress: shellRoot.ringOsdProgress
            rawPercent: shellRoot.ringOsdRawPercent
            shown: shellRoot.ringOsdShown
            iconFontFamily: shellRoot.userConfig.iconFontFamily
            accentColor: IslandTheme.accent
            shellFill: IslandTheme.shellFill
        }
    }

    // The ring used to need its own IslandTheme instance here, because
    // DynamicIslandWindow's was an object with an id and ids are
    // file-scoped. IslandTheme is a singleton now, so there is one palette,
    // one FileView and no way for the two windows to disagree — which is
    // the same argument that put the palette in a generated file rather
    // than in QML in the first place.

    // The unanimated theme apply, for when forkThemeTransitionEnabled is
    // off. Its own Process rather than reusing the overlay's: that one
    // belongs to a per-screen window which, with the transition disabled,
    // is exactly the object we are declining to involve.
    Process { id: themeApplyDirect }

    // ---- qtile's TreeTab, AS qtile DREW IT ----
    //
    // hypr/scripts/layout-cycle.sh mapped TreeTab onto "a Hyprland group
    // with the groupbar switched on", and its own header admits the whole
    // of the claim: the groupbar "is the only thing TreeTab adds to Max".
    // That is right about the information and wrong about the shape —
    // qtile's TreeTab is a 180 px panel down the LEFT EDGE, subtracted from
    // the tiling area, and Hyprland's groupbar is a strip of tabs across
    // the top of the window. Same list, different surface, and the surface
    // was what was asked for.
    //
    // The panel is drawn here rather than by the compositor because there
    // is nothing in Hyprland to draw it with: groups are the only stacking
    // primitive and the groupbar is the only chrome they have. A layer-shell
    // surface with an exclusive zone is the same bargain qtile struck —
    // tree.py's `layout()` hsplits panel_width off the screen rect before
    // placing any window.
    //
    // ---- WHY THE DATA FEED IS BEHIND A LOADER ----
    //
    // HyprlandData re-runs `hyprctl clients`, `monitors`, `workspaces` and
    // `activeworkspace` on every window event, debounced 90 ms. That is
    // cheap for a panel that is open, and it is four processes per window
    // event for the entire session on a machine whose user never touches
    // treetab. It is constructed only while a treetab workspace is focused,
    // which is exactly when the sidebar can be visible at all.
    //
    // ONE instance, not one per screen: it is a machine-wide snapshot and N
    // copies would be N times the subprocesses for identical answers.
    LayoutState { id: treeTabLayoutState }

    Loader {
        id: treeTabDataLoader

        active: treeTabLayoutState.layout === "treetab"
        sourceComponent: Component { HyprlandData {} }
    }

    Variants {
        id: treeTabVariants

        model: Quickshell.screens

        TreeTabSidebar {
            required property var modelData

            screen: modelData
            outputName: modelData && modelData.name !== undefined
                ? String(modelData.name) : ""
            layoutIsTreeTab: treeTabLayoutState.layout === "treetab"
            // Null while the loader is inactive. The sidebar treats that as
            // "nothing to list" and stays retracted, which is the same state
            // it is in on every non-treetab workspace anyway.
            hyprlandData: treeTabDataLoader.item
        }
    }

    Variants {
        id: panelVariants

        model: Quickshell.screens

        DynamicIslandWindow {
            required property var modelData

            screen: modelData
            shellRootController: shellRoot
        }
    }
}
