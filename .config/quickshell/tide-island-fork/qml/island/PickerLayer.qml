pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io

// FORK: the shared scale factor — see qml/common/Metrics.js.
import "../common/Metrics.js" as Metrics
// FORK: the shared motion system — one spring for geometry, one
// critically damped curve for opacity. See qml/common/Motion.js.
import "../common/Motion.js" as Motion
import "../common"

//
// FORK — new file. The GENERIC LIST PICKER.
//
// WHY THIS IS ONE PANEL AND NOT THREE
// -----------------------------------
// The rofi chord ($mod P, hypr/submaps.conf) reached about twenty scripts.
// Most of them are the same program written twenty times: build a list,
// pipe it to rofi, read one line back, act on it. Three of those — close a
// window, kill a process, go to a workspace — are already ports waiting to
// happen, and porting them as three QML files would mean three copies of
// "list with a search field and a details column", which this shell has
// enough of already (settings, theme picker, cheatsheet).
//
// So the panel knows nothing about windows, processes or workspaces. It
// knows about `--list` and `--run`. Everything specific lives in
// hypr/scripts/island-picker.py and a fourth menu costs a function there
// and a bind, not a file here.
//
// THE PANEL NEVER SEES A COMMAND, AND THAT IS DELIBERATE
// -----------------------------------------------------
// island-picker.py's docstring makes the same point from its side: an item
// is {id, label, detail} and the id goes back to the script, which decides
// what it means. A panel that executed strings handed to it by a script
// would execute whatever anything could write into that script's stdout.
// This is why there is no `exec` property on an item and no code path here
// that builds a command out of model data.
//
// WHERE THE SHAPE COMES FROM
// --------------------------
// SettingsLayer.qml, almost line for line: list on the left, details on
// the right, a footer hint, j/k that wrap, q/Esc to close. The one addition
// is the search field, taken from ApplicationLauncherLayer.qml — and it is
// the reason the key handling below is more complicated than settings',
// because a panel you can type into cannot spend `j` and `k` on movement
// unconditionally. See "THE j/k PROBLEM".
//
FocusScope {
    id: root

    signal closeRequested

    property bool showCondition: false
    property string textFontFamily: ""
    property string heroFontFamily: ""
    property string iconFontFamily: ""

    // Which menu island-picker.py should build: windows | processes |
    // workspaces. Set by DynamicIslandWindow BEFORE the state flips, so the
    // Loader's first fetch is already for the right menu (same ordering
    // showCheatsheet uses for `cheatsheetWhich`).
    property string menu: "windows"

    readonly property string ctl: Quickshell.env("HOME") + "/.config/hypr/scripts/island-picker.py"

    // ---- THE PAGE STACK ----
    //
    // Everything below the first five menus is a CONVERSATION: pick a
    // screenshot area, then say where it goes; type a sentence, then pick
    // which mistake to fix; walk a directory tree. The first version of this
    // panel could not express that and island-picker.py's header said so —
    // it concluded that a one-shot list was "the wrong primitive for a
    // conversation" and left four menus on rofi.
    //
    // The conclusion was wrong and the fix is two lines of protocol: --run
    // may answer {"ok":true,"page":{…}} instead of {"ok":true}, and this
    // holds a stack of the pages it has been given. Escape still closes;
    // Backspace on an empty field pops one page.
    //
    // What this panel deliberately still does NOT know: what any page means.
    // It does not know that `confedit` is a filesystem or that `spellcheck`
    // is holding a sentence between pages. A page is {title, mode, items,
    // …} and an item is still {id, label, detail}; the id goes back and the
    // script decides. That is the same rule as before, and it is the reason
    // a stack is safe to add — a stack of opaque pages is still opaque.
    //
    // The stack is NOT a history for re-running: popping restores a page
    // this panel already has in memory, so going back never re-executes
    // anything. That matters for `pass`, where "back" must not mean "read
    // the secret again".
    property var pageStack: []
    readonly property var page: root.pageStack.length > 0
        ? root.pageStack[root.pageStack.length - 1] : null

    // list | prompt | message. The panel's whole behaviour keys off this and
    // nothing else; a menu changes shape by sending a different mode, not by
    // this file learning its name.
    readonly property string mode: root.page && root.page.mode !== undefined
        ? String(root.page.mode) : "list"
    readonly property var items: root.page && root.page.items !== undefined
        ? root.page.items : []
    readonly property string title: root.page && root.page.title !== undefined
        ? String(root.page.title) : ""
    readonly property string note: root.page && root.page.note !== undefined
        ? String(root.page.note) : ""

    property bool loading: false
    property string query: ""
    property int selectedIndex: 0
    property string statusText: ""
    property bool statusIsError: false

    // Set for the duration of a `menu` re-target (the `hub` menu's rows do
    // this). Without it, assigning root.menu fires onMenuChanged, which
    // re-fetches --list for the new menu and throws away the page the script
    // just handed us — the hub would flash the right panel and then replace
    // it with an identical one, at the cost of a second subprocess.
    property bool retargeting: false

    // ---- THE FILTER ----
    //
    // "Fuzzy-ish", and the -ish is the whole of it: this is a SUBSEQUENCE
    // match over the label and the detail joined, not a scored fuzzy match
    // like fzf's. Two reasons it stops there.
    //
    //   1. The lists are small. `windows` is ten rows on this session,
    //      `workspaces` is three, `processes` is capped at 40 by the script.
    //      Ranking exists to make a thousand candidates usable; over ten
    //      rows it only means the row you were looking at moves while you
    //      type, which is worse than no ranking at all.
    //   2. A subsequence match over label+detail already gets the query
    //      that matters. "brw5" finds the Brave window on workspace 5
    //      because the workspace number is in the DETAIL — the search
    //      crosses both fields, which a label-only match would not.
    //
    // Order is preserved from the script (windows alphabetical, workspaces
    // numeric, processes by RSS), so the list never reshuffles under the
    // cursor — it only gets shorter.
    // 2 = the query is a literal substring, 1 = subsequence only, 0 = no
    // match. Not a score: three buckets, and the order inside a bucket is
    // whatever the script sent.
    function matchRank(item, needle) {
        if (needle === "")
            return 4;
        const label = (item.label || "").toLowerCase();
        const hay = (label + " " + (item.detail || "")).toLowerCase();
        // ---- WHY THE LABEL OUTRANKS THE DETAIL ----
        //
        // Reported as a case-sensitivity bug -- "I type c and Clipboard does
        // not come up" -- and it is not one: both sides have been lowercased
        // since this was written. The real cause is that `hay` is label AND
        // detail, so on the screenshot menu's Destination page all three
        // rows tied at 2 for the query "c":
        //
        //     File       detail "/home/ati/Screenshots"   <- the c is here
        //     Clipboard  label starts with it
        //     Both       detail "file and clipboard"      <- and here
        //
        // A tie keeps the script's order, so File stayed first and Enter ran
        // it. The row whose NAME you typed lost to two rows that happened to
        // spell the letter somewhere in a path.
        //
        // Four buckets instead of two. Still not a score -- order inside a
        // bucket is whatever the script sent, so the list does not reshuffle
        // under the cursor beyond the one regrouping the keystroke caused.
        if (label.startsWith(needle))
            return 4;
        if (label.includes(needle))
            return 3;
        if (hay.includes(needle))
            return 2;
        // Otherwise: every character of the needle, in order, somewhere in
        // the haystack. Spaces are skipped so "qute 2" and "qute2" are the
        // same query — a space in a query is a word separator to a person,
        // never a character to be found.
        let at = 0;
        for (const ch of needle) {
            if (ch === " ")
                continue;
            at = hay.indexOf(ch, at);
            if (at < 0)
                return 0;
            at += 1;
        }
        return 1;
    }

    // ---- WHY THERE ARE TWO PASSES AND NOT ONE ----
    //
    // The first version was one pass and a boolean `matches()`, which kept
    // the script's order for everything that matched. Since the cursor
    // resets to 0 on every keystroke (see onFilteredChanged), whatever is
    // first is what Enter runs, and "first" was "alphabetically first among
    // everything that matched at all".
    //
    // THE MEASUREMENT THAT PROMPTED THIS WAS MISREAD, and the misreading is
    // worth keeping because the conclusion survived it and the reasoning did
    // not. Against the real `windows` list on this session:
    //
    //     "brave" -> ChatGPT | Reacher (2022) … - Brave | web.whatsapp.com
    //
    // which was read as "two coincidental subsequence hits outranking the
    // literal one". It is not: all three rows literally contain "brave",
    // because the search covers the DETAIL and the detail carries the window
    // class — ChatGPT's is "brave-chat.openai.com__-Chatgpt" and WhatsApp's
    // is "brave-web.whatsapp.com__-Whatsapp". Every browser-wrapped webapp
    // on this system shares that prefix, so "brave" is a genuinely ambiguous
    // query and no ranking rescues it. Two passes changes that line NOT AT
    // ALL.
    //
    // What it does change, measured on the same list:
    //
    //     "ank"  one pass -> ChatGPT | Reacher … | Qtile … | User 1 - Anki
    //            two pass -> User 1 - Anki | ChatGPT | Reacher … | Qtile …
    //
    // "Anki" is the only literal hit and it was LAST of four, so Enter after
    // typing the exactly right query closed ChatGPT.
    //
    // Two passes, substring bucket first, fixes that without introducing a
    // score: rows still cannot overtake each other WITHIN a bucket, so the
    // list still does not reshuffle under the cursor as you type. That was
    // the reason for not ranking in the first place, and it survives.
    readonly property var filtered: {
        const needle = root.query.trim().toLowerCase();
        const strong = [];
        const weak = [];
        for (const item of root.items) {
            const rank = root.matchRank(item, needle);
            if (rank === 2)
                strong.push(item);
            else if (rank === 1)
                weak.push(item);
        }
        return strong.concat(weak);
    }

    readonly property var selected:
        (root.selectedIndex >= 0 && root.selectedIndex < root.filtered.length)
            ? root.filtered[root.selectedIndex] : null

    // Any change to the filter invalidates the cursor: the row it was on may
    // not be in the list any more, and leaving the index where it was means
    // Enter runs whatever slid into that position. Back to the top, which is
    // also where the best match is when you have just typed one.
    onFilteredChanged: {
        if (root.selectedIndex > root.filtered.length - 1)
            root.selectedIndex = 0;
    }

    // FORK: header height, content inset and the key-hint strip are
    // PanelChrome's now. See qml/common/PanelChrome.qml.
    readonly property real searchHeight: Metrics.px(26)
    readonly property real rowHeight: Metrics.px(30)

    // ---- WHY THE HEIGHT IS COMPUTED FROM `items` AND NOT `filtered` ----
    //
    // Sizing to the FILTERED count is the obvious thing and it is wrong for
    // exactly the reason CheatsheetLayer went to a fixed frame: the panel
    // would change height on every keystroke, so the search field — the one
    // element that must stay under your eyes while you type — would walk up
    // and down the screen as the list narrowed.
    //
    // Sizing to the unfiltered count instead keeps the frame still for the
    // whole of one open, and it is still content-sized between menus:
    // `workspaces` (3 rows) does not get the height `processes` (40) needs.
    //
    // The 11-row cap is the other half. 40 process rows at 30 px is 1200 px
    // of panel on a 768 px screen; the window clamps that to
    // screen.height - 60 anyway, but doing it here means the LIST is what
    // scrolls rather than the panel being silently truncated by the clamp
    // with its own footer off the bottom of the screen.
    readonly property int maxVisibleRows: 11
    // A prompt and a message have no list, so they must not be given a row's
    // worth of height "just in case": a one-field panel that is eleven rows
    // tall is a panel with a hole in it.
    readonly property int visibleRows: root.mode === "list"
        ? Math.max(1, Math.min(root.maxVisibleRows, root.items.length)) : 0
    readonly property real noteHeight:
        root.note === "" ? 0 : noteLabel.implicitHeight + Metrics.pad(8)
    // Metrics and not chrome.chromeHeight: this sizes the capsule the panel is
    // drawn inside, so reading it off a child of that panel is a loop waiting
    // for one more term.
    readonly property real preferredHeight:
        Metrics.chromeTotal() + root.searchHeight + Metrics.pad(8)
        + root.noteHeight
        + root.visibleRows * root.rowHeight

    readonly property real listWidth: Math.round(root.width * 0.54)

    focus: showCondition
    activeFocusOnTab: true
    anchors.fill: parent
    opacity: showCondition ? 1 : 0
    visible: opacity > 0.01

    // FORK: one choreography for every layer in the shell. See Motion.js.
    Behavior on opacity {
        SequentialAnimation {
            // The delay is what keeps the content from being painted inside
            // a capsule that is still the wrong size for it.
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

    // ---- FETCHING: A FRESH Process EVERY TIME ----
    //
    // The trap written up at length in ModeKeysLayer.qml and obeyed again in
    // CheatsheetLayer and SettingsLayer: a REUSED Quickshell Process with a
    // StdioCollector hands back the PREVIOUS run's text on the second and
    // later runs. It would be worse here than anywhere else it has bitten,
    // because this panel's rows are VOLATILE — a stale `windows` list is a
    // list of window addresses that may no longer exist, and Enter on one of
    // those closes nothing while looking like it closed something. A stale
    // `processes` list is worse still: pids are reused.
    //
    // Toggling the Loader off and on is what destroys the old pair. The
    // `active = false` is not redundant with the assignment that follows —
    // a Loader that is already active does not rebuild for a source that has
    // not changed, which would quietly reinstate the reuse this avoids.
    function refresh() {
        root.loading = true;
        root.pageStack = [];
        listLoader.active = false;
        listLoader.active = true;
    }

    // ---- APPLYING A PAGE ----
    //
    // `stack` says what the page does to the stack, and the three values are
    // each earning their place:
    //
    //   push    (default) — a step deeper. Backspace comes back.
    //   replace          — the spell-checker after a fix, and the translator
    //                      after a language change. The page you came from
    //                      describes text that no longer exists, so keeping
    //                      it on the stack means Backspace goes to a list of
    //                      mistakes in a sentence that has been rewritten.
    //   root             — a mutation finished (note saved, task toggled).
    //                      The whole stack is stale for the same reason.
    function applyPage(incoming, fallbackStack) {
        if (!incoming)
            return;
        const how = String(incoming.stack !== undefined ? incoming.stack
                                                        : (fallbackStack || "push"));

        if (incoming.menu !== undefined && String(incoming.menu) !== root.menu) {
            root.retargeting = true;
            root.menu = String(incoming.menu);
            root.retargeting = false;
        }

        let next = root.pageStack.slice();
        if (how === "root" || next.length === 0)
            next = [incoming];
        else if (how === "replace")
            next[next.length - 1] = incoming;
        else
            next.push(incoming);
        root.pageStack = next;
        root.settleField();
    }

    // A prompt page's field starts holding its prefill; every other page's
    // field starts empty, because on a list page the field is the FILTER and
    // carrying the last page's query into a new list is how you arrive at
    // "no match" for something you did not type.
    function settleField() {
        const current = root.page;
        const prefill = (current && String(current.mode || "list") === "prompt")
            ? String(current.value || "") : "";
        searchInput.text = prefill;
        root.query = prefill;
        root.selectedIndex = 0;
        root.statusText = "";
        root.statusIsError = false;
    }

    // Returns whether it actually went anywhere, so the key handler can let
    // Backspace fall through to the field when there is nothing to pop.
    function popPage() {
        if (root.pageStack.length < 2)
            return false;
        root.pageStack = root.pageStack.slice(0, root.pageStack.length - 1);
        root.settleField();
        return true;
    }

    // ---- WHY THE OPEN IS IN A FUNCTION AND CALLED FROM TWO PLACES ----
    //
    // The obvious single hook is onShowConditionChanged, and on its own it
    // is WRONG on the open that matters most — the first one. PanelLoader
    // mounts this item only once `live` is already true, and `showCondition`
    // is BOUND to that same boolean, so at construction the property is
    // already 1 and the change handler never fires. The panel would come up
    // with an empty list and no keyboard focus, and the only way to make it
    // fetch would be to close and reopen it inside PanelLoader's fade-out
    // hold window — i.e. it would look like it worked intermittently.
    //
    // So: Component.onCompleted covers the mount, onShowConditionChanged
    // covers a reopen that catches the item still alive on the hold timer
    // (see PanelLoader.qml — the item outlives its own dismissal by
    // fadeOutDuration + 40 ms so its out-fade can actually run).
    function openReset() {
        root.statusText = "";
        root.statusIsError = false;
        root.query = "";
        searchInput.text = "";
        root.selectedIndex = 0;
        root.refresh();
        root.grabKeyboardFocus();
    }

    Component.onCompleted: {
        if (root.showCondition)
            root.openReset();
    }

    onShowConditionChanged: {
        if (showCondition)
            root.openReset();
    }

    // Changing menus while the panel is open (there is no key for it today,
    // but the IPC can) re-fetches rather than filtering the old rows.
    onMenuChanged: {
        if (root.showCondition && !root.retargeting)
            root.refresh();
    }

    Loader {
        id: listLoader
        active: false

        sourceComponent: Component {
            Process {
                command: ["python3", root.ctl, "--list", root.menu]
                running: true
                stdout: StdioCollector {
                    onStreamFinished: {
                        root.loading = false;
                        try {
                            const parsed = JSON.parse(text);
                            if (parsed.title === undefined)
                                parsed.title = root.menu;
                            root.applyPage(parsed, "root");
                            if (parsed.error !== undefined) {
                                root.statusText = String(parsed.error);
                                root.statusIsError = true;
                            }
                        } catch (error) {
                            // A menu that cannot be read says so rather than
                            // opening blank. A blank picker is
                            // indistinguishable from a picker with nothing
                            // in it, and "no windows open" and "the script
                            // is broken" want different reactions.
                            root.applyPage({ "title": root.menu, "items": [] }, "root");
                            root.statusText = "island-picker.py --list " + root.menu
                                + " produced no readable output";
                            root.statusIsError = true;
                        }
                        if (root.selectedIndex > root.filtered.length - 1)
                            root.selectedIndex = 0;
                    }
                }
            }
        }
    }

    // ---- RUNNING ----
    //
    // A second fresh-per-invocation pair, for the same reason and one more:
    // this one reads the RESULT. On a reused Process the second run of the
    // session would report the first run's {"ok":true} — so a failed kill
    // would print "done" — which is the same failure mode SettingsLayer
    // calls the worst available one for a panel that writes.
    //
    // `pendingId` also serves as the in-flight guard: Enter twice on the
    // same row must not fire twice. For `workspaces` that would be harmless
    // and for `processes` it means two SIGTERMs, the second one landing on
    // whatever inherited the pid.
    property string pendingId: ""
    // The typed text, passed as ONE argv element however many spaces it
    // holds. Always sent, empty on a list page: an optional trailing
    // argument that is sometimes absent is how argv[4] becomes argv[3]'s
    // problem, and island-picker.py reads it positionally.
    property string pendingText: ""

    function runSelected() {
        const item = root.selected;
        if (!item || root.pendingId !== "")
            return;
        root.pendingId = String(item.id);
        root.pendingText = "";
        root.statusText = "";
        root.statusIsError = false;
        runLoader.active = false;
        runLoader.active = true;
    }

    // Enter on a prompt page. The submit id comes from the page, not from a
    // row — a prompt has no rows — and it is the same `id` contract: the
    // script named the id when it built the page and knows what it means.
    function submitPrompt() {
        const current = root.page;
        if (!current || current.submit === undefined || root.pendingId !== "")
            return;
        root.pendingId = String(current.submit);
        root.pendingText = searchInput.text;
        root.statusText = "working…";
        root.statusIsError = false;
        runLoader.active = false;
        runLoader.active = true;
    }

    Loader {
        id: runLoader
        active: false

        sourceComponent: Component {
            Process {
                command: ["python3", root.ctl, "--run", root.menu,
                          root.pendingId, root.pendingText]
                running: true
                stdout: StdioCollector {
                    onStreamFinished: {
                        let ok = false;
                        let message = "";
                        let nextPage = null;
                        try {
                            const parsed = JSON.parse(text);
                            ok = parsed.ok === true;
                            message = String(parsed.error || "");
                            if (parsed.page !== undefined && parsed.page !== null)
                                nextPage = parsed.page;
                        } catch (error) {
                            message = "island-picker.py produced no readable output";
                        }
                        root.pendingId = "";
                        root.pendingText = "";

                        if (!ok) {
                            root.statusText = message !== "" ? message : "failed";
                            root.statusIsError = true;
                            // Stay open on failure. Re-read ONLY at the root
                            // of the stack, and that restriction is the
                            // whole change here: the list is the evidence
                            // when a window was already gone, but a refresh
                            // rebuilds the stack from --list, so doing it
                            // three pages into a directory walk would answer
                            // "that file is gone" by teleporting you to the
                            // top of ~/.config.
                            if (root.pageStack.length <= 1)
                                root.refresh();
                            return;
                        }

                        // A page means the conversation continues. No page
                        // means the verb is done, and closing on a finished
                        // verb is the rofi behaviour these menus are ported
                        // from: a picker that stayed open after `workspace
                        // 5` would be a panel sitting on top of the
                        // workspace you just asked to look at.
                        if (nextPage !== null) {
                            root.applyPage(nextPage, "push");
                            root.grabKeyboardFocus();
                            return;
                        }
                        root.closeRequested();
                    }
                }
            }
        }
    }

    Timer {
        id: focusTimer
        interval: 0
        repeat: false
        onTriggered: root.grabKeyboardFocus()
    }

    // Two-step, like CheatsheetLayer: the FocusScope has to own the focus
    // before the field inside it can, or the field gets active focus in a
    // scope that does not have it and no keystrokes arrive.
    function grabKeyboardFocus() {
        root.forceActiveFocus();
        searchInput.forceActiveFocus();
    }

    function move(delta) {
        if (root.filtered.length === 0)
            return;
        let next = root.selectedIndex + delta;
        // Wraps, like every other list in this shell. See FORK-NOTES.md,
        // "the cursors wrap".
        if (next < 0) next = root.filtered.length - 1;
        if (next > root.filtered.length - 1) next = 0;
        root.selectedIndex = next;
        list.positionViewAtIndex(next, ListView.Contain);
    }

    // ---- CHROME, SHARED ---- see qml/common/PanelChrome.qml.
    PanelChrome {
        id: chrome
        textFontFamily: root.textFontFamily

        // The script owns the title ("Close window", "Kill process"), not this
        // file. The title is the sentence the Enter key completes, so it
        // belongs beside the code that decides what Enter does.
        title: root.title !== "" ? root.title : root.menu

        // The row count is meaningless on a page with no rows, and "0 of 0"
        // beside a question reads as a failure. Depth is what a prompt page
        // can usefully report instead — it is the only thing on screen that
        // says Backspace has somewhere to go.
        status: root.statusText !== "" ? root.statusText
            : (root.loading ? "reading…"
                : (root.mode === "list"
                    ? root.filtered.length + " of " + root.items.length
                    : (root.pageStack.length > 1 ? "step " + root.pageStack.length : "")))
        statusLevel: root.statusIsError ? "error" : (root.loading ? "busy" : "idle")

        // The hints CHANGE with the query, because the keys change with it —
        // see THE j/k PROBLEM above. A static "j/k move" would be a lie the
        // moment you typed a character, and a hint that lies is worse than no
        // hint: it is the reason you conclude the panel is broken. They change
        // with the MODE for the same reason: on a prompt page j/k are letters
        // and Enter submits.
        hints: {
            if (root.mode === "prompt") {
                const h = [{ key: "Enter", label: "submit" }];
                if (root.pageStack.length > 1)
                    h.push({ key: "Ctrl+h", label: "back" });
                h.push({ key: "Esc", label: "close" });
                return h;
            }
            if (root.query === "") {
                const h = [
                    { key: "j/k", label: "move" },
                    { key: "Enter", label: "run" },
                    { key: "type", label: "filter" }
                ];
                if (root.pageStack.length > 1)
                    h.push({ key: "BkSp", label: "back" });
                h.push({ key: "q", label: "close" });
                return h;
            }
            return [
                { key: "↑/↓", label: "move" },
                { key: "Ctrl+n/p", label: "move" },
                { key: "Enter", label: "run" },
                { key: "Esc", label: "close" }
            ];
        }
    }

    // ---- THE SEARCH FIELD ----
    //
    // Taken from ApplicationLauncherLayer's, at the cheatsheet's size: this
    // panel's field sits above a list rather than being the whole of the
    // surface, so the launcher's 46 px pill would be the loudest thing on a
    // panel whose subject is the list.
    Rectangle {
        id: searchField
        x: chrome.contentX
        y: chrome.contentY
        width: chrome.contentWidth
        height: root.searchHeight
        radius: Metrics.px(8)
        color: searchInput.activeFocus ? IslandTheme.inputFillFocused : IslandTheme.inputFill
        border.width: 1
        border.color: searchInput.activeFocus ? IslandTheme.inputBorderFocused : IslandTheme.inputBorder

        Behavior on color { ColorAnimation { duration: 140 } }
        Behavior on border.color { ColorAnimation { duration: 140 } }

        Text {
            id: searchIcon
            anchors.left: parent.left
            anchors.leftMargin: Metrics.pad(10)
            anchors.verticalCenter: parent.verticalCenter
            // The glyph is the mode indicator, and it is the only one
            // there is: the field looks identical whether it filters a
            // list or holds an answer, and "am I searching or am I
            // typing an answer" is the one thing you must not have to
            // guess. Magnifier for a filter, chevron for a prompt,
            // padlock when the prompt masks what you type.
            text: root.mode !== "prompt" ? ""
                : (root.page && root.page.secret === true ? "" : "")
            color: searchInput.activeFocus ? IslandTheme.textSecondary : IslandTheme.textMuted
            font.family: root.iconFontFamily
            font.pixelSize: Metrics.font(11)
        }

        TextInput {
            id: searchInput
            anchors.left: searchIcon.right
            anchors.leftMargin: Metrics.pad(9)
            anchors.right: parent.right
            anchors.rightMargin: Metrics.pad(10)
            anchors.verticalCenter: parent.verticalCenter
            color: IslandTheme.textPrimary
            selectionColor: IslandTheme.accent
            selectedTextColor: IslandTheme.accentInk
            font.family: root.textFontFamily
            font.pixelSize: Metrics.font(11)
            clip: true
            selectByMouse: true

            // ---- ONE FIELD, TWO JOBS ----
            //
            // A prompt page reuses this field rather than adding a second
            // TextInput below the list. The reason is focus, not tidiness:
            // getting the keyboard into a field inside a FocusScope inside a
            // layer-shell surface is the fiddliest thing on this panel
            // (grabKeyboardFocus is two steps and a Timer for exactly that
            // reason), and a second field would mean two more states it can
            // be wrong in. There is exactly one focusable item here and that
            // is deliberate — it is also why Tab is swallowed below.
            echoMode: (root.mode === "prompt" && root.page
                       && root.page.secret === true)
                ? TextInput.Password : TextInput.Normal

            onTextChanged: {
                if (root.query !== text)
                    root.query = text;
            }

            // ---- THE j/k PROBLEM ----
            //
            // The brief for this panel asks for j/k movement AND for typing
            // to filter, and those two are in direct conflict: `j` is a
            // letter. SettingsLayer can spend j/k on movement because it has
            // no field; the application launcher can spend Left/Right on it
            // because its own field takes the letters.
            //
            // The rule here, which is the launcher's rule generalised:
            //
            //   * with the query EMPTY, j/k move. The panel opens empty, so
            //     the muscle memory from every other list in this shell
            //     works on the state you are in when you open it.
            //   * once you have typed anything, j and k are letters again —
            //     they have to be, or "jack" is untypeable — and movement is
            //     Up/Down, which never stops working.
            //
            // Ctrl+n / Ctrl+p are the third way in, always available, for
            // the hand that is already in readline. They are cheap and they
            // are the only movement keys that work identically in both
            // states, which is why they are also in the footer hint when the
            // query is non-empty.
            //
            // `q` gets the same treatment as j/k and for the same reason:
            // with an empty query it closes (SettingsLayer's contract), with
            // a query it types. Escape always closes, which is the promise
            // every submap and panel in this session already makes.
            //
            // ---- AND WHY A PROMPT PAGE SUSPENDS ALL OF IT ----
            //
            // On a prompt page every letter is content. `q` is not close,
            // `j` and `k` are not movement even with the field empty, and
            // Enter submits instead of running a row. So the whole block
            // above is gated on `list`: the mode is what decides whether a
            // letter is a command, and there is no state in which a letter
            // is ambiguous. Escape still closes and Up/Down/Ctrl+n/p still
            // do nothing harmful on a page with no rows.
            Keys.onPressed: function (event) {
                const list = root.mode === "list";
                const empty = searchInput.text === "";
                const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;

                if (event.key === Qt.Key_Escape) {
                    root.closeRequested();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    if (root.mode === "prompt")
                        root.submitPrompt();
                    else
                        root.runSelected();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Backspace && empty) {
                    // Backspace on an empty field goes back one page, which
                    // is the file-manager gesture and the reason `../` is
                    // NOT a row in the confedit port: a row that duplicates
                    // a key can disagree with it. When the stack is one deep
                    // it falls through and Backspace is just Backspace.
                    event.accepted = root.popPage();
                } else if (ctrl && event.key === Qt.Key_H) {
                    // The same, always available — Backspace is spent as
                    // soon as there is a character in the field, and a
                    // prompt page is a field with characters in it.
                    event.accepted = root.popPage();
                } else if (event.key === Qt.Key_Down
                        || (ctrl && event.key === Qt.Key_N)
                        || (list && empty && event.key === Qt.Key_J)) {
                    root.move(1);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Up
                        || (ctrl && event.key === Qt.Key_P)
                        || (list && empty && event.key === Qt.Key_K)) {
                    root.move(-1);
                    event.accepted = true;
                } else if (list && empty && event.key === Qt.Key_Q) {
                    root.closeRequested();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
                    // Swallowed rather than left to Qt's focus navigation.
                    // There is exactly one focusable item on this panel, so
                    // Tab's only possible effect is to take the focus OFF
                    // the field and leave the keyboard grab pointing at
                    // nothing — a panel that has stopped responding with no
                    // visible reason why.
                    event.accepted = true;
                } else if (ctrl && event.key === Qt.Key_R) {
                    // Re-read. The lists are volatile — windows close,
                    // processes exit — and a picker that has been open for a
                    // minute is showing history.
                    root.refresh();
                    event.accepted = true;
                }
            }

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                visible: parent.text === ""
                // A prompt's placeholder is written by the SCRIPT, because
                // the script is the thing that knows whether it is asking
                // for a URL or a sentence. This file only supplies the
                // fallback for a page that forgot to say.
                text: root.mode === "prompt"
                    ? (root.page && root.page.prompt !== undefined
                        ? String(root.page.prompt) : "type an answer, Enter submits")
                    : "type to filter — j/k move, Enter runs, Esc closes"
                color: IslandTheme.textDisabled
                font.family: root.textFontFamily
                font.pixelSize: Metrics.font(11)
            }
        }
    }

    // ---- THE NOTE ----
    //
    // Prose the script wants above the list: why a page is asking, where a
    // file will be written, what a menu deliberately does not do. It spans
    // the FULL width rather than the list column, because it is a sentence
    // and the list column is 54% of a 900 px panel — a paragraph in a
    // half-width column next to an empty details pane reads as a layout
    // accident.
    Text {
        id: noteLabel
        x: chrome.contentX
        y: chrome.contentY + root.searchHeight + Metrics.pad(8)
        width: chrome.contentWidth
        visible: root.note !== ""
        text: root.note
        wrapMode: Text.WordWrap
        color: IslandTheme.textMuted
        font.pixelSize: Metrics.font(11)
        font.family: root.textFontFamily
        lineHeight: 1.25
    }

    ListView {
        id: list
        // FORK: P1-3. One shared indicator; see qml/common/IslandScrollBar.qml
        // for why `active` does not gate on pointer interaction alone.
        ScrollBar.vertical: IslandScrollBar { view: list }
        x: chrome.contentX
        y: chrome.contentY + root.searchHeight + Metrics.pad(8) + root.noteHeight
        width: root.listWidth
        height: parent.height - y - Metrics.chromeFooter() - chrome.gap
        visible: root.mode === "list"
        clip: true
        model: root.filtered
        currentIndex: root.selectedIndex
        boundsBehavior: Flickable.StopAtBounds

        // A search that matches nothing has to say so; a blank list reads as
        // a panel that failed to load. The empty-list case is a different
        // sentence, because "no windows" is a fact about the session and
        // "no match" is a fact about what you typed.
        Text {
            anchors.centerIn: parent
            visible: !root.loading && root.filtered.length === 0
            text: root.items.length === 0
                ? "nothing to pick"
                : "no match for “" + root.query + "”"
            color: IslandTheme.textDisabled
            font.family: root.textFontFamily
            font.pixelSize: Metrics.font(11)
        }

        delegate: PanelRow {
            id: rowItem
            required property int index
            required property var modelData

            readonly property bool isSelected: rowItem.index === root.selectedIndex

            width: list.width
            height: root.rowHeight

            // `active` is never set: every row in a picker menu is an equally
            // available choice, so there is no system state to mark and the
            // cursor is the whole of it. That also moves this list off
            // IslandTheme.selectionFill, which is the accent wash.
            selected: rowItem.isSelected

            onCursorRequested: root.selectedIndex = rowItem.index
            onActivated: root.runSelected()

            // FORK: the row thumbnail, for menus whose items carry an
            // `icon` path. Only the clipboard menu does today.
            //
            // "image" repeated down a column is not a list of images, it
            // is the same word eight times — the entry you are looking
            // for is a picture and the only thing that identifies it is
            // what it looks like. copyq_rofi knew this and passed
            // -show-icons; this panel had no way to.
            //
            // sourceSize caps the DECODE, not just the draw. Without it
            // a 1366x768 screenshot is decoded at full resolution into
            // a 22 px box, once per row, and the clipboard is mostly
            // screenshots.
            Image {
                id: rowThumb
                visible: source !== ""
                source: rowItem.modelData.icon !== undefined
                    ? "file://" + rowItem.modelData.icon : ""
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                height: Metrics.px(18)
                width: Metrics.px(28)
                fillMode: Image.PreserveAspectFit
                horizontalAlignment: Image.AlignLeft
                sourceSize.width: Metrics.px(56)
                sourceSize.height: Metrics.px(36)
                asynchronous: true
                // The files are rewritten under the same names on every
                // --list, so a cached copy is a preview of the previous
                // clipboard.
                cache: false
                smooth: true
                }

                Text {
                anchors.left: rowThumb.visible ? rowThumb.right : parent.left
                anchors.leftMargin: rowThumb.visible ? Metrics.pad(10) : 0
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                // Elided, not wrapped. A window title can be a whole
                // sentence ("Reacher (2022) — Watch on Cineby - Brave")
                // and a row that grew to fit one would break the fixed
                // row height every height calculation on this panel
                // depends on. The full string is in the details column,
                // which has room and wraps.
                elide: Text.ElideRight
                text: rowItem.modelData.label
                color: IslandTheme.textPrimary
                font.pixelSize: Metrics.font(12)
                font.family: root.textFontFamily
                font.weight: rowItem.isSelected ? Font.DemiBold : Font.Normal
            }

            // The MouseArea is PanelRow's; its two signals are wired above.
        }
    }

    // ---- DETAILS ----
    //
    // The same list-plus-details shape SettingsLayer uses, and here it earns
    // its width for a different reason: the label alone is ambiguous in two
    // of the three menus. Six terminals all read "~"; the detail is
    // "scratch-term1 · workspace special:term1" and that is the entire
    // difference between closing the right window and the wrong one. The
    // full label is repeated at the top unelided for the same reason.
    Column {
        id: details
        anchors.left: parent.left
        anchors.leftMargin: chrome.padX + root.listWidth + Metrics.pad(16)
        anchors.right: parent.right
        anchors.rightMargin: chrome.padX
        y: list.y + Metrics.px(2)
        spacing: Metrics.px(6)
        // Nothing is selected on a prompt or a message page, so every Text
        // below would bind to "" — three invisible empty labels holding a
        // column open. Hidden as a unit instead.
        visible: root.mode === "list"

        Text {
            width: details.width
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
            text: root.selected ? String(root.selected.label || "") : ""
            color: IslandTheme.textPrimary
            font.pixelSize: Metrics.font(13)
            font.family: root.heroFontFamily
            font.weight: Font.DemiBold
        }

        // The real preview. The row thumbnail is 28 px and only says
        // "which one"; this says what it actually is, which for a
        // screenshot is the entire content of the clipboard entry.
        Rectangle {
            visible: preview.source !== ""
            width: Math.min(details.width, preview.paintedWidth + 2)
            height: preview.paintedHeight + 2
            color: IslandTheme.surfaceSunken
            radius: Metrics.px(4)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.08)

            Image {
                id: preview
                anchors.centerIn: parent
                source: root.selected && root.selected.icon !== undefined
                    ? "file://" + root.selected.icon : ""
                width: details.width - Metrics.px(2)
                height: Metrics.px(120)
                fillMode: Image.PreserveAspectFit
                sourceSize.width: Metrics.px(520)
                sourceSize.height: Metrics.px(260)
                asynchronous: true
                cache: false
                smooth: true
            }
        }

        Text {
            width: details.width
            wrapMode: Text.WordWrap
            maximumLineCount: 4
            elide: Text.ElideRight
            text: root.selected ? String(root.selected.detail || "") : ""
            color: IslandTheme.textSecondary
            font.pixelSize: Metrics.font(11)
            font.family: root.textFontFamily
            lineHeight: 1.25
        }

        // The id, dimmed. It is the thing that actually crosses back to the
        // script — a window address, a pid, a workspace number — and on the
        // `processes` menu it is the number you would need if you decided
        // this wants a real `kill -9` instead. SettingsLayer shows the
        // config key here for the same reason.
        Text {
            text: root.selected ? String(root.selected.id || "") : ""
            color: IslandTheme.textDisabled
            font.pixelSize: Metrics.font(10)
            font.family: root.textFontFamily
        }
    }

    // The footer hint.
    // The key-hint Text that used to close this file is `chrome.hints` now.
}
