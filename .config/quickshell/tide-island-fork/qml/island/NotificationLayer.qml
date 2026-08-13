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
    property string appName: ""
    property string summary: ""
    property string body: ""
    property string iconText: ""
    property bool expanded: false
    // NotificationUrgency.Low / Normal / Critical, straight off the bus.
    // 1 is Normal and is what the spec says to assume when a sender says
    // nothing — written as a number rather than the enum so this file does
    // not have to import the notification service to name a default.
    property int urgency: 1
    // QList<NotificationAction>; each carries `identifier`, `text` and
    // invoke(). Empty for the overwhelming majority of notifications, which
    // is why the row below costs nothing when it is not needed.
    property var actions: []
    property int toggleButton: Qt.LeftButton
    property var configSource: null
    readonly property var activeConfig: configSource || userConfig
    property string iconFontFamily: activeConfig.iconFontFamily
    property string textFontFamily: activeConfig.textFontFamily
    property string heroFontFamily: activeConfig.heroFontFamily

    signal expansionToggleRequested()
    signal dismissRequested()
    signal actionRequested(int index)

    // ---- URGENCY IS DRAWN ON THE ICON, NOT AS AN EDGE ----
    //
    // The three urgencies have to be distinguishable at a glance or the
    // level is decoration. Two candidates were rejected before this one:
    //
    //   * Colouring the TEXT. Wrong twice: the capsule sits on the
    //     island's own fill, so coloured body text fights the contrast
    //     solving in IslandTheme, and a low-urgency message would end up
    //     LESS legible than a normal one — punishing the reader for the
    //     sender's choice.
    //   * A leading edge — a coloured stripe down the left. Built, shipped
    //     for one round, and rejected by the user on sight: it adds a
    //     second element to a shape whose entire argument is that it is one
    //     shape, and it pushes the content off the capsule's centre line.
    //
    // The icon slot is already there, already carries a glyph, and is
    // already the thing the eye lands on first. Colouring it costs no
    // geometry at all, which is what makes it compatible with the centred
    // content below.
    readonly property color urgencyColor: urgency === 2
        ? IslandTheme.danger
        : (urgency === 0 ? IslandTheme.textMuted : IslandTheme.textPrimary)
    readonly property bool hasActions: actions && actions.length > 0

    readonly property string contentText: {
        if (summary !== "" && body !== "" && body !== summary) return summary + "  " + body;
        if (summary !== "") return summary;
        if (body !== "") return body;
        return "New notification";
    }
    readonly property real minimumWidth: Metrics.px(272)
    readonly property real compactMaximumWidth: 400
    readonly property real expandedMaximumWidth: 520
    readonly property real maximumWidth: expanded && hasOverflowContent ? expandedMaximumWidth : compactMaximumWidth
    readonly property real iconSlotWidth: 18
    readonly property real contentSpacing: 13
    readonly property real horizontalPadding: Metrics.pad(16)
    readonly property real compactVerticalPadding: 7
    readonly property real expandedVerticalPadding: 13
    readonly property real verticalPadding: expanded && hasOverflowContent ? expandedVerticalPadding : compactVerticalPadding
    readonly property real compactMaximumContentHeight: 68 - compactVerticalPadding * 2
    readonly property real expandedMaximumContentHeight: 240 - expandedVerticalPadding * 2
    readonly property real textBlockWidthAtMaximum: compactMaximumWidth - horizontalPadding * 2 - iconSlotWidth - contentSpacing
    readonly property real expandedTextBlockWidthAtMaximum: expandedMaximumWidth - horizontalPadding * 2 - iconSlotWidth - contentSpacing
    readonly property real availableWidth: Math.max(0, width - horizontalPadding * 2 - iconSlotWidth - contentSpacing)
    readonly property bool prefersWrappedContent: contentMetrics.advanceWidth > textBlockWidthAtMaximum
    readonly property bool hasOverflowContent: compactContentProbe.lineCount > 2
        || contentMetrics.advanceWidth > textBlockWidthAtMaximum * 2
        || (contentMetrics.advanceWidth > textBlockWidthAtMaximum && compactContentProbe.lineCount <= 1)
    readonly property real compactPreferredWidth: prefersWrappedContent
        ? maximumWidth
        : Math.max(minimumWidth, Math.min(maximumWidth, contentMetrics.advanceWidth + iconSlotWidth + contentSpacing + horizontalPadding * 2))
    readonly property real compactPreferredHeight: prefersWrappedContent ? compactMaximumContentHeight + compactVerticalPadding * 2 : 56
    readonly property real expandedPreferredWidth: expandedMaximumWidth
    readonly property real expandedPreferredHeight: Math.max(
        84,
        Math.min(240, Math.min(expandedMaximumContentHeight, expandedContentProbe.implicitHeight) + expandedVerticalPadding * 2)
    )
    readonly property real preferredWidth: expanded && hasOverflowContent ? expandedPreferredWidth : compactPreferredWidth
    readonly property real preferredHeight: expanded && hasOverflowContent ? expandedPreferredHeight : compactPreferredHeight

    anchors.fill: parent
    anchors.margins: 0
    opacity: showCondition ? 1 : 0

    // FORK: one choreography for every layer in the shell.
    // Was `showCondition ? 280 : 140` on Easing.InOutQuad — one of
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

    TextMetrics {
        id: contentMetrics
        font.family: textFontFamily
        font.pixelSize: userConfig.bodyFontSize
        font.weight: Font.DemiBold
        font.letterSpacing: -0.15
        text: contentText
    }

    Text {
        id: compactContentProbe
        x: Metrics.px(-10000)
        y: Metrics.px(-10000)
        height: 0
        opacity: 0
        width: textBlockWidthAtMaximum
        text: contentText
        font.pixelSize: userConfig.bodyFontSize
        font.family: textFontFamily
        font.weight: Font.DemiBold
        font.letterSpacing: -0.15
        wrapMode: Text.WordWrap
        lineHeight: 0.95
    }

    Text {
        id: expandedContentProbe
        x: Metrics.px(-10000)
        y: Metrics.px(-10000)
        height: 0
        opacity: 0
        width: expandedTextBlockWidthAtMaximum
        text: contentText
        font.pixelSize: userConfig.bodyFontSize
        font.family: textFontFamily
        font.weight: Font.DemiBold
        font.letterSpacing: -0.15
        wrapMode: Text.WordWrap
        lineHeight: 1.05
    }

    Row {
        anchors.fill: parent
        anchors.leftMargin: horizontalPadding
        anchors.rightMargin: horizontalPadding
        anchors.topMargin: verticalPadding
        anchors.bottomMargin: verticalPadding
        spacing: contentSpacing
        anchors.verticalCenter: parent.verticalCenter

        Text {
            width: iconSlotWidth
            anchors.verticalCenter: parent.verticalCenter
            text: iconText
            // The urgency, and the only place it is drawn. See urgencyColor.
            color: root.urgencyColor
            font.pixelSize: userConfig.iconFontSize
            font.family: iconFontFamily
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }

        Item {
            width: parent.width - iconSlotWidth - contentSpacing
            height: parent.height

            Text {
                visible: !(root.expanded && root.hasOverflowContent)
                anchors.verticalCenter: parent.verticalCenter
                text: contentText
                color: IslandTheme.textPrimary
                font.pixelSize: userConfig.bodyFontSize
                font.family: textFontFamily
                font.weight: Font.DemiBold
                font.letterSpacing: -0.15
                width: parent.width
                // Centred, at the user's request. It also happens to be the
                // right answer for this shape: the capsule sizes ITSELF to
                // the message (compactPreferredWidth is derived from the
                // text metrics), so left-aligned text in a box that is
                // already the width of the text reads as centred until a
                // short message arrives — at which point it jumps left and
                // the capsule looks lopsided. Centring makes the two cases
                // agree.
                horizontalAlignment: Text.AlignHCenter
                wrapMode: prefersWrappedContent ? Text.WordWrap : Text.NoWrap
                maximumLineCount: prefersWrappedContent ? 2 : 1
                elide: Text.ElideRight
                lineHeight: 0.95
            }

            Flickable {
                id: expandedFlickable
                visible: root.expanded && root.hasOverflowContent
                anchors.fill: parent
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                contentWidth: width
                contentHeight: expandedContentText.implicitHeight
                interactive: contentHeight > height

                Text {
                    id: expandedContentText
                    width: expandedFlickable.width
                    text: contentText
                    color: IslandTheme.textPrimary
                    font.pixelSize: userConfig.bodyFontSize
                    font.family: textFontFamily
                    font.weight: Font.DemiBold
                    font.letterSpacing: -0.15
                    // Matches the compact state, so expanding a notification
                    // does not also re-align it.
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    elide: Text.ElideNone
                    lineHeight: 1.05
                }
            }
        }
    }

    // ---- ACTIONS ----
    //
    // Drawn only when expanded, and that is the whole design decision. A
    // resting capsule is 56 px tall and about 400 wide; buttons in it would
    // either be unreadably small or would push the message out. Expanding
    // is already the gesture for "I want to deal with this", it is already
    // bound to a click, and it already stops the auto-hide timer — so the
    // notification cannot expire out from under a hand reaching for a
    // button, which is the failure mode that makes action buttons useless
    // elsewhere.
    Row {
        id: actionRow
        visible: root.hasActions && root.expanded
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: root.horizontalPadding
        anchors.bottomMargin: Metrics.pad(6)
        spacing: Metrics.px(6)

        Repeater {
            model: root.visible && root.hasActions ? root.actions : []

            delegate: Rectangle {
                id: actionButton

                required property int index
                required property var modelData

                height: Metrics.px(20)
                width: actionLabel.implicitWidth + Metrics.pad(16)
                radius: Metrics.px(6)
                color: actionMouse.containsMouse
                    ? IslandTheme.surfaceRaisedHover
                    : IslandTheme.surfaceRaised
                border.width: 1
                border.color: IslandTheme.hairline

                Text {
                    id: actionLabel
                    anchors.centerIn: parent
                    // `text` is the human label; `identifier` is what goes
                    // back on the bus. Senders that supply only "default"
                    // give an empty label, so fall back rather than draw an
                    // invisible button.
                    text: actionButton.modelData.text !== ""
                        ? actionButton.modelData.text
                        : actionButton.modelData.identifier
                    color: IslandTheme.textPrimary
                    font.pixelSize: Metrics.font(10)
                    font.family: root.textFontFamily
                    font.weight: Font.Medium
                }

                MouseArea {
                    id: actionMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.actionRequested(actionButton.index)
                }
            }
        }
    }

    // Dismiss. A right-click, because the left button is already the
    // expand/collapse toggle and a notification that dismissed itself when
    // you tried to read it would be worse than one that never dismissed.
    //
    // There is no key handler here and there must not be one. This layer
    // takes no keyboard focus — the notch stealing the keyboard from
    // whatever you were typing in, every time a message arrives, is a worse
    // bug than any it would fix — so there is no focused surface for Escape
    // to be pressed into. The keyboard route is therefore a COMPOSITOR
    // bind: `$alt N` -> `tide dismissNotification`, which is the same key
    // qtile used and which used to run `dunstctl close`.
    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: root.dismissRequested()
    }

    TapHandler {
        enabled: root.hasOverflowContent
        acceptedButtons: root.toggleButton
        onTapped: root.expansionToggleRequested()
    }
}
