import QtQuick
import IslandBackend

// FORK: one shared scale factor for every island surface.
// FORK: the shared ring lives in qml/common — see ProgressRing.qml.
import "../common"
import "../common/Metrics.js" as Metrics
// FORK: the shared motion system — one spring for geometry, one
// critically damped curve for opacity. See qml/common/Motion.js.
import "../common/Motion.js" as Motion

Item {
    id: root

    readonly property var userConfig: UserConfig

    property string iconText: ""
    property real progress: -1
    property string customText: ""
    property var configSource: null
    readonly property var activeConfig: configSource || userConfig
    property string iconFontFamily: activeConfig.iconFontFamily
    property string textFontFamily: activeConfig.textFontFamily
    property string heroFontFamily: activeConfig.heroFontFamily
    property string slideDirection: "none"
    property real transitionProgress: 0
    readonly property bool showProgress: progress >= 0
    readonly property bool showText: progress < 0 && customText !== ""
    property bool showCondition: false
    property real hiddenLeftPadding: Metrics.pad(16)
    property real hiddenRightPadding: Metrics.pad(16)
    readonly property real clampedProgress: slideDirection === "right"
        ? Math.max(0, Math.min(1, transitionProgress))
        : (slideDirection === "left"
            ? Math.max(0, Math.min(1, -transitionProgress))
            : 0)
    readonly property real revealProgress: slideDirection === "none" ? 1 : (1 - clampedProgress)
    readonly property real contentX: slideDirection === "right"
        ? (width + hiddenRightPadding) * clampedProgress
        : (slideDirection === "left"
            ? -(width + hiddenLeftPadding) * clampedProgress
            : 0)

    anchors.fill: parent
    clip: true
    opacity: showCondition ? revealProgress : 0

    // FORK: one choreography for every layer in the shell.
    // Was `showCondition ? 280 : 200` on Easing.InOutQuad — one of
    // eight hand-picked in-durations and six out-durations that agreed
    // with neither each other nor the 400 ms the shape takes. See
    // Motion.js, "CONTENT CHOREOGRAPHY", for the measurement.
    Behavior on opacity {
        enabled: slideDirection === "none"

        NumberAnimation {
            duration: showCondition ? Motion.fadeInDuration() : Motion.fadeOutDuration()
            // Critically damped: opacity is clamped 0-1 and an
            // overshooting fade reads as a cut. Motion.js says why.
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Motion.fade()
        }
    }

    Item {
        x: contentX
        width: parent.width
        height: parent.height
        visible: showProgress

        // FORK: the volume/brightness OSD, restyled onto the TIMER's ring
        // idiom — the ring is the element, with the glyph living inside it.
        //
        // What it was: icon and "74%" as a text pair on the left, and a
        // 30 px ring pushed against the right edge. Three separate things
        // reading left-to-right, and the ring — the only part that shows a
        // QUANTITY at a glance — was the smallest and furthest from where
        // the eye lands. The number carried all the information and the ring
        // was decoration beside it.
        //
        // The timer page had already solved this: one large ring with the
        // value centred in it (ExpandedPlayerLayer.qml ~line 798). That is
        // the shape a radial indicator wants, and ProgressRing was built for
        // it — `centerContent` is its default property alias and centreSlot
        // is sized to 62% of the ring, which is why the glyph needs no
        // measurements of its own here.
        //
        // The ring stays LEFT rather than moving to the timer's centre: this
        // capsule is the resting notch width, and a centred ring would put
        // the number where the clock normally is, so a volume nudge would
        // read as the clock changing.
        Row {
            anchors.left: parent.left
            anchors.leftMargin: Metrics.pad(16)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Metrics.px(13)

            // Sized off the capsule rather than a literal, so it stays a ring
            // inside the shape at any islandHeight the settings panel sets —
            // the height is user-editable now and a fixed 30 would overflow a
            // shorter notch and float in a taller one.
            Item {
                width: Math.round(root.height * 0.62)
                height: width
                anchors.verticalCenter: parent.verticalCenter

                ProgressRing {
                    anchors.fill: parent
                    progress: root.progress
                    // Thicker than the 3.5 default: at this diameter the
                    // default reads as a hairline outline rather than as a
                    // gauge, which is the same complaint in miniature.
                    lineWidth: Metrics.px(4)

                    // The glyph that says WHICH quantity this is, in the one
                    // place it cannot be mistaken for anything else.
                    Text {
                        anchors.centerIn: parent
                        text: root.iconText
                        color: "white"
                        font.pixelSize: root.userConfig.iconFontSize
                        font.family: root.iconFontFamily
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }

            Text {
                text: Math.round(root.progress * 100) + "%"
                color: "white"
                font.pixelSize: root.userConfig.titleFontSize
                font.family: root.heroFontFamily
                font.weight: Font.Bold
                font.letterSpacing: -0.35
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    Item {
        x: contentX
        width: parent.width
        height: parent.height
        visible: showText

        Row {
            anchors.centerIn: parent
            spacing: Metrics.px(14)

            Text {
                text: iconText
                color: "white"
                font.pixelSize: userConfig.iconFontSize
                font.family: iconFontFamily
                anchors.verticalCenter: parent.verticalCenter
            }

            Text {
                text: customText
                color: "white"
                font.pixelSize: userConfig.bodyFontSize
                font.family: textFontFamily
                font.weight: Font.DemiBold
                font.letterSpacing: -0.15
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }
}
