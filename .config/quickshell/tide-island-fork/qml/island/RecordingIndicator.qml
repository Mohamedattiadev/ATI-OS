import QtQuick
// FORK: the shared motion system — one generated spring for geometry,
// one critically damped curve for opacity. See qml/common/Motion.js.
import "../common/Motion.js" as Motion
import "../common"

Item {
    id: root

    property bool active: false
    property real contentOpacity: 1
    property int dotSize: 4
    property color dotColor: IslandTheme.danger

    implicitWidth: dotSize
    implicitHeight: dotSize
    width: dotSize
    height: dotSize
    opacity: active ? contentOpacity : 0
    visible: active || opacity > 0.01

    // PROMPT-NEXT.md item 8's "the recording... glitching" triage. Measured
    // by reading the two animations against each other rather than assumed:
    // this used to reset `core.opacity` to 1.0 the INSTANT `active` went
    // false — a plain property set, no Behavior, so if the pulse was
    // mid-dim (say 0.35) that instant is a hard snap to full brightness. The
    // OUTER item's own opacity fades out smoothly over 220ms starting at the
    // same moment, so the visible result was a bright flash the frame the
    // dot starts disappearing. Delayed to fire after the outer fade-out has
    // actually finished, so the reset happens while the dot is already
    // invisible rather than while it is still on screen mid-fade.
    onActiveChanged: {
        if (!active)
            resetCoreOpacity.restart();
    }

    Timer {
        id: resetCoreOpacity
        interval: 220  // matches the fade-OUT duration below
        onTriggered: core.opacity = 1.0
    }

    Behavior on opacity {
        NumberAnimation {
            duration: root.active ? 180 : 220
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Motion.fade()   // FORK: was Easing.InOutQuad
        }
    }

    Rectangle {
        id: core
        width: root.dotSize
        height: root.dotSize
        anchors.centerIn: parent
        radius: width / 2
        color: root.dotColor
        opacity: 1.0
    }

    SequentialAnimation {
        running: root.active
        loops: Animation.Infinite

        PauseAnimation {
            duration: 110
        }

        NumberAnimation {
            target: core
            property: "opacity"
            to: 0.35
            duration: 980
            easing.type: Easing.InOutSine
        }

        PauseAnimation {
            duration: 120
        }

        NumberAnimation {
            target: core
            property: "opacity"
            to: 1.0
            duration: 1040
            easing.type: Easing.InOutSine
        }
    }
}
