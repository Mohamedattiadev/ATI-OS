.pragma library

//
// Motion.js — one motion system for the island, generated at runtime.
//
// DESIGN-SPEC.md, quoting the notch author:
//
//   "None of this runs on easing presets. There's no ease out quad, no in
//    out cubic. The shell generates a real spring at runtime."
//
//   Duration 400 ms, damping ratio 0.8 — "under 1, so it overshoots
//   slightly and settles. That tiny overshoot is the whole difference
//   between something that moves and something that feels like it has
//   mass."
//
// Upstream Tide Island runs everything on Easing.OutQuint at 400 ms.
// OutQuint is monotone with a very long tail: it covers 97% of the
// distance in the first ~150 ms and then spends 250 ms crawling the last
// 3%. That tail is precisely the "the movement feels slow" complaint —
// the animation is not slow to START, it is slow to STOP. A spring at the
// same nominal 400 ms arrives, overshoots 1.5%, and settles, which reads
// as faster while lasting exactly as long.
//
// WHY A BEZIER SPLINE AND NOT SpringAnimation
// -------------------------------------------
// Qt ships SpringAnimation, but it is parameterised by spring constant and
// damping *coefficient*, not by duration and damping *ratio*, and it has no
// defined end time — it runs until epsilon. Every Behavior in this file
// needs to compose with durations that other things (loaders, delays,
// sliderIntroDelay) are already synchronised against. So we do what the
// spec describes: solve the damped harmonic oscillator analytically, and
// hand Qt the step response as a cubic Bezier spline it can run inside a
// normal duration-bounded NumberAnimation.
//
// TWO CURVES, NOT ONE — and this is not a detail
// ----------------------------------------------
//   "Fades use a different, critically damped curve, because opacity is
//    clamped 0-1: an overshooting fade tries to exceed fully opaque, gets
//    clipped, and reads as an abrupt cut. Position can overshoot and
//    opacity physically can't."
//
// So: `spring` (zeta 0.8) for geometry, `fade` (zeta 1.0) for opacity and
// colour. Using `spring` on an opacity Behavior is a real bug, not a taste
// question — Qt clamps the overshoot flat and you get a visible hitch.
//

// ---------------------------------------------------------------------
//  Tunables — the whole motion system's speed lives in these three lines
// ---------------------------------------------------------------------

// Spec duration for the island's own morph, in ms.
var MORPH_MS = 400;

// Fades are shorter than moves on purpose: a fade that lasts as long as
// the move it accompanies reads as lag, because the eye resolves opacity
// faster than it resolves position.
var FADE_MS = 220;

// Global multiplier, for taste. 1.0 is the spec. Lower is faster.
// This exists so "make it snappier" is a one-number change rather than a
// hunt through 92 hardcoded durations.
var SCALE = 1.0;

// ---------------------------------------------------------------------
//  ONE DURATION FOR A 40 px MOVE AND A 1000 px ONE WAS THE BUG
// ---------------------------------------------------------------------
//
// MORPH_MS was applied flat to every shape change. The island's smallest
// morph is the resting capsule gaining the EQ allowance, ~40 px of width.
// Its largest is resting -> control centre: 120 px to 1100 px, a 980 px
// change, plus roughly 300 px of height. Both took 400 ms.
//
// Those cannot both be right, and the failure is asymmetric. A 40 px move
// given 400 ms is watchable but slow — it is the one that reads as
// "laggy". A 980 px move given 400 ms has to cover 2.45 px per ms, which
// no spring curve can make read as mass; it reads as a jump with a
// wobble on the end. The complaint that the animation is "not smooth"
// is mostly this second case.
//
// amanhex/ukishima, which was the comparison, does not do this: its
// Motion singleton carries BOTH `morph: 420` and `shapeshift: 820`, and
// the big surfaces use the second. That is the idea borrowed here — the
// implementation is ours, because a two-value step still picks the wrong
// one at the boundary.
//
// So the duration interpolates on distance instead. Below REF_PX the
// duration is MORPH_MS; at or above LARGE_PX it is LARGE_MORPH_MS; in
// between it is linear. Linear and not the square-root law that physical
// motion suggests: sqrt compresses the middle of the range hard, and the
// island's most common non-trivial morphs (resting -> expanded player,
// ~500 px) sit exactly in that middle.
//
// The spec's 400 ms is preserved as the SMALL-morph duration, which is
// what it was measured on — the spec describes the resting pill's own
// motion, not a full-width panel.

// Distance, in px, at or below which a morph is "small" and gets MORPH_MS.
var REF_PX = 120;
// Distance at or above which it is "large" and gets LARGE_MORPH_MS.
var LARGE_PX = 900;
// Ukishima's shapeshift is 820. 760 here: our curve is a real spring with
// an overshoot that already reads as arrival, so it needs slightly less
// wall-clock time than their monotone bezier to feel equally settled.
//
// 760 STAYS, and the attempt to lower it is recorded here because the
// measurement that killed it is worth more than the change would have been.
//
// "From going to popup to another there are laggness" looks like this
// number's fault, and 760 -> 520 was tried on exactly that reasoning: our
// spring is zeta 0.8, so the envelope e^(-8t) is at 3% by t=0.42 and the
// shape is visually THERE at 42% of whatever duration it is given, making
// the rest a tail. Halving the tail should have halved the complaint.
//
// It did nothing. Measured with a 50 fps grim burst (20 ms/frame, PPM so
// the PNG encode stays out of the sample rate), island RESTARTED between
// runs because this is a `.pragma library` and the running shell caches it:
//
//     LARGE_MORPH_MS = 760    settle 787 ms
//     LARGE_MORPH_MS = 520    settle 801 ms
//
// Within noise, and in the wrong direction. The shape duration is not what
// the transition is waiting on, so lowering it buys nothing and costs the
// mass the paragraph above is right to want.
//
// What it IS waiting on came out of DIFFERENCING two frames either side of
// the tail rather than measuring the tail's magnitude: at +621 ms against
// +990 ms the whole content block is still shifting ~8 px vertically and
// the brightness slider is still sweeping toward its value. Neither is the
// morph. See `sliderIntroDelay` in ControlCenterLayer.qml.
var LARGE_MORPH_MS = 760;

function morphDuration() { return Math.round(MORPH_MS * SCALE); }
function fadeDuration()  { return Math.round(FADE_MS  * SCALE); }

// The duration for a morph that travels `px`. Callers that do not know
// their distance keep using morphDuration() and get the old behaviour.
function morphDurationFor(px) {
    var d = Math.abs(Number(px));
    if (!isFinite(d) || d <= REF_PX)
        return morphDuration();
    if (d >= LARGE_PX)
        return Math.round(LARGE_MORPH_MS * SCALE);
    var t = (d - REF_PX) / (LARGE_PX - REF_PX);
    return Math.round((MORPH_MS + (LARGE_MORPH_MS - MORPH_MS) * t) * SCALE);
}

// ---------------------------------------------------------------------
//  CONTENT CHOREOGRAPHY — the three numbers that fix "too bad" animations
// ---------------------------------------------------------------------
//
// Everything above governs the SHAPE. Nothing above governed the CONTENT,
// and that is where the complaint actually lived. Before this section
// existed, every one of the 20 layers in this shell carried its own
// hand-picked pair of fade durations on `Easing.InOutQuad`:
//
//     in:  160 180 200 220 240 260 280 300
//     out: 100 120 130 140 150 200
//
// Eight in-durations and six out-durations, none of them derived from the
// 400 ms the shape takes, none of them equal to each other, and none of
// them the critically damped curve the spec insists opacity must use. A
// state change therefore ran three clocks at once — old content on one,
// new content on another, the capsule on a third — and three clocks that
// disagree is the definition of a stutter.
//
// MEASURED, closing the theme picker (10 grim frames, ~66 ms apart, times
// from `date +%s%N` around the IPC call rather than assumed):
//
//   t=+58ms   capsule still ~700 px wide, theme grid ALREADY GONE,
//             clock ALREADY at full opacity, centred in a huge empty box
//   t=+196ms  capsule fully collapsed to the notch
//
// and opening it:
//
//   t=+69ms   capsule barely wider than the notch, "Theme" header already
//             painted and clipped by the shape's own `clip: true`
//   t=+138ms  capsule near full width, still only the header
//   t=+272ms  full grid
//
// So content was not fading at all in either direction — it teleported,
// and it teleported at the WRONG END of the morph both times. See
// PanelLoader.qml for why the out-fade never even started.
//
// The choreography these three numbers encode:
//
//   0 .. FADE_OUT_MS          old content leaves, fast, while the shape has
//                             barely begun to move
//   0 .. morphDuration()      the shape travels (spring: reaches target at
//                             ~168 ms, peaks +1.5% at ~210 ms, settles)
//   CONTENT_DELAY_MS ..
//     + FADE_IN_MS            new content arrives INTO a shape that is
//                             already ~72% of the way there at 90 ms and
//                             within 1% of final by 290 ms
//
// The delay is the load-bearing part and it is cheap: 90 ms is below the
// ~100 ms threshold at which a response stops feeling immediate, so the
// panel still reads as instant while no longer being drawn inside a box
// that is the wrong size for it.
var FADE_IN_MS = 200;
var FADE_OUT_MS = 130;
var CONTENT_DELAY_MS = 90;

function fadeInDuration()  { return Math.round(FADE_IN_MS  * SCALE); }
function fadeOutDuration() { return Math.round(FADE_OUT_MS * SCALE); }
function contentDelay()    { return Math.round(CONTENT_DELAY_MS * SCALE); }

// ---------------------------------------------------------------------
//  CONTROL_MS — geometry INSIDE a panel that has already arrived
// ---------------------------------------------------------------------
//
// Everything above this line times the CAPSULE: a shape crossing most of a
// screen, where mass is the point and 400 ms reads as considered. A tab
// underline sliding 60 px is not that movement, and borrowing the capsule's
// clock for it is what makes an in-panel control feel like it is lagging
// behind the finger that moved it. `morphDurationFor()` cannot help — it
// floors at `morphDuration()` for anything under REF_PX, which is every
// control this is for.
//
// This is a CONSOLIDATION and not a new number. `IslandTheme.durationFast`
// is 120 ms and is already on screen in seven places; its three siblings
// (durationControl 130, durationQuick 140, durationStandard 280) have zero
// callers between them, which is the same "inventory, not system" the type
// and radius tables were. 120 is therefore the value the shell already
// settled on for this class of movement, named here so the next in-panel
// control has one place to take it from and the dead tokens can go.
//
// Paired with spring() rather than fade() wherever it moves a shape: this
// shell's geometry overshoots ~1.5% and stopping dead is the tell that
// something is a rectangle rather than an object.
var CONTROL_MS = 120;

function controlDuration() { return Math.round(CONTROL_MS * SCALE); }

// ---------------------------------------------------------------------
//  The oscillator
// ---------------------------------------------------------------------

// Unit step response of a second-order system, normalised so that
// t is in [0,1] across the whole animation.
//
//   underdamped (zeta < 1):
//     y(t) = 1 - e^(-zeta*w*t) * (cos(wd*t) + zeta/sqrt(1-zeta^2) * sin(wd*t))
//   critically damped (zeta = 1):
//     y(t) = 1 - e^(-w*t) * (1 + w*t)
//
// w is chosen so the response has FULLY settled by t=1, not merely entered
// its settling band. That distinction cost a rewrite and is worth spelling
// out, because the textbook number gives a curve with no visible spring in
// it at all:
//
// The usual 2% settling time is 4.6/(zeta*w). Plug that in and, at zeta
// 0.8, w=5.75 — which puts the overshoot PEAK at t=0.91, i.e. almost
// exactly at the end of the animation. The curve is then normalised by its
// own value at t=1 (see _buildCurve), and dividing the peak by a point
// that sits on the peak flattens it: measured 0.15% overshoot instead of
// the theoretical 1.52%. Invisible. The spring was mathematically present
// and perceptually absent.
//
// Using zeta*w = 8 (envelope e^-8 = 0.03% at t=1) puts the peak at t=0.52
// and leaves the tail genuinely flat, so normalisation costs nothing:
// measured 1.54% overshoot against a theoretical
// exp(-pi*zeta/sqrt(1-zeta^2)) = 1.52%. It also means the motion is
// essentially complete at 105 ms of the 400 ms budget — which is the
// actual answer to "the animations are too slow", without shortening the
// duration other things synchronise to.
function _omega(zeta) {
    if (zeta >= 1.0)
        return 10.0;
    return 8.0 / zeta;
}

function _value(zeta, t) {
    var w = _omega(zeta);
    if (zeta >= 1.0)
        return 1 - Math.exp(-w * t) * (1 + w * t);

    var wd = w * Math.sqrt(1 - zeta * zeta);
    return 1 - Math.exp(-zeta * w * t)
        * (Math.cos(wd * t) + (zeta / Math.sqrt(1 - zeta * zeta)) * Math.sin(wd * t));
}

// Analytic derivative. Used for the spline tangents rather than a finite
// difference, because a finite difference at the overshoot peak rounds the
// peak off — and the peak is the only part of this curve anyone can see.
function _slope(zeta, t) {
    var w = _omega(zeta);
    if (zeta >= 1.0)
        return w * w * t * Math.exp(-w * t);

    var wd = w * Math.sqrt(1 - zeta * zeta);
    return (w / Math.sqrt(1 - zeta * zeta)) * Math.exp(-zeta * w * t) * Math.sin(wd * t);
}

// ---------------------------------------------------------------------
//  Oscillator -> Easing.BezierSpline
// ---------------------------------------------------------------------
//
// ##  READ THIS BEFORE CHANGING _SEGMENTS  ##
//
// Qt's BezierSpline easing supports AT MOST 10 cubic segments. Handing it
// an eleventh does not warn, does not fall back, and does not fail — it
// corrupts the heap and the process dies with SIGSEGV.
//
// In qeasingcurve.cpp, BezierEase's constructor preallocates
//
//     _curves(10), _intervals(10)
//
// and init() then does `for (i = 0; i < _curveCount; i++) _intervals[i] = ...`
// where _curveCount is points/3 — taken from the curve you supplied, with
// no bound check against the 10 it reserved. Eleven segments writes one
// past the end of a QList.
//
// This is not theory. An earlier revision of this file used 24 segments and
// killed the whole shell on the first animated frame:
//
//     ERROR: Quickshell has crashed under pid ...
//     ERROR: Quickshell crashed within 10 seconds of launching.
//     WARN:  QEventLoop: Cannot be used without QCoreApplication
//
// The QEventLoop warning is emitted by the crash handler AFTER the fact and
// is a red herring; it says nothing about the cause. The crash was bisected
// in an offscreen `qml6` harness with nothing in it but a NumberAnimation
// and this file: 8 segments fine, 10 segments fine, 11 segments SIGSEGV.
// The stack (QQuickBehavior::write -> QAbstractAnimationJob::setCurrentTime
// -> QEasingCurve) confirms it is the curve and not the QML around it.
//
// So the segment budget is fixed at 10 and the fidelity has to come from
// spending those 10 well, which is what the non-uniform knots below do.
var _SEGMENTS = 10;

// Knots are NOT evenly spaced in t. With only 10 segments, even spacing
// wastes half of them on the dead flat tail after the spring has settled,
// and the maximum error lands at 2.9e-3 — right on the overshoot peak, the
// one part of the curve that exists to be seen.
//
// Instead the knots are warped by t^1.8, which clusters them where the
// curvature is (the rise and the peak, roughly t < 0.6) and leaves three
// long segments to cover the flat remainder that a straight line would
// have fitted anyway.
//
// Measured against the analytic response at 1001 sample points:
//
//   | knots            | segs | max deviation | overshoot peak |
//   |------------------|------|---------------|----------------|
//   | uniform          |  24  | 1.1e-4        | 1.0154 @ 0.524 |  <- crashes
//   | uniform          |  10  | 2.9e-3        | 1.0154 @ 0.525 |
//   | t^1.8 (this)     |  10  | 4.0e-4        | 1.0154 @ 0.523 |
//
// i.e. the 10-segment curve we are forced into tracks the true spring to
// within 0.04% of the travel distance, and the overshoot is intact —
// theoretical is 1.0152.
var _WARP = 1.8;

// Qt's bezierCurve is a flat list of cubic segments:
//
//     [c1x,c1y, c2x,c2y, p1x,p1y,  c1x,c1y, c2x,c2y, p2x,p2y, ...]
//
// starting implicitly at (0,0). Qt only marks the curve valid if the final
// point is exactly (1,1); miss it and BezierEase silently stays invalid and
// the animation runs linear, which is easy to overlook because it still
// runs.
//
// Each segment is a cubic Hermite converted to Bezier: with an x-step h,
// control points sit at x1+h/3 and x2-h/3, carrying the analytic slope.
// Because h/3 is always less than half the interval, x stays strictly
// increasing across the whole list even with the non-uniform knots, which
// Qt also requires.
//
// The whole response is divided by its own value at t=1 so the curve lands
// on exactly 1.0. With the omega chosen in _omega that value is 0.9998, so
// the normalisation is a rounding correction and the overshoot survives it
// intact — see the long comment there for what happens when it does not.
function _buildCurve(zeta, segments, warp) {
    var norm = _value(zeta, 1.0);
    var out = [];

    for (var i = 0; i < segments; i++) {
        var x1 = Math.pow(i / segments, warp);
        var x2 = Math.pow((i + 1) / segments, warp);
        var h = x2 - x1;

        var y1 = _value(zeta, x1) / norm;
        var y2 = _value(zeta, x2) / norm;
        var m1 = _slope(zeta, x1) / norm;
        var m2 = _slope(zeta, x2) / norm;

        out.push(x1 + h / 3, y1 + m1 * h / 3);
        out.push(x2 - h / 3, y2 - m2 * h / 3);

        // Snap the final knot to exact 1,1. Floating point lands on
        // 0.9999999999999999 often enough that leaving it to chance means
        // the curve is occasionally rejected, and only occasionally — the
        // worst kind of bug to chase.
        if (i === segments - 1)
            out.push(1.0, 1.0);
        else
            out.push(x2, y2);
    }

    return out;
}

// Memoised, because a Behavior re-evaluates its bindings and there is one
// of these per capsule per property. Computing the exponentials on every
// evaluation of every Behavior on every screen is free-ish but pointless.
var _cache = {};

function curve(zeta) {
    var key = String(zeta);
    if (!_cache[key])
        _cache[key] = _buildCurve(zeta, Math.min(_SEGMENTS, 10), _WARP);
    return _cache[key];
}

// ---------------------------------------------------------------------
//  WHAT IS DELIBERATELY *NOT* ON THIS SYSTEM
// ---------------------------------------------------------------------
//
// This file was written and then most of the shell kept upstream's easing
// presets anyway: an audit counted 66 raw `easing.type: Easing.*` against
// 23 files that referenced Motion. 49 of those were transitions — sizes,
// positions, scales, opacities, colours — and are now converted, classified
// strictly by what the property IS:
//
//   spring (zeta 0.8)  width height x y scale rotation radius, and the
//                      0-1 values that drive a POSITION (animatedGroupShift,
//                      pageProgress, the timer bubble's reveal)
//   fade   (zeta 1.0)  opacity, colour, and every 0-1 value that is CLAMPED
//                      like opacity is — displayedVolume, displayedBrightness,
//                      batteryDrawerProgress, animatedProgress, slashProgress,
//                      lyricChangeProgress
//
// The second half of that list is the part worth arguing. A volume slider's
// fill is not opacity, but it is bounded at both ends exactly like opacity,
// and a spring's 1.5% overshoot on a slider at 100% draws a fill wider than
// its own track for ~100 ms. Same failure mode, same curve.
//
// 16 raw easings remain ON PURPOSE. They are not transitions between two
// states and the spring says nothing about them.
//
// ---- RE-AUDITED 2026-08-13, AND THE LIST WAS NOT SIMPLY INHERITED ----
//
// The brief asked for this list to be CONFIRMED rather than carried forward,
// which was the right instinct: three of its claims were wrong, one of them
// in a way that would have justified the wrong thing next time.
//
// Counted first, by grepping `easing.type: Easing.` and discarding
// BezierSpline (which is this file's own curves being applied):
//
//     FavoriteStar          8   (6 InOutCubic, 2 InOutQuad)
//     timerCompletion       4   (3 OutCubic, 1 InOutQuad)
//     RecordingIndicator    2   (InOutSine)
//     ThemeTransitionWindow 1   (Linear)
//     osdProgress           1   (on a SmoothedAnimation — see below)
//     ------------------------
//                          16
//
//   * THE COUNT WAS 17 AND IS 16. The seventeenth slot was SwipeCavaBars,
//     which the list itself describes as having been converted TO the spring
//     — an entry saying "this is not one of them" was being counted as one of
//     them. Verified still on `Motion.spring()` in that file.
//
//   * FavoriteStar's REASON WAS WRONG, though its conclusion holds. The list
//     said "the overshoot is already authored into the keyframes; adding a
//     second one fights it". There is no overshoot in those keyframes: the
//     eight legs are 1 -> 0.9, 0.9 -> 1, 0.5 -> 1, 1 -> 0.5, 0 -> 1 and
//     1 -> 0, and nothing exceeds 1. It is a squash-and-return, not an
//     overshoot. The real reason to leave them raw is stronger and is now
//     what is written here: they are scripted legs of a SequentialAnimation
//     rather than a state transition, and a spring on each leg would
//     compound its 1.5% past the *intermediate* values the choreography was
//     drawn against.
//
//   * osdProgress's easing.type IS DEAD CODE, which the old entry implied and
//     did not say. `SmoothedAnimation { velocity: 1.2; duration: 180;
//     easing.type: Easing.InOutQuad }` — SmoothedAnimation solves its own
//     velocity-limited trajectory (Qt's private header carries `tp`, the time
//     of peak velocity, and `vi`, the normalised initial velocity) and never
//     evaluates the easing curve.
//
//     MEASURED rather than read: two SmoothedAnimations differing only in
//     easing type (InOutQuad vs OutBounce), sampled every 16 ms for 30
//     frames, produce byte-identical trajectories. The same harness on a
//     plain NumberAnimation reports them different, which is the control that
//     makes the first result mean anything. So the entry stands — it is
//     velocity-limited on purpose, because volume keys autorepeat and a
//     duration-based animation restarts from the beginning on every repeat —
//     but the easing.type on it is inert and should not be read as a choice.
//
// The four that survive unchanged:
//
//   FavoriteStar (8)          a hand-choreographed pop, as scripted legs of a
//                             SequentialAnimation. See above for why the
//                             original reason was wrong and this one is not.
//   RecordingIndicator (2)    a looping InOutSine breathe. A step response
//                             has no meaning for something that never stops.
//   timerCompletion (4)       a bespoke pulse-and-flash celebration, same
//                             reasoning as the star: 0 -> 1 then 1 -> 0 on
//                             two properties, scripted, not a transition.
//   ThemeTransitionWindow (1) the 620 ms wipe. Linear, and its own file
//                             argues it at length: a straight front covers
//                             area at a constant rate, so easing it makes the
//                             front visibly accelerate and brake. Its radius
//                             must also be monotone — an overshoot past
//                             maximumRadius would re-cover the screen it just
//                             revealed.
//
// The two curves the spec names. Call these, not curve().
//
//   spring — geometry: width, height, radius, position, the notch morph.
//            Overshoots ~1.5% and settles.
//   fade   — opacity and colour. Critically damped: arrives and stops,
//            never exceeds 1 (measured max is exactly 1.00000), so
//            nothing gets clipped.
function spring() { return curve(0.8); }
function fade()   { return curve(1.0); }

// How far past its target the spring goes, as a fraction of the travel.
//
// Published rather than left implicit because callers have to BUDGET for
// it. Anything that sizes a container from an animated value's TARGET —
// the island's own layer surface is the case that bit — is sizing for a
// height the shape briefly exceeds, and clips the peak of every morph.
//
// Theory for zeta = 0.8 is exp(-pi*zeta/sqrt(1-zeta^2)) = 1.52%; the
// 10-segment spline this file is limited to measures 1.54% against the
// analytic response at 1001 sample points. The larger of the two is the
// safe one to hand out.
function overshoot() { return 0.0154; }

