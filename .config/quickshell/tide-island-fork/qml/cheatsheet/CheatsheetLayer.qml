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
// FORK: FocusScope, not Item — `root.forceActiveFocus()` on a plain Item
// does not move keyboard focus back OFF the search field the way it does
// on every sibling panel (ThemePickerLayer, WallpaperPickerLayer,
// DisplayPanel, …), because only a FocusScope's focus-child mechanism
// gives that call somewhere defined to land. Needed for `searchFocused`
// below, which is the same hjkl/`/` mode switch those panels already have.
FocusScope {
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
    property bool loading: false

    // ---- NAVIGATION MODE, LIKE THE THEME AND WALLPAPER PICKERS ----
    //
    // Asked for directly: "make it works with hjkl motion and not enter to
    // the searchbar till i click '/'". This panel used to hold the field
    // focused the entire time it was open — the "better answer" this
    // file's own header comment credits it with, before ThemePickerLayer
    // and WallpaperPickerLayer were BOTH moved off that shape and back to a
    // `/`-gated mode (`064f4bf`). Bringing this one in line rather than
    // leaving it the one panel still disagreeing with the other two.
    //
    // `query` is no longer a property this file writes — it is read
    // straight off the field below, same as ThemePickerLayer's
    // `searchQuery`, so there is exactly one place that holds the text.
    property bool searchFocused: false
    readonly property string query: searchField.query

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

    // PanelChrome's `tabs` model — the {value, label} form, since the label
    // on screen ("FISH / KITTY") is not the sheet key cheatsheet.py takes
    // ("fish"). Replaces the hand-rolled Repeater the header used to draw;
    // see PanelTabs.qml.
    readonly property var chromeTabs: {
        const out = [];
        for (const key of root.sheetOrder)
            out.push({ value: key, label: root.sheetLabels[key] || key });
        return out;
    }

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

    // The field plus the gap under it. Same two numbers ThemePickerLayer's
    // own `searchStripHeight` uses — one field height, one shell.
    readonly property real searchStripHeight: Metrics.px(26) + Metrics.px(10)

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
    // Per-row/per-header estimate matches the card delegate's OWN sizes
    // further down — a px(15) combo chip plus px(2) row spacing, and a
    // TYPE.strong(13) card title plus its own padding — not the bigger
    // numbers this used before the card content was rescaled down to the
    // rest of the shell's ramp. See that section for the actual values.
    readonly property real bodyHeight: {
        const heights = [0, 0, 0];
        for (const section of root.sections) {
            let at = 0;
            for (let c = 1; c < 3; c++)
                if (heights[c] < heights[at])
                    at = c;
            heights[at] += (section.rows || []).length * Metrics.px(17)
                + Metrics.px(23);
        }
        return Math.max(heights[0], heights[1], heights[2]);
    }

    // Metrics and chrome.tabsHeight, not chrome.chromeHeight — same reason
    // DisplayPanel's own tabbed `preferredHeight` reads it this way: this
    // number sizes the capsule the panel is drawn inside, so reading it off
    // a child of that panel is a loop waiting for one more term.
    readonly property real preferredHeight:
        Math.max(Metrics.px(200),
                 Math.round(Metrics.chromeTotal() + chrome.tabsHeight
                     + root.searchStripHeight + root.bodyHeight));

    // ---- FETCHING: A FRESH Process EVERY TIME, ON PURPOSE ----
    //
    // Same lesson as ModeKeysLayer.qml, and it cost enough there to be
    // worth obeying without re-learning it: a REUSED Process and its
    // StdioCollector hand back the PREVIOUS run's text, so switching sheets
    // with Tab would render vim's rows under the WM's title — one sheet
    // behind, correct on the first press and lying on every one after.
    // Toggling the Loader destroys the pair and builds a new one.
    function reload() {
        console.log("[cheatsheet] reload() for sheet '" + root.sheet + "'");
        root.loading = true;
        fetchLoader.active = false;
        fetchLoader.active = true;
    }

    // Does NOT clear `sections`/`title`/`note` — same reason
    // `onShowConditionChanged` below doesn't: this handler fires on every
    // Tab/h/l sheet switch, not just open, and wiping the model here
    // collapses the capsule to `preferredHeight`'s px(200) floor and back
    // for every switch, the same up-down glitch `retain` on this file's
    // Loader (DynamicIslandWindow) was added to remove — retain does not
    // cover this path, because the instance is already alive and nothing
    // is destroyed/rebuilt on a plain sheet change.
    onSheetChanged: root.reload()

    // Opens in NAVIGATION mode, not search — hjkl has to work the instant
    // the panel is on screen, same as ThemePickerLayer's own note on its
    // twin of this handler. `searchField.clear()` and not `root.query = ""`:
    // `query` is derived off the field now, so clearing it means clearing
    // what it is derived FROM.
    //
    // Does NOT clear `sections` — retaining this Loader (DynamicIslandWindow)
    // is what keeps the PREVIOUS sheet's cards on screen, correctly sized,
    // while this reload's fetch is in flight, and wiping the model here
    // would put the empty-capsule collapse straight back.
    onShowConditionChanged: {
        if (showCondition) {
            searchField.clear();
            root.searchFocused = false;
            root.reload();
            focusTimer.restart();
        } else {
            root.searchFocused = false;
        }
    }

    // PanelLoader mounts this item only once `live` is already true, so
    // `showCondition` is 1 from construction and the handler above never
    // fires for the FIRST open — the same trap ThemePickerLayer's and
    // PickerLayer's own Component.onCompleted exist to close. Without this,
    // the very first cheatsheet of a session would show "nothing in this
    // sheet" forever, having never asked cheatsheet.py for anything.
    Component.onCompleted: {
        // If this ever logs mid-session (not just once at the very start),
        // the whole CheatsheetLayer instance was destroyed and rebuilt --
        // `sheet` resets to its "hypr" default on that, which would look
        // exactly like "scroll up and it goes to hyprland" from the
        // outside even though nothing about scrolling caused it.
        console.log("[cheatsheet] CheatsheetLayer (re)created, sheet='" + root.sheet + "'");
        if (root.showCondition)
            root.reload();
    }

    Loader {
        id: fetchLoader
        active: false

        sourceComponent: Component {
            Process {
                // "switch to vim, scroll down, scroll up again -> it goes
                // to hyprland". `command` above is a LIVE binding to
                // root.sheet, but this Process was already spawned for
                // whatever sheet was current the moment it was created --
                // reading root.sheet again down in onStreamFinished, after
                // the fact, answers "what sheet is selected NOW", not
                // "what sheet was this particular fetch FOR". Two fetches
                // can be in flight at once (a fast double Tab, or Tab
                // right as a slow one is still running) and nothing before
                // this stopped the OLDER one's callback from landing
                // second and overwriting the newer sheet's content with
                // the older sheet's data -- exactly the shape reported,
                // and exactly what reload()'s own comment already named
                // as the risk ("StdioCollector hand back the PREVIOUS
                // run's text") without this guard actually closing it.
                // Captured once, at creation, so it can't drift.
                id: fetchProcess
                property string fetchedFor: root.sheet
                command: ["python3", root.ctl, "--sheet-json", root.sheet]
                running: true
                stdout: StdioCollector {
                    onStreamFinished: {
                        if (fetchProcess.fetchedFor !== root.sheet) {
                            console.log("[cheatsheet] discarding stale fetch for '"
                                + fetchProcess.fetchedFor + "', current sheet is '" + root.sheet + "'");
                            return;
                        }
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

    // Called on the first open (DynamicIslandWindow's onLoaded) and on
    // every reopen — always into NAVIGATION mode, same as the theme and
    // wallpaper pickers. A field that grabbed focus unconditionally is
    // exactly the shape being removed here.
    function grabKeyboardFocus() {
        root.searchFocused = false;
        root.forceActiveFocus();
    }

    function cycleSheet(step) {
        const order = root.sheetOrder;
        const at = order.indexOf(root.sheet);
        const next = (at < 0 ? 0 : (at + step + order.length) % order.length);
        console.log("[cheatsheet] cycleSheet(" + step + ") from '" + root.sheet + "' -> '" + order[next] + "'");
        if (order[next] !== root.sheet) {
            searchField.clear();
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

    // g / G, same convention as ThemePickerLayer and SystemMonitorPanel:
    // jump the viewport to either end without walking it a page at a time.
    function jumpTo(where) {
        body.contentY = where === "top"
            ? 0 : Math.max(0, body.contentHeight - body.height);
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

    // ---- NAVIGATION MODE'S KEY MAP ----
    //
    // Only reached while `searchFocused` is false — same shape as
    // ThemePickerLayer's own handler, and for the same reason: the field
    // holds the keyboard once `/` hands it over, and this handler sees
    // nothing but what the field does not claim (Escape/Tab, wired through
    // PanelSearchField's `cancelled`/`tabbed` signals below).
    Keys.onPressed: function(event) {
        if (root.searchFocused)
            return;

        switch (event.key) {
        case Qt.Key_Escape:
        case Qt.Key_Q:
            root.closeRequested();
            event.accepted = true;
            break;
        case Qt.Key_Slash:
            root.searchFocused = true;
            searchField.focusField();
            event.accepted = true;
            break;
        case Qt.Key_J:
        case Qt.Key_Down:
            root.scrollBy(0.25);
            event.accepted = true;
            break;
        case Qt.Key_K:
        case Qt.Key_Up:
            root.scrollBy(-0.25);
            event.accepted = true;
            break;
        // h/l double as the sheet switcher — the tab row is laid out
        // left-to-right, so "left/right" and "previous/next sheet" are the
        // same motion. Tab/Shift+Tab still do it too; the field's own
        // `tabbed` signal below reaches the same function while searching.
        case Qt.Key_H:
        case Qt.Key_Left:
        case Qt.Key_Backtab:
            root.cycleSheet(-1);
            event.accepted = true;
            break;
        case Qt.Key_L:
        case Qt.Key_Right:
        case Qt.Key_Tab:
            root.cycleSheet(1);
            event.accepted = true;
            break;
        case Qt.Key_G:
            root.jumpTo((event.modifiers & Qt.ShiftModifier) ? "bottom" : "top");
            event.accepted = true;
            break;
        case Qt.Key_PageDown:
            root.scrollBy(1);
            event.accepted = true;
            break;
        case Qt.Key_PageUp:
            root.scrollBy(-1);
            event.accepted = true;
            break;
        default:
            break;
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
    // ---- CHROME, SHARED ---- see qml/common/PanelChrome.qml. Replaces the
    // hand-rolled title/note/tab Row this file used to draw on its own,
    // which is the other half of "make cheat's fonts same like other
    // popups": register B (font(10) uppercase, muted, a "· note" clause) is
    // what every other panel's title already is, and this one was the sole
    // holdout still drawing its own font(20) hero title.
    PanelChrome {
        id: chrome
        textFontFamily: root.textFontFamily

        title: root.title

        // The keyd note ("ALT = Caps Lock…") in the clause slot, same
        // corner Wi-Fi's "· SSID" occupies — not `status`, which is a
        // right-aligned, colour-by-level "what is happening now" and the
        // note is neither of those, it is a fact about the sheet.
        statusClause: root.note === "" ? "" : "· " + root.note
        statusClauseLive: false

        status: root.loading ? "loading…" : ""
        statusLevel: root.loading ? "busy" : "idle"

        tabs: root.chromeTabs
        currentTab: root.sheet
        onTabRequested: name => {
            if (name !== root.sheet) {
                searchField.clear();
                root.sheet = name;
            }
            root.grabKeyboardFocus();
        }

        hints: root.searchFocused
            ? [
                { key: "type", label: "filter" },
                { key: "Tab", label: "sheet" },
                { key: "Esc", label: "back" }
              ]
            : [
                { key: "j/k", label: "scroll" },
                { key: "h/l", label: "sheet" },
                { key: "/", label: "search" },
                { key: "q", label: "close" }
              ]
    }

    // ---- THE SEARCH FIELD, SHARED ---- see qml/common/PanelSearchField.qml.
    // Replaces the hand-rolled Rectangle+TextInput this file grew before
    // that component existed — the rest of "make cheat's fonts same like
    // other popups". `readOnly`, not a focus hand-off, is what keeps
    // navigation-mode keys from typing into it while it sits unfocused —
    // see the component's own note on why.
    PanelSearchField {
        id: searchField
        x: chrome.contentX
        y: chrome.contentY
        width: chrome.contentWidth

        textFontFamily: root.textFontFamily
        iconFontFamily: root.iconFontFamily
        placeholder: "type to filter"
        countText: root.loading ? "" : (root.query === "" ? "" : root.matchCount + " match")
        // Claims nothing, keeps focus, while navigation mode owns the
        // keyboard — see `searchFocused`.
        readOnly: !root.searchFocused
        // One-stage: Escape always leaves the field, same as ThemePickerLayer
        // — this panel has navigation mode to fall back to, and the filter
        // staying applied there is the point, same as vim's own `/pat<CR>`.
        escapeClearsQuery: false

        // Cheatsheet rows are not "selected and activated" the way a theme
        // or a wallpaper is — there is nothing for Enter to commit — so it
        // does the same thing Escape does: leave search mode, keep the
        // filter.
        onSubmitted: {
            root.searchFocused = false;
            root.forceActiveFocus();
        }
        onCancelled: {
            root.searchFocused = false;
            root.forceActiveFocus();
        }
        // Same split as h/l and j/k in navigation mode: vertical scrolls,
        // horizontal switches sheets. Tab does too, for the sheet — the
        // signal PanelSearchField's own header comment names this shell's
        // "panels with sheets" for.
        onMoved: function(delta) { root.scrollBy(delta * 0.25); }
        onMovedHorizontally: function(delta) { root.cycleSheet(delta); }
        onTabbed: function(direction) { root.cycleSheet(direction); }
    }

    // Any filter change makes the old scroll position meaningless — the row
    // it was showing may not be in the grid any more.
    onQueryChanged: body.contentY = 0

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
        x: chrome.contentX
        y: chrome.contentY + root.searchStripHeight
        width: chrome.contentWidth
        height: chrome.contentHeight - root.searchStripHeight
        clip: true
        contentWidth: width
        contentHeight: cardGrid.implicitHeight + Metrics.px(12)
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: IslandScrollBar { view: body }

        // A search that matches nothing has to say so. A blank grid
        // reads as a panel that failed to load. TYPE.reading — same size
        // every other panel's own empty-state line uses (WifiPanel's "no
        // networks", BluetoothPanel's "no devices"), not a one-off bigger
        // than either.
        Text {
            anchors.centerIn: parent
            visible: !root.loading && root.matchCount === 0
            text: root.query === "" ? "nothing in this sheet" : "no key matches “" + root.query + "”"
            color: IslandTheme.textDisabled
            font.family: root.textFontFamily
            font.pixelSize: Metrics.TYPE.reading
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
                            // Guarded: a fast-typed search rebuilds this
                            // Repeater's whole model on every keystroke
                            // (`cardColumns` is a plain array, not an
                            // incremental model), and a delegate can be
                            // asked to bind before Qt has finished
                            // parenting it into the Column above —
                            // measured as a real, repeating "Cannot read
                            // property 'width' of null" in the log
                            // during exactly that (typing "yank" letter
                            // by letter). Self-corrects the next frame
                            // either way; this just stops it logging.
                            width: parent ? parent.width : 0
                            height: cardCol.implicitHeight + Metrics.px(12)
                            // RADIUS.card, not px(8) — that constant is
                            // deliberately NOT run through the SCALE that
                            // Metrics.px() applies to everything else; it is
                            // derived to sit concentric with this panel's own
                            // px(18) content padding, and asking px() to
                            // scale it again is what broke that. See
                            // Metrics.js's own note on the RADIUS table.
                            radius: Metrics.RADIUS.card
                            color: IslandTheme.surfaceRaised

                            Column {
                                id: cardCol
                                x: Metrics.pad(9)
                                y: Metrics.pad(6)
                                width: parent.width - Metrics.pad(18)
                                spacing: Metrics.px(2)

                                // TYPE.strong — "emphasised body", the same
                                // ramp step every other panel reaches for on
                                // a label that has to stand out from its own
                                // rows without becoming a second title. Was
                                // font(18), a size nothing else in the shell
                                // uses outside the hero clock.
                                Text {
                                    text: String(card.modelData.title || "")
                                    color: IslandTheme.info
                                    font.family: root.textFontFamily
                                    font.pixelSize: Metrics.TYPE.strong
                                    font.weight: Font.DemiBold
                                    bottomPadding: Metrics.px(3)
                                }

                                Repeater {
                                    model: card.modelData.rows

                                    delegate: Item {
                                        required property var modelData
                                        width: cardCol.width
                                        // The label now runs a size bigger
                                        // than the chip (TYPE.reading vs the
                                        // chip's fixed px(15)), where it used
                                        // to be the chip that was tallest —
                                        // so the row has to size off whichever
                                        // actually is, or the label clips
                                        // against the next row.
                                        height: Math.max(rowComboChip.height, rowLabel.implicitHeight)

                                        // The combo first and fixed-width,
                                        // the label filling what is left —
                                        // the eye scans one column of keys,
                                        // same as qtile's own grid.
                                        //
                                        // The chip is styled off KeyHint.qml
                                        // — the shell's one existing small
                                        // key-badge, drawn in every panel's
                                        // own footer — rather than off a
                                        // number invented for this file:
                                        // RADIUS.tight, a hairline border,
                                        // TYPE.caption DemiBold on
                                        // textSecondary. The label beside it
                                        // is what a footer hint's own label
                                        // is not — the ROW's primary content,
                                        // not a second caption — so it takes
                                        // TYPE.reading, the size every list
                                        // row's primary label uses elsewhere
                                        // (BluetoothPanel, WifiPanel,
                                        // PickerLayer).
                                        Rectangle {
                                            id: rowComboChip
                                            width: Math.min(rowComboText.implicitWidth + Metrics.pad(8),
                                                            parent.width * 0.45)
                                            height: Metrics.px(15)
                                            radius: Metrics.RADIUS.tight
                                            color: IslandTheme.surfaceRaised
                                            border.width: 1
                                            border.color: IslandTheme.hairline
                                            Text {
                                                id: rowComboText
                                                anchors.centerIn: parent
                                                width: parent.width - Metrics.pad(6)
                                                elide: Text.ElideRight
                                                text: String(modelData.combo || "")
                                                color: IslandTheme.textSecondary
                                                font.family: root.textFontFamily
                                                font.pixelSize: Metrics.TYPE.caption
                                                font.weight: Font.DemiBold
                                            }
                                        }
                                        Text {
                                            id: rowLabel
                                            anchors.left: rowComboChip.right
                                            anchors.leftMargin: Metrics.pad(6)
                                            anchors.right: parent.right
                                            anchors.verticalCenter: rowComboChip.verticalCenter
                                            elide: Text.ElideRight
                                            text: String(modelData.label || "")
                                            color: IslandTheme.textPrimary
                                            font.family: root.textFontFamily
                                            font.pixelSize: Metrics.TYPE.reading
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
