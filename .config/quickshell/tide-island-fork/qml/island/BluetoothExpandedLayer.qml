import QtQuick
import IslandBackend

// FORK: one shared scale factor for every island surface.
import "../common/Metrics.js" as Metrics
// FORK: the shared motion system — one spring for geometry, one
// critically damped curve for opacity. See qml/common/Motion.js.
import "../common/Motion.js" as Motion
import "../common"

Item {
    id: root

    readonly property var userConfig: UserConfig

    property bool showCondition: false
    property var device: null
    property real volumeLevel: -1
    property string iconText: ""
    property string iconFontFamily: ""
    property string textFontFamily: ""

    readonly property string deviceName: {
        if (!device) return "Bluetooth device";

        const preferred = String(device.deviceName === undefined || device.deviceName === null ? "" : device.deviceName).trim();
        if (preferred.length > 0) return preferred;

        const alias = String(device.name === undefined || device.name === null ? "" : device.name).trim();
        if (alias.length > 0) return alias;

        const address = String(device.address === undefined || device.address === null ? "" : device.address).trim();
        return address.length > 0 ? address : "Bluetooth device";
    }
    readonly property bool batteryAvailable: !!(device && device.batteryAvailable)
    readonly property real batteryRawValue: batteryAvailable ? Math.max(0, Number(device.battery) || 0) : -1
    readonly property int batteryPercent: batteryAvailable
        ? Math.max(0, Math.min(100, Math.round(batteryRawValue <= 1 ? batteryRawValue * 100 : batteryRawValue)))
        : -1
    readonly property bool volumeAvailable: volumeLevel >= 0
    readonly property int volumePercent: volumeAvailable
        ? Math.max(0, Math.min(100, Math.round(volumeLevel * 100)))
        : -1
    // ONE OF THE FOUR DELIBERATE EXCEPTIONS TO THE TOKEN LAYER.
    //
    // Everything else in this file now reads IslandTheme. This ladder does
    // not, and must not: here the colour IS the reading. A user glances at
    // a red bar and knows to charge the headphones — nobody reads the
    // number. Bound to IslandTheme.danger/warning/success it would be
    // gruvbox yellow at 10% on one theme and matrix green at 10% on
    // another, i.e. "10% battery" rendered in the colour of "fine".
    //
    // The other three are listed in qml/common/IslandTheme.qml: the Wi-Fi
    // QR card, the theme picker's 22 tiles, and the theme-transition
    // overlay.
    readonly property color batteryColor: {
        if (!batteryAvailable) return "#5d6068";
        if (batteryPercent <= 10) return "#ff3b30";
        if (batteryPercent <= 20) return "#ffcc00";
        return "#34c759";
    }

    anchors.fill: parent
    anchors.margins: Metrics.pad(20)
    opacity: showCondition ? 1 : 0

    // FORK: one choreography for every layer in the shell.
    // Was `showCondition ? 260 : 100` on Easing.InOutQuad — one of
    // eight hand-picked in-durations and six out-durations that agreed
    // with neither each other nor the 400 ms the shape takes. See
    // Motion.js, "CONTENT CHOREOGRAPHY", for the measurement.
    Behavior on opacity {
        SequentialAnimation {
            // The delay is what keeps the content from being painted
            // inside a capsule that is still the wrong size for it.
            PauseAnimation { duration: showCondition ? Motion.contentDelay() : 0 }
            NumberAnimation {
                duration: showCondition ? Motion.fadeInDuration() : Motion.fadeOutDuration()
                // Critically damped: opacity is clamped 0-1 and an
                // overshooting fade reads as a cut. Motion.js says why.
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Motion.fade()
            }
        }
    }

    Column {
        anchors.fill: parent
        spacing: Metrics.px(16)

        Item {
            width: parent.width
            height: Metrics.px(66)

            Item {
                id: bluetoothIcon
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: Metrics.px(44)
                height: Metrics.px(58)

                Text {
                    anchors.centerIn: parent
                    text: root.iconText
                    color: IslandTheme.accent
                    font.pixelSize: userConfig.iconFontSize + Metrics.px(16)
                    font.family: root.iconFontFamily
                }
            }

            Item {
                id: batteryIcon
                anchors.right: parent.right
                y: infoBlock.y + Math.round((nameLine.height - height) / 2)
                width: Metrics.px(28)
                height: Metrics.px(14)

                Rectangle {
                    anchors.fill: parent
                    anchors.rightMargin: Metrics.pad(2)
                    radius: Metrics.px(4)
                    color: "transparent"
                    border.color: IslandTheme.textSecondary
                    border.width: 1

                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.margins: Metrics.pad(2)
                        radius: Metrics.px(2)
                        width: root.batteryAvailable ? (parent.width - 4) * (root.batteryPercent / 100.0) : 0
                        color: root.batteryColor

                        Behavior on width {
                            NumberAnimation {
                                duration: 300
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Motion.spring()   // FORK: was Easing.OutCubic
                            }
                        }

                        Behavior on color {
                            ColorAnimation { duration: 160 }
                        }
                    }
                }

                Rectangle {
                    width: Metrics.px(2)
                    height: Metrics.px(6)
                    radius: 1
                    color: IslandTheme.textSecondary
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            Item {
                id: infoBlock
                anchors.left: bluetoothIcon.right
                anchors.leftMargin: Metrics.pad(12)
                anchors.right: batteryIcon.left
                anchors.rightMargin: Metrics.pad(4)
                anchors.verticalCenter: parent.verticalCenter
                height: Metrics.px(44)

                Row {
                    id: nameLine
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    height: Metrics.px(22)
                    spacing: Metrics.px(8)

                    Text {
                        width: Math.max(0, parent.width - batteryText.implicitWidth - parent.spacing)
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.deviceName
                        color: IslandTheme.textPrimary
                        font.pixelSize: userConfig.bodyFontSize - 1
                        font.family: root.textFontFamily
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }

                    Text {
                        id: batteryText
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.batteryAvailable ? root.batteryPercent + "%" : "--"
                        color: root.batteryAvailable ? IslandTheme.textSecondary : IslandTheme.textMuted
                        font.pixelSize: userConfig.bodyFontSize - 3
                        font.family: root.textFontFamily
                        font.weight: Font.DemiBold
                    }
                }

                Text {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    text: "Connected"
                    color: IslandTheme.success
                    font.pixelSize: userConfig.bodyFontSize - 4
                    font.family: root.textFontFamily
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                }
            }
        }

        Item {
            width: parent.width
            height: Metrics.px(43)

            Text {
                id: volumeLabel
                anchors.left: parent.left
                anchors.leftMargin: Metrics.pad(12)
                anchors.baseline: volumeValue.baseline
                text: "vol"
                color: IslandTheme.textPrimary
                font.pixelSize: Metrics.font(12)
                font.family: root.textFontFamily
                font.weight: Font.Medium
            }

            Text {
                id: volumeValue
                anchors.right: parent.right
                anchors.rightMargin: Metrics.pad(12)
                anchors.verticalCenter: volumeTrack.verticalCenter
                text: root.volumeAvailable ? root.volumePercent : "--"
                color: IslandTheme.textSecondary
                font.pixelSize: Metrics.font(12)
                font.family: root.textFontFamily
                font.weight: Font.Medium
            }

            Rectangle {
                id: volumeTrack
                anchors.left: volumeLabel.right
                anchors.leftMargin: Metrics.pad(14)
                anchors.right: volumeValue.left
                anchors.rightMargin: Metrics.pad(14)
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Metrics.pad(15)
                height: Metrics.px(8)
                radius: Metrics.px(4)
                color: IslandTheme.surfaceRaised

                Rectangle {
                    width: root.volumeAvailable ? parent.width * (root.volumePercent / 100.0) : 0
                    height: parent.height
                    radius: parent.radius
                    color: IslandTheme.textPrimary

                    Behavior on width {
                        NumberAnimation {
                            duration: 260
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Motion.spring()   // FORK: was Easing.OutCubic
                        }
                    }
                }
            }
        }
    }
}
