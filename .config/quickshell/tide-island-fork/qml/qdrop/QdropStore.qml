import QtQuick
import Quickshell
import Quickshell.Io

//
// ============================================================
//  qdrop's model — ~/.cache/qdrop.json, the same file the GTK shelf uses
// ============================================================
//
// The Quickshell shelf is a REWRITE OF THE SURFACE, NOT OF THE FORMAT. The
// GTK version's 2,187 lines are mostly GTK; what is worth keeping is the
// contract, and this is it:
//
//     [ { "type": "file" | "text" | "url",
//         "value": "<path or text>",
//         "added_ts": <unix float>,
//         "pinned": <bool> }, ... ]      newest first
//
// Keeping the file means `qdrop.py --add-text` still works, everything that
// already feeds the shelf keeps feeding it, and switching between the two
// implementations does not lose a single entry.
//
// WHY NO JsonAdapter
// ------------------
// NEXT-SESSION.md records a crash from `FileView` + `JsonAdapter` with a
// free-form map on it: the config LOADED cleanly, logged "Configuration
// Loaded", and then the process died with `QProcess: Destroyed while process
// ("pactl") is still running`. Its own advice is that a LIST is the shape
// known to survive. A list is exactly what this is — but `setText()` with
// JSON.stringify sidesteps the adapter entirely, which is one fewer thing
// that can take the bar down. topbar/shell.qml already writes a file that
// way.
//
// THE WATCHER AND OUR OWN WRITES
// ------------------------------
// `atomicWrites` replaces the inode, and IslandTheme.qml's note says why that
// matters — FileView is a QFileSystemWatcher, and a watcher on a replaced
// file is a watcher on an unlinked one. So a write here re-arms the watch
// explicitly rather than trusting it to survive, and `writing` suppresses the
// reload our own write provokes so the model does not round-trip through the
// disk on every change.
//
Item {
    id: root

    property string path: Quickshell.env("HOME") + "/.cache/qdrop.json"

    // The list, newest first. Read-only to consumers; go through the
    // functions, which are what write the file.
    property var entries: []

    property bool loaded: false
    property bool writing: false

    readonly property int count: entries.length

    signal changed()

    function applyText(t) {
        const s = String(t || "").trim();
        if (s === "") {
            root.entries = [];
            root.loaded = true;
            root.changed();
            return;
        }
        try {
            const parsed = JSON.parse(s);
            root.entries = Array.isArray(parsed) ? parsed : [];
        } catch (e) {
            // A half-written file is a state, not an error worth losing the
            // model over: keep what we had and let the next change fix it.
            console.warn("[qdrop] could not parse " + root.path + ": " + e);
            return;
        }
        root.loaded = true;
        root.changed();
    }

    function persist() {
        root.writing = true;
        file.setText(JSON.stringify(root.entries));
        // Re-arm: see the note above about atomicWrites and the watcher.
        Qt.callLater(function () {
            file.path = "";
            file.path = root.path;
            root.writing = false;
        });
        root.changed();
    }

    // ---- the operations the surface needs ----

    function addValue(type, value) {
        const v = String(value || "");
        if (v === "")
            return false;
        const list = root.entries.slice();
        // Same de-duplication the GTK shelf has: re-dropping something you
        // already have moves it to the top rather than making a second row.
        for (let i = 0; i < list.length; i++) {
            if (list[i] && String(list[i].value) === v
                    && String(list[i].type) === String(type)) {
                const existing = list.splice(i, 1)[0];
                existing.added_ts = Date.now() / 1000;
                list.unshift(existing);
                root.entries = list;
                root.persist();
                return true;
            }
        }
        list.unshift({
            "type": String(type),
            "value": v,
            "added_ts": Date.now() / 1000,
            "pinned": false
        });
        root.entries = list;
        root.persist();
        return true;
    }

    // A dropped URL is `file://...` for a file and anything else for a link.
    // decodeURIComponent because a path with a space arrives percent-encoded
    // and every consumer of this file wants the real path.
    function addUrl(url) {
        const u = String(url || "");
        if (u === "")
            return false;
        if (u.indexOf("file://") === 0) {
            let p = u.substring(7);
            const hash = p.indexOf("#");
            if (hash >= 0)
                p = p.substring(0, hash);
            try {
                p = decodeURIComponent(p);
            } catch (e) {}
            return root.addValue("file", p);
        }
        return root.addValue("url", u);
    }

    function addText(t) {
        const s = String(t || "").trim();
        if (s === "")
            return false;
        if (/^[a-zA-Z][a-zA-Z0-9+.-]*:\/\//.test(s))
            return root.addValue("url", s);
        return root.addValue("text", s);
    }

    function removeAt(indexes) {
        const drop = {};
        for (let i = 0; i < indexes.length; i++)
            drop[indexes[i]] = true;
        const list = [];
        for (let i = 0; i < root.entries.length; i++)
            if (!drop[i])
                list.push(root.entries[i]);
        root.entries = list;
        root.persist();
    }

    function clear() {
        root.entries = [];
        root.persist();
    }

    // ---- presentation, kept here so both hosts agree ----
    //
    // entry_badge() and entry_label() from qdrop.py, same answers.

    readonly property var imgExt: ["png", "jpg", "jpeg", "gif", "bmp", "webp",
                                   "svg", "tiff"]
    readonly property var docExt: ["pdf", "doc", "docx", "odt", "rtf"]

    function extOf(p) {
        const s = String(p);
        const slash = s.lastIndexOf("/");
        const base = slash >= 0 ? s.substring(slash + 1) : s;
        const dot = base.lastIndexOf(".");
        return dot > 0 ? base.substring(dot + 1).toLowerCase() : "";
    }

    function badge(entry) {
        if (!entry)
            return "";
        const t = String(entry.type);
        if (t === "url")
            return "URL";
        if (t === "text")
            return "TXT";
        const p = String(entry.value);
        // A trailing slash is the only "is this a directory" test available
        // without stat()ing from QML, and it is what a directory drop gives.
        if (p.length > 1 && p.charAt(p.length - 1) === "/")
            return "DIR";
        const e = root.extOf(p);
        if (e === "")
            return "DIR";
        if (root.imgExt.indexOf(e) >= 0)
            return "IMG";
        if (root.docExt.indexOf(e) >= 0)
            return "DOC";
        return "FILE";
    }

    function label(entry) {
        if (!entry)
            return "";
        const t = String(entry.type);
        const v = String(entry.value);
        if (t === "text")
            return v.replace(/\s+/g, " ").trim();
        if (t === "url")
            return v;
        const slash = v.replace(/\/+$/, "").lastIndexOf("/");
        return slash >= 0 ? v.substring(slash + 1) : v;
    }

    function subtitle(entry) {
        if (!entry)
            return "";
        const t = String(entry.type);
        const v = String(entry.value);
        if (t === "text")
            return v.length + " characters";
        if (t === "url")
            return "link";
        const slash = v.replace(/\/+$/, "").lastIndexOf("/");
        return slash > 0 ? v.substring(0, slash) : v;
    }

    function isImage(entry) {
        return entry && String(entry.type) === "file"
            && root.imgExt.indexOf(root.extOf(entry.value)) >= 0;
    }

    FileView {
        id: file

        path: root.path
        watchChanges: true
        preload: true
        atomicWrites: true
        // The file does not exist until something has been dropped. That is a
        // normal first-run state, not an error worth a log line -- the same
        // argument LayoutState.qml makes for the layout file.
        printErrors: false

        onLoaded: root.applyText(text())
        onFileChanged: {
            if (root.writing)
                return;
            reload();
            root.applyText(text());
        }
    }
}
