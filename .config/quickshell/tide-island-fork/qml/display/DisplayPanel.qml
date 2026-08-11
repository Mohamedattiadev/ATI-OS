pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import IslandBackend

//
// FORK — new file. The port of qtile's popups/DisplayPopup.py (28 bindings),
// which was the largest single hole left by the migration and the only one
// with no fallback at all: MIGRATION.md named nwg-displays and wdisplays as
// the stand-in and NEITHER is installed, so until this existed there was no
// way to change resolution, scale, rotation or arrangement outside of
// editing monitors.conf and reloading.
//
// This layer owns NO knowledge of Hyprland's monitor syntax. Everything
// about how a `monitor =` line is spelled, which scales a resolution can
// legally take, and how the five one-key presets are composed lives in
// hypr/scripts/display-ctl.py, where it can be run and checked from a shell
// rather than only from inside a compositor. This file is the keyboard and
// the pixels. That split is deliberate: the previous generation of this
// feature was 2,000 lines of Python that could only be exercised by opening
// the popup.
//
// KEYMAP — qtile's Display-Mode, key for key
// ------------------------------------------
//   j / k          move the cursor         (in arrange: nudge the output)
//   g / G          top / bottom
//   Tab            pick the next output    (arrange: which one moves)
//   Return         open the mode list · apply a mode · restore a layout
//   BackSpace      back to the output list
//   i / e / m      preset: internal only · external only · mirror
//   h / l          place external left / right of the laptop
//   u / d          place external above / below
//   t / f          rotate · flip the selected output
//   o              switch the selected output on or off
//   p              cycle scale                        <-- see below
//   r              re-read the compositor
//   v / s / x      saved layouts · save current · delete selected
//   y / c          keep a provisional change · revert it now
//   =              cycle cross-axis alignment while arranging
//   q / Escape     close
//
// `p` is the ONE deliberate divergence. In qtile it set the xrandr primary
// output, and Hyprland has no primary at all — the bar is a Variants over
// every screen and workspaces bind to monitors individually, so there is
// nothing for the key to do. It cycles SCALE instead, which is the control
// Wayland actually has and xrandr never usefully did.
//
FocusScope {
    id: root

    signal closeRequested

    property bool showCondition: false
    property string textFontFamily: ""
    property string heroFontFamily: ""

    // --- model -------------------------------------------------------------
    property var outputs: []
    property var layouts: []
    property string view: "outputs"          // outputs | modes | layouts | arrange
    property int selectedIndex: 0
    property string modeOutput: ""           // whose modes the mode list shows
    property string statusText: "Ready"
    property string statusLevel: "idle"      // idle | busy | ok | error
    property bool busy: false

    // A change that could cost you the ability to SEE the panel is applied
    // provisionally: the configuration before it is captured, and put back
    // automatically unless confirmed with `y`. Confirm-to-apply would be
    // useless here — the whole failure mode is that you can no longer read
    // the prompt.
    property var revertSpecs: null
    property int revertLeft: 0
    property int confirmSeconds: 12

    // Arrange view: pending logical positions being edited, keyed by output
    // name. Nothing is applied until Return, so a mistake costs a keypress
    // rather than a black screen.
    property var arrangePositions: ({})
    property int arrangePick: 0
    readonly property var alignments: ["start", "centre", "end"]
    property int alignIndex: 0

    readonly property real horizontalPadding: 18
    readonly property real headerHeight: 34
    readonly property int rowsVisible: 6

    focus: showCondition
    activeFocusOnTab: true
    anchors.fill: parent
    opacity: showCondition ? 1 : 0

    Behavior on opacity {
        NumberAnimation {
            duration: root.showCondition ? 220 : 120
            easing.type: Easing.InOutQuad
        }
    }

    onShowConditionChanged: {
        if (showCondition) {
            root.view = "outputs";
            root.selectedIndex = 0;
            root.refresh();
            forceActiveFocus();
        } else {
            // Leaving with a change still provisional must NOT silently keep
            // it — the countdown is the only thing standing between a bad
            // mode and a screen you cannot use, and closing the panel is
            // exactly what someone does when they cannot see. Revert on the
            // way out, same as qtile's cleanup_on_leave.
            if (root.revertSpecs !== null)
                root.revertNow("reverted on close");
            countdownTimer.stop();
        }
    }

    // --- derived lists -----------------------------------------------------
    readonly property var currentItems: {
        switch (root.view) {
        case "outputs":
        case "arrange":
            return root.outputs;
        case "layouts":
            return root.layouts;
        case "modes":
            for (let i = 0; i < root.outputs.length; i++) {
                if (root.outputs[i].name === root.modeOutput)
                    return root.outputs[i].modes.map(m => ({ mode: m, name: m }));
            }
            return [];
        }
        return [];
    }

    function selectedOutput() {
        // In the modes view the cursor is over a MODE, so the output is the
        // one whose list we opened, not the one under the cursor.
        if (root.view === "modes") {
            for (let i = 0; i < root.outputs.length; i++) {
                if (root.outputs[i].name === root.modeOutput)
                    return root.outputs[i];
            }
            return null;
        }
        if (root.selectedIndex >= 0 && root.selectedIndex < root.outputs.length)
            return root.outputs[root.selectedIndex];
        return null;
    }

    function setStatus(text, level) {
        root.statusText = text;
        root.statusLevel = level || "idle";
    }

    // --- talking to display-ctl.py ----------------------------------------
    readonly property string ctl: Quickshell.env("HOME") + "/.config/hypr/scripts/display-ctl.py"

    function refresh() {
        queryProcess.running = true;
    }

    Process {
        id: queryProcess
        command: [root.ctl, "query"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(text);
                    root.outputs = parsed.outputs || [];
                    root.layouts = parsed.layouts || [];
                    if (parsed.confirmSeconds)
                        root.confirmSeconds = parsed.confirmSeconds;
                    root.clampIndex();
                } catch (error) {
                    // A parse failure means display-ctl.py printed something
                    // that is not JSON, which in practice means it crashed.
                    // Say so, rather than showing an empty list that reads as
                    // "you have no monitors".
                    root.outputs = [];
                    root.setStatus("display-ctl produced no readable output", "error");
                }
            }
        }
    }

    // One process for every mutating call. Serialising them through a single
    // Process is not a limitation, it is the point: two monitor keywords
    // racing each other produce a configuration that is neither of the two
    // you asked for, and the snapshot taken for the second one would already
    // contain the first one's half-applied result.
    Process {
        id: actionProcess
        property bool risky: false
        property var pendingSnapshot: null

        stdout: StdioCollector {
            onStreamFinished: {
                root.busy = false;
                let result = null;
                try {
                    result = JSON.parse(text);
                } catch (error) {
                    root.setStatus("display-ctl failed", "error");
                    root.refresh();
                    return;
                }

                if (!result.ok) {
                    root.setStatus(String(result.status || "failed"), "error");
                    root.refresh();
                    return;
                }

                if (actionProcess.risky && actionProcess.pendingSnapshot) {
                    root.revertSpecs = actionProcess.pendingSnapshot;
                    root.revertLeft = root.confirmSeconds;
                    countdownTimer.restart();
                    root.setStatus(String(result.status || "applied"), "busy");
                } else {
                    root.setStatus(String(result.status || "applied"), "ok");
                }
                root.refresh();
            }
        }
    }

    // The snapshot is taken immediately before each risky apply and read out
    // of the compositor rather than remembered from the last one, so it is
    // still correct if a hotplug changed the layout while the panel sat open.
    Process {
        id: snapshotProcess
        command: [root.ctl, "snapshot"]
        property var queuedCommand: null
        stdout: StdioCollector {
            onStreamFinished: {
                let specs = null;
                try {
                    specs = JSON.parse(text).specs || null;
                } catch (error) {
                    specs = null;
                }
                actionProcess.pendingSnapshot = specs;
                actionProcess.risky = true;
                actionProcess.command = snapshotProcess.queuedCommand;
                actionProcess.running = true;
            }
        }
    }

    function run(args, message, risky) {
        if (root.busy || root.revertSpecs !== null)
            return;
        root.busy = true;
        root.setStatus(message, "busy");
        if (risky) {
            snapshotProcess.queuedCommand = [root.ctl].concat(args);
            snapshotProcess.running = true;
        } else {
            actionProcess.risky = false;
            actionProcess.pendingSnapshot = null;
            actionProcess.command = [root.ctl].concat(args);
            actionProcess.running = true;
        }
    }

    Timer {
        id: countdownTimer
        interval: 1000
        repeat: true
        onTriggered: {
            if (root.revertSpecs === null) {
                countdownTimer.stop();
                return;
            }
            root.revertLeft -= 1;
            if (root.revertLeft <= 0)
                root.revertNow("no answer — reverted");
        }
    }

    Process {
        id: revertProcess
        stdout: StdioCollector {
            onStreamFinished: root.refresh()
        }
    }

    function revertNow(message) {
        const specs = root.revertSpecs;
        root.revertSpecs = null;
        root.revertLeft = 0;
        countdownTimer.stop();
        if (specs === null)
            return;
        root.busy = false;
        root.setStatus(message, "idle");
        revertProcess.command = [root.ctl, "restore", JSON.stringify(specs)];
        revertProcess.running = true;
    }

    function keep() {
        if (root.revertSpecs === null)
            return;
        root.revertSpecs = null;
        root.revertLeft = 0;
        countdownTimer.stop();
        root.setStatus("kept", "ok");
        root.refresh();
    }

    // --- navigation --------------------------------------------------------
    function clampIndex() {
        const count = root.currentItems.length;
        root.selectedIndex = Math.max(0, Math.min(root.selectedIndex, Math.max(0, count - 1)));
    }

    function move(step) {
        const count = root.currentItems.length;
        if (count === 0)
            return;
        root.selectedIndex = Math.max(0, Math.min(count - 1, root.selectedIndex + step));
        listView.positionViewAtIndex(root.selectedIndex, ListView.Contain);
    }

    function jump(where) {
        const count = root.currentItems.length;
        if (count === 0)
            return;
        root.selectedIndex = where === "top" ? 0 : count - 1;
        listView.positionViewAtIndex(root.selectedIndex, ListView.Contain);
    }

    function setView(next) {
        root.view = next;
        root.selectedIndex = 0;
        root.clampIndex();
    }

    function back() {
        if (root.view === "arrange") {
            root.arrangePositions = ({});
            root.setStatus("arrange cancelled", "idle");
        }
        if (root.view !== "outputs")
            root.setView("outputs");
    }

    // --- actions -----------------------------------------------------------
    function showModes() {
        const out = root.selectedOutput();
        if (out === null)
            return;
        if (!out.modes || out.modes.length === 0) {
            root.setStatus(out.name + " reports no modes", "idle");
            return;
        }
        root.modeOutput = out.name;
        root.setView("modes");
        // Land the cursor on the mode that is already active, so Enter twice
        // is a no-op rather than a surprise.
        for (let i = 0; i < out.modes.length; i++) {
            if (out.modes[i] === out.currentMode) {
                root.selectedIndex = i;
                break;
            }
        }
    }

    function activate() {
        if (root.view === "arrange") {
            root.applyArrange();
            return;
        }
        if (root.view === "layouts") {
            const layout = root.layouts[root.selectedIndex];
            if (!layout)
                return;
            // Through the same countdown as anything else: a layout saved
            // while a monitor was plugged in blanks the screen when replayed
            // after it is gone.
            root.run(["layout-apply", String(layout.name)],
                     "restoring " + layout.name + "…", true);
            return;
        }
        if (root.view === "outputs") {
            root.showModes();
            return;
        }
        // modes view
        const out = root.selectedOutput();
        const mode = root.currentItems[root.selectedIndex];
        if (!out || !mode)
            return;
        root.run(["set", out.name, "--mode", String(mode.mode)],
                 out.name + " → " + mode.mode, true);
    }

    function preset(kind) {
        const out = root.selectedOutput();
        const args = ["preset", kind];
        if (out && !out.internal)
            args.push(out.name);
        root.run(args, kind + "…", true);
    }

    function toggleOutput() {
        const out = root.selectedOutput();
        if (out === null)
            return;
        root.run(["set", out.name, out.enabled ? "--disable" : "--enable"],
                 (out.enabled ? "switching off " : "switching on ") + out.name, true);
    }

    function simple(command) {
        const out = root.selectedOutput();
        if (out === null)
            return;
        root.run([command, out.name], command + " " + out.name + "…", true);
    }

    // --- arrange -----------------------------------------------------------
    // Positions are edited in LOGICAL pixels (width / scale), because that is
    // the space Hyprland lays monitors out in. Using the physical pixel count
    // leaves a gap or an overlap on any scaled output — nothing reports it,
    // and you find out when the pointer refuses to cross.
    function logicalSize(out) {
        const scale = Number(out.scale) || 1;
        return { w: Math.round(out.width / scale), h: Math.round(out.height / scale) };
    }

    function startArrange() {
        if (root.outputs.length < 2) {
            root.setStatus("arrange needs two or more outputs", "idle");
            return;
        }
        const positions = {};
        for (let i = 0; i < root.outputs.length; i++)
            positions[root.outputs[i].name] = [root.outputs[i].x, root.outputs[i].y];
        root.arrangePositions = positions;
        root.arrangePick = Math.max(0, Math.min(root.selectedIndex, root.outputs.length - 1));
        root.setView("arrange");
        root.setStatus("arranging — hjkl to move, Enter to apply", "idle");
    }

    function arrangeStep(dx, dy) {
        const out = root.outputs[root.arrangePick];
        if (!out)
            return;
        const size = root.logicalSize(out);
        // A step is a whole screen edge, not a pixel: monitors are laid out
        // edge to edge and anything else is a mistake you would then have to
        // correct by hand.
        const positions = Object.assign({}, root.arrangePositions);
        const at = positions[out.name] || [0, 0];
        positions[out.name] = [at[0] + dx * size.w, at[1] + dy * size.h];
        root.arrangePositions = positions;
    }

    function cycleAlign() {
        root.alignIndex = (root.alignIndex + 1) % root.alignments.length;
        const moving = root.outputs[root.arrangePick];
        if (!moving)
            return;
        // Align the moved output against the FIRST other output on the axis
        // it is not travelling along — tops, centres or bottoms flush. This
        // is the one thing arandr could do that qtile's popup could not, and
        // it is the difference between "next to it" and "next to it and
        // lined up".
        let anchor = null;
        for (let i = 0; i < root.outputs.length; i++) {
            if (i !== root.arrangePick) { anchor = root.outputs[i]; break; }
        }
        if (anchor === null)
            return;
        const positions = Object.assign({}, root.arrangePositions);
        const anchorAt = positions[anchor.name] || [anchor.x, anchor.y];
        const anchorSize = root.logicalSize(anchor);
        const movingSize = root.logicalSize(moving);
        const at = positions[moving.name] || [moving.x, moving.y];
        const align = root.alignments[root.alignIndex];
        let y = anchorAt[1];
        if (align === "centre")
            y = anchorAt[1] + Math.round((anchorSize.h - movingSize.h) / 2);
        else if (align === "end")
            y = anchorAt[1] + anchorSize.h - movingSize.h;
        positions[moving.name] = [at[0], y];
        root.arrangePositions = positions;
        root.setStatus("aligned " + align, "idle");
    }

    function applyArrange() {
        if (Object.keys(root.arrangePositions).length === 0)
            return;
        // The WHOLE map goes over in one call. Applying it one output at a
        // time would walk through intermediate layouts that overlap, and
        // Hyprland reshuffles windows on each — two visible jolts for one
        // logical change, and a failure halfway leaves a layout nobody asked
        // for. display-ctl.py's `arrange` composes every spec first and
        // applies them together.
        root.run(["arrange", JSON.stringify(root.arrangePositions)],
                 "arranging…", true);
        root.setView("outputs");
    }

    // --- saving a layout ---------------------------------------------------
    // The name is typed into rofi rather than into a field here, for the same
    // reason qtile delegated it: this is a layer surface with an exclusive
    // keyboard grab and no text-input plumbing, so a home-made field would
    // have no clipboard, no keyboard layout and no composition. rofi already
    // solves all three, runs under XWayland, and every dm-* script uses it.
    Process {
        id: saveNameProcess
        stdout: StdioCollector {
            onStreamFinished: {
                const name = String(text).trim();
                if (name === "")
                    return;
                saveProcess.command = [root.ctl, "layout-save", name];
                saveProcess.running = true;
            }
        }
    }

    Process {
        id: saveProcess
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(text);
                    root.setStatus(String(parsed.status || "saved"), parsed.ok ? "ok" : "error");
                } catch (error) {
                    root.setStatus("save failed", "error");
                }
                root.refresh();
            }
        }
    }

    function saveCurrent() {
        let suggestion = "";
        for (let i = 0; i < root.outputs.length; i++) {
            if (root.outputs[i].enabled)
                suggestion += (suggestion === "" ? "" : "-") + root.outputs[i].name;
        }
        saveNameProcess.command = [
            "sh", "-c",
            "printf '%s' \"$1\" | rofi -dmenu -l 0 -p 'Layout name' "
            + "-theme-str 'window { width: 42%; } inputbar { padding: 12px; spacing: 12px; }'",
            "sh", suggestion
        ];
        saveNameProcess.running = true;
    }

    function deleteLayout() {
        if (root.view !== "layouts")
            return;
        const layout = root.layouts[root.selectedIndex];
        if (!layout)
            return;
        saveProcess.command = [root.ctl, "layout-delete", String(layout.name)];
        saveProcess.running = true;
    }

    // --- keys --------------------------------------------------------------
    Keys.onPressed: function(event) {
        const shift = (event.modifiers & Qt.ShiftModifier) !== 0;

        switch (event.key) {
        case Qt.Key_Escape:
            root.closeRequested();
            break;
        case Qt.Key_Q:
            root.closeRequested();
            break;
        case Qt.Key_J:
        case Qt.Key_Down:
            if (root.view === "arrange") root.arrangeStep(0, 1); else root.move(1);
            break;
        case Qt.Key_K:
        case Qt.Key_Up:
            if (root.view === "arrange") root.arrangeStep(0, -1); else root.move(-1);
            break;
        case Qt.Key_G:
            root.jump(shift ? "bottom" : "top");
            break;
        case Qt.Key_Tab:
            if (root.view === "arrange")
                root.arrangePick = (root.arrangePick + 1) % Math.max(1, root.outputs.length);
            else
                root.move(1);
            break;
        case Qt.Key_Return:
        case Qt.Key_Enter:
            root.activate();
            break;
        case Qt.Key_Backspace:
            root.back();
            break;
        case Qt.Key_A:
            root.startArrange();
            break;
        case Qt.Key_I:
            root.preset("internal");
            break;
        case Qt.Key_E:
            root.preset("external");
            break;
        case Qt.Key_M:
            root.preset("mirror");
            break;
        case Qt.Key_H:
        case Qt.Key_Left:
            if (root.view === "arrange") root.arrangeStep(-1, 0); else root.preset("left");
            break;
        case Qt.Key_L:
        case Qt.Key_Right:
            if (root.view === "arrange") root.arrangeStep(1, 0); else root.preset("right");
            break;
        case Qt.Key_U:
            root.preset("above");
            break;
        case Qt.Key_D:
            root.preset("below");
            break;
        case Qt.Key_T:
            root.simple("rotate");
            break;
        case Qt.Key_F:
            root.simple("reflect");
            break;
        case Qt.Key_O:
            root.toggleOutput();
            break;
        case Qt.Key_P:
            root.simple("cycle-scale");
            break;
        case Qt.Key_R:
            root.setStatus("re-reading outputs…", "busy");
            root.refresh();
            break;
        case Qt.Key_V:
            root.setView(root.view === "layouts" ? "outputs" : "layouts");
            break;
        case Qt.Key_S:
            root.saveCurrent();
            break;
        case Qt.Key_X:
            root.deleteLayout();
            break;
        case Qt.Key_Y:
            root.keep();
            break;
        case Qt.Key_C:
            if (root.revertSpecs !== null)
                root.revertNow("reverted");
            else
                root.setStatus("nothing to cancel", "idle");
            break;
        case Qt.Key_Equal:
            root.cycleAlign();
            break;
        default:
            return;
        }
        event.accepted = true;
    }

    // --- chrome ------------------------------------------------------------
    Text {
        id: header
        x: root.horizontalPadding
        y: 10
        text: "Display"
        color: "white"
        font.pixelSize: 15
        font.family: root.heroFontFamily
        font.weight: Font.DemiBold
        font.letterSpacing: -0.2
    }

    Row {
        anchors.left: header.right
        anchors.leftMargin: 14
        y: 12
        spacing: 10

        Repeater {
            model: ["outputs", "modes", "layouts", "arrange"]
            delegate: Text {
                required property var modelData
                text: modelData
                color: root.view === modelData ? "white" : "#6a6a6a"
                font.pixelSize: 11
                font.family: root.textFontFamily
                font.weight: root.view === modelData ? Font.DemiBold : Font.Normal
            }
        }
    }

    // The countdown takes the header's right-hand slot when armed, because a
    // provisional change is the single most important thing on the panel —
    // it is the only state with a deadline.
    Text {
        anchors.right: parent.right
        anchors.rightMargin: root.horizontalPadding
        y: 12
        text: root.revertSpecs !== null
            ? "reverting in " + root.revertLeft + "s — y to keep, c to revert"
            : root.statusText
        color: root.revertSpecs !== null
            ? "#ffcc66"
            : (root.statusLevel === "error" ? "#ff6b6b"
               : (root.statusLevel === "ok" ? "#9ad18a" : "#8a8a8a"))
        font.pixelSize: 11
        font.family: root.textFontFamily
        elide: Text.ElideRight
        width: Math.min(implicitWidth, root.width * 0.55)
        horizontalAlignment: Text.AlignRight
    }

    ListView {
        id: listView
        x: root.horizontalPadding
        y: root.headerHeight + 4
        width: parent.width * 0.56 - root.horizontalPadding
        height: parent.height - root.headerHeight - 40
        clip: true
        model: root.currentItems
        currentIndex: root.selectedIndex
        boundsBehavior: Flickable.StopAtBounds
        spacing: 2

        delegate: Rectangle {
            id: row
            required property int index
            required property var modelData

            width: listView.width
            height: 26
            radius: 7
            color: row.index === root.selectedIndex ? "#22ffffff" : "transparent"
            border.width: (root.view === "arrange" && row.index === root.arrangePick) ? 1 : 0
            border.color: "#ffcc66"

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 20
                elide: Text.ElideRight
                color: {
                    if (root.view === "outputs" || root.view === "arrange")
                        return row.modelData.enabled ? "white" : "#6a6a6a";
                    return "white";
                }
                font.pixelSize: 12
                font.family: root.textFontFamily
                text: {
                    if (root.view === "layouts")
                        return row.modelData.name + "   " + (row.modelData.saved || "");
                    if (root.view === "modes")
                        return row.modelData.mode;
                    const out = row.modelData;
                    let label = out.name + (out.internal ? "  (laptop)" : "");
                    if (root.view === "arrange") {
                        const at = root.arrangePositions[out.name];
                        if (at)
                            label += "   " + at[0] + "," + at[1];
                    } else if (!out.enabled) {
                        label += "   off";
                    } else {
                        label += "   " + out.width + "x" + out.height;
                    }
                    return label;
                }
            }
        }
    }

    // Details for whatever the cursor is on. The list alone cannot say what a
    // change would do; this is where scale, transform and mirror live, and
    // they are precisely the fields with no visible cue anywhere else.
    Column {
        x: parent.width * 0.58
        y: root.headerHeight + 6
        width: parent.width * 0.42 - root.horizontalPadding
        spacing: 3

        Repeater {
            model: {
                const out = root.selectedOutput();
                if (out === null)
                    return [["", "no output selected"]];
                return [
                    ["name", out.name],
                    ["model", out.description],
                    ["mode", out.enabled ? out.currentMode : "off"],
                    ["position", out.x + ", " + out.y],
                    ["scale", String(out.scale) + "x"],
                    ["rotation", out.transformName],
                    ["mirror", out.mirrorOf],
                ];
            }
            delegate: Row {
                required property var modelData
                spacing: 8
                Text {
                    text: modelData[0]
                    color: "#6a6a6a"
                    font.pixelSize: 11
                    font.family: root.textFontFamily
                    width: 62
                }
                Text {
                    text: String(modelData[1] || "—")
                    color: "#d0d0d0"
                    font.pixelSize: 11
                    font.family: root.textFontFamily
                    elide: Text.ElideRight
                    width: 190
                }
            }
        }
    }

    Text {
        anchors.left: parent.left
        anchors.leftMargin: root.horizontalPadding
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 10
        width: parent.width - root.horizontalPadding * 2
        elide: Text.ElideRight
        color: "#6a6a6a"
        font.pixelSize: 10
        font.family: root.textFontFamily
        text: root.view === "arrange"
            ? "hjkl move · Tab pick · = align · Enter apply · BkSp cancel"
            : "j/k move · Enter modes · i/e/m preset · h/l/u/d place · t rotate · f flip · o on-off · p scale · v layouts · s save · q close"
    }
}
