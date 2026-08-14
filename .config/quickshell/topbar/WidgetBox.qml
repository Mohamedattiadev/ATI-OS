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

    // ---- THE OPEN FLAG IS THE SHELL'S, NOT THIS CHIP'S ----
    //
    // It used to be state here, flipped by the chip's own click. Two things
    // broke that. A `Variants` builds one bar PER SCREEN, so a box opened on
    // one monitor stayed shut on the other — the same widget disagreeing with
    // itself. And qtile binds these boxes to KEYS as well as to clicks
    // ($alt ` system, $mod ` 2nd system, $alt Tab tray), which a script has to
    // be able to reach; a flag private to a delegate cannot be driven at all.
    //
    // So the flag lives on the shell root, the chip only ASKS for it to
    // change, and the IPC and the pointer end up in the same place.
    property bool open: false
    signal toggle()

    text: root.open
        ? String.fromCodePoint(root.codepointOpen)
        : String.fromCodePoint(root.codepointClosed)
    // The FACE follows the codepoint, which is what qtile does implicitly by
    // letting widget_defaults' font handle anything the Nerd Font set does
    // not own. Two of these toggles are NOT Nerd Font icons and config.py
    // says so at both: U+2716 is "a plain heavy multiplication X" and U+25B3
    // "a plain geometric shape rather than an icon from the nerd font set,
    // chosen for its silhouette". Forcing them through Symbols Nerd Font drew
    // a different, heavier mark than qtile's — visible side by side against
    // the real bar.
    //
    // U+E000 is the start of the private-use area, so this is the actual
    // boundary between "Nerd Font glyph" and "ordinary character" rather than
    // a list of exceptions to keep up to date.
    //
    // "Adwaita Mono" and not the bar's own "Ubuntu Bold", because Ubuntu has
    // neither of these characters and the two toolkits then fall back
    // DIFFERENTLY — that is the whole of the difference. Asked directly:
    //
    //     fc-match -s "Ubuntu Bold:charset=2716"
    //       1. Adwaita Mono Regular        <- what pango, and so qtile, draws
    //       2. Noto Sans Symbols 2
    //       3. Font Awesome 7 Free Solid   <- what Qt was drawing: a heavy
    //                                         filled cross, visibly bolder
    //                                         than qtile's beside it
    //
    // Naming fontconfig's first choice explicitly makes Qt pick the face
    // pango already picks, rather than leaving it to two different fallback
    // orders to agree by luck.
    fontFamily: (root.open ? root.codepointOpen : root.codepointClosed) < 0xE000
        ? "Adwaita Mono" : "Symbols Nerd Font"
    clickable: true

    onClicked: root.toggle()
}
