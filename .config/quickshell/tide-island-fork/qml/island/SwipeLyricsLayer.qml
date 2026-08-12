import QtQuick
import Qt5Compat.GraphicalEffects
import IslandBackend

// FORK: one shared scale factor for every island surface.
import "../common/Metrics.js" as Metrics
// FORK: the shared motion system — one spring for geometry, one
// critically damped curve for opacity. See qml/common/Motion.js.
import "../common/Motion.js" as Motion

Item {
    id: root

    readonly property var userConfig: UserConfig

    property string lyricText: ""
    property string currentArtUrl: ""
    property var cavaLevels: []
    property string timeText: ""
    property var configSource: null
    readonly property var activeConfig: configSource || userConfig
    property string textFontFamily: activeConfig.textFontFamily
    property string timeFontFamily: activeConfig.timeFontFamily
    property bool showCondition: false
    property bool showSecondaryText: true
    // FORK: whether sound is actually coming out right now, not whether a
    // player exists. Gates the resting EQ — see restingEq below.
    property bool musicPlaying: false
    property bool recordingActive: false
    property real transitionProgress: 0
    property int textPixelSize: userConfig.bodyFontSize
    property real minimumWidth: Metrics.px(220)
    property real maximumWidth: minimumWidth
    property real horizontalPadding: Metrics.pad(14)
    property real coverSize: Metrics.px(24)
    property real coverRadius: Metrics.px(7)
    property real visualSpacing: Metrics.px(35)
    property real hiddenLeftPadding: Metrics.pad(18)
    property real hiddenRightPadding: Metrics.pad(16)
    property string activeLyricText: lyricText
    property string previousLyricText: ""
    property real lyricChangeProgress: 1
    property int recordingDotSpacing: 12

    // Gap between the clock and the resting EQ, and the total the collapsed
    // capsule has to grow by to fit it. Exported so DynamicIslandWindow can
    // widen the capsule on the same spring rather than clipping the bars.
    readonly property real restingEqGap: 7
    readonly property real restingEqWidth: 4 * 3 + 3 * 3
    readonly property real restingEqAllowance: restingEqWidth + restingEqGap
    // The clock and the EQ are one centred group, so the clock slides left
    // by half the allowance when the bars appear rather than staying put
    // and letting the pair sit off-centre. Animated on its own short curve
    // because it is content shifting inside the capsule, not the capsule
    // moving — those two settling at different times is what makes the
    // bars look bolted on.
    readonly property real restingGroupShift:
        (musicPlaying && showSecondaryText) ? restingEqAllowance / 2 : 0

    readonly property real clampedProgress: Math.max(0, Math.min(1, transitionProgress))
    readonly property bool lyricMostlyVisible: clampedProgress > 0.92
    readonly property real textWidth: Math.max(0, width - horizontalPadding * 2)
    readonly property real lyricTextWidth: Math.max(
        0,
        textWidth - coverSize - cavaBars.implicitWidth - visualSpacing * 2
    )
    readonly property real centeredX: horizontalPadding
    readonly property real lyricHiddenLeftX: -textWidth - hiddenLeftPadding
    readonly property real timeHiddenRightX: width + hiddenRightPadding
    readonly property real lyricEntryDistance: Math.max(0, centeredX - lyricHiddenLeftX)
    readonly property real timeExitDistance: Math.max(0, timeHiddenRightX - centeredX)
    readonly property real dragDistance: Math.max(lyricEntryDistance, timeExitDistance)
    readonly property real lyricX: centeredX - (1 - clampedProgress) * dragDistance
    readonly property real timeX: centeredX + clampedProgress * dragDistance
    property real animatedGroupShift: restingGroupShift
    readonly property real shiftedTimeX: timeX - animatedGroupShift

    Behavior on animatedGroupShift {
        NumberAnimation {
            duration: 180
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Motion.spring()   // FORK: was Easing.InOutQuad
        }
    }
    readonly property real lyricBaselineY: lyricBaselineGuide.y + lyricBaselineGuide.baselineOffset
    readonly property real timeBaselineY: timeBaselineGuide.y + timeBaselineGuide.baselineOffset
    readonly property real visibleLyricWidth: Math.min(lyricTextWidth, Math.max(0, lyricMetrics.advanceWidth))
    readonly property real visibleTimeWidth: Math.min(textWidth, Math.max(0, timeMetrics.advanceWidth))
    readonly property real timeRecordingDotX: Math.max(
        4,
        timeX + (textWidth - visibleTimeWidth) / 2 - recordingDotSpacing - timeRecordingIndicator.width
    )
    readonly property real preferredWidth: Math.max(
        minimumWidth,
        Math.min(
            Math.max(minimumWidth, maximumWidth),
            lyricMetrics.advanceWidth
                + horizontalPadding * 2
                + coverSize
                + cavaBars.implicitWidth
                + visualSpacing * 2
        )
    )

    onLyricTextChanged: {
        if (lyricText === activeLyricText) return;

        if (activeLyricText === "" || !lyricMostlyVisible) {
            lyricChangeAnimation.stop();
            previousLyricText = "";
            activeLyricText = lyricText;
            lyricChangeProgress = 1;
            return;
        }

        previousLyricText = activeLyricText;
        activeLyricText = lyricText;
        lyricChangeProgress = 0;
        lyricChangeAnimation.restart();
    }

    onShowConditionChanged: {
        if (showCondition) return;
        lyricChangeAnimation.stop();
        previousLyricText = "";
        activeLyricText = lyricText;
        lyricChangeProgress = 1;
    }

    onTransitionProgressChanged: {
        if (lyricMostlyVisible) return;
        lyricChangeAnimation.stop();
        previousLyricText = "";
        activeLyricText = lyricText;
        lyricChangeProgress = 1;
    }

    anchors.fill: parent
    clip: true
    opacity: showCondition ? 1 : 0

    // FORK: one choreography for every layer in the shell.
    // Was `showCondition ? 220 : 140` on Easing.InOutQuad — one of
    // eight hand-picked in-durations and six out-durations that agreed
    // with neither each other nor the 400 ms the shape takes. See
    // Motion.js, "CONTENT CHOREOGRAPHY", for the measurement.
    Behavior on opacity {
        NumberAnimation {
            duration: showCondition ? Motion.fadeInDuration() : Motion.fadeOutDuration()
            // Critically damped: opacity is clamped 0-1 and an
            // overshooting fade reads as a cut. Motion.js says why.
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Motion.fade()
        }
    }

    TextMetrics {
        id: lyricMetrics
        font.family: textFontFamily
        font.pixelSize: textPixelSize
        font.weight: Font.DemiBold
        text: activeLyricText !== "" ? activeLyricText : lyricText
    }

    TextMetrics {
        id: timeMetrics
        font.family: timeFontFamily
        font.pixelSize: textPixelSize + 1
        font.weight: Font.Bold
        text: timeText
    }

    Text {
        id: lyricBaselineGuide
        anchors.verticalCenter: parent.verticalCenter
        text: "Ag国"
        opacity: 0
        font.pixelSize: textPixelSize
        font.family: textFontFamily
        font.weight: Font.DemiBold
        font.letterSpacing: -0.15
        wrapMode: Text.NoWrap
    }

    Text {
        id: timeBaselineGuide
        anchors.verticalCenter: parent.verticalCenter
        text: "00:00"
        opacity: 0
        font.pixelSize: textPixelSize + 1
        font.family: timeFontFamily
        font.weight: Font.Bold
        font.letterSpacing: -0.25
        wrapMode: Text.NoWrap
    }

    SequentialAnimation {
        id: lyricChangeAnimation

        NumberAnimation {
            target: root
            property: "lyricChangeProgress"
            from: 0
            to: 1
            duration: 260
            // Drives a CROSSFADE between two lyric lines, so it is opacity in
            // all but name and must not overshoot: past 1 the outgoing line
            // has already been discarded and the incoming one clips flat.
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Motion.fade()   // FORK: was Easing.OutCubic
        }

        ScriptAction {
            script: root.previousLyricText = ""
        }
    }

    Item {
        id: lyricContent

        x: root.lyricX
        width: root.textWidth
        height: parent.height
        opacity: root.clampedProgress

        Rectangle {
            id: coverFrame

            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: root.coverSize
            height: root.coverSize
            radius: root.coverRadius
            color: "#2c2c2e"
            antialiasing: true

            Rectangle {
                id: coverMask

                anchors.fill: parent
                radius: root.coverRadius
                antialiasing: true
                visible: false
                layer.enabled: true
            }

            Image {
                anchors.fill: parent
                source: root.currentArtUrl
                fillMode: Image.PreserveAspectCrop
                visible: source.toString() !== ""
                sourceSize: Qt.size(root.coverSize * 2, root.coverSize * 2)
                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: coverMask
                }
            }
        }

        Item {
            id: lyricViewport

            anchors.left: coverFrame.right
            anchors.leftMargin: root.visualSpacing
            anchors.right: cavaBars.left
            anchors.rightMargin: root.visualSpacing
            height: parent.height
            clip: true

            Text {
                visible: root.previousLyricText !== ""
                y: root.lyricBaselineY - baselineOffset - 14 * root.lyricChangeProgress
                width: parent.width
                text: root.previousLyricText
                color: "white"
                opacity: 1 - root.lyricChangeProgress
                font.pixelSize: root.textPixelSize
                font.family: root.textFontFamily
                font.weight: Font.DemiBold
                font.letterSpacing: -0.15
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                wrapMode: Text.NoWrap
            }

            Text {
                visible: root.activeLyricText !== ""
                y: root.lyricBaselineY - baselineOffset
                    + (root.previousLyricText !== "" ? 12 * (1 - root.lyricChangeProgress) : 0)
                width: parent.width
                text: root.activeLyricText
                color: "white"
                opacity: root.previousLyricText !== "" ? root.lyricChangeProgress : 1
                font.pixelSize: root.textPixelSize
                font.family: root.textFontFamily
                font.weight: Font.DemiBold
                font.letterSpacing: -0.15
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                wrapMode: Text.NoWrap
            }
        }

        SwipeCavaBars {
            id: cavaBars

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            levels: root.cavaLevels
            barCount: 5
            barWidth: Metrics.px(3)
            barSpacing: Metrics.px(3)
            minimumBarHeight: Metrics.px(4)
            barColor: "white"
        }
    }

    Text {
        visible: timeText !== "" && showSecondaryText
        x: shiftedTimeX
        y: timeBaselineY - baselineOffset
        width: textWidth
        text: timeText
        color: "white"
        opacity: 1 - clampedProgress
        font.pixelSize: textPixelSize + 1
        font.family: timeFontFamily
        font.weight: Font.Bold
        font.letterSpacing: -0.25
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        wrapMode: Text.NoWrap
    }

    // FORK: the resting-state EQ. DESIGN-SPEC.md's resting island shows
    // exactly two things — "the time, and a 4-bar EQ visualiser that
    // animates only while music actually plays".
    //
    // Upstream already draws cava bars, but only inside the lyrics row,
    // which lives at clampedProgress 1 — i.e. only after you swipe. At
    // rest that row is fully transparent and all you get is the clock.
    // This is a second, smaller instance that lives on the clock's side of
    // the crossfade instead: its opacity is 1 - clampedProgress, exactly
    // like the time text, so swiping to lyrics hands the EQ over to the
    // big one rather than showing two.
    //
    // Four bars, not upstream's five, because the spec says four and
    // because the collapsed capsule is 96 px wide on this panel — the
    // fifth bar costs 6 px that the clock needs.
    //
    // "Animates only while music plays" is taken literally: with nothing
    // playing the bars are not idling at their minimum height, they are
    // gone, and the capsule is just a clock. cavaLevels stays pinned at
    // zero unless the cava module is present, so a flat row of dots would
    // have been the permanent state on a machine without it — a
    // decoration that never moves, which is the exact trade the spec
    // deletes battery and Wi-Fi for.
    SwipeCavaBars {
        id: restingEq
        levels: root.cavaLevels
        barCount: 4
        barWidth: Metrics.px(3)
        barSpacing: Metrics.px(3)
        minimumBarHeight: Metrics.px(3)
        barColor: "white"
        height: Metrics.px(14)

        readonly property bool shown: root.musicPlaying && root.showSecondaryText

        anchors.verticalCenter: parent.verticalCenter
        // Sits just right of the clock's own ink, not of its full-width
        // centred box, so the pair reads as one centred group.
        x: root.shiftedTimeX + (root.textWidth + root.visibleTimeWidth) / 2 + root.restingEqGap
        opacity: shown ? (1 - root.clampedProgress) : 0
        visible: opacity > 0.001

        Behavior on opacity {
            NumberAnimation {
                duration: 180
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Motion.fade()   // FORK: was Easing.InOutQuad
            }
        }
    }

    RecordingIndicator {
        id: timeRecordingIndicator
        active: root.recordingActive
            && root.showSecondaryText
            && root.timeText !== ""
            && root.clampedProgress < 0.001
        contentOpacity: 1 - root.clampedProgress
        x: root.timeRecordingDotX
        anchors.verticalCenter: parent.verticalCenter
    }
}
