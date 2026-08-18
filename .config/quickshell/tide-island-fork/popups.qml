import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

import "qml/common"
import "qml/popups"
import "qml/qdrop"
import "qml/theme"

//
// ============================================================
//  qtile's popups, for the sessions that have no qtile
// ============================================================
//
// FORK — new file, and a THIRD entry point into this config directory
// alongside shell.qml and treetab.qml. Same reason as that one: `qs -p <file>`
// resolves a config's imports against the entry file's directory, so
// everything here reaches IslandTheme and the rest of qml/common without
// anything being copied.
//
// WHAT THIS IS FOR
// ----------------
// Several of the topbar's chips are qtile chips whose action is a POPUP
// rather than a command:
//
//     ✖  wallpaper_toggle  ->  toggle_wallpaper_picker  (WallpaperPopup.py)
//     network                  Wifi-Mode                (WifiPopup.py)
//     volume                   Audio-Mode               (AudioPopup.py)
//     w_wifi_qr                WifiQR.toggle            (WifiQR.py)
//
// Under the topbar they ran rofi menus or nothing at all, which is a
// different thing wearing the same key. Asked for directly: "the ✖ chip
// should show the wal picker that was written as a qtile popup — write one in
// Quickshell, same style, same working — and the network and the volume
// popups should be the same style, UX and behaviour."
//
// The last clause is why they share PopupChrome: one frame, one palette
// derivation, one keycap bar, three bodies.
//
// WHY NOT IN THE TOPBAR'S OWN CONFIG
// ----------------------------------
// The same wall treetab.qml ran into, and the same measurement: Quickshell's
// QML scanner refuses a module path outside the config folder, symlink or
// not, so nothing outside this directory can reach IslandTheme. The choice is
// between an entry point here and a second copy of the palette — and this
// tree knows what the second copy costs.
//
// WHY ONE PROCESS FOR ALL THREE
// -----------------------------
// A popup that has to be started before it can be shown answers its first
// keystroke ~400 ms late, every time, because a Quickshell start is a QML
// compile. One resident process with three Loaders answers immediately, and
// an unopened popup is an inactive Loader — no windows, no processes, nothing
// polling.
ShellRoot {
    id: root

    // Constructed on first ACCESS, so the palette is touched here rather than
    // by the first paint binding — otherwise a popup opens in fallback
    // DoomOne for one frame and then repaints. IslandTheme's own header
    // records the trap.
    Component.onCompleted: {
        IslandTheme.themeName;
        PopupMetrics.scale;
    }

    property string open: ""

    // ---- ONE AT A TIME ----
    //
    // Not a stack. Each of these takes an EXCLUSIVE keyboard grab, and two
    // exclusive grabs is a race the compositor resolves by picking one — so
    // the second popup would be on screen with its keys going to the first.
    // Opening one closes the other, which is also what qtile's chords do:
    // entering a chord leaves the one you were in.
    function show(which) {
        root.open = which;
    }
    function hide() {
        root.open = "";
    }
    function toggle(which) {
        root.open = (root.open === which) ? "" : which;
    }

    IpcHandler {
        target: "popups"

        function wallpaper(): void { root.toggle("wallpaper"); }
        function network(): void   { root.toggle("network"); }
        function volume(): void    { root.toggle("volume"); }
        function wifiqr(): void    { root.toggle("wifiqr"); }
        function display(): void   { root.toggle("display"); }
        // The cheatsheet takes WHICH sheet, so it is a show-with-argument
        // rather than a toggle: pressing `v` while the vim sheet is up should
        // keep it up, not close it.
        function cheatsheet(which: string): void {
            root.cheatsheetWhich = (which === "" ? "hypr" : which);
            root.show("cheatsheet");
        }
        function bluetooth(): void  { root.toggle("bluetooth"); }

        // Explicit show/hide beside the toggles, because a toggle driven from
        // a script goes out of phase the first time a click and a key
        // disagree — NEXT-SESSION.md's RULES say to prefer these when
        // scripting, and a test cannot do it without them.
        function showWallpaper(): void { root.show("wallpaper"); }
        function showNetwork(): void   { root.show("network"); }
        function showVolume(): void    { root.show("volume"); }
        function showWifiQr(): void    { root.show("wifiqr"); }
        function showDisplay(): void   { root.show("display"); }
        function showBluetooth(): void  { root.show("bluetooth"); }
        function close(): void         { root.hide(); }
        function status(): string      { return root.open === "" ? "none" : root.open; }
    }

    // ---------------------------------------------------------------
    //  THE THEME SWEEP, WHICH IS NOT A POPUP
    // ---------------------------------------------------------------
    //
    // Reported: "when I change the theme and wallpaper I want the same
    // animation of the island". There was none, and the reason is where the
    // overlay lives rather than anything about theme-apply: shell.qml owns the
    // ThemeTransitionWindows, and bar-switch stops the island to start the
    // topbar. Under that bar a theme change was theme-apply repainting the
    // desktop in stages, with nothing in front of it.
    //
    // Same arrangement as the TreeTab sidebar and for the same reason — it is
    // a SESSION surface, not a bar widget, and it belongs to whichever shell
    // is resident. This one is, so it hosts it.
    //
    // The overlay RUNS theme-apply itself, behind a frozen screenshot; that is
    // the whole trick and it is why the trigger cannot be "watch for the theme
    // changing". Freezing has to happen first. AtiScriptsV1/theme-animate is
    // the one place that decides which shell to hand a theme change to.
    //
    // NOT Wayland only, any more. This process is now ALSO started under
    // qtile wearing its own bar (see qtile/autostart.sh 2c) specifically so
    // `tide applyThemeAnimated` has somewhere to land there too — the one
    // remaining case theme-animate's own header used to describe as "no
    // shell running, unanimated". That made this block's old comment (kept
    // below in spirit, corrected in fact) wrong the moment it was true: a
    // Variants of bare `ThemeTransitionWindowWayland` declares
    // `WlrLayershell.*`, an attached property that does not exist off
    // Wayland and that fails the WHOLE component when it cannot be created
    // — exactly the trap `shell.qml`'s own `onWayland` comment documents.
    // Under qtile/X11 every instance silently failed to construct, so
    // `themeWindows` was always `[]` and `startThemeTransition` returned on
    // its own `windows.length === 0` guard with no log line at all — which
    // is why a wallpaper pick in wal mode changed the palette with no sweep
    // and no error either. Same split shell.qml already uses, so both
    // resident shells agree on which wrapper to build.
    readonly property bool onWayland: {
        const wl = Quickshell.env("WAYLAND_DISPLAY");
        return wl !== undefined && wl !== null && String(wl) !== "";
    }

    Variants {
        id: themeTransitionVariantsWayland

        model: root.onWayland ? Quickshell.screens : []

        ThemeTransitionWindowWayland {
            required property var modelData

            screen: modelData
            outputName: modelData && modelData.name !== undefined
                ? String(modelData.name) : ""
            // Absolute, not a bare "theme-apply": Quickshell is started by the
            // compositor, so its PATH is the session's and AtiScriptsV1 is not
            // on it. shell.qml's copy of this line carries the same note.
            themeApplyPath: Quickshell.env("HOME")
                + "/.dotfiles/.config/AtiScriptsV1/theme-apply"
            // Only the first screen's overlay runs theme-apply, and the others
            // wait on its `themeApplied` — without the relay each would sit on
            // a frozen screenshot until its own 12 s cap fired.
            ownsThemeApply: Quickshell.screens.length === 0
                || modelData === Quickshell.screens[0]

            onThemeApplied: root.relayThemeApplied()
        }
    }

    Variants {
        id: themeTransitionVariantsX11

        model: root.onWayland ? [] : Quickshell.screens

        ThemeTransitionWindowX11 {
            required property var modelData

            screen: modelData
            outputName: modelData && modelData.name !== undefined
                ? String(modelData.name) : ""
            themeApplyPath: Quickshell.env("HOME")
                + "/.dotfiles/.config/AtiScriptsV1/theme-apply"
            ownsThemeApply: Quickshell.screens.length === 0
                || modelData === Quickshell.screens[0]

            onThemeApplied: root.relayThemeApplied()
        }
    }

    readonly property var themeWindows: root.onWayland
        ? (themeTransitionVariantsWayland.instances || [])
        : (themeTransitionVariantsX11.instances || [])

    function startThemeTransition(themeName) {
        if (!themeName)
            return;
        const windows = root.themeWindows;
        if (windows.length === 0)
            return;
        for (let i = 0; i < windows.length; i++) {
            if (windows[i])
                windows[i].begin(String(themeName));
        }
    }

    function relayThemeApplied() {
        const windows = root.themeWindows;
        for (let i = 0; i < windows.length; i++) {
            if (windows[i])
                windows[i].noteThemeApplied();
        }
    }

    // The same target and the same function NAME the island exposes, so
    // theme-animate can try one and then the other without a second spelling
    // to keep in step. shell.qml's own comment predicted this consumer: the
    // IPC is there "so theme-toggle (the rofi picker, which the qtile session
    // shares) can get the same animation later".
    IpcHandler {
        target: "tide"
        function applyThemeAnimated(theme: string) {
            root.startThemeTransition(theme);
        }
    }

    // ---------------------------------------------------------------
    //  THE PASSTHROUGH CONFIRM, WHICH IS NOT ONE OF THE POPUPS EITHER
    // ---------------------------------------------------------------
    //
    // config.py's _show_pass_confirm: a small centred window asking "Exit
    // passthrough mode?" with Yes and No. The chord and the chip were ported
    // when passthrough was; this is the surface that went with them.
    //
    // DRIVEN BY THE SUBMAP ITSELF, NOT BY AN IPC. Its visibility is exactly
    // "the compositor is in `passthrough-confirm`", so reading that directly
    // means the popup cannot go out of phase with the mode — which is the
    // failure the RULES describe for toggles, arriving here in a new shape.
    // It also means passthrough.sh does not have to know this exists.
    //
    // `submap>>name` with an EMPTY name on reset, so the empty case closes it.
    property string submapName: ""

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (String(event.name) === "submap")
                root.submapName = String(event.data || "").trim();
        }
    }

    Loader {
        active: root.submapName === "passthrough-confirm"
        sourceComponent: Component {
            PassthroughConfirm {
                // The buttons do what the submap's y and n do, because they
                // are the same two answers. Spelt out rather than routed
                // through the script alone: `submap` is a dispatcher and
                // the bar/notification half is the script's.
                onYes: {
                    Quickshell.execDetached([
                        Quickshell.env("HOME")
                            + "/.config/hypr/scripts/passthrough.sh", "exit"]);
                    Quickshell.execDetached(["hyprctl", "dispatch", "submap", "reset"]);
                }
                onNo: Quickshell.execDetached(
                    ["hyprctl", "dispatch", "submap", "passthrough"])
            }
        }
    }

    // ---- THE POPUPS ----
    //
    // Loaders, not `visible: false` windows. A layer-shell surface that
    // exists is a surface the compositor is compositing, and PopupChrome
    // takes an exclusive keyboard grab as soon as it maps — an invisible one
    // holding the keyboard is the worst of both.
    Loader {
        active: root.open === "wallpaper"
        sourceComponent: Component {
            WallpaperPopup {
                onRequestClose: root.hide()
            }
        }
    }

    Loader {
        active: root.open === "network"
        sourceComponent: Component {
            NetworkPopup {
                onRequestClose: root.hide()
            }
        }
    }

    Loader {
        active: root.open === "volume"
        sourceComponent: Component {
            VolumePopup {
                onRequestClose: root.hide()
            }
        }
    }

    Loader {
        active: root.open === "wifiqr"
        sourceComponent: Component {
            WifiQrPopup {
                onRequestClose: root.hide()
            }
        }
    }

    property string cheatsheetWhich: "hypr"

    Loader {
        active: root.open === "cheatsheet"
        sourceComponent: Component {
            CheatsheetPopup {
                which: root.cheatsheetWhich
                onRequestClose: root.hide()
            }
        }
    }

    Loader {
        active: root.open === "display"
        sourceComponent: Component {
            DisplayPopup {
                onRequestClose: root.hide()
            }
        }
    }

    Loader {
        active: root.open === "bluetooth"
        sourceComponent: Component {
            BluetoothPopup {
                onRequestClose: root.hide()
            }
        }
    }

    // ---------------------------------------------------------------
    //  THE DROP SHELF, WHICH IS NOT ONE OF THE POPUPS
    // ---------------------------------------------------------------
    //
    // Deliberately NOT in root.open's one-at-a-time set, and the reason is
    // the same reason it takes OnDemand keyboard focus rather than Exclusive:
    // the shelf is a thing you drag ONTO. The exclusivity above exists
    // because two exclusive keyboard grabs is a race the compositor resolves
    // by picking one — the shelf takes no such grab, so it has nothing to
    // race with, and closing the wallpaper picker because you opened the
    // shelf would be a rule applied for a reason that does not hold here.
    //
    // A SESSION surface, hosted here for exactly the reason the TreeTab
    // sidebar and the theme overlay are: shell.qml owns it while the island
    // is the bar, and bar-switch stops the island to start the topbar. Same
    // IPC target and the same function names on both sides, so
    // hypr/scripts/qdrop.sh can try one and then the other without a second
    // spelling to keep in step.
    property bool qdropOpen: false
    property bool qdropForDrag: false

    IpcHandler {
        target: "qdrop"

        // `open`/`close` and NOT `show`/`hide`, which is not a taste call:
        // `qs ipc show` IS A SUBCOMMAND, so `qs ipc call qdrop show` is eaten
        // by the CLI, prints the handler's function list, and EXITS 0. That
        // is the RULES' "prints Function not found and still exits 0" trap
        // wearing a different hat, and it is why a caller could not tell the
        // difference. Measured: `hide` worked, `show` never arrived.
        // popups.qml already dodges this by spelling its explicit openers
        // showWallpaper/showNetwork rather than show.
        function open(): void   { root.qdropForDrag = false; root.qdropOpen = true; }
        // See shell.qml's copy: a shelf opened mid-drag must not grab the
        // keyboard, because the grab cancels the drag.
        function openForDrag(): void { root.qdropForDrag = true; root.qdropOpen = true; }
        function close(): void  { root.qdropOpen = false; }
        function toggle(): void { root.qdropOpen = !root.qdropOpen; }
        function status(): string { return root.qdropOpen ? "open" : "closed"; }
    }

    Loader {
        active: root.qdropOpen
        sourceComponent: Component {
            QdropShelf {
                forDrag: root.qdropForDrag
                onRequestClose: root.qdropOpen = false
                onDropLanded: root.qdropForDrag = false
            }
        }
    }
}
