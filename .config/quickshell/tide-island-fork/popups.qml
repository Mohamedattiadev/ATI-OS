import QtQuick
import Quickshell
import Quickshell.Io

import "qml/common"
import "qml/popups"
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
        function calculator(): void { root.toggle("calculator"); }
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
        function showCalculator(): void { root.show("calculator"); }
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
    // Wayland only. popups.qml is started by hypr/scripts/topbar.sh, which is
    // the Hyprland session's; under qtile the island is the shell that is up
    // and it has its own overlay, in both backends. There is no third case
    // today — qtile with its OWN bar has no Quickshell running at all, which
    // is the one combination that still gets an unanimated theme change, and
    // theme-animate says so when it falls through.
    Variants {
        id: themeTransitionVariants

        model: Quickshell.screens

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

    readonly property var themeWindows: themeTransitionVariants.instances

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

    Loader {
        active: root.open === "display"
        sourceComponent: Component {
            DisplayPopup {
                onRequestClose: root.hide()
            }
        }
    }

    Loader {
        active: root.open === "calculator"
        sourceComponent: Component {
            CalculatorPopup {
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
}
