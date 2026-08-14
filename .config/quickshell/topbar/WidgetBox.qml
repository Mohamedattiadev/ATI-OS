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

    // ---- THE TWO STATES DO NOT SHARE A SIZE ----
    //
    // config.py's systray_widgetbox carries `raw_markup=True` and puts the
    // size INSIDE text_closed's span rather than on the widget, and says why:
    // the number on the widget sizes the close CHEVRON, and sharing one
    // "made the chevron balloon when the triangle was scaled up".
    //
    // This box had only the widget's number, so the triangle was drawn at the
    // chevron's 11 px — reported as "the triangle shape is small, make it a
    // bit bigger". It is not a matter of taste: qtile draws it at
    // `size="15500"`, and a pango size attribute is in POINTS while the
    // widget's fontsize reaches pango as absolute PIXELS, so the two numbers
    // are not comparable and the smaller one is not the smaller glyph.
    //
    // Measured rather than converted, since that ambiguity is exactly what
    // makes it worth measuring. Rendering config.py's span verbatim through
    // pango-view and trimming to the ink:
    //
    //     pango, qtile's own markup       12x9
    //     Qt / Adwaita Mono Bold, 20 px   12x9   <- match
    //     Qt / Adwaita Mono Bold, 11 px    6x5   <- what was on screen
    //
    // config.py's own sweep of that attribute agrees from the other side:
    // "14000 -> 11x10, 16000 -> 12x10". Its `rise="7000"` is left out; the
    // same note sweeps it and records 6000 and 8000 as ±0.5 px, so it is
    // a nudge below this bar's resolution rather than a placement.
    //
    // Not expressed as a property here: `fontPixelSize` is what the CALLER
    // sets on three of these four boxes, and a binding in this file would be
    // silently replaced by each of those assignments. The one box that needs
    // two sizes writes the conditional at its own call site, where the
    // override cannot be overridden in turn. See shell.qml's systrayBox.
    clickable: true

    onClicked: root.toggle()
}
