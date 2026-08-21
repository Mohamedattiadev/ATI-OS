import QtQuick
import Quickshell
import Quickshell.Io

import "../common"

//
// FORK — new file. popups/WallpaperPopup.py, in Quickshell.
//
// WHY IT EXISTS
// -------------
// The topbar's ✖ chip is qtile's `wallpaper_toggle`, whose Button1 is
// `toggle_wallpaper_picker` — that popup. Under this bar it ran `ati-dm-setbg`, a
// rofi menu, which is a different thing wearing the same key. Asked for
// directly: "the ✖ chip should show the wal picker that was written as a
// qtile popup — write one in Quickshell, same style, same working, and it
// should behave like the qtile one".
//
// So the SPEC is that file, and it is followed rather than reinterpreted:
// three columns of twenty names, the preview card, the meta strip, the
// footer with its scroll bar, and the same keys.
//
//     h l      move column        j k    move row
//     r        random             /      fuzzy search (rofi, as there)
//     Return   apply              q Esc  close
//
// WHAT IS DELIBERATELY DIFFERENT
// ------------------------------
// `xwallpaper --stretch` is X11 and does nothing under Hyprland, so applying
// goes through hypr/scripts/wallpaper-set.sh, which is this session's own
// setter and already does the ~/.cache/wall symlink and the conditional
// retheme. The RULE it implements is the one worth keeping and is copied out
// of that file's comment: retheme ONLY when the active mode is `wal`, because
// on a pinned preset "picking a wallpaper must swap the desktop image and
// leave every themed consumer alone".
PopupChrome {
    id: root

    // NOT `closed`: a PanelWindow is a QQuickWindow and already has one,
    // so declaring it logs "Duplicate signal name: invalid override of
    // property change signal or superclass signal" and the handler is
    // never called — a popup that cannot ask to be closed, with a
    // warning rather than an error to say so.
    signal requestClose()

    titleIcon: String.fromCodePoint(0xF0E09)
    title: "Wallpapers"
    subtitle: "~/Pictures/Wallpapers  ·  " + root.images.length + " images"

    // render_header_badge(): what a pick will do to the palette.
    badgeLabel: root.themeMode === "wal"
        ? "palette follows wallpaper" : "palette pinned"
    badgeValue: String.fromCodePoint(0xF03D8) + " "
        + (root.themeMode === "" ? "unknown" : root.themeMode)

    hints: [
        { key: "hjkl", desc: "move" },
        { key: "/",    desc: "search" },
        { key: "R",    desc: "random" },
        { key: "↵", desc: "apply" },
        { key: "Esc",  desc: "close" }
    ]

    // ---- STATE ----
    property var images: []          // absolute paths, sorted
    property int index: 0
    property int colOffset: 0
    property string currentWall: ""
    property string themeMode: ""

    // ROWS_PER_COL / COL_COUNT / MAX_NAME_LEN, verbatim.
    readonly property int rowsPerCol: 20
    readonly property int colCount: 3
    readonly property int maxNameLen: 17

    readonly property string wallDir: Quickshell.env("HOME") + "/Pictures/Wallpapers"

    function baseName(p) {
        const i = String(p).lastIndexOf("/");
        return i < 0 ? String(p) : String(p).substring(i + 1);
    }

    // truncate(): pad to MAX_NAME_LEN so the selected row's block is the same
    // width on every row — "ensure name fills the space for the background
    // color to look like a bar".
    function padName(n) {
        let s = String(n);
        if (s.length > root.maxNameLen)
            s = s.substring(0, root.maxNameLen - 1) + "…";
        while (s.length < root.maxNameLen)
            s += " ";
        return s;
    }

    // ---- NAVIGATION ----
    //
    // index_to_pos(): row = i % ROWS_PER_COL, col = i / ROWS_PER_COL. The
    // list fills DOWN each column and then across, which is why `l` steps by
    // a whole column and not by one.
    function move(dRow, dCol) {
        if (root.images.length === 0)
            return;
        const next = root.index + dRow + dCol * root.rowsPerCol;
        if (next < 0 || next >= root.images.length)
            return;
        root.index = next;
        root.ensureVisible();
    }

    function ensureVisible() {
        const col = Math.floor(root.index / root.rowsPerCol);
        if (col < root.colOffset)
            root.colOffset = col;
        else if (col >= root.colOffset + root.colCount)
            root.colOffset = col - root.colCount + 1;
    }

    function jumpToRandom() {
        if (root.images.length === 0)
            return;
        root.index = Math.floor(Math.random() * root.images.length);
        root.ensureVisible();
    }

    // ---- THE LIST ----
    //
    // `find` rather than a directory model, because the original sorts the
    // names and filters on the same four extensions, and FolderListModel
    // would give a second ordering to keep in step.
    //
    // NOT `-maxdepth 1`. That excluded `~/Pictures/Wallpapers/themed/` —
    // the 21 `themed/<theme>.jpg` covers AND the ~500 `themed/<theme>/*.jpg`
    // images inside each theme folder — from `root.images` entirely, so
    // `/` search for "gruvbox" (or any theme name) always came back empty:
    // not a search bug, the file was never in the list to match. The
    // island's own picker hit the exact same thing and was already fixed
    // to walk the whole tree (see WallpaperPickerLayer.qml's `os.walk`
    // note); this popup — the native/topbar bar's picker — was not. `-o
    // -path '*/.git' -prune` keeps the walk out of the directory's own git
    // metadata, which `-maxdepth 1` also happened to exclude for free.
    Process {
        id: listProc
        command: ["sh", "-c",
            "find \"$HOME/Pictures/Wallpapers\" -path '*/.git' -prune "
            + "-o -type f \\( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' "
            + "-o -iname '*.webp' \\) -print | sort"]
        stdout: StdioCollector {
            onStreamFinished: {
                const list = text.split("\n").filter((l) => l.trim() !== "");
                root.images = list;
                // Open ON the applied wallpaper, which is what
                // load_current_wallpaper() is for there.
                const at = list.indexOf(root.currentWall);
                root.index = at >= 0 ? at : 0;
                root.ensureVisible();
            }
        }
    }

    // ~/.cache/wall is normally a SYMLINK to the image and only falls back to
    // holding the path as text. That file's own comment records what reading
    // it the other way costs: "reading a symlinked JPEG as text raises
    // UnicodeDecodeError, which is why this used to always come back None and
    // neither the check mark nor the opening position ever worked".
    Process {
        id: currentProc
        command: ["sh", "-c",
            "readlink -f \"$HOME/.cache/wall\" 2>/dev/null || cat \"$HOME/.cache/wall\" 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.currentWall = text.trim();
                listProc.running = true;
            }
        }
    }

    Process {
        id: modeProc
        command: ["sh", "-c", "cat \"$HOME/.cache/qtile/theme_mode\" 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: root.themeMode = text.trim()
        }
    }

    Component.onCompleted: {
        modeProc.running = true;
        currentProc.running = true;
    }

    // ---- ACTIONS ----
    function apply() {
        if (root.images.length === 0)
            return;
        Quickshell.execDetached([
            Quickshell.env("HOME") + "/.config/hypr/scripts/wallpaper-set.sh",
            root.images[root.index]]);
        root.requestClose();
    }

    // fuzzy_search_rofi(), and it stays ROFI rather than becoming an inline
    // field. Not laziness: the original is rofi, the ✖ chip's neighbours on
    // this bar are rofi, and a second search UI would be a second set of
    // matching rules for the same list. The name comes back on stdout and is
    // looked up in `images` exactly as _apply() does there.
    Process {
        id: searchProc
        stdout: StdioCollector {
            onStreamFinished: {
                const name = text.trim();
                if (name === "")
                    return;
                for (let i = 0; i < root.images.length; i++) {
                    if (root.baseName(root.images[i]) === name) {
                        root.index = i;
                        root.ensureVisible();
                        return;
                    }
                }
            }
        }
    }

    function search() {
        if (root.images.length === 0)
            return;
        const names = root.images.map((p) => root.baseName(p)).join("\n");
        searchProc.command = ["sh", "-c",
            "printf '%s' \"$1\" | rofi -dmenu -p 'Search Wallpaper' -i "
            + "-theme-str 'window {width: 50%;}'", "sh", names];
        searchProc.running = true;
    }

    onKeyPressed: (key, mods, text) => {
        switch (key) {
        case Qt.Key_H: case Qt.Key_Left:  root.move(0, -1); break;
        case Qt.Key_L: case Qt.Key_Right: root.move(0, 1);  break;
        case Qt.Key_J: case Qt.Key_Down:  root.move(1, 0);  break;
        case Qt.Key_K: case Qt.Key_Up:    root.move(-1, 0); break;
        // Lowercase deliberately, and config.py explains why its own binding
        // is spelled that way: "qtile's keysym table is lowercase-normalised,
        // so Key([], "R") never meant Shift+R". Both are accepted here since
        // the hint bar shows an R.
        case Qt.Key_R:                    root.jumpToRandom(); break;
        case Qt.Key_Slash:                root.search(); break;
        case Qt.Key_Return: case Qt.Key_Enter: root.apply(); break;
        }
    }

    onDismissed: root.requestClose()

    // ---- THE COLUMNS ----
    //
    // Three cards side by side. "Each control paints its own rounded surface,
    // so the gaps between them are the popup background showing through."
    Row {
        anchors.left: parent.left
        anchors.top: parent.top
        height: parent.height
        // col_width 0.166 and gap 0.009 are fractions of POPUP_W; the parent
        // here is the body area, which is 0.93 of it.
        spacing: root.popupWidth * 0.009

        Repeater {
            model: root.colCount

            delegate: Rectangle {
                required property int index
                readonly property int colIndex: index

                width: root.popupWidth * 0.166
                // The list cards are body_h tall; the preview is shorter and
                // gives its bottom to the meta strip.
                height: parent.height
                color: root.cSurface
                radius: PopupMetrics.s(10)

                Column {
                    anchors.left: parent.left
                    anchors.leftMargin: PopupMetrics.s(8)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 0

                    Repeater {
                        model: root.rowsPerCol

                        delegate: Item {
                            required property int index
                            readonly property int rowIndex: index
                            // pos_to_index(): the visible column plus the
                            // horizontal scroll offset.
                            readonly property int imgIndex:
                                (colIndex + root.colOffset) * root.rowsPerCol + rowIndex
                            readonly property bool exists:
                                imgIndex >= 0 && imgIndex < root.images.length
                            readonly property bool selected: exists && imgIndex === root.index
                            readonly property bool isCurrent:
                                exists && root.images[imgIndex] === root.currentWall

                            width: rowText.implicitWidth + PopupMetrics.s(10)
                            // A fixed line box, so short columns pad with
                            // BLANK LINES rather than being cut short — the
                            // cards are centred vertically and a ragged column
                            // would float its rows away from its neighbours'.
                            height: Math.round(PopupMetrics.rowSize * 1.45)

                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: 0
                                visible: parent.selected
                                color: root.cHighlight
                                radius: PopupMetrics.s(3)
                            }

                            Text {
                                id: rowText
                                anchors.left: parent.left
                                anchors.leftMargin: PopupMetrics.s(5)
                                anchors.verticalCenter: parent.verticalCenter
                                text: {
                                    if (!parent.exists)
                                        return "";
                                    const name = root.padName(
                                        root.baseName(root.images[parent.imgIndex]));
                                    // The mark column: a check on the applied
                                    // wallpaper, a dot otherwise, so every row
                                    // is the same character count and the
                                    // names line up.
                                    const mark = parent.isCurrent
                                        ? String.fromCodePoint(0xF012C)
                                        : String.fromCodePoint(0xF0765);
                                    return " " + mark + " " + name + " ";
                                }
                                color: parent.selected ? root.cHighlightInk
                                    : parent.isCurrent ? IslandTheme.success
                                    : root.cFg
                                font.family: PopupMetrics.font
                                font.pixelSize: PopupMetrics.rowSize
                                font.bold: parent.selected || parent.isCurrent
                                renderType: Text.NativeRendering
                            }
                        }
                    }
                }
            }
        }
    }

    // ---- PREVIEW ----
    //
    // "The card colour doubles as the letterbox for images whose aspect ratio
    // doesn't match the frame, so the preview always reads as a framed panel."
    Rectangle {
        id: previewCard
        x: parent.width - width
        y: 0
        // pos_x 0.565 / width 0.3995 of POPUP_W; against the body area, whose
        // own width is 0.93 of it, that is the right-hand 0.4296.
        width: root.popupWidth * 0.3995
        height: PopupMetrics.s(380)
        color: root.cSurface
        radius: PopupMetrics.s(10)
        clip: true

        Image {
            anchors.fill: parent
            anchors.margins: PopupMetrics.s(6)
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            cache: false
            // sourceSize caps the decode. Without it a 4K wallpaper is
            // decoded at full size for a 440x380 card, per keypress, and
            // holding `j` walks the whole directory through the image cache.
            sourceSize.width: PopupMetrics.s(880)
            sourceSize.height: PopupMetrics.s(760)
            source: root.images.length > 0
                ? "file://" + root.images[root.index] : ""
        }
    }

    // ---- META ----
    //
    // pos_y 526 against body_y 138 — 388 into the body, "in the gap left
    // under the preview card; bottom edge is flush with the list cards".
    Rectangle {
        x: previewCard.x
        y: PopupMetrics.s(526 - 138)
        width: previewCard.width
        height: PopupMetrics.s(48)
        color: root.cSurface
        radius: PopupMetrics.s(10)

        Text {
            anchors.centerIn: parent
            text: root.metaText
            color: root.cMuted
            font.family: PopupMetrics.font
            font.pixelSize: PopupMetrics.hintSize
            renderType: Text.NativeRendering
        }
    }

    // image_meta(): "1920×1080  ·  JPG  ·  1.4 MB".
    //
    // CACHED PER PATH, which is that function's own note and its reason:
    // "this runs on the qtile event loop on every cursor move, and PIL only
    // reads the header, but a dict lookup beats even that when you hold down
    // `j`". Here it is a subprocess rather than a header read, so the cache is
    // not an optimisation but the difference between a popup and a fork bomb.
    //
    // `identify -ping` reads the header and stops — without it a 4K wallpaper
    // is fully decoded to answer a question about its width. The dimensions do
    // NOT come from the preview Image, which was the first attempt and was
    // wrong in a way that reads as right: sourceSize caps the decode, so
    // implicitWidth is the SCALED size and the strip confidently reported
    // 1169×760 for a 3840×2160 image.
    property var metaCache: ({})
    property string metaText: ""

    Process {
        id: metaProc
        property string forPath: ""
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.trim().split(/\s+/);
                const bytes = parseInt(parts[0], 10);
                const dims = parts.length > 1 ? parts[1] : "";
                const out = [];
                if (dims !== "" && dims.indexOf("x") > 0)
                    out.push(dims.replace("x", "×"));
                const dot = metaProc.forPath.lastIndexOf(".");
                if (dot >= 0)
                    out.push(metaProc.forPath.substring(dot + 1).toUpperCase());
                if (isFinite(bytes))
                    out.push(bytes >= 1048576 ? (bytes / 1048576).toFixed(1) + " MB"
                                              : Math.floor(bytes / 1024) + " KB");
                const meta = out.join("  ·  ");
                root.metaCache[metaProc.forPath] = meta;
                // Only if the cursor has not moved on while this ran — holding
                // `j` starts several of these and the last to finish is not
                // the one under the cursor.
                if (root.images[root.index] === metaProc.forPath)
                    root.metaText = meta;
            }
        }
    }

    function refreshMeta() {
        if (root.images.length === 0) {
            root.metaText = "";
            return;
        }
        const path = root.images[root.index];
        const hit = root.metaCache[path];
        if (hit !== undefined) {
            root.metaText = hit;
            return;
        }
        root.metaText = "";
        metaProc.forPath = path;
        metaProc.command = ["sh", "-c",
            "stat -c %s \"$1\"; identify -ping -format '%wx%h' \"$1\" 2>/dev/null",
            "sh", path];
        metaProc.running = true;
    }

    onIndexChanged: root.refreshMeta()
    // …and on the FIRST list, which onIndexChanged does not cover: the cursor
    // opens at 0 and stays at 0 whenever the applied wallpaper is the first
    // one or is missing, so the signal never fires and the strip stayed empty.
    onImagesChanged: root.refreshMeta()

    // ---- FOOTER ----
    //
    // render_footer(): a glyph, the file name, a twenty-cell scroll bar with
    // the filled part in the accent, then position / total and a percentage.
    footer: Row {
        anchors.centerIn: parent
        spacing: 0
        visible: root.images.length > 0

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: String.fromCodePoint(0xF03D8) + "  "
            color: root.cHighlight
            font.family: PopupMetrics.font
            font.pixelSize: PopupMetrics.footSize
            renderType: Text.NativeRendering
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.images.length > 0 ? root.baseName(root.images[root.index]) : ""
            color: root.cFg
            font.bold: true
            font.family: PopupMetrics.font
            font.pixelSize: PopupMetrics.footSize
            renderType: Text.NativeRendering
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "   ·   "
            color: root.cLine
            font.family: PopupMetrics.font
            font.pixelSize: PopupMetrics.footSize
            renderType: Text.NativeRendering
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            // bar_len=20, filled = max(1, round(20 * position / total)).
            text: {
                const total = root.images.length;
                if (total === 0) return "";
                const pos = root.index + 1;
                const filled = Math.max(1, Math.round(20 * pos / total));
                return "━".repeat(filled);
            }
            color: root.cHighlight
            font.family: PopupMetrics.font
            font.pixelSize: PopupMetrics.footSize
            renderType: Text.NativeRendering
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: {
                const total = root.images.length;
                if (total === 0) return "";
                const pos = root.index + 1;
                const filled = Math.max(1, Math.round(20 * pos / total));
                return "━".repeat(20 - filled);
            }
            color: root.cLine
            font.family: PopupMetrics.font
            font.pixelSize: PopupMetrics.footSize
            renderType: Text.NativeRendering
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "   ·   "
            color: root.cLine
            font.family: PopupMetrics.font
            font.pixelSize: PopupMetrics.footSize
            renderType: Text.NativeRendering
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: String(root.index + 1)
            color: IslandTheme.purpleText
            font.bold: true
            font.family: PopupMetrics.font
            font.pixelSize: PopupMetrics.footSize
            renderType: Text.NativeRendering
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: {
                const total = root.images.length;
                if (total === 0) return "";
                const pct = Math.round(100 * (root.index + 1) / total);
                return " / " + total + "   (" + pct + "%)";
            }
            color: root.cMuted
            font.family: PopupMetrics.font
            font.pixelSize: PopupMetrics.footSize
            renderType: Text.NativeRendering
        }
    }
}
