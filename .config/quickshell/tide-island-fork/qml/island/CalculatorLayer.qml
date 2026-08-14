pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

// FORK: the shared scale factor — see qml/common/Metrics.js.
import "../common/Metrics.js" as Metrics
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
            input.focusField();
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

    function evaluate() {
        const expr = root.expression.trim();
        if (expr === "")
            return;
        root.pendingExpression = expr;
        root.evaluating = true;
        evalLoader.active = false;
        evalLoader.active = true;
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
                // wl-copy rather than a QML clipboard: Quickshell has no
                // clipboard API, and wl-copy is already a hard dependency of
                // this session (autostart.conf runs two wl-paste watchers
                // into copyq).
                command: ["sh", "-c",
                    "printf '%s' \"$1\" | wl-copy", "sh", root.result]
                running: true
            }
        }
    }

    Keys.onPressed: function(event) {
        // FALLBACK ONLY — the field holds the keyboard and answers Enter,
        // Escape and the arrows through the signals wired below.
        if (event.key === Qt.Key_Escape) {
            root.closeRequested();
            event.accepted = true;
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

        hints: [
            { key: "Enter", label: "keep" },
            { key: "↑↓", label: "recall" },
            { key: "^C", label: "copy" },
            { key: "Esc", label: "close" }
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
        onCancelled: root.closeRequested()
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
            width: parent.width
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
                width: parent.width
                height: root.rowHeight

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
                        input.focusField();
                    }
                }
            }
        }
    }
}
