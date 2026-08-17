import QtQuick
import Quickshell

import "../common"
import "../common/Clipboard.js" as Clipboard
import "../common/Metrics.js" as Metrics
// FORK: the shared motion system — see qml/common/Motion.js.
import "../common/Motion.js" as Motion

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
    // The drag this shelf may have been opened to receive has landed, so a
    // keyboard grab is safe now. See DynamicIslandWindow's islandKeyboardFocus.
    signal dropLanded
    // A drag has ARRIVED over the panel. The host uses it to hold off the
    // keyboard grab: the grab cancels an in-flight drag, and a timer alone
    // cannot know how long you will take to get here.
    signal dragHovering

    property bool showCondition: false
    property string textFontFamily: ""
    property string iconFontFamily: ""
    property color panelFill: IslandTheme.surface
    property color accentColor: IslandTheme.accent
    property bool drawBackground: false

    property string status: ""

    // ---- A DROP THAT LANDED BEFORE THIS PANEL EXISTED --------------------
    //
    // The notch is a drop target now (see `notchDropArea` in
    // DynamicIslandWindow.qml): carrying a file to the top edge opens this
    // shelf, and letting go ON the notch is the fast version of the same
    // gesture — you never wait for the panel at all.
    //
    // But the panel is what owns a store, and at the moment of that drop it
    // does not exist: `PanelLoader` builds it from `live`, which is the
    // state change the drop itself causes. So the host takes the URIs off
    // the drag, holds them, and hands them over here on the way up.
    //
    // Consumed and CLEARED through a signal rather than by writing back to
    // the property, because the host owns it: a Loader's item assigning to
    // its own binding's source is how you get a value that reappears on the
    // next open. `Component.onCompleted` for the same reason the focus
    // grab below uses it — `live` and `showCondition` come from one
    // expression, so onShowConditionChanged never fires for the opening.
    property var pendingUrls: []
    property string pendingText: ""
    signal pendingConsumed()

    function drainPending() {
        const list = root.pendingUrls || [];
        const text = String(root.pendingText || "");
        if (list.length === 0 && text === "")
            return;
        let n = 0;
        for (let i = 0; i < list.length; i++)
            if (store.addUrl(list[i]))
                n++;
        if (list.length === 0 && text !== "" && store.addText(text))
            n++;
        root.pendingConsumed();
        if (n > 0) {
            root.status = n + (n === 1 ? " item added" : " items added");
            statusClear.restart();
        }
    }

    // Its own store, like QdropShelf's, rather than one handed down. The two
    // hosts are never up together — which one you get is which BAR you are on
    // — and a PanelLoader that is not live has no store at all, so an island
    // that has never opened the shelf never reads the file.
    QdropStore { id: store }

    // ---- FIXED, AND IDENTICAL TO THE GTK SHELF ----
    //
    // "the islend popup should hacve a fixed hight as and width which will be
    // as same as the qdrop idnetcal and not exceed it ok eveything will fit
    // inisde perfectly and will has scroll bar".
    //
    // qdrop.py's window is 624x331. That is the number, not an approximation
    // of it — the muscle memory being served is a shelf of exactly that size
    // in exactly that place, and a panel that is nearly the same size is just
    // a different size.
    //
    // Content-sized was WRONG here and this replaces it. A shelf grows every
    // time you drop something, so content-sizing means the capsule changes
    // shape whenever you use it, and a panel whose height depends on how much
    // is in it is the exact re-aim NEXT-SESSION.md keeps warning about. Fixed
    // shape, scrolling content: the grid takes what is left after the chrome
    // and the search strip, and IslandScrollBar covers the overflow.
    readonly property real fixedWidth: Metrics.px(624)
    readonly property real preferredHeight: Metrics.px(331)

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
        statusClause: grid.visual ? "· VISUAL"
            : (grid.selectedCount > 0 ? "· " + grid.selectedCount + " selected" : "")
        statusClauseLive: grid.visual || grid.selectedCount > 0

        status: root.status !== "" ? root.status
            : (store.count > 0
               ? store.count + (store.count === 1 ? " item" : " items")
               : "empty")
        statusLevel: root.status !== "" ? "ok" : "idle"

        hints: [
            { key: "hjkl", label: "move" },
            { key: "v", label: "visual" },
            { key: "space", label: "pick" },
            { key: "y", label: "copy" },
            // CTRL on both, because they are the two commands here that
            // cannot be taken back. See the note in QdropGrid's key map.
            { key: "^z", label: "zip" },
            { key: "^d", label: "del" },
            { key: "s", label: "sort" },
            { key: "/", label: "search" },
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
        textFontFamily: root.textFontFamily
        iconFontFamily: root.iconFontFamily

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
        onCloseRequested: root.closeRequested()
        onFocusWanted: root.forceActiveFocus()
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

        onEntered: (d) => root.dragHovering()

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
            root.dropLanded();
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
            Quickshell.execDetached(Clipboard.argv(String(e.value)));
        else
            Quickshell.execDetached(["xdg-open", String(e.value)]);
    }

    // ---- FOCUS, WHICH THIS PANEL DID NOT HAVE ----
    //
    // Reported as four separate bugs — "the esc not working or q", hjkl doing
    // nothing, shift-select doing nothing — and they were all ONE bug: the
    // panel never took the keyboard, so not a single key reached it.
    //
    // Three lines short of the pattern every other island panel uses, and
    // SystemMonitorPanel.qml's header already explains each of them:
    //
    //   anchors.fill      a FocusScope with no geometry is not in the chain
    //   activeFocusOnTab  what puts it IN the chain
    //   forceActiveFocus  from Component.onCompleted, and THIS is the one
    //                     that matters here: PanelLoader creates the
    //                     component only once `live` is true, and `live` and
    //                     `showCondition` are bound to the SAME expression —
    //                     so showCondition is already true when the panel is
    //                     built and onShowConditionChanged NEVER FIRES for
    //                     the opening.
    //
    // The handler is kept too, for a re-show into an already-live loader.
    anchors.fill: parent
    focus: root.showCondition
    activeFocusOnTab: true

    // ---- THE CONTENT WAITS FOR THE SHAPE ----
    //
    // This panel had NO opacity choreography at all — the one layer in the
    // shell without it, while CalculatorLayer, SystemMonitorPanel and
    // AudioPanel all carry `Motion.contentDelay()`. So the shelf's content
    // was mapped at full opacity in the same turn the state changed, while
    // the capsule was still 32 px tall and morphing.
    //
    // Recorded at 60 fps across three open/close cycles, and the frames say
    // it plainly: at the open, the tiles, the search field and the whole
    // keycap bar are drawn INSIDE THE NOTCH — a wide, ~30 px strip of
    // illegible squashed text — for several frames before the capsule
    // catches up. That is what "not smooth" looks like here, and it is the
    // "three animations, three owners, no coordinator" problem this tree's
    // notes describe, in the one place where the coordinator was simply
    // missing.
    //
    // The pause is the whole fix: the capsule gets a head start, and the
    // content fades in once there is a shape to put it in.
    opacity: root.showCondition ? 1 : 0

    Behavior on opacity {
        SequentialAnimation {
            PauseAnimation {
                duration: root.showCondition ? Motion.contentDelay() : 0
            }
            NumberAnimation {
                duration: root.showCondition
                    ? Motion.fadeInDuration() : Motion.fadeOutDuration()
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Motion.fade()
            }
        }
    }

    Component.onCompleted: {
        root.drainPending();
        if (root.showCondition)
            root.forceActiveFocus();
    }
    onShowConditionChanged: {
        if (root.showCondition) {
            root.drainPending();
            root.forceActiveFocus();
        }
    }

    // ---- AND ON THE VALUE ITSELF, WHICH IS THE CASE THAT ACTUALLY HAPPENS -
    //
    // Draining only from the two handlers above looks sufficient and is not.
    // Driven with a real Wayland drag from scripts/test/dnd-peer.py to the
    // notch: the shelf OPENED (the 180 ms dwell fired) and the file was
    // never stored — `entries 0`.
    //
    // The dwell is why. It reveals the shelf ~400 ms before you let go, so
    // by the time the drop lands `showCondition` has ALREADY been true for
    // a while and the panel has ALREADY completed. Qt still delivers that
    // drop to `notchDropArea`, because an item holding a drag keeps it for
    // the drop even once `enabled` goes false underneath it — so the host
    // sets `qdropPendingUrls` into a panel where neither handler above can
    // ever fire again, and the file is stranded in a property nobody reads.
    //
    // This is the same shape as the trap the focus grab above documents —
    // a handler that cannot fire because the thing it watches was already
    // true — and the answer is the same: watch the value that changed.
    // Draining is idempotent (it clears through `pendingConsumed`, and an
    // empty list returns immediately), so all three paths can be live at
    // once without one undoing another.
    onPendingUrlsChanged: root.drainPending()
    onPendingTextChanged: root.drainPending()

    // Escape AND q, which is the convention on every panel in this shell —
    // AudioPanel, DisplayPanel and SystemMonitorPanel all take both, and this
    // one took neither. Everything else belongs to the grid.
    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Escape
                || (event.key === Qt.Key_Q && event.modifiers === Qt.NoModifier)) {
            root.closeRequested();
            event.accepted = true;
            return;
        }
        event.accepted = grid.handleKey(event.key, event.modifiers);
    }
}
