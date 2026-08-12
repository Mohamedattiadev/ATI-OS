pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

// FORK: the shared scale factor — see qml/common/Metrics.js.
import "../common/Metrics.js" as Metrics
// FORK: the shared motion system — one spring for geometry, one
// critically damped curve for opacity. See qml/common/Motion.js.
import "../common/Motion.js" as Motion

//
// FORK — new file. The GENERIC LIST PICKER.
//
// WHY THIS IS ONE PANEL AND NOT THREE
// -----------------------------------
// The rofi chord ($mod P, hypr/submaps.conf) reached about twenty scripts.
// Most of them are the same program written twenty times: build a list,
// pipe it to rofi, read one line back, act on it. Three of those — close a
// window, kill a process, go to a workspace — are already ports waiting to
// happen, and porting them as three QML files would mean three copies of
// "list with a search field and a details column", which this shell has
// enough of already (settings, theme picker, cheatsheet).
//
// So the panel knows nothing about windows, processes or workspaces. It
// knows about `--list` and `--run`. Everything specific lives in
// hypr/scripts/island-picker.py and a fourth menu costs a function there
// and a bind, not a file here.
//
// THE PANEL NEVER SEES A COMMAND, AND THAT IS DELIBERATE
// -----------------------------------------------------
// island-picker.py's docstring makes the same point from its side: an item
// is {id, label, detail} and the id goes back to the script, which decides
// what it means. A panel that executed strings handed to it by a script
// would execute whatever anything could write into that script's stdout.
// This is why there is no `exec` property on an item and no code path here
// that builds a command out of model data.
//
// WHERE THE SHAPE COMES FROM
// --------------------------
// SettingsLayer.qml, almost line for line: list on the left, details on
// the right, a footer hint, j/k that wrap, q/Esc to close. The one addition
// is the search field, taken from ApplicationLauncherLayer.qml — and it is
// the reason the key handling below is more complicated than settings',
// because a panel you can type into cannot spend `j` and `k` on movement
// unconditionally. See "THE j/k PROBLEM".
//
FocusScope {
    id: root

    signal closeRequested

    property bool showCondition: false
    property string textFontFamily: ""
    property string heroFontFamily: ""
    property string iconFontFamily: ""

    // Which menu island-picker.py should build: windows | processes |
    // workspaces. Set by DynamicIslandWindow BEFORE the state flips, so the
    // Loader's first fetch is already for the right menu (same ordering
    // showCheatsheet uses for `cheatsheetWhich`).
    property string menu: "windows"

    readonly property string ctl: Quickshell.env("HOME") + "/.config/hypr/scripts/island-picker.py"

    // Straight from --list. [{ id, label, detail }, ...]
    property var items: []
    property string title: ""
    property bool loading: false
    property string query: ""
    property int selectedIndex: 0
    property string statusText: ""
    property bool statusIsError: false

    // ---- THE FILTER ----
    //
    // "Fuzzy-ish", and the -ish is the whole of it: this is a SUBSEQUENCE
    // match over the label and the detail joined, not a scored fuzzy match
    // like fzf's. Two reasons it stops there.
    //
    //   1. The lists are small. `windows` is ten rows on this session,
    //      `workspaces` is three, `processes` is capped at 40 by the script.
    //      Ranking exists to make a thousand candidates usable; over ten
    //      rows it only means the row you were looking at moves while you
    //      type, which is worse than no ranking at all.
    //   2. A subsequence match over label+detail already gets the query
    //      that matters. "brw5" finds the Brave window on workspace 5
    //      because the workspace number is in the DETAIL — the search
    //      crosses both fields, which a label-only match would not.
    //
    // Order is preserved from the script (windows alphabetical, workspaces
    // numeric, processes by RSS), so the list never reshuffles under the
    // cursor — it only gets shorter.
    // 2 = the query is a literal substring, 1 = subsequence only, 0 = no
    // match. Not a score: three buckets, and the order inside a bucket is
    // whatever the script sent.
    function matchRank(item, needle) {
        if (needle === "")
            return 2;
        const hay = ((item.label || "") + " " + (item.detail || "")).toLowerCase();
        if (hay.includes(needle))
            return 2;
        // Otherwise: every character of the needle, in order, somewhere in
        // the haystack. Spaces are skipped so "qute 2" and "qute2" are the
        // same query — a space in a query is a word separator to a person,
        // never a character to be found.
        let at = 0;
        for (const ch of needle) {
            if (ch === " ")
                continue;
            at = hay.indexOf(ch, at);
            if (at < 0)
                return 0;
            at += 1;
        }
        return 1;
    }

    // ---- WHY THERE ARE TWO PASSES AND NOT ONE ----
    //
    // The first version was one pass and a boolean `matches()`, which kept
    // the script's order for everything that matched. Since the cursor
    // resets to 0 on every keystroke (see onFilteredChanged), whatever is
    // first is what Enter runs, and "first" was "alphabetically first among
    // everything that matched at all".
    //
    // THE MEASUREMENT THAT PROMPTED THIS WAS MISREAD, and the misreading is
    // worth keeping because the conclusion survived it and the reasoning did
    // not. Against the real `windows` list on this session:
    //
    //     "brave" -> ChatGPT | Reacher (2022) … - Brave | web.whatsapp.com
    //
    // which was read as "two coincidental subsequence hits outranking the
    // literal one". It is not: all three rows literally contain "brave",
    // because the search covers the DETAIL and the detail carries the window
    // class — ChatGPT's is "brave-chat.openai.com__-Chatgpt" and WhatsApp's
    // is "brave-web.whatsapp.com__-Whatsapp". Every browser-wrapped webapp
    // on this system shares that prefix, so "brave" is a genuinely ambiguous
    // query and no ranking rescues it. Two passes changes that line NOT AT
    // ALL.
    //
    // What it does change, measured on the same list:
    //
    //     "ank"  one pass -> ChatGPT | Reacher … | Qtile … | User 1 - Anki
    //            two pass -> User 1 - Anki | ChatGPT | Reacher … | Qtile …
    //
    // "Anki" is the only literal hit and it was LAST of four, so Enter after
    // typing the exactly right query closed ChatGPT.
    //
    // Two passes, substring bucket first, fixes that without introducing a
    // score: rows still cannot overtake each other WITHIN a bucket, so the
    // list still does not reshuffle under the cursor as you type. That was
    // the reason for not ranking in the first place, and it survives.
    readonly property var filtered: {
        const needle = root.query.trim().toLowerCase();
        const strong = [];
        const weak = [];
        for (const item of root.items) {
            const rank = root.matchRank(item, needle);
            if (rank === 2)
                strong.push(item);
            else if (rank === 1)
                weak.push(item);
        }
        return strong.concat(weak);
    }

    readonly property var selected:
        (root.selectedIndex >= 0 && root.selectedIndex < root.filtered.length)
            ? root.filtered[root.selectedIndex] : null

    // Any change to the filter invalidates the cursor: the row it was on may
    // not be in the list any more, and leaving the index where it was means
    // Enter runs whatever slid into that position. Back to the top, which is
    // also where the best match is when you have just typed one.
    onFilteredChanged: {
        if (root.selectedIndex > root.filtered.length - 1)
            root.selectedIndex = 0;
    }

    readonly property real horizontalPadding: Metrics.pad(18)
    readonly property real headerHeight: Metrics.pad(34)
    readonly property real searchHeight: Metrics.px(26)
    readonly property real rowHeight: Metrics.px(30)
    readonly property real footerHeight: Metrics.px(22)

    // ---- WHY THE HEIGHT IS COMPUTED FROM `items` AND NOT `filtered` ----
    //
    // Sizing to the FILTERED count is the obvious thing and it is wrong for
    // exactly the reason CheatsheetLayer went to a fixed frame: the panel
    // would change height on every keystroke, so the search field — the one
    // element that must stay under your eyes while you type — would walk up
    // and down the screen as the list narrowed.
    //
    // Sizing to the unfiltered count instead keeps the frame still for the
    // whole of one open, and it is still content-sized between menus:
    // `workspaces` (3 rows) does not get the height `processes` (40) needs.
    //
    // The 11-row cap is the other half. 40 process rows at 30 px is 1200 px
    // of panel on a 768 px screen; the window clamps that to
    // screen.height - 60 anyway, but doing it here means the LIST is what
    // scrolls rather than the panel being silently truncated by the clamp
    // with its own footer off the bottom of the screen.
    readonly property int maxVisibleRows: 11
    readonly property int visibleRows: Math.max(1, Math.min(root.maxVisibleRows, root.items.length))
    readonly property real preferredHeight:
        root.headerHeight + root.searchHeight + Metrics.pad(8)
        + root.visibleRows * root.rowHeight
        + root.footerHeight + Metrics.pad(16)

    readonly property real listWidth: Math.round(root.width * 0.54)

    focus: showCondition
    activeFocusOnTab: true
    anchors.fill: parent
    opacity: showCondition ? 1 : 0
    visible: opacity > 0.01

    // FORK: one choreography for every layer in the shell. See Motion.js.
    Behavior on opacity {
        SequentialAnimation {
            // The delay is what keeps the content from being painted inside
            // a capsule that is still the wrong size for it.
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

    // ---- FETCHING: A FRESH Process EVERY TIME ----
    //
    // The trap written up at length in ModeKeysLayer.qml and obeyed again in
    // CheatsheetLayer and SettingsLayer: a REUSED Quickshell Process with a
    // StdioCollector hands back the PREVIOUS run's text on the second and
    // later runs. It would be worse here than anywhere else it has bitten,
    // because this panel's rows are VOLATILE — a stale `windows` list is a
    // list of window addresses that may no longer exist, and Enter on one of
    // those closes nothing while looking like it closed something. A stale
    // `processes` list is worse still: pids are reused.
    //
    // Toggling the Loader off and on is what destroys the old pair. The
    // `active = false` is not redundant with the assignment that follows —
    // a Loader that is already active does not rebuild for a source that has
    // not changed, which would quietly reinstate the reuse this avoids.
    function refresh() {
        root.loading = true;
        root.items = [];
        listLoader.active = false;
        listLoader.active = true;
    }

    // ---- WHY THE OPEN IS IN A FUNCTION AND CALLED FROM TWO PLACES ----
    //
    // The obvious single hook is onShowConditionChanged, and on its own it
    // is WRONG on the open that matters most — the first one. PanelLoader
    // mounts this item only once `live` is already true, and `showCondition`
    // is BOUND to that same boolean, so at construction the property is
    // already 1 and the change handler never fires. The panel would come up
    // with an empty list and no keyboard focus, and the only way to make it
    // fetch would be to close and reopen it inside PanelLoader's fade-out
    // hold window — i.e. it would look like it worked intermittently.
    //
    // So: Component.onCompleted covers the mount, onShowConditionChanged
    // covers a reopen that catches the item still alive on the hold timer
    // (see PanelLoader.qml — the item outlives its own dismissal by
    // fadeOutDuration + 40 ms so its out-fade can actually run).
    function openReset() {
        root.statusText = "";
        root.statusIsError = false;
        root.query = "";
        searchInput.text = "";
        root.selectedIndex = 0;
        root.refresh();
        root.grabKeyboardFocus();
    }

    Component.onCompleted: {
        if (root.showCondition)
            root.openReset();
    }

    onShowConditionChanged: {
        if (showCondition)
            root.openReset();
    }

    // Changing menus while the panel is open (there is no key for it today,
    // but the IPC can) re-fetches rather than filtering the old rows.
    onMenuChanged: {
        if (root.showCondition)
            root.refresh();
    }

    Loader {
        id: listLoader
        active: false

        sourceComponent: Component {
            Process {
                command: ["python3", root.ctl, "--list", root.menu]
                running: true
                stdout: StdioCollector {
                    onStreamFinished: {
                        root.loading = false;
                        try {
                            const parsed = JSON.parse(text);
                            root.items = parsed.items || [];
                            root.title = String(parsed.title || root.menu);
                            if (parsed.error !== undefined) {
                                root.statusText = String(parsed.error);
                                root.statusIsError = true;
                            }
                        } catch (error) {
                            // A menu that cannot be read says so rather than
                            // opening blank. A blank picker is
                            // indistinguishable from a picker with nothing
                            // in it, and "no windows open" and "the script
                            // is broken" want different reactions.
                            root.items = [];
                            root.title = root.menu;
                            root.statusText = "island-picker.py --list " + root.menu
                                + " produced no readable output";
                            root.statusIsError = true;
                        }
                        if (root.selectedIndex > root.filtered.length - 1)
                            root.selectedIndex = 0;
                    }
                }
            }
        }
    }

    // ---- RUNNING ----
    //
    // A second fresh-per-invocation pair, for the same reason and one more:
    // this one reads the RESULT. On a reused Process the second run of the
    // session would report the first run's {"ok":true} — so a failed kill
    // would print "done" — which is the same failure mode SettingsLayer
    // calls the worst available one for a panel that writes.
    //
    // `pendingId` also serves as the in-flight guard: Enter twice on the
    // same row must not fire twice. For `workspaces` that would be harmless
    // and for `processes` it means two SIGTERMs, the second one landing on
    // whatever inherited the pid.
    property string pendingId: ""

    function runSelected() {
        const item = root.selected;
        if (!item || root.pendingId !== "")
            return;
        root.pendingId = String(item.id);
        root.statusText = "";
        root.statusIsError = false;
        runLoader.active = false;
        runLoader.active = true;
    }

    Loader {
        id: runLoader
        active: false

        sourceComponent: Component {
            Process {
                command: ["python3", root.ctl, "--run", root.menu, root.pendingId]
                running: true
                stdout: StdioCollector {
                    onStreamFinished: {
                        let ok = false;
                        let message = "";
                        try {
                            const parsed = JSON.parse(text);
                            ok = parsed.ok === true;
                            message = String(parsed.error || "");
                        } catch (error) {
                            message = "island-picker.py produced no readable output";
                        }
                        root.pendingId = "";

                        if (!ok) {
                            root.statusText = message !== "" ? message : "failed";
                            root.statusIsError = true;
                            // Stay open on failure, and re-read. The list is
                            // the evidence: if the window was already gone,
                            // the refreshed list is the proof, and closing
                            // the panel would take that away at the moment
                            // it was needed.
                            root.refresh();
                            return;
                        }

                        // Closing on success is the rofi behaviour these
                        // menus are ported from, and it is right for all
                        // three: every one of them is a one-shot verb. A
                        // picker that stayed open after `workspace 5` would
                        // be a panel sitting on top of the workspace you
                        // just asked to look at.
                        root.closeRequested();
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

    // Two-step, like CheatsheetLayer: the FocusScope has to own the focus
    // before the field inside it can, or the field gets active focus in a
    // scope that does not have it and no keystrokes arrive.
    function grabKeyboardFocus() {
        root.forceActiveFocus();
        searchInput.forceActiveFocus();
    }

    function move(delta) {
        if (root.filtered.length === 0)
            return;
        let next = root.selectedIndex + delta;
        // Wraps, like every other list in this shell. See FORK-NOTES.md,
        // "the cursors wrap".
        if (next < 0) next = root.filtered.length - 1;
        if (next > root.filtered.length - 1) next = 0;
        root.selectedIndex = next;
        list.positionViewAtIndex(next, ListView.Contain);
    }

    Text {
        id: header
        x: root.horizontalPadding
        y: Metrics.pad(10)
        // The script owns the title ("Close window", "Kill process"), not
        // this file. The title is the sentence the Enter key completes, so
        // it belongs beside the code that decides what Enter does.
        text: root.title !== "" ? root.title : root.menu
        color: "white"
        font.pixelSize: Metrics.font(15)
        font.family: root.heroFontFamily
        font.weight: Font.DemiBold
        font.letterSpacing: -0.2
    }

    Text {
        id: statusLabel
        anchors.right: parent.right
        anchors.rightMargin: root.horizontalPadding
        y: Metrics.pad(13)
        width: Math.min(implicitWidth, root.width * 0.5)
        horizontalAlignment: Text.AlignRight
        elide: Text.ElideRight
        text: root.statusText !== "" ? root.statusText
            : (root.loading ? "reading…"
                            : root.filtered.length + " of " + root.items.length)
        color: root.statusIsError ? "#ff6b6b" : "#6a6f78"
        font.pixelSize: Metrics.font(11)
        font.family: root.textFontFamily
    }

    // ---- THE SEARCH FIELD ----
    //
    // Taken from ApplicationLauncherLayer's, at the cheatsheet's size: this
    // panel's field sits above a list rather than being the whole of the
    // surface, so the launcher's 46 px pill would be the loudest thing on a
    // panel whose subject is the list.
    Rectangle {
        id: searchField
        x: root.horizontalPadding
        y: root.headerHeight
        width: root.width - 2 * root.horizontalPadding
        height: root.searchHeight
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
            anchors.right: parent.right
            anchors.rightMargin: Metrics.pad(10)
            anchors.verticalCenter: parent.verticalCenter
            color: "#f5f5f7"
            selectionColor: "#0a84ff"
            selectedTextColor: "#ffffff"
            font.family: root.textFontFamily
            font.pixelSize: Metrics.font(11)
            clip: true
            selectByMouse: true

            onTextChanged: {
                if (root.query !== text)
                    root.query = text;
            }

            // ---- THE j/k PROBLEM ----
            //
            // The brief for this panel asks for j/k movement AND for typing
            // to filter, and those two are in direct conflict: `j` is a
            // letter. SettingsLayer can spend j/k on movement because it has
            // no field; the application launcher can spend Left/Right on it
            // because its own field takes the letters.
            //
            // The rule here, which is the launcher's rule generalised:
            //
            //   * with the query EMPTY, j/k move. The panel opens empty, so
            //     the muscle memory from every other list in this shell
            //     works on the state you are in when you open it.
            //   * once you have typed anything, j and k are letters again —
            //     they have to be, or "jack" is untypeable — and movement is
            //     Up/Down, which never stops working.
            //
            // Ctrl+n / Ctrl+p are the third way in, always available, for
            // the hand that is already in readline. They are cheap and they
            // are the only movement keys that work identically in both
            // states, which is why they are also in the footer hint when the
            // query is non-empty.
            //
            // `q` gets the same treatment as j/k and for the same reason:
            // with an empty query it closes (SettingsLayer's contract), with
            // a query it types. Escape always closes, which is the promise
            // every submap and panel in this session already makes.
            Keys.onPressed: function (event) {
                const empty = searchInput.text === "";
                const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;

                if (event.key === Qt.Key_Escape) {
                    root.closeRequested();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    root.runSelected();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Down
                        || (ctrl && event.key === Qt.Key_N)
                        || (empty && event.key === Qt.Key_J)) {
                    root.move(1);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Up
                        || (ctrl && event.key === Qt.Key_P)
                        || (empty && event.key === Qt.Key_K)) {
                    root.move(-1);
                    event.accepted = true;
                } else if (empty && event.key === Qt.Key_Q) {
                    root.closeRequested();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
                    // Swallowed rather than left to Qt's focus navigation.
                    // There is exactly one focusable item on this panel, so
                    // Tab's only possible effect is to take the focus OFF
                    // the field and leave the keyboard grab pointing at
                    // nothing — a panel that has stopped responding with no
                    // visible reason why.
                    event.accepted = true;
                } else if (ctrl && event.key === Qt.Key_R) {
                    // Re-read. The lists are volatile — windows close,
                    // processes exit — and a picker that has been open for a
                    // minute is showing history.
                    root.refresh();
                    event.accepted = true;
                }
            }

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                visible: parent.text === ""
                text: "type to filter — j/k move, Enter runs, Esc closes"
                color: "#6b7079"
                font.family: root.textFontFamily
                font.pixelSize: Metrics.font(11)
            }
        }
    }

    ListView {
        id: list
        x: root.horizontalPadding
        y: root.headerHeight + root.searchHeight + Metrics.pad(8)
        width: root.listWidth
        height: parent.height - y - root.footerHeight - Metrics.pad(8)
        clip: true
        model: root.filtered
        currentIndex: root.selectedIndex
        boundsBehavior: Flickable.StopAtBounds

        // A search that matches nothing has to say so; a blank list reads as
        // a panel that failed to load. The empty-list case is a different
        // sentence, because "no windows" is a fact about the session and
        // "no match" is a fact about what you typed.
        Text {
            anchors.centerIn: parent
            visible: !root.loading && root.filtered.length === 0
            text: root.items.length === 0
                ? "nothing to pick"
                : "no match for “" + root.query + "”"
            color: "#6b7079"
            font.family: root.textFontFamily
            font.pixelSize: Metrics.font(11)
        }

        delegate: Item {
            id: rowItem
            required property int index
            required property var modelData

            readonly property bool isSelected: rowItem.index === root.selectedIndex

            width: list.width
            height: root.rowHeight

            Rectangle {
                anchors.fill: parent
                anchors.topMargin: Metrics.px(2)
                anchors.bottomMargin: Metrics.px(2)
                radius: Metrics.px(7)
                color: rowItem.isSelected ? "#2c3038" : "transparent"

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: Metrics.pad(10)
                    anchors.right: parent.right
                    anchors.rightMargin: Metrics.pad(10)
                    anchors.verticalCenter: parent.verticalCenter
                    // Elided, not wrapped. A window title can be a whole
                    // sentence ("Reacher (2022) — Watch on Cineby - Brave")
                    // and a row that grew to fit one would break the fixed
                    // row height every height calculation on this panel
                    // depends on. The full string is in the details column,
                    // which has room and wraps.
                    elide: Text.ElideRight
                    text: rowItem.modelData.label
                    color: "#f2f4f7"
                    font.pixelSize: Metrics.font(12)
                    font.family: root.textFontFamily
                    font.weight: rowItem.isSelected ? Font.DemiBold : Font.Normal
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: root.selectedIndex = rowItem.index
                    onClicked: {
                        root.selectedIndex = rowItem.index;
                        root.runSelected();
                    }
                }
            }
        }
    }

    // ---- DETAILS ----
    //
    // The same list-plus-details shape SettingsLayer uses, and here it earns
    // its width for a different reason: the label alone is ambiguous in two
    // of the three menus. Six terminals all read "~"; the detail is
    // "scratch-term1 · workspace special:term1" and that is the entire
    // difference between closing the right window and the wrong one. The
    // full label is repeated at the top unelided for the same reason.
    Column {
        id: details
        anchors.left: parent.left
        anchors.leftMargin: root.horizontalPadding + root.listWidth + Metrics.pad(16)
        anchors.right: parent.right
        anchors.rightMargin: root.horizontalPadding
        y: list.y + Metrics.px(2)
        spacing: Metrics.px(6)

        Text {
            width: details.width
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
            text: root.selected ? String(root.selected.label || "") : ""
            color: "white"
            font.pixelSize: Metrics.font(13)
            font.family: root.heroFontFamily
            font.weight: Font.DemiBold
        }

        Text {
            width: details.width
            wrapMode: Text.WordWrap
            maximumLineCount: 4
            elide: Text.ElideRight
            text: root.selected ? String(root.selected.detail || "") : ""
            color: "#a8aeb8"
            font.pixelSize: Metrics.font(11)
            font.family: root.textFontFamily
            lineHeight: 1.25
        }

        // The id, dimmed. It is the thing that actually crosses back to the
        // script — a window address, a pid, a workspace number — and on the
        // `processes` menu it is the number you would need if you decided
        // this wants a real `kill -9` instead. SettingsLayer shows the
        // config key here for the same reason.
        Text {
            text: root.selected ? String(root.selected.id || "") : ""
            color: "#5a5f68"
            font.pixelSize: Metrics.font(10)
            font.family: root.textFontFamily
        }
    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Metrics.pad(8)
        // The hint CHANGES with the query, because the keys change with it —
        // see THE j/k PROBLEM above. A static "j/k move" would be a lie the
        // moment you typed a character, and a hint that lies is worse than
        // no hint: it is the reason you conclude the panel is broken.
        text: root.query === ""
            ? "j/k move  ·  Enter run  ·  type to filter  ·  q close"
            : "↑/↓ or Ctrl+n/p move  ·  Enter run  ·  Esc close"
        color: "#6a6a6a"
        font.pixelSize: Metrics.font(10)
        font.family: root.textFontFamily
    }
}
