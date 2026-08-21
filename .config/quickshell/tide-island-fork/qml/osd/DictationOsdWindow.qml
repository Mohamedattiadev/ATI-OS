import QtQuick
import Quickshell
// No `import Quickshell.Wayland` — same backend-neutral-base reasoning as
// RingOsdWindow.qml, see ../common/BackendSurface.md. The three
// `WlrLayershell.*` lines live in DictationOsdWindowWayland.qml instead.

import "../common"
import "../common/Metrics.js" as Metrics
import "../common/Motion.js" as Motion
import "../island"

//
// FORK — new file. A standalone "you are being heard" indicator for
// ati-voice-dictate-live (Alt+F8), cloned structurally from RingOsdWindow.qml
// rather than invented fresh: same reasons apply almost word for word.
//
// WHY A SEPARATE WINDOW AND NOT AN ISLAND STATE
// ----------------------------------------------
// RingOsdWindow's header already makes this case for the volume ring, and
// dictation has a second reason of its own: DynamicIslandWindow's capsule is
// a state machine (resting / split / notification / panels / swipe cards),
// and every one of those states already has an owner. Wedging a fifth thing
// in there means picking which existing state it interrupts, for a feature
// that can run for however long a sentence takes — long enough to matter,
// short enough that fighting the capsule's own auto-hide timer (built for a
// volume blip, not an open-ended recording) would have been a second problem
// on top of the first. A window that only exists while listening sidesteps
// both: nothing to interrupt, nothing to auto-hide.
//
// WHY IT DOES NOT TAKE INPUT, WHY Overlay, WHY NOT `exclusiveZone`
// ------------------------------------------------------------------
// Identical to RingOsdWindow — see that file. This one is mapped for
// however long a dictation session runs rather than a ~1.4s blip, which
// makes the empty input mask MORE load-bearing here, not less: a fullscreen
// click-eating surface that can legitimately stay up for a full minute
// (ati-voice-dictate-live's own MAX isn't enforced — whisper-stream just
// keeps listening until Alt+F8 is pressed again) would be a real, not
// theoretical, way to lock the desktop.
//
PanelWindow {
    id: root

    required property var shellRootController

    // Scrolling amplitude history (0..1 per sample, oldest first) and dBFS
    // peak-meter state — see shell.qml's dictationWaveformRing/
    // dictationPeakDbfs/dictationHeldDbfs for where these come from (a
    // second, mic-reading cava instance) and the waveform/meter Canvas
    // below for how they're drawn. Left at zeroed defaults while inactive
    // rather than cleared explicitly: nothing reads them while `shown` is
    // false, and shell.qml's dictationResetMeters() already clears the
    // source the moment dictation stops.
    property var ring: []
    property real peakDbfs: -120
    property real heldDbfs: -120
    property color accentColor: IslandTheme.accent
    property color shellFill: IslandTheme.surface

    // ---- WAVEFORM + METER RENDERING ----
    //
    // Ported from Voxtype's own Quickshell OSD frontend
    // (github.com/peteonrails/voxtype, MIT — quickshell/voxtype-shared/
    // RecipeRenderer.qml's _drawWaveform/_drawMeter and Theme.qml's color
    // constants), which is what the reference screenshot for this feature
    // actually is. NOT ported: their layer/recipe system
    // (_sortedLayers/_rebuildLayers, the pluggable "bars"/"pulse"/"ring"/
    // "icon"/"label" layer types, StyleLoader) — that's a user-theming
    // mechanism this desktop has no equivalent slot for. Also NOT
    // ported: _waveLevels/_updateLevels's per-column spring smoothing —
    // cava's own `noise_reduction` already smooths the source, so
    // _drawWaveform below samples dictationWaveformRing directly through
    // the same neighbor 3-tap blend _drawWaveform itself applies, skipping
    // the extra smoothing stage upstream runs before that blend.
    //
    // waveformColor deliberately uses THIS shell's accent (threaded in via
    // shell.qml, same as the rest of this file) rather than Theme.qml's own
    // hardcoded rgba(0.40,0.78,1.00,1) — so the waveform re-themes with the
    // rest of the desktop instead of carrying a second, unrelated blue.
    // Everything else below is the upstream value unchanged.
    readonly property color waveformColor: root.accentColor
    readonly property color waveformPeakColor: "#FCFBF8"
    readonly property color meterLowColor: Qt.rgba(0.30, 0.85, 0.45, 1.0)
    readonly property color meterMidColor: Qt.rgba(0.95, 0.80, 0.30, 1.0)
    readonly property color meterHighColor: Qt.rgba(0.95, 0.35, 0.30, 1.0)
    readonly property real waveformGain: 10.0
    readonly property real meterFloorDbfs: -60.0

    // 0..1: how loud the current dBFS reads against the meter's floor —
    // ported from RecipeRenderer._meterFill.
    function _meterFill(dbfs) {
        if (!isFinite(dbfs) || dbfs <= root.meterFloorDbfs)
            return 0.0;
        const clipped = Math.min(dbfs, 0);
        return Math.max(0, Math.min(1, (clipped - root.meterFloorDbfs) / -root.meterFloorDbfs));
    }

    // Interpolated sample at a given output column — ported from
    // RecipeRenderer._levelAt, applied straight to the ring (see the
    // smoothing note above for why there's no intermediate array here).
    function _levelAt(samples, index, count) {
        if (!samples || samples.length === 0)
            return 0.0;
        const t = count <= 1 ? 0 : index / (count - 1);
        const f = t * (samples.length - 1);
        const lo = Math.floor(f);
        const hi = Math.min(samples.length - 1, lo + 1);
        const mix = f - lo;
        return samples[lo] * (1 - mix) + samples[hi] * mix;
    }

    function _paintRounded(ctx, x, y, w, h, r) {
        if (w <= 0 || h <= 0)
            return;
        const rr = Math.max(0, Math.min(r || 0, Math.min(w, h) / 2));
        ctx.beginPath();
        ctx.moveTo(x + rr, y);
        ctx.lineTo(x + w - rr, y);
        ctx.quadraticCurveTo(x + w, y, x + w, y + rr);
        ctx.lineTo(x + w, y + h - rr);
        ctx.quadraticCurveTo(x + w, y + h, x + w - rr, y + h);
        ctx.lineTo(x + rr, y + h);
        ctx.quadraticCurveTo(x, y + h, x, y + h - rr);
        ctx.lineTo(x, y + rr);
        ctx.quadraticCurveTo(x, y, x + rr, y);
        ctx.closePath();
        ctx.fill();
    }

    // Mirrored filled envelope (top+bottom trace around the vertical
    // center) plus a soft multi-pass stroked outline on the top edge only
    // — ported from RecipeRenderer._drawWaveform (mirror=true branch) and
    // _strokeSoftLine, ring capacity is oldest-at-index-0 so the trace
    // scrolls left (old) to right (new) same as upstream.
    function _drawWaveform(ctx, rect, samples) {
        const cols = Math.max(24, Math.min(96, Math.floor(rect.w / 5)));
        const cy = rect.y + rect.h / 2;
        const amp = Math.max(1, rect.h * 0.45);

        const raw = new Array(cols);
        for (let i = 0; i < cols; i++)
            raw[i] = root._levelAt(samples, i, cols);
        const blended = new Array(cols);
        for (let i = 0; i < cols; i++) {
            const prev = raw[Math.max(0, i - 1)];
            const next = raw[Math.min(cols - 1, i + 1)];
            blended[i] = prev * 0.25 + raw[i] * 0.5 + next * 0.25;
        }
        function envelopeAt(i) {
            return Math.max(0.015, Math.min(1.0, blended[i] * root.waveformGain));
        }
        function xAt(i) {
            const t = cols <= 1 ? 0 : i / (cols - 1);
            return rect.x + t * rect.w;
        }

        ctx.save();

        ctx.beginPath();
        for (let i = 0; i < cols; i++) {
            const x = xAt(i), y = cy - envelopeAt(i) * amp;
            if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
        }
        for (let i = cols - 1; i >= 0; i--) {
            const x = xAt(i), y = cy + envelopeAt(i) * amp;
            ctx.lineTo(x, y);
        }
        ctx.closePath();
        ctx.globalAlpha = 0.18;
        ctx.fillStyle = root.waveformColor;
        ctx.fill();

        function topPath() {
            ctx.beginPath();
            for (let i = 0; i < cols; i++) {
                const x = xAt(i), y = cy - envelopeAt(i) * amp;
                if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
            }
        }
        ctx.strokeStyle = root.waveformColor;
        ctx.lineCap = "round";
        ctx.lineJoin = "round";
        ctx.globalAlpha = 0.75 * 0.25; ctx.lineWidth = 1.4 * 4.0; topPath(); ctx.stroke();
        ctx.globalAlpha = 0.75 * 0.55; ctx.lineWidth = 1.4 * 2.0; topPath(); ctx.stroke();
        ctx.globalAlpha = 0.75;        ctx.lineWidth = 1.4;       topPath(); ctx.stroke();

        ctx.restore();
    }

    // Vertical peak meter: rounded track, green→yellow→red fill rising from
    // the BOTTOM, bright held-peak tick — a 90-degree reorientation of
    // RecipeRenderer._drawMeter (upstream's meter is horizontal, filling
    // left-to-right; the reference screenshot's is vertical) with the same
    // gradient stop positions and colors.
    function _drawMeter(ctx, rect, peakDbfs, heldDbfs) {
        const fill = root._meterFill(peakDbfs);
        const heldFill = root._meterFill(heldDbfs);
        const radius = rect.w / 2;

        ctx.save();
        ctx.globalAlpha = 0.28;
        ctx.fillStyle = "rgba(255, 255, 255, 0.25)";
        root._paintRounded(ctx, rect.x, rect.y, rect.w, rect.h, radius);

        const fillH = rect.h * fill;
        const fillY = rect.y + rect.h - fillH;
        const grad = ctx.createLinearGradient(rect.x, rect.y + rect.h, rect.x, rect.y);
        grad.addColorStop(0.0, root.meterLowColor);
        grad.addColorStop(0.72, root.meterMidColor);
        grad.addColorStop(1.0, root.meterHighColor);
        ctx.globalAlpha = 1.0;
        ctx.fillStyle = grad;
        root._paintRounded(ctx, rect.x, fillY, rect.w, fillH, radius);

        if (heldFill > 0) {
            const tickY = rect.y + rect.h - rect.h * heldFill;
            ctx.fillStyle = root.waveformPeakColor;
            root._paintRounded(ctx, rect.x - 2, Math.max(rect.y, tickY - 1.5), rect.w + 4, 3, 2);
        }
        ctx.restore();
    }
    // Bound straight to shell.qml's dictationActive (the FileView-driven
    // state, not a separate concept) — this window has nothing else to be
    // "shown" FOR.
    property bool shown: false

    // Full-screen, anchored on all four sides — see RingOsdWindow's header
    // for why a fixed-margin small surface would be the wrong shape here
    // too: the plate below is positioned by anchors INSIDE this, so the
    // window itself never has to move when the plate does.
    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true

    color: "transparent"
    // Ignore, not `exclusiveZone: 0` — see RingOsdWindow.qml /
    // ScreenCornersWindow.qml for why the distinction matters: assigning
    // `exclusiveZone` at all is what puts a surface into Normal mode and
    // lays it out inside the island's reservation instead of the true
    // screen edges.
    exclusionMode: ExclusionMode.Ignore

    // THE INPUT MASK. Without this the surface is a fullscreen click sink
    // for as long as a dictation session runs. Region with no rects means
    // nothing on this surface is interactive.
    mask: Region {}

    // Mapped only while shown or mid-fade, same as RingOsdWindow — a
    // fullscreen transparent surface the compositor has to composite on
    // every frame is not free just because it draws nothing.
    visible: root.shown || fade.opacity > 0.01

    Item {
        id: fade
        anchors.fill: parent
        opacity: root.shown ? 1 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: root.shown ? Motion.fadeInDuration() : Motion.fadeOutDuration()
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Motion.fade()
            }
        }

        Rectangle {
            id: plate
            anchors.horizontalCenter: parent.horizontalCenter
            // Same fixed clearance off the bottom edge as RingOsdWindow's
            // plate, and the same measured reasoning: a fraction of
            // parent.height scales the gap with the screen instead of
            // holding it constant. Not stacked directly on top of the ring
            // OSD's own y (170px clearance) — dictation and a volume/
            // brightness adjustment are unlikely to overlap in practice, and
            // sharing the exact same shelf if they ever do is a harmless
            // coincidence, not a collision this needs to actively avoid.
            y: parent.height - height - Metrics.px(170)
            // Fixed, not content-hugging: a Canvas has no implicitWidth to
            // measure like waveformRow's old Row/SwipeCavaBars did. 340 is
            // narrower than Voxtype's own OsdConfig default (400px, see
            // Theme.qml defaultWidthPx) — chosen at this shell's own
            // Metrics.px() scale rather than reused verbatim, since 400
            // unscaled read too wide once actually placed on this bar.
            width: Metrics.px(340)
            height: Metrics.px(64)
            radius: height / 2
            // Same 0.97 as RingOsdWindow's plate, for the same reason: at
            // lower opacity text behind it stayed legible through it.
            color: Qt.rgba(root.shellFill.r, root.shellFill.g, root.shellFill.b, 0.97)

            border.width: 1
            border.color: IslandTheme.alpha(IslandTheme.ink, 0.07)

            scale: root.shown ? 1 : 0.96
            Behavior on scale {
                NumberAnimation {
                    duration: Motion.morphDuration()
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Motion.spring()
                }
            }

            // No mic glyph — the reference screenshot this feature clones
            // (Voxtype's own OSD) is just the waveform and the meter, no
            // icon; ati-voice-dictate-live's notify-send pill already
            // carries the 🎙 for the "did my keypress register" moment,
            // this OSD's job is only the live "you are being heard" trace.
            Canvas {
                id: waveformCanvas
                anchors.fill: parent
                anchors.margins: Metrics.px(14) // Theme.qml's own `padding: 14`.

                onPaint: {
                    const ctx = getContext("2d");
                    ctx.clearRect(0, 0, width, height);
                    const meterW = Metrics.px(10);
                    const gap = Metrics.px(10);
                    const waveRect = { x: 0, y: 0, w: Math.max(0, width - meterW - gap), h: height };
                    const meterRect = { x: width - meterW, y: 0, w: meterW, h: height };
                    root._drawWaveform(ctx, waveRect, root.ring);
                    root._drawMeter(ctx, meterRect, root.peakDbfs, root.heldDbfs);
                }
            }

            // 16ms — matches RecipeRenderer.qml's own paint cadence while its
            // daemonState is "recording". Only runs while shown, same as
            // every other animation on this plate.
            Timer {
                interval: 16
                repeat: true
                running: root.shown
                triggeredOnStart: true
                onTriggered: waveformCanvas.requestPaint()
            }
        }
    }
}
