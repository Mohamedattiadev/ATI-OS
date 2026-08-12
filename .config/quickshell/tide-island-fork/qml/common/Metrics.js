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
var NOTCH_SCALE = ISLAND_HEIGHT / DESIGN_HEIGHT;   // 0.7368…

//
// ---- WHY THE PANELS ARE NO LONGER SCALED BY NOTCH_SCALE ----
//
// The paragraphs above are right about the resting NOTCH and were wrong to
// apply the same number to everything else. Two reports made it obvious —
// "the sizing of the element and font in all the island is not proper" and
// "some elements look eaten, not full" — and they are one bug:
//
//   * px() shrank every container by 0.74, while
//   * font() FLOORED at 9.
//
// Below a source size of about 12, that floor is doing all the work:
// font(10), font(11) and font(12) all returned 9. So the boxes kept
// shrinking, the text inside them stopped, and the text ran out of its
// box — which on screen is a label with its descenders or its last
// characters cut off. Literally eaten. It also flattened the type
// hierarchy: four deliberately different sizes rendered as one.
//
// The deeper mistake is the premise. 28/38 exists because qtile's BAR is
// 28 px tall and the resting notch has to match it. **No expanded panel is
// bound by that.** A theme picker or a cheatsheet hangs below the bar as a
// free-floating surface; the only thing constraining it is the screen. It
// was being shrunk to fit a constraint that does not apply to it.
//
// Verified before changing anything: the resting shape does NOT come from
// here. It is `userConfig.islandWidth` / `islandHeight` in
// DynamicIslandWindow.qml, read straight from userconfig.json. So raising
// the panel scale cannot make the notch grow — the two really are
// separable, which is what makes this safe.
//
// 0.92 rather than 1.0: the vendored upstream numbers were drawn for a
// 2560x1440 screen and this panel is 1366x768, so a little tightening is
// still right. What was wrong was tightening by a quarter.
//
var SCALE = 0.92;

//
// Type gets its own scale, and it is 1.0.
//
// Legibility is an absolute, not a ratio: 11 px of Inter is the same size
// on any panel, and shrinking type to match a shape only ever costs
// readability. The source sizes were already chosen by eye at design size,
// so the honest transform is none at all. The floor below is kept as a
// backstop for anything that asks for something silly, not as a working
// part of the system — if it ever fires again, the fix is the source size.
//
var FONT_SCALE = 1.0;

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
// The 1.35 boost that used to be here is GONE, and its removal is part of
// the same fix. It existed to claw back what the 0.74 shrink took out of
// internal margins — a correction for a scale that is no longer applied.
// Keeping both would double-count: padding would now grow faster than the
// boxes it sits inside, and content would drift away from its own edges
// as surely as it was jammed against them before. 1.06 is a light touch
// on top of the panel scale, because glyph height still does not shrink
// and the space around type is the first thing to feel tight.
function pad(n) {
    return Math.max(1, Math.round(n * SCALE * 1.06));
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
    return Math.max(9, Math.round(n * FONT_SCALE));
}
