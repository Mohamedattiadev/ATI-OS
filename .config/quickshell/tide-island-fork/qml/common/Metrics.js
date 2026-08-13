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

// ---------------------------------------------------------------------
//  THE RAMP AND THE SCALE — measured before being named
// ---------------------------------------------------------------------
//
// upgread_UI_UX.md P1-5 calls the type and radius numbers "inventories, not
// systems" and sets a target of 11 -> 6 sizes and 16 -> 4 radii. Counted
// across the tree before touching anything, the premise is mostly already
// false, and the real state is worth writing down because it changes what
// the remaining work IS:
//
//     font sizes   151 uses, 10 distinct     143 already go through font()
//     radii         64 uses, 18 distinct      55 already go through px()
//
// So the funnel exists. What is missing is NAMES for the steps, not a
// funnel — and the distribution says the steps are already there: 145 of
// the 151 type uses fall in 9..15, i.e. six values, with the remaining six
// uses being 18/19/24/29, which are display sizes and legitimately not on
// the body ramp.
//
// TWO THINGS THAT LOOK LIKE BUGS AND ARE NOT
// ------------------------------------------
// The 8 raw `font.pixelSize: N` literals are ALL in DisplayPanel.qml, which
// does not import Metrics at all and says so in a comment: it sizes
// everything with literals and mixing one scaled dimension into an unscaled
// panel would put that element out of step with the header around it. That
// is internally consistent rather than a miss. Captured beside AudioPanel,
// which uses Metrics 35 times, the two panels are indistinguishable in type
// size — which brings us to the reason why:
//
// **FONT_SCALE IS 1.0, SO font(n) IS THE IDENTITY ABOVE 9.** Every
// `Metrics.font(11)` in this tree evaluates to exactly 11, the same number
// DisplayPanel writes directly. The type "system" therefore has no
// mechanical effect at all today; it is a naming convention and a single
// place to change later, which is worth having and is not worth pretending
// is more than it is.
//
// The remaining raw radii are `0` and `1`. px(0) returns 0 and px(1) is
// floored at 1, so routing them through px() would be churn that provably
// cannot change a pixel.
//
// WHAT THESE CONSTANTS ARE FOR
// ----------------------------
// New code, and one place to look when deciding a size. They are NOT
// applied retroactively over 198 call sites: that would be a large diff
// whose only verification is "every panel still looks right", which is the
// class of change this repo has twice been burned by. The steps below are
// the values already in use, named — so adopting one is a no-op by
// construction and any future change to the ramp is one edit here.
//
var TYPE = {
    caption:  9,   // 12 uses — key hints, footnotes
    small:   10,   // 42 uses — secondary labels, list subtitles
    body:    11,   // 47 uses — the workhorse
    reading: 12,   // 19 uses — body where the line is long enough to matter
    strong:  13,   // 13 uses — emphasised body
    title:   15    // 12 uses — panel headings
};

// Display sizes, off the body ramp on purpose: 18/19/24/29 in the tree, all
// of them single-purpose (the timer, the OSD numeral, the clock at size).
var DISPLAY = { small: 18, medium: 24, large: 29 };

// Radius. Four steps against 18 values in use.
//
// ---- THE LADDER IS ALREADY CONCENTRIC, AND THAT WAS NOT PLANNED ----
//
// The note that used to sit here said a radius change "cannot be a
// find-and-replace" because nested shapes need concentric radii — outer =
// inner + padding — and there was no measurement saying which of the 18
// values were deliberate. The measurement is now here, and it is a happier
// answer than expected. Against the padding this shell actually uses:
//
//     panel shell   px(28)  = 26      the capsule every panel draws
//     minus padX    pad(18) = 18
//     ------------------------------
//     inner card              8       == RADIUS.card, exactly
//     minus a chip's pad(4) = 4
//     ------------------------------
//     chip                    4       == RADIUS.tight, exactly
//
// So `card` and `tight` are not a proposal laid over the tree — they are
// what concentricity DERIVES from the horizontal padding that nine panels
// already agreed on. A row drawn at 8 inside a panel drawn at 26 with 18 px
// of padding has a curve parallel to the shell around it, and that is the
// whole of what "concentric" buys.
//
// `panel` at 16 is NOT the outer capsule. The capsule is px(28) and is the
// island's own shape — settled, and not this table's business. 16 is for
// large surfaces INSIDE a panel: a drawer, a tab body, a hero card.
var RADIUS = {
    hairline: 1,   // dividers and 1 px rules
    tight:    4,   // chips, small controls    = card - pad(4)
    card:     8,   // list rows, cards         = px(28) - pad(18)
    panel:   16    // large surfaces inside a panel, not the capsule
};

// ---------------------------------------------------------------------
//  CHROME — the numbers nine panels each picked separately
// ---------------------------------------------------------------------
//
// Counted before choosing: the key-hint footer exists on 9 panels under TWO
// property names (`hintHeight` on 5, `footerHeight` on 4) at FOUR heights
// (pad(26), px(22), px(20), and a raw 24). The header is `pad(34)` on six
// panels, `pad(36)` on two, `pad(38)` on one and a raw 34 on DisplayPanel.
// The horizontal padding is `pad(18)` on nine and a raw 18 on DisplayPanel.
//
// None of that spread is a decision anyone made. It is nine files each
// answering the same question once, which is exactly what extracting
// PanelChrome exists to stop happening a tenth time.
//
// The values below are the MAJORITY of what is already there, not new
// numbers — pad(18), pad(34), pad(26) each won their own vote. So the panels
// that already agreed do not move at all, and the outliers converge onto
// what most of the shell was already drawing.
//
// Functions rather than a table of pre-scaled numbers, because SCALE is a
// literal in this file and a table would freeze at whatever it was when the
// file was parsed. These are cheap and called at binding time.
//
function chromePadX()    { return pad(18); }   // 18 — the content inset
function chromeHeader()  { return pad(34); }   // 33 — title baseline to body
function chromeFooter()  { return pad(26); }   // 25 — the key-hint strip
function chromeGap()     { return pad(8);  }   //  8 — body to footer
function chromeTop()     { return pad(12); }   // 12 — title's own baseline
