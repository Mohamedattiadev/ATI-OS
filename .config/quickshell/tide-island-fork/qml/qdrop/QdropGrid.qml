import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io

import "../common"
import "../common/Clipboard.js" as Clipboard
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
//     ctrl+click       add/remove one            <- "more than one"
//     shift+click      the RANGE, from wherever the cursor last settled
//     drag on empty    rubber-band a region      <- the same, by mouse
//     double-click     open
//     drag a tile      drags EVERY selected item, as one uri-list
//     right-click      open / copy / copy path / zip / reveal / pin / remove
//
//     h j k l, arrows  move            SHIFT+motion extends the selection
//     g / G            first / last
//     a / A            select all / none
//     space            toggle the focused tile
//     enter            open
//     y  or  ctrl+c    copy (yank)
//     ctrl+d, Delete   remove          C  clear the shelf
//     p                pin, and pinned tiles sort first
//     s                sort: date -> name -> type
//     ctrl+z           zip the selection back onto the shelf
//     /                search;  Esc or Enter leaves it
//     Esc / q          close
//
// IT IS MODAL, and that is the only way to have both halves of what was
// asked: plain hjkl AND a search box. A focused text field turns every
// letter into text, so the two cannot coexist in one mode — which is the
// problem vi solved. The field is `readOnly` until `/`, and PanelSearchField
// documents readOnly as the thing that "keeps focus and inserts nothing".
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

    property string textFontFamily: ""
    property string iconFontFamily: ""

    property QdropStore store

    // ---- FIXED COLUMNS, SO NOTHING EVER EXCEEDS THE PANEL ----
    //
    // "everything will fit inside perfectly". The cell is DERIVED from the
    // width rather than fixed at 104 px, which is the difference between a
    // grid that fits and a grid that is nearly right: a fixed cell leaves a
    // ragged remainder on the right, and on a narrower panel it silently
    // drops to five columns with a gap. Six equal columns always fill the
    // width exactly, which is what ThemePickerLayer does with four.
    property int columns: 6
    readonly property real cellSize: Math.floor(grid.width / body.columns)

    readonly property real searchStripHeight: searchField.implicitHeight
        + PopupMetrics.s(8)

    // ---- selection, keyed by the entry's index in store.entries ----
    //
    // NOT by its position in the grid: `view` re-sorts and re-filters, and a
    // selection that survives both is the only kind worth having.
    property var selected: ({})
    property int focusIdx: 0          // index into `view`
    property int anchorIdx: 0         // where a shift-range starts
    property string sortMode: "date"
    property string query: ""
    property bool searching: false

    // ---- VISUAL MODE ----
    //
    // Asked for by name: "i wnat to add v to select like vim visual and y to
    // copy". `v` starts it at the focused tile, every motion extends the
    // selection from there, and the operators end it the way vi's do —
    // `y` yanks and leaves, `ctrl+d` deletes and leaves, `v` or Esc cancels.
    //
    // It is the same machinery shift+motion already uses, with the shift
    // held for you; the anchor is the tile `v` was pressed on.
    property bool visual: false

    signal openRequested(int entryIndex)
    signal statusChanged(string text)
    signal closeRequested()
    // Leaving search has to hand the keyboard BACK to the host's FocusScope.
    // Measured: without it the first Escape left search and the second did
    // nothing, because active focus was still inside the search field's
    // TextInput and the host's Keys handler never saw the key. `q` worked
    // throughout, which is what made it look like an Escape bug rather than
    // a focus one.
    signal focusWanted()
    // A tile's own `Drag.active` starting or ending — see the tile's
    // `Drag.onActiveChanged` below for why the host needs to hear this.
    signal dragActiveChanged(bool active)

    // ---- the visible order: filter, then sort ----
    readonly property var view: {
        const e = store ? store.entries : [];
        const q = body.query.toLowerCase().trim();
        const idx = [];
        for (let i = 0; i < e.length; i++) {
            if (q !== "") {
                // The LABEL and the type, not the whole path — a path match
                // makes "conf" hit every file under ~/.config, which is not
                // a filter. The full path is searched only when the query
                // looks like one, so "hypr/" still finds a directory.
                const wantsPath = q.indexOf("/") >= 0;
                const hay = (wantsPath ? String(e[i].value)
                             : body.store.label(e[i]) + " " + body.store.badge(e[i])
                            ).toLowerCase();
                if (hay.indexOf(q) < 0)
                    continue;
            }
            idx.push(i);
        }
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
    readonly property int total: store ? store.count : 0
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

    // SHIFT-RANGE. Reported as not working, and it needed the anchor to be
    // maintained by every path that moves the cursor rather than by plain
    // clicks alone — a range is "from the last place I settled to here", and
    // the keyboard settles in as many places as the mouse does.
    function selectRange(fromViewIdx, toViewIdx) {
        const a = Math.max(0, Math.min(fromViewIdx, toViewIdx));
        const b = Math.min(body.count - 1, Math.max(fromViewIdx, toViewIdx));
        const s = {};
        for (let i = a; i <= b; i++)
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
    //
    // TRAILING CRLF, not just one BETWEEN entries. RFC 2483 says a line is
    // CRLF-TERMINATED, which the last URI was not — `join("\r\n")` puts the
    // separator only between entries, so a single-file drag (the common
    // case) offered a bare URI with no terminator at all. Found chasing a
    // real crash: dragging out of this shelf into pcmanfm-qt's "Copy Here"
    // segfaults inside libfm-qt6 (`Fm::FileTransferJob::setDestDirPath`,
    // confirmed with `coredumpctl debug` — three crashes logged, one live).
    // Not proven to be the cause — the crash is inside a system library
    // this repo does not own the source of — but an unterminated last line
    // is a genuine spec violation on our side regardless of whether it is
    // THE cause, so it is fixed either way.
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
        return out.length === 0 ? "" : out.join("\r\n") + "\r\n";
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
        const m = {};
        if (uris !== "")
            m["text/uri-list"] = uris;
        m["text/plain"] = body.plainText(indexes);
        return m;
    }

    function copySelection() {
        const idx = body.targets();
        if (idx.length === 0)
            return;
        const uris = body.uriList(idx);
        // A PROCESS rather than a clipboard API, because Quickshell has none
        // — and through Clipboard.js rather than straight at `wl-copy`,
        // because this panel runs under qtile too, where wl-copy is inert and
        // silently so. That file carries the whole argument.
        //
        // Either way it goes through the SELECTION and not through some
        // private channel: copyq is this desktop's clipboard manager and it
        // watches the selection, so a copy from here lands in the history
        // like every other. The uri-list form is what a file manager pastes
        // as FILES; without it a paste into pcmanfm-qt is the path as text.
        if (uris !== "")
            Quickshell.execDetached(Clipboard.argv(uris, "text/uri-list"));
        else
            Quickshell.execDetached(Clipboard.argv(body.plainText(idx)));
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

    // ---- ZIP THE SELECTION ----
    //
    // qdrop.py's "zip a selection", same idea and the same destination shape:
    // a dated archive under ~/.cache, added back to the shelf so the thing
    // you just made is the thing you can drag out.
    //
    // Through python3's zipfile rather than `zip`, because that is what
    // qdrop.py uses and it is guaranteed present here — `zip` is not in the
    // package list. A Process rather than execDetached, because the entry
    // may only be added if the archive was actually written: a fire-and-
    // forget would leave a shelf entry pointing at a file that does not
    // exist whenever the zip failed.
    property string pendingZip: ""

    function zipSelection() {
        const idx = body.targets();
        if (idx.length === 0)
            return;
        const paths = [];
        for (let i = 0; i < idx.length; i++) {
            const e = store.entries[idx[i]];
            if (e && String(e.type) === "file")
                paths.push(String(e.value));
        }
        if (paths.length === 0) {
            body.statusChanged("nothing to zip — files only");
            return;
        }
        const d = new Date();
        const stamp = d.getFullYear()
            + ("0" + (d.getMonth() + 1)).slice(-2)
            + ("0" + d.getDate()).slice(-2) + "-"
            + ("0" + d.getHours()).slice(-2)
            + ("0" + d.getMinutes()).slice(-2)
            + ("0" + d.getSeconds()).slice(-2);
        const out = Quickshell.env("HOME") + "/.cache/qdrop-zips/qdrop-"
            + stamp + ".zip";
        body.pendingZip = out;
        zipProc.command = ["python3", "-c",
            "import os,sys,zipfile\n"
            + "out=sys.argv[1]\n"
            + "os.makedirs(os.path.dirname(out), exist_ok=True)\n"
            + "z=zipfile.ZipFile(out,'w',zipfile.ZIP_DEFLATED)\n"
            + "for p in sys.argv[2:]:\n"
            + "    if os.path.isdir(p):\n"
            + "        base=os.path.dirname(p.rstrip('/'))\n"
            + "        for r,_,fs in os.walk(p):\n"
            + "            for f in fs:\n"
            + "                full=os.path.join(r,f)\n"
            + "                z.write(full, os.path.relpath(full, base))\n"
            + "    elif os.path.exists(p):\n"
            + "        z.write(p, os.path.basename(p))\n"
            + "z.close()\n",
            out].concat(paths);
        zipProc.running = true;
        body.statusChanged("zipping " + paths.length + "…");
    }

    // ---- AND THE ARCHIVE HAS TO BE VISIBLE WHEN IT LANDS ----
    //
    // Reported as "the zip not working", and the archives were on disk the
    // whole time: three of them under ~/.cache/qdrop-zips, one pair written
    // two seconds apart, which is what pressing a key that appears to do
    // nothing looks like from the outside. Driven in an isolated Quickshell
    // instance, every link in the chain answered correctly — the Process
    // exits 0, `onExited` fires with the pending path intact, and
    // `QdropStore.addValue` writes the entry — so what was missing was never
    // the mechanism. It was that a new tile appearing at the top of a full
    // shelf, behind whatever the cursor was already on, says nothing.
    //
    // Three changes, none of them to the zipping itself:
    //
    //   * stderr is CAPTURED and reported. "zip failed" with no reason is a
    //     dead end, and python's traceback is the whole diagnosis.
    //   * the archive is checked to EXIST before an entry claiming it is
    //     added, so a shelf can never hold a tile pointing at nothing.
    //   * the cursor MOVES TO THE ARCHIVE and selects it, so the answer to
    //     "did that work" is on screen and under your hand — ready to drag
    //     straight back out, which is the whole reason to zip on a shelf.
    Process {
        id: zipProc

        stderr: StdioCollector { id: zipErr }

        onExited: (code) => {
            const out = body.pendingZip;
            body.pendingZip = "";
            if (code !== 0 || out === "") {
                const err = String(zipErr.text || "").trim();
                const last = err === "" ? "" : err.split("\n").pop();
                body.statusChanged(last === "" ? "zip failed"
                                                : "zip failed: " + last);
                return;
            }
            zipCheck.pending = out;
            zipCheck.command = ["test", "-s", out];
            zipCheck.running = true;
        }
    }

    // `test -s` rather than trusting the exit code alone: python can exit 0
    // having written nothing if every path handed to it had vanished by the
    // time it ran, and an entry pointing at a missing file is worse than no
    // entry — it drags out as a broken URI and there is nothing on the tile
    // to say so.
    Process {
        id: zipCheck

        property string pending: ""

        onExited: (code) => {
            const out = zipCheck.pending;
            zipCheck.pending = "";
            if (code !== 0 || out === "") {
                body.statusChanged("zip failed — nothing was written");
                return;
            }
            body.store.addValue("file", out);
            body.revealEntry(out);
            body.statusChanged("zipped");
        }
    }

    // Put the cursor on an entry by VALUE, and select only it. By value and
    // not by index because `view` re-sorts the moment the store changes, so
    // the position the archive will occupy is not knowable before it lands —
    // and under `name` or `type` sorting it is not the top row at all.
    //
    // Qt.callLater, because `view` is a binding over `store.entries`: reading
    // it in the same turn as the write that provoked it returns the STALE
    // list, which is this tree's own rule about notifiers and one it has paid
    // for twice.
    function revealEntry(value) {
        Qt.callLater(function () {
            for (let i = 0; i < body.count; i++) {
                const e = body.store.entries[body.view[i]];
                if (e && String(e.value) === String(value)) {
                    body.selectOnly(body.view[i]);
                    body.gotoIdx(i, false);
                    return;
                }
            }
        });
    }

    // ---- motion ----
    //
    // The anchor follows every settle, so shift-extending picks up from
    // wherever you last stopped rather than from wherever you last clicked.
    function moveFocus(delta, extend) {
        if (body.count === 0)
            return;
        const next = Math.max(0, Math.min(body.count - 1, body.focusIdx + delta));
        body.focusIdx = next;
        if (extend || body.visual)
            body.selectRange(body.anchorIdx, next);
        else
            body.anchorIdx = next;
        grid.positionViewAtIndex(next, GridView.Contain);
    }

    function gotoIdx(i, extend) {
        if (body.count === 0)
            return;
        const next = Math.max(0, Math.min(body.count - 1, i));
        body.focusIdx = next;
        if (extend || body.visual)
            body.selectRange(body.anchorIdx, next);
        else
            body.anchorIdx = next;
        grid.positionViewAtIndex(next, GridView.Contain);
    }

    function enterVisual() {
        if (body.count === 0)
            return;
        body.visual = true;
        body.anchorIdx = body.focusIdx;
        body.selectRange(body.focusIdx, body.focusIdx);
        body.statusChanged("visual");
    }

    function leaveVisual(keepSelection) {
        body.visual = false;
        if (!keepSelection)
            body.selectNone();
    }

    function enterSearch() {
        body.searching = true;
        searchField.readOnly = false;
        searchField.focusField();
    }

    function leaveSearch(clearQuery) {
        if (clearQuery)
            body.query = "";
        body.searching = false;
        searchField.readOnly = true;
        body.focusWanted();
    }

    // ---- THE KEY MAP ----
    //
    // MODAL, and that is the only way to have both halves of what was asked:
    // "using the hjkl for moving vim motion etc" AND a search box. A focused
    // text field turns every letter into text, so the two cannot coexist in
    // one mode — which is exactly the problem vi solved.
    //
    //   command mode (default)  the field is readOnly and claims NOTHING, so
    //                           every key below reaches here
    //   `/`                     enters search; typing filters
    //   Esc / Enter             leaves search, back to command mode
    //
    // PanelSearchField's own header describes readOnly as the mechanism that
    // "keeps focus and inserts nothing", which is what makes this work with
    // no focus juggling at all.
    //
    // Returns true when the key was ours.
    function handleKey(key, mods) {
        const ctrl = (mods & Qt.ControlModifier) !== 0;
        const shift = (mods & Qt.ShiftModifier) !== 0;
        const perRow = body.columns;

        if (body.searching) {
            // In search mode the field owns the letters; only these escape.
            if (key === Qt.Key_Escape) { body.leaveSearch(true); return true; }
            if (key === Qt.Key_Return || key === Qt.Key_Enter) {
                body.leaveSearch(false); return true;
            }
            return false;
        }

        if (key === Qt.Key_Slash) { body.enterSearch(); return true; }

        // `v` toggles visual; Escape leaves it before it closes the panel,
        // which is vi's own precedence and what stops one key doing two
        // things at once.
        if (key === Qt.Key_V) {
            if (body.visual)
                body.leaveVisual(false);
            else
                body.enterVisual();
            return true;
        }
        if (key === Qt.Key_Escape && body.visual) {
            body.leaveVisual(false);
            return true;
        }

        if (key === Qt.Key_L || key === Qt.Key_Right) { body.moveFocus(1, shift); return true; }
        if (key === Qt.Key_H || key === Qt.Key_Left)  { body.moveFocus(-1, shift); return true; }
        if (key === Qt.Key_J || key === Qt.Key_Down)  { body.moveFocus(perRow, shift); return true; }
        if (key === Qt.Key_K || key === Qt.Key_Up)    { body.moveFocus(-perRow, shift); return true; }
        if (key === Qt.Key_G) {
            // g first, G last — the convention every other panel in this
            // shell uses for the ends of a list.
            body.gotoIdx(shift ? body.count - 1 : 0, false);
            return true;
        }
        if (key === Qt.Key_Home) { body.gotoIdx(0, shift); return true; }
        if (key === Qt.Key_End)  { body.gotoIdx(body.count - 1, shift); return true; }

        if (key === Qt.Key_Return || key === Qt.Key_Enter) { body.openTargets(); return true; }
        // ---- THE TWO DESTRUCTIVE KEYS TAKE CTRL, AND THAT IS THE POINT ----
        //
        // Asked for by name: "the 'zip' not working make it with cntl+z the
        // del make it cntl+d". They are the only two commands on this panel
        // that cannot be undone by pressing the key again — `d` throws the
        // entry away and `z` writes a file to disk — and they sat on bare
        // letters in the middle of a map you drive with your fingers resting
        // on hjkl. Every other key here is a view change.
        //
        // `Delete` still deletes, unmodified, because that is what the key is
        // for and nobody presses it by accident on the way to `s`.
        if (key === Qt.Key_Delete || (ctrl && key === Qt.Key_D)) {
            body.removeTargets(); body.leaveVisual(false); return true;
        }
        if (key === Qt.Key_A) {
            if (shift)
                body.selectNone();
            else
                body.selectAll();
            return true;
        }
        // `y` is yank, and ctrl+c is the same thing for anyone who does not
        // think in vi. Both, because this panel has both audiences.
        if (key === Qt.Key_Y || (ctrl && key === Qt.Key_C)) {
            // Yank, then leave visual with the selection intact — `y` in vi
            // ends the visual and leaves the cursor where it was, and the
            // selection is what you just copied.
            body.copySelection();
            body.visual = false;
            return true;
        }
        if (key === Qt.Key_C && shift) {
            store.clear(); body.selectNone();
            body.statusChanged("shelf cleared");
            return true;
        }
        if (key === Qt.Key_P) { body.pinTargets(); return true; }
        if (key === Qt.Key_S) { body.cycleSort(); return true; }
        if (ctrl && key === Qt.Key_Z) { body.zipSelection(); return true; }
        if (key === Qt.Key_Space) {
            if (body.count > 0) {
                body.toggleOne(body.view[body.focusIdx]);
                body.anchorIdx = body.focusIdx;
            }
            return true;
        }
        return false;
    }

    // ---- SEARCH ----
    PanelSearchField {
        id: searchField

        width: parent.width
        textFontFamily: body.textFontFamily
        iconFontFamily: body.iconFontFamily
        placeholder: body.searching ? "filter the shelf" : "press / to search"
        readOnly: true
        query: body.query
        countText: body.query !== ""
            ? (body.count + " of " + body.total) : ""

        onQueryChanged: {
            if (body.query !== query)
                body.query = query;
            body.focusIdx = 0;
            body.anchorIdx = 0;
        }
        onSubmitted: body.leaveSearch(false)
        onCancelled: {
            if (body.searching)
                body.leaveSearch(true);
            else
                body.closeRequested();
        }
        onMoved: (delta) => body.moveFocus(delta * body.columns, false)
        onMovedHorizontally: (delta) => body.moveFocus(delta, false)
        onCopyRequested: body.copySelection()
    }

    // ---- THE TILES ----
    GridView {
        id: grid

        x: 0
        y: body.searchStripHeight
        width: parent.width
        height: Math.max(0, parent.height - body.searchStripHeight)
        clip: true
        cellWidth: body.cellSize
        cellHeight: body.cellSize
        model: body.view
        boundsBehavior: Flickable.StopAtBounds
        currentIndex: body.focusIdx
        // Unset default (-1/velocity-based) turns every currentIndex change
        // into Qt's own slow follow-scroll, uncoordinated with anything
        // this shell tunes. See ThemePickerLayer.qml's themeGrid for the
        // frame-capture measurement that found it.
        highlightMoveDuration: 0

        // "will has scroll bar". The shelf is the one panel with genuinely
        // unbounded content — it grows every time you drop something.
        ScrollBar.vertical: IslandScrollBar { view: grid }

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
                    spacing: PopupMetrics.s(3)

                    // The thumbnail IS the identity of an image entry. For
                    // everything else the type glyph is.
                    Item {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: PopupMetrics.s(40)
                        height: PopupMetrics.s(40)

                        Image {
                            anchors.fill: parent
                            visible: body.store.isImage(tile.entry)
                            fillMode: Image.PreserveAspectCrop
                            clip: true
                            asynchronous: true
                            cache: true
                            sourceSize.width: PopupMetrics.s(40) * 2
                            sourceSize.height: PopupMetrics.s(40) * 2
                            source: body.store.isImage(tile.entry)
                                ? "file://" + encodeURI(String(tile.entry.value)) : ""
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: !body.store.isImage(tile.entry)
                            text: body.store.glyph(tile.entry)
                            color: tile.isSelected ? body.cHighlightInk : IslandTheme.info
                            font.family: PopupMetrics.font
                            font.pixelSize: Math.round(PopupMetrics.headSize * 1.8)
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
                        font.pixelSize: Math.round(PopupMetrics.hintSize * 0.92)
                        renderType: Text.NativeRendering
                    }
                }

                // The pin, in the corner, because it is a property of the
                // tile and not a line of its text.
                Text {
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.margins: PopupMetrics.s(4)
                    visible: tile.entry && tile.entry.pinned
                    text: String.fromCodePoint(0xF0403)
                    color: tile.isSelected ? body.cHighlightInk : body.cHighlight
                    font.family: PopupMetrics.font
                    font.pixelSize: Math.round(PopupMetrics.hintSize * 0.8)
                    renderType: Text.NativeRendering
                }

                // The type badge — qdrop.py's entry_badge(), for the cases a
                // glyph cannot disambiguate (TXT and DOC are one glyph).
                //
                // TOP-left, not bottom-left, which is where it was first put:
                // the label wraps to two lines and a two-line label reaches
                // the bottom of the tile, so the badge and the filename drew
                // on top of each other.
                Text {
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.margins: PopupMetrics.s(4)
                    text: body.store.badge(tile.entry)
                    color: tile.isSelected ? body.cHighlightInk : body.cMuted
                    font.family: PopupMetrics.font
                    font.pixelSize: Math.round(PopupMetrics.hintSize * 0.72)
                    renderType: Text.NativeRendering
                }
            }

            // ---- DRAGGING OUT ----
            //
            // The mime is built from the SELECTION, not from the tile, so
            // dragging one of five selected files carries all five. Pressing
            // an UNSELECTED tile selects it first, which is what every file
            // manager does and what keeps "drag the one I pressed" true.
            Drag.dragType: Drag.Automatic
            Drag.supportedActions: Qt.CopyAction
            Drag.mimeData: body.mimeFor(body.targets())
            // ---- THE CRASH THIS FIXES ----
            //
            // Reported live: dragging a tile OUT into pcmanfm-qt aborted the
            // whole shell — `QMessageLogger::fatal` inside a QQmlDelegateModel/
            // QQuickItemView teardown, on the call stack of `QDrag::exec()`'s
            // own nested event loop, started from THIS `Drag.active` write.
            // Confirmed with `coredumpctl info`: the abort fires from inside
            // the drag's modal loop, meaning something destroyed a view while
            // the loop that owns this very tile was still running underneath
            // it — a reentrancy Qt has no recovery for but a fatal abort.
            //
            // The file's own header already documents the mechanism for the
            // OTHER direction: "an exclusive [Wayland] grab CANCELS an
            // in-flight drag" is why a shake-opened shelf (`forDrag`) drops to
            // OnDemand keyboard focus before a drag can land in it. A shelf
            // opened the ordinary way — the key, not the shake — has no
            // reason to expect a drag and keeps its Exclusive grab, which is
            // right for typing `hjkl` into it and wrong the instant a tile
            // starts an OUTGOING drag: the same grab-vs-drag conflict, just
            // starting from the grabbed surface instead of arriving at it.
            //
            // `dragActiveChanged` tells the host (QdropShelf) to relax the
            // grab to OnDemand for exactly as long as `Drag.active` is true,
            // whichever direction opened the shelf — see shelf.tileDragActive.
            Drag.onActiveChanged: body.dragActiveChanged(tile.Drag.active)

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
                        body.anchorIdx = tile.index;
                    } else if (m.modifiers & Qt.ShiftModifier) {
                        // The range, from wherever the cursor last settled.
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
                    // ---- THE FILE GOES UNDER THE CURSOR ----
                    //
                    // Reported: "when i drag a file why the file not dirct
                    // under the cursor its too far from it in the right hand
                    // side". `Drag.hotSpot` is the point INSIDE the dragged
                    // item that sits at the pointer, and it defaults to the
                    // item's TOP-LEFT — so the whole tile hangs down and to
                    // the right of where you are pointing, which is exactly
                    // the offset described.
                    //
                    // The right answer is not the centre either: it is the
                    // point you actually grabbed, so the tile stays where it
                    // was under your finger when the drag began. That is what
                    // the X11 shelf does.
                    tile.Drag.hotSpot = Qt.point(tileMouse.px, tileMouse.py);
                    // `active = true` IS the start, for Drag.Automatic —
                    // startDrag() is not, and calling it warns
                    // `startDrag() drag must be active` on every drag while
                    // still delivering. Qt clears `active` when the drag ends.
                    tile.Drag.active = true;
                }

                onDoubleClicked: body.openTargets()
            }
        }
    }

    // ---- RUBBER BAND ----
    //
    // "how can i selecte more than one" has a keyboard answer and a MOUSE
    // answer, and this is the mouse one. Below the tiles in z order and over
    // the grid only, so it can never start on top of something that wanted to
    // be dragged.
    MouseArea {
        id: bandArea

        x: 0
        y: body.searchStripHeight
        width: parent.width
        height: Math.max(0, parent.height - body.searchStripHeight)
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
            band.y = bandArea.y + Math.min(bandArea.oy, m.y);
            band.width = Math.abs(m.x - bandArea.ox);
            band.height = Math.abs(m.y - bandArea.oy);
            body.selectWithin(Math.min(bandArea.ox, m.x), Math.min(bandArea.oy, m.y),
                              band.width, band.height);
        }
        onReleased: {
            bandArea.active = false;
            band.width = 0;
            band.height = 0;
        }
    }

    // Coordinates are the GRID's, which is what itemAtIndex reports against.
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
            font.pixelSize: Math.round(PopupMetrics.headSize * 2.0)
            renderType: Text.NativeRendering
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: body.total === 0 ? "drag files here" : "nothing matches"
            color: body.cMuted
            font.family: PopupMetrics.font
            font.pixelSize: PopupMetrics.rowSize
            renderType: Text.NativeRendering
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: body.total === 0
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

        function openAt(pt) {
            menu.x = Math.max(0, Math.min(pt.x, body.width - menu.width - PopupMetrics.s(4)));
            menu.y = Math.max(0, Math.min(pt.y, body.height - menu.height - PopupMetrics.s(4)));
            menu.visible = true;
        }

        visible: false
        z: 20
        width: PopupMetrics.s(190)
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
                    { label: "Open",          act: "open" },
                    { label: "Copy",          act: "copy" },
                    { label: "Copy path",     act: "path" },
                    { label: "Zip selection", act: "zip" },
                    { label: "Reveal",        act: "reveal" },
                    { label: "Pin / unpin",   act: "pin" },
                    { label: "Remove",        act: "remove" }
                ]

                Rectangle {
                    required property var modelData

                    width: menuCol.width
                    height: PopupMetrics.s(24)
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
            Quickshell.execDetached(Clipboard.argv(body.plainText(idx)));
            body.statusChanged("path copied");
        } else if (act === "zip") {
            body.zipSelection();
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
