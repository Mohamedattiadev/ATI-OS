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

    // FORK: the type here was hardcoded and had no hierarchy — the panel
    // heading and a card's TITLE were both Metrics.font(15) Bold, so a
    // notification shouted as loudly as the panel containing it, and the
    // card body was 13 while this shell's base body size is 12. Nothing in
    // the file read userConfig, so the notification centre was the one
    // surface that ignored `bodyFontSize` entirely: turning the shell's type
    // down left this panel exactly where it was. That is the "font too big".
    readonly property int titleSize: Metrics.font(userConfig.titleFontSize)
    readonly property int cardTitleSize: Metrics.font(userConfig.bodyFontSize)
    readonly property int cardBodySize: Metrics.font(userConfig.bodyFontSize - 1)

    // FORK: line boxes were fixed at 18 and 16 px, which are LATIN
    // measurements. Arabic carries harakat ABOVE the ascender and below the
    // baseline, so an ayah at the same pixel size needs materially more
    // vertical room — measured on a real notify-send of al-Fatiha, the title
    // rode over the card's top border and the body was cut off by its
    // bottom one. 1.75x covers the harakat case; Latin needs about 1.3 and
    // simply sits with more air, which is the cheaper of the two errors.
    //
    // Derived arithmetically rather than probed with a hidden Text: an
    // offscreen string forces Qt to SHAPE it, and shaping one Arabic glyph
    // would map an Arabic face into the process permanently. That is exactly
    // what the `"Ag国"` baseline guide did with NotoSansCJK at 27.6 MB.
    readonly property real titleLineHeight: Math.round(cardTitleSize * 1.75)
    readonly property real bodyLineHeight: Math.round(cardBodySize * 1.75)

    readonly property real headerHeight: 28
    readonly property real listTopGap: 9
    readonly property real cardTopPad: Metrics.pad(3)
    readonly property real cardBottomPad: Metrics.pad(6)
    readonly property real cardHeight: titleLineHeight + bodyLineHeight
        + cardTopPad + cardBottomPad + Metrics.px(2)
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
                font.pixelSize: root.titleSize
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
            font.pixelSize: root.cardBodySize
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

                // FORK: was two Texts pinned to the card's top and bottom
                // edges with fixed 18/16 px heights. That did two things
                // wrong at once.
                //
                // The fixed heights are Latin measurements, so an Arabic
                // title clipped against the card's top border and an Arabic
                // body against its bottom one. These Texts now take their
                // NATURAL implicitHeight, which Qt computes per script from
                // the face actually selected — the correct height for the
                // text present, with no probe and no guessing.
                //
                // And pinning the body to the BOTTOM edge stranded the title
                // at the top whenever a notification had no distinct body,
                // leaving a card that was half empty with its one line of
                // text jammed against the ceiling. A centred Column puts a
                // title-only card's text where it belongs, because the
                // hidden body stops occupying space at all.
                Column {
                    anchors.left: parent.left
                    anchors.leftMargin: Metrics.pad(16)
                    anchors.right: parent.right
                    anchors.rightMargin: Metrics.pad(16)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Metrics.px(2)

                    Text {
                        width: parent.width
                        text: delegateItem.titleText
                        textFormat: Text.PlainText
                        color: IslandTheme.textPrimary
                        font.pixelSize: root.cardTitleSize
                        font.family: root.textFontFamily
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }

                    Text {
                        width: parent.width
                        visible: delegateItem.bodyText !== ""
                        text: delegateItem.bodyText
                        textFormat: Text.PlainText
                        color: IslandTheme.textSecondary
                        font.pixelSize: root.cardBodySize
                        font.family: root.textFontFamily
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
