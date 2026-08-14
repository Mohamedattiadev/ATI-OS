import QtQuick
import Quickshell
import Quickshell.Io

import "../common"

//
// FORK — new file. popups/DisplayPopup.py, in Quickshell.
//
// POPUP_W=940, POPUP_H=600, ROWS_VISIBLE=17 — that file's numbers, and its
// vertical rhythm is why PopupChrome grew an optional tabs row: this is the
// one qtile popup with four VIEWS, and render_tabs() sits at y=126 between
// the hint bar and the body.
//
// WHY THIS IS A PORT AND NOT THE ISLAND'S PANEL
// ---------------------------------------------
// It was the island's panel first — qml/display/DisplayPanel.qml hosted in a
// window — on the argument that the panel is itself a key-for-key port of
// this file, so hosting it meant one implementation instead of two. Asked
// for directly afterwards: "the display popup should be same style ui of the
// qtile one". The argument was about where the CODE lives; the request is
// about what the SURFACE looks like, and under qtile's bar the surface
// should be qtile's. So this is the popup, in the grammar its three
// neighbours share, and the island keeps its panel on the same key.
//
// EVERYTHING ABOUT HYPRLAND'S MONITOR SYNTAX STAYS IN THE SCRIPT.
// hypr/scripts/display-ctl.py already carries all of it — which modes and
// scales an output can legally take, how a `monitor =` line is spelled, and
// how the presets are composed — and it can be run and checked from a shell
// rather than only from inside a compositor. This file is the keyboard and
// the pixels, which is the same split DisplayPanel.qml's header argues for.
//
// KEYMAP — qtile's Display-Mode, with that file's own hint bar
//
//     j k    move                ↵      modes / apply / restore
//     i      laptop only         e      external only      m  mirror
//     h l    external left/right u d    above / below
//     t      rotate              f      flip
//     p      cycle scale         o      output on / off
//     a      arrange             v      saved layouts
//     s      save layout         x      delete layout
//     r      re-read             Backspace  back
//     q Esc  close
//
// `p` IS THE ONE DELIBERATE DIVERGENCE, and it is inherited rather than
// invented: in qtile it set the xrandr PRIMARY output, and Hyprland has no
// primary at all — the bar is a Variants over every screen and workspaces
// bind to monitors individually. It cycles SCALE instead, which is the
// control Wayland actually has. DisplayPanel.qml made the same call.
PopupChrome {
    id: root

    // NOT `closed` — QQuickWindow has one. See NetworkPopup's header.
    signal requestClose()

    popupWidth: PopupMetrics.s(940)
    popupHeight: PopupMetrics.s(600)

    titleIcon: String.fromCodePoint(0xF0379)
    title: "Display"
    subtitle: root.outputs.length === 1
        ? "1 output"
        : root.outputs.length + " outputs"

    badgeLabel: "focused"
    badgeValue: root.focusedName

    // Ten chips on the 874 px bar, which is what that file measured this
    // exact list against — so the one-space gap, as the wifi popup uses.
    hintGap: PopupMetrics.hintSize * 0.6

    hints: [
        { key: "jk", desc: "move" },
        { key: "↵", desc: "modes" },
        { key: "i",  desc: "laptop" },
        { key: "e",  desc: "external" },
        { key: "m",  desc: "mirror" },
        { key: "a",  desc: "arrange" },
        { key: "p",  desc: "scale" },
        { key: "t",  desc: "rotate" },
        { key: "f",  desc: "flip" },
        { key: "v",  desc: "saved" }
    ]

    // ---- STATE ----
    property var outputs: []          // display-ctl query's `outputs`
    property var layouts: []
    property string view: "outputs"   // outputs | modes | layouts
    property string modeOutput: ""
    property var modeList: []
    property string status: ""
    property string statusLevel: ""

    readonly property string focusedName: {
        for (const o of root.outputs)
            if (o.focused)
                return String(o.name);
        return root.outputs.length > 0 ? String(root.outputs[0].name) : "—";
    }

    readonly property var selectedOutput:
        (root.view === "outputs" && root.list.index >= 0
            && root.list.index < root.outputs.length)
            ? root.outputs[root.list.index] : null

    function setStatus(text, level) {
        root.status = text;
        root.statusLevel = level;
    }

    // render_tabs(): the view's name, then the keys that only apply in it.
    tabsLabel: root.view === "modes"
            ? "Modes — " + root.modeOutput
        : root.view === "layouts" ? "Saved layouts"
        : "Outputs"

    tabsExtra: root.view === "modes"
            ? "   ↵ apply   Backspace back   r refresh   q close"
        : root.view === "layouts"
            ? "   ↵ restore   s save   x delete   v back"
        : "   put external:  h left   l right   u above   d below"
          + "      o on/off   s save   r refresh   q close"

    // ---- THE READ ----
    Process {
        id: queryProc
        command: ["python3",
            Quickshell.env("HOME") + "/.config/hypr/scripts/display-ctl.py",
            "query"]
        stdout: StdioCollector {
            onStreamFinished: {
                let parsed = null;
                try {
                    parsed = JSON.parse(text);
                } catch (error) {
                    root.setStatus("display-ctl produced no readable output",
                                   "error");
                    return;
                }
                if (!parsed.ok) {
                    root.setStatus(String(parsed.status || "query failed"),
                                   "error");
                    return;
                }
                root.outputs = parsed.outputs || [];
                root.layouts = parsed.layouts || [];
                if (root.view === "modes") {
                    for (const o of root.outputs) {
                        if (String(o.name) === root.modeOutput) {
                            root.modeList = o.modes || [];
                            break;
                        }
                    }
                }
            }
        }
    }

    function refresh() {
        queryProc.running = true;
    }

    Component.onCompleted: root.refresh()

    // ---- ACTIONS ----
    //
    // Every one reports into the footer. That is the half a reimplementation
    // drops, and here it matters more than usual: a display change can take a
    // second and can also leave you unable to SEE the popup, so silence is
    // indistinguishable from a key that did nothing.
    Process {
        id: actionProc
        stdout: StdioCollector {
            onStreamFinished: {
                let parsed = null;
                try {
                    parsed = JSON.parse(text);
                } catch (error) {
                    parsed = null;
                }
                if (parsed && parsed.status !== undefined)
                    root.setStatus(String(parsed.status),
                                   parsed.ok ? "ok" : "error");
                else
                    root.setStatus(root.pendingOk, "ok");
                root.refresh();
            }
        }
    }
    property string pendingOk: ""

    // display-ctl EXITS 0 EVEN WHEN IT FAILS — its own header says so, and it
    // is why bar-action's `--menu || nwg-displays` fallback was dead code.
    // So the exit status is never consulted here: `ok` in the JSON is the
    // only thing that says whether it worked.
    function ctl(args, busy, ok) {
        root.setStatus(busy, "busy");
        root.pendingOk = ok;
        actionProc.command = ["python3",
            Quickshell.env("HOME") + "/.config/hypr/scripts/display-ctl.py"]
            .concat(args);
        actionProc.running = true;
    }

    function preset(kind, label) {
        root.ctl(["preset", kind], label + "…", label);
    }

    function rotateSelected() {
        if (!root.selectedOutput) return;
        root.ctl(["rotate", String(root.selectedOutput.name)],
                 "rotating…", "rotated");
    }
    function flipSelected() {
        if (!root.selectedOutput) return;
        root.ctl(["reflect", String(root.selectedOutput.name)],
                 "flipping…", "flipped");
    }
    function scaleSelected() {
        if (!root.selectedOutput) return;
        root.ctl(["cycle-scale", String(root.selectedOutput.name)],
                 "cycling scale…", "scale changed");
    }
    function toggleSelected() {
        if (!root.selectedOutput) return;
        const o = root.selectedOutput;
        // The last enabled output cannot be turned off — that is a black
        // screen with no way back, and the popup is the thing that would have
        // gone with it.
        let enabled = 0;
        for (const x of root.outputs)
            if (x.enabled) enabled++;
        if (o.enabled && enabled <= 1) {
            root.setStatus("that is the only enabled output", "error");
            return;
        }
        // --disable / --enable, which is parse_set()'s spelling. Checked
        // against the script rather than guessed: --off/--on are rejected
        // with "unknown option", and the script EXITS 0 saying so.
        root.ctl(["set", String(o.name), o.enabled ? "--disable" : "--enable"],
                 o.enabled ? "turning off…" : "turning on…",
                 o.enabled ? "output off" : "output on");
    }

    // ---- VIEWS ----
    function showModes() {
        if (!root.selectedOutput) return;
        root.modeOutput = String(root.selectedOutput.name);
        root.modeList = root.selectedOutput.modes || [];
        root.view = "modes";
        root.list.index = 0;
        root.list.clampIndex();
    }

    function applyMode() {
        if (root.list.index < 0 || root.list.index >= root.modeList.length)
            return;
        const mode = String(root.modeList[root.list.index]);
        root.ctl(["set", root.modeOutput, "--mode", mode],
                 "applying " + mode + "…", mode);
    }

    function showLayouts() {
        root.view = "layouts";
        root.list.index = 0;
        root.list.clampIndex();
    }

    function back() {
        root.view = "outputs";
        root.list.index = 0;
        root.list.clampIndex();
    }

    Process {
        id: saveProc
        stdout: StdioCollector {
            onStreamFinished: {
                const name = text.trim();
                if (name === "")
                    return;
                root.ctl(["layout-save", name], "saving " + name + "…",
                         "saved " + name);
            }
        }
    }

    // The name comes from rofi, for the reason NetworkPopup gives about its
    // password prompt: one prompt, one set of matching rules, and this popup
    // never has to own a text field.
    function saveLayout() {
        saveProc.command = ["sh", "-c",
            "rofi -dmenu -p 'Save layout as' </dev/null"];
        saveProc.running = true;
    }

    function deleteLayout() {
        if (root.view !== "layouts") return;
        if (root.list.index < 0 || root.list.index >= root.layouts.length)
            return;
        const name = String(root.layouts[root.list.index].name
                            || root.layouts[root.list.index]);
        root.ctl(["layout-delete", name], "deleting " + name + "…",
                 "deleted " + name);
    }

    function applyLayout() {
        if (root.list.index < 0 || root.list.index >= root.layouts.length)
            return;
        const name = String(root.layouts[root.list.index].name
                            || root.layouts[root.list.index]);
        root.ctl(["layout-apply", name], "restoring " + name + "…",
                 "restored " + name);
    }

    onKeyPressed: (key, mods, text) => {
        switch (key) {
        case Qt.Key_J: case Qt.Key_Down: root.list.move(1); break;
        case Qt.Key_K: case Qt.Key_Up:   root.list.move(-1); break;
        case Qt.Key_G:
            root.list.jump(mods & Qt.ShiftModifier ? "bottom" : "top");
            break;

        case Qt.Key_Return: case Qt.Key_Enter:
            if (root.view === "modes") root.applyMode();
            else if (root.view === "layouts") root.applyLayout();
            else root.showModes();
            break;

        case Qt.Key_Backspace: root.back(); break;

        case Qt.Key_I: root.preset("internal", "laptop only"); break;
        case Qt.Key_E: root.preset("external", "external only"); break;
        case Qt.Key_M: root.preset("mirror", "mirroring"); break;
        case Qt.Key_H: root.preset("left", "external left"); break;
        case Qt.Key_L: root.preset("right", "external right"); break;
        case Qt.Key_U: root.preset("above", "external above"); break;
        case Qt.Key_D: root.preset("below", "external below"); break;

        case Qt.Key_T: root.rotateSelected(); break;
        case Qt.Key_F: root.flipSelected(); break;
        case Qt.Key_P: root.scaleSelected(); break;
        case Qt.Key_O: root.toggleSelected(); break;

        case Qt.Key_V:
            if (root.view === "layouts") root.back();
            else root.showLayouts();
            break;
        case Qt.Key_S: root.saveLayout(); break;
        case Qt.Key_X: root.deleteLayout(); break;

        case Qt.Key_A: root.arrange(); break;

        case Qt.Key_R: root.refresh(); root.setStatus("re-read", "ok"); break;
        }
    }

    onDismissed: root.requestClose()

    // ---- BODY ----
    property alias list: dispList

    PopupRowList {
        id: dispList
        anchors.fill: parent
        rowsVisible: 17
        surface: root.cSurface
        fg: root.cFg
        muted: root.cMuted
        highlight: root.cHighlight
        highlightInk: root.cHighlightInk

        rows: root.view === "modes"
            ? root.modeList.map((m) => ({
                mark: String.fromCodePoint(0xF0379),
                left: String(m),
                right: String(m) === root.currentModeOf(root.modeOutput)
                    ? "current" : "",
                tone: root.cFg
            }))
            : root.view === "layouts"
            ? root.layouts.map((l) => ({
                mark: String.fromCodePoint(0xF0193),
                left: String(l.name || l),
                right: "",
                tone: root.cFg
            }))
            : root.outputs.map((o) => ({
                // A filled dot on the focused output and a hollow one
                // otherwise, so every row is the same width and the names
                // line up — the trick the network popup's marks use.
                mark: o.focused ? String.fromCodePoint(0xF012C)
                                : String.fromCodePoint(0xF0765),
                left: String(o.name)
                    + (o.internal ? "  (laptop)" : "")
                    + (o.enabled ? "" : "  (off)"),
                // The four facts a display change is judged by, which is why
                // none of them elides: mode, scale, position, rotation.
                right: (o.enabled ? String(o.currentMode) : "disabled")
                    + "   " + String(o.scale) + "x"
                    + "   @" + String(o.x) + "," + String(o.y)
                    + (String(o.transformName) !== "normal"
                        ? "   " + String(o.transformName) : ""),
                tone: !o.enabled ? root.cMuted
                    : o.focused ? IslandTheme.success : root.cFg
            }))
    }

    // ---- ARRANGE IS NOT PORTED, AND SAYS SO ----
    //
    // qtile's arrange view is a positional EDITOR: pick an output, nudge it
    // with hjkl, align with =, apply as one unit. display-ctl.py already has
    // the apply half — `arrange` takes a whole {name: [x, y]} map so the move
    // lands atomically, for the reason its own docstring gives.
    //
    // What is missing is the editor, and it cannot be built honestly here:
    // this machine has ONE output, so every state of that view is
    // unreachable and untestable, and this tree's own note on scratchpads
    // says multi-monitor is verified-by-history only. Shipping an editor
    // nobody can drive is how the display `--menu` came to be dead code.
    //
    // So the key reports what it needs. A control that says why it did
    // nothing is debuggable; one that silently does nothing is what this
    // whole pass exists to remove. The island's DisplayPanel has the full
    // editor when two outputs are actually present.
    function arrange() {
        let enabled = 0;
        for (const o of root.outputs)
            if (o.enabled) enabled++;
        if (enabled < 2) {
            root.setStatus("arrange needs two enabled outputs", "");
            return;
        }
        root.setStatus("arrange is on the island's panel — $mod SHIFT P",
                       "error");
    }

    function currentModeOf(name) {
        for (const o of root.outputs)
            if (String(o.name) === name)
                return String(o.currentMode);
        return "";
    }

    // ---- FOOTER ----
    footer: Text {
        anchors.centerIn: parent
        text: root.status !== "" ? root.status
            : (root.outputs.length === 0 ? "no outputs reported"
               : "Ready")
        color: root.statusLevel === "busy" ? IslandTheme.info
            : root.statusLevel === "ok" ? IslandTheme.success
            : root.statusLevel === "error" ? IslandTheme.danger
            : root.cMuted
        font.family: PopupMetrics.font
        font.pixelSize: PopupMetrics.footSize
        renderType: Text.NativeRendering
    }
}
