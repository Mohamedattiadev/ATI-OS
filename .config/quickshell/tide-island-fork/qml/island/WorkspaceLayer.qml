import QtQuick
import IslandBackend

// FORK: one shared scale factor for every island surface.
import "../common/Metrics.js" as Metrics
// FORK: IslandTheme, for the text colour — see the sweep that removed the
// 29 hardcoded `color: "white"` from this tree.
import "../common"
// FORK: the shared motion system — one spring for geometry, one
// critically damped curve for opacity. See qml/common/Motion.js.
import "../common/Motion.js" as Motion

Item {
    id: root

    readonly property var userConfig: UserConfig

    property int workspaceId: 1
    property string displayText: "Workspace " + workspaceId
    property var configSource: null
    readonly property var activeConfig: configSource || userConfig
    property string textFontFamily: activeConfig.textFontFamily
    property bool showCondition: false
    property int textPixelSize: userConfig.bodyFontSize
    property string slideDirection: "none"
    property bool animateVisibility: true
    property real transitionProgress: 0
    property real horizontalPadding: Metrics.pad(14)
    property real hiddenLeftPadding: Metrics.pad(16)
    property real hiddenRightPadding: Metrics.pad(16)

    readonly property real clampedProgress: slideDirection === "right"
        ? Math.max(0, Math.min(1, transitionProgress))
        : (slideDirection === "left"
            ? Math.max(0, Math.min(1, -transitionProgress))
            : 0)
    readonly property real revealProgress: slideDirection === "none" ? 1 : (1 - clampedProgress)
    readonly property real textWidth: Math.max(0, width - horizontalPadding * 2)
    readonly property real centeredX: horizontalPadding
    readonly property real hiddenLeftX: -textWidth - hiddenLeftPadding
    readonly property real hiddenRightX: width + hiddenRightPadding
    readonly property real labelX: slideDirection === "right"
        ? centeredX + (hiddenRightX - centeredX) * clampedProgress
        : (slideDirection === "left"
            ? centeredX + (hiddenLeftX - centeredX) * clampedProgress
            : centeredX)

    anchors.fill: parent
    clip: true
    opacity: showCondition ? (animateVisibility ? revealProgress : 1) : 0

    // FORK: one choreography for every layer in the shell.
    // Was `showCondition ? 300 : 100` on Easing.InOutQuad — one of
    // eight hand-picked in-durations and six out-durations that agreed
    // with neither each other nor the 400 ms the shape takes. See
    // Motion.js, "CONTENT CHOREOGRAPHY", for the measurement.
    Behavior on opacity {
        enabled: animateVisibility

        NumberAnimation {
            duration: showCondition ? Motion.fadeInDuration() : Motion.fadeOutDuration()
            // Critically damped: opacity is clamped 0-1 and an
            // overshooting fade reads as a cut. Motion.js says why.
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Motion.fade()
        }
    }

    Text {
        x: labelX
        width: textWidth
        anchors.verticalCenter: parent.verticalCenter
        text: displayText
        color: IslandTheme.textPrimary
        opacity: revealProgress
        font.pixelSize: textPixelSize
        font.family: textFontFamily
        font.weight: Font.DemiBold
        font.letterSpacing: -0.15
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        wrapMode: Text.NoWrap
    }
}
