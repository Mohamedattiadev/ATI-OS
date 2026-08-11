.pragma library

//
// Metrics.js — ONE scale factor for every surface the island draws.
//
// FORK — new file.
//
// WHY THIS EXISTS
// ---------------
// The island was resized from DESIGN-SPEC.md's 38 px notch to qtile's 28 px
// bar height, on the user's explicit call: qtile's bar was the known-good
// daily driver for years, and the spec's 38 was measured off a stranger's
// 2560x1440 screen. Changing `islandHeight` and the three font sizes in
// userconfig.json did exactly that much and no more — because every OTHER
// dimension in this shell is a literal in QML that the config cannot reach:
// panel widths, tile sizes, grid spacing, thumbnail sizes, album art,
// internal padding, corner radii.
//
// The result of moving only the config was worse than not moving it: the
// theme picker kept its full-size panel and tile boxes and got tiny labels
// inside them, which reads as broken rather than as smaller. A shell only
// looks deliberate when everything in it is scaled by the same number.
//
// So: every structural literal now goes through px(), and the scale lives
// here, once.
//
// THE TWO HALVES OF ONE DECISION
// ------------------------------
// SCALE and `islandHeight` in .config/tide-island/userconfig.json.tmpl are
// not independent. SCALE is defined as islandHeight / DESIGN_HEIGHT, and
// DESIGN_HEIGHT is the 38 px that every hardcoded number in the vendored
// upstream QML was drawn against. Change the island's height and this
// number changes with it or the shell goes back to being half-scaled.
//
// It is a literal rather than read from UserConfig on purpose. A `.pragma
// library` JS file has no QML context and cannot see the config singleton,
// and initialising it from QML at startup would make every layer's layout
// depend on load order — a class of bug that shows up as "the panel is the
// right size on the second open". A literal with the derivation written
// next to it is the honest version.
//
var DESIGN_HEIGHT = 38;
var ISLAND_HEIGHT = 28;
var SCALE = ISLAND_HEIGHT / DESIGN_HEIGHT;   // 0.7368…

//
// px(n) — a structural length, scaled and snapped to whole pixels.
//
// Rounded, not left fractional: these land on Rectangle widths, x positions
// and radii, and a half pixel there is a blurred edge on a shape whose whole
// point is a crisp one. Never returns less than 1 for a positive input, so a
// hairline border does not scale itself out of existence.
//
function px(n) {
    if (n === 0)
        return 0;
    var scaled = Math.round(n * SCALE);
    if (n > 0 && scaled < 1)
        return 1;
    if (n < 0 && scaled > -1)
        return -1;
    return scaled;
}

//
// pad(n) — the same, but for INTERNAL padding, which gets a deliberate boost.
//
// Padding is the one dimension that must not shrink linearly with the shape.
// Scaling a 38 px capsule's margins by 0.74 alongside its height keeps the
// ratio and keeps the cramped look, and "the padding should be better, more"
// was the actual complaint — the shape got smaller and the content stayed
// jammed against its edges. Content is bounded below by glyph height, which
// does not scale at all past a point, so the space around it has to be given
// back explicitly. 1.35 recovers the linear loss and adds roughly a third on
// top, which is what reads as breathing room at this size.
//
function pad(n) {
    return Math.max(1, Math.round(n * SCALE * 1.35));
}

//
// font(n) — a type size.
//
// Floored at 9: below that Inter stops being legible on a 1366x768 panel
// regardless of what the ratio says, and an unreadable label is not a
// smaller label. Sizes that hit the floor are the ones to raise in the
// source rather than to fix here.
//
function font(n) {
    return Math.max(9, Math.round(n * SCALE));
}
