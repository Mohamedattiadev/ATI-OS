import QtQuick

//
// One chip. qtile's `chip()` helper and its RectDecoration, in QML.
//
// There are NO separators on this bar, and that is a decision rather than an
// omission: config.py's own note records that the one surviving pipe was the
// sole flat element among the chips and read as a stray mark rather than a
// divider. Chip padding does the separating.
//
// The bar's background is "#11111b00" — fully transparent — so every visible
// pixel on it belongs to one of these.
Item {
    id: root

    property string text: ""
    property color foreground: BarTheme.fg
    property color plate: BarTheme.plate
    property int fontPixelSize: Metrics.s(11)
    property string fontFamily: "Ubuntu Bold"
    // qtile's `padding` is per-side horizontal padding inside the plate.
    property int padding: 11
    property bool clickable: false
    // Chips with nothing to say take no width at all rather than leaving a
    // bare plate on the bar — the chord chip is empty except inside a chord,
    // and MPRIS is empty with no player.
    property bool active: true

    signal clicked(int button)

    // qtile's TOOLTIP_BY_NAME string for this chip. Empty means no tooltip,
    // which is what most of the bar's own widgets have.
    property string tooltip: ""
    // Set by the bar; the chip reports hover into it so ONE popup serves the
    // whole bar. See Tooltip.qml for why that removes the need for qtile's
    // _kill_all_tooltips().
    property var hoverSink: null

    visible: active && (text !== "" || root.emoji !== "")
    implicitWidth: visible ? labelRow.implicitWidth + root.padding * 2 : 0
    implicitHeight: parent ? parent.height : Metrics.barHeight
    width: implicitWidth

    Rectangle {
        id: plateRect
        anchors.fill: parent
        // RectDecoration's padding_x=3 / padding_y=2: the plate is inset from
        // the widget's own box, which is what leaves the gap between chips.
        anchors.leftMargin: Metrics.s(3)
        anchors.rightMargin: Metrics.s(3)
        anchors.topMargin: Metrics.s(2)
        anchors.bottomMargin: Metrics.s(2)

        // ---- HALF THE PLATE'S HEIGHT, NOT A CONSTANT ----
        //
        // config.py derives this and says why: a flat 11 against a plate that
        // is barHeight - 2*padding_y = 24 tall is one pixel short of the 12 a
        // full round needs, leaving a 2 px straight segment on each short
        // side. Small, and it is the difference between "circle" and
        // "squircle" — it was visible on the logo chip.
        //
        // Taken from this rectangle's own height so it cannot drift from the
        // bar size the way a copied literal would.
        radius: height / 2
        color: root.plate
        opacity: mouse.pressed && root.clickable ? 0.72 : 1

        // The click flash config.py gives chips that actually respond to
        // clicks. Not applied to inert ones — there is no point animating a
        // chip that does nothing when pressed.
        Behavior on opacity {
            NumberAnimation { duration: 90; easing.type: Easing.OutQuad }
        }
    }

    // ---- WHY THE EMOJI IS ITS OWN Text ----
    //
    // The keyboard chip is "flag + EN", and a flag is a regional-indicator
    // PAIR in a colour BITMAP font. config.py's own comment records what that
    // costs: colour emoji "ignore the widget's foreground, sit on their own
    // baseline, and render at a size unrelated to the surrounding text". It
    // renders them at pango size 11000 against 10pt text for exactly that
    // reason — "unscaled the flag looked undersized, and 15000 was too big.
    // 12000 splits it."
    //
    // A QML Text has ONE font family, and fontconfig will not substitute
    // inside an explicitly-named one, so a flag inside the label's Text is a
    // blank. Hence two Texts side by side, each with its own face and size.
    // Empty by default, so every other chip is unaffected.
    property string emoji: ""

    Row {
        id: labelRow
        anchors.centerIn: plateRect
        spacing: root.emoji === "" ? 0 : Metrics.s(3)

        Text {
            visible: root.emoji !== ""
            text: root.emoji
            font.family: "Noto Color Emoji"
            // A shade larger than the label, which is config.py's 11000-
            // against-10pt in the units available here.
            font.pixelSize: Math.round(root.fontPixelSize * 1.1)
            anchors.verticalCenter: parent.verticalCenter
        }

    Text {
        id: label
        text: root.text
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: root.fontPixelSize
        // The bar is 28 px tall and a chip is one line, always. Without this a
        // long MPRIS title would wrap inside the plate and be clipped to its
        // first line, which reads as a truncation bug rather than a layout.
        maximumLineCount: 1
        elide: Text.ElideRight
        renderType: Text.NativeRendering
        anchors.verticalCenter: parent.verticalCenter
    }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        // hoverEnabled regardless of `clickable`: several chips are pure
        // readouts with a tooltip and no click, which is true in config.py too
        // — w_lang and the widget boxes carry hints for things the keyboard
        // does.
        hoverEnabled: root.tooltip !== ""
        onEntered: if (root.hoverSink) root.hoverSink.enter(root, root.tooltip)
        onExited: if (root.hoverSink) root.hoverSink.exit(root)
        enabled: root.clickable || hoverEnabled
        // A chip with only a tooltip must not swallow clicks meant for the
        // desktop behind it.
        acceptedButtons: root.clickable
            ? (Qt.LeftButton | Qt.MiddleButton | Qt.RightButton)
            : Qt.NoButton
        cursorShape: root.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: (event) => root.clicked(event.button)
    }
}
