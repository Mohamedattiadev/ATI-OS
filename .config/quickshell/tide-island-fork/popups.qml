import QtQuick
import Quickshell
import Quickshell.Io

import "qml/common"
import "qml/popups"

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
// Three of the topbar's chips are qtile chips whose action is a POPUP rather
// than a command:
//
//     ✖  wallpaper_toggle  ->  toggle_wallpaper_picker  (WallpaperPopup.py)
//     network                  Wifi-Mode                (WifiPopup.py)
//     volume                   Audio-Mode               (AudioPopup.py)
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

        // Explicit show/hide beside the toggles, because a toggle driven from
        // a script goes out of phase the first time a click and a key
        // disagree — NEXT-SESSION.md's RULES say to prefer these when
        // scripting, and a test cannot do it without them.
        function showWallpaper(): void { root.show("wallpaper"); }
        function showNetwork(): void   { root.show("network"); }
        function showVolume(): void    { root.show("volume"); }
        function close(): void         { root.hide(); }
        function status(): string      { return root.open === "" ? "none" : root.open; }
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
}
