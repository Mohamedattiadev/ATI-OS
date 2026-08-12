import QtQuick
import IslandBackend

// FORK: one shared scale factor for every island surface.
import "../common/Metrics.js" as Metrics

Rectangle {
    id: root

    signal interactionStarted()
    signal valueMoved(real value)
    signal commitRequested()
    signal cancelRequested()

    property string title: ""
    property string iconText: ""
    property string iconFontFamily: ""
    property string textFontFamily: ""
    property real value: 0
    property real knobSize: 24
    property color moduleColor: StyleTokens.module
    property color moduleHover: StyleTokens.moduleHover
    property color trackColor: StyleTokens.track
    property color textPrimary: StyleTokens.textPrimary
    property color textSecondary: StyleTokens.textSecondary
    readonly property bool pressed: sliderArea.pressed

    function clamp01(nextValue) {
        return Math.max(0, Math.min(1, nextValue));
    }

    radius: Metrics.px(24)
    color: StyleTokens.clearBlack
    clip: true

    MatteSurface {
        anchors.fill: parent
        radius: root.radius
        hovered: sliderArea.containsMouse
        pressed: sliderArea.pressed
    }

    Item {
        anchors.fill: parent
        anchors.margins: Metrics.pad(12)

        Text {
            anchors.left: parent.left
            anchors.top: parent.top
            text: root.title
            color: root.textPrimary
            font.pixelSize: Metrics.font(13)
            font.family: root.textFontFamily
            font.weight: Font.DemiBold
        }

        Rectangle {
            id: sliderTrack
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            // FORK: 22 -> 30. The card is Metrics.px(76) = 70 tall and was
            // spending 20 of that on the track and the rest on nothing: a
            // 13px label at the top, a 20px bar at the bottom, and a ~25px
            // band of empty module colour between them that reads as a
            // half-drawn card. macOS's own control-centre sliders are a
            // TRACK with a label over it, not a label with a hairline under
            // it. 30 makes the track the body of the card, which is also
            // what makes the icon inside it legible at 13px.
            height: Metrics.px(30)
            radius: height / 2
            color: "#1d1f24"
            border.width: 1
            border.color: "#30333a"
            clip: true

            Rectangle {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Metrics.pad(10)
                width: Metrics.px(22)
                height: Metrics.px(22)
                radius: width / 2
                color: StyleTokens.transparent

                Text {
                    anchors.centerIn: parent
                    text: root.iconText
                    color: root.textSecondary
                    font.pixelSize: Metrics.font(13)
                    font.family: root.iconFontFamily
                }
            }

            Rectangle {
                // Floors at the track height rather than at a bare 34, so a
                // near-zero value still draws a ROUND cap instead of a
                // lozenge narrower than its own corner radius.
                width: root.value <= 0.001
                    ? 0
                    : Math.max(sliderTrack.height, Math.min(sliderTrack.width, sliderTrack.width * root.value + 1))
                height: parent.height
                radius: parent.radius
                color: "#eceef2"
            }

            Rectangle {
                x: Math.max(0, Math.min(parent.width - width, parent.width * root.value - width / 2))
                y: -1
                width: root.knobSize
                height: root.knobSize
                radius: root.knobSize / 2
                border.width: 1
                border.color: "#b8ffffff"
                color: "#f4f5f7"
            }

            MouseArea {
                id: sliderArea
                anchors.fill: parent
                hoverEnabled: true

                function update(mouseX) {
                    root.valueMoved(root.clamp01(mouseX / width));
                }

                onPressed: function(mouse) {
                    root.interactionStarted();
                    update(mouse.x);
                }
                onPositionChanged: function(mouse) {
                    if (pressed)
                        update(mouse.x);
                }
                onReleased: root.commitRequested()
                onCanceled: root.cancelRequested()
            }
        }
    }
}
