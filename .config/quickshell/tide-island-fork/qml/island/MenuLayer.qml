pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

import "../common"
import "../common/Metrics.js" as Metrics
import "../common/Motion.js" as Motion

//
// FORK — new file. A real island panel for the command tree ati-menu
// (Super+Shift+/) already renders, for bar-mode=island specifically.
//
// WHY THIS EXISTS, VERBATIM
// -------------------------
// Asked for directly, after a smaller approximation (ati-menu's own
// window, given a grow-in animation and moved near the top) was tried and
// rejected: "roll back it to the middle and do design one form scratch
// for the island... one like the real popups of island". So this is not
// ati-menu repositioned — it is a genuinely separate implementation that
// morphs out of the capsule the same way every other panel in this file
// does (PanelChrome + the islandState machine), reading the SAME
// ati-menu.json data ati-menu itself reads, independently.
//
// WHAT IS DELIBERATELY NOT PORTED, AND WHY THAT IS A SCOPE LINE AND NOT
// AN OVERSIGHT
// -----------------------------------------------------------------------
// Menu.qml/MenuModel.js (vendored Omarchy, see NOTICE.md) is a mature,
// tuned engine: weighted fuzzy search across the whole tree, batched
// guard evaluation (one `bash -lc` per reload rather than one per row —
// MenuModel.js's own header says this was measured at "over a second"
// unbatched), a provider mechanism for the Apps/Fonts sections. Rebuilding
// all of that for a second, independent Quickshell package under real
// time pressure would mean shipping it unverified. So this panel does the
// smaller, honest thing instead:
//
//   * Search is plain substring on label+id, not the weighted scorer —
//     same limitation this session's own CheatsheetPopup search has, and
//     for the same reason: correct as far as it goes, not ranked.
//   * "when"/"disabled" guards are NOT evaluated — every row always shows,
//     enabled. `install.docker` still offers to install Docker even if it
//     already is. Wrong in the same DIRECTION as showing nothing, not a
//     crash or a broken action — just imprecise, and said so here rather
//     than silently.
//   * The `apps`/`fonts` PROVIDER entries are excluded from the tree
//     entirely (filtered by `provider !== undefined`), not rendered as
//     broken rows. Apps (DesktopEntries) and live font enumeration both
//     need machinery this panel does not have today.
//
// Everything else — the ~80 static, action-bearing entries under Style/
// System/Setup/Docs/Install/Remove/Update/Trigger/Learn — works: browse,
// search, drill down, run.
//
// ============================================================
//  TODO, EXPLICITLY TRACKED — not done, not forgotten
// ============================================================
// Reported directly: "make all of options opens as island popup thing".
// This panel is real (morphs from the capsule, real chrome) — but almost
// every LEAF ACTION it runs still shells out to a script that pops rofi
// or ati-menu's own separate window instead of a genuine island panel:
// ati-docs (About/Keybindings/Cheatsheets/Documentation/Espanso/System
// info/Maintenance — one script, six menu entries), ati-default-app,
// ati-webapp-remove, ati-keybindings, ati-emoji-insert, ati-theme-toggle,
// ui-scale-toggle, ati-dns-set, ati-reminder, ati-transcode, dm-confedit,
// ati-satty, ati-copyq-rofi (clipboard). These were made bar-mode-aware
// this session (route to rofi under island instead of always popping
// ati-menu's window — see ati-rofi-common.sh's `use_ati_menu_select()`),
// which is a REAL improvement (the wrong-window confusion these caused is
// gone) but is NOT the end state asked for — rofi is still not an island
// panel. Turning each of those into a real PanelChrome-based island panel
// (the way THIS file replaced ati-menu's own window) is a genuinely large
// job — a dozen-plus separate features, not one — and was explicitly
// deferred rather than rushed. Pick one at a time, starting with whichever
// gets used most; ati-docs's `pick()` (six menu entries through one
// function) is probably the highest-leverage first target.
FocusScope {
    id: root

    property string textFontFamily: ""
    property string heroFontFamily: ""
    property string iconFontFamily: ""
    property bool showCondition: false
    signal closeRequested()

    readonly property real preferredHeight: Math.min(
        Metrics.px(420),
        chrome.chromeHeight + Metrics.px(60) + Math.min(root.visibleRows.length, 8) * root.rowHeight)

    readonly property int rowHeight: Metrics.px(30)

    // ---- DATA: THE SAME FILE ati-menu.json IS ----
    property var entries: ({})   // id -> {id, icon, label, action, aliases, disabled, when, provider}
    property var order: []       // ids, in file order — search results keep this as a stable tiebreak

    function parseTree(json) {
        const out = {};
        const ord = [];
        try {
            const parsed = JSON.parse(json);
            for (const id in parsed) {
                const raw = parsed[id] || {};
                if (raw.provider !== undefined)
                    continue;   // apps / fonts — see file header
                out[id] = {
                    id: id,
                    icon: String(raw.icon || ""),
                    label: String(raw.label || id),
                    action: raw.action !== undefined ? String(raw.action) : "",
                    aliases: raw.aliases || []
                };
                ord.push(id);
            }
        } catch (e) {
            // A half-written ati-menu.json must not crash the island —
            // same defensiveness IslandTheme.applyJson uses for the same
            // reason (theme-apply writes in place, not atomically).
        }
        root.entries = out;
        root.order = ord;
    }

    FileView {
        id: menuFile
        path: Quickshell.env("HOME") + "/.config/AtiScriptsV1/ati-menu.json"
        watchChanges: true
        printErrors: false
        onLoaded: root.parseTree(text())
        onFileChanged: reload()
    }

    // ---- NAVIGATION ----
    property string currentPath: ""   // "" = root
    property int selectedIndex: 0

    function childrenOf(path) {
        const out = [];
        for (let i = 0; i < root.order.length; i++) {
            const id = root.order[i];
            const dot = id.lastIndexOf(".");
            const parent = dot < 0 ? "" : id.substring(0, dot);
            if (parent === path)
                out.push(root.entries[id]);
        }
        return out;
    }

    function hasChildren(id) {
        return root.childrenOf(id).length > 0;
    }

    readonly property var visibleRows: {
        const query = search.query.trim().toLowerCase();
        if (query === "") {
            return root.childrenOf(root.currentPath);
        }
        const out = [];
        for (let i = 0; i < root.order.length; i++) {
            const e = root.entries[root.order[i]];
            const hay = e.label.toLowerCase() + " " + e.id.toLowerCase() + " "
                + (e.aliases || []).join(" ").toLowerCase();
            if (hay.indexOf(query) !== -1)
                out.push(e);
        }
        return out;
    }

    onVisibleRowsChanged: root.selectedIndex = Math.max(0,
        Math.min(root.selectedIndex, root.visibleRows.length - 1));

    readonly property string breadcrumb: {
        if (root.currentPath === "")
            return "Menu";
        const parts = root.currentPath.split(".");
        const labels = [];
        let path = "";
        for (const part of parts) {
            path = path === "" ? part : path + "." + part;
            const e = root.entries[path];
            labels.push(e ? e.label : part);
        }
        return labels.join(" › ");
    }

    function enter() {
        const row = root.visibleRows[root.selectedIndex];
        if (!row)
            return;
        if (root.hasChildren(row.id)) {
            root.currentPath = row.id;
            root.selectedIndex = 0;
            search.clear();
        } else if (row.action !== "") {
            Quickshell.execDetached(["bash", "-lc", row.action]);
            root.closeRequested();
        }
    }

    function back() {
        if (search.query !== "") {
            search.clear();
            return;
        }
        if (root.currentPath === "") {
            root.closeRequested();
            return;
        }
        const dot = root.currentPath.lastIndexOf(".");
        root.currentPath = dot < 0 ? "" : root.currentPath.substring(0, dot);
        root.selectedIndex = 0;
    }

    // ---- NAVIGATION MODE VS SEARCH MODE ----
    //
    // Reported directly: bare hjkl should move/back/open, not Ctrl+hjkl,
    // and `/` is what starts a search — the vim-gated pattern
    // ThemePickerLayer.qml/CheatsheetPopup.qml already use, not the
    // always-focused rofi-style field PanelSearchField defaults to (which
    // is what this had before: every letter went into the query, so hjkl
    // could only ever move by way of the Ctrl+ variant PanelSearchField
    // itself reserves for navigation while a field owns the keys).
    //
    // The mechanism is CalculatorLayer's own normal/insert toggle, not a
    // new one: `readOnly` keeps the field showing but stops it from
    // claiming keystrokes, and activeFocus moves explicitly between the
    // FocusScope and the field with each transition — see that file's
    // enterNormal()/enterInsert() for the same shape.
    property bool searching: false

    function enterSearch() {
        root.searching = true;
        search.readOnly = false;
        search.focusField();
    }

    function exitSearch() {
        root.searching = false;
        search.readOnly = true;
        search.clear();
        root.forceActiveFocus();
    }

    onShowConditionChanged: {
        if (root.showCondition) {
            root.currentPath = "";
            root.selectedIndex = 0;
            root.searching = false;
            search.readOnly = true;
            search.clear();
            root.forceActiveFocus();
        }
    }

    Keys.onPressed: (event) => {
        // The field owns keys while searching (readOnly is false, so its
        // own Keys.onPressed claims them first and this handler never
        // sees them) -- this branch only runs in navigation mode.
        switch (event.key) {
        case Qt.Key_Slash:
            root.enterSearch();
            break;
        case Qt.Key_J: case Qt.Key_Down:
            if (root.visibleRows.length > 0)
                root.selectedIndex = (root.selectedIndex + 1) % root.visibleRows.length;
            break;
        case Qt.Key_K: case Qt.Key_Up:
            if (root.visibleRows.length > 0)
                root.selectedIndex = (root.selectedIndex - 1 + root.visibleRows.length)
                    % root.visibleRows.length;
            break;
        case Qt.Key_L: case Qt.Key_Right:
        case Qt.Key_Return: case Qt.Key_Enter:
            root.enter();
            break;
        case Qt.Key_H: case Qt.Key_Left:
            root.back();
            break;
        case Qt.Key_Escape:
        case Qt.Key_Q:
            // Bare q closes -- safe here in a way it is not for the
            // cheatsheet's own search field, because this field is
            // readOnly (claims nothing) whenever this handler can even
            // see the keypress at all.
            root.closeRequested();
            break;
        default:
            return;
        }
        event.accepted = true;
    }

    PanelChrome {
        id: chrome
        anchors.fill: parent
        title: root.breadcrumb
        textFontFamily: root.textFontFamily
        hints: root.searching
            ? [{ key: "esc", label: "cancel search" }]
            : [
                { key: "hjkl", label: "move / back / open" },
                { key: "/", label: "search" },
                { key: "q / esc", label: "close" }
            ]
    }

    PanelSearchField {
        id: search
        x: chrome.contentX
        y: chrome.contentY
        width: chrome.contentWidth
        textFontFamily: root.textFontFamily
        iconFontFamily: root.iconFontFamily
        readOnly: true
        placeholder: "search " + (root.currentPath === "" ? "menu" : root.breadcrumb.toLowerCase()) + "…"
        countText: root.visibleRows.length > 0 ? String(root.visibleRows.length) : "no matches"
        escapeClearsQuery: true

        onMoved: (delta) => {
            if (root.visibleRows.length === 0)
                return;
            root.selectedIndex = (root.selectedIndex + delta + root.visibleRows.length)
                % root.visibleRows.length;
        }
        onMovedHorizontally: (delta) => { if (delta > 0) root.enter(); else root.back(); }
        onSubmitted: root.enter()
        onCancelled: root.exitSearch()
    }

    ListView {
        id: list
        x: chrome.contentX
        y: search.y + search.height + Metrics.pad(6)
        width: chrome.contentWidth
        height: Math.max(0, chrome.contentY + chrome.contentHeight - y)
        clip: true
        model: root.visibleRows
        currentIndex: root.selectedIndex
        highlightMoveDuration: Motion.controlDuration()

        onCurrentIndexChanged: {
            if (currentIndex >= 0)
                positionViewAtIndex(currentIndex, ListView.Contain);
        }

        delegate: Rectangle {
            id: rowItem
            required property var modelData
            required property int index
            readonly property bool selected: index === root.selectedIndex
            readonly property bool hasKids: root.hasChildren(modelData.id)

            width: list.width
            height: root.rowHeight
            radius: Metrics.RADIUS.tight
            color: selected ? IslandTheme.selectionFill : "transparent"

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: root.selectedIndex = rowItem.index
                onClicked: { root.selectedIndex = rowItem.index; root.enter(); }
            }

            Row {
                anchors.left: parent.left
                anchors.leftMargin: Metrics.pad(8)
                anchors.right: parent.right
                anchors.rightMargin: Metrics.pad(8)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Metrics.pad(8)

                Text {
                    text: rowItem.modelData.icon
                    color: rowItem.selected ? IslandTheme.accentText : IslandTheme.textMuted
                    font.family: root.iconFontFamily
                    font.pixelSize: Metrics.TYPE.body
                    width: Metrics.px(18)
                    horizontalAlignment: Text.AlignHCenter
                }

                Text {
                    width: parent.width - Metrics.px(18) - Metrics.px(14) - Metrics.pad(16)
                    text: rowItem.modelData.label
                    color: rowItem.selected ? IslandTheme.accentText : IslandTheme.textPrimary
                    font.family: root.textFontFamily
                    font.pixelSize: Metrics.TYPE.body
                    font.weight: rowItem.selected ? Font.DemiBold : Font.Normal
                    elide: Text.ElideRight
                }

                Text {
                    visible: rowItem.hasKids
                    text: "›"
                    color: IslandTheme.textMuted
                    font.family: root.textFontFamily
                    font.pixelSize: Metrics.TYPE.body
                    width: Metrics.px(14)
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }

        Text {
            anchors.centerIn: parent
            visible: root.visibleRows.length === 0
            text: search.query !== "" ? "no matches for “" + search.query + "”" : "nothing here"
            color: IslandTheme.textMuted
            font.family: root.textFontFamily
            font.pixelSize: Metrics.TYPE.body
        }
    }
}
