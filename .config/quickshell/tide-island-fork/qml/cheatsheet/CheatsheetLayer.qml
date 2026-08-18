pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "../common/Metrics.js" as Metrics
// FORK: the shared motion system — one spring for geometry, one
// critically damped curve for opacity. See qml/common/Motion.js.
import "../common/Motion.js" as Motion
import "../common/Match.js" as Match
import "../common"

//
// FORK — new file. The cheatsheets, in the island instead of in rofi.
//
// WHY THIS EXISTS WHEN cheatsheet.py ALREADY WORKED
// -------------------------------------------------
// It worked, and REQUIREMENTS.md item 3 had a rule that said it should
// stay as it was: rebuild the *interactive* popups in the shell, leave the
// *launcher* problems on rofi, because a cheatsheet is a list you read and
// dismiss and rofi already solves that shape for free. The rule was
// overruled — every other surface in this session lives in the notch, and
// a rofi window opening over the desktop for the one chord that is
// supposed to explain the desktop was the odd one out.
//
// So the reasoning that kept it on rofi is not wrong, it is just no longer
// the deciding factor. What it DID get right is the thing this file has to
// carry over, and the reason this is not merely a text dump:
//
//   **rofi's real contribution was not the window, it was the typing.**
//
// qtile's CheatSheet-Mode spent four of its sixteen bindings (j, k, Tab,
// Shift+Tab) moving a viewport around 129 rows. rofi replaced all four
// with a search field. A QML panel that renders 192 rows and makes you
// scroll them would be a regression past rofi and most of the way back to
// qtile, so the search field is not a nicety here — it is the feature
// being ported, and the panel is built around it.
//
// ONE PANEL, ALL THREE SHEETS
// ---------------------------
// qtile had three chord keys and rofi had three separate invocations, each
// a fresh process that lost whatever you had typed. Here k/v/f pick the
// sheet the panel OPENS on, and Tab cycles between them once it is open,
// so comparing a vim binding against a WM binding no longer means leaving
// and re-entering the chord twice.
//
// The rows come from `cheatsheet.py --sheet-json`, which builds them from
// the same two functions that print the rofi sheet — the live compositor
// for the WM sheet, and the qtile popups' own CHEATSHEET dicts for vim and
// fish. There is no second copy of the content anywhere in this file.
//
Item {
    id: root

    property bool showCondition: false
    property string textFontFamily: ""
    property string heroFontFamily: ""
    property string iconFontFamily: ""

    // Which sheet is open. The chord sets it; Tab cycles it.
    property string sheet: "hypr"

    property string title: ""
    property string note: ""
    property var sections: []
    property string query: ""
    property bool loading: false

    signal closeRequested

    readonly property string ctl: Quickshell.env("HOME") + "/.config/hypr/scripts/cheatsheet.py"

    // "island" is last on purpose: the three before it are the sheets you
    // reach for while using something ELSE, and this one is about the shell
    // drawing the sheet. Adding it here is what puts it in the Tab cycle —
    // showCheatsheet("island") worked without it, but the sheet was then
    // reachable only by knowing its name, and invisible from the other three.
    // DOCS and TROUBLE are last on purpose. Tab cycles this list, and the
    // three key sheets are what you reach for mid-task; the reference
    // pair is what you reach for when something is already wrong, which
    // is a moment you are willing to press Tab twice more for.
    //
    // Both come from cheatsheet.py like every other sheet, so `$mod SHIFT
    // /` and `cheatsheet.py trouble` in a terminal cannot disagree — and
    // the terminal path still works on the day the shell is what broke,
    // which is exactly the day a troubleshooting sheet is wanted.
    readonly property var sheetOrder: ["hypr", "vim", "fish", "island", "docs", "trouble"]
    readonly property var sheetLabels: ({
        "hypr": "WM", "vim": "VIM", "fish": "FISH / KITTY", "island": "ISLAND",
        "docs": "DOCS", "trouble": "FIXING"
    })

    // ---- CARDS, LIKE QTILE'S OWN, NOT A FLAT SCROLLING LIST ----
    //
    // Reported directly against the first attempt at item 7 (which only
    // made the flat list's type bigger): "i want it as card fixed has all
    // the things inside and i can scroll updownn like the one of qtile but
    // as popup and also searchable". qtile's own cheatsheets
    // (popups/_cheatsheet_grid.py, read before touching this) are a
    // 3-column grid of one CARD per section, balanced by row count and
    // packed onto one tall page that scrolls — CheatsheetPopup.qml already
    // reproduces exactly that shape for `bar-mode=native`. This ports the
    // same card grid here, kept searchable (which qtile's own sheet is
    // not, and neither is CheatsheetPopup — the field is this file's own
    // addition, same as it always was).
    //
    // A section whose rows all fail the filter is DROPPED from its column
    // rather than left standing empty as a bare heading — same rule the
    // old flat model used, moved to the section level instead of the row
    // level.
    readonly property var visibleSections: {
        const needle = root.query.trim().toLowerCase();
        const out = [];
        for (const section of root.sections) {
            const rows = [];
            for (const row of (section.rows || [])) {
                if (needle === "" || Match.rank(row.combo, row.label, needle) > 0)
                    rows.push(row);
            }
            if (rows.length > 0)
                out.push({ title: section.title || "", rows: rows });
        }
        return out;
    }

    readonly property int matchCount: {
        let n = 0;
        for (const section of root.visibleSections)
            n += section.rows.length;
        return n;
    }

    // ---- THE COLUMN SPLIT, PORTED FROM CheatsheetPopup.qml VERBATIM ----
    //
    // Balances by HEIGHT (rows + 2 for the card's own heading and gap), not
    // by dealing sections round-robin — a round-robin puts a sheet's first
    // and third section side by side and leaves one column twice the
    // height of its neighbours. Same three columns qtile's own grid uses.
    readonly property int columnCount: 3
    readonly property var cardColumns: {
        const cols = [];
        const heights = [];
        for (let c = 0; c < root.columnCount; c++) {
            cols.push([]);
            heights.push(0);
        }
        for (const section of root.visibleSections) {
            let at = 0;
            for (let c = 1; c < root.columnCount; c++)
                if (heights[c] < heights[at])
                    at = c;
            cols[at].push(section);
            heights[at] += section.rows.length + 2;
        }
        return cols;
    }

    // ---- THE HEIGHT THIS SHEET WANTS ----
    //
    // Read by DynamicIslandWindow's `case "cheatsheet"`, which clamps it to
    // the screen — a sheet whose tallest COLUMN still overflows scrolls
    // rather than running the capsule off the bottom, same as
    // CheatsheetPopup's own Flickable. Computed from `sections` (the
    // unfiltered fetch), not `visibleSections`, so the panel does not
    // resize on every keystroke while the search field you are typing into
    // is what would walk up the screen.
    //
    // Distributes the UNFILTERED sections through the same balancer so the
    // estimate matches what will actually render once the query clears.
    readonly property int preferredHeight: {
        const heights = [0, 0, 0];
        for (const section of root.sections) {
            let at = 0;
            for (let c = 1; c < 3; c++)
                if (heights[c] < heights[at])
                    at = c;
            heights[at] += (section.rows || []).length * Metrics.px(20)
                + Metrics.px(34);
        }
        const tallest = Math.max(heights[0], heights[1], heights[2]);
        return Math.max(Metrics.px(200),
                        Math.round(Metrics.pad(12) * 2 + body.y + tallest));
    }

    // ---- FETCHING: A FRESH Process EVERY TIME, ON PURPOSE ----
    //
    // Same lesson as ModeKeysLayer.qml, and it cost enough there to be
    // worth obeying without re-learning it: a REUSED Process and its
    // StdioCollector hand back the PREVIOUS run's text, so switching sheets
    // with Tab would render vim's rows under the WM's title — one sheet
    // behind, correct on the first press and lying on every one after.
    // Toggling the Loader destroys the pair and builds a new one.
    function reload() {
        root.loading = true;
        fetchLoader.active = false;
        fetchLoader.active = true;
    }

    onSheetChanged: {
        root.sections = [];
        root.title = "";
        root.note = "";
        root.reload();
    }

    onShowConditionChanged: {
        if (showCondition) {
            searchInput.text = "";
            root.query = "";
            root.reload();
            focusTimer.restart();
        }
    }

    Loader {
        id: fetchLoader
        active: false

        sourceComponent: Component {
            Process {
                command: ["python3", root.ctl, "--sheet-json", root.sheet]
                running: true
                stdout: StdioCollector {
                    onStreamFinished: {
                        root.loading = false;
                        try {
                            const parsed = JSON.parse(text);
                            root.sections = parsed.sections || [];
                            root.title = parsed.title || "";
                            root.note = parsed.note || "";
                        } catch (error) {
                            // A sheet that cannot be read says so in the
                            // panel rather than opening blank — a blank
                            // cheatsheet is indistinguishable from a
                            // cheatsheet with nothing in it.
                            root.sections = [];
                            root.title = "COULD NOT READ SHEET";
                            root.note = "";
                        }
                    }
                }
            }
        }
    }

    Timer {
        id: focusTimer
        interval: 0
        repeat: false
        onTriggered: root.grabKeyboardFocus()
    }

    function grabKeyboardFocus() {
        root.forceActiveFocus();
        searchInput.forceActiveFocus();
    }

    function cycleSheet(step) {
        const order = root.sheetOrder;
        const at = order.indexOf(root.sheet);
        const next = (at < 0 ? 0 : (at + step + order.length) % order.length);
        if (order[next] !== root.sheet) {
            searchInput.text = "";
            root.query = "";
            root.sheet = order[next];
        }
    }

    // Scrolling is by the Flickable's own page metric rather than a fixed
    // pixel count, so it stays a page on any panel height.
    function scrollBy(pages) {
        const target = body.contentY + pages * body.height;
        const max = Math.max(0, body.contentHeight - body.height);
        body.contentY = Math.max(0, Math.min(max, target));
    }

    anchors.fill: parent
    focus: showCondition
    opacity: showCondition ? 1 : 0
    visible: opacity > 0.01

    // FORK: one choreography for every layer in the shell.
    // Was `root.showCondition ? 160 : 100` on Easing.InOutQuad — one of
    // eight hand-picked in-durations and six out-durations that agreed
    // with neither each other nor the 400 ms the shape takes. See
    // Motion.js, "CONTENT CHOREOGRAPHY", for the measurement.
    Behavior on opacity {
        SequentialAnimation {
            // The delay is what keeps the content from being painted
            // inside a capsule that is still the wrong size for it.
            PauseAnimation { duration: root.showCondition ? Motion.contentDelay() : 0 }
            NumberAnimation {
                duration: root.showCondition ? Motion.fadeInDuration() : Motion.fadeOutDuration()
                // Critically damped: opacity is clamped 0-1 and an
                // overshooting fade reads as a cut. Motion.js says why.
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Motion.fade()
            }
        }
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) {
            root.closeRequested();
            event.accepted = true;
        }
    }

    // PROMPT-NEXT.md item 7: "the documention and cheat ones are so small
    // and can not seen ... like the one in qtile". Measured, not assumed —
    // every font.pixelSize below was landing on Metrics.font()'s 9px FLOOR
    // regardless of the number passed in (the whole point of `font()`
    // flooring at 9 is that nothing in this shell goes below it, but with
    // SCALE at 0.7368 that meant every argument here under ~13 collapsed to
    // the same minimum). qtile's own reference popups render body text
    // around 15px unscaled — this file's `font.pixelSize` calls are
    // rescaled below to land in that same neighbourhood, and the geometry
    // (row heights, chip sizes, margins) grows with them so nothing clips.
    // `preferredHeight` above already carries the matching Metrics.px(30) /
    // Metrics.px(26) — see its own comment on why those two have to agree
    // with the delegate's row heights further down.
    Column {
        anchors.fill: parent
        anchors.topMargin: Metrics.pad(16)
        anchors.bottomMargin: Metrics.pad(16)
        anchors.leftMargin: Metrics.pad(22)
        anchors.rightMargin: Metrics.pad(22)
        spacing: Metrics.px(10)

        // ---- header: title, the three tabs, and the exit hint ----
        Item {
            width: parent.width
            height: Metrics.px(28)

            Text {
                id: sheetTitle
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: root.title
                color: IslandTheme.textPrimary
                font.family: root.heroFontFamily
                font.pixelSize: Metrics.font(20)
                font.weight: Font.DemiBold
                font.letterSpacing: 0.6
            }

            // The keyd note. It is the difference between a sheet that says
            // ALT and a keyboard that has no key labelled ALT, so it rides
            // next to the title rather than being dropped for space.
            Text {
                anchors.left: sheetTitle.right
                anchors.leftMargin: Metrics.pad(10)
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(0, tabRow.x - x - Metrics.pad(10))
                text: root.note
                color: IslandTheme.textMuted
                font.family: root.textFontFamily
                font.pixelSize: Metrics.font(14)
                font.italic: true
                elide: Text.ElideRight
            }

            Row {
                id: tabRow
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Metrics.pad(6)

                Repeater {
                    model: root.sheetOrder

                    Rectangle {
                        required property string modelData

                        readonly property bool active: modelData === root.sheet

                        width: tabLabel.implicitWidth + Metrics.pad(14)
                        height: Metrics.px(24)
                        radius: Metrics.px(5)
                        color: active ? IslandTheme.surfaceRaisedActive : IslandTheme.surfaceRaised

                        Behavior on color { ColorAnimation { duration: 120 } }

                        Text {
                            id: tabLabel
                            anchors.centerIn: parent
                            text: root.sheetLabels[parent.modelData] || parent.modelData
                            color: parent.active ? IslandTheme.textPrimary : IslandTheme.textSecondary
                            font.family: root.textFontFamily
                            font.pixelSize: Metrics.font(14)
                            font.weight: parent.active ? Font.DemiBold : Font.Normal
                            font.letterSpacing: 0.4
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (!parent.active) {
                                    searchInput.text = "";
                                    root.query = "";
                                    root.sheet = parent.modelData;
                                }
                                root.grabKeyboardFocus();
                            }
                        }
                    }
                }
            }
        }

        // ---- the search field: the feature being ported from rofi ----
        Rectangle {
            id: searchField
            width: parent.width
            height: Metrics.px(34)
            radius: Metrics.px(8)
            color: searchInput.activeFocus ? IslandTheme.inputFillFocused : IslandTheme.inputFill
            border.width: 1
            border.color: searchInput.activeFocus ? IslandTheme.inputBorderFocused : IslandTheme.inputBorder

            Behavior on color { ColorAnimation { duration: 140 } }
            Behavior on border.color { ColorAnimation { duration: 140 } }

            Text {
                id: searchIcon
                anchors.left: parent.left
                anchors.leftMargin: Metrics.pad(10)
                anchors.verticalCenter: parent.verticalCenter
                text: ""
                color: searchInput.activeFocus ? IslandTheme.textSecondary : IslandTheme.textMuted
                font.family: root.iconFontFamily
                font.pixelSize: Metrics.font(16)
            }

            TextInput {
                id: searchInput
                anchors.left: searchIcon.right
                anchors.leftMargin: Metrics.pad(9)
                anchors.right: countLabel.left
                anchors.rightMargin: Metrics.pad(9)
                anchors.verticalCenter: parent.verticalCenter
                color: IslandTheme.textPrimary
                selectionColor: IslandTheme.accent
                selectedTextColor: IslandTheme.accentInk
                font.family: root.textFontFamily
                font.pixelSize: Metrics.font(17)
                clip: true
                selectByMouse: true

                onTextChanged: {
                    if (root.query !== text) {
                        root.query = text;
                        // Any filter change makes the old scroll position
                        // meaningless — the row it was showing may not be
                        // in the grid any more.
                        body.contentY = 0;
                    }
                }

                // Tab is taken for switching sheets, which means it cannot
                // also be a focus-navigation key; there is nothing else
                // here to focus, so nothing is lost. Everything that is not
                // claimed below falls through to the field and types, which
                // is the behaviour the whole panel is built around.
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape) {
                        root.closeRequested();
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Tab) {
                        root.cycleSheet(1);
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Backtab) {
                        root.cycleSheet(-1);
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Down) {
                        root.scrollBy(0.25);
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Up) {
                        root.scrollBy(-0.25);
                        event.accepted = true;
                    } else if (event.key === Qt.Key_PageDown) {
                        root.scrollBy(1);
                        event.accepted = true;
                    } else if (event.key === Qt.Key_PageUp) {
                        root.scrollBy(-1);
                        event.accepted = true;
                    }
                }

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    visible: parent.text === ""
                    text: "type to filter — Tab switches sheet, Esc closes"
                    color: IslandTheme.textDisabled
                    font.family: root.textFontFamily
                    font.pixelSize: Metrics.font(17)
                }
            }

            Text {
                id: countLabel
                anchors.right: parent.right
                anchors.rightMargin: Metrics.pad(10)
                anchors.verticalCenter: parent.verticalCenter
                text: root.loading ? "…" : (root.matchCount + (root.query === "" ? "" : " match"))
                color: IslandTheme.textDisabled
                font.family: root.textFontFamily
                font.pixelSize: Metrics.font(13)
            }
        }

        // ---- the cards, in a scrolling 3-column grid ----
        //
        // Structurally identical to CheatsheetPopup.qml's own body — a
        // Flickable over a Row of Columns of card Rectangles — because that
        // is the shape "like the one of qtile" actually names. Kept as its
        // own copy rather than a shared component: the two read different
        // font/spacing scales (Metrics.js here, PopupMetrics there — see
        // Metrics.js's own header on why the two do not mix), and a
        // component parameterised over both would be one more layer to
        // read to see what either popup actually draws.
        Flickable {
            id: body
            width: parent.width
            height: parent.height - y
            clip: true
            contentWidth: width
            contentHeight: cardGrid.implicitHeight + Metrics.px(12)
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: IslandScrollBar { view: body }

            // A search that matches nothing has to say so. A blank grid
            // reads as a panel that failed to load.
            Text {
                anchors.centerIn: parent
                visible: !root.loading && root.matchCount === 0
                text: root.query === "" ? "nothing in this sheet" : "no key matches “" + root.query + "”"
                color: IslandTheme.textDisabled
                font.family: root.textFontFamily
                font.pixelSize: Metrics.font(17)
            }

            Row {
                id: cardGrid
                width: parent.width
                spacing: Metrics.px(10)

                Repeater {
                    model: root.cardColumns

                    delegate: Column {
                        required property var modelData
                        width: (cardGrid.width - Metrics.px(10) * (root.columnCount - 1))
                               / root.columnCount
                        spacing: Metrics.px(8)

                        Repeater {
                            model: parent.modelData

                            // ---- ONE CARD, ONE SECTION ----
                            delegate: Rectangle {
                                id: card
                                required property var modelData
                                width: parent.width
                                height: cardCol.implicitHeight + Metrics.px(12)
                                radius: Metrics.px(8)
                                color: IslandTheme.surfaceRaised

                                Column {
                                    id: cardCol
                                    x: Metrics.pad(9)
                                    y: Metrics.pad(6)
                                    width: parent.width - Metrics.pad(18)
                                    spacing: Metrics.px(2)

                                    Text {
                                        text: String(card.modelData.title || "")
                                        color: IslandTheme.info
                                        font.family: root.textFontFamily
                                        font.pixelSize: Metrics.font(18)
                                        font.weight: Font.DemiBold
                                        bottomPadding: Metrics.px(3)
                                    }

                                    Repeater {
                                        model: card.modelData.rows

                                        delegate: Item {
                                            required property var modelData
                                            width: cardCol.width
                                            height: rowComboChip.height

                                            // The combo first and
                                            // fixed-width, the label
                                            // filling what is left — the
                                            // eye scans one column of
                                            // keys, same as qtile's own
                                            // grid.
                                            Rectangle {
                                                id: rowComboChip
                                                width: Math.min(rowComboText.implicitWidth + Metrics.pad(8),
                                                                parent.width * 0.45)
                                                height: rowComboText.implicitHeight + Metrics.px(3)
                                                radius: Metrics.px(4)
                                                color: IslandTheme.surfaceRaisedHover
                                                Text {
                                                    id: rowComboText
                                                    anchors.centerIn: parent
                                                    width: parent.width - Metrics.pad(6)
                                                    elide: Text.ElideRight
                                                    text: String(modelData.combo || "")
                                                    color: IslandTheme.textPrimary
                                                    font.family: root.textFontFamily
                                                    font.pixelSize: Metrics.font(15)
                                                    font.weight: Font.Medium
                                                }
                                            }
                                            Text {
                                                anchors.left: rowComboChip.right
                                                anchors.leftMargin: Metrics.pad(6)
                                                anchors.right: parent.right
                                                anchors.verticalCenter: rowComboChip.verticalCenter
                                                elide: Text.ElideRight
                                                text: String(modelData.label || "")
                                                color: IslandTheme.textSecondary
                                                font.family: root.textFontFamily
                                                font.pixelSize: Metrics.font(15)
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
    }
}
