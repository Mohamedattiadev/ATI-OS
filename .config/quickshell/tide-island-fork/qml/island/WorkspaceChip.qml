import QtQuick

import "../common/Metrics.js" as Metrics
import "../common/Motion.js" as Motion

//
// FORK — new file. The persistent "which workspace am I on" readout.
//
// WHY IT IS NOT INSIDE THE PILL
// -----------------------------
// The island already had a workspace display: WorkspaceLayer.qml, the
// "Workspace 5" long capsule that appears for a moment when you switch and
// then goes away. That answers "did the switch happen", which is a different
// question from "where am I", and it answers it only in the two seconds when
// you already know.
//
// The obvious fix is to put a number in the resting capsule beside the
// clock. That capsule is `islandWidth` wide — 135 px on this machine, and
// already holding a 24-hour clock plus, when music plays, four EQ bars it
// had to grow `restingEqAllowance` to fit. Adding a second permanent
// occupant means widening it again, and every one of the ~20 `islandState`
// cases in mainCapsule.baseTargetWidth is arithmetic against that width.
//
// So the chip is a SIBLING of mainCapsule, not a child, sitting in the empty
// bar to its left. The layer surface is the full screen width (1366 px here)
// against a 135 px pill, so there are ~615 px of unused bar on each side;
// this costs the capsule nothing and cannot perturb a morph.
//
// IT IS NOT INTERACTIVE, BY CONSTRUCTION
// --------------------------------------
// The island window's input Region is built from mainCapsule's rectangle
// alone (see the mask near the top of DynamicIslandWindow.qml). Anything
// outside that rectangle is drawn but unclickable, which is exactly right
// for a readout — and it means this cannot steal a click from the desktop
// the way a naive full-width surface would.
//
Item {
    id: root

    // 0 when the island is hidden, 1 when it rests. Bound to the same
    // autoHideProgress the capsule uses so the chip cannot linger on screen
    // after the thing it belongs to has gone.
    property real revealProgress: 1
    property int workspaceId: 1
    property string textFontFamily: ""
    property color accentColor: "#51afef"
    property color fillColor: "#1a1a1a"
    property bool showCondition: true

    implicitWidth: chip.width
    implicitHeight: chip.height

    opacity: showCondition ? revealProgress : 0
    visible: opacity > 0.01

    Behavior on opacity {
        NumberAnimation {
            duration: root.showCondition ? Motion.fadeInDuration() : Motion.fadeOutDuration()
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Motion.fade()
        }
    }

    Rectangle {
        id: chip

        width: Math.max(Metrics.px(30), label.implicitWidth + Metrics.pad(18))
        height: Metrics.px(22)
        radius: height / 2

        // Reads as part of the island rather than as a separate widget: the
        // same shell fill, with the accent mixed in far enough to say "this
        // is the live one" and not so far that it competes with the pill.
        color: Qt.rgba(root.fillColor.r, root.fillColor.g, root.fillColor.b, 0.92)
        border.width: 1
        border.color: Qt.rgba(root.accentColor.r, root.accentColor.g,
                              root.accentColor.b, 0.45)

        // The number itself is accent-coloured. The chip is small enough
        // that a grey digit on a dark fill reads as disabled.
        Text {
            id: label
            anchors.centerIn: parent
            text: String(root.workspaceId)
            color: root.accentColor
            font.pixelSize: Metrics.font(12)
            font.family: root.textFontFamily
            font.weight: Font.DemiBold
            // Tabular figures would be ideal; Inter's default figures are
            // already tabular-width for digits, so a 1 and a 8 do not
            // resize the chip and make it twitch on every workspace change.
        }
    }
}
