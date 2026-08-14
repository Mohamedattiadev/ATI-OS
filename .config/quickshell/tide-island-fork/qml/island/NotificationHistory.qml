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
    // 1.45, not the 1.75 the title and body use. That factor exists for
    // harakat above the ascender and below the baseline on Arabic TEXT --
    // and this line is not text, it is a small-caps sender name and a
    // two-character age. Nothing in it is ever vocalised, so it was paying
    // for a script feature it cannot use, on every card, three cards deep.
    // The title and body keep 1.75; they are the lines that carry the
    // message.
    readonly property real metaLineHeight: Math.round(metaSize * 1.45)

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

    // ---- VIM MOTIONS ----
    //
    // This panel had NO keys at all beyond Escape and q, in a shell where
    // every other list — the picker, wifi, bluetooth, the theme picker —
    // moves on j/k and says so in a footer. You could open the notification
    // centre and then only look at it.
    //
    // The verbs are taken from the panels that already exist rather than
    // invented, because a second vocabulary for the same gestures is worse
    // than none: j/k move, g/G first and last, d or x acts on the row under
    // the cursor, D on all of them, q or Escape closes. `x` is BluetoothPanel's
    // "forget" and `d` its "disconnect" — both mean "make this go away", so
    // both land on dismiss here rather than picking one and leaving the other
    // to do nothing.
    //
    // The cursor starts at -1 — NOTHING selected — and not at 0. This list's
    // action is destructive and it opens under a keyboard grab, so a cursor
    // resting on row 0 the instant it appears means one reflexive `d`
    // deletes a notification you had not finished reading. j or k from
    // nowhere lands on the first row, which is the same keystroke it would
    // have cost anyway.
    property int cursor: -1

    function clampCursor() {
        if (root.itemCount === 0) {
            root.cursor = -1;
            return;
        }
        if (root.cursor >= root.itemCount)
            root.cursor = root.itemCount - 1;
    }

    onItemCountChanged: clampCursor()

    function moveCursor(delta) {
        if (root.itemCount === 0)
            return;
        // From nowhere, j goes to the top and k to the bottom, which is what
        // the same keys do in a pager.
        if (root.cursor < 0)
            root.cursor = delta > 0 ? 0 : root.itemCount - 1;
        else
            root.cursor = Math.max(0, Math.min(root.itemCount - 1,
                                               root.cursor + delta));
        listView.positionViewAtIndex(root.cursor, ListView.Contain);
    }

    function dismissAt(index) {
        if (!root.notificationModel || index < 0 || index >= root.notificationModel.count)
            return;
        root.notificationModel.remove(index);
        // The cursor stays on the same ROW NUMBER, so a run of `d` clears
        // downward from where you were instead of walking away from itself.
        // clampCursor catches the case where the row removed was the last.
        root.clampCursor();
    }

    // ---- WHY THIS IS NOT JUST `event.modifiers & Qt.ShiftModifier` ----
    //
    // Caught by driving the panel with `wtype G`: the capital arrives with
    // `text` "G" and NO ShiftModifier set, so the shifted branch never ran
    // and G silently did what g does. Real hardware sets the modifier and
    // this would have shipped looking fine.
    //
    // Anything that synthesises input at the protocol level rather than the
    // keyboard level can deliver a capital this way — which is every remote,
    // accessibility and automation path into this shell. The character the
    // user produced is the more reliable of the two signals, so check it
    // first and keep the modifier as the fallback for the case where `text`
    // is empty.
    function isUpper(event) {
        if (event.text && event.text.length === 1)
            return event.text === event.text.toUpperCase()
                && event.text !== event.text.toLowerCase();
        return (event.modifiers & Qt.ShiftModifier) !== 0;
    }

    function handleKey(event) {
        switch (event.key) {
        case Qt.Key_J:      root.moveCursor(1);  return true;
        case Qt.Key_K:      root.moveCursor(-1); return true;
        case Qt.Key_Down:   root.moveCursor(1);  return true;
        case Qt.Key_Up:     root.moveCursor(-1); return true;
        case Qt.Key_G:
            if (root.itemCount === 0)
                return true;
            // Shift+G is last, bare g is first — vim's gg without the
            // double-tap, because there is no other g verb here to disambiguate.
            root.cursor = root.isUpper(event) ? root.itemCount - 1 : 0;
            listView.positionViewAtIndex(root.cursor, ListView.Contain);
            return true;
        case Qt.Key_D:
            if (root.isUpper(event)) {
                root.clearAllRequested();
                return true;
            }
            root.dismissAt(root.cursor);
            return true;
        case Qt.Key_X:
            root.dismissAt(root.cursor);
            return true;
        default:
            return false;
        }
    }

    signal clearAllRequested()

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

    // The key hints, owned HERE rather than by the layer above.
    //
    // The first attempt put the KeyHint in NotificationCenterLayer and
    // positioned it from that layer's own height, then from `parent.bottom`,
    // then from `contentHeight`. All three drew the hints on the DESKTOP
    // below the panel, because the layer fills the WINDOW — which is
    // islandTopMargin + contentHeight + 6 — and none of those three is the
    // capsule's bottom edge.
    //
    // The fix is not a fourth guess at which number is the real height. It
    // is that the layer and this file were measuring from DIFFERENT
    // references at all: the layer computed from a height, this file laid
    // itself out top-down from its header. Now everything below derives
    // from `listContentHeight` and the layer's contentHeight is
    // `2 x padding + totalHeight`, so the two cannot disagree — there is one
    // arithmetic and both read it.
    property var hints: []
    readonly property real footerHeight: Metrics.chromeFooter()
    readonly property real footerGap: Metrics.pad(6)

    // The floor is one card, for the empty case: "No notifications" is
    // centred in it, and a panel barely taller than its own title bar reads
    // as a rendering failure.
    readonly property real bodyHeight: Math.max(cardHeight, listContentHeight)
    readonly property real totalHeight: headerHeight + listTopGap + bodyHeight
        + footerGap + footerHeight

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
        // Explicit, NOT anchored to parent.bottom. The parent is the window,
        // so filling to its bottom made this viewport taller than the panel
        // it is drawn in — invisible with three cards because they are
        // top-anchored, and a fourth would have scrolled into space that is
        // never painted. See the note on `hints` above.
        height: root.bodyHeight
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
                    // The keyboard cursor reads as hover. Same affordance,
                    // because it means the same thing — "this is the row the
                    // next verb applies to" — and inventing a second
                    // highlight would make the mouse and the keyboard
                    // disagree about which row is live.
                    hovered: cardMouse.containsMouse || root.cursor === index
                    pressed: cardMouse.pressed
                }

                // The accent edge, only on the keyboard cursor. Hover gets
                // the plate lift and nothing more: a pointer already says
                // where it is by being visible, and a mouse that drew a
                // selection ring would look like it had SELECTED something
                // it has not.
                Rectangle {
                    anchors.fill: parent
                    radius: root.cardRadius
                    color: "transparent"
                    border.width: 1
                    border.color: IslandTheme.alpha(IslandTheme.accent, 0.9)
                    visible: root.cursor === index
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
                    // Hovering moves the keyboard cursor, so the two input
                    // methods share one notion of "the current row" and a
                    // `d` after a mouse move acts on the card under the
                    // pointer rather than on wherever j/k was left.
                    onContainsMouseChanged: {
                        if (containsMouse)
                            root.cursor = index;
                    }
                    onClicked: root.dismissAt(index)
                }
            }
        }
    }

    // Directly below the list, off the same terms the list is sized from.
    KeyHint {
        x: 0
        y: listViewport.y + listViewport.height + root.footerGap
        width: root.width
        height: root.footerHeight
        hints: root.hints
        textFontFamily: root.textFontFamily
    }
}
