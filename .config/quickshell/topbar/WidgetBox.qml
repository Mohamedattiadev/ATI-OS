import QtQuick

//
// qtile's SmartWidgetBox: a toggle chip that reveals its contents in place.
//
// Four of the right-hand chips are these, and they are the reason that side of
// the bar has two widths. config.py's `close_button_location='right'` puts the
// toggle at the RIGHT of the group, so the contents open to its LEFT — the
// button stays under the pointer that just clicked it rather than sliding away
// from it.
//
// The default property is the contents, so a caller writes:
//
//     WidgetBox {
//         closedGlyph: ...; openGlyph: ...
//         Chip { ... }
//         Chip { ... }
//     }
//
// ---- THE GLYPHS ARE qtile's OWN, SUPPLEMENTARY PLANE AND ALL ----
//
// NEXT-SESSION.md records that "supplementary-plane Nerd Font glyphs do not
// render — U+F022C and neighbours paint nothing, while BMP ones render in the
// same widget", and concludes that anything drawn in this shell should stay in
// the BMP private-use block.
//
// That conclusion is too broad, and this bar is the counter-example. Probed
// here by rendering twelve codepoints side by side in a panel and looking at
// them: U+F0570, U+F0336, U+F0335, U+F05AF, U+F0902, U+F0042 and U+F035C —
// all supplementary — drew correctly, in the SAME run as the BMP ones. The
// variable is the FACE, not the plane: these render in "Symbols Nerd Font".
//
// So the toggles below use qtile's exact codepoints and the bar is faithful
// rather than approximated. They must be written with String.fromCodePoint
// and not fromCharCode: the latter takes a UTF-16 code unit and silently
// truncates anything above U+FFFF.
Item {
    id: root

    default property alias content: contentRow.data

    property int codepointClosed: 0
    property int codepointOpen: 0
    property color foreground: BarTheme.fg
    property int fontPixelSize: Metrics.s(12)
    property int padding: 11
    property bool open: false
    // Forwarded to the toggle chip, so hovering a collapsed box says what is
    // inside it — which is the one place a tooltip earns its keep most.
    property string tooltip: ""
    property var hoverSink: null

    implicitWidth: layout.implicitWidth

    implicitHeight: parent ? parent.height : Metrics.barHeight

    Row {
        id: layout
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0

        // The contents, LEFT of the toggle. Width animates so the right-hand
        // side of the bar does not teleport — the tasklist cap in shell.qml is
        // bound to rightGroup.width and would otherwise jump with it.
        Item {
            id: clipper
            height: root.height
            width: root.open ? contentRow.implicitWidth : 0
            clip: true

            // NO `visible: width > 0` HERE, and that is not an omission.
            //
            // It was written that way first and produced a box that toggled
            // its GLYPH and never revealed anything. The three bindings
            // deadlock at zero: this Item's visibility would depend on its
            // width, its width depends on contentRow.implicitWidth, and a Row
            // counts only VISIBLE children — which its children are not,
            // because an item whose parent is invisible reports visible
            // false. Nothing in that cycle can ever become non-zero.
            //
            // Diagnosed by logging the children rather than by staring at it:
            // they had their text ("82%", "4811M") and w=0, v=false.
            //
            // A zero-width Item draws nothing anyway, and `clip` already
            // stops the contents spilling while the width animates, so the
            // gate bought nothing even before it deadlocked.

            Behavior on width {
                NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
            }

            Row {
                id: contentRow
                height: parent.height
                spacing: 0
                // Anchored RIGHT so the group grows leftwards out of the
                // button rather than sliding out from under it.
                anchors.right: parent.right
            }
        }

        Chip {
            text: root.open
                ? String.fromCodePoint(root.codepointOpen)
                : String.fromCodePoint(root.codepointClosed)
            foreground: root.foreground
            fontPixelSize: root.fontPixelSize
            fontFamily: "Symbols Nerd Font"
            padding: root.padding
            clickable: true
            height: root.height
            tooltip: root.tooltip
            hoverSink: root.hoverSink
            onClicked: root.open = !root.open
        }
    }
}
