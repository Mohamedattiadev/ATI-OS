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
    // widget_defaults' fontsize and font, split into the two things pango was
    // reading out of "Ubuntu Bold" all along — see Metrics.textFamily, which
    // is where the measurement that found this lives.
    property int fontPixelSize: Metrics.textSize
    property string fontFamily: Metrics.textFamily

    // Bold only on the TEXT face by default. Symbols Nerd Font and Adwaita
    // Mono are named explicitly by the chips that want them, and asking Qt
    // for a bold cut a family does not have makes it SYNTHESISE one — a
    // heavier glyph than qtile draws, which is the same mistake the widget
    // box's font note records from the fallback-order side.
    //
    // Settable, because one glyph on this bar genuinely is bold in a face
    // that has a bold cut: config.py asks for the tray triangle in
    // `<span font_family="Adwaita Mono" weight="bold">` and gives its reason
    // at length — Adwaita Mono Bold carries 31% more stroke than JetBrains
    // Mono at the same ink height, and the ask was a bolder triangle.
    property bool fontBold: root.fontFamily === Metrics.textFamily
    // qtile's `padding` is per-side horizontal padding inside the plate.
    property int padding: 11
    property bool clickable: false
    // Chips with nothing to say take no width at all rather than leaving a
    // bare plate on the bar — the chord chip is empty except inside a chord,
    // and MPRIS is empty with no player.
    property bool active: true

    signal clicked(int button)

    // ---- SCROLL, WHICH TWO OF qtile's WIDGETS HAVE WITHOUT SAYING SO ----
    //
    // config.py sets no mouse_callbacks on w_volume, and this bar read that as
    // "the widget is inert" and wrote the comment down. Wrong, and wrong in
    // the way the RULES warn about — the claim was never measured. Asked of
    // the installed libqtile instead of the config:
    //
    //     Volume.__init__ -> add_callbacks({
    //         "Button1": self.mute,        "Button3": self.run_app,
    //         "Button4": self.increase_vol, "Button5": self.decrease_vol })
    //
    // The widget ships its own, so an empty mouse_callbacks means "keep the
    // defaults" rather than "do nothing" — and the tooltip TOOLTIP_BY_NAME
    // gives it, "Volume · scroll to change", was describing behaviour this
    // bar did not have. Mpris2 is the same shape: config.py maps Button4 and
    // Button5 on it explicitly.
    //
    // +1 for a scroll UP, -1 for down.
    signal scrolled(int direction)
    property bool scrollable: false

    // qtile's TOOLTIP_BY_NAME string for this chip. Empty means no tooltip,
    // which is what most of the bar's own widgets have.
    property string tooltip: ""
    // Raised when the pointer enters, before the sink is told. For a chip
    // whose tooltip is DATA rather than a label — the clock's next prayer and
    // FX rates — this is where the fetch is kicked off, and Tooltip reads the
    // chip's `tooltip` live so an answer that arrives inside the delay is the
    // one that gets drawn.
    signal tooltipRequested()
    // Set by the bar; the chip reports hover into it so ONE popup serves the
    // whole bar. See Tooltip.qml for why that removes the need for qtile's
    // _kill_all_tooltips().
    property var hoverSink: null

    // ---- AND WHY THE NERD FONT GLYPH IS ITS OWN Text TOO ----
    //
    // Same trap as the emoji below, from the other direction. Several of
    // config.py's strings are ONE string mixing a Nerd Font icon with plain
    // words — CHORD_CHIP_LABELS' "\U000f0349   ROFI : i , o , p …" is the
    // clearest. pango renders that by falling back per RUN, so qtile draws the
    // glyph from a Nerd Font and the words from Ubuntu Bold without being
    // asked. Qt does not: a Text with an explicitly-named family draws
    // everything in that family and puts a box where the family has no glyph.
    //
    // So the icon is split out and given its own face, and the words keep
    // theirs. Empty by default, so every chip that is only words is unaffected.
    property string icon: ""
    property string iconFamily: "Symbols Nerd Font"

    // ---- A WIDTH THAT DOES NOT MOVE WHEN THE TEXT DOES ----
    //
    // config.py grows a whole SteadyCurrentLayout subclass for this and its
    // docstring is the specification: the layout chip "is exactly as wide as
    // the name it is showing, so moving from a group on monadtall to one on
    // max shrank it by six characters. It sits to the LEFT of the centred
    // GroupBox, so that whole difference shoved the GroupBox sideways" — one
    // frame of jitter on every workspace switch between two layouts.
    //
    // Same fix: reserve the widest string this chip can ever hold, and centre
    // whatever is actually in it. Empty by default; a chip whose text does not
    // change size has nothing to reserve.
    property string widestText: ""

    TextMetrics {
        id: widest
        text: root.widestText
        font: label.font
    }

    visible: active && (text !== "" || root.emoji !== "" || root.icon !== "")
    implicitWidth: visible
        ? Math.max(labelRow.implicitWidth, widest.width) + root.padding * 2 : 0
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
            visible: root.icon !== ""
            text: root.icon
            color: root.foreground
            font.family: root.iconFamily
            font.pixelSize: root.fontPixelSize
            renderType: Text.NativeRendering
            anchors.verticalCenter: parent.verticalCenter
        }

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
        font.bold: root.fontBold
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
        onEntered: {
            // BEFORE the sink, so a chip whose tooltip is fetched rather than
            // written has the whole tooltipDelay to answer in. See the clock
            // chip in shell.qml, and qtile's own _clock_tooltip_text, which is
            // called at show time for the same reason.
            root.tooltipRequested();
            if (root.hoverSink)
                root.hoverSink.enter(root, root.tooltip);
        }
        onExited: if (root.hoverSink) root.hoverSink.exit(root)
        enabled: root.clickable || hoverEnabled || root.scrollable
        // A chip with only a tooltip must not swallow clicks meant for the
        // desktop behind it.
        acceptedButtons: root.clickable
            ? (Qt.LeftButton | Qt.MiddleButton | Qt.RightButton)
            : Qt.NoButton
        cursorShape: root.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: (event) => root.clicked(event.button)

        // Only where a chip asked for it. A wheel handler that is always
        // present eats scroll events over the bar — the widgets that do NOT
        // respond to the wheel in qtile pass it through, and a bar that
        // swallows every scroll is a bar you cannot scroll a workspace on.
        onWheel: (wheel) => {
            if (!root.scrollable) {
                wheel.accepted = false;
                return;
            }
            // angleDelta rather than pixelDelta: a mouse wheel reports in
            // 120ths of a degree and reports nothing at all in pixels, so
            // pixelDelta is zero on exactly the device this is for.
            const dy = wheel.angleDelta.y;
            if (dy === 0)
                return;
            root.scrolled(dy > 0 ? 1 : -1);
        }
    }
}
