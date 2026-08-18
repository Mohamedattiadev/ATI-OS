pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

// FORK: the shared scale factor — see qml/common/Metrics.js.
import "../common/Metrics.js" as Metrics
// FORK: copying, on both display servers — see qml/common/Clipboard.js.
import "../common/Clipboard.js" as Clipboard
// FORK: the shared motion system — one spring for geometry, one
// critically damped curve for opacity. See qml/common/Motion.js.
import "../common/Motion.js" as Motion
import "../common"

//
// FORK — new file. The CALCULATOR, in the island instead of in a scratchpad.
//
// WHAT IT REPLACES
// ----------------
// `$alt 5` spawned qalculate-gtk into the `special:calc` scratchpad, wrapped
// in `env GTK_THEME=Adwaita:dark` — which is the whole story of why this was
// asked for ("instead of clac app can we make our own with popup"). That
// env var is a confession: the app cannot follow theme-apply, so it was
// nailed to one dark GTK theme and left there. Under `mono-light` the
// desktop goes light and the calculator stays Adwaita dark; under all 22
// palettes it is the same grey box.
//
// Its geometry was also a lie the migration record already caught: the
// scratchpad asks for 60%x60% and qalculate-gtk enforces a GTK minimum
// height, so it lands at 820x550 instead of 820x461 and Hyprland re-centres
// around it. MIGRATION.md files that under "known cosmetic deviations,
// app-imposed, not worth fighting" — correct at the time, and it stops
// being a deviation worth tolerating once the panel is ours.
//
// THE ENGINE IS THE SAME ONE, WHICH IS THE POINT
// ----------------------------------------------
// This does NOT reimplement arithmetic. `qalc` is libqalculate's CLI and is
// already installed — it is what qalculate-gtk is a front end FOR, so the
// package list does not move and neither does the answer to any expression.
// Measured on this machine, qalc 5.12.0:
//
//     (3+4)*2        14                    2^10        1024
//     1/3            0.3333333333          sin(pi/2)   1
//     200 * 15%      30                    log(100,10) 2
//     1 GiB to MB    1073.741824 MB        now         2026-08-14T08:16:35
//
// ~90 ms per invocation, which is why evaluation is LIVE rather than on
// Enter: at that cost the result can just follow the expression, and a
// calculator that answers while you type is the one thing a popup can do
// that a window cannot.
//
// ONE TRAP, AND IT IS qalc's
// --------------------------
// qalc resolves an unknown identifier as a UNIT rather than failing:
// `frobnicate(3)` returns `0 B·t·m⁴`, not an error. So a typo produces a
// confident nonsense answer instead of a complaint, and there is no exit
// code to test — it exits 0 for that too. Nothing here can detect it; the
// defence is that the expression stays on screen above the result, so the
// answer is always read next to what was actually asked.
//
FocusScope {
    id: root

    signal closeRequested

    property bool showCondition: false
    property string textFontFamily: ""
    property string heroFontFamily: ""
    property string iconFontFamily: ""

    // The live result, and the expression it belongs to. Kept as a pair
    // because they are displayed as a pair: a result with no expression over
    // it is exactly the state the qalc trap above produces silently.
    property string result: ""
    property string resultFor: ""
    property string errorText: ""
    property bool evaluating: false

    // [{ expr, result }, …], newest LAST so the list reads downward like a
    // paper tape and the most recent line sits closest to the input.
    property var history: []
    // -1 = not recalling. Walks `history` backwards on Up.
    property int recallIndex: -1

    // ---- THE TAPE SURVIVES A CLOSE ----
    //
    // Was a plain property on a panel this shell does not retain, so the
    // tape died with the panel — and, since a hot reload re-parses this
    // whole tree, with every edit made to this file too.
    //
    // NO JsonAdapter: NEXT-SESSION.md records a crash from FileView +
    // JsonAdapter on a free-form MAP — loaded clean, logged "Configuration
    // Loaded", then died. Its own advice is that a LIST is the shape known
    // to survive, and `history` already is one; `setText(JSON.stringify(...))`
    // sidesteps the adapter entirely, the same way QdropStore.qml does for
    // the shelf. Copied rather than shared, because the shelf's version
    // carries add/remove/pin machinery this tape has no use for — one
    // function, called from the one place `history` is ever appended to.
    function persistHistory() {
        historyFile.writing = true;
        historyFile.setText(JSON.stringify(root.history));
        // Re-arm: FileView is a QFileSystemWatcher and atomicWrites replaces
        // the inode, so a watcher on the old one is a watcher on nothing —
        // see IslandTheme.qml's note on the same trap.
        Qt.callLater(function () {
            historyFile.path = "";
            historyFile.path = Quickshell.env("HOME") + "/.cache/tide-island/calculator-tape.json";
            historyFile.writing = false;
        });
    }

    FileView {
        id: historyFile
        path: Quickshell.env("HOME") + "/.cache/tide-island/calculator-tape.json"
        watchChanges: true
        preload: true
        atomicWrites: true
        // Does not exist on a machine that has never used the calculator —
        // a normal first run, not an error.
        printErrors: false
        property bool writing: false

        onLoaded: {
            const s = text().trim();
            if (s === "")
                return;
            try {
                const parsed = JSON.parse(s);
                if (Array.isArray(parsed))
                    root.history = parsed;
            } catch (e) {
                // A half-written file is a state, not a reason to lose
                // whatever is already in memory.
                console.warn("[calculator] could not parse " + historyFile.path + ": " + e);
            }
        }
    }

    // ========================================================================
    //  MODAL, AND IT IS vi's MODEL RUN THE OTHER WAY UP
    // ========================================================================
    //
    // Reported: "the popup of calcoter is too dumm and poor and no vim motion
    // enough for moving". It answered exactly one key — Escape — because the
    // input field holds the keyboard and every other keystroke is text.
    //
    // THIS IS QdropGrid's PROBLEM, INVERTED, and that is the whole design.
    // The shelf can be hjkl by default and put its search behind `/`, because
    // browsing is the primary act there and typing is the exception. A
    // calculator is the other way round: typing the expression IS the act,
    // and `d`, `y`, `j` and `g` are all legal inside one — `2d`, `0y`, and
    // `log` all contain letters this would otherwise steal. So:
    //
    //     INSERT (default)   the field is live, type the expression
    //     Esc                leave the field -> NORMAL
    //     NORMAL             j/k walk the tape, g/G its ends, y yanks the
    //                        result, Y the expression, Enter recalls into the
    //                        box and returns to insert, i/a go back to
    //                        typing, Esc closes the panel
    //
    // Escape therefore takes TWO presses to close from a half-typed sum,
    // which is vi's own precedence and the point of it: the first press is
    // "stop typing", not "throw this away".
    //
    // `PanelSearchField.readOnly` is the mechanism, as it is in the shelf —
    // its header calls it the thing that "keeps focus and inserts nothing" —
    // so normal mode needs no focus juggling at all, and the host's
    // Keys.onPressed simply starts receiving what the field stops claiming.
    property bool normalMode: false
    // Which tape row the cursor is on in normal mode. Indexes `history`,
    // which is newest-LAST, so it starts at the newest row: that is the one
    // you almost always want, and it is the one nearest the input box.
    property int tapeIndex: 0

    function enterNormal() {
        if (root.history.length === 0) {
            // Nothing to navigate. A mode with no content to move through is
            // a mode you cannot tell you are in, so Escape keeps its old
            // meaning until there is a tape.
            root.closeRequested();
            return;
        }
        root.normalMode = true;
        input.readOnly = true;
        root.tapeIndex = root.history.length - 1;
        root.forceActiveFocus();
    }

    function enterInsert() {
        root.normalMode = false;
        input.readOnly = false;
        input.focusField();
    }

    function tapeMove(delta) {
        if (root.history.length === 0)
            return;
        // CLAMPED, not wrapped, and deliberately unlike the shelf's motion:
        // this list is a tape with a top and a bottom, and running off the
        // newest end into the oldest is not a thing a tape does.
        root.tapeIndex = Math.max(0, Math.min(root.history.length - 1,
                                              root.tapeIndex + delta));
    }

    readonly property var tapeRowAt: root.history[
        Math.max(0, Math.min(root.tapeIndex, root.history.length - 1))] || null

    // Yank the ANSWER by default and the expression on Y. Which one you want
    // is the whole question a tape gets asked, and the answer is the common
    // one — the expression is already recallable with Enter.
    function yankTape(wantExpr) {
        const row = root.tapeRowAt;
        if (!row)
            return;
        Quickshell.execDetached(
            Clipboard.argv(String(wantExpr ? row.expr : row.result)));
        root.errorText = wantExpr ? "expression copied" : "result copied";
        errorClear.restart();
    }

    // The status line is the only feedback a copy has, and a copy that says
    // nothing looks like a copy that did not happen. It shares `errorText`
    // with the real errors because they occupy the same slot; this puts it
    // back to the resting text afterwards.
    Timer {
        id: errorClear
        interval: 1600
        onTriggered: root.errorText = ""
    }

    // ---- A MEMORY REGISTER ----
    //
    // The remaining "upgrade" item from the original ask, "not investigated
    // at all yet" per the last session's own notes. One register, not a
    // bank of them — this is a pocket calculator's M+/MR, not a spreadsheet,
    // and a panel this small has nowhere to show more than one value anyway.
    //
    // A STRING, not a number: qalc's results are not always numeric ("5 km
    // to mi" is three terms with units, `now` is a quoted timestamp), and
    // storing the exact text qalc printed is what makes recall put back
    // exactly what was there to store, with no re-formatting to get wrong.
    //
    // NOT PERSISTED across a close, unlike the tape. The tape is a record of
    // what you did; a memory register is scratch space for what you are
    // about to do, and qalculate-gtk's own didn't survive a restart either.
    property string memoryValue: ""

    function storeMemory() {
        if (root.result === "")
            return;
        root.memoryValue = root.result;
        root.errorText = "stored " + root.result;
        errorClear.restart();
    }

    function recallMemory() {
        if (root.memoryValue === "")
            return;
        // Same shape as a tape row's Enter: land in the box, ready to type
        // around the recalled value, rather than replacing it outright —
        // storing a number and then wanting `M * 1.08` is the common case.
        input.setText(String(root.memoryValue));
        root.recallIndex = -1;
        root.enterInsert();
    }

    readonly property string expression: input.query

    readonly property real rowHeight: Metrics.px(22)
    readonly property real inputStripHeight: Metrics.px(26) + Metrics.px(10)
    readonly property real resultStripHeight: Metrics.px(46)
    // Enough tape to be useful, few enough that the panel does not become a
    // window. Six is two more than the number of intermediate values anyone
    // holds in their head, which is the job this list is doing.
    readonly property int maxHistory: 6

    readonly property real preferredHeight:
        Metrics.chromeTotal() + root.inputStripHeight + root.resultStripHeight
        + Math.min(root.history.length, root.maxHistory) * root.rowHeight

    focus: showCondition
    activeFocusOnTab: true
    anchors.fill: parent
    opacity: showCondition ? 1 : 0

    // FORK: one choreography for every layer in the shell. See Motion.js,
    // "CONTENT CHOREOGRAPHY".
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
            root.errorText = "";
            root.recallIndex = -1;
            // The TAPE SURVIVES a close, the expression does not. Reopening
            // with the last expression still in the box means the first
            // keystroke appends to it, which is never what was wanted; the
            // history is the part worth keeping, and Up reaches it.
            input.clear();
            root.result = "";
            root.resultFor = "";
            // Always INSERT on open. A modal panel that reopens in whatever
            // mode you left it in is a panel that swallows your first
            // expression roughly half the time, and the reason you pressed
            // the key was to type one.
            root.enterInsert();
        }
    }

    // ---- EVALUATION ----
    //
    // Debounced, not per-keystroke. qalc is ~90 ms and typing is faster than
    // that, so an un-debounced version spawns a process per character and the
    // answers arrive out of order — the fresh-Process rule below stops them
    // being read out of the WRONG collector, not out of order.
    Timer {
        id: debounce
        interval: 140
        repeat: false
        onTriggered: root.evaluate()
    }

    onExpressionChanged: {
        root.recallIndex = -1;
        if (root.expression.trim() === "") {
            root.result = "";
            root.resultFor = "";
            root.errorText = "";
            root.resultTrapped = false;
            debounce.stop();
            return;
        }
        debounce.restart();
    }

    // ---- A FRESH Process EVERY TIME, ON PURPOSE ----
    //
    // The trap written up at length in ModeKeysLayer.qml and paid for again
    // in the cheatsheet: a REUSED Quickshell Process with a StdioCollector
    // hands back the PREVIOUS run's text on the second and later runs. For a
    // calculator that is the worst possible failure — it does not look
    // broken, it looks like a wrong answer, and every answer after the first
    // would be the previous expression's.
    property string pendingExpression: ""

    // ---- THE UNIT TRAP, FLAGGED RATHER THAN PREVENTED ----
    //
    // Reported: "i can write any letter i which means nothing, so make a
    // specific letters or simpler ref person can write" — which reads as
    // TWO different fixes (restrict what INSERT mode accepts, or flag when
    // an answer is qalc's unit-trap nonsense rather than a real one), and
    // they are different features with different costs. Left running
    // unattended: the character-restriction reading needs the user to say
    // which they meant, so it is not built. This half is strictly additive
    // and reversible and helps regardless of which reading is right, so it
    // is.
    //
    // The header's own trap example is `frobnicate(3)` -> `0 B·t·m⁴`, and
    // `-t` (terse) is exactly what hides the evidence: it prints the value
    // and nothing else, by design, so the panel shows the double display of
    // the expression as one line. The evidence lives in the NON-terse
    // output, which prints an `error: "f" is not a valid variable/function/
    // unit.` line ahead of the (still-computed) result — qalc recovers from
    // the error and answers anyway, silently, which is the whole trap.
    //
    // A second, parallel Process rather than dropping `-t` from the first
    // one: the existing evaluate()/parsing above is the panel's actual
    // answer and is left untouched, byte for byte. This one only ever sets
    // one boolean and is safe to get wrong.
    property bool resultTrapped: false

    function evaluate() {
        const expr = root.expression.trim();
        if (expr === "")
            return;
        root.pendingExpression = expr;
        root.evaluating = true;
        root.resultTrapped = false;
        evalLoader.active = false;
        evalLoader.active = true;
        trapCheckLoader.active = false;
        trapCheckLoader.active = true;
    }

    Loader {
        id: trapCheckLoader
        active: false

        sourceComponent: Component {
            Process {
                // Same expression, no `-t` — see the note above `resultTrapped`.
                command: ["qalc", root.pendingExpression]
                running: true

                stdout: StdioCollector {
                    onStreamFinished: {
                        // Stale by the time it lands: a later keystroke
                        // already started a newer check. Its own answer,
                        // when it arrives, is the one that matters.
                        if (root.pendingExpression === "")
                            return;
                        const lines = String(text).split("\n");
                        // The LAST line is always the "expr = result" (or
                        // "expr ≈ result") line — everything before an
                        // `error:` line ahead of it is qalc recovering from
                        // one and answering anyway regardless.
                        let trapped = false;
                        for (let i = 0; i < lines.length - 1; i++) {
                            if (lines[i].indexOf("error:") === 0) {
                                trapped = true;
                                break;
                            }
                        }
                        // Only apply it if this run's expression is still
                        // the one on screen — the fresh-Process-every-time
                        // rule protects the TEXT, this protects the FLAG.
                        if (root.pendingExpression === root.expression.trim())
                            root.resultTrapped = trapped;
                    }
                }
            }
        }
    }

    Loader {
        id: evalLoader
        active: false

        sourceComponent: Component {
            Process {
                // -t is "terse": the result alone, with no echo of the input
                // and no surrounding prose. Without it qalc prints the
                // expression back and the panel would show it twice.
                command: ["qalc", "-t", root.pendingExpression]
                running: true

                stdout: StdioCollector {
                    onStreamFinished: {
                        const out = String(text).trim();
                        root.evaluating = false;
                        if (out === "") {
                            root.errorText = "no result";
                            return;
                        }
                        root.errorText = "";
                        // Only the FIRST line. qalc emits a warning line
                        // before the value for some inputs, and a two-line
                        // result in a one-line slot renders as a clipped
                        // first line with the answer pushed out of sight.
                        root.result = out.split("\n")[0];
                        root.resultFor = root.pendingExpression;
                    }
                }

                stderr: StdioCollector {
                    onStreamFinished: {
                        const err = String(text).trim();
                        if (err !== "")
                            root.errorText = err.split("\n")[0];
                    }
                }

                onExited: function(exitCode) {
                    root.evaluating = false;
                    // qalc exits 0 even for input it could not parse — see
                    // the header. A non-zero code here means it is not
                    // installed or could not start, which IS worth saying,
                    // because the panel would otherwise just never answer.
                    if (exitCode !== 0 && root.result === "")
                        root.errorText = "qalc failed (exit " + exitCode + ")";
                }
            }
        }
    }

    // ---- THE TAPE ----
    function commit() {
        const expr = root.expression.trim();
        if (expr === "" || root.result === "")
            return;
        // Guard against committing a result that belongs to an EARLIER
        // expression: Enter pressed inside the 140 ms debounce would
        // otherwise pair the new text with the old answer.
        if (root.resultFor !== expr) {
            root.evaluate();
            return;
        }
        const next = root.history.slice();
        next.push({ expr: expr, result: root.result });
        while (next.length > root.maxHistory)
            next.shift();
        root.history = next;
        root.persistHistory();
        input.clear();
        root.recallIndex = -1;
    }

    // Up walks back through the tape, Down forward and then out of it. The
    // expression is what is recalled, not the result — you re-run and edit a
    // calculation, you do not retype an answer.
    function recall(delta) {
        if (root.history.length === 0)
            return;
        let next = root.recallIndex < 0
            ? (delta < 0 ? root.history.length - 1 : -1)
            : root.recallIndex + (delta < 0 ? -1 : 1);

        if (next < 0) next = 0;
        if (next > root.history.length - 1) {
            // Walked off the recent end: back to an empty box, which is
            // where you were before you started recalling.
            root.recallIndex = -1;
            input.clear();
            return;
        }
        root.recallIndex = next;
        input.setText(String(root.history[next].expr));
    }

    function copyResult() {
        if (root.result === "")
            return;
        copyLoader.active = false;
        copyLoader.active = true;
    }

    Loader {
        id: copyLoader
        active: false
        sourceComponent: Component {
            Process {
                // A PROCESS rather than a QML clipboard, because Quickshell
                // has no clipboard API — and through Clipboard.js rather
                // than straight at wl-copy, because this panel is on $alt 5
                // under qtile as well, where wl-copy is inert and says
                // nothing about it. See qml/common/Clipboard.js.
                command: Clipboard.argv(root.result)
                running: true
            }
        }
    }

    // ---- NORMAL MODE'S KEY MAP ----
    //
    // Only reached once the field is readOnly, which is what stops every one
    // of these letters from being part of an expression. In insert mode the
    // field claims them all and this handler sees nothing but Escape.
    Keys.onPressed: function(event) {
        if (!root.normalMode) {
            // FALLBACK ONLY — the field holds the keyboard and answers
            // Enter, Escape and the arrows through the signals wired below.
            if (event.key === Qt.Key_Escape) {
                root.enterNormal();
                event.accepted = true;
            }
            return;
        }

        const shift = (event.modifiers & Qt.ShiftModifier) !== 0;
        event.accepted = true;

        switch (event.key) {
        case Qt.Key_Escape:
        case Qt.Key_Q:
            root.closeRequested();
            return;
        case Qt.Key_I:
        case Qt.Key_A:
            root.enterInsert();
            return;
        case Qt.Key_J:
        case Qt.Key_Down:
            root.tapeMove(1);
            return;
        case Qt.Key_K:
        case Qt.Key_Up:
            root.tapeMove(-1);
            return;
        case Qt.Key_G:
            // g to the oldest, G to the newest — the ends of the tape, in
            // the direction the tape is drawn.
            root.tapeIndex = shift ? root.history.length - 1 : 0;
            return;
        case Qt.Key_Home:
            root.tapeIndex = 0;
            return;
        case Qt.Key_End:
            root.tapeIndex = root.history.length - 1;
            return;
        case Qt.Key_Y:
            root.yankTape(shift);
            return;
        case Qt.Key_C:
            if (event.modifiers & Qt.ControlModifier)
                root.yankTape(false);
            return;
        // ---- h/l: character-wise cursor movement in the still-visible
        // expression, vim-style. Re-asked for after this file's own audit
        // left them unbound ("no natural meaning on a 1-D tape") — the
        // natural meaning j/k does not already cover is the box's TEXT
        // cursor, not the tape. Goes through PanelSearchField.moveCursor(),
        // which does not need insert mode: a `readOnly` field still has a
        // cursor and still draws it, the field just refuses to let a
        // keystroke change the text, and this is not one.
        case Qt.Key_H:
            input.moveCursor(-1);
            return;
        case Qt.Key_L:
            input.moveCursor(1);
            return;
        // ---- a memory register, M+/MR-style. `m` stores the CURRENT
        // RESULT (the answer, not the expression — the same choice
        // `yankTape` already makes and for the same reason: the expression
        // is already recallable off the tape with Enter, the number is the
        // thing with nowhere else to go). `M` recalls it into the box and
        // switches to insert, same as Enter on a tape row, so the stored
        // value is immediately usable inside a new expression.
        case Qt.Key_M:
            if (shift)
                root.recallMemory();
            else
                root.storeMemory();
            return;
        case Qt.Key_Return:
        case Qt.Key_Enter:
            // Recall the EXPRESSION and go straight back to typing, because
            // the only reason to pull a line off the tape is to edit it.
            if (root.tapeRowAt) {
                input.setText(String(root.tapeRowAt.expr));
                root.recallIndex = -1;
                root.enterInsert();
            }
            return;
        default:
            event.accepted = false;
        }
    }

    // ---- CHROME, SHARED ---- see qml/common/PanelChrome.qml.
    PanelChrome {
        id: chrome
        textFontFamily: root.textFontFamily

        title: "calculator"

        status: root.errorText !== "" ? root.errorText
              : (root.evaluating ? "…" : "qalc")
        statusLevel: root.errorText !== "" ? "error"
                   : (root.evaluating ? "busy" : "idle")

        // The memory register, shown the same way ThemePickerLayer shows its
        // search count: a clause in the header, present only while there is
        // something to say. Muted rather than accent — it is a fact about
        // the panel's state, not a live one the way "3 of 21" is.
        statusClause: root.memoryValue !== "" ? ("M " + root.memoryValue) : ""

        // The bar follows the MODE, because a key chip naming a key that
        // does nothing in the mode you are standing in is worse than a
        // shorter bar — the same argument the volume popup's own hints make.
        hints: root.normalMode
            ? [
                { key: "jk", label: "tape" },
                { key: "hl", label: "cursor" },
                { key: "↵", label: "recall" },
                { key: "y", label: "copy" },
                { key: "Y", label: "expr" },
                { key: "m/M", label: "mem" },
                { key: "i", label: "type" },
                { key: "Esc", label: "close" }
            ]
            : [
                { key: "Enter", label: "keep" },
                { key: "↑↓", label: "recall" },
                { key: "^C", label: "copy" },
                { key: "Esc", label: "tape" }
            ]
    }

    PanelSearchField {
        id: input
        x: chrome.contentX
        y: chrome.contentY
        width: chrome.contentWidth

        textFontFamily: root.textFontFamily
        iconFontFamily: root.iconFontFamily
        // nf-fa-calculator. By codepoint, not pasted — a private-use
        // character does not survive a round trip through a text edit.
        icon: String.fromCharCode(0xf1ec)
        placeholder: "2+2 · 5 km to mi · 200 * 15% · 1 GiB to MB"
        // Escape closes on the FIRST press here. The two-stage clear is for
        // a filter, where the query is the only way back to the full list;
        // an expression is cheap to retype and the tape already kept it.
        escapeClearsQuery: false

        onSubmitted: root.commit()
        // Escape leaves the FIELD, it does not leave the panel. See the modal
        // note above: the first press is "stop typing", the second closes.
        onCancelled: root.enterNormal()
        onMoved: function(delta) { root.recall(delta); }
        onCopyRequested: root.copyResult()
    }

    // ---- THE RESULT ----
    Item {
        id: resultRow
        x: chrome.contentX
        y: chrome.contentY + root.inputStripHeight
        width: chrome.contentWidth
        height: root.resultStripHeight

        // ---- THE UNIT-TRAP FLAG ----
        //
        // Left-aligned, opposite the result, so it never sits on top of the
        // digits it is warning about. `resultText`'s own width gives up room
        // for it below, rather than the two overlapping when the answer is
        // long — a warning a long result draws over is a warning nobody
        // reads.
        Text {
            id: trapFlag
            visible: root.resultTrapped && root.result !== ""
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            // A FIXED fraction, not `Math.min(…, implicitWidth)` — the
            // obvious spelling for "only as wide as the text needs" loops:
            // `elide` makes Qt's implicitWidth for this Text depend on the
            // width it is given, and a width bound to implicitWidth is
            // bound to itself. Measured: "Binding loop detected for
            // property width" the first time this ran.
            width: visible ? parent.width * 0.42 : 0
            text: "  unrecognised word read as a unit?"
            color: IslandTheme.warning
            font.family: root.textFontFamily
            font.pixelSize: Metrics.font(10)
            elide: Text.ElideRight
            wrapMode: Text.NoWrap
        }

        Text {
            id: resultText
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            // Right-aligned and set in the hero face at nearly twice the
            // input's size. A calculator's answer is the one piece of text on
            // the panel you came to read, and every other panel in this shell
            // reserves that treatment for its own subject.
            text: root.result !== "" ? root.result : "—"
            color: root.result !== "" ? IslandTheme.accentText : IslandTheme.textDisabled
            font.family: root.heroFontFamily
            font.pixelSize: Metrics.font(24)
            font.weight: Font.DemiBold
            elide: Text.ElideLeft
            width: parent.width - trapFlag.width - (trapFlag.visible ? Metrics.pad(8) : 0)
            horizontalAlignment: Text.AlignRight
        }
    }

    // ---- THE TAPE, newest at the bottom ----
    Column {
        x: chrome.contentX
        y: chrome.contentY + root.inputStripHeight + root.resultStripHeight
        width: chrome.contentWidth

        Repeater {
            model: root.history

            Item {
                id: tapeRow
                required property var modelData
                required property int index
                width: parent.width
                height: root.rowHeight

                // The normal-mode cursor. Only while the mode is on: a
                // highlighted row in insert mode would claim the tape is
                // being navigated when every keystroke is going into the box.
                Rectangle {
                    anchors.fill: parent
                    anchors.leftMargin: -Metrics.pad(6)
                    anchors.rightMargin: -Metrics.pad(6)
                    radius: Metrics.px(4)
                    visible: root.normalMode && tapeRow.index === root.tapeIndex
                    color: IslandTheme.alpha(IslandTheme.accent, 0.18)
                    border.width: 1
                    border.color: IslandTheme.alpha(IslandTheme.accent, 0.45)
                }

                Text {
                    id: tapeExpr
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: tapeRow.modelData.expr
                    color: IslandTheme.textDisabled
                    font.family: root.textFontFamily
                    font.pixelSize: Metrics.font(10)
                    elide: Text.ElideRight
                    width: Math.max(0, parent.width * 0.5)
                }

                Text {
                    anchors.right: parent.right
                    anchors.left: tapeExpr.right
                    anchors.leftMargin: Metrics.pad(10)
                    anchors.verticalCenter: parent.verticalCenter
                    text: tapeRow.modelData.result
                    color: IslandTheme.textSecondary
                    font.family: root.textFontFamily
                    font.pixelSize: Metrics.font(10)
                    horizontalAlignment: Text.AlignRight
                    elide: Text.ElideLeft
                }

                // Click a tape row to put its expression back in the box.
                // The keyboard has Up for this; the mouse had nothing, and a
                // list you can see but not reach is furniture.
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        input.setText(String(tapeRow.modelData.expr));
                        root.tapeIndex = tapeRow.index;
                        // A click is a decision to edit that line, so it
                        // lands you in insert mode whichever mode you were
                        // in — otherwise clicking a row while in normal mode
                        // fills a box you cannot type into.
                        root.enterInsert();
                    }
                }
            }
        }
    }
}
