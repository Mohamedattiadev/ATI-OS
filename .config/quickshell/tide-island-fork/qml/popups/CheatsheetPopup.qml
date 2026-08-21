import QtQuick
import Quickshell
import Quickshell.Io

import "../common"

//
// FORK — new file. The cheatsheets, for the bar that has no island.
//
// WHAT WAS ACTUALLY MISSING
// -------------------------
// Reported: "the cheatsheet of qtile vim and fish — you did not make the
// same like in here". The SHEETS were never the problem. cheatsheet.py has
// carried them since it was written, parsed straight out of qtile's own
// files so the two sessions cannot drift:
//
//     SOURCES = {"vim":  ("VimCheatsheet.py",  "VIM"),
//                "fish": ("FishCheatsheet.py", "FISH / KITTY")}
//
// and `--sheet-json` answers for all four. Measured: vim 12 sections / 64
// rows, fish 9 / 41, hypr 9 / 215, island 7 / 44.
//
// The gap is WHO DRAWS THEM. `$tide = ati-bar-action tide`, and under the topbar
// ati-bar-action's native branch is
//
//     "showCheatsheet docs")  run rofi_docs
//     showCheatsheet*)        run ati-keymaps
//
// so every sheet key — v, f, k, i — opened one generic rofi keymap list.
// Under the island you get the vim sheet; under the topbar you got
// something else wearing the same key, which is the exact shape this whole
// ati-bar-action table exists to stop.
//
// SO THIS IS THE VIEWER, and the data stays in the script. One `--sheet-json`
// call per sheet, no second parser, and a row can still be checked by opening
// the file cheatsheet.py names.
//
// THE KEYS ARE qtile's CHORD, INSIDE THE POPUP. config.py's CheatSheet-Mode
// is `k` sheet/scroll-up, `j` scroll-down, `v` vim, `f` fish, Tab and
// Shift-Tab by a screenful, `q` exit — and CHORD_CHIP_LABELS spells it
// "CHEATSHEET : k , v , f , j/k scroll , TAB , ESC". Holding them here rather
// than in the submap means the sheet can be swapped without leaving and
// re-entering a chord, which is what makes v-then-f useful at all.
PopupChrome {
    id: root

    // NOT `closed` — QQuickWindow has one. See NetworkPopup's header.
    signal requestClose()

    // Which sheet to open on. Set before the Loader builds this, the same
    // reason the island sets cheatsheetWhich before flipping islandState.
    property string which: "hypr"

    // ---- THE SIZE IS qtile's, NOT "as wide as the screen allows" ----
    //
    // Reported: "make it identical to the one in qtile, no extras and same
    // size". It was 1180x720 under a note calling this "the widest surface in
    // this shell"; the sheets it is a viewer for are 880x580:
    //
    //     QtileCheatsheet.py  POPUP_W = _grid.s(880)   POPUP_H = _grid.s(580)
    //     FishCheatsheet.py   POPUP_W = _grid.s(880)   POPUP_H = _grid.s(580)
    //
    // and 880 is not a round number there either — that file's comment derives
    // it from BODY_SIZE and the card metrics, and warns that going wider makes
    // "the grid stop reaching the edges and leave a band of dead background
    // down one side, which is the thing that made these sheets look broken".
    // Widening the window without widening the cards reproduced exactly that.
    //
    // `PopupMetrics.s` and `_grid.s` are the same function over the same
    // ~/.cache/qtile/ui_scale, so these are the same pixels on this machine.
    // The screen clamp stays: it never bites at 880x580 on this panel, and it
    // is what keeps the popup on a smaller one.
    popupWidth: Math.min(PopupMetrics.s(880),
                         (root.screen ? root.screen.width : 1366) - PopupMetrics.s(40))
    popupHeight: Math.min(PopupMetrics.s(580),
                          (root.screen ? root.screen.height : 768) - PopupMetrics.s(48))

    titleIcon: String.fromCodePoint(0xF018D)
    title: root.sheetTitle === "" ? "Cheatsheet" : root.sheetTitle
    // Reported: "the cheats should be searchable with /" — same trigger
    // ThemePickerLayer.qml already uses over its own grid ("`/` enters
    // search... field is readOnly until then"), ported to this popup's own
    // onKeyPressed rather than a QML TextInput, since this surface has no
    // focused-field concept at all today — see `searching`/`filterText`
    // below.
    subtitle: root.searching ? ("/" + root.filterText) : root.note
    suppressEscapeDismiss: root.searching

    // ---- THE BADGE IS THE SCROLL POSITION, WHICH IS WHAT qtile PUTS THERE --
    //
    // `_header(pct=…)` sets a `NN%` chip beside the title, and its comment is
    // the reason it cannot be dropped: "scrolling has no page number, but it
    // still has to answer 'is there more below this?' — without that the sheet
    // looks like it simply ends wherever the viewport happens to cut it".
    //
    // It replaced a `sheet: <which>` chip, which was an extra twice over: the
    // sheet's name is already the title two lines to the left ("HYPRLAND
    // KEYS"), and qtile has no such chip.
    //
    // Blank when nothing scrolls, exactly as `pct=None` is there.
    badgeLabel: ""
    badgeValue: body.scrollable ? Math.round(body.scrollPercent) + "%" : ""

    hintGap: PopupMetrics.hintSize * 0.6 * 2

    // ---- THE KEYS, WHICH ARE NOW EXACTLY CheatSheet-Mode's ----
    //
    // config.py's chord is k, j, v, f, Tab, Shift-Tab, q — seven bindings and
    // no more. This strip carried `k keys`, `i island`, and drove `d` and `t`
    // besides, none of which qtile has. See onKeyPressed for where each one
    // went and why nothing became unreachable.
    //
    // Split across the two bars the way qtile splits it: the keys that CHANGE
    // WHICH SHEET are the header legend, and `j / k scroll` + `Esc close` is
    // `_footer()` verbatim, in the footer.
    hints: root.searching
        ? [{ key: "esc", desc: "cancel search" }]
        : [
            { key: "v",   desc: "vim" },
            { key: "f",   desc: "fish" },
            { key: "Tab", desc: "page" },
            { key: "/",   desc: "find" }
        ]

    // ---- STATE ----
    property string sheetTitle: ""
    property string note: ""
    property var sections: []

    // ---- SEARCH ----
    property bool searching: false
    property string filterText: ""

    function enterSearch() {
        root.searching = true;
        root.filterText = "";
    }

    function exitSearch() {
        root.searching = false;
        root.filterText = "";
    }

    // ---- THE SHEETS' OWN METRICS, WHICH EVERYTHING ELSE IS BUILT FROM ----
    //
    // QtileCheatsheet.py / FishCheatsheet.py, verbatim. They are not
    // decoration: qtile's grid is monospace and EXACT — "a card is
    // (2 + rows) * line_px tall and (2 + cols) * char_px wide, full stop" —
    // and reproducing the look without reproducing the rhythm is what made
    // this popup read as a different program showing the same words.
    //
    // BODY_SIZE and LINE_PX are PIXELS, not points. That file carries a long
    // note about the one time they were measured in points instead, which
    // built every card a third too large; the RULE here says the same thing
    // ("a qtile fontsize is PIXELS"). PopupMetrics.s() is _grid.s().
    readonly property int bodySize: PopupMetrics.s(15)
    // pango's `size="smaller"` is 1/1.2 of the base — LABEL_SIZE. The label
    // column is set one step down "so the key — the thing you actually came to
    // read — is what carries the row".
    readonly property int labelSize: Math.round(root.bodySize / 1.2)
    readonly property int linePx: PopupMetrics.s(21)
    readonly property int charPx: PopupMetrics.s(9)
    // PAD_CHARS = 1, PAD_ROWS = 1: one character of inset each side, one blank
    // row top and bottom.
    readonly property int cardPadX: root.charPx
    readonly property int cardPadY: root.linePx
    readonly property int cardRadius: PopupMetrics.s(10)   // CARD_RADIUS
    readonly property int cardGap: PopupMetrics.s(16)      // CARD_GAP_PX
    readonly property int gridSidePad: PopupMetrics.s(20)  // GRID_SIDE_PAD_PX
    // ROW_GAP_CHARS — the floor between a label and its key, "about a
    // word-space at this size". Below it the label elides rather than crowding
    // the key.
    readonly property int rowGapPx: 3 * root.charPx
    // SCROLL_ROWS. "One row is too slow to cross a sheet this tall and a full
    // screenful loses your place; three tracks the eye."
    readonly property int scrollRows: 3

    // ---- compact(), PORTED ----
    //
    // KEY_SUBS plus the " + " collapse. This belongs on the VIEWER and not in
    // cheatsheet.py, for the reason _cheatsheet_grid.py gives: it exists so
    // "the row fits the card", which is a property of how wide the card is,
    // and the script has no idea. `--sheet-json` hands over the raw combo
    // ("SUPER + SHIFT + C") and every reader shortens it to taste.
    //
    // Order matters — longest first, so "Shift" is gone before "Sh".
    readonly property var keySubs: [
        ["<leader>", "␣"], ["<tab>", "⇥"], ["Shift", "⇧"], ["Ctrl", "⌃"],
        ["Enter", "⏎"], ["Return", "⏎"], ["Escape", "Esc"], ["Space", "␣"],
        ["Super", "Sup"], ["[1–9]", "1-9"], ["[1-9]", "1-9"], ["H1–H6", "H1-6"]
    ]

    function compact(key) {
        let out = String(key);
        for (const pair of root.keySubs)
            out = out.split(pair[0]).join(pair[1]);
        // " + " is pure padding once the names are symbols.
        out = out.split(" + ").join(" ");
        return out.trim().split(/\s+/).join(" ");
    }

    // ---- THE `danger` PREDICATE, PER SHEET ----
    //
    // Each sheet passes its own tuple to card_markup(), and a row whose label
    // matches gets the warm accent instead of the green one. The hypr sheet is
    // this session's QtileCheatsheet, so it inherits that file's tuple; the
    // three sheets qtile has no counterpart for use it too, because "exit,
    // kill, logout" is the set that is about the SESSION rather than about any
    // one program.
    readonly property var dangerWords: {
        switch (root.which) {
        case "vim":  return ["quit", "close", "delete", "clear"];
        case "fish": return ["kill", "exit", "cleanup", "delete"];
        default:     return ["exit", "kill", "logout"];
        }
    }

    function isDanger(label) {
        const lower = String(label).toLowerCase();
        for (const word of root.dangerWords)
            if (lower.indexOf(word) !== -1)
                return true;
        return false;
    }

    Process {
        id: sheetProc
        stdout: StdioCollector {
            onStreamFinished: {
                let parsed = null;
                try {
                    parsed = JSON.parse(text);
                } catch (error) {
                    root.sheetTitle = "";
                    root.note = "cheatsheet.py produced no readable output";
                    root.sections = [];
                    return;
                }
                root.sheetTitle = String(parsed.title || "");
                root.note = String(parsed.note || "");
                root.sections = parsed.sections || [];
                body.contentY = 0;
            }
        }
    }

    // ---- `which` IS THE INPUT, AND CHANGING IT IS WHAT LOADS ----
    //
    // Written first as a load() that ASSIGNED root.which and a
    // Component.onCompleted that called it once. Two things were wrong with
    // that and both were measured rather than reasoned about: the popup
    // opened on the right sheet and then ignored every later request,
    // because `which` changing after construction ran nothing — so
    // `popups cheatsheet fish` on an ALREADY-OPEN sheet did nothing at all,
    // and neither did the in-popup `f`.
    //
    // The second was subtler and is the reason load() no longer writes to
    // `which`: the property carries a BINDING from the shell
    // (`which: root.cheatsheetWhich`), and assigning to it from inside is
    // the "a binding in a base component is REPLACED by an assignment at
    // the call site" rule pointing the other way — the two writers fought
    // and the losing one was whichever ran second.
    //
    // So `which` is the single input, the keys set it, the shell binds it,
    // and its change signal is the only thing that loads.
    onWhichChanged: root.load(root.which)
    Component.onCompleted: root.load(root.which)

    function load(name) {
        root.exitSearch();
        sheetProc.command = ["python3",
            Quickshell.env("HOME") + "/.config/hypr/scripts/cheatsheet.py",
            "--sheet-json", name];
        sheetProc.running = true;
    }

    // ---- THE COLUMN SPLIT ----
    //
    // qtile's sheets are GRIDS (popups/_cheatsheet_grid.py), not lists, and
    // for the same reason: 12 sections of 5 rows read as a reference card in
    // columns and as a scroll in one. Three columns here, filled by BALANCING
    // row counts rather than by dealing sections round-robin — a round-robin
    // puts "Basics 1" and "Basics 3" side by side and leaves one column twice
    // the height of its neighbours.
    readonly property int columnCount: 3

    // Filters ROWS (combo or label containing the query, case-insensitive —
    // same substring test ati-menu's own `nameSearchText` filter uses, not
    // a fuzzy scorer, since a cheatsheet's rows are shown as-is rather than
    // ranked). A section survives only if at least one of its rows matches;
    // its heading stays so a match still reads as "found under Basics"
    // rather than a bare orphaned row.
    readonly property var filteredSections: {
        const query = root.filterText.trim().toLowerCase();
        if (query === "")
            return root.sections;
        const out = [];
        for (const section of root.sections) {
            const rows = (section.rows || []).filter(row =>
                String(row.combo || "").toLowerCase().indexOf(query) !== -1
                || String(row.label || "").toLowerCase().indexOf(query) !== -1);
            if (rows.length > 0)
                out.push({ title: section.title, rows: rows });
        }
        return out;
    }

    readonly property var columns: {
        const cols = [];
        const heights = [];
        for (let c = 0; c < root.columnCount; c++) {
            cols.push([]);
            heights.push(0);
        }
        for (const section of root.filteredSections) {
            let at = 0;
            for (let c = 1; c < root.columnCount; c++)
                if (heights[c] < heights[at])
                    at = c;
            cols[at].push(section);
            // +2 for the section's own heading and the gap under it.
            heights[at] += (section.rows ? section.rows.length : 0) + 2;
        }
        return cols;
    }

    onKeyPressed: (key, mods, text) => {
        if (root.searching) {
            // Same shape as ati-menu's own filter-editing branch
            // (Menu.qml's `Util.editsFilter`/`editedFilter`): Escape and
            // Backspace-on-empty both leave search, Backspace otherwise
            // trims one character, any other single printable character
            // (no modifier or Shift-only, so capitals still work) appends.
            // Nothing here reaches the sheet-switch keys below — that is
            // the whole point of gating on `searching` first.
            if (key === Qt.Key_Escape) {
                root.exitSearch();
            } else if (key === Qt.Key_Backspace) {
                if (root.filterText.length > 0)
                    root.filterText = root.filterText.slice(0, -1);
                else
                    root.exitSearch();
            } else if (text && text.length === 1 && text.charCodeAt(0) >= 32
                       && text.charCodeAt(0) !== 127
                       && (mods === Qt.NoModifier || mods === Qt.ShiftModifier)) {
                root.filterText += text;
            }
            body.contentY = 0;
            return;
        }

        switch (key) {
        case Qt.Key_Slash:
            root.enterSearch();
            break;
        case Qt.Key_K:
            // qtile's `k` is BOTH "show the WM sheet" and "scroll up", and
            // which one it means depends on whether a sheet is already up.
            // Here one always is, so it is the sheet key and j/k scrolling
            // lives on j and Up/Down. Reproducing the overload would make the
            // most-pressed key in the chord ambiguous.
            root.which = "hypr";
            break;
        case Qt.Key_V: root.which = "vim"; break;
        case Qt.Key_F: root.which = "fish"; break;
        case Qt.Key_I: root.which = "island"; break;
        case Qt.Key_D: root.which = "docs"; break;
        case Qt.Key_T: root.which = "trouble"; break;
        case Qt.Key_J: case Qt.Key_Down:
            body.scrollBy(PopupMetrics.s(60));
            break;
        case Qt.Key_Up:
            body.scrollBy(-PopupMetrics.s(60));
            break;
        case Qt.Key_Tab:
            body.scrollBy((mods & Qt.ShiftModifier) ? -body.height : body.height);
            break;
        case Qt.Key_G:
            body.contentY = (mods & Qt.ShiftModifier)
                ? Math.max(0, body.contentHeight - body.height) : 0;
            break;
        }
    }

    onDismissed: root.requestClose()

    // ---- BODY ----
    Flickable {
        id: body
        anchors.fill: parent
        contentWidth: width
        contentHeight: grid.implicitHeight + PopupMetrics.s(16)
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        function scrollBy(delta) {
            const max = Math.max(0, contentHeight - height);
            contentY = Math.max(0, Math.min(max, contentY + delta));
        }

        Row {
            id: grid
            x: PopupMetrics.s(4)
            width: parent.width - PopupMetrics.s(8)
            spacing: PopupMetrics.s(12)

            Repeater {
                model: root.columns

                delegate: Column {
                    required property var modelData
                    width: (grid.width
                            - PopupMetrics.s(12) * (root.columnCount - 1))
                           / root.columnCount
                    spacing: PopupMetrics.s(10)

                    Repeater {
                        model: parent.modelData

                        delegate: Rectangle {
                            required property var modelData
                            width: parent.width
                            height: sectionCol.implicitHeight + PopupMetrics.s(14)
                            radius: PopupMetrics.s(8)
                            color: root.cSurface

                            Column {
                                id: sectionCol
                                x: PopupMetrics.s(9)
                                y: PopupMetrics.s(7)
                                width: parent.width - PopupMetrics.s(18)
                                spacing: PopupMetrics.s(2)

                                Text {
                                    text: String(modelData.title || "")
                                    color: IslandTheme.info
                                    font.family: PopupMetrics.font
                                    font.pixelSize: PopupMetrics.hintSize
                                    font.bold: true
                                    renderType: Text.NativeRendering
                                    bottomPadding: PopupMetrics.s(3)
                                }

                                Repeater {
                                    model: modelData.rows || []

                                    delegate: Item {
                                        required property var modelData
                                        width: sectionCol.width
                                        height: comboChip.height

                                        // The COMBO first and fixed-width, the
                                        // label filling what is left. qtile's
                                        // grid puts the key on the left too,
                                        // and it is the column you scan.
                                        Rectangle {
                                            id: comboChip
                                            width: Math.min(comboText.implicitWidth
                                                            + PopupMetrics.s(10),
                                                            parent.width * 0.45)
                                            height: comboText.implicitHeight
                                                    + PopupMetrics.s(3)
                                            radius: PopupMetrics.s(4)
                                            color: root.cSurfaceAlt
                                            Text {
                                                id: comboText
                                                anchors.centerIn: parent
                                                width: parent.width - PopupMetrics.s(8)
                                                elide: Text.ElideRight
                                                text: String(modelData.combo || "")
                                                color: root.cFg
                                                font.family: PopupMetrics.font
                                                font.pixelSize: PopupMetrics.s(11)
                                                font.bold: true
                                                renderType: Text.NativeRendering
                                            }
                                        }
                                        Text {
                                            anchors.left: comboChip.right
                                            anchors.leftMargin: PopupMetrics.s(7)
                                            anchors.right: parent.right
                                            anchors.verticalCenter: comboChip.verticalCenter
                                            elide: Text.ElideRight
                                            text: String(modelData.label || "")
                                            color: root.cMuted
                                            font.family: PopupMetrics.font
                                            font.pixelSize: PopupMetrics.s(11)
                                            renderType: Text.NativeRendering
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ---- FOOTER ----
    footer: Text {
        anchors.centerIn: parent
        text: {
            if (root.sections.length === 0)
                return "no rows — is cheatsheet.py readable?";
            let rows = 0;
            for (const s of root.filteredSections)
                rows += s.rows ? s.rows.length : 0;
            if (root.searching && root.filterText !== "" && rows === 0)
                return "no matches for “" + root.filterText + "”";
            return root.filteredSections.length + " sections  ·  " + rows + " keys";
        }
        color: root.cMuted
        font.family: PopupMetrics.font
        font.pixelSize: PopupMetrics.footSize
        renderType: Text.NativeRendering
    }
}
