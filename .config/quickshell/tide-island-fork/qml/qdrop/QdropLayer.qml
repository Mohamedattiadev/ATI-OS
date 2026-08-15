import QtQuick
import Quickshell

import "../common"
import "../common/Metrics.js" as Metrics

//
// ============================================================
//  The drop shelf AS AN ISLAND STATE — it comes out of the capsule
// ============================================================
//
// "the shelf drop should be like the other islend popup coming form the
// islned it self".
//
// The standalone popup (QdropShelf.qml) is a layer surface of its own that
// appears at the top of the screen. It looks like the island's popups because
// it is a PopupChrome, but it does not COME FROM the island — the capsule
// does not morph into it, and that morph is the whole visual identity of this
// shell. This file is the other host: a 25th island state, so `$alt SHIFT D`
// and the shake grow the shelf out of the notch exactly the way the control
// centre, the wallpaper picker and the system monitor do.
//
// BOTH HOSTS STAY, and which one you get is which BAR you are on:
//
//     bar-mode island   ->  this, an island state, morphed from the capsule
//     bar-mode native   ->  QdropShelf.qml, hosted by popups.qml
//     qtile's own bar   ->  the GTK shelf, via hypr/scripts/qdrop.sh
//
// That is the ask from two messages ago, unchanged: "under the island the
// shelf should be an island popup, in island UI/UX; under the qtile-like
// topbar it should behave exactly as real qtile's does."
//
// ONE BODY, THREE FRAMES. QdropGrid.qml holds every tile, every selection
// rule and every drag, and it is handed a palette rather than deriving one —
// so the island version and the popup version cannot drift, and there is
// still exactly one place where "what does a shelf tile look like" is
// answered. The palette here is the ISLAND's: accent for selection, not
// PopupChrome's green, because inside the capsule the accent is what every
// other panel highlights with.
//
// THE PANEL DOES NOT DRAW ITS OWN BACKGROUND, same as every other island
// panel: the capsule is already painted in exactly that colour, and a second
// rounded fill at a smaller radius shows as four pale corner wedges.
//
FocusScope {
    id: root

    signal closeRequested

    property bool showCondition: false
    property string textFontFamily: ""
    property color panelFill: IslandTheme.surface
    property color accentColor: IslandTheme.accent
    property bool drawBackground: false

    property string status: ""

    // Its own store, like QdropShelf's, rather than one handed down. The two
    // hosts are never up together — which one you get is which BAR you are on
    // — and a PanelLoader that is not live has no store at all, so an island
    // that has never opened the shelf never reads the file.
    QdropStore { id: store }

    // ---- HEIGHT, CONTENT-SIZED LIKE THE REST ----
    //
    // The tile grid is the only variable: one row of tiles is a shelf with a
    // few things on it, four rows is a shelf you have been filling all day.
    // Clamped at both ends — a floor so an EMPTY shelf is still a shelf and
    // not a slot, and a ceiling so it cannot grow past the screen.
    //
    // The rule NEXT-SESSION.md keeps repeating applies here and is why the
    // floor is not zero: a panel that reports a height before its content
    // exists makes the capsule aim twice, and the second aim is the visible
    // glitch. There is no async fetch behind this one — the store is a
    // FileView that is preloaded — but the floor costs nothing and removes
    // the question.
    readonly property real cell: grid.cellSize
    readonly property int perRow: Math.max(1, Math.floor(
        (root.width - Metrics.chromePadX() * 2) / Math.max(1, root.cell)))
    readonly property int rows: Math.max(1, Math.ceil(
        store.count / root.perRow))
    readonly property real preferredHeight:
        Metrics.chromeTotal() + Math.min(root.rows, 4) * root.cell + Metrics.pad(4)

    PanelChrome {
        id: chrome

        textFontFamily: root.textFontFamily
        drawBackground: root.drawBackground
        panelFill: root.panelFill

        title: "shelf"

        // What the panel is DOING, in the slot the audio and connectivity
        // panels use for the same purpose. A copy or a removal says so for a
        // moment; the rest of the time it is the count, because "how much is
        // on the shelf" is the one fact worth carrying in the header.
        statusClause: grid.selectedCount > 0
            ? "· " + grid.selectedCount + " selected" : ""
        statusClauseLive: grid.selectedCount > 0

        status: root.status !== "" ? root.status
            : (store.count > 0
               ? store.count + (store.count === 1 ? " item" : " items")
               : "empty")
        statusLevel: root.status !== "" ? "ok" : "idle"

        hints: [
            { key: "click", label: "select" },
            { key: "ctrl", label: "add" },
            { key: "drag", label: "out" },
            { key: "^c", label: "copy" },
            { key: "d", label: "remove" },
            { key: "q", label: "close" }
        ]
    }

    QdropGrid {
        id: grid

        x: chrome.contentX
        y: chrome.contentY
        width: chrome.contentWidth
        height: chrome.contentHeight

        store: store

        // The ISLAND's palette, not the popup's. Derived the same way
        // PopupChrome derives its three tones so the cards read identically,
        // but highlighting with the island's accent because that is what
        // every other panel in the capsule selects with.
        cFg: IslandTheme.textPrimary
        cMuted: IslandTheme.textMuted
        cSurface: IslandTheme.mix(IslandTheme.background, IslandTheme.foreground, 0.07)
        cSurfaceAlt: IslandTheme.mix(IslandTheme.background, IslandTheme.foreground, 0.14)
        cHighlight: root.accentColor
        cHighlightInk: IslandTheme.background

        onOpenRequested: (i) => root.openEntry(i)
        onStatusChanged: (t) => {
            root.status = t;
            statusClear.restart();
        }
    }

    // ---- DROPPING IN ----
    //
    // Over the tiles and costing them nothing: a DropArea only ever sees
    // DRAGS, so every click, rubber-band and drag-out underneath still works.
    //
    // It covers the WHOLE PANEL and not just the grid, because the thing you
    // are aiming at while carrying a file is the shape on screen, and missing
    // it by the width of the header is not a miss anybody would accept.
    DropArea {
        id: drop

        anchors.fill: parent

        onDropped: (d) => {
            let n = 0;
            if (d.hasUrls) {
                for (let i = 0; i < d.urls.length; i++)
                    if (store.addUrl(d.urls[i]))
                        n++;
            } else if (d.hasText) {
                if (store.addText(d.text))
                    n++;
            }
            if (n > 0) {
                d.accept(Qt.CopyAction);
                root.status = n + (n === 1 ? " item added" : " items added");
                statusClear.restart();
            }
        }
    }

    Rectangle {
        x: chrome.contentX
        y: chrome.contentY
        width: chrome.contentWidth
        height: chrome.contentHeight
        radius: Metrics.px(10)
        color: "transparent"
        border.width: Metrics.px(2)
        border.color: root.accentColor
        opacity: drop.containsDrag ? 1 : 0
        visible: opacity > 0
        Behavior on opacity {
            NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
        }
    }

    Timer {
        id: statusClear
        interval: 2500
        onTriggered: root.status = ""
    }

    function openEntry(i) {
        const e = store.entries[i];
        if (!e)
            return;
        if (String(e.type) === "text")
            Quickshell.execDetached(["sh", "-c",
                "printf '%s' \"$1\" | wl-copy", "sh", String(e.value)]);
        else
            Quickshell.execDetached(["xdg-open", String(e.value)]);
    }

    // `q` closes, which is the island's convention on every panel; everything
    // else belongs to the grid. Escape is the capsule's own and never reaches
    // here.
    focus: root.showCondition
    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Q && event.modifiers === Qt.NoModifier) {
            root.closeRequested();
            event.accepted = true;
            return;
        }
        event.accepted = grid.handleKey(event.key, event.modifiers);
    }
}
