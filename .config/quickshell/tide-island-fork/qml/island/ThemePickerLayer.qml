pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io

// FORK: the shared scale factor — see qml/common/Metrics.js.
import "../common/Metrics.js" as Metrics
// FORK: the shared motion system — one spring for geometry, one
// critically damped curve for opacity. See qml/common/Motion.js.
import "../common/Motion.js" as Motion
import "../common/Match.js" as Match
import "../common"

//
// FORK — new file. The theme switcher DESIGN-SPEC.md lists as one of the
// island's states ("launcher, control center, calendar, power menu, Polkit
// prompt, wallpaper picker, theme switcher") and which upstream Tide Island
// does not have at all.
//
// It is a front-end for AtiScriptsV1/theme-apply, which already applies 22
// themes across kitty, rofi, dunst, GTK, Qt, btop, browsers, nvim AND
// Hyprland, and which is shared with the still-running qtile session. This
// layer deliberately owns no theming logic of its own: it lists what
// theme-apply offers and runs theme-apply. Anything smarter here would be a
// second opinion about the same state.
//
// This file used to state the spec's one hard rule about theming — "the
// colour of the shell shape stays #000000 regardless of what is picked in
// here… theme the contents, never the shape" — and that has been REVERSED
// by the user, deliberately, and is recorded as reversed in
// REQUIREMENTS.md item 1, upgread_UI_UX.md Part 3 and
// qml/common/IslandTheme.qml. Picking a theme in here now repaints the
// notch too.
//
// The spec's actual concern is still answered, just not by its rule: the
// fill is the palette's background slot dragged 45% toward black with 8%
// accent mixed in, which reads as tinted bezel rather than as the
// "coloured blob" the spec warns about. The measurement is in
// IslandTheme.qml. This note is here so nobody reads the spec alone and
// "fixes" the shape back to black.
//
FocusScope {
    id: root

    signal closeRequested

    // FORK: when the shell can drive the circular reveal (REQUIREMENTS.md
    // item 5), the picker hands the theme name over instead of running
    // theme-apply itself — the animation has to OWN the apply, because it
    // freezes the screen first and applies underneath the frozen frame.
    // Running it here as well would repaint the desktop before the capture
    // and there would be nothing left to reveal.
    signal themeRequested(string name)
    property bool useTransition: false

    property bool showCondition: false
    property string textFontFamily: ""
    property string heroFontFamily: ""
    // For the search field's magnifier. A Nerd Font glyph set in the
    // text family renders as nothing at all, with no warning.
    property string iconFontFamily: ""

    property var themes: []
    property string currentTheme: ""
    property int selectedIndex: 0
    property string pendingTheme: ""
    property string errorText: ""

    readonly property int columns: 4
    readonly property real tileSpacing: Metrics.px(10)
    // FORK: header height, content inset and the key-hint strip are
    // PanelChrome's now. See qml/common/PanelChrome.qml.

    // ---- SEARCH: A REAL FILTER, AND THIS TIME THAT IS THE RIGHT ANSWER ----
    //
    // The wallpaper picker got type-to-jump and its file explains why a filter
    // was wrong THERE: `allWallpapers` is a ListModel carrying per-item
    // thumbnail state (thumbnailReady, thumbnailSource, cacheRevision) and
    // `wallpaperIndexByPath` maps a path to its index in that model, so
    // rebuilding it to show a subset invalidates every index and throws away
    // the generated-thumbnail bookkeeping — a re-scan per keystroke.
    //
    // NONE OF THAT IS TRUE HERE, and it is worth being explicit rather than
    // copying the other panel's conclusion:
    //
    //   * `themes` is a plain JS array of {name, colors} parsed once from
    //     theme-list.sh. No per-item cache state, nothing keyed by index.
    //   * it is a GridView, not a PathView. A grid of 22 with 6 hidden is a
    //     grid you scroll; a grid of 3 is just a smaller grid. A carousel of
    //     3 is a different component.
    //   * 22 items, not 362. Filtering the whole array on every keystroke is
    //     22 string compares.
    //
    // So the query narrows the grid, and the count is drawn in the field for
    // the reason the wallpaper picker draws its own: a search with nothing on
    // screen is indistinguishable from a stuck keyboard, and the count is
    // what separates "no such theme" from "you typo'd".
    //
    // ---- BACK TO A MODE, ON REQUEST ----
    //
    // This was the rofi-style always-on field for a while — "the power
    // popop theme popup and some other popups need searchh bar like its
    // rofi one" — and then explicitly asked back the other way: "in theme
    // and wallpaer popup i wnat to use the normal keys hjkl to move untill
    // i use '/' so i enter to the searchbar and i can write to search".
    // That is vi's own model, and `searchFocused` is the mode: hjkl/g/G
    // navigate the grid by default, `/` focuses the field, Escape from the
    // field returns to navigation (the filter it left typed stays applied
    // — the same thing vim's own `/pattern<CR>` leaves you with).
    property bool searchFocused: false
    readonly property string searchQuery: searchField.query
    readonly property bool searching: root.searchQuery !== ""

    // The grid's model. `themes` stays the unfiltered truth — applyTheme and
    // the active-tile check both read names, not indices, so nothing outside
    // this property has to know the list narrowed.
    // Ranked through the shared matcher, so "mono" puts mono-dark and
    // mono-light above a theme that merely contains those letters, and so
    // this panel cannot drift from the others. A theme has no detail field —
    // the swatch IS its detail — so only the name is matched.
    readonly property var visibleThemes: Match.filter(
        root.themes, root.searchQuery,
        function (t) { return t.name; }, null)

    function endSearch() {
        searchField.clear();
        root.setSelection(0);
    }

    // ---- WHY THE PICKER SIZES ITSELF ----
    //
    // MEASURED: 22 themes in 4 columns is 6 rows at cellHeight
    // Metrics.px(62) = 57, so the grid wants 342 px. The capsule gave it
    // Metrics.px(290) = 267, of which the header takes 31 and the bottom
    // gap 18 — 218 px, or 3.8 rows. **Six of the 22 themes were below the
    // fold on every open**, and a GridView with `clip: true` says nothing
    // about that; the 19th tile simply is not there.
    //
    // A picker whose entire job is "show me what I can pick" hiding a
    // quarter of the options is the worst version of the "does not look
    // like the video" complaint, and it is not a styling problem — no
    // amount of padding fixes a missing row.
    //
    // The grid is not bound by the bar height (Metrics.js says why in its
    // second section): it hangs below the notch as a free-floating
    // surface, and the only thing constraining it is the screen. 6 rows
    // comes to 397 px on a 768 px panel. The clamp against the screen in
    // DynamicIslandWindow is what makes a 40-theme library scroll instead
    // of running off the bottom.
    readonly property int rowCount: Math.max(1, Math.ceil(root.visibleThemes.length / root.columns))
    readonly property real gridHeight: root.rowCount * root.cellHeight
    readonly property real cellHeight: Metrics.px(62)
    // ---- THE PANEL DOES NOT SHRINK WHILE YOU TYPE ----
    //
    // Sized from the UNFILTERED count on purpose, and it is PickerLayer's
    // argument applied to a grid: a panel that re-sizes on every keystroke
    // makes the query line — the one element that must stay under your eyes
    // while you type — walk up the screen as the list narrows. `rowCount`
    // follows the filter so the GRID lays out correctly; the frame does not.
    readonly property int fullRowCount:
        Math.max(1, Math.ceil(root.themes.length / root.columns))
    readonly property real preferredHeight:
        Metrics.chromeTotal() + root.searchStripHeight
        + root.fullRowCount * root.cellHeight

    // The field plus the gap under it. In one place because the height above
    // and the grid's y and height below all have to agree about it.
    readonly property real searchStripHeight: Metrics.px(26) + Metrics.px(10)

    focus: showCondition
    activeFocusOnTab: true
    anchors.fill: parent
    opacity: showCondition ? 1 : 0

    // FORK: one choreography for every layer in the shell.
    // Was `root.showCondition ? 220 : 120` on Easing.InOutQuad — one of
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

    onShowConditionChanged: {
        if (showCondition) {
            // Re-read on every open rather than caching. The qtile session
            // can change the theme while this is closed, and the two share
            // ~/.cache/qtile/theme_mode — a stale highlight here would be
            // the picker disagreeing with the desktop it is sitting on.
            themeListProcess.running = true;
            // Opens in NAVIGATION mode, not search — hjkl has to work the
            // instant the panel is on screen. The FocusScope itself holds
            // focus until `/` hands it to the field.
            root.searchFocused = false;
            root.forceActiveFocus();
        } else {
            root.errorText = "";
            root.searchFocused = false;
            // A query left over from the last open is a picker that comes up
            // showing three of twenty-two themes with no memory of why.
            searchField.clear();
        }
    }

    function applyTheme(name) {
        if (!name || applyProcess.running)
            return;

        // Optimistic: the highlight moves now, not when theme-apply
        // finishes. theme-apply takes over a second on a cold run (it
        // regenerates a dozen config files and reloads as many programs)
        // and a picker that does not acknowledge the click for that long
        // reads as broken, so pendingTheme carries the intent visually
        // while the real work happens.
        root.pendingTheme = name;
        root.errorText = "";

        if (root.useTransition) {
            root.themeRequested(name);
            // The picker cannot watch the apply's exit code any more — the
            // shell owns the process now — so the highlight is reconciled on
            // a timer instead. Long enough for theme-apply's slowest run plus
            // the 620ms reveal.
            reconcileTimer.restart();
            return;
        }

        applyProcess.command = [Quickshell.env("HOME") + "/.dotfiles/.config/AtiScriptsV1/theme-apply", name];
        applyProcess.running = true;
    }

    // Both walk `visibleThemes`, not `themes`: with a query active the grid IS
    // the filtered list, and clamping to the unfiltered length would let the
    // cursor run off the end of what is drawn.
    function moveSelection(delta) {
        if (root.visibleThemes.length === 0)
            return;
        let next = root.selectedIndex + delta;
        if (next < 0) next = 0;
        if (next > root.visibleThemes.length - 1) next = root.visibleThemes.length - 1;
        root.setSelection(next);
    }

    function setSelection(index) {
        if (root.visibleThemes.length === 0) {
            root.selectedIndex = 0;
            return;
        }
        const next = Math.max(0, Math.min(root.visibleThemes.length - 1, index));
        root.selectedIndex = next;
        themeGrid.positionViewAtIndex(next, GridView.Contain);
    }

    Process {
        id: themeListProcess
        command: [Quickshell.env("HOME") + "/.config/hypr/scripts/theme-list.sh"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(text);
                    root.themes = parsed.themes || [];
                    root.currentTheme = String(parsed.current || "");
                    root.pendingTheme = "";
                    const activeIndex = root.indexOfTheme(root.currentTheme);
                    root.selectedIndex = activeIndex >= 0 ? activeIndex : 0;
                    themeGrid.positionViewAtIndex(root.selectedIndex, GridView.Contain);
                } catch (error) {
                    // A parse failure here means theme-list.sh emitted
                    // something that is not JSON, which in practice means
                    // theme-apply moved or its presets block changed shape.
                    // Say so in the panel rather than presenting an empty
                    // grid that looks like "you have no themes".
                    root.themes = [];
                    root.errorText = "could not read theme list";
                }
            }
        }
    }

    Timer {
        id: reconcileTimer
        interval: 2600
        repeat: false
        onTriggered: themeListProcess.running = true
    }

    Process {
        id: applyProcess
        onExited: function(exitCode) {
            if (exitCode !== 0)
                root.errorText = "theme-apply failed (" + exitCode + ")";
            // Re-read either way: on success to pick up the new current
            // theme, on failure to snap the highlight back to whatever is
            // actually applied instead of leaving the optimistic one.
            themeListProcess.running = true;
        }
    }

    // Over the VISIBLE list, because its one caller positions the cursor and
    // the cursor indexes what is drawn. With no query the two lists are the
    // same object, so this is unchanged in the normal case.
    function indexOfTheme(name) {
        for (let index = 0; index < root.visibleThemes.length; index++) {
            if (String(root.visibleThemes[index].name) === String(name))
                return index;
        }
        return -1;
    }

    // ---- NAVIGATION MODE'S KEY MAP ----
    //
    // Only reached while `searchFocused` is false, which is what keeps
    // these letters from typing into a query — the field holds the
    // keyboard once `/` hands it over, and this handler sees nothing but
    // what the field does not claim (Escape/Enter/arrows/Ctrl+HJKL, wired
    // below). See `searchFocused`'s own note for why this is a mode again.
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
        case Qt.Key_H:
        case Qt.Key_Left:
            root.moveSelection(-1);
            event.accepted = true;
            break;
        case Qt.Key_L:
        case Qt.Key_Right:
            root.moveSelection(1);
            event.accepted = true;
            break;
        case Qt.Key_K:
        case Qt.Key_Up:
            root.moveSelection(-root.columns);
            event.accepted = true;
            break;
        case Qt.Key_J:
        case Qt.Key_Down:
            root.moveSelection(root.columns);
            event.accepted = true;
            break;
        case Qt.Key_G:
            root.setSelection((event.modifiers & Qt.ShiftModifier)
                ? root.visibleThemes.length - 1 : 0);
            event.accepted = true;
            break;
        case Qt.Key_Return:
        case Qt.Key_Enter:
            root.activateSelection();
            event.accepted = true;
            break;
        default:
            break;
        }
    }

    // One place for "apply what is under the cursor", because the field's
    // Enter and the fallback Enter must not drift apart — and because the
    // bounds check is the difference between applying a theme and applying
    // `undefined` when the filter matched nothing.
    function activateSelection() {
        if (root.selectedIndex >= 0 && root.selectedIndex < root.visibleThemes.length)
            root.applyTheme(String(root.visibleThemes[root.selectedIndex].name));
    }

    // ---- CHROME, SHARED ---- see qml/common/PanelChrome.qml.
    //
    // The error used to REPLACE the title, exactly as the power menu's did —
    // the panel stopped saying what it was at the moment something failed. It
    // is in the status slot now, which already colours by level.
    PanelChrome {
        id: chrome
        textFontFamily: root.textFontFamily

        title: "theme"

        // The query itself is in the field now and does not need echoing in
        // the header. What stays is the ALERT: red when a query matches
        // nothing, because an empty grid and a stuck keyboard look alike.
        statusClause: ""
        statusClauseLive: false
        statusClauseAlert: root.searching && root.visibleThemes.length === 0

        status: {
            if (root.errorText !== "")
                return root.errorText;
            if (root.pendingTheme !== "")
                return "applying " + root.pendingTheme + "…";
            return root.currentTheme;
        }
        statusLevel: root.errorText !== "" ? "error"
                   : (root.pendingTheme !== "" ? "busy" : "idle")

        // One strip in both states. The old panel had two, because it had two
        // modes to describe; there is one now, and a hint strip that changes
        // under you is itself a thing to read twice.
        hints: root.searchFocused
            ? [
                { key: "type", label: "filter" },
                { key: "Enter", label: "apply" },
                { key: "Esc", label: "back" }
              ]
            : [
                { key: "hjkl", label: "move" },
                { key: "/", label: "search" },
                { key: "Enter", label: "apply" },
                { key: "q", label: "close" }
              ]
    }

    PanelSearchField {
        id: searchField
        x: chrome.contentX
        y: chrome.contentY
        width: chrome.contentWidth

        textFontFamily: root.textFontFamily
        iconFontFamily: root.iconFontFamily
        placeholder: "type to filter themes"
        countText: root.searching
            ? (root.visibleThemes.length + " of " + root.themes.length) : ""
        // Claims nothing, keeps focus, while navigation mode owns the
        // keyboard — see `searchFocused`.
        readOnly: !root.searchFocused
        // One-stage: Escape always leaves the field. The two-stage
        // clear-then-cancel is for a host with nowhere else for Escape to
        // go; this one has navigation mode to go back to, and the filter
        // staying applied there is the point — vim's own `/pattern<CR>`
        // leaves the pattern active too.
        escapeClearsQuery: false

        // Both Enter and Escape leave search back to navigation mode — the
        // doc's own wording for this ask: "Esc/Enter leave search back to
        // command mode".
        onSubmitted: {
            root.activateSelection();
            root.searchFocused = false;
            root.forceActiveFocus();
        }
        onCancelled: {
            root.searchFocused = false;
            root.forceActiveFocus();
        }
        // A grid, so vertical movement is a whole ROW and horizontal is one
        // tile — the same mapping the arrow keys always had here.
        onMoved: function(delta) { root.moveSelection(delta * root.columns); }
        onMovedHorizontally: function(delta) { root.moveSelection(delta); }
    }

    // Back to the first match on every change of the query. Unlike the
    // wallpaper carousel there is no "current item" worth preserving across a
    // narrowing: the grid has re-laid out under the cursor entirely, so
    // whatever index survived is pointing at a different theme.
    onSearchQueryChanged: root.setSelection(0)

    GridView {
        id: themeGrid
        x: chrome.contentX
        y: chrome.contentY + root.searchStripHeight
        width: chrome.contentWidth
        height: chrome.contentHeight - root.searchStripHeight
        clip: true

        // FORK: P1-3, and the note at the top of this file already said it —
        // "a GridView with `clip: true` says nothing" about the rows below
        // the fold. Now it does.
        ScrollBar.vertical: IslandScrollBar { view: themeGrid }

        cellWidth: Math.floor(width / root.columns)
        // Tall enough that the label and the swatch chips cannot meet. The tile's
        // usable height is cellHeight MINUS tileSpacing (the delegate insets
        // itself by tileSpacing/2 on each side), which is what made the first
        // scaled attempt overlap: 41 looked like plenty and was 34 in practice.
        // Lives on root now, because preferredHeight is built from it and a
        // grid sized off a different cell height than the shape around it is
        // a grid with a clipped last row.
        cellHeight: root.cellHeight
        model: root.visibleThemes
        currentIndex: root.selectedIndex
        boundsBehavior: Flickable.StopAtBounds

        // MEASURED with panel-glitch-frames.py + a frame-by-frame visual
        // diff: the grid was still visibly scrolling ~500-600ms after the
        // capsule's own shape had settled — not a Motion.js curve, since
        // nothing here calls into it. `highlightFollowsCurrentItem`
        // defaults to true and `highlightMoveDuration` defaults to -1
        // (Qt's own velocity-based follow, tuned for neither this panel
        // nor this shell), so every `currentIndex` write — which
        // `setSelection()` below already pairs with an explicit, meant-
        // to-be-instant `positionViewAtIndex(..., Contain)` — ALSO kicked
        // off Qt's own slow follow-scroll on top of it. Two view-movement
        // mechanisms doing the same job, uncoordinated, is what read as
        // "not smooth". Zero makes `currentIndex` changes land in the same
        // frame `positionViewAtIndex` already does.
        highlightMoveDuration: 0

        // Whole rows only.
        //
        // positionViewAtIndex(Contain) scrolls by the minimum needed to make
        // one CELL visible, which routinely lands contentY mid-row: the row
        // above is then cut horizontally through its middle by the panel's
        // top edge — labels sliced in half, tiles at half height, hard
        // against the header. It looks like a rendering fault rather than
        // like scrolling. snapMode makes every rest position a row boundary,
        // so a partially scrolled grid always reads as "there is more above",
        // never as "this is broken".
        snapMode: GridView.SnapToRow

        // And a real gap under the header, so even a mid-flick frame has the
        // top row passing UNDER a margin rather than touching the title.
        topMargin: Metrics.pad(6)

        delegate: Item {
            id: tile
            required property int index
            required property var modelData

            width: themeGrid.cellWidth
            height: themeGrid.cellHeight

            readonly property bool isActive:
                String(tile.modelData.name) === (root.pendingTheme !== "" ? root.pendingTheme : root.currentTheme)
            readonly property bool isSelected: tile.index === root.selectedIndex

            Rectangle {
                anchors.fill: parent
                anchors.margins: root.tileSpacing / 2
                radius: Metrics.px(10)
                // The swatch IS the tile background, so the list previews
                // itself: every tile is painted in the palette it applies.
                //
                // ONE OF THE FOUR DELIBERATE EXCEPTIONS TO THE TOKEN LAYER,
                // and the one whose reason is easiest to state: bound to
                // IslandTheme this picker would be twenty-two identical
                // swatches in the theme you already have. The chrome around
                // them — the header, the hint footer, the status line — does
                // follow the palette, and does so a few lines above and
                // below. Only the tiles and their borders opt out, because a
                // fixed white-alpha edge is the only edge that reads on all
                // twenty-two backgrounds at once.
                color: tile.modelData.bg || "#1a1a1a"
                border.width: tile.isActive ? 2 : (tile.isSelected ? 1 : 0)
                border.color: tile.isActive
                    ? (tile.modelData.accent || "white")
                    : "#55ffffff"

                Behavior on border.width { NumberAnimation { duration: 120 } }

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: Metrics.pad(10)
                    anchors.top: parent.top
                    // px, not pad: inside a 46px tile the label and the chips are
                    // competing for the same 39px, and generous margins here buy
                    // breathing room by taking it from the two things that need it.
                    anchors.topMargin: Metrics.px(8)
                    text: tile.modelData.name
                    color: tile.modelData.fg || "white"
                    font.pixelSize: Metrics.font(12)
                    font.family: root.textFontFamily
                    font.weight: tile.isActive ? Font.DemiBold : Font.Normal
                    elide: Text.ElideRight
                    width: parent.width - Metrics.pad(20)
                }

                // Three chips: alt, fg, accent. Enough to tell nord from
                // everforest at a glance, which is the actual job — the
                // full 9-slot palette in a 4-column grid would be mush.
                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: Metrics.pad(10)
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: Metrics.px(9)
                    spacing: Metrics.px(5)

                    Repeater {
                        model: [tile.modelData.alt, tile.modelData.fg, tile.modelData.accent]
                        delegate: Rectangle {
                            required property var modelData
                            width: Metrics.px(12)
                            height: Metrics.px(12)
                            radius: Metrics.px(3)
                            color: modelData || "#000000"
                            border.width: 1
                            border.color: "#22ffffff"
                        }
                    }
                }

                // wal has no fixed palette — it is derived from whatever
                // wallpaper is up — so its swatch is a placeholder and
                // saying so is more honest than showing three grey chips.
                Text {
                    visible: tile.modelData.dynamic === true
                    anchors.right: parent.right
                    anchors.rightMargin: Metrics.pad(10)
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: Metrics.px(9)
                    text: "from wallpaper"
                    color: IslandTheme.textMuted
                    font.pixelSize: Metrics.font(9)
                    font.family: root.textFontFamily
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: root.selectedIndex = tile.index
                    onClicked: root.applyTheme(String(tile.modelData.name))
                }
            }
        }
    }
}
