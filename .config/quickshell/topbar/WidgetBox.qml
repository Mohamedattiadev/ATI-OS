import QtQuick

//
// qtile's SmartWidgetBox, reduced to what it actually is here: a toggle.
//
// It used to hold its own contents and reveal them in place, which is where
// config.py's `close_button_location='right'` puts them — between the lamp
// and the button. That was changed on request: the contents of every box now
// open in ONE shared area at the far left of the right-hand cluster, left of
// the lamp chip. See BoxContent.qml.
//
// So this is a Chip with two glyphs and an `open` flag. The contents that
// belong to it live in the expansion area and bind to that flag, which keeps
// the boxes independent exactly as qtile's are — more than one can be open,
// and they sit beside each other rather than fighting for one slot.
//
// ---- THE GLYPHS ARE qtile's OWN, SUPPLEMENTARY PLANE AND ALL ----
//
// NEXT-SESSION.md records that supplementary-plane Nerd Font glyphs paint
// nothing here. Too broad, and this bar is the counter-example: probed by
// rendering twelve codepoints side by side, U+F0570, U+F0336, U+F0335,
// U+F05AF, U+F0902, U+F0042 and U+F035C all drew correctly, in the same run
// as the BMP ones. The variable is the FACE — they render in "Symbols Nerd
// Font".
//
// Written with String.fromCodePoint and never fromCharCode: the latter takes
// a UTF-16 code unit and silently truncates anything above U+FFFF.
Chip {
    id: root

    property int codepointClosed: 0
    property int codepointOpen: 0
    property bool open: false

    text: root.open
        ? String.fromCodePoint(root.codepointOpen)
        : String.fromCodePoint(root.codepointClosed)
    fontFamily: "Symbols Nerd Font"
    clickable: true

    onClicked: root.open = !root.open
}
