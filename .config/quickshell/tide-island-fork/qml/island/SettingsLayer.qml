pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import IslandBackend

// FORK: the shared scale factor — see qml/common/Metrics.js.
import "../common/Metrics.js" as Metrics
// FORK: the shared motion system — one spring for geometry, one
// critically damped curve for opacity. See qml/common/Motion.js.
import "../common/Motion.js" as Motion
import "../common"

//
// FORK — new file. The SETTINGS surface.
//
// WHY THIS IS A PANEL AND NOT A PATCH
// -----------------------------------
// tide-island already has a settings application. It is
// /usr/bin/tide-island-config-app, and it is a COMPILED C++/Qt binary owned
// by the pacman package `tide-island 1.0.34-1`. Patching it means building it
// locally, and a local build of a packaged binary is overwritten without
// warning by the next `yay -Syu` — the same trap FORK-NOTES.md records for
// the vendored QML tree, except worse, because that one at least leaves a
// diff behind for `diff -ru` to find. A replaced binary leaves nothing.
//
// So this is a state of the island, like every other panel here.
//
// AND IT IS NOT A CLONE OF THAT APP
// ---------------------------------
// Reproducing all 39 backend properties would be a worse text editor than
// the file already is: userconfig.json is heavily annotated with `_key`
// comment entries explaining every divergence from upstream, and a panel
// cannot show those in the space a row has. Two tests decided each row, and
// they are written out in island-settings.py beside the table itself —
// roughly "changed more than once in practice", or "FORK-ONLY".
//
// The fork-only ones are the point. Notch mode, the chord HUD, the resting
// EQ and the theme reveal do not exist upstream, so
// UserConfigBackend has no property for them, so the packaged config app
// cannot show them and never will. Before this panel the only way to change
// one was to edit a QML literal. `scope` is on every row for exactly that
// reason: "fork" means the packaged app is blind to this key.
//
// WHERE THE WRITE HAPPENS, AND WHY NOT HERE
// -----------------------------------------
// hypr/scripts/island-settings.py, via os.replace. Not from QML, and the
// reason is the annotations: a writer has to read the whole object, change
// one key, and put the object back, or the twelve `_key` comments explaining
// a dozen decisions are gone in one save with nothing on screen to say so.
// That is a read-modify-write with an atomic rename, and doing it in QML
// would mean doing it without either.
//
// TWO CONSUMERS, TWO REFRESH PATHS
// --------------------------------
//   * `fork*` keys are read by qml/common/ForkConfig.qml, which WATCHES the
//     file. Those update themselves.
//   * packaged keys are read by the compiled UserConfigBackend, which is
//     re-read explicitly with UserConfig.reload() after a successful write.
//     Without that the file would be right and the island would not move,
//     which reads as the write having failed.
//
FocusScope {
    id: root

    signal closeRequested

    property bool showCondition: false
    property string textFontFamily: ""
    property string heroFontFamily: ""

    readonly property var userConfig: UserConfig
    readonly property string ctl: Quickshell.env("HOME") + "/.config/hypr/scripts/island-settings.py"

    // [{ key, label, type, value, scope, detail, ... }, ...]
    property var settings: []
    property int selectedIndex: 0
    property string statusText: ""
    property bool statusIsError: false
    property string configPath: ""

    // Problems in settings-extra.json, from --list. A row rejected for a typo
    // is SKIPPED rather than fatal (island-settings.py, load_extra), which is
    // the right call and is also completely invisible — the panel just has
    // one fewer row than the file asked for. This is the half that makes it
    // visible.
    property var warnings: []

    // FORK: header height, content inset and the key-hint strip are
    // PanelChrome's now. The warning band is not chrome — it is this panel's
    // own content — so it stays here and is declared to the chrome as
    // footerExtraHeight, which is room reserved above the hints.
    readonly property real rowHeight: Metrics.px(30)
    readonly property int warningLines: Math.min(root.warnings.length, 3)
    readonly property real warningHeight:
        root.warningLines > 0
            ? root.warningLines * Metrics.px(14) + Metrics.pad(8) : 0

    // The list is the tall half; the details column beside it is bounded by
    // the list, not the other way round. Same list-plus-details shape the
    // display and audio panels use.
    // Metrics and not chrome.chromeHeight: this sizes the capsule the panel is
    // drawn inside, so reading it off a child of that panel is a loop waiting
    // for one more term.
    readonly property real preferredHeight:
        Metrics.chromeTotal() + root.settings.length * root.rowHeight
        + root.warningHeight

    readonly property real listWidth: Math.round(root.width * 0.52)

    readonly property var selected:
        (root.selectedIndex >= 0 && root.selectedIndex < root.settings.length)
            ? root.settings[root.selectedIndex] : null

    focus: showCondition
    activeFocusOnTab: true
    anchors.fill: parent
    opacity: showCondition ? 1 : 0

    // FORK: one choreography for every layer in the shell. See Motion.js.
    Behavior on opacity {
        SequentialAnimation {
            PauseAnimation { duration: root.showCondition ? Motion.contentDelay() : 0 }
            NumberAnimation {
                duration: root.showCondition ? Motion.fadeInDuration() : Motion.fadeOutDuration()
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Motion.fade()
            }
        }
    }

    onShowConditionChanged: {
        if (showCondition) {
            // Re-read on every open. The file is also written by the packaged
            // config app and by hand, and a panel showing a cached value would
            // be the one place in this shell that disagreed with the config it
            // is editing.
            root.statusText = "";
            root.statusIsError = false;
            listProcess.running = true;
            // DEFERRED, where this used to be a bare forceActiveFocus().
            //
            // The direct call runs in the same event-loop turn as the
            // showCondition change, and so does islandContainer's own
            // forceActiveFocus() — the FocusScope hands focus to its focus
            // child and recurses, so whichever of the two runs LAST decides
            // who ends up with it. That is why this panel's keyboard was
            // intermittent rather than dead: measured, one run of twelve
            // paced `j` presses moved the selection four rows and the next
            // moved it none, with nothing changed in between.
            //
            // Qt.callLater puts the claim in the turn after both, which is
            // the same fix NotificationCenterLayer needed and for the same
            // reason. The guard matters because the panel can be closed
            // inside that one turn.
            Qt.callLater(function() {
                if (root.showCondition)
                    root.forceActiveFocus();
            });
        }
    }

    Process {
        id: listProcess
        command: ["python3", root.ctl, "--list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(text);
                    // FORK: filtered on `panel`, not taken whole.
                    //
                    // The schema now carries rows this panel has no editor
                    // for — the four font families and the wallpaper folder,
                    // which are `font` and `path` and need a text field.
                    // There is no text field here and there cannot be one:
                    // this layer lives under a Hyprland keyboard grab, and a
                    // field would swallow the next character typed into the
                    // focused window.
                    //
                    // island-settings.py derives `panel` from the type and
                    // reports it per row, so the test is on DATA rather than
                    // on a copy of that table living here and drifting from
                    // it. Without this line those five rows would render,
                    // show their values and ignore every keypress — which is
                    // the inert-row failure the schema exists to prevent,
                    // reintroduced by the schema itself.
                    //
                    // `!== false` rather than `=== true` so a hand-written
                    // row in settings-extra.json that predates the field
                    // still shows up instead of silently vanishing.
                    root.settings = (parsed.settings || [])
                        .filter(function(row) { return row.panel !== false; });
                    root.configPath = String(parsed.path || "");
                    root.warnings = parsed.warnings || [];
                    // Clamp after a re-read: the list can get SHORTER than it
                    // was, because a --set re-reads settings-extra.json too
                    // and it may have been edited since the panel opened.
                    if (root.selectedIndex > root.settings.length - 1)
                        root.selectedIndex = Math.max(0, root.settings.length - 1);
                } catch (error) {
                    root.settings = [];
                    root.warnings = [];
                    root.statusText = "could not read island-settings.py --list";
                    root.statusIsError = true;
                }
            }
        }
    }

    // ---- THE WRITE, AND WHY THE Process IS BUILT FRESH ----
    //
    // The trap written up at length in ModeKeysLayer.qml: a REUSED Quickshell
    // Process with a StdioCollector hands back the PREVIOUS run's text on the
    // second and later runs. This panel reads the write's result, so on the
    // reused form the SECOND toggle would report the FIRST toggle's outcome —
    // and since the first one succeeds, a failing second write would show
    // "ok". Silently reporting success for a write that did not happen is the
    // worst available failure for a settings panel.
    //
    // Fresh pair per write, which is what actually fixed it there.
    property string pendingKey: ""
    property string pendingValue: ""

    function commit(key, value) {
        if (root.pendingKey !== "")
            return;
        root.pendingKey = String(key);
        root.pendingValue = String(value);
        root.statusText = "";
        root.statusIsError = false;
        writeLoader.active = false;
        writeLoader.active = true;
    }

    Loader {
        id: writeLoader
        active: false

        sourceComponent: Component {
            Process {
                command: ["python3", root.ctl, "--set", root.pendingKey, root.pendingValue]
                running: true
                stdout: StdioCollector {
                    onStreamFinished: {
                        let ok = false;
                        let message = "";
                        try {
                            const parsed = JSON.parse(text);
                            ok = parsed.ok === true;
                            message = String(parsed.error || "");
                        } catch (error) {
                            message = "island-settings.py produced no readable output";
                        }

                        root.pendingKey = "";
                        root.pendingValue = "";

                        if (!ok) {
                            root.statusText = message !== "" ? message : "write failed";
                            root.statusIsError = true;
                            // Re-read anyway, so the row snaps back to what is
                            // actually in the file rather than keeping the
                            // value the keypress implied.
                            listProcess.running = true;
                            return;
                        }

                        root.statusText = "saved";
                        root.statusIsError = false;

                        // The packaged backend does not watch the file, so
                        // without this the config is right and the island does
                        // not move — which is indistinguishable from the write
                        // having failed. ForkConfig.qml needs no equivalent:
                        // it has its own watcher.
                        root.userConfig.reload();
                        listProcess.running = true;
                    }
                }
            }
        }
    }

    // ---- CHANGING A VALUE ----
    //
    // One verb, three types. `delta` is +1 or -1: for a bool either sign
    // toggles (there are only two states and h/l meaning "the other one" is
    // what the hand expects), for an enum it steps the list, for an int it
    // adds a step. Enter is +1, which makes the common case — flipping a
    // switch — a single key.
    // ---- THE LIST EDITOR ----
    //
    // FORK: `list` is an ORDERED SUBSET, and it needs a sub-mode because it
    // is the only row type where one keystroke cannot express the change.
    // bool has two states, enum and int step along one axis — all three are
    // answered by h/l on the row itself. "Which of ten items, in which
    // order" is two questions, so it gets its own mode with its own cursor
    // and an explicit commit.
    //
    // Edited against a DRAFT rather than committing per keystroke. Every
    // other row in this panel writes on the key press, which is right when
    // the change is one value and instantly reversible. Here a single edit
    // is several presses — add three items, move one up twice — and writing
    // each intermediate state would put four or five half-finished readouts
    // through the island, each triggering a config reload. Escape therefore
    // means "throw the draft away", which it cannot mean anywhere else in
    // this panel.
    property bool listEditActive: false
    property int listCursor: 0
    property var listDraft: []

    function listBegin() {
        const entry = root.selected;
        if (!entry || entry.type !== "list")
            return;
        // slice() rather than assigning the model's array: QML hands out the
        // same JS array object the model holds, so mutating it in place would
        // edit the live row and leave Escape with nothing to restore.
        root.listDraft = (entry.value || []).slice();
        root.listCursor = 0;
        root.listEditActive = true;
    }

    function listCancel() {
        root.listEditActive = false;
        root.listDraft = [];
    }

    function listCommit() {
        const entry = root.selected;
        if (!entry) return;
        // Comma-separated, matching island-settings.py's `list` coercion. An
        // empty draft sends an empty string, which that end reads as the
        // empty list — a legal answer meaning "show nothing here".
        root.commit(entry.key, root.listDraft.join(","));
        root.listEditActive = false;
    }

    // ---- THE FONT PICKER ----
    //
    // A `font` row is 716 choices, which is an enum too large to page through
    // with h/l and not a string. So it opens a sub-mode with a filter, and the
    // filter is the theme picker's: `/` is not needed because the whole mode
    // IS the search, letters narrow, Backspace widens, and THERE IS NO
    // TextInput ANYWHERE.
    //
    // That last part is the entire reason this row can exist in this panel at
    // all. island-settings.py's note is right that a text field under a
    // Hyprland keyboard grab would swallow the next character typed into the
    // focused window — so the panel's own Keys handler owns the characters
    // instead, exactly as the theme picker and the wallpaper picker do, and
    // nothing is ever typed INTO a widget.
    //
    // The families come from fc-list rather than from the schema. A schema
    // that enumerated 716 values would put them in every `--list` response,
    // on every panel open, to answer a question only this sub-mode asks.
    property bool fontEditActive: false
    property int fontCursor: 0
    property string fontQuery: ""
    property var fontFamilies: []
    property bool fontListLoaded: false

    readonly property var fontMatches: {
        const needle = root.fontQuery.trim().toLowerCase();
        if (needle === "")
            return root.fontFamilies;
        const out = [];
        for (let i = 0; i < root.fontFamilies.length; i++) {
            if (root.fontFamilies[i].toLowerCase().indexOf(needle) >= 0)
                out.push(root.fontFamilies[i]);
        }
        return out;
    }

    function fontBegin() {
        const entry = root.selected;
        if (!entry || entry.type !== "font")
            return;
        root.fontQuery = "";
        root.fontEditActive = true;
        // Start on the family the row already holds, so opening the picker on
        // a set value and pressing Enter is a no-op rather than a silent
        // change to whatever happens to sort first.
        const current = String(entry.value || "");
        const at = root.fontFamilies.indexOf(current);
        root.fontCursor = at >= 0 ? at : 0;
        if (!root.fontListLoaded)
            fontListProcess.running = true;
    }

    function fontCancel() {
        root.fontEditActive = false;
        root.fontQuery = "";
    }

    function fontCommit() {
        const entry = root.selected;
        if (!entry)
            return;
        const matches = root.fontMatches;
        if (root.fontCursor < 0 || root.fontCursor >= matches.length) {
            // Nothing to commit is not an error and must not write: a query
            // with no matches would otherwise send an empty family, and
            // fontconfig resolves empty to Noto Sans CJK without complaining.
            root.fontCancel();
            return;
        }
        root.commit(entry.key, matches[root.fontCursor]);
        root.fontEditActive = false;
        root.fontQuery = "";
    }

    function fontMoveCursor(delta) {
        const matches = root.fontMatches;
        if (matches.length === 0)
            return;
        let next = root.fontCursor + delta;
        if (next < 0) next = 0;
        if (next > matches.length - 1) next = matches.length - 1;
        root.fontCursor = next;
        fontList.positionViewAtIndex(next, ListView.Contain);
    }

    // `fc-list : family` prints one line per FILE, comma-separated aliases,
    // with heavy duplication — 3000+ lines for 716 families on this machine.
    // Split, dedupe and sort here rather than in QML per keystroke.
    Process {
        id: fontListProcess
        command: ["sh", "-c",
                  "fc-list : family | tr ',' '\\n' | sed 's/^ *//; s/ *$//' | sort -u | grep -v '^$'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = String(text).split("\n").filter(l => l.length > 0);
                root.fontFamilies = lines;
                root.fontListLoaded = true;
                const entry = root.selected;
                if (entry && entry.type === "font") {
                    const at = lines.indexOf(String(entry.value || ""));
                    root.fontCursor = at >= 0 ? at : 0;
                    fontList.positionViewAtIndex(root.fontCursor, ListView.Contain);
                }
            }
        }
    }

    function listMoveCursor(delta) {
        const values = (root.selected && root.selected.values) || [];
        if (values.length === 0) return;
        let next = root.listCursor + delta;
        if (next < 0) next = values.length - 1;
        if (next > values.length - 1) next = 0;
        root.listCursor = next;
    }

    function listToggle() {
        const values = (root.selected && root.selected.values) || [];
        const item = values[root.listCursor];
        if (item === undefined) return;
        const draft = root.listDraft.slice();
        const at = draft.indexOf(item);
        if (at >= 0) draft.splice(at, 1);
        else draft.push(item);          // appended, so order is the order you added them
        root.listDraft = draft;
    }

    // Reorder within the draft. Operates on the item under the CANDIDATE
    // cursor, not on a second cursor over the draft — one cursor is enough
    // because an item's position in the draft is shown next to it, so you
    // can see what you are moving without looking somewhere else.
    function listShift(delta) {
        const values = (root.selected && root.selected.values) || [];
        const item = values[root.listCursor];
        if (item === undefined) return;
        const draft = root.listDraft.slice();
        const at = draft.indexOf(item);
        if (at < 0) return;             // not included; nothing to reorder
        const to = at + delta;
        if (to < 0 || to > draft.length - 1) return;
        draft.splice(at, 1);
        draft.splice(to, 0, item);
        root.listDraft = draft;
    }

    function change(delta) {
        const entry = root.selected;
        if (!entry || root.pendingKey !== "")
            return;

        if (entry.type === "font") {
            // Forward only, like `list`: `h` on a font row does nothing rather
            // than opening the same mode, so the two directions do not both
            // mean "enter".
            if (delta > 0)
                root.fontBegin();
            return;
        }

        if (entry.type === "list") {
            // Only forward (l / Enter / Space) opens it. `h` on a list row
            // does nothing rather than opening the same mode, so the two
            // directions do not both mean "enter", which on every other row
            // type they emphatically do not.
            if (delta > 0)
                root.listBegin();
            return;
        }

        if (entry.type === "bool") {
            root.commit(entry.key, entry.value === true ? "false" : "true");
            return;
        }

        if (entry.type === "enum") {
            const values = entry.values || [];
            if (values.length === 0)
                return;
            let index = values.indexOf(String(entry.value));
            if (index < 0) index = 0;
            index = (index + delta + values.length) % values.length;
            root.commit(entry.key, values[index]);
            return;
        }

        if (entry.type === "int") {
            const step = Number(entry.step || 1);
            let next = Number(entry.value) + delta * step;
            next = Math.max(Number(entry.min), Math.min(Number(entry.max), next));
            if (next === Number(entry.value))
                return;
            root.commit(entry.key, String(next));
            return;
        }
    }

    function move(delta) {
        if (root.settings.length === 0)
            return;
        let next = root.selectedIndex + delta;
        // Wraps, like every other list in this shell. See FORK-NOTES.md,
        // "the cursors wrap".
        if (next < 0) next = root.settings.length - 1;
        if (next > root.settings.length - 1) next = 0;
        root.selectedIndex = next;
        list.positionViewAtIndex(next, ListView.Contain);
    }

    Keys.onPressed: function(event) {
        // ---- THE FONT SUB-MODE OWNS THE KEYBOARD, LETTERS INCLUDED ----
        //
        // Ahead of everything else and returning early, for the reason the
        // wallpaper and theme pickers give: every navigation key in this panel
        // is a LETTER, and a font family is letters. "Inter" alone would hit
        // `t` — and on this panel `j`/`k` move the ROW selection, which is the
        // row the draft belongs to.
        //
        // This branch is also the whole reason a `font` row is renderable here
        // at all: the characters are consumed by a Keys handler, not by a
        // TextInput, so nothing competes with the Hyprland keyboard grab.
        if (root.fontEditActive) {
            if (event.key === Qt.Key_Escape) {
                root.fontCancel();
                event.accepted = true;
                return;
            }
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                root.fontCommit();
                event.accepted = true;
                return;
            }
            if (event.key === Qt.Key_Backspace) {
                root.fontQuery = root.fontQuery.slice(0, -1);
                root.fontCursor = 0;
                event.accepted = true;
                return;
            }
            // Arrows only. j/k are letters here and belong to the query.
            if (event.key === Qt.Key_Down) {
                root.fontMoveCursor(1);
                event.accepted = true;
                return;
            }
            if (event.key === Qt.Key_Up) {
                root.fontMoveCursor(-1);
                event.accepted = true;
                return;
            }
            if (event.key === Qt.Key_PageDown) {
                root.fontMoveCursor(10);
                event.accepted = true;
                return;
            }
            if (event.key === Qt.Key_PageUp) {
                root.fontMoveCursor(-10);
                event.accepted = true;
                return;
            }
            if (event.text && event.text.length === 1 && event.text >= " ") {
                root.fontQuery += event.text;
                // Back to the first match: the list has re-laid out under the
                // cursor entirely, so holding the old index would land on an
                // unrelated family.
                root.fontCursor = 0;
                event.accepted = true;
                return;
            }
            return;
        }

        // The list sub-mode owns the keyboard entirely while it is open, and
        // returns early rather than falling through. Sharing the switch below
        // would mean j/k moving the ROW selection out from under the draft —
        // and the draft belongs to the row you opened it on.
        if (root.listEditActive) {
            switch (event.key) {
            case Qt.Key_Escape:
                root.listCancel();          // the draft is discarded; see listBegin
                event.accepted = true;
                return;
            case Qt.Key_Return:
            case Qt.Key_Enter:
                root.listCommit();
                event.accepted = true;
                return;
            case Qt.Key_Space:
                root.listToggle();
                event.accepted = true;
                return;
            case Qt.Key_Down:
            case Qt.Key_J:
                // Shift is reorder, plain is move. J/K rather than a separate
                // pair of keys because "move the thing" and "move the cursor"
                // are the same gesture with and without a modifier, which is
                // the convention every list-reorder UI already uses.
                if ((event.modifiers & Qt.ShiftModifier) !== 0) root.listShift(1);
                else root.listMoveCursor(1);
                event.accepted = true;
                return;
            case Qt.Key_Up:
            case Qt.Key_K:
                if ((event.modifiers & Qt.ShiftModifier) !== 0) root.listShift(-1);
                else root.listMoveCursor(-1);
                event.accepted = true;
                return;
            default:
                // Swallowed on purpose. `q` must not close the panel from
                // inside the sub-mode with an uncommitted draft on screen.
                event.accepted = true;
                return;
            }
        }

        switch (event.key) {
        case Qt.Key_Escape:
        case Qt.Key_Q:
            root.closeRequested();
            event.accepted = true;
            break;
        case Qt.Key_Down:
        case Qt.Key_J:
            root.move(1);
            event.accepted = true;
            break;
        case Qt.Key_Up:
        case Qt.Key_K:
            root.move(-1);
            event.accepted = true;
            break;
        case Qt.Key_Left:
        case Qt.Key_H:
            root.change(-1);
            event.accepted = true;
            break;
        case Qt.Key_Right:
        case Qt.Key_L:
        case Qt.Key_Return:
        case Qt.Key_Enter:
        case Qt.Key_Space:
            root.change(1);
            event.accepted = true;
            break;
        case Qt.Key_G:
            root.selectedIndex = (event.modifiers & Qt.ShiftModifier) !== 0
                ? Math.max(0, root.settings.length - 1) : 0;
            list.positionViewAtIndex(root.selectedIndex, ListView.Contain);
            event.accepted = true;
            break;
        default:
            break;
        }
    }

    // ---- CHROME, SHARED ---- see qml/common/PanelChrome.qml.
    //
    // The header was "Island settings" at font(15) in heroFontFamily with
    // `color: IslandTheme.textPrimary`; instrument register now.
    PanelChrome {
        id: chrome
        textFontFamily: root.textFontFamily

        title: "island settings"

        // The path, on the panel. This surface edits a file that is also
        // edited by hand and by the packaged app, so which file it is is not
        // trivia — it is the first thing you need when the panel and the shell
        // disagree.
        status: root.statusText !== "" ? root.statusText : root.configPath
        statusLevel: root.statusIsError ? "error"
                   : (root.statusText !== "" ? "ok" : "idle")

        footerExtraHeight: root.warningHeight

        // The footer follows the mode. A hint row that advertises keys the
        // current mode does not answer is worse than no hint row — this
        // panel's own cheatsheet argument, applied to itself.
        // The footer follows the MODE. A hint row advertising keys the current
        // mode does not answer is worse than no hint row — and in the font
        // mode j/k are letters, which is precisely the lie that would make
        // someone conclude the panel is broken.
        hints: root.fontEditActive
            ? [
                { key: "type", label: "filter" },
                { key: "↑↓", label: "move" },
                { key: "Enter", label: "use" },
                { key: "Esc", label: "cancel" }
              ]
            : root.listEditActive
            ? [
                { key: "j/k", label: "move" },
                { key: "space", label: "toggle" },
                { key: "J/K", label: "reorder" },
                { key: "Enter", label: "save" },
                { key: "Esc", label: "cancel" }
              ]
            : [
                { key: "j/k", label: "move" },
                { key: "h/l", label: "change" },
                { key: "Enter", label: "change" },
                { key: "q", label: "close" }
              ]
    }

    ListView {
        id: list
        x: chrome.contentX
        y: chrome.contentY
        width: root.listWidth
        height: chrome.contentHeight
        clip: true
        model: root.settings
        currentIndex: root.selectedIndex
        // Unset default (-1/velocity-based) turns every currentIndex change
        // into Qt's own slow follow-scroll, uncoordinated with anything
        // this shell tunes. See ThemePickerLayer.qml's themeGrid for the
        // frame-capture measurement that found it.
        highlightMoveDuration: 0
        boundsBehavior: Flickable.StopAtBounds

        // FORK: P1-3. This list is 25 rows in a viewport that shows about
        // eight, it is driven entirely from the keyboard, and it drew nothing
        // at all to say so — the same silent fold that made "the settings
        // panel receives no keyboard input" look true for three runs when the
        // selection had simply scrolled below a cropped capture.
        ScrollBar.vertical: IslandScrollBar { view: list }

        delegate: PanelRow {
            id: rowItem
            required property int index
            required property var modelData

            readonly property bool isSelected: rowItem.index === root.selectedIndex

            width: list.width
            height: root.rowHeight

            // `active` is never set: a settings row is not in a state — the
            // VALUE carries that, in the right-hand column, where "on" is
            // already green. So the only mark here is the cursor, which also
            // moves this row off IslandTheme.selectionFill, the accent wash
            // this shell reserves for actual system state.
            selected: rowItem.isSelected

            onCursorRequested: root.selectedIndex = rowItem.index
            onActivated: root.change(1)

            Text {
                id: rowLabel
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: rowItem.modelData.label
                color: IslandTheme.textPrimary
                font.pixelSize: Metrics.font(12)
                font.family: root.textFontFamily
                font.weight: rowItem.isSelected ? Font.DemiBold : Font.Normal
                }

                // The value, right-aligned. Booleans read "on"/"off" rather
                // than "true"/"false": the file is JSON and the panel is not,
                // and "off" is the word the eye is scanning a settings list
                // for.
            Text {
                id: rowValue
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                // A list renders as its COUNT, not as its contents. The
                // value column is ~40% of a 52%-width list and
                // "cpu,battery,ram" already elides there; ten items would
                // be a row of ellipsis. The contents are one keypress
                // away in the editor, where they have room and an order.
                text: rowItem.modelData.type === "bool"
                    ? (rowItem.modelData.value === true ? "on" : "off")
                    : rowItem.modelData.type === "list"
                        ? ((rowItem.modelData.value || []).length + " items")
                        : String(rowItem.modelData.value)
                // There was a red case here for `forkPolkitAgentEnabled`
                // when ON — the one row that could supposedly take the
                // system's password prompts away. That row is gone (it
                // never did anything; see island-settings.py), so the
                // red is gone with it rather than sitting here waiting
                // for a key that will never arrive.
                color: rowItem.modelData.value === true ? IslandTheme.success : IslandTheme.textSecondary
                font.pixelSize: Metrics.font(12)
                font.family: root.textFontFamily
                font.weight: Font.DemiBold
            }

            // The MouseArea is PanelRow's; its two signals are wired above.
        }
    }

    // ---- DETAILS ----
    //
    // Every row's `detail` is the WHY, carried over from the `_key`
    // annotations in userconfig.json rather than newly written here: the file
    // is the record of these decisions and a second copy in a different place
    // would drift the first time one was revised. It is the reason the panel
    // is 860 px wide — a settings list of twelve switches with no explanation
    // of any of them is a list you change by trial and error.
    Column {
        id: details
        anchors.left: parent.left
        anchors.leftMargin: chrome.padX + root.listWidth + Metrics.pad(16)
        anchors.right: parent.right
        anchors.rightMargin: chrome.padX
        y: chrome.contentY + Metrics.px(2)
        spacing: Metrics.px(6)

        Row {
            id: titleRow
            spacing: Metrics.pad(8)

            Text {
                // ---- BOUNDED, because a Text is not clipped by its width ----
                //
                // Found auditing every island detail pane after the record
                // menu was reported as "over each other and out of the frame".
                // This one had no width and no elide, and a Qt Text with
                // neither paints its full contentWidth regardless of the
                // column it is in — so a long setting label ran out through
                // the right edge of the panel and under the chips beside it.
                //
                // Capped against what the two chips to the right actually
                // occupy, read off their own widths rather than guessed at, so
                // the label yields to them instead of overlapping them.
                width: Math.min(implicitWidth,
                                details.width - titleRow.spacing * 2
                                - scopeChip.width - sourceChip.width)
                elide: Text.ElideRight
                maximumLineCount: 1
                text: root.selected ? root.selected.label : ""
                color: IslandTheme.textPrimary
                font.pixelSize: Metrics.font(13)
                font.family: root.heroFontFamily
                font.weight: Font.DemiBold
            }

            // The scope chip. "fork" is the load-bearing one: it says the
            // packaged config app has no row for this key and cannot get
            // one, which is the difference between "I could also change this
            // in the other app" and "this is the only place it exists".
            Rectangle {
                id: scopeChip
                anchors.verticalCenter: parent.verticalCenter
                visible: root.selected !== null
                width: scopeLabel.implicitWidth + Metrics.pad(10)
                height: Metrics.px(16)
                radius: Metrics.px(5)
                color: (root.selected && root.selected.scope === "fork")
                    ? IslandTheme.selectionFill : IslandTheme.surfaceRaisedActive

                Text {
                    id: scopeLabel
                    anchors.centerIn: parent
                    text: root.selected
                        ? (root.selected.scope === "fork" ? "fork only" : "packaged")
                        : ""
                    color: (root.selected && root.selected.scope === "fork")
                        ? IslandTheme.accentText : IslandTheme.textSecondary
                    font.pixelSize: Metrics.font(9)
                    font.family: root.textFontFamily
                    font.weight: Font.Medium
                }
            }

            // The provenance chip, beside the scope chip and only when there
            // is something to say. `scope` answers "can the packaged app
            // change this too"; this answers "where did this ROW come from",
            // and they are different questions the moment settings-extra.json
            // exists. It matters most for "edited": that row's detail may be
            // the user's own words, so the reasoning it shows is no longer
            // necessarily the reasoning this repo recorded.
            Rectangle {
                id: sourceChip
                anchors.verticalCenter: parent.verticalCenter
                visible: root.selected !== null
                    && root.selected.source !== undefined
                    && root.selected.source !== "builtin"
                // Width is claimed even while INVISIBLE, which the label's cap
                // above depends on: an invisible Item still reports a width,
                // and a Row skips it. Reserving it means the label does not
                // grow and re-elide as chips come and go with the selection.
                width: sourceLabel.implicitWidth + Metrics.pad(10)
                height: Metrics.px(16)
                radius: Metrics.px(5)
                color: IslandTheme.warningFill

                Text {
                    id: sourceLabel
                    anchors.centerIn: parent
                    text: (root.selected && root.selected.source === "user")
                        ? "yours" : "edited"
                    color: IslandTheme.warning
                    font.pixelSize: Metrics.font(9)
                    font.family: root.textFontFamily
                    font.weight: Font.Medium
                }
            }
        }

        Text {
            width: details.width
            wrapMode: Text.WordWrap
            text: root.selected ? String(root.selected.detail || "") : ""
            // This was pink for the polkit row, whose detail was the only
            // one that claimed it could cost you something. With that row
            // removed no detail is a warning, so they are all neutral.
            color: IslandTheme.textSecondary
            font.pixelSize: Metrics.font(11)
            font.family: root.textFontFamily
            lineHeight: 1.25
        }

        // The key name, so the row can be found in the file it edits.
        Text {
            text: root.selected ? root.selected.key : ""
            color: IslandTheme.textDisabled
            font.pixelSize: Metrics.font(10)
            font.family: root.textFontFamily
        }
    }

    // ---- WARNINGS FROM settings-extra.json ----
    //
    // Amber, not red: nothing is broken. The built-in rows are all present
    // and working; some row the user's file asked for is not. Red here would
    // put the panel's most alarming colour on the least alarming failure.
    // It used to sit next to a red polkit row, which made the contrast the
    // argument; that row is gone and amber is still right on its own.
    //
    // Three lines and no more. The full list is `island-settings.py --check`,
    // which is where you would be anyway if you were fixing the file, and a
    // banner that can grow without limit eats the list it is reporting on.
    Text {
        id: warningBanner
        visible: root.warnings.length > 0
        // anchors.left AND anchors.right, not `x` plus anchors.right. With
        // only one horizontal anchor the Text keeps its implicitWidth, which
        // for one long line is far wider than the panel — wrapMode then has
        // nothing to wrap against and the string runs out past the rounded
        // left edge instead of onto a second line. This is what it did.
        anchors.left: parent.left
        anchors.leftMargin: chrome.padX
        anchors.right: parent.right
        anchors.rightMargin: chrome.padX
        anchors.bottom: parent.bottom
        // Sits in the room the chrome reserved for it, directly above the
        // hints — see PanelChrome.footerExtraHeight.
        anchors.bottomMargin: Metrics.chromeFooter()
        wrapMode: Text.WordWrap
        maximumLineCount: root.warningLines
        elide: Text.ElideRight
        text: root.warnings.length > 0
            ? "settings-extra.json: " + root.warnings.join("  ·  ")
              + (root.warnings.length > 3 ? "   (--check for all)" : "")
            : ""
        color: IslandTheme.warning
        font.pixelSize: Metrics.font(10)
        font.family: root.textFontFamily
        lineHeight: 1.2
    }

    // The key-hint Text that used to be here is `chrome.hints` now.

    // ---- THE LIST EDITOR OVERLAY ----
    //
    // Covers the whole panel rather than living in the detail column. The
    // detail column is 48% of the width and this needs ten rows with an
    // order badge on each; squeezed in there it would be the same mistake
    // the control centre's first tile grid made. It is a MODE, so it looks
    // like one.
    // ---- THE FONT PICKER OVERLAY ----
    //
    // A MODE, so it looks like one — same full-panel treatment the list editor
    // uses and for the same reason: this needs a scrolling list of hundreds
    // and the detail column is 48% of the width.
    //
    // Note what is NOT here: a TextInput. The query is drawn as text and
    // built by the Keys handler above. See the note there.
    Rectangle {
        id: fontEditor
        anchors.fill: parent
        visible: root.fontEditActive
        color: IslandTheme.surface
        opacity: root.fontEditActive ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: Motion.controlDuration() }
        }

        // Swallows clicks so a stray press does not reach the rows behind the
        // overlay and move the selection this draft is anchored to.
        MouseArea { anchors.fill: parent }

        Text {
            id: fontTitle
            x: chrome.contentX
            y: Metrics.pad(11)
            text: root.selected ? root.selected.label : ""
            color: IslandTheme.textPrimary
            font.pixelSize: Metrics.font(15)
            font.family: root.heroFontFamily
            font.weight: Font.DemiBold
        }

        // The query and the match count, both load-bearing for the reason the
        // wallpaper picker records: a search with nothing on screen is
        // indistinguishable from a stuck keyboard, and the count is what
        // separates "no such family" from "you typo'd". Red at zero.
        Text {
            anchors.left: fontTitle.right
            anchors.leftMargin: Metrics.pad(8)
            anchors.baseline: fontTitle.baseline
            text: {
                if (!root.fontListLoaded)
                    return "reading families…";
                const q = root.fontQuery === "" ? "" : "/" + root.fontQuery + "   ";
                return q + root.fontMatches.length + " of " + root.fontFamilies.length;
            }
            color: (root.fontListLoaded && root.fontMatches.length === 0)
                ? IslandTheme.danger : IslandTheme.textMuted
            font.pixelSize: Metrics.font(10)
            font.family: root.textFontFamily
        }

        ListView {
            id: fontList
            x: chrome.contentX
            y: chrome.contentY
            width: chrome.contentWidth
            height: chrome.contentHeight
            clip: true
            model: root.fontMatches
            currentIndex: root.fontCursor
            // Unset default (-1/velocity-based) turns every currentIndex
            // change into Qt's own slow follow-scroll, uncoordinated with
            // anything this shell tunes. See ThemePickerLayer.qml's
            // themeGrid for the frame-capture measurement that found it.
            highlightMoveDuration: 0
            boundsBehavior: Flickable.StopAtBounds
            spacing: Metrics.px(1)

            ScrollBar.vertical: IslandScrollBar { view: fontList }

            Text {
                anchors.centerIn: parent
                visible: root.fontListLoaded && root.fontMatches.length === 0
                text: "no family matches " + root.fontQuery
                color: IslandTheme.textDisabled
                font.pixelSize: Metrics.font(11)
                font.family: root.textFontFamily
            }

            delegate: PanelRow {
                id: fontRow
                required property int index
                required property var modelData

                width: fontList.width
                height: Metrics.px(26)

                // `active` is the family the row currently HOLDS — a fact
                // about the system — and `selected` is the cursor. Opening the
                // picker on a set value shows both on the same row, which is
                // exactly the state PanelRow was built to render legibly.
                active: root.selected
                    && String(fontRow.modelData) === String(root.selected.value)
                selected: fontRow.index === root.fontCursor

                onCursorRequested: root.fontCursor = fontRow.index
                onActivated: root.fontCommit()

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width * 0.5
                    elide: Text.ElideRight
                    text: String(fontRow.modelData)
                    color: IslandTheme.textPrimary
                    font.pixelSize: Metrics.font(12)
                    font.family: root.textFontFamily
                }

                // ---- THE PREVIEW IS THE POINT ----
                //
                // A font list that does not show the fonts is a list of
                // strings. This is the one thing the GTK app's Gtk.FontDialog
                // gives for free and the reason a bare filtered list would
                // have been a worse answer than no row at all.
                //
                // Latin only, deliberately: every family name in fc-list is
                // Latin and the sample is fixed ASCII, so this cannot map a
                // CJK or Arabic face by shaping it. That is the `"Ag国"`
                // lesson — a visible Text is still a shaped Text.
                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width * 0.45
                    horizontalAlignment: Text.AlignRight
                    elide: Text.ElideRight
                    text: "Ag 0123"
                    color: IslandTheme.textSecondary
                    font.pixelSize: Metrics.font(13)
                    font.family: String(fontRow.modelData)
                }
            }
        }
    }

    Rectangle {
        id: listEditor
        anchors.fill: parent
        visible: root.listEditActive
        color: IslandTheme.surface
        opacity: root.listEditActive ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: Motion.controlDuration() }
        }

        // Swallows clicks so a stray press does not reach the rows behind
        // the overlay and move a selection the draft is anchored to.
        MouseArea { anchors.fill: parent }

        Text {
            id: editorTitle
            x: chrome.contentX
            y: Metrics.pad(11)
            text: root.selected ? root.selected.label : ""
            color: IslandTheme.textPrimary
            font.pixelSize: Metrics.font(15)
            font.family: root.heroFontFamily
            font.weight: Font.DemiBold
        }

        Text {
            anchors.left: editorTitle.right
            anchors.leftMargin: Metrics.pad(8)
            anchors.baseline: editorTitle.baseline
            text: root.listDraft.length + " shown, left to right"
            color: IslandTheme.textMuted
            font.pixelSize: Metrics.font(10)
            font.family: root.textFontFamily
        }

        Column {
            x: chrome.contentX
            y: chrome.contentY
            width: chrome.contentWidth
            spacing: Metrics.px(1)

            Repeater {
                model: (root.selected && root.selected.values) || []

                delegate: Item {
                    id: cand
                    required property int index
                    required property string modelData

                    readonly property int orderAt: root.listDraft.indexOf(cand.modelData)
                    readonly property bool included: cand.orderAt >= 0
                    readonly property bool isCursor: root.listCursor === cand.index

                    width: parent.width
                    height: Metrics.px(22)

                    Rectangle {
                        anchors.fill: parent
                        radius: Metrics.px(6)
                        color: cand.isCursor ? IslandTheme.selectionFill : "transparent"
                        border.width: cand.isCursor ? 1 : 0
                        border.color: IslandTheme.selectionBorder
                    }

                    // The order badge IS the inclusion state — a number when
                    // in, a dash when out. A separate tick plus a separate
                    // number would be two marks for one fact, and the number
                    // is the one that carries more.
                    Text {
                        id: badge
                        x: Metrics.pad(8)
                        anchors.verticalCenter: parent.verticalCenter
                        width: Metrics.px(18)
                        text: cand.included ? String(cand.orderAt + 1) : "–"
                        color: cand.included ? IslandTheme.accentText : IslandTheme.textDisabled
                        font.pixelSize: Metrics.font(11)
                        font.family: root.textFontFamily
                        font.weight: Font.DemiBold
                    }

                    Text {
                        anchors.left: badge.right
                        anchors.leftMargin: Metrics.pad(6)
                        anchors.verticalCenter: parent.verticalCenter
                        text: cand.modelData
                        color: cand.included ? IslandTheme.textPrimary : IslandTheme.textMuted
                        font.pixelSize: Metrics.font(12)
                        font.family: root.textFontFamily
                    }
                }
            }
        }
    }
}
