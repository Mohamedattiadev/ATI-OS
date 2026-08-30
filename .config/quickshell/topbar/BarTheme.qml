pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

//
// The topbar palette — qtile's `colors[N]`, by name.
//
// ONE SOURCE, NOT A SECOND COPY
// -----------------------------
// This reads the SAME file the island's IslandTheme reads:
// ~/.cache/tide-island/colors.json, written by AtiScriptsV1/theme/theme-apply's
// gen_island_colors(). It deliberately does not carry a palette of its own
// and does not re-read pywal, because a second copy of 22 palettes drifts the
// first time a shade is adjusted — silently, because a wrong colour still
// renders. That exact bug is what made every window border green in all 20+
// themes, and IslandTheme's header records it.
//
// Consequence, and it is the point: `theme-apply gruvbox` retints the island,
// this bar, and the qtile bar from one write. Watched rather than read once,
// so it happens without restarting anything.
//
// THE INDEX MAP
// -------------
// qtile/colors.py is a list of nine [hex, hex] pairs and config.py addresses
// them positionally. Read off DoomOne, which is the list every other palette
// in that file is shaped after:
//
//     colors[0] bg        colors[3] red      colors[6] blue
//     colors[1] fg        colors[4] green    colors[7] purple
//     colors[2] color01   colors[5] yellow   colors[8] cyan
//
// The names below are those, so a widget ported from config.py can keep
// saying what it said. `colors[2]` maps to bgAlt rather than to a literal:
// it is `#000000` on every dark theme in that file, and the topbar has no
// use for a slot that is black everywhere.
Singleton {
    id: root

    property string themeName: ""

    // Fallbacks are DoomOne's, matching qtile/colors.py's first entry, so a
    // missing or unreadable palette gives the theme this desktop started on
    // rather than an arbitrary one.
    property color bg: "#282c34"          // colors[0]
    property color fg: "#bbc2cf"          // colors[1]
    property color bgAlt: "#1c1f24"       // colors[2]
    property color red: "#ff6c6b"         // colors[3]
    property color green: "#98be65"       // colors[4]
    property color yellow: "#da8548"      // colors[5]
    property color blue: "#51afef"        // colors[6]
    property color purple: "#c678dd"      // colors[7]
    property color cyan: "#46d9ff"        // colors[8]
    property color accent: "#51afef"

    // ---- THE CHIP PLATE ----
    //
    // config.py's _chip_plate(), reproduced including its two factors and the
    // reason they differ. It used to be a literal from the static doom-one
    // palette, so it stayed the same on all 22 themes: invisible on the dark
    // ones and plainly wrong on mono-light, where near-black chips sat on a
    // white desktop.
    //
    // Derived from the BACKGROUND rather than pointed at colors[2], because
    // colors[2] is #000000 on every dark theme here — correct in that it
    // tracks, but it would turn every chip pure black and change how the bar
    // looks on the themes actually in use.
    //
    // 30% off a dark background lands gruvbox on #1c1c1c, indistinguishable
    // from the #1c1f24 it replaces; the same 30% on white would give
    // mid-grey, so a light background is darkened by only 12% instead, which
    // lands mono-light on #e0e0e0 — exactly what that theme's own alt slot
    // holds. The derivation agrees with the palette where the palette has an
    // opinion.
    readonly property color plate: {
        const c = root.bg;
        const light = (0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b) > 0.5;
        const f = light ? 0.88 : 0.70;
        return Qt.rgba(c.r * f, c.g * f, c.b * f, 1);
    }

    function alpha(c, a) {
        return Qt.rgba(c.r, c.g, c.b, a);
    }

    FileView {
        path: Quickshell.env("HOME") + "/.cache/tide-island/colors.json"
        watchChanges: true
        // Preloaded so the first frame already carries the theme. A bar that
        // paints doomone-black and then repaints is more noticeable than one
        // that starts a beat later.
        preload: true
        printErrors: false

        onFileChanged: reload()
        onLoaded: root.applyPalette(text())
    }

    function applyPalette(raw) {
        try {
            const p = JSON.parse(raw);
            root.themeName = String(p.theme || "");
            root.bg = String(p.bg);
            root.bgAlt = String(p.bgAlt || p.bg);
            root.fg = String(p.fg || "#bbc2cf");
            root.red = String(p.red || "#ff6c6b");
            root.green = String(p.green || "#98be65");
            root.yellow = String(p.yellow || "#da8548");
            root.blue = String(p.blue || "#51afef");
            root.purple = String(p.purple || "#c678dd");
            root.cyan = String(p.cyan || "#46d9ff");
            root.accent = String(p.accent || p.blue || "#51afef");
        } catch (error) {
            // Keep whatever is already loaded. theme-apply truncates and
            // rewrites this file IN PLACE rather than renaming it into place —
            // deliberately, because FileView is a QFileSystemWatcher and an
            // atomic mv replaces the inode, leaving the watch pointed at an
            // unlinked file and onFileChanged never firing again. So a torn
            // read is a real if narrow window, and this is what covers it.
        }
    }
}
