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
// The gap is WHO DRAWS THEM. `$tide = bar-action tide`, and under the topbar
// bar-action's native branch is
//
//     "showCheatsheet docs")  run rofi_docs
//     showCheatsheet*)        run rofi_keymaps
//
// so every sheet key — v, f, k, i — opened one generic rofi keymap list.
// Under the island you get the vim sheet; under the topbar you got
// something else wearing the same key, which is the exact shape this whole
// bar-action table exists to stop.
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

    // The cheatsheet is the widest surface in this shell and clamped only by
    // the screen — the island's own note: a row is a key chip plus a command,
    // some of which are full paths, and the alternative to width is eliding
    // the half of the row that says what the key does.
    popupWidth: Math.min(PopupMetrics.s(1180),
                         (root.screen ? root.screen.width : 1366) - PopupMetrics.s(40))
    popupHeight: Math.min(PopupMetrics.s(720),
                          (root.screen ? root.screen.height : 768) - PopupMetrics.s(48))

    titleIcon: String.fromCodePoint(0xF018D)
    title: root.sheetTitle === "" ? "Cheatsheet" : root.sheetTitle
    subtitle: root.note

    badgeLabel: "sheet"
    badgeValue: root.which

    hintGap: PopupMetrics.hintSize * 0.6

    hints: [
        { key: "k",   desc: "keys" },
        { key: "v",   desc: "vim" },
        { key: "f",   desc: "fish" },
        { key: "i",   desc: "island" },
        { key: "jk",  desc: "scroll" },
        { key: "Tab", desc: "page" },
        { key: "Esc", desc: "close" }
    ]

    // ---- STATE ----
    property string sheetTitle: ""
    property string note: ""
    property var sections: []

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
    readonly property var columns: {
        const cols = [];
        const heights = [];
        for (let c = 0; c < root.columnCount; c++) {
            cols.push([]);
            heights.push(0);
        }
        for (const section of root.sections) {
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
        switch (key) {
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
            let rows = 0;
            for (const s of root.sections)
                rows += s.rows ? s.rows.length : 0;
            return root.sections.length === 0
                ? "no rows — is cheatsheet.py readable?"
                : root.sections.length + " sections  ·  " + rows + " keys";
        }
        color: root.cMuted
        font.family: PopupMetrics.font
        font.pixelSize: PopupMetrics.footSize
        renderType: Text.NativeRendering
    }
}
