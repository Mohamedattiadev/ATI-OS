import QtQuick
import QtQuick.Controls
import QtQuick.Shapes
import IslandBackend
import "../controlcenter"

// FORK: one shared scale factor for every island surface.
import "../common/Metrics.js" as Metrics
// FORK: the shared motion system. See qml/common/Motion.js.
import "../common/Motion.js" as Motion
import "../common"

Item {
    id: root

    readonly property var userConfig: UserConfig

    property var notificationModel: null
    property string iconFontFamily: userConfig.iconFontFamily
    property string textFontFamily: userConfig.textFontFamily
    property string heroFontFamily: userConfig.heroFontFamily

    readonly property real headerHeight: 28
    readonly property real listTopGap: 9
    readonly property real cardHeight: 49
    readonly property real cardRadius: 16
    readonly property real cardGap: 7
    readonly property int maxVisibleItems: 3
    readonly property int itemCount: notificationModel ? notificationModel.count : 0
    readonly property bool hasNotifications: itemCount > 0
    readonly property real rawListContentHeight: hasNotifications
        ? itemCount * cardHeight + (itemCount - 1) * cardGap
        : 0
    readonly property real listContentHeight: Math.min(
        rawListContentHeight,
        maxVisibleItems * cardHeight + (maxVisibleItems - 1) * cardGap
    )

    Item {
        id: header

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: root.headerHeight

        Row {
            anchors.left: parent.left
            anchors.leftMargin: Metrics.pad(6)
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: 1
            spacing: Metrics.px(8)

            Item {
                width: Metrics.px(18)
                height: Metrics.px(18)

                Shape {
                    width: Metrics.px(24)
                    height: Metrics.px(24)
                    scale: 0.75
                    transformOrigin: Item.TopLeft
                    preferredRendererType: Shape.CurveRenderer

                    ShapePath {
                        fillColor: "transparent"
                        strokeColor: IslandTheme.textSecondary
                        strokeWidth: 1.8
                        capStyle: ShapePath.RoundCap
                        joinStyle: ShapePath.RoundJoin

                        PathSvg {
                            path: "M3.7 8.2V3.9 M3.7 3.9H8 M3.7 3.9l3 3 M4 12a8.3 8.3 0 1 0 2.7-6.1"
                        }
                    }

                    ShapePath {
                        fillColor: "transparent"
                        strokeColor: IslandTheme.textSecondary
                        strokeWidth: 1.8
                        capStyle: ShapePath.RoundCap
                        joinStyle: ShapePath.RoundJoin

                        PathSvg {
                            path: "M12 7.5V12l3 1.8"
                        }
                    }
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Notification History"
                textFormat: Text.PlainText
                color: IslandTheme.textPrimary
                font.pixelSize: Metrics.font(15)
                font.family: root.textFontFamily
                font.weight: Font.Bold
                font.letterSpacing: 0.1
            }
        }
    }

    Item {
        id: listViewport

        anchors.top: header.bottom
        anchors.topMargin: root.listTopGap
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        clip: true

        Text {
            visible: !root.hasNotifications
            anchors.centerIn: parent
            text: "No notifications"
            textFormat: Text.PlainText
            color: IslandTheme.textDisabled
            font.pixelSize: Metrics.font(10)
            font.family: root.textFontFamily
            font.weight: Font.Medium
        }

        ListView {
            id: listView

            anchors.fill: parent
            visible: root.hasNotifications
            clip: true
            interactive: contentHeight > height
            boundsBehavior: Flickable.StopAtBounds
            model: root.notificationModel
            currentIndex: -1
            spacing: root.cardGap

            remove: Transition {
                ParallelAnimation {
                    NumberAnimation {
                        property: "opacity"
                        to: 0
                        duration: 170
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Motion.fade()   // FORK: was Easing.InOutCubic
                    }

                    NumberAnimation {
                        property: "scale"
                        to: 0.94
                        duration: 190
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Motion.spring()   // FORK: was Easing.InOutCubic
                    }
                }
            }

            removeDisplaced: Transition {
                NumberAnimation {
                    properties: "x,y"
                    duration: 260
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Motion.spring()   // FORK: was Easing.OutCubic
                }
            }

            ScrollBar.vertical: ScrollBar {
                active: listView.moving || listView.dragging
                policy: ScrollBar.AsNeeded
                width: Metrics.px(3)

                contentItem: Rectangle {
                    radius: Metrics.px(1.5)
                    color: IslandTheme.textDisabled
                }

                background: Rectangle {
                    color: "transparent"
                }
            }

            delegate: Item {
                id: delegateItem

                width: listView.width
                height: root.cardHeight

                readonly property string titleText: model.summary !== ""
                    ? model.summary
                    : "Notification"
                readonly property string bodyText: model.body !== "" && model.body !== model.summary
                    ? model.body
                    : ""

                MatteSurface {
                    anchors.fill: parent
                    radius: root.cardRadius
                    hovered: cardMouse.containsMouse
                    pressed: cardMouse.pressed
                }

                Item {
                    anchors.left: parent.left
                    anchors.leftMargin: Metrics.pad(16)
                    anchors.right: parent.right
                    anchors.rightMargin: Metrics.pad(16)
                    anchors.top: parent.top
                    anchors.topMargin: Metrics.pad(3)
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: Metrics.pad(6)

                    Text {
                        anchors.top: parent.top
                        width: parent.width
                        height: Metrics.px(18)
                        text: delegateItem.titleText
                        textFormat: Text.PlainText
                        color: IslandTheme.textPrimary
                        font.pixelSize: Metrics.font(15)
                        font.family: root.textFontFamily
                        font.weight: Font.Bold
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                    }

                    Text {
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: Metrics.px(16)
                        text: delegateItem.bodyText
                        textFormat: Text.PlainText
                        color: IslandTheme.textSecondary
                        font.pixelSize: Metrics.font(13)
                        font.family: root.textFontFamily
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                    }
                }

                MouseArea {
                    id: cardMouse

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (root.notificationModel && index >= 0 && index < root.notificationModel.count)
                            root.notificationModel.remove(index);
                    }
                }
            }
        }
    }
}
