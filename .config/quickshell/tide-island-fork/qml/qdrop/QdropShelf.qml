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
PopupChrome {
    id: shelf

    // WIDTH/HEIGHT are the GTK shelf's 624x331 plus the chrome it does not
    // have — the header and the keycap bar — on the same argument
    // WifiQrPopup.qml makes for its own numbers.
    popupWidth: PopupMetrics.s(640)
    popupHeight: PopupMetrics.s(430)

    // By CODEPOINT, like every other popup here, because a private-use
    // character does not survive being read back out of a file. 0xF0BA8 is
    // the tray; 0xF01DA below is the arrow-into-a-line. Both were rendered
    // and LOOKED AT before being chosen — the first literal glyph tried here
    // came out as a pair of scissors.
    titleIcon: String.fromCodePoint(0xF0BA8)
    title: "Drop shelf"
    subtitle: store.count === 0
        ? "drag files here — or shake one while you carry it"
        : "drag items back out, newest first"

    badgeLabel: "items"
    badgeValue: String(store.count)

    hints: [
        { key: "j/k", desc: "move" },
        { key: "↵", desc: "open" },
        { key: "d", desc: "remove" },
        { key: "a", desc: "all" },
        { key: "c", desc: "clear" },
        { key: "Esc", desc: "close" }
    ]

    // ---- the two overrides, and why, above ----
    anchors { top: true }
    margins { top: PopupMetrics.s(8) }
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    signal requestClose()

    property int current: 0
    property var selected: ({})

    QdropStore { id: store }

    function selectedIndexes() {
        const out = [];
        for (const k in shelf.selected)
            if (shelf.selected[k])
                out.push(parseInt(k));
        if (out.length === 0 && store.count > 0)
            out.push(shelf.current);
        out.sort(function (a, b) { return a - b; });
        return out;
    }

    function clearSelection() {
        shelf.selected = ({});
    }

    function toggleAt(i) {
        const s = {};
        for (const k in shelf.selected)
            s[k] = shelf.selected[k];
        s[i] = !s[i];
        shelf.selected = s;
    }

    function selectAll() {
        const s = {};
        for (let i = 0; i < store.count; i++)
            s[i] = true;
        shelf.selected = s;
    }

    function openAt(i) {
        const e = store.entries[i];
        if (!e)
            return;
        // xdg-open for everything, which is what the GTK shelf's Enter does.
        // A text entry has no target to open, so it is copied instead —
        // wl-copy rather than the clipboard API because copyq is the
        // clipboard manager on this desktop and it watches the selection.
        if (String(e.type) === "text")
            Quickshell.execDetached(["sh", "-c",
                "printf '%s' \"$1\" | wl-copy", "sh", String(e.value)]);
        else
            Quickshell.execDetached(["xdg-open", String(e.value)]);
    }

    function removeSelected() {
        const idx = shelf.selectedIndexes();
        if (idx.length === 0)
            return;
        store.removeAt(idx);
        shelf.clearSelection();
        if (shelf.current >= store.count)
            shelf.current = Math.max(0, store.count - 1);
    }

    onKeyPressed: (key, mods, text) => {
        const ctrl = (mods & Qt.ControlModifier) !== 0;
        if (key === Qt.Key_J || key === Qt.Key_Down) {
            shelf.current = Math.min(store.count - 1, shelf.current + 1);
            list.positionViewAtIndex(shelf.current, ListView.Contain);
        } else if (key === Qt.Key_K || key === Qt.Key_Up) {
            shelf.current = Math.max(0, shelf.current - 1);
            list.positionViewAtIndex(shelf.current, ListView.Contain);
        } else if (key === Qt.Key_Return || key === Qt.Key_Enter) {
            shelf.openAt(shelf.current);
        } else if (key === Qt.Key_D || key === Qt.Key_Delete) {
            shelf.removeSelected();
        } else if (key === Qt.Key_A) {
            if (ctrl && (mods & Qt.ShiftModifier))
                shelf.clearSelection();
            else
                shelf.selectAll();
        } else if (key === Qt.Key_C) {
            store.clear();
            shelf.clearSelection();
        } else if (key === Qt.Key_Space) {
            shelf.toggleAt(shelf.current);
        }
    }

    // ---- THE BODY ----
    Item {
        anchors.fill: parent

        ListView {
            id: list

            anchors.fill: parent
            clip: true
            spacing: PopupMetrics.s(6)
            model: store.entries
            currentIndex: shelf.current
            boundsBehavior: Flickable.StopAtBounds

            delegate: Rectangle {
                id: row

                required property var modelData
                required property int index

                width: list.width
                height: PopupMetrics.s(52)
                radius: PopupMetrics.s(8)
                color: shelf.selected[index]
                    ? shelf.cHighlight
                    : (index === shelf.current ? shelf.cSurfaceAlt : shelf.cSurface)

                readonly property color ink: shelf.selected[index]
                    ? shelf.cHighlightInk : shelf.cFg
                readonly property color inkMuted: shelf.selected[index]
                    ? shelf.cHighlightInk : shelf.cMuted

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: PopupMetrics.s(10)
                    anchors.rightMargin: PopupMetrics.s(10)
                    spacing: PopupMetrics.s(10)

                    // The type badge, IMG/TXT/DIR/DOC/URL/FILE — qdrop.py's
                    // entry_badge(), same answers, in QdropStore.
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: PopupMetrics.s(46)
                        height: PopupMetrics.s(22)
                        radius: PopupMetrics.s(5)
                        color: shelf.selected[row.index]
                            ? shelf.cHighlightInk : shelf.cSurfaceAlt
                        Text {
                            anchors.centerIn: parent
                            text: store.badge(row.modelData)
                            color: shelf.selected[row.index]
                                ? shelf.cHighlight : IslandTheme.info
                            font.family: PopupMetrics.font
                            font.pixelSize: PopupMetrics.hintSize
                            font.bold: true
                            renderType: Text.NativeRendering
                        }
                    }

                    // A thumbnail for an image, because the GTK shelf has one
                    // and "which screenshot was that" is the whole reason a
                    // shelf beats a list of paths.
                    Image {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: store.isImage(row.modelData)
                        width: visible ? PopupMetrics.s(40) : 0
                        height: PopupMetrics.s(40)
                        fillMode: Image.PreserveAspectCrop
                        clip: true
                        asynchronous: true
                        cache: true
                        sourceSize.height: PopupMetrics.s(40) * 2
                        source: store.isImage(row.modelData)
                            ? "file://" + String(row.modelData.value) : ""
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - PopupMetrics.s(
                            store.isImage(row.modelData) ? 130 : 90)
                        spacing: PopupMetrics.s(1)

                        Text {
                            width: parent.width
                            text: store.label(row.modelData)
                            color: row.ink
                            elide: Text.ElideMiddle
                            font.family: PopupMetrics.font
                            font.pixelSize: PopupMetrics.rowSize
                            font.bold: true
                            renderType: Text.NativeRendering
                        }
                        Text {
                            width: parent.width
                            text: store.subtitle(row.modelData)
                            color: row.inkMuted
                            elide: Text.ElideMiddle
                            font.family: PopupMetrics.font
                            font.pixelSize: PopupMetrics.hintSize
                            renderType: Text.NativeRendering
                        }
                    }
                }

                // ---- DRAGGING BACK OUT ----
                //
                // Drag.Automatic, not Drag.Internal: Internal is QML's own
                // in-scene drag between DropAreas, and what is wanted here is
                // a REAL system drag that another application can receive.
                // Automatic hands the mimeData to the platform, which on
                // Wayland is wl_data_device — the same protocol pcmanfm-qt
                // speaks, which is the entire point of this rewrite.
                //
                // startDrag() is called from the MouseArea below rather than
                // bound to `Drag.active`, because a drag has to begin from a
                // real press-and-move; binding it to a boolean starts a drag
                // nobody asked for.
                // NO `Drag.active: false` here, and that is not an omission.
                // Writing it declares a BINDING that holds the property at
                // false, and startDrag() is exactly the call that needs to
                // set it — so the drag starts, reports nothing, and delivers
                // nothing. Measured: `QDROPDBG startDrag row 0` logged on
                // every attempt while the receiving window saw no drag at
                // all.
                Drag.dragType: Drag.Automatic
                Drag.supportedActions: Qt.CopyAction
                Drag.mimeData: {
                    const e = row.modelData;
                    if (!e)
                        return ({});
                    if (String(e.type) === "text")
                        return { "text/plain": String(e.value) };
                    if (String(e.type) === "url")
                        return {
                            "text/uri-list": String(e.value),
                            "text/plain": String(e.value)
                        };
                    const uri = "file://" + encodeURI(String(e.value));
                    return { "text/uri-list": uri, "text/plain": String(e.value) };
                }

                MouseArea {
                    id: rowMouse

                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton
                    property real pressX: 0
                    property real pressY: 0
                    property bool dragging: false

                    onPressed: (m) => {
                        shelf.current = row.index;
                        rowMouse.pressX = m.x;
                        rowMouse.pressY = m.y;
                        rowMouse.dragging = false;
                        if (m.modifiers & Qt.ControlModifier)
                            shelf.toggleAt(row.index);
                    }
                    onPositionChanged: (m) => {
                        if (rowMouse.dragging || !rowMouse.pressed)
                            return;
                        // Qt's own drag threshold, so a click that wobbles is
                        // still a click.
                        const dx = m.x - rowMouse.pressX;
                        const dy = m.y - rowMouse.pressY;
                        if (Math.abs(dx) + Math.abs(dy) < 10)
                            return;
                        rowMouse.dragging = true;
                        // `active` FIRST, then startDrag(). Not the other way
                        // round and not instead of: the engine says so out
                        // loud, and it is the whole reason the first version
                        // of this delivered nothing --
                        //
                        //     WARN scene: startDrag() drag must be active
                        //
                        // logged on every attempt while the receiving window
                        // saw no drag at all. Assigned imperatively rather
                        // than declared as `Drag.active: false`, because a
                        // declaration is a BINDING and a binding holds the
                        // property at false against the drag that needs it.
                        row.Drag.active = true;
                        row.Drag.startDrag();
                        row.Drag.active = false;
                    }
                    onDoubleClicked: shelf.openAt(row.index)
                }
            }

            // ---- EMPTY STATE ----
            //
            // The shelf is empty most of the time it is looked at, so the
            // empty state is not a footnote: it is where it says what it is
            // for. The GTK one draws a dashed target here too.
            Item {
                anchors.centerIn: parent
                width: parent.width * 0.8
                height: PopupMetrics.s(90)
                visible: store.count === 0

                Column {
                    anchors.centerIn: parent
                    spacing: PopupMetrics.s(6)

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: String.fromCodePoint(0xF01DA)
                        color: shelf.cMuted
                        font.family: PopupMetrics.font
                        font.pixelSize: Math.round(PopupMetrics.headSize * 2.2)
                        renderType: Text.NativeRendering
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "nothing on the shelf"
                        color: shelf.cMuted
                        font.family: PopupMetrics.font
                        font.pixelSize: PopupMetrics.rowSize
                        renderType: Text.NativeRendering
                    }
                }
            }
        }

        // ---- DROPPING IN ----
        //
        // Last child so it is on top of the list, and it does NOT eat the
        // mouse: a DropArea only ever sees drags, so the rows underneath keep
        // their clicks and their drag-out.
        DropArea {
            id: drop

            anchors.fill: parent

            onDropped: (d) => {
                let took = false;
                if (d.hasUrls) {
                    for (let i = 0; i < d.urls.length; i++)
                        took = store.addUrl(d.urls[i]) || took;
                } else if (d.hasText) {
                    took = store.addText(d.text);
                }
                if (took)
                    d.accept(Qt.CopyAction);
            }
        }

        // The whole body glows while a drag is over it. On top of the list so
        // it reads over the rows, and transparent to the mouse so it cannot
        // interfere with the drop it is describing.
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

    // ---- THE FOOTER ----
    //
    // PopupChrome DRAWS the footer card whether or not anything is put in it,
    // so leaving it empty is not "no footer", it is an empty grey box — which
    // is what the first capture of this showed. What belongs in it is the one
    // thing the rows cannot say: their labels are elided to a filename, and a
    // shelf full of `screenshot.png` is a shelf you cannot use. So the footer
    // carries the CURRENT row in full.
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
                text: store.count === 0
                    ? "drop files, folders, images or text"
                    : store.label(store.entries[shelf.current])
                color: shelf.cFg
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
                    : String((store.entries[shelf.current] || {}).value || "")
                color: shelf.cMuted
                elide: Text.ElideMiddle
                font.family: PopupMetrics.font
                font.pixelSize: PopupMetrics.hintSize
                renderType: Text.NativeRendering
            }
        }
    }

    onDismissed: shelf.requestClose()
}
