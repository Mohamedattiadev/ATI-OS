pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "../common/Metrics.js" as Metrics
// FORK: the shared motion system — one spring for geometry, one
// critically damped curve for opacity. See qml/common/Motion.js.
import "../common/Motion.js" as Motion

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

    readonly property var sheetOrder: ["hypr", "vim", "fish"]
    readonly property var sheetLabels: ({ "hypr": "WM", "vim": "VIM", "fish": "FISH / KITTY" })

    // ---- THE FLAT MODEL, AND WHY FILTERING DROPS HEADERS ----
    //
    // The list is one array of two kinds of entry — section headers and
    // key rows — rather than a ListView of ListViews, because a search has
    // to cut across sections and a nested view cannot shrink a section to
    // nothing.
    //
    // A section whose rows all fail the filter is REMOVED rather than left
    // standing empty. An empty header is a promise of content that is not
    // there, and with 8 sections in the WM sheet a search for one word
    // otherwise returns a screen of headings with three rows hidden among
    // them.
    readonly property var entries: {
        const needle = root.query.trim().toLowerCase();
        const out = [];

        for (const section of root.sections) {
            const rows = [];
            for (const row of (section.rows || [])) {
                if (needle === ""
                        || (row.label || "").toLowerCase().includes(needle)
                        || (row.combo || "").toLowerCase().includes(needle))
                    rows.push(row);
            }
            if (rows.length === 0)
                continue;
            out.push({ header: true, text: section.title || "" });
            for (const row of rows)
                out.push({ header: false, label: row.label || "", combo: row.combo || "" });
        }
        return out;
    }

    readonly property int matchCount: {
        let n = 0;
        for (const entry of root.entries)
            if (!entry.header)
                n += 1;
        return n;
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

    // Scrolling is by the list's own page metric rather than a fixed pixel
    // count, so it stays a page on any panel height.
    function scrollBy(pages) {
        const target = list.contentY + pages * list.height;
        const max = Math.max(0, list.contentHeight - list.height);
        list.contentY = Math.max(0, Math.min(max, target));
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

    Column {
        anchors.fill: parent
        anchors.topMargin: Metrics.pad(12)
        anchors.bottomMargin: Metrics.pad(12)
        anchors.leftMargin: Metrics.pad(18)
        anchors.rightMargin: Metrics.pad(18)
        spacing: Metrics.px(8)

        // ---- header: title, the three tabs, and the exit hint ----
        Item {
            width: parent.width
            height: Metrics.px(20)

            Text {
                id: sheetTitle
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: root.title
                color: "white"
                font.family: root.heroFontFamily
                font.pixelSize: Metrics.font(13)
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
                color: "#7c828c"
                font.family: root.textFontFamily
                font.pixelSize: Metrics.font(10)
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
                        height: Metrics.px(17)
                        radius: Metrics.px(5)
                        color: active ? "#3a3f48" : "#212429"

                        Behavior on color { ColorAnimation { duration: 120 } }

                        Text {
                            id: tabLabel
                            anchors.centerIn: parent
                            text: root.sheetLabels[parent.modelData] || parent.modelData
                            color: parent.active ? "#ffffff" : "#8a8f98"
                            font.family: root.textFontFamily
                            font.pixelSize: Metrics.font(9)
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
            height: Metrics.px(26)
            radius: Metrics.px(8)
            color: searchInput.activeFocus ? "#17181c" : "#111216"
            border.width: 1
            border.color: searchInput.activeFocus ? "#3d3f47" : "#292a30"

            Behavior on color { ColorAnimation { duration: 140 } }
            Behavior on border.color { ColorAnimation { duration: 140 } }

            Text {
                id: searchIcon
                anchors.left: parent.left
                anchors.leftMargin: Metrics.pad(10)
                anchors.verticalCenter: parent.verticalCenter
                text: ""
                color: searchInput.activeFocus ? "#d1d1d6" : "#8e8e93"
                font.family: root.iconFontFamily
                font.pixelSize: Metrics.font(11)
            }

            TextInput {
                id: searchInput
                anchors.left: searchIcon.right
                anchors.leftMargin: Metrics.pad(9)
                anchors.right: countLabel.left
                anchors.rightMargin: Metrics.pad(9)
                anchors.verticalCenter: parent.verticalCenter
                color: "#f5f5f7"
                selectionColor: "#0a84ff"
                selectedTextColor: "#ffffff"
                font.family: root.textFontFamily
                font.pixelSize: Metrics.font(11)
                clip: true
                selectByMouse: true

                onTextChanged: {
                    if (root.query !== text) {
                        root.query = text;
                        // Any filter change makes the old scroll position
                        // meaningless — the row it was showing may not be
                        // in the list any more.
                        list.contentY = 0;
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
                    color: "#6b7079"
                    font.family: root.textFontFamily
                    font.pixelSize: Metrics.font(11)
                }
            }

            Text {
                id: countLabel
                anchors.right: parent.right
                anchors.rightMargin: Metrics.pad(10)
                anchors.verticalCenter: parent.verticalCenter
                text: root.loading ? "…" : (root.matchCount + (root.query === "" ? "" : " match"))
                color: "#6b7079"
                font.family: root.textFontFamily
                font.pixelSize: Metrics.font(10)
            }
        }

        // ---- the rows ----
        ListView {
            id: list
            width: parent.width
            height: parent.height - y
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: root.entries
            cacheBuffer: Metrics.px(400)

            // A search that matches nothing has to say so. A blank list
            // reads as a panel that failed to load.
            Text {
                anchors.centerIn: parent
                visible: !root.loading && root.matchCount === 0
                text: root.query === "" ? "nothing in this sheet" : "no key matches “" + root.query + "”"
                color: "#6b7079"
                font.family: root.textFontFamily
                font.pixelSize: Metrics.font(11)
            }

            delegate: Item {
                id: entryItem
                required property var modelData

                width: list.width
                height: modelData.header ? Metrics.px(22) : Metrics.px(18)

                // Section header
                Text {
                    visible: entryItem.modelData.header
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: Metrics.px(3)
                    text: entryItem.modelData.header ? entryItem.modelData.text : ""
                    color: "#6f7681"
                    font.family: root.textFontFamily
                    font.pixelSize: Metrics.font(9)
                    font.weight: Font.DemiBold
                    font.letterSpacing: 0.8
                }

                // Key row. The combo is the thing being looked up, so it
                // gets the chip and the left edge — the eye scans one
                // column of keys, not a ragged right margin. This is the
                // opposite order from the printed sheet, where the label
                // leads because a printed line has no columns to scan.
                Item {
                    visible: !entryItem.modelData.header
                    anchors.fill: parent

                    Rectangle {
                        id: comboChip
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.max(Metrics.px(22), comboText.implicitWidth + Metrics.pad(10))
                        height: Metrics.px(14)
                        radius: Metrics.px(4)
                        color: "#26292f"
                        visible: comboText.text !== ""

                        Text {
                            id: comboText
                            anchors.centerIn: parent
                            text: entryItem.modelData.header ? "" : entryItem.modelData.combo
                            color: "#e8eaed"
                            font.family: root.textFontFamily
                            font.pixelSize: Metrics.font(9)
                            font.weight: Font.Medium
                        }
                    }

                    Text {
                        anchors.left: comboChip.visible ? comboChip.right : parent.left
                        anchors.leftMargin: comboChip.visible ? Metrics.pad(9) : 0
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: entryItem.modelData.header ? "" : entryItem.modelData.label
                        color: "#b9bec7"
                        font.family: root.textFontFamily
                        font.pixelSize: Metrics.font(10)
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }
}
