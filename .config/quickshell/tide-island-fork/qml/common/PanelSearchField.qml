pragma ComponentBehavior: Bound

import QtQuick

// Sibling-relative, because this file IS in qml/common. Metrics is a .js
// LIBRARY and not a singleton: without this import every px()/pad()/font()
// below resolves to undefined at runtime, the file still loads, and every
// size collapses to zero with `ReferenceError: Metrics is not defined` in
// the shell log as the only evidence. That has cost this fork a session
// once already — see upgread_UI_UX.md on the onboarding layer.
import "Metrics.js" as Metrics

//
// FORK — new file. The rofi search bar, once, for every panel that lists
// things.
//
// WHY THIS EXISTS
// ---------------
// Asked for directly: "the power popop theme popup and some other popups
// need searchh bar like its rofi one". Three panels already had three
// answers to that, and the differences between them were not design:
//
//   ApplicationLauncherLayer   a real TextInput, always on screen
//   CheatsheetLayer            a real TextInput, always on screen
//   ThemePickerLayer           NO field. `/` set `searching = true` and
//                              every subsequent keypress was appended to a
//                              string by hand, one `event.text` at a time
//   WallpaperPickerLayer       the same hand-rolled `/` gate again
//   PowerMenuLayer             nothing at all
//
// The `/` gate is the part the user is actually reporting. It is vi's
// idea of search, not rofi's: rofi has no search MODE, it has a field that
// is always there and always focused, and you filter by typing the way you
// would into any other box. A search you must first ask for is a search
// most people never find — and this shell's own cheatsheet already had the
// better answer, which is what made the inconsistency worth removing
// rather than the missing field worth adding twice more.
//
// It is also two hand-rolled key handlers fewer. `searchQuery += event.text`
// re-implements a text field: it has no selection, no clipboard, no cursor,
// no IME, and no way to click into the middle of what you typed. Every one
// of those came free with the TextInput the other two panels already used.
//
// WHAT THE HOST STILL OWNS
// ------------------------
// This is a FIELD, not a controller. It owns the text and the keys that
// belong to a text field; it emits everything else and knows nothing about
// what is being filtered. That is deliberate — the theme picker moves
// through a grid, the power menu through a list, the wallpaper picker
// through a carousel, and a component that tried to serve all three would
// need to know which it was in.
//
// THE ONE BEHAVIOUR CHANGE, AND IT IS THE POINT
// ---------------------------------------------
// Letters TYPE. They used to be motions — the theme picker read h/j/k/l,
// added deliberately so it would match every other panel in this shell.
// A field that is always focused cannot also spend the alphabet on
// navigation, and rofi resolves this the same way: arrows move, letters
// filter. Ctrl+N/Ctrl+P are carried over from rofi and from readline so
// the hand that does not want to leave the home row still has somewhere to
// go, and Ctrl+H/J/K/L map to the four motions for the same reason.
//
// ESCAPE IS TWO-STAGE, which is not rofi's behaviour and is deliberate: a
// query you have typed is state you can lose by accident, and a panel you
// opened is not. So Esc clears a non-empty query and only closes on the
// second press. `escapeClearsQuery` turns that off for a host that wants
// one-press dismissal.
//
Item {
    id: root

    // ---- what the host reads ----
    property string query: ""
    // Whether the field itself currently holds keyboard focus — for a host
    // that wants to refresh `query` from an external source (the calendar's
    // cursor moving under a live hover) without clobbering text the user is
    // mid-typing. Read-only: the host asks, it does not set this.
    readonly property alias focused: input.activeFocus

    // ---- what the host sets ----
    property string placeholder: "type to filter"
    property string textFontFamily: ""
    property string iconFontFamily: ""
    // The glyph in the left gutter. Defaults to the magnifier, because every
    // host but one is a search; the calculator sets its own. Assigned from
    // the codepoint rather than pasted, since a private-use character does
    // not survive being written into a file by anything that reads it back
    // as text — that cost this component its icon once already.
    property string icon: String.fromCharCode(0xf002)
    // Right-hand side of the field. A count, "3 of 21", "no match" — the
    // host knows what it is counting, so it says so rather than being asked.
    property string countText: ""
    property bool escapeClearsQuery: true

    // ---- HANDING THE KEYBOARD BACK ----
    //
    // Set by a host that needs the keys for something modal — the power
    // menu's y/n confirmation is the case this was written for. While it is
    // true the field types nothing and claims nothing, so every key reaches
    // the host's own Keys handler.
    //
    // It exists because the obvious way to do this DOES NOT WORK, and the
    // failure is quiet. The host's first attempt was `root.forceActiveFocus()`
    // on its FocusScope to pull focus off the field — but calling
    // forceActiveFocus() on a FocusScope gives active focus to the scope's
    // focus CHILD, which is this TextInput. Focus never moved. What happened
    // instead was that the TextInput inserted the character and the event
    // then bubbled up to the host, so `n` both cancelled the confirmation and
    // typed an `n`: measured on screen, the field read "reloadn" and the
    // match count fell to 0 of 6 the moment the dialog was dismissed.
    //
    // A read-only TextInput keeps focus and inserts nothing, which is exactly
    // the wanted behaviour and needs no focus juggling at all.
    property bool readOnly: false

    // ---- what the host listens to ----
    signal submitted            // Enter
    signal cancelled            // Esc, after the clear stage
    signal moved(int delta)     // Up/Down, Ctrl+P/N, Ctrl+K/J
    signal movedHorizontally(int delta)  // Left/Right, Ctrl+H/L
    signal paged(int pages)     // PageUp/PageDown
    signal tabbed(int direction) // Tab / Shift+Tab, for panels with sheets
    // Ctrl+C with NOTHING SELECTED. With a selection it is left alone, so
    // the field keeps the copy behaviour every text box has; the host only
    // hears about the case where the standard action would be a no-op and
    // the user plainly meant "copy the thing this panel is showing me".
    signal copyRequested()

    implicitHeight: Metrics.px(26)
    height: implicitHeight

    function focusField() {
        input.forceActiveFocus();
    }

    function clear() {
        input.text = "";
    }

    // Replace the contents and put the cursor at the end — the calculator's
    // history recall, where the recalled expression is usually about to be
    // edited. Assigning `query` from outside would not do it: `query` is
    // driven BY the input, not the other way round.
    function setText(value) {
        input.text = String(value);
        input.cursorPosition = input.text.length;
    }

    // Move the text cursor without typing — for a host that wants hjkl-style
    // character movement while `readOnly` is on (PROMPT-NEXT.md item 6, the
    // calculator's normal mode). A `readOnly` TextInput still has a cursor
    // position and still draws it while focused; the field only refuses to
    // let KEYSTROKES change the text, and this does not go through a
    // keystroke. `Math.max/min` clamp rather than wrap — vi's `h`/`l` stop
    // at the ends of the line, they do not carry into the next one, and
    // there is no next line here.
    function moveCursor(delta) {
        input.cursorPosition = Math.max(0, Math.min(input.text.length,
                                                     input.cursorPosition + delta));
    }

    // The host's own Keys handler is usually on an ancestor, so anything
    // this field does not claim arrives there anyway. What it claims is
    // exactly the set above — everything else falls through to the field
    // and types, which is the behaviour the panel is built around.
    Rectangle {
        id: field
        anchors.fill: parent
        radius: Metrics.px(8)
        color: input.activeFocus ? IslandTheme.inputFillFocused : IslandTheme.inputFill
        border.width: 1
        border.color: input.activeFocus ? IslandTheme.inputBorderFocused : IslandTheme.inputBorder

        Behavior on color { ColorAnimation { duration: 140 } }
        Behavior on border.color { ColorAnimation { duration: 140 } }

        Text {
            id: icon
            anchors.left: parent.left
            anchors.leftMargin: Metrics.pad(10)
            anchors.verticalCenter: parent.verticalCenter
            text: root.icon
            color: input.activeFocus ? IslandTheme.textSecondary : IslandTheme.textMuted
            font.family: root.iconFontFamily
            font.pixelSize: Metrics.font(11)
        }

        TextInput {
            id: input
            anchors.left: icon.right
            anchors.leftMargin: Metrics.pad(9)
            anchors.right: count.left
            anchors.rightMargin: Metrics.pad(9)
            anchors.verticalCenter: parent.verticalCenter
            color: IslandTheme.textPrimary
            selectionColor: IslandTheme.accent
            selectedTextColor: IslandTheme.accentInk
            font.family: root.textFontFamily
            font.pixelSize: Metrics.font(11)
            clip: true
            selectByMouse: true
            readOnly: root.readOnly

            onTextChanged: {
                if (root.query !== text)
                    root.query = text;
            }

            // Kept in step when the HOST assigns query — clearing it on
            // close, say. Guarded both ways so the two assignments cannot
            // ping-pong.
            Connections {
                target: root
                function onQueryChanged() {
                    if (input.text !== root.query)
                        input.text = root.query;
                }
            }

            Keys.onPressed: event => {
                // Claim NOTHING while the host is modal. Returning without
                // accepting is what lets Escape, Enter and the letters reach
                // the host's confirmation branch unmodified.
                if (root.readOnly)
                    return;

                // Ctrl first: Ctrl+H is also Backspace's control code on a
                // terminal, and testing the plain keys first would eat it.
                if (event.modifiers & Qt.ControlModifier) {
                    switch (event.key) {
                    case Qt.Key_N: case Qt.Key_J:
                        root.moved(1); event.accepted = true; return;
                    case Qt.Key_P: case Qt.Key_K:
                        root.moved(-1); event.accepted = true; return;
                    case Qt.Key_H:
                        root.movedHorizontally(-1); event.accepted = true; return;
                    case Qt.Key_L:
                        root.movedHorizontally(1); event.accepted = true; return;
                    case Qt.Key_C:
                        // Only when the standard action would do nothing.
                        if (input.selectedText === "") {
                            root.copyRequested();
                            event.accepted = true;
                        }
                        return;
                    }
                    return;
                }

                switch (event.key) {
                case Qt.Key_Escape:
                    if (root.escapeClearsQuery && input.text !== "")
                        input.text = "";
                    else
                        root.cancelled();
                    event.accepted = true;
                    break;
                case Qt.Key_Return:
                case Qt.Key_Enter:
                    root.submitted();
                    event.accepted = true;
                    break;
                case Qt.Key_Down:
                    root.moved(1); event.accepted = true; break;
                case Qt.Key_Up:
                    root.moved(-1); event.accepted = true; break;
                case Qt.Key_Left:
                    root.movedHorizontally(-1); event.accepted = true; break;
                case Qt.Key_Right:
                    root.movedHorizontally(1); event.accepted = true; break;
                case Qt.Key_PageDown:
                    root.paged(1); event.accepted = true; break;
                case Qt.Key_PageUp:
                    root.paged(-1); event.accepted = true; break;
                case Qt.Key_Tab:
                    root.tabbed(1); event.accepted = true; break;
                case Qt.Key_Backtab:
                    root.tabbed(-1); event.accepted = true; break;
                }
            }

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                visible: parent.text === ""
                text: root.placeholder
                color: IslandTheme.textDisabled
                font.family: root.textFontFamily
                font.pixelSize: Metrics.font(11)
                elide: Text.ElideRight
                width: parent.width
            }
        }

        Text {
            id: count
            anchors.right: parent.right
            anchors.rightMargin: Metrics.pad(10)
            anchors.verticalCenter: parent.verticalCenter
            text: root.countText
            color: IslandTheme.textMuted
            font.family: root.textFontFamily
            font.pixelSize: Metrics.font(10)
        }
    }
}
