import QtQuick
import Quickshell
import Quickshell.Io

//
// FORK — new file. The island's colours, read live from the palette
// AtiScriptsV1/theme-apply generates for every theme.
//
// THIS REVERSES DESIGN-SPEC.md, ON PURPOSE
// ----------------------------------------
// The spec is emphatic that the notch shape stays hardcoded #000000 and is
// never tinted, because it is imitating bezel: "tint it and it stops being
// a notch and becomes a colored blob". REQUIREMENTS.md item 1 recorded that
// as a conflict to decide, and the user has decided the other way — the
// island background follows the colour theme. Both documents now say so;
// this comment exists so that nobody reads the spec alone and "fixes" it
// back.
//
// It is a compromise rather than a plain override: the fill is the theme's
// background slot, which in every one of the 22 palettes is a very dark
// near-black (doomone #282c34, nord #2e3440, gruvbox #282828). Blended
// most of the way toward black it reads as a tinted bezel rather than as a
// coloured blob, so the spec's actual concern is answered even though its
// rule is not followed.
//
// WHERE THE COLOURS COME FROM
// ---------------------------
// theme-apply's gen_island_colors(), one of the seven targets in
// gen_all_theme_css(), writing ~/.cache/tide-island/colors.json. This file
// owns no palette of its own — a second copy of 22 palettes would drift the
// first time a shade was adjusted, silently, because a wrong colour still
// renders. That is exactly the bug that made every window border green in
// all 20+ themes.
//
// It is WATCHED rather than read once, so `theme-apply gruvbox` from a
// terminal repaints the island without restarting the shell, and so the
// still-running qtile session and this one cannot disagree.
//
// An invisible Item, not a QtObject, and that is load-bearing. FileView
// needs to sit in the object tree as an ordinary child to start watching;
// declared as the value of a property on a bare QtObject it constructs
// happily, reports no error, and never fires onLoaded or onFileChanged —
// so the island silently keeps its fallback palette and looks exactly like
// "the theme is not wired up". This is the same shape
// WallpaperThumbnailCache.qml uses, which is the proven one in this tree.
Item {
    id: root

    visible: false
    width: 0
    height: 0

    // Fallbacks are the doomone palette, not neutral greys. If the file is
    // missing — a fresh machine where theme-apply has not run yet — the
    // island should look like the desktop's default theme rather than like
    // a bug.
    property string themeName: ""
    property color background: "#282c34"
    property color backgroundAlt: "#1e222a"
    property color foreground: "#dcdfe4"
    property color accent: "#51afef"

    // How far toward black the background slot is dragged before it becomes
    // the shell's fill.
    //
    // 0 would be the raw palette background, which at ~38% luminance is a
    // grey slab with a hint of colour and reads exactly as the "coloured
    // blob" the spec warns about. 1 is pure black and ignores the theme
    // entirely.
    //
    // 0.35 was arrived at by sampling the framebuffer while cycling, not
    // from theory. 0.72 was tried first and is where this landed
    // originally; it is technically correct and useless — every palette's
    // background slot is ALREADY near-black, so darkening it by three
    // quarters put doomone at #0b0c0f and gruvbox at #0b0b0b, four points
    // apart on one channel. The theme was being followed and no human eye
    // could tell. 0.35 keeps the shape unmistakably dark while leaving the
    // hue readable: doomone #1a1d22 (cool), gruvbox #1a1a1a (neutral),
    // nord #1e2129 (blue).
    readonly property real darkenTowardBlack: 0.35

    readonly property color shellFill: Qt.rgba(
        root.background.r * (1 - root.darkenTowardBlack),
        root.background.g * (1 - root.darkenTowardBlack),
        root.background.b * (1 - root.darkenTowardBlack),
        1)

    function applyJson(text) {
        try {
            const parsed = JSON.parse(text);
            if (!parsed || !parsed.bg)
                return;
            root.themeName = String(parsed.theme || "");
            root.background = String(parsed.bg);
            root.backgroundAlt = String(parsed.bgAlt || parsed.bg);
            root.foreground = String(parsed.fg || "#ffffff");
            root.accent = String(parsed.accent || parsed.blue || "#51afef");
        } catch (error) {
            // Keep whatever is already loaded. A half-written or corrupt
            // palette must not repaint the shell into something unreadable
            // — theme-apply renames the file into place atomically so this
            // should be unreachable, and it is here because "should be" is
            // not a guarantee about a file another process writes.
        }
    }

    FileView {
        path: Quickshell.env("HOME") + "/.cache/tide-island/colors.json"
        watchChanges: true
        // Preloaded: the very first frame the island draws must already
        // carry the theme, or the shell flashes doomone-black and then
        // repaints, which is more noticeable than a slow start.
        preload: true
        printErrors: false

        onLoaded: root.applyJson(text())
        onFileChanged: {
            reload();
            root.applyJson(text());
        }
    }
}
