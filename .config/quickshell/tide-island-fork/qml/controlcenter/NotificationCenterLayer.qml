import QtQuick
import QtQuick.Shapes
import "../island"

// FORK: one shared scale factor for every island surface.
import "../common/Metrics.js" as Metrics
// FORK: the shared motion system — one generated spring for geometry,
// one critically damped curve for opacity. See qml/common/Motion.js.
import "../common/Motion.js" as Motion
import "../common"

Item {
    id: notificationCenter

    signal clearAllRequested()
    // FORK: Escape / q, the third of the three panels that had no keyboard
    // dismissal. Listed with the control centre and the expanded player
    // rather than left for later because the three share one cause — none of
    // them appeared in DynamicIslandWindow's keyboardFocus list, so none of
    // them could receive a keystroke, so none of them grew a handler.
    signal closeRequested()

    property bool showCondition: false
    property var notificationModel: null
    property string iconFontFamily: userConfig.iconFontFamily
    property string textFontFamily: userConfig.textFontFamily
    property string heroFontFamily: userConfig.heroFontFamily

    readonly property bool hasNotifications: notificationModel && notificationModel.count > 0
    readonly property real verticalPadding: Metrics.pad(10)
    readonly property real horizontalPadding: Metrics.pad(22)

    //
    // FORK — content-sized, like the display and audio panels and for the
    // same reason.
    //
    // `contentHeight` was the literal 218, which DynamicIslandWindow.qml
    // reads straight through as the capsule's height for `notification_center`.
    // Work out where 218 came from and it is not a design decision at all:
    // 2 x pad(10) + header 28 + gap 9 + (3 cards x 49 + 2 gaps x 7 = 161)
    // = 218. It is the THREE-notification height — NotificationHistory's own
    // `maxVisibleItems` ceiling — hardcoded as the height for every case.
    //
    // Every real open is smaller than its worst case. Screenshotted with the
    // one notification actually in history: content ended 106 px down and the
    // remaining 112 px — 51% of the panel — was empty black with a scrollbar
    // track's worth of nothing in it.
    //
    // The list already publishes exactly the number needed:
    // `listContentHeight` is min(actual rows, 3 rows), which is why the
    // ceiling survives this change untouched — a fourth notification scrolls
    // rather than growing the capsule, same as before. Reading it here rather
    // than recomputing a row count is deliberate: a height derived from a
    // different count than the one drawn is a panel that clips its own last
    // card.
    //
    // The empty case gets one card's worth of floor rather than collapsing to
    // 57, because "No notifications" is centred in that space and a panel
    // barely taller than its own title bar reads as a rendering failure.
    //
    readonly property real contentHeight: verticalPadding * 2
        + notificationHistory.headerHeight
        + notificationHistory.listTopGap
        + Math.max(notificationHistory.cardHeight,
                   notificationHistory.listContentHeight)

    focus: showCondition
    activeFocusOnTab: true

    // The same explicit claim ControlCenterLayer makes, and the reason this
    // panel was the one of the three still not closing on Escape after the
    // loaders were put into the focus chain.
    //
    // `focus: showCondition` nominates this item as its parent scope's focus
    // child. That is enough ONCE something walks the chain — which is what
    // keyPanelFocusTimer's islandContainer.forceActiveFocus() does. But the
    // timer is restarted from onNotificationCenterLayerVisibleChanged in
    // DynamicIslandWindow, i.e. from the property change, while this item is
    // built by a Loader reacting to the same change. Whether the item exists
    // when the timer fires is a race between two observers of one boolean,
    // and on this panel it lost: interval 0 is the next event-loop turn, and
    // the notification centre's loader has more to build than the other two
    // (NotificationHistory instantiates a ListView over the history model)
    // so it is the one that is reliably not ready in time.
    //
    // Claiming from the item itself removes the race entirely — this runs
    // when the item is up, by definition, because it IS the item running it.
    // Qt.callLater rather than a direct call for the ordering reason given
    // at the control centre: the timer may still fire after us and hand
    // focus back to the scope, so the claim has to land in the same turn the
    // timer does rather than before it.
    onShowConditionChanged: {
        if (showCondition)
            Qt.callLater(function() {
                if (notificationCenter.showCondition)
                    notificationCenter.forceActiveFocus();
            });
    }

    Keys.onPressed: function(event) {
        switch (event.key) {
        case Qt.Key_Escape:
        case Qt.Key_Q:
            notificationCenter.closeRequested();
            event.accepted = true;
            break;
        default:
            break;
        }
    }

    NotificationHistory {
        id: notificationHistory

        anchors.fill: parent
        anchors.topMargin: notificationCenter.verticalPadding
        anchors.bottomMargin: notificationCenter.verticalPadding
        anchors.leftMargin: notificationCenter.horizontalPadding
        anchors.rightMargin: notificationCenter.horizontalPadding
        notificationModel: notificationCenter.notificationModel
        iconFontFamily: notificationCenter.iconFontFamily
        textFontFamily: notificationCenter.textFontFamily
        heroFontFamily: notificationCenter.heroFontFamily
    }

    // Keep the action inside the first notification card so it does not create
    // a separate black toolbar above the list.
    Item {
        id: clearButton

        z: 100
        opacity: notificationCenter.hasNotifications ? 1 : 0.5
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: notificationCenter.verticalPadding + 3
        anchors.rightMargin: notificationCenter.horizontalPadding + 2
        width: Metrics.px(24)
        height: Metrics.px(24)

        Behavior on opacity {
            NumberAnimation {
                duration: 180
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Motion.fade()   // FORK: was Easing.OutCubic
            }
        }

        Item {
            id: trashIcon

            anchors.centerIn: parent
            width: Metrics.px(24)
            height: Metrics.px(24)
            scale: clearMouse.pressed ? 0.70 : 0.75

            Behavior on scale {
                NumberAnimation {
                    duration: 280
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Motion.spring()   // FORK: was Easing.OutCubic
                }
            }

            Shape {
                id: trashBody

                x: 0
                y: clearMouse.containsMouse ? 1 : 0
                width: parent.width
                height: parent.height
                preferredRendererType: Shape.CurveRenderer

                Behavior on y {
                    NumberAnimation {
                        duration: 360
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Motion.spring()   // FORK: was Easing.OutCubic
                    }
                }

                ShapePath {
                    fillColor: "transparent"
                    strokeColor: IslandTheme.textSecondary
                    strokeWidth: 1.8
                    capStyle: ShapePath.RoundCap
                    joinStyle: ShapePath.RoundJoin

                    PathSvg {
                        path: "M5 6v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V6 M10 11v6 M14 11v6"
                    }
                }
            }

            Item {
                id: trashLid

                x: 0
                transformOrigin: Item.Right
                y: clearMouse.containsMouse ? -1.5 : 0
                width: parent.width
                height: parent.height
                rotation: clearMouse.containsMouse ? 12 : 0

                Behavior on y {
                    NumberAnimation {
                        duration: 360
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Motion.spring()   // FORK: was Easing.OutCubic
                    }
                }

                Behavior on rotation {
                    NumberAnimation {
                        duration: 360
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Motion.spring()   // FORK: was Easing.OutCubic
                    }
                }

                Shape {
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer

                    ShapePath {
                        fillColor: "transparent"
                        strokeColor: IslandTheme.textSecondary
                        strokeWidth: 1.8
                        capStyle: ShapePath.RoundCap
                        joinStyle: ShapePath.RoundJoin

                        PathSvg {
                            path: "M3 6h18 M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"
                        }
                    }
                }
            }
        }

        MouseArea {
            id: clearMouse

            anchors.fill: parent
            enabled: notificationCenter.hasNotifications
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: notificationCenter.clearAllRequested()
        }
    }
}
