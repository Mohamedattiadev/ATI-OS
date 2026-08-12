pragma ComponentBehavior: Bound

import QtQuick
import "../common/Metrics.js" as Metrics
import "../common"

//
// FORK — new file. The island's ring, extracted so more than one thing can
// draw it.
//
// WHERE IT CAME FROM
// ------------------
// It was drawn inline in qml/island/OsdLayer.qml — the little circle that
// rides beside the notch on a volume or brightness change, a dark dot with
// a track ring around it and a white arc sweeping from twelve o'clock. It
// was the best-looking element in the shell and it could only ever be one
// thing, because it was forty lines of Canvas in the middle of a layer that
// is about something else.
//
// "That circle is a good style — use it in other things" is the whole of
// why this file exists. Nothing about the drawing changed in the move; the
// numbers below are the ones OsdLayer used, promoted to properties.
//
// WHAT IS A PROPERTY AND WHAT IS NOT
// ----------------------------------
// `lineWidth` is deliberately NOT scaled through Metrics.px() by default.
// A stroke is the one dimension where the design value IS the right value:
// 3.5 px reads as a ring at 30 px across and still reads as a ring at 64,
// where a proportional stroke would go heavy and turn the hole in the
// middle into a dot. Callers that want a heavier ring say so.
//
// The centre is a `default property alias` rather than a fixed icon slot,
// so a caller can put a glyph, a number, or nothing in the middle without
// this file knowing what any of those are. OsdLayer puts nothing there and
// keeps its dark dot; the display panel's countdown puts the seconds in it.
//
Item {
    id: root

    // 0..1. Clamped here rather than at every call site — a progress ring
    // handed 1.2 should draw a full circle, not three-quarters of one after
    // the angle wraps.
    property real progress: 0
    readonly property real clampedProgress: Math.max(0, Math.min(1, progress))

    property real lineWidth: 3.5
    // Qt.rgba(), NOT the CSS string "rgba(255,255,255,0.16)" the inline
    // Canvas used. A Canvas strokeStyle is happy with CSS colour syntax; a
    // QML `color` PROPERTY is not, and rejects it with "Invalid property
    // assignment: color expected" — which fails the whole component, and
    // with it every parent up to shell.qml. Moving the value out of the
    // paint call and into a property is exactly what changed its type.
    property color trackColor: Qt.rgba(1, 1, 1, 0.16)
    property color fillColor: IslandTheme.textPrimary

    // The dark disc behind the arc. OsdLayer's ring has one; a ring drawn
    // over an already-dark panel does not need it, so it can be switched
    // off rather than being painted in a colour that hopes to match.
    property bool showCore: true
    property color coreColor: IslandTheme.surface
    property color coreBorderColor: IslandTheme.hairlineStrong

    default property alias centerContent: centerSlot.data

    implicitWidth: Metrics.px(30)
    implicitHeight: Metrics.px(30)

    Rectangle {
        anchors.centerIn: parent
        visible: root.showCore
        width: Math.round(Math.min(root.width, root.height) * 0.54)
        height: width
        radius: width / 2
        color: root.coreColor
        border.color: root.coreBorderColor
        border.width: 1
    }

    Canvas {
        id: canvas
        anchors.fill: parent
        antialiasing: true

        // Repainting is driven by every input the paint reads. A Canvas does
        // not repaint on a property change by itself, and a ring that only
        // updates when it happens to be resized is the failure this guards:
        // it looks correct on the first draw and then quietly stops
        // tracking, which is the hardest kind of wrong to notice.
        property real p: root.clampedProgress
        property real lw: root.lineWidth
        property color tc: root.trackColor
        property color fc: root.fillColor

        // ---- AND A REPAINT WHEN THE RING BECOMES VISIBLE AT ALL ----
        //
        // The list below guards against a ring that stops tracking its
        // inputs. It does NOT cover a ring created inside a parent that is
        // not visible yet, and that gap had a real symptom.
        //
        // A Canvas does not paint while it is invisible, and it does not
        // catch up on its own once it becomes visible — it waits for another
        // repaint request. The window strip builds its rings inside an Item
        // whose `visible` is false until the strip has windows and has faded
        // in, so every ring was created unpainted. The ones whose `progress`
        // then animated 0 -> 1 repainted as a SIDE EFFECT of onPChanged and
        // looked right; the ones that stayed at 0 never changed a painted
        // property again and stayed permanently blank.
        //
        // The symptom was "only the focused app has a ring, and no track is
        // ever drawn anywhere", which reads exactly like a colour or alpha
        // bug and is not one. Isolated by putting this component in a
        // throwaway window that was visible from creation: an opaque track
        // drew correctly at progress 0 there, while the identical colours
        // drew nothing in the live strip.
        onAvailableChanged: if (available) requestPaint()
        onVisibleChanged: if (visible) requestPaint()
        Component.onCompleted: requestPaint()

        onPChanged: requestPaint()
        onLwChanged: requestPaint()
        onTcChanged: requestPaint()
        onFcChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        onPaint: {
            const ctx = getContext("2d");
            const size = Math.min(width, height);
            const center = size / 2;
            const radius = (size - lw) / 2 - 0.5;
            if (radius <= 0)
                return;

            // Twelve o'clock, clockwise. Canvas puts zero at three o'clock,
            // which for a progress ring reads as starting a quarter of the
            // way round.
            const startAngle = -Math.PI / 2;
            const endAngle = startAngle + (Math.PI * 2 * p);

            ctx.clearRect(0, 0, width, height);
            ctx.lineCap = "round";
            ctx.lineWidth = lw;

            ctx.strokeStyle = tc;
            ctx.beginPath();
            ctx.arc(center, center, radius, 0, Math.PI * 2, false);
            ctx.stroke();

            // Skipped at zero: a round cap on a zero-length arc still paints
            // a dot at twelve o'clock, so an empty ring would show a bead
            // that looks like a small amount of progress.
            if (p > 0.001) {
                ctx.strokeStyle = fc;
                ctx.beginPath();
                ctx.arc(center, center, radius, startAngle, endAngle, false);
                ctx.stroke();
            }
        }
    }

    Item {
        id: centerSlot
        anchors.centerIn: parent
        width: Math.round(Math.min(root.width, root.height) * 0.62)
        height: width
    }
}
