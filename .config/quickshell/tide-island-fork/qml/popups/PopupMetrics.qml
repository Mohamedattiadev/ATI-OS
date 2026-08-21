pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

//
// FORK — new file. The scale and the type scale for the qtile-style popups.
//
// WHY NOT Metrics.js, WHICH THIS SHELL ALREADY HAS
// ------------------------------------------------
// Two different scales that both look like "the UI scale". Metrics.js's
// SCALE is 0.92 and is defined as islandHeight / DESIGN_HEIGHT — the ratio
// between this desktop's 28 px island and the 38 px notch the vendored
// upstream QML was drawn against. It is a correction for one specific set of
// hardcoded numbers, and its own header says so.
//
// These popups are not island surfaces. They are reimplementations of
// popups/*.py, whose every dimension goes through popups/_scale.py — which
// reads ~/.cache/qtile/ui_scale, the per-machine DPI factor AtiScriptsV1's
// ati-ui-scale writes. Sizing them by 0.92 would be applying the island's
// correction to numbers that were never drawn against the island.
//
// So this reads the same file config.py's `_s()` reads, applies the same
// 0.5-4.0 clamp for the same reason, and the topbar's own Metrics.qml does
// the identical thing for the identical reason. Three readers, one file, no
// second opinion about how big this desktop is.
Singleton {
    id: root

    property real scale: 1.0

    function s(px) {
        return Math.max(1, Math.round(px * root.scale));
    }

    // popups/WallpaperPopup.py's FONT. Monospace and NOT the bar's Ubuntu:
    // "the padded rows only line up in a fixed-width face", and the rows in
    // all three of these popups are padded columns.
    readonly property string font: "JetBrainsMono Nerd Font"

    // ROW_SIZE / HEAD_SIZE / HINT_SIZE / FOOT_SIZE, and they are PIXELS —
    // that file says so in as many words: "qtile builds these layouts with a
    // *pixel* font size, so these are px, not points".
    readonly property int rowSize: root.s(14)
    readonly property int headSize: root.s(14)
    readonly property int hintSize: root.s(13)
    readonly property int footSize: root.s(14)

    FileView {
        path: Quickshell.env("HOME") + "/.cache/qtile/ui_scale"
        watchChanges: true
        preload: true
        // Absent on any machine where the wizard's scale module has never
        // run, which is the common case and means 1.0.
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            const v = parseFloat(text());
            if (isFinite(v) && v >= 0.5 && v <= 4.0)
                root.scale = v;
        }
    }
}
