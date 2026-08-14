pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

//
// FORK — the shell's ONE colour system. Read live from the palette
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
//
// ================= WHY THIS FILE GREW =================
//
// It used to publish four colours and `shellFill`, bound at 18 sites.
// upgread_UI_UX.md P0-2 counted what that left behind: 291 raw hex
// literals across 33 of the 61 files, plus 121 uses of `StyleTokens`.
// Three parallel colour systems, and the only one `theme-apply` could
// reach was the smallest.
//
// `StyleTokens` cannot be fixed in place and that is not a matter of
// effort. All 55 of its properties are `isReadonly: true` AND
// `isPropertyConstant: true` in IslandBackend.qmltypes — C++ constants in
// a package binary. No amount of QML makes `StyleTokens.accent` follow
// gruvbox.
//
// (upgread_UI_UX.md says its values "could not be extracted". They can:
// `quickshell -p` on a four-line config that imports IslandBackend and
// logs each property prints all 55. The earlier attempt used a bare
// `qml6` harness, which produces no console output in this environment —
// the tool was the obstacle, not the binary. Every value below that says
// "was #xxxxxx" was read that way, so the derived roles start from the
// appearance they are replacing rather than from taste.)
//
// So the roles below are DERIVED from the ten palette slots rather than
// listed. Deriving and not listing is the whole point: a list would need
// `gen_island_colors()` to grow twenty new arguments, and would need every
// one of them re-picked, by hand, for all 22 palettes.
//
//
// ================= LEGIBILITY IS COMPUTED, NOT ASSUMED =================
//
// The obvious derivation — textPrimary = the palette's `fg` — is wrong,
// and `mono-light` is the proof. Its palette is bg #ffffff, fg #000000.
// `shellFill` darkens the background toward black, so on every OTHER
// theme the surface ends up at 0.4–2.2% luminance and any light `fg`
// reads. On mono-light the same arithmetic lands at #81818b — 22%
// luminance, a mid grey — and #000000 text on it is the one case a
// hardcoded "text is light" rule renders unreadable.
//
// This is exactly the class of failure this codebase keeps producing: a
// wrong colour still renders, so nothing reports it. So text is not
// picked, it is SOLVED — `_toContrast` walks the palette colour toward
// whichever extreme the surface is not until WCAG contrast clears the
// target. MEASURED over all 21 named palettes before being written here:
// textPrimary lands between 5.45:1 (mono-light) and 16.13:1 (oxocarbon),
// and mono-light is the only theme where the ink flips to black.
//
// The lower roles are then mixed from textPrimary TOWARD the surface, so
// they cannot outrun it: secondary ≥ 3.75:1, muted ≥ 2.76:1, disabled
// ≥ 2.08:1 across the same 21. Disabled is meant to be hard to read; it
// is not meant to be invisible, and now it cannot become invisible on a
// palette nobody tested.
//
//
// ================= WHAT STAYS HARDCODED =================
//
// Four exceptions, and they are exceptions because the colour carries
// information that the theme must not be allowed to overwrite:
//
//   1. The Wi-Fi QR card — black on white, always. A themed QR is a QR
//      that phones refuse to decode.
//   2. The battery bar's success/warning/danger. There the colour IS the
//      reading; a gruvbox-yellow "danger" is a lie.
//   3. The theme picker's 22 tiles, each painted in the palette it
//      applies. Painting them in the CURRENT theme would make the picker
//      a list of 22 identical swatches.
//   4. The theme-transition overlay, which by definition renders while
//      two palettes are live at once.
//
// Anything else that cannot be said as a role here is a MISSING ROLE and
// belongs in this file — not a licence to keep the hex.
//
//
// ================= WHY A SINGLETON =================
//
// It was an `Item`, instantiated twice (DynamicIslandWindow and shell.qml
// for the ring OSD), with its colours threaded down to panels as explicit
// `panelFill` / `accentColor` properties. That is workable for four
// tokens and absurd for forty across 45 files — every panel would grow a
// property per role and every call site would have to pass it.
//
// The old comment warned that this had to be an Item because a `FileView`
// declared on a bare `QtObject` constructs happily, reports no error, and
// never fires. That warning is still true and it does NOT apply here:
// Quickshell's `Singleton` has `defaultProperty: "children"` and derives
// from `ReloadPropagator`, so a FileView is an ordinary child in the
// object tree, which is the condition that was actually load-bearing.
// Verified rather than reasoned: a probe singleton watching a copy of
// colors.json reported the fallback, then the file's real contents, then
// picked up an out-of-band rewrite — i.e. `onLoaded` and `onFileChanged`
// both fire.
//
// One consequence, and shell.qml carries the fix: a QML singleton is
// constructed on FIRST ACCESS, so if the first access is a paint binding
// the shell draws one frame in the fallback palette. `blockLoading` does
// not help — measured, it still misses the first read. shell.qml touches
// this object in `Component.onCompleted`, which moves construction ahead
// of every window, and that was measured too: the same probe went from
// "fallback, then correct" to correct on the first read.
//
Singleton {
    id: root

    // ---------------------------------------------------------------
    //  The palette, exactly as theme-apply emits it
    // ---------------------------------------------------------------
    //
    // Fallbacks are the doomone palette, not neutral greys. If the file is
    // missing — a fresh machine where theme-apply has not run yet — the
    // island should look like the desktop's default theme rather than like
    // a bug. Every role below is derived, so these ten values are the only
    // thing a fresh machine needs to look finished.
    property string themeName: ""
    property color background: "#282c34"
    property color backgroundAlt: "#1e222a"
    property color foreground: "#dcdfe4"
    property color red: "#ff6c6b"
    property color green: "#98be65"
    property color yellow: "#ecbe7b"
    property color blue: "#51afef"
    property color purple: "#c678dd"
    property color cyan: "#46d9ff"
    property color accent: "#51afef"

    // ---------------------------------------------------------------
    //  Colour maths
    // ---------------------------------------------------------------

    // Coerce whatever was passed into a real colour before reading .r/.g/.b
    // off it. This is not defensive tidying, it is a bug fix: a STRING
    // reaches these functions whenever a caller writes `mix(surface,
    // "#000000", 0.55)`, and `"#000000".r` is `undefined`, so every channel
    // becomes NaN and `Qt.rgba(NaN, NaN, NaN, NaN)` is TRANSPARENT BLACK.
    // No error, no warning — the surface simply is not painted.
    //
    // Six roles shipped broken that way and the palette-cycling probe is
    // what found them: surfaceSunken, inputFill (which reads it),
    // surfaceScrim, accentPressed, overviewCard and both overview overlays
    // all resolved to #00000000 on every one of the five themes tested.
    // `Qt.darker(x, 1.0)` is the coercion because it takes a string or a
    // colour and returns the same colour either way.
    function toColor(v) {
        return Qt.darker(v, 1.0);
    }

    function mix(a, b, t) {
        const ca = root.toColor(a);
        const cb = root.toColor(b);
        return Qt.rgba(ca.r + (cb.r - ca.r) * t,
                       ca.g + (cb.g - ca.g) * t,
                       ca.b + (cb.b - ca.b) * t,
                       ca.a + (cb.a - ca.a) * t);
    }

    function alpha(c, a) {
        const cc = root.toColor(c);
        return Qt.rgba(cc.r, cc.g, cc.b, a);
    }

    // WCAG relative luminance. The gamma expansion is not decoration: a
    // naive 0.2126r+0.7152g+0.0722b on sRGB values puts mono-light's
    // #81818b fill at 51% and every dark theme at 8–13%, which ranks them
    // correctly and sizes them wrongly — and the contrast target is a
    // ratio, so the sizes are what it uses.
    function _lin(v) {
        return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
    }

    function luminance(c) {
        return 0.2126 * root._lin(c.r) + 0.7152 * root._lin(c.g) + 0.0722 * root._lin(c.b);
    }

    function contrast(a, b) {
        const la = root.luminance(a);
        const lb = root.luminance(b);
        return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05);
    }

    // Walk `c` toward `ink` in twentieths until it clears `target` against
    // `bg`. Twenty steps because the answer is a colour on a screen, not a
    // limit — one step is 5% and no palette needed more than a few.
    // Returns the fully-inked colour if even that will not clear the
    // target, which is the best available answer rather than a failure:
    // that only happens on a surface where nothing is legible, and the
    // surface is the bug then.
    function _toContrast(c, bg, ink, target) {
        if (root.contrast(c, bg) >= target)
            return c;
        for (let i = 1; i <= 20; i++) {
            const cand = root.mix(c, ink, i / 20);
            if (root.contrast(cand, bg) >= target)
                return cand;
        }
        return ink;
    }

    // ---------------------------------------------------------------
    //  The surface — unchanged, and the numbers are still the measured ones
    // ---------------------------------------------------------------
    //
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
    // could tell.
    //
    // ---- WHY DARKENING ALONE COULD NEVER WORK ----
    //
    // 0.35 was still the wrong shape of fix, and gruvbox is the proof. Its
    // background slot is #282828: R, G and B are IDENTICAL. Channel spread
    // zero. Scaling all three by any constant leaves them identical, so
    // every value of this knob yields a pure grey — 0.35 gives #1a1a1a and
    // 0.15 just gives a lighter #222222. The island was reported as "always
    // black" on gruvbox and it was, unavoidably, because the slot being
    // followed HAS no hue to follow. Darkening controls how dark it is; it
    // cannot control whether it is coloured at all.
    //
    // So the hue now comes from the ACCENT, which every palette defines as
    // a saturated colour, and the background keeps its job of being dark.
    // MEASURED across four palettes, fill luminance % and channel spread:
    //
    //              0.35 / no mix        0.45 + 8% accent
    //   gruvbox    #1a1a1a  10.2   0    #282318  13.8  16
    //   doomone    #1a1d22  11.3   8    #1b242d  13.6  18
    //   nord       #1e222a  13.2  12    #222a31  16.0  15
    //   dracula    #1a1b23  10.7   9    #23212f  13.5  14
    //
    // Spread goes from 0..12 to 14..18 — every theme, including the neutral
    // one, now has a hue the eye can name. The darken went 0.35 -> 0.45 in
    // the same change and that pairing is the point: mixing in accent LIFTS
    // luminance, so without the extra darkening this landed at 15-18% and
    // stopped reading as bezel. Together they cost ~3 points of luminance.
    //
    // 8% and not more: at 16% gruvbox reaches #3e341d, a brown that reads as
    // a tinted surface rather than a dark one, which is the "coloured blob"
    // DESIGN-SPEC.md warns about arriving by a different road.
    //
    // (Those percentages are the naive luminance the original measurement
    // used. `luminance()` above is the gamma-correct one and reports the
    // same fills at 1.3–2.2%. Both orderings agree; only the scale differs,
    // and the note is here so the two sets of numbers in this file do not
    // read as a contradiction.)
    // ---- THE DARKENING IS NOT THE SAME ON A LIGHT PALETTE ----
    //
    // 0.45 was a constant, and on the twenty dark palettes it is right: the
    // background is already near-black, dragging it further makes bezel.
    //
    // On mono-light it drags a #f4f4f2 page to a mid-grey slab. Reported as
    // "the light is too bad" alongside the unreadable text, and it is the
    // same mistake in a different place — treating "darker than the page" as
    // a fixed AMOUNT rather than as a relationship. A bezel on a light
    // machine is light grey; it is not the same grey a dark machine uses.
    //
    // 0.10 there, which takes #f4f4f2 to about #dcdcda: still visibly a
    // step down from the page, still reads as an inset frame, and it leaves
    // the surface pale enough that `surfaceIsDark` stays false and the ink
    // stays dark. At 0.45 the surface luminance lands near the 0.18 flip and
    // the panel was one palette tweak away from choosing white ink on grey.
    //
    // Keyed off `background` and NOT off `surface`: surface IS shellFill,
    // which is what this computes, so reading it here is a binding cycle.
    readonly property bool backgroundIsLight: root.luminance(root.background) >= 0.18
    readonly property real darkenTowardBlack: root.backgroundIsLight ? 0.10 : 0.45
    readonly property real accentMix: 0.08

    readonly property color shellFill: {
        const k = 1 - root.darkenTowardBlack;
        const m = root.accentMix;
        return Qt.rgba(
            root.background.r * k * (1 - m) + root.accent.r * m,
            root.background.g * k * (1 - m) + root.accent.g * m,
            root.background.b * k * (1 - m) + root.accent.b * m,
            1);
    }

    // ---------------------------------------------------------------
    //  Surfaces
    // ---------------------------------------------------------------

    // The one surface everything else is measured against. Every panel in
    // this shell sits on the island's own fill — that is the "one shape"
    // argument the notch is built on — so there is exactly one background
    // to solve contrast for, which is why solving it is cheap.
    readonly property color surface: root.shellFill

    // Is the surface dark enough that light ink wins? 0.18 rather than 0.5
    // because relative luminance is not perceptual lightness: a surface has
    // to be genuinely pale before dark ink beats light ink on it. Of the 21
    // palettes exactly one (mono-light, 22%) lands on the light side, and
    // the next highest is nord at 2.2%, so nothing sits near the boundary.
    readonly property bool surfaceIsDark: root.luminance(root.surface) < 0.18

    // The legible extreme for this surface. Everything readable is pushed
    // toward it; everything recessive is pushed away from it.
    readonly property color ink: root.surfaceIsDark ? "#ffffff" : "#000000"

    // Cards, module chips, the raised rows in a list. Was StyleTokens
    // `module` #1c1c1e / `cardFillActive` #26272b / `connectivityCard`
    // #343437 — three names for one idea at three depths.
    readonly property color surfaceRaised: root.mix(root.surface, root.ink, 0.07)
    readonly property color surfaceRaisedHover: root.mix(root.surface, root.ink, 0.12)
    readonly property color surfaceRaisedActive: root.mix(root.surface, root.ink, 0.17)

    // Inputs, slider grooves, progress tracks — anything that reads as cut
    // INTO the surface rather than laid on it. Away from the ink, so it
    // stays a recess on a light surface too instead of inverting.
    readonly property color surfaceSunken: root.mix(root.surface, root.surfaceIsDark ? "#000000" : "#ffffff", 0.35)

    // A full-bleed scrim for anything modal behind the island.
    readonly property color surfaceScrim: root.alpha(root.surfaceIsDark ? "#000000" : "#ffffff", 0.55)

    // The inverted surface: a pill or button painted IN the text colour,
    // with the surface showing through the glyphs. Was StyleTokens
    // buttonFill #f5f5f7 / buttonFillHover #ffffff / buttonFillPressed
    // #e9e9ec, i.e. a white pill on a black shell.
    readonly property color inverseSurface: root.textPrimary
    readonly property color inverseSurfaceHover: root.mix(root.textPrimary, root.ink, 0.35)
    readonly property color inverseSurfacePressed: root.mix(root.textPrimary, root.surface, 0.12)
    readonly property color inverseSurfaceInk: root.surface

    // The search / text field. Its own roles rather than reuse of
    // surfaceSunken, and that is a FINDING rather than a preference:
    // every panel with a filter draws a four-state input (fill and border
    // × focused and not) and each one had spelled the four out as
    // literals — #111216/#17181c/#292a30/#3d3f47 in the cheatsheet and
    // the picker, #212226/#3f4046 in the compiled tokens. Four values
    // that always move together are one role with four faces, and the
    // migration is what made that visible.
    //
    // Focus is drawn in a stronger HAIRLINE, not in the accent. That is a
    // translation and not a design change — the literals it replaces were
    // greys — and it is left that way deliberately, since the panels also
    // draw a selected ROW in the accent and a focused field ringed in the
    // same colour would compete with it.
    readonly property color inputFill: root.surfaceSunken
    readonly property color inputFillFocused: root.mix(root.surfaceSunken, root.ink, 0.05)
    readonly property color inputBorder: root.hairline
    readonly property color inputBorderFocused: root.hairlineStrong

    // Dividers. Alpha rather than a mixed opaque colour, because a
    // hairline crosses a card edge as often as it crosses the panel and
    // has to sit correctly on both. Was a literal "#22ffffff" at six
    // sites, which is this value on a dark theme and a white line on a
    // light one.
    readonly property color hairline: root.alpha(root.ink, 0.13)
    readonly property color hairlineStrong: root.alpha(root.ink, 0.24)

    // ---------------------------------------------------------------
    //  Text
    // ---------------------------------------------------------------
    //
    // Four roles, not eleven. The tree had eight StyleTokens text greys
    // (#7f828a … #f7f8fb) plus raw #6a6a6a, #8a8a8a, #8e8e93, #d0d0d0,
    // #f5f5f7 and #ffffff, and nothing anywhere said what distinguished
    // any two of them — so the next edit picked whichever the line above
    // used. These four are named for what they MEAN, and the collapse of
    // each old name onto one of them is recorded at the call site.
    readonly property color textPrimary: root._toContrast(root.foreground, root.surface, root.ink, 4.5)
    readonly property color textSecondary: root.mix(root.textPrimary, root.surface, 0.32)
    readonly property color textMuted: root.mix(root.textPrimary, root.surface, 0.48)
    readonly property color textDisabled: root.mix(root.textPrimary, root.surface, 0.62)

    // Text and glyphs drawn ON an accent fill, not on the surface. Solved
    // against the accent for the same reason as everything else: gruvbox's
    // accent is #fabd2f and matrix's is #00ff9f, and white text on either
    // is unreadable while black is fine — the opposite of every dark theme
    // in the list.
    // NAMED `accentInk` AND NOT `onAccent`, WHICH IS THE OBVIOUS NAME AND
    // IS A TRAP. In QML a property whose name begins with `on` collides
    // with the signal-handler syntax: `readonly property color onAccent:
    // <expr>` parses, loads, produces no error of any kind — and the
    // binding never runs, so the property sits at a `color`'s default,
    // which is opaque BLACK. Three roles were written that way here
    // (`onAccent`, `onInverseSurface`, `onOverviewPlate`) and all three
    // resolved to #000000 on all five themes the probe cycled, including
    // the ones where the correct answer is white. Black glyphs on a navy
    // accent, and nothing in the log.
    //
    // Do not name a token `onAnything`.
    readonly property color accentInk: root.inkOn(root.accent)

    // The same decision for ANY fill, not just the accent. `accentInk` was
    // the only place in the shell that painted text on a coloured chip, so
    // the rule lived inside it; qtile's TreeTab sidebar paints every
    // inactive row on the palette's RED and needed the identical answer.
    //
    // Generalised rather than copied, because the copy is the failure mode
    // this file exists to stop: a second site would have restated the 0.18
    // threshold, and the two would have disagreed the first time one of
    // them was adjusted. `toColor` first for the reason above — a caller
    // handing this a string would otherwise read NaN off it and get a
    // luminance of NaN, which compares false and silently returns white.
    function inkOn(c) {
        return root.luminance(root.toColor(c)) > 0.18 ? "#000000" : "#ffffff";
    }

    // ---------------------------------------------------------------
    //  Accent and selection
    // ---------------------------------------------------------------

    // `accent` above is the palette's raw signature colour and is what to
    // use for a fill. `accentText` is the same colour made safe to READ on
    // the surface — 3.0 rather than 4.5 because it is always used at title
    // or icon weight, never for body copy. Worst case across the 21
    // palettes is 4.15:1, i.e. the walk is never even needed.
    readonly property color accentText: root._toContrast(root.accent, root.surface, root.ink, 3.0)
    readonly property color accentPressed: root.mix(root.accent, "#000000", 0.22)
    readonly property color accentSoft: root.mix(root.accent, root.surface, 0.55)

    // A selected row. Fill is the accent at low alpha so the row's own
    // text keeps its colour; border is the accent itself.
    readonly property color selectionFill: root.alpha(root.accent, 0.18)
    readonly property color selectionFillHover: root.alpha(root.accent, 0.10)
    readonly property color selectionBorder: root.alpha(root.accent, 0.55)

    // ---------------------------------------------------------------
    //  Status
    // ---------------------------------------------------------------
    //
    // These are the palette's own red/green/yellow, made legible the same
    // way as everything else. They are NOT the battery bar's colours —
    // that one keeps its literals, because there the colour is the
    // reading rather than the styling. See "what stays hardcoded".
    readonly property color success: root._toContrast(root.green, root.surface, root.ink, 3.0)
    readonly property color warning: root._toContrast(root.yellow, root.surface, root.ink, 3.0)
    readonly property color danger: root._toContrast(root.red, root.surface, root.ink, 3.0)
    readonly property color info: root._toContrast(root.blue, root.surface, root.ink, 3.0)

    // The fifth palette slot, and the only one that had no legible form.
    // success/warning/danger/info solve green, yellow, red and blue; purple
    // was reachable only as the raw `purple`, which is a FILL colour and
    // carries no promise about being readable on the surface.
    //
    // Added because qtile's TreeTab uses colors[7] — purple — for its
    // section headings (config.py:7332, `section_fg`), and a heading is
    // text. Named after the slot rather than after a meaning, like
    // `accentText` beside it, because purple has no status meaning here;
    // it is the palette's fifth signature colour and nothing more. Same
    // 3.0 target as its four neighbours: these are all label weight, never
    // body copy.
    readonly property color purpleText: root._toContrast(root.purple, root.surface, root.ink, 3.0)

    // The tinted chip a status word sits in — `selectionFill` is the same
    // idea in the accent, and these are its status siblings. Same 0.18 so
    // a warning chip and a selected row read as one family.
    readonly property color successFill: root.alpha(root.success, 0.18)
    readonly property color warningFill: root.alpha(root.warning, 0.18)
    readonly property color dangerFill: root.alpha(root.danger, 0.18)
    // The accent's member of that family. `selectionFill` above is the same
    // 0.18 of the accent and is spoken for by row selection; this one is for
    // the other thing an accent tint marks — "this is the current one" —
    // which the calendar needs for today and which was being drawn in
    // `successFill` before, i.e. green in all 22 palettes.
    readonly property color accentFill: root.alpha(root.accent, 0.18)

    // ---------------------------------------------------------------
    //  Tracks
    // ---------------------------------------------------------------
    readonly property color trackEmpty: root.surfaceSunken
    readonly property color trackFill: root.accent

    // The same groove drawn ON a card rather than on the panel — a signal
    // strength bar, a per-stream volume bar. Alpha, because the thing
    // behind it is already a raised surface and an opaque sunken colour
    // would read as a hole in it. Was "#26ffffff" at two sites, which is
    // this value on a dark theme and a white smear on a light one.
    readonly property color trackSubtle: root.alpha(root.ink, 0.15)

    // ---------------------------------------------------------------
    //  The workspace overview
    // ---------------------------------------------------------------
    //
    // Its own roles rather than the panel ones, because it is the single
    // surface that draws ON TOP of the wallpaper rather than on the island
    // — so its card needs its own alpha and its borders are light-on-photo
    // rather than ink-on-fill. Was StyleTokens overviewCard #ee17181b,
    // overviewBorder #33ffffff, overviewInnerBorder #12ffffff,
    // workspaceCell #202226, workspaceCellBorder #1effffff,
    // workspaceOverlay #42070b10, workspaceActiveBorder #73d4ff.
    readonly property color overviewCard: root.alpha(root.mix(root.surface, "#000000", 0.15), 0.93)
    readonly property color overviewBorder: root.alpha(root.ink, 0.20)
    readonly property color overviewInnerBorder: root.alpha(root.ink, 0.07)
    readonly property color overviewCell: root.surfaceRaised
    readonly property color overviewCellHover: root.surfaceRaisedHover
    readonly property color overviewCellBorder: root.alpha(root.ink, 0.12)
    readonly property color overviewCellBorderHover: root.alpha(root.accent, 0.40)
    readonly property color overviewOverlay: root.alpha(root.mix(root.surface, "#000000", 0.6), 0.26)
    readonly property color overviewOverlayHover: root.alpha(root.mix(root.surface, "#000000", 0.4), 0.16)
    readonly property color overviewActiveBorder: root.accent

    // The window-name plate in the overview, and the one place in the shell
    // where the token layer cannot simply follow the surface.
    //
    // That label sits on a LIVE PREVIEW of the user's own window, so there
    // is no background to solve against — it is whatever is on screen, and
    // it changes while they look at it. No text colour survives both a
    // white page and a black terminal, which is why the plate exists at
    // all. The plate is therefore forced dark on EVERY theme (55% toward
    // black) rather than taking the surface as-is, and its ink is solved
    // against the plate rather than against the panel.
    //
    // Doing it the ordinary way would have broken exactly one theme, in
    // exactly the silent manner this file exists to prevent: on mono-light
    // the surface is #81818b, so `surface` at 0.88 is a mid grey plate and
    // `textPrimary` is BLACK — black on grey over a photograph.
    readonly property color plateBase: root.mix(root.surface, "#000000", 0.55)
    readonly property color overviewPlate: root.alpha(root.plateBase, 0.88)
    readonly property color overviewPlateBorder: root.alpha("#ffffff", 0.14)
    readonly property color overviewPlateInk: root._toContrast(root.foreground, root.plateBase, "#ffffff", 4.5)

    // ---------------------------------------------------------------
    //  Radii and durations — mirrored, not derived
    // ---------------------------------------------------------------
    //
    // The same four values `StyleTokens` publishes, restated here so that
    // migrating a file off `StyleTokens` does not leave it importing
    // `IslandBackend` for one integer. They are NOT theme-driven and are
    // not supposed to be; they are here for reach, not for colour.
    //
    // ---- DELETED, AND COUNTED BEFORE DELETING ----
    //
    // There were eight of these — four radii and four durations, mirrored from
    // the packaged `StyleTokens` so a file migrating off it did not have to
    // import `IslandBackend` for one integer. Counted across the whole tree:
    //
    //     radiusPanel radiusModule radiusPrompt radiusButton     0 callers
    //     durationControl durationQuick durationStandard         0 callers
    //     durationFast                                           7 callers
    //
    // Seven of eight were an inventory nobody shopped from, which is the exact
    // thing P1-5 called out about the type and radius numbers and which the
    // audit then found was mostly already false ELSEWHERE — here it was true.
    // The radius argument now lives in Metrics.RADIUS, which is derived from
    // the padding rather than mirrored from a package, and the durations live
    // in Motion.js, which is the file that owns time in this shell.
    //
    // durationFast's 120 ms is not lost: it IS Motion.CONTROL_MS, and its
    // seven callers were moved to Motion.controlDuration() in the same commit
    // that took these out, so nothing on screen changed.

    // ---------------------------------------------------------------
    //  The source
    // ---------------------------------------------------------------

    function applyJson(text) {
        try {
            const parsed = JSON.parse(text);
            if (!parsed || !parsed.bg)
                return;
            root.themeName = String(parsed.theme || "");
            root.background = String(parsed.bg);
            root.backgroundAlt = String(parsed.bgAlt || parsed.bg);
            root.foreground = String(parsed.fg || "#ffffff");
            root.red = String(parsed.red || "#ff6c6b");
            root.green = String(parsed.green || "#98be65");
            root.yellow = String(parsed.yellow || "#ecbe7b");
            root.blue = String(parsed.blue || "#51afef");
            root.purple = String(parsed.purple || "#c678dd");
            root.cyan = String(parsed.cyan || "#46d9ff");
            root.accent = String(parsed.accent || parsed.blue || "#51afef");
        } catch (error) {
            // Keep whatever is already loaded. A half-written or corrupt
            // palette must not repaint the shell into something
            // unreadable, and now that every surface in the shell reads
            // this object that is not a small blast radius.
            //
            // This IS reachable, and the earlier revision of this comment
            // said the opposite — it claimed theme-apply "renames the file
            // into place atomically". It does not, and it must not:
            // MIGRATION.md item 4 records that the rename was REMOVED,
            // because FileView is a QFileSystemWatcher and an atomic mv
            // replaces the inode, leaving the watch pointed at an unlinked
            // file and onFileChanged never firing again. theme-apply
            // truncates and rewrites in place for that reason, so a torn
            // read is a real if narrow window, and this catch is the thing
            // that covers it.
        }
    }

    FileView {
        path: Quickshell.env("HOME") + "/.cache/tide-island/colors.json"
        watchChanges: true
        // Preloaded: the very first frame the island draws must already
        // carry the theme, or the shell flashes doomone-black and then
        // repaints, which is more noticeable than a slow start. See the
        // singleton note in the header — preload alone is not enough, the
        // early touch in shell.qml is the other half.
        preload: true
        printErrors: false

        onLoaded: root.applyJson(text())
        onFileChanged: {
            reload();
            root.applyJson(text());
        }
    }
}
