import QtQuick
import Quickshell
import Quickshell.Wayland

import "../common"
import "../popups"

//
// ============================================================
//  qdrop, as an island surface — and the measurement that forced it
// ============================================================
//
// Asked for directly: "the qdrop should be same style with the island … i
// think u can rebuild it with quickshell will be better". It is not only a
// style request, and that is the part worth writing down, because the GTK
// shelf was WORKING and a rewrite of a working thing needs a reason.
//
// THE REASON. Driven with scripts/test/dnd-peer.py and uinput-shake.py, in
// hypr/scripts:
//
//     XWayland source -> the GTK shelf     drop in AND drag out both work
//     Wayland source  -> the GTK shelf     drag begins, NOTHING arrives
//     Wayland source  -> any XWayland win  the drop arrives carrying the X11
//                                          PRIMARY SELECTION instead of the
//                                          URI that was offered
//
// So the compositor's Wayland -> XWayland drag bridge is what is broken, not
// qdrop — and pcmanfm-qt runs QT_QPA_PLATFORM=wayland;xcb, which means THE
// FILE MANAGER YOU WOULD ACTUALLY DRAG FROM IS ON THE WRONG SIDE OF IT. The
// GTK shelf is on XWayland because it POSITIONS ITSELF (`move()` to
// top-centre, and its slide-down reveal is more `move()`), which Wayland does
// not permit a client to do at all.
//
// A Quickshell layer surface is on the Wayland side, and it was probed before
// any of this was written rather than after:
//
//     PROBE entered formats=["text/uri-list","text/plain"]
//     PROBE dropped urls=["file:///…/qdrop-test-file.txt"]
//
// The exact case that fails for the GTK shelf. Four defects collapse into
// this one file: the drag bridge leaves the path entirely, the surface gets
// IslandTheme like every other popup, the compositor places it so nothing
// needs XWayland, and hiding stops being "move off-screen" — which is what
// made `windowrule = pin` fatal (Hyprland clamps a pinned window into the
// monitor, so the hidden [371, -331] became [371, 35] and it could never hide
// again).
//
// WHY PopupChrome, AND THE TWO THINGS OVERRIDDEN AT THIS CALL SITE
// ----------------------------------------------------------------
// The whole point is that it looks like the other popups, so it IS one of the
// other popups: same frame, same derived tones, same fade, same keycap bar,
// one palette. Duplicating that derivation is the mistake this tree already
// paid for once — "one duplicated palette made every window border green on
// twenty-two themes, silently".
//
// Two of its decisions are wrong for a shelf, and both are set here because a
// binding in a base component is REPLACED by an assignment at the call site:
//
//   1. ANCHORS. PopupChrome deliberately has none, because an unanchored
//      layer surface is centred and every popup wants that. A shelf is
//      top-centre — that is the shape the muscle memory has — so anchoring
//      the top edge and letting the implicit width centre it horizontally is
//      the whole placement.
//
//   2. KEYBOARD FOCUS. PopupChrome takes WlrKeyboardFocus.Exclusive, which
//      for a shelf would be a bug rather than a preference: YOU ARRIVE HERE
//      MID-DRAG, holding a file that belongs to another application, and a
//      surface that seizes the keyboard the moment it maps takes it away from
//      the window you are dragging out of. OnDemand gives the keyboard when
//      you click the shelf and never before, which is the behaviour the
//      keyboard map below needs and the drag does not.
//
// PopupChrome dismisses on Escape and on nothing else — no focus grab, no
// close-on-focus-loss — which is exactly right here and is the reason this
// works at all. A popup that closed when it lost focus would close the
// instant the drag it exists to receive began.
//
// THE BODY IS NOT IN THIS FILE, and that is the point of the split. There
// are two frames now — this standalone popup, and the island's own panel in
// QdropLayer.qml — around ONE body, QdropGrid.qml. The interaction model the
// user asked for ("same style of file [f] [f] [f]…, how can i select more
// than one, how to copy or drag them out — do all possibility to match the
// qdrop") lives there, once, so the two hosts cannot drift apart.
//
PopupChrome {
    id: shelf

    // Wider than the GTK shelf's 624x331 because the tiles need the room: at
    // 104 px a cell that is six across and three deep, plus the header and
    // the keycap bar this has and that one does not.
    popupWidth: PopupMetrics.s(680)
    popupHeight: PopupMetrics.s(460)

    // By CODEPOINT, like every other popup here, because a private-use
    // character does not survive being read back out of a file. 0xF0BA8 is
    // the tray. It was rendered and LOOKED AT before being chosen — the first
    // literal glyph tried here came out as a pair of scissors.
    titleIcon: String.fromCodePoint(0xF0BA8)
    title: "Drop shelf"
    subtitle: store.count === 0
        ? "drag files here — or shake one while you carry it"
        : "click, ctrl+click or drag a box to select · drag out to move"

    badgeLabel: grid.selectedCount > 0 ? "selected" : "items"
    badgeValue: grid.selectedCount > 0
        ? String(grid.selectedCount) : String(store.count)

    // The bar is the MOUSE answers as well as the keys, because half of what
    // was asked is "how do I do this with the mouse".
    hints: [
        { key: "click", desc: "select" },
        { key: "ctrl", desc: "add" },
        { key: "drag", desc: "out" },
        { key: "^c", desc: "copy" },
        { key: "d", desc: "remove" },
        { key: "Esc", desc: "close" }
    ]

    // The default gap is hintSize*0.6*FIVE, sized for the two- and three-chip
    // bars. The Row is centred, so a bar that overflows is clipped at BOTH
    // ends — the first capture of this lost the `c` of `click`. Same fix and
    // same value the network, volume, display, bluetooth and cheatsheet
    // popups all reached for.
    hintGap: PopupMetrics.hintSize * 0.6

    // ---- the two overrides, and why, above ----
    anchors { top: true }
    margins { top: PopupMetrics.s(8) }
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    signal requestClose()

    property string status: ""

    QdropStore { id: store }

    onKeyPressed: (key, mods, text) => grid.handleKey(key, mods)

    Item {
        anchors.fill: parent

        QdropGrid {
            id: grid

            anchors.fill: parent
            store: store

            cFg: shelf.cFg
            cMuted: shelf.cMuted
            cSurface: shelf.cSurface
            cSurfaceAlt: shelf.cSurfaceAlt
            cHighlight: shelf.cHighlight
            cHighlightInk: shelf.cHighlightInk

            onOpenRequested: (i) => shelf.openEntry(i)
            onStatusChanged: (t) => {
                shelf.status = t;
                statusClear.restart();
            }
        }

        // ---- DROPPING IN ----
        //
        // Last child so it is over the tiles, and it costs them nothing: a
        // DropArea only ever sees DRAGS, so every click, rubber-band and
        // drag-out underneath still works.
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
                    shelf.status = n + (n === 1 ? " item added" : " items added");
                    statusClear.restart();
                }
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: PopupMetrics.s(10)
            color: "transparent"
            border.width: PopupMetrics.s(2)
            border.color: shelf.cHighlight
            opacity: drop.containsDrag ? 1 : 0
            visible: opacity > 0
            Behavior on opacity {
                NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
            }
        }
    }

    Timer {
        id: statusClear
        interval: 2500
        onTriggered: shelf.status = ""
    }

    function openEntry(i) {
        const e = store.entries[i];
        if (!e)
            return;
        // A text entry has nothing to open, so it is copied instead — which
        // is what the GTK shelf's Enter does with one.
        if (String(e.type) === "text")
            Quickshell.execDetached(["sh", "-c",
                "printf '%s' \"$1\" | wl-copy", "sh", String(e.value)]);
        else
            Quickshell.execDetached(["xdg-open", String(e.value)]);
    }

    // ---- THE FOOTER ----
    //
    // PopupChrome DRAWS the footer card whether or not you fill it, so an
    // empty footer is an empty grey box — which is what the first capture of
    // this showed. It carries the thing the tiles cannot: their labels are
    // elided to a filename, and a shelf full of `screenshot.png` is a shelf
    // you cannot use. A status line takes it over for a moment when something
    // happens, because a copy that gives no feedback looks like a copy that
    // did not happen.
    footer: Item {
        anchors.fill: parent

        Column {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: PopupMetrics.s(12)
            anchors.rightMargin: PopupMetrics.s(12)
            spacing: PopupMetrics.s(2)

            Text {
                width: parent.width
                text: shelf.status !== "" ? shelf.status
                    : (store.count === 0 ? "drop files, folders, images or text"
                       : store.label(store.entries[grid.view[
                           Math.min(grid.focusIdx, Math.max(0, grid.count - 1))]]))
                color: shelf.status !== "" ? shelf.cHighlight : shelf.cFg
                elide: Text.ElideMiddle
                font.family: PopupMetrics.font
                font.pixelSize: PopupMetrics.rowSize
                font.bold: true
                renderType: Text.NativeRendering
            }
            Text {
                width: parent.width
                text: store.count === 0
                    ? "shake a file while you drag it and this opens by itself"
                    : String((store.entries[grid.view[
                        Math.min(grid.focusIdx, Math.max(0, grid.count - 1))]]
                        || {}).value || "")
                color: shelf.cMuted
                elide: Text.ElideMiddle
                font.family: PopupMetrics.font
                font.pixelSize: PopupMetrics.hintSize
                renderType: Text.NativeRendering
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            anchors.rightMargin: PopupMetrics.s(12)
            text: grid.sortMode
            color: shelf.cMuted
            font.family: PopupMetrics.font
            font.pixelSize: PopupMetrics.hintSize
            renderType: Text.NativeRendering
        }
    }

    onDismissed: shelf.requestClose()
}
