import QtQuick
import Quickshell

import "../common"
import "../popups"

//
// ============================================================
//  The shelf's BODY — tiles, not rows
// ============================================================
//
// "u should mak the same stile of file [f] [f] [f]... file near files etc,
// and how can i selecte more than one and how to put inside and how to copy
// or drag them with the mouse out — do all possiblity to match the qdrop".
//
// The first version of this was a vertical LIST, and a list is the wrong
// shape for the thing: a shelf is something you sweep files onto and pick
// them off again, and what you recognise them by is a THUMBNAIL, not a
// filename in a column. qdrop.py has always drawn tiles. So does the macOS
// shelf it names as its model.
//
// Split out of QdropShelf.qml rather than nested in it because there are two
// hosts now — the standalone popup and the island's own panel — and they
// differ only in the frame around this. One body, two frames; the
// alternative is the duplicated-palette mistake in a new place.
//
// WHAT "ALL POSSIBILITY" TURNED OUT TO MEAN, all of it from qdrop.py's own
// header and its context menu:
//
//     click            select one
//     ctrl+click       add/remove one          <- "more than one"
//     shift+click      select the range
//     drag on empty    rubber-band a region    <- "more than one", by mouse
//     ctrl+A           all
//     ctrl+shift+A     none
//     space            toggle the focused tile
//     double-click     open
//     enter            open the focused tile
//     drag a tile      drag EVERY selected item out, as one uri-list
//     ctrl+C           copy the selection to the clipboard
//     right-click      open / copy / copy path / reveal / pin / remove
//     delete, d        remove the selection
//     p                pin, and pinned tiles sort first
//     s                cycle date -> name -> type
//     j k h l, arrows  move the focus
//
Item {
    id: body

    // The palette and metrics come from the frame, so the two hosts stay one
    // palette. See the note above.
    property color cFg: "white"
    property color cMuted: "grey"
    property color cSurface: "#222"
    property color cSurfaceAlt: "#333"
    property color cHighlight: "#8ec07c"
    property color cHighlightInk: "black"

    property QdropStore store

    // ---- selection, keyed by the entry's index in store.entries ----
    //
    // NOT by its position in the grid: `view` re-sorts, and a selection that
    // survives a sort is the only kind worth having.
    property var selected: ({})
    property int focusIdx: 0          // index into `view`
    property int anchorIdx: 0         // where a shift+click range starts
    property string sortMode: "date"

    signal openRequested(int entryIndex)
    signal statusChanged(string text)

    readonly property var view: {
        const e = store ? store.entries : [];
        const idx = [];
        for (let i = 0; i < e.length; i++)
            idx.push(i);
        const mode = body.sortMode;
        idx.sort(function (a, b) {
            const pa = (e[a] && e[a].pinned) ? 0 : 1;
            const pb = (e[b] && e[b].pinned) ? 0 : 1;
            if (pa !== pb)
                return pa - pb;          // pinned first, always
            if (mode === "name")
                return String(body.store.label(e[a]))
                    .localeCompare(String(body.store.label(e[b])));
            if (mode === "type") {
                const ta = body.store.badge(e[a]);
                const tb = body.store.badge(e[b]);
                if (ta !== tb)
                    return ta < tb ? -1 : 1;
            }
            return (e[b] ? e[b].added_ts || 0 : 0) - (e[a] ? e[a].added_ts || 0 : 0);
        });
        return idx;
    }

    readonly property int count: view.length
    readonly property int selectedCount: {
        let n = 0;
        for (const k in body.selected)
            if (body.selected[k])
                n++;
        return n;
    }

    // The entry indexes to act on: the selection, or the focused tile when
    // nothing is selected. Every command goes through this, so "no selection"
    // never means "do nothing to nothing".
    function targets() {
        const out = [];
        for (const k in body.selected)
            if (body.selected[k])
                out.push(parseInt(k));
        if (out.length === 0 && body.count > 0)
            out.push(body.view[Math.min(body.focusIdx, body.count - 1)]);
        out.sort(function (a, b) { return a - b; });
        return out;
    }

    function setSelection(map) {
        body.selected = map;
    }

    function selectOnly(entryIdx) {
        const s = {};
        s[entryIdx] = true;
        body.selected = s;
    }

    function toggleOne(entryIdx) {
        const s = {};
        for (const k in body.selected)
            s[k] = body.selected[k];
        s[entryIdx] = !s[entryIdx];
        body.selected = s;
    }

    function selectRange(fromViewIdx, toViewIdx) {
        const a = Math.min(fromViewIdx, toViewIdx);
        const b = Math.max(fromViewIdx, toViewIdx);
        const s = {};
        for (let i = a; i <= b && i < body.count; i++)
            s[body.view[i]] = true;
        body.selected = s;
    }

    function selectAll() {
        const s = {};
        for (let i = 0; i < body.count; i++)
            s[body.view[i]] = true;
        body.selected = s;
    }

    function selectNone() {
        body.selected = ({});
    }

    // ---- the uri-list every drag and every copy is built from ----
    //
    // One entry per line, CRLF, which is what the spec says and what every
    // toolkit splits on. A text entry has no URI, so a selection that mixes
    // the two offers text/plain as well and lets the receiver choose.
    function uriList(indexes) {
        const e = store.entries;
        const out = [];
        for (let i = 0; i < indexes.length; i++) {
            const it = e[indexes[i]];
            if (!it)
                continue;
            const t = String(it.type);
            if (t === "file")
                out.push("file://" + encodeURI(String(it.value)));
            else if (t === "url")
                out.push(String(it.value));
        }
        return out.join("\r\n");
    }

    function plainText(indexes) {
        const e = store.entries;
        const out = [];
        for (let i = 0; i < indexes.length; i++)
            if (e[indexes[i]])
                out.push(String(e[indexes[i]].value));
        return out.join("\n");
    }

    function mimeFor(indexes) {
        const uris = body.uriList(indexes);
        const text = body.plainText(indexes);
        const m = {};
        if (uris !== "")
            m["text/uri-list"] = uris;
        m["text/plain"] = text;
        return m;
    }

    function copySelection() {
        const idx = body.targets();
        if (idx.length === 0)
            return;
        const uris = body.uriList(idx);
        // wl-copy rather than a clipboard API: copyq is this desktop's
        // clipboard manager and it watches the Wayland selection, so a copy
        // that goes through wl-copy lands in the history like every other.
        // The uri-list form is what a file manager pastes as FILES; without
        // it a paste into pcmanfm-qt is the path as text.
        if (uris !== "")
            Quickshell.execDetached(["sh", "-c",
                "printf '%s' \"$1\" | wl-copy --type text/uri-list", "sh", uris]);
        else
            Quickshell.execDetached(["sh", "-c",
                "printf '%s' \"$1\" | wl-copy", "sh", body.plainText(idx)]);
        body.statusChanged(idx.length + (idx.length === 1 ? " item" : " items")
                           + " copied");
    }

    function openTargets() {
        const idx = body.targets();
        for (let i = 0; i < idx.length; i++)
            body.openRequested(idx[i]);
    }

    function removeTargets() {
        const idx = body.targets();
        if (idx.length === 0)
            return;
        store.removeAt(idx);
        body.selectNone();
        body.focusIdx = Math.max(0, Math.min(body.focusIdx, body.count - 1));
        body.statusChanged(idx.length + " removed");
    }

    function pinTargets() {
        const idx = body.targets();
        if (idx.length === 0)
            return;
        store.togglePin(idx);
        body.statusChanged("pin toggled");
    }

    function cycleSort() {
        body.sortMode = body.sortMode === "date" ? "name"
            : (body.sortMode === "name" ? "type" : "date");
        body.statusChanged("sorted by " + body.sortMode);
    }

    function moveFocus(delta) {
        if (body.count === 0)
            return;
        body.focusIdx = Math.max(0, Math.min(body.count - 1, body.focusIdx + delta));
        grid.positionViewAtIndex(body.focusIdx, GridView.Contain);
    }

    // Returns true when the key was ours, so the frame can leave Escape alone.
    function handleKey(key, mods) {
        const ctrl = (mods & Qt.ControlModifier) !== 0;
        const shift = (mods & Qt.ShiftModifier) !== 0;
        const perRow = Math.max(1, Math.floor(grid.width / grid.cellWidth));

        if (key === Qt.Key_L || key === Qt.Key_Right) { body.moveFocus(1); return true; }
        if (key === Qt.Key_H || key === Qt.Key_Left)  { body.moveFocus(-1); return true; }
        if (key === Qt.Key_J || key === Qt.Key_Down)  { body.moveFocus(perRow); return true; }
        if (key === Qt.Key_K || key === Qt.Key_Up)    { body.moveFocus(-perRow); return true; }
        if (key === Qt.Key_Return || key === Qt.Key_Enter) { body.openTargets(); return true; }
        if (key === Qt.Key_Delete || key === Qt.Key_D) { body.removeTargets(); return true; }
        if (key === Qt.Key_A) {
            if (ctrl && shift)
                body.selectNone();
            else
                body.selectAll();
            return true;
        }
        if (key === Qt.Key_C) {
            if (ctrl)
                body.copySelection();
            else {
                store.clear();
                body.selectNone();
                body.statusChanged("shelf cleared");
            }
            return true;
        }
        if (key === Qt.Key_P) { body.pinTargets(); return true; }
        if (key === Qt.Key_S) { body.cycleSort(); return true; }
        if (key === Qt.Key_Space) {
            if (body.count > 0)
                body.toggleOne(body.view[body.focusIdx]);
            return true;
        }
        return false;
    }

    // ---- THE TILES ----
    GridView {
        id: grid

        anchors.fill: parent
        clip: true
        cellWidth: PopupMetrics.s(104)
        cellHeight: PopupMetrics.s(104)
        model: body.view
        boundsBehavior: Flickable.StopAtBounds
        currentIndex: body.focusIdx

        delegate: Item {
            id: tile

            required property var modelData     // index into store.entries
            required property int index         // position in `view`

            readonly property var entry: body.store.entries[tile.modelData]
            readonly property bool isSelected: !!body.selected[tile.modelData]
            readonly property bool isFocused: index === body.focusIdx

            width: grid.cellWidth
            height: grid.cellHeight

            Rectangle {
                anchors.fill: parent
                anchors.margins: PopupMetrics.s(4)
                radius: PopupMetrics.s(10)
                color: tile.isSelected ? body.cHighlight : body.cSurface
                border.width: tile.isFocused ? PopupMetrics.s(2) : 0
                border.color: body.cHighlight

                Column {
                    anchors.centerIn: parent
                    width: parent.width - PopupMetrics.s(10)
                    spacing: PopupMetrics.s(4)

                    // The thumbnail IS the identity of an image entry. For
                    // everything else the type glyph is, which is why the
                    // badge is large here and small in the old row form.
                    Item {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: PopupMetrics.s(46)
                        height: PopupMetrics.s(46)

                        Image {
                            anchors.fill: parent
                            visible: body.store.isImage(tile.entry)
                            fillMode: Image.PreserveAspectCrop
                            clip: true
                            asynchronous: true
                            cache: true
                            sourceSize.width: PopupMetrics.s(46) * 2
                            sourceSize.height: PopupMetrics.s(46) * 2
                            source: body.store.isImage(tile.entry)
                                ? "file://" + encodeURI(String(tile.entry.value)) : ""
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: !body.store.isImage(tile.entry)
                            text: body.store.glyph(tile.entry)
                            color: tile.isSelected ? body.cHighlightInk : IslandTheme.info
                            font.family: PopupMetrics.font
                            font.pixelSize: Math.round(PopupMetrics.headSize * 2.0)
                            renderType: Text.NativeRendering
                        }
                    }

                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: body.store.label(tile.entry)
                        color: tile.isSelected ? body.cHighlightInk : body.cFg
                        elide: Text.ElideMiddle
                        maximumLineCount: 2
                        wrapMode: Text.WrapAnywhere
                        font.family: PopupMetrics.font
                        font.pixelSize: PopupMetrics.hintSize
                        renderType: Text.NativeRendering
                    }
                }

                // The pin, drawn in the corner rather than as a row, because
                // it is a property of the tile and not a line of its text.
                Text {
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.margins: PopupMetrics.s(4)
                    visible: tile.entry && tile.entry.pinned
                    text: String.fromCodePoint(0xF0403)
                    color: tile.isSelected ? body.cHighlightInk : body.cHighlight
                    font.family: PopupMetrics.font
                    font.pixelSize: PopupMetrics.hintSize
                    renderType: Text.NativeRendering
                }

                // The type badge — qdrop.py's entry_badge(), for the cases a
                // glyph cannot disambiguate (TXT vs DOC are one glyph).
                //
                // TOP-left, not bottom-left, which is where it was first put:
                // the label wraps to two lines and a two-line label reaches
                // the bottom of the tile, so the badge and the filename drew
                // on top of each other. Measured on the URL and text tiles,
                // where `URL` sat across `ude.com/`.
                Text {
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.margins: PopupMetrics.s(5)
                    text: body.store.badge(tile.entry)
                    color: tile.isSelected ? body.cHighlightInk : body.cMuted
                    font.family: PopupMetrics.font
                    font.pixelSize: Math.round(PopupMetrics.hintSize * 0.8)
                    renderType: Text.NativeRendering
                }
            }

            // ---- DRAGGING OUT ----
            //
            // The mime is built from the SELECTION, not from the tile, so
            // dragging one of five selected files carries all five. Pressing
            // an UNSELECTED tile selects it first, which is what every file
            // manager does and what makes "drag the one I pressed" still true.
            //
            // No `Drag.active: false` here: writing it declares a BINDING that
            // holds the property at false, and startDrag() is the call that
            // has to set it. Measured, the engine says so —
            // `WARN scene: startDrag() drag must be active` — and the
            // receiving window sees nothing at all.
            Drag.dragType: Drag.Automatic
            Drag.supportedActions: Qt.CopyAction
            Drag.mimeData: body.mimeFor(body.targets())

            MouseArea {
                id: tileMouse

                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                property real px: 0
                property real py: 0
                property bool dragging: false

                onPressed: (m) => {
                    tileMouse.px = m.x;
                    tileMouse.py = m.y;
                    tileMouse.dragging = false;
                    body.focusIdx = tile.index;
                    if (m.button === Qt.RightButton) {
                        if (!tile.isSelected)
                            body.selectOnly(tile.modelData);
                        menu.openAt(tile.mapToItem(body, m.x, m.y));
                        return;
                    }
                    if (m.modifiers & Qt.ControlModifier) {
                        body.toggleOne(tile.modelData);
                    } else if (m.modifiers & Qt.ShiftModifier) {
                        body.selectRange(body.anchorIdx, tile.index);
                    } else {
                        if (!tile.isSelected)
                            body.selectOnly(tile.modelData);
                        body.anchorIdx = tile.index;
                    }
                }

                onPositionChanged: (m) => {
                    if (tileMouse.dragging || !tileMouse.pressed)
                        return;
                    if (Math.abs(m.x - tileMouse.px) + Math.abs(m.y - tileMouse.py) < 10)
                        return;
                    tileMouse.dragging = true;
                    tile.Drag.active = true;
                    tile.Drag.startDrag();
                    tile.Drag.active = false;
                }

                onDoubleClicked: body.openTargets()
            }
        }
    }

    // ---- RUBBER BAND ----
    //
    // "how can i selecte more than one" has a keyboard answer and a MOUSE
    // answer, and this is the mouse one. Below the tiles in z order and
    // accepting only presses that miss a tile, so it can never start on top
    // of something that wanted to be dragged.
    MouseArea {
        id: bandArea

        anchors.fill: parent
        z: -1
        acceptedButtons: Qt.LeftButton
        property real ox: 0
        property real oy: 0
        property bool active: false

        onPressed: (m) => {
            bandArea.ox = m.x;
            bandArea.oy = m.y;
            bandArea.active = true;
            if (!(m.modifiers & (Qt.ControlModifier | Qt.ShiftModifier)))
                body.selectNone();
        }
        onPositionChanged: (m) => {
            if (!bandArea.active)
                return;
            band.x = Math.min(bandArea.ox, m.x);
            band.y = Math.min(bandArea.oy, m.y);
            band.width = Math.abs(m.x - bandArea.ox);
            band.height = Math.abs(m.y - bandArea.oy);
            body.selectWithin(band.x, band.y, band.width, band.height);
        }
        onReleased: {
            bandArea.active = false;
            band.width = 0;
            band.height = 0;
        }
    }

    function selectWithin(x, y, w, h) {
        const s = {};
        for (let i = 0; i < body.count; i++) {
            const item = grid.itemAtIndex(i);
            if (!item)
                continue;
            const ix = item.x - grid.contentX;
            const iy = item.y - grid.contentY;
            if (ix + item.width >= x && ix <= x + w
                    && iy + item.height >= y && iy <= y + h)
                s[body.view[i]] = true;
        }
        body.selected = s;
    }

    Rectangle {
        id: band
        visible: width > 2 && height > 2
        color: IslandTheme.alpha(body.cHighlight, 0.18)
        border.width: 1
        border.color: body.cHighlight
        radius: PopupMetrics.s(3)
        z: 5
    }

    // ---- EMPTY STATE ----
    Column {
        anchors.centerIn: parent
        spacing: PopupMetrics.s(6)
        visible: body.count === 0

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: String.fromCodePoint(0xF01DA)
            color: body.cMuted
            font.family: PopupMetrics.font
            font.pixelSize: Math.round(PopupMetrics.headSize * 2.2)
            renderType: Text.NativeRendering
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "drag files here"
            color: body.cMuted
            font.family: PopupMetrics.font
            font.pixelSize: PopupMetrics.rowSize
            renderType: Text.NativeRendering
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "or shake one while you carry it"
            color: body.cMuted
            font.family: PopupMetrics.font
            font.pixelSize: PopupMetrics.hintSize
            renderType: Text.NativeRendering
        }
    }

    // ---- THE CONTEXT MENU ----
    //
    // qdrop.py's right-click menu, same entries. Drawn here rather than as a
    // Quickshell popup window because a second layer surface would need its
    // own keyboard story, and this one is dismissed by clicking anywhere.
    Rectangle {
        id: menu

        property var actions: []

        function openAt(pt) {
            menu.x = Math.min(pt.x, body.width - menu.width - PopupMetrics.s(4));
            menu.y = Math.min(pt.y, body.height - menu.height - PopupMetrics.s(4));
            menu.visible = true;
        }

        visible: false
        z: 20
        width: PopupMetrics.s(180)
        height: menuCol.implicitHeight + PopupMetrics.s(10)
        radius: PopupMetrics.s(8)
        color: body.cSurfaceAlt
        border.width: 1
        border.color: body.cHighlight

        Column {
            id: menuCol
            anchors.centerIn: parent
            width: parent.width - PopupMetrics.s(10)

            Repeater {
                model: [
                    { label: "Open",         act: "open" },
                    { label: "Copy",         act: "copy" },
                    { label: "Copy path",    act: "path" },
                    { label: "Reveal",       act: "reveal" },
                    { label: "Pin / unpin",  act: "pin" },
                    { label: "Remove",       act: "remove" }
                ]

                Rectangle {
                    required property var modelData

                    width: menuCol.width
                    height: PopupMetrics.s(26)
                    radius: PopupMetrics.s(5)
                    color: ma.containsMouse ? body.cHighlight : "transparent"

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: PopupMetrics.s(8)
                        text: modelData.label
                        color: ma.containsMouse ? body.cHighlightInk : body.cFg
                        font.family: PopupMetrics.font
                        font.pixelSize: PopupMetrics.hintSize
                        renderType: Text.NativeRendering
                    }

                    MouseArea {
                        id: ma
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            menu.visible = false;
                            body.runAction(modelData.act);
                        }
                    }
                }
            }
        }
    }

    // Anywhere outside the menu closes it. Above the tiles only while the
    // menu is up, so it costs nothing the rest of the time.
    MouseArea {
        anchors.fill: parent
        z: 19
        visible: menu.visible
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onPressed: menu.visible = false
    }

    function runAction(act) {
        const idx = body.targets();
        if (idx.length === 0)
            return;
        if (act === "open") {
            body.openTargets();
        } else if (act === "copy") {
            body.copySelection();
        } else if (act === "path") {
            Quickshell.execDetached(["sh", "-c",
                "printf '%s' \"$1\" | wl-copy", "sh", body.plainText(idx)]);
            body.statusChanged("path copied");
        } else if (act === "reveal") {
            const e = body.store.entries[idx[0]];
            if (e && String(e.type) === "file") {
                const v = String(e.value);
                const slash = v.replace(/\/+$/, "").lastIndexOf("/");
                Quickshell.execDetached(["xdg-open", slash > 0 ? v.substring(0, slash) : v]);
            }
        } else if (act === "pin") {
            body.pinTargets();
        } else if (act === "remove") {
            body.removeTargets();
        }
    }
}
