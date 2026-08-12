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

Scope {
    id: shellRoot

    readonly property bool screenRecordingActive: SystemServices.screenRecordingActive
    property bool focusEnabled: false
    property bool nightLightEnabled: false
    property bool shuttingDown: false
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

    function showNotificationAll(appName, summary, body) {
        if (focusEnabled)
            return;

        shellRoot.forEachWindow((window) => {
            if (window && window.showNotification)
                window.showNotification(appName, summary, body);
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

    Connections {
        target: SystemServices

        function onNotificationReceived(appName, summary, body) {
            shellRoot.showNotificationAll(appName, summary, body);
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
