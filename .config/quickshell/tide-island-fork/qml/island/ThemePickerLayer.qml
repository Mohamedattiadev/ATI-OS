pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import IslandBackend

// FORK: the shared scale factor — see qml/common/Metrics.js.
import "../common/Metrics.js" as Metrics
// FORK: the shared motion system — one spring for geometry, one
// critically damped curve for opacity. See qml/common/Motion.js.
import "../common/Motion.js" as Motion

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
// The colour of the shell shape stays #000000 regardless of what is picked
// in here. That is the spec's one hard rule about theming and it is worth
// restating at the site that would otherwise be tempted to break it: the
// notch is imitating bezel, "tint it and it stops being a notch and becomes
// a colored blob". Theme the contents, never the shape.
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

    property var themes: []
    property string currentTheme: ""
    property int selectedIndex: 0
    property string pendingTheme: ""
    property string errorText: ""

    readonly property int columns: 4
    readonly property real tileSpacing: Metrics.px(10)
    readonly property real horizontalPadding: Metrics.pad(18)
    readonly property real headerHeight: Metrics.pad(34)

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
    readonly property int rowCount: Math.max(1, Math.ceil(root.themes.length / root.columns))
    readonly property real gridHeight: root.rowCount * root.cellHeight
    readonly property real cellHeight: Metrics.px(62)
    readonly property real preferredHeight:
        root.headerHeight + Metrics.pad(6) + root.gridHeight + Metrics.pad(18)

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
            forceActiveFocus();
        } else {
            root.errorText = "";
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

    function moveSelection(delta) {
        if (root.themes.length === 0)
            return;
        let next = root.selectedIndex + delta;
        if (next < 0) next = 0;
        if (next > root.themes.length - 1) next = root.themes.length - 1;
        root.setSelection(next);
    }

    function setSelection(index) {
        if (root.themes.length === 0)
            return;
        const next = Math.max(0, Math.min(root.themes.length - 1, index));
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

    function indexOfTheme(name) {
        for (let index = 0; index < root.themes.length; index++) {
            if (String(root.themes[index].name) === String(name))
                return index;
        }
        return -1;
    }

    Keys.onPressed: function(event) {
        switch (event.key) {
        case Qt.Key_Escape:
            root.closeRequested();
            event.accepted = true;
            break;
        // hjkl beside the arrows. This is a grid, so h/l step one tile and
        // j/k step one ROW — `root.columns` tiles — which is what the arrow
        // keys already did and what the hand expects from a grid. Every
        // other panel in this shell reads vim motions; the theme picker was
        // the one that did not, and there is no reason for it to be the
        // exception.
        case Qt.Key_Left:
        case Qt.Key_H:
            root.moveSelection(-1);
            event.accepted = true;
            break;
        case Qt.Key_Right:
        case Qt.Key_L:
            root.moveSelection(1);
            event.accepted = true;
            break;
        case Qt.Key_Up:
        case Qt.Key_K:
            root.moveSelection(-root.columns);
            event.accepted = true;
            break;
        case Qt.Key_Down:
        case Qt.Key_J:
            root.moveSelection(root.columns);
            event.accepted = true;
            break;
        // g / G to the ends, same as the audio and display panels.
        case Qt.Key_G:
            root.setSelection((event.modifiers & Qt.ShiftModifier) !== 0
                              ? root.themes.length - 1 : 0);
            event.accepted = true;
            break;
        case Qt.Key_Return:
        case Qt.Key_Enter:
        case Qt.Key_Space:
            if (root.selectedIndex >= 0 && root.selectedIndex < root.themes.length)
                root.applyTheme(String(root.themes[root.selectedIndex].name));
            event.accepted = true;
            break;
        default:
            break;
        }
    }

    Text {
        id: header
        x: root.horizontalPadding
        y: Metrics.pad(12)
        height: root.headerHeight - Metrics.pad(12)
        text: root.errorText !== "" ? root.errorText : "Theme"
        color: root.errorText !== "" ? "#ff6b6b" : "white"
        font.pixelSize: Metrics.font(15)
        font.family: root.heroFontFamily
        font.weight: Font.DemiBold
        font.letterSpacing: -0.2
    }

    Text {
        anchors.right: parent.right
        anchors.rightMargin: root.horizontalPadding
        y: Metrics.pad(12)
        height: root.headerHeight - Metrics.pad(12)
        text: root.pendingTheme !== "" ? "applying " + root.pendingTheme + "…" : root.currentTheme
        color: "#8a8a8a"
        font.pixelSize: Metrics.font(13)
        font.family: root.textFontFamily
    }

    GridView {
        id: themeGrid
        x: root.horizontalPadding
        y: root.headerHeight + Metrics.pad(6)
        width: parent.width - root.horizontalPadding * 2
        height: parent.height - root.headerHeight - Metrics.pad(18)
        clip: true
        cellWidth: Math.floor(width / root.columns)
        // Tall enough that the label and the swatch chips cannot meet. The tile's
        // usable height is cellHeight MINUS tileSpacing (the delegate insets
        // itself by tileSpacing/2 on each side), which is what made the first
        // scaled attempt overlap: 41 looked like plenty and was 34 in practice.
        // Lives on root now, because preferredHeight is built from it and a
        // grid sized off a different cell height than the shape around it is
        // a grid with a clipped last row.
        cellHeight: root.cellHeight
        model: root.themes
        currentIndex: root.selectedIndex
        boundsBehavior: Flickable.StopAtBounds

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
                    color: "#8a8a8a"
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
