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

    // ---- THE META LINE: WHO SENT IT, HOW URGENT, HOW LONG AGO ----
    //
    // The card used to be a title and a body and nothing else, which is the
    // "notification centre UI is too bad". Three facts were missing and all
    // three were already in the model — `notificationHistoryModel` is a
    // plain ListModel filled at DynamicIslandWindow.qml:2371 with appName,
    // urgency, timestamp and the live notification object. Nothing had to be
    // plumbed; the delegate simply never read past summary and body.
    //
    // What that cost: a CRITICAL low-battery warning and a "now playing"
    // from a music player were pixel-identical rows. The capsule has had an
    // urgency ramp the whole time (NotificationLayer.qml's urgencyColor);
    // the centre, where you go to catch up on what you missed, threw it away.
    //
    // Same 1.75x line box as the other two, and for the same reason — see
    // the note above. This row is Latin-only in practice (app names, a
    // relative time) but it sits in the same column as text that is not, and
    // a row that changed height with the script would shift every card below
    // it.
    readonly property int metaSize: Metrics.font(userConfig.bodyFontSize - 2)
    readonly property real metaLineHeight: Math.round(metaSize * 1.75)

    // ---- RELATIVE TIME, AND WHY IT TICKS ----
    //
    // "2m", not "14:32". The centre answers "what did I miss", and the
    // useful axis for that is how long ago, not what the clock said. An
    // absolute time makes you do the subtraction yourself.
    //
    // `nowTick` is what makes it live. A binding on `new Date()` computes
    // once and never again, so a card posted "now" would still say "now" an
    // hour later — the kind of wrong that looks like a working feature.
    // Every relative time in the list reads this, so one timer updates all
    // of them, and it only runs while the panel is on screen.
    property date nowTick: new Date()

    Timer {
        // 20 s, which is the coarsest interval that cannot show a stale
        // "now": "now" covers the first 45 s, so a 20 s tick redraws it at
        // least twice before it becomes a lie. Minutes and hours change far
        // more slowly than they are checked.
        interval: 20000
        running: root.visible
        repeat: true
        triggeredOnStart: true
        onTriggered: root.nowTick = new Date()
    }

    function relativeTime(when) {
        if (!when || isNaN(when.getTime()))
            return "";
        const seconds = Math.max(0, (root.nowTick.getTime() - when.getTime()) / 1000);
        if (seconds < 45) return "now";
        const minutes = Math.round(seconds / 60);
        if (minutes < 60) return minutes + "m";
        const hours = Math.round(minutes / 60);
        if (hours < 24) return hours + "h";
        // Days rather than a date, because the model keeps 50 entries and
        // drops the rest — nothing here is old enough for a calendar date to
        // be the clearer answer.
        return Math.round(hours / 24) + "d";
    }

    // The capsule's ramp, deliberately reused rather than re-picked.
    // NotificationLayer.qml solved this once — critical is danger, low is
    // muted, normal is the ordinary text colour — and two surfaces showing
    // the same notification in two different colour languages is worse than
    // either language.
    function urgencyColor(urgency) {
        if (urgency === 2) return IslandTheme.danger;
        if (urgency === 0) return IslandTheme.textMuted;
        return IslandTheme.textSecondary;
    }

    readonly property real headerHeight: 28
    readonly property real listTopGap: 9
    readonly property real cardTopPad: Metrics.pad(3)
    readonly property real cardBottomPad: Metrics.pad(6)
    readonly property real cardHeight: metaLineHeight + titleLineHeight
        + bodyLineHeight + cardTopPad + cardBottomPad + Metrics.px(2)
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

                // Defaulted at the READ, not assumed present. These three
                // roles are written by DynamicIslandWindow.qml:2371 on every
                // insert, so in practice they are always there — but a
                // ListModel role that is undefined for one row silently
                // poisons every binding that touches it, and the failure
                // shows up as a blank column rather than as an error.
                readonly property string appNameText:
                    model.appName !== undefined && model.appName !== ""
                        ? model.appName : "Notification"
                readonly property int urgencyValue:
                    model.urgency !== undefined ? model.urgency : 1
                readonly property var postedAt: model.timestamp

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

                    // ---- THE META ROW ----
                    //
                    // Sender on the left, age on the right, and an urgency
                    // dot that appears ONLY when the urgency is not normal.
                    // A dot that is always present in the same colour says
                    // nothing; one that shows up is a mark you can scan a
                    // list for.
                    //
                    // A dot and not a coloured left edge on the card. The
                    // capsule rejected a leading edge and the argument there
                    // was that it pushes content off the centre line of a
                    // shape whose whole point is being one shape. A list
                    // card is not that shape and the argument does not
                    // transfer — but the OTHER half of that note does:
                    // urgency belongs on a mark, not on the text, because
                    // colouring the words makes a low-urgency message less
                    // legible than a normal one and punishes the reader for
                    // the sender's choice.
                    Item {
                        width: parent.width
                        height: root.metaLineHeight

                        Rectangle {
                            id: urgencyDot
                            anchors.verticalCenter: parent.verticalCenter
                            width: Metrics.px(5)
                            height: width
                            radius: width / 2
                            color: root.urgencyColor(delegateItem.urgencyValue)
                            visible: delegateItem.urgencyValue !== 1
                        }

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: urgencyDot.visible
                                ? urgencyDot.width + Metrics.pad(6) : 0
                            anchors.right: ageText.left
                            anchors.rightMargin: Metrics.pad(8)
                            anchors.verticalCenter: parent.verticalCenter
                            text: delegateItem.appNameText
                            textFormat: Text.PlainText
                            // Critical says so in the sender's name as well
                            // as the dot. A 5 px dot is a fine scanning mark
                            // and a poor alarm.
                            color: delegateItem.urgencyValue === 2
                                ? IslandTheme.danger : IslandTheme.textMuted
                            font.pixelSize: root.metaSize
                            font.family: root.textFontFamily
                            font.weight: Font.DemiBold
                            font.capitalization: Font.AllUppercase
                            font.letterSpacing: 0.6
                            elide: Text.ElideRight
                        }

                        Text {
                            id: ageText
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.relativeTime(delegateItem.postedAt)
                            textFormat: Text.PlainText
                            color: IslandTheme.textMuted
                            font.pixelSize: root.metaSize
                            font.family: root.textFontFamily
                            // Tabular figures: this number rewrites itself
                            // under a 20 s timer, and without them the row's
                            // right edge twitches every time a digit's
                            // advance width changes.
                            font.features: ({ "tnum": 1 })
                        }
                    }

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
