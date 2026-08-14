import QtQuick
import Quickshell
import Quickshell.Io

import "../common"

//
// FORK — new file. popups/AudioPopup.py, in Quickshell.
//
// POPUP_W=940, POPUP_H=600, ROWS_VISIBLE=17, VOLUME_STEP=5 — that file's
// numbers. Its four tabs are pavucontrol's four and it says so:
//
//     outputs   inputs   playback   recording
//
// and the keys are Audio-Mode's, from config.py:
//
//     j k    move            g G    top / bottom
//     Tab    next view       o i a  outputs / inputs / playback
//     ↵      use as default  m      mute
//     h l    volume ∓5       r      refresh
//     q Esc  close
//
// WHAT IS NOT HERE, AND IT IS NAMED RATHER THAN QUIETLY DROPPED
// -------------------------------------------------------------
// `p` profiles, `P` ports, `C` cards and the balance keys open three more
// views in that file — 2,241 lines of it — and each is a list of card
// profiles or port names from `pactl list cards`. They are absent here, and
// the hint bar does not advertise them, because a key chip that names a view
// which does not open is worse than a shorter bar. The four TABS are the
// popup; the sub-views are a card editor that pavucontrol also has.
//
// WHY wpctl AND pactl BOTH
// ------------------------
// wpctl is the PipeWire-native tool and is what the rest of this desktop uses
// for volume — the topbar's readout, the media keys, the island's OSD — so
// the numbers here cannot disagree with those. It has no listing verb that
// gives ids and descriptions together in a parseable form, though, so the
// LIST comes from `pactl -f json`, which does. One tool per job rather than
// two tools per job.
PopupChrome {
    id: root

    // NOT `closed`: a PanelWindow is a QQuickWindow and already has one,
    // so declaring it logs "Duplicate signal name: invalid override of
    // property change signal or superclass signal" and the handler is
    // never called — a popup that cannot ask to be closed, with a
    // warning rather than an error to say so.
    signal requestClose()

    popupWidth: PopupMetrics.s(940)
    popupHeight: PopupMetrics.s(600)

    titleIcon: String.fromCodePoint(0xF057E)
    title: "Audio"
    subtitle: root.viewLabel + "  ·  " + root.rows.length + " "
        + (root.rows.length === 1 ? "entry" : "entries")

    badgeLabel: "default sink"
    badgeValue: root.defaultSinkName === "" ? "none" : root.defaultSinkName

    // ONE space, not the wallpaper picker's five — see PopupChrome's
    // hintGap. WifiPopup.py measured this bar and its note is exact:
    // ten chips at two spaces overflow by 6 px, and nothing clips.
    hintGap: PopupMetrics.hintSize * 0.6

    hints: [
        { key: "jk",  desc: "move" },
        { key: "↵", desc: "use" },
        { key: "hl",  desc: "vol" },
        { key: "m",   desc: "mute" },
        { key: "Tab", desc: "view" },
        { key: "r",   desc: "refresh" },
        { key: "Esc", desc: "close" }
    ]

    // ---- STATE ----
    //
    // _TABS, in order, and one cursor per view — "so switching back to a list
    // puts you where you left it", which is that file's own reason and is the
    // difference between a tab bar and four popups.
    readonly property var views: ["outputs", "inputs", "playback", "recording"]
    property string view: "outputs"
    property var cursors: ({ outputs: 0, inputs: 0, playback: 0, recording: 0 })

    property var sinks: []
    property var sources: []
    property var sinkInputs: []
    property var sourceOutputs: []
    property string defaultSink: ""
    property string defaultSource: ""

    readonly property string viewLabel: {
        switch (root.view) {
        case "outputs":   return "Output devices";
        case "inputs":    return "Input devices";
        case "playback":  return "Playback streams";
        default:          return "Recording streams";
        }
    }

    readonly property var rows: {
        switch (root.view) {
        case "outputs":   return root.sinks;
        case "inputs":    return root.sources;
        case "playback":  return root.sinkInputs;
        default:          return root.sourceOutputs;
        }
    }

    readonly property var selected:
        (list.index >= 0 && list.index < root.rows.length)
            ? root.rows[list.index] : null

    readonly property string defaultSinkName: {
        for (const s of root.sinks) {
            if (s.name === root.defaultSink)
                return s.label;
        }
        return "";
    }

    function setView(v) {
        if (root.views.indexOf(v) < 0)
            return;
        // Save where the cursor was before leaving, so coming back lands
        // there rather than at the top.
        const c = root.cursors;
        c[root.view] = list.index;
        root.view = v;
        list.index = c[v] || 0;
        list.clampIndex();
    }

    function cycleView(delta) {
        const i = root.views.indexOf(root.view);
        root.setView(root.views[(i + delta + root.views.length) % root.views.length]);
    }

    // ---- THE LISTING ----
    //
    // `pactl -f json` for the four lists in one call. Four separate calls
    // would be four processes on every refresh and on every volume step,
    // which on a key you hold down is the same mistake HyprlandData is
    // criticised for elsewhere in this tree.
    Process {
        id: listProc
        command: ["sh", "-c",
            "printf '{\"sinks\":%s,\"sources\":%s,\"sink_inputs\":%s,"
            + "\"source_outputs\":%s,\"defsink\":\"%s\",\"defsource\":\"%s\"}' "
            + "\"$(pactl -f json list sinks)\" \"$(pactl -f json list sources)\" "
            + "\"$(pactl -f json list sink-inputs)\" "
            + "\"$(pactl -f json list source-outputs)\" "
            + "\"$(pactl get-default-sink)\" \"$(pactl get-default-source)\""]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    root.error = "";
                    root.defaultSink = String(d.defsink || "");
                    root.defaultSource = String(d.defsource || "");
                    root.sinks = root.mapDevices(d.sinks, root.defaultSink);
                    root.sources = root.mapDevices(d.sources, root.defaultSource);
                    root.sinkInputs = root.mapStreams(d.sink_inputs);
                    root.sourceOutputs = root.mapStreams(d.source_outputs);
                } catch (e) {
                    // Keep the last good lists. pactl's json is written in one
                    // go, but a torn read would otherwise blank the popup
                    // under the cursor mid-keypress.
                }
            }
        }

        // ---- A FAILURE THAT SAYS SO ----
        //
        // This was silent, and the first thing it hid was real. pactl refused
        // every connection on this machine with
        //
        //     Connection failure: Connection terminated
        //
        // and the popup drew its frame, its tabs and "0 entries" — which reads
        // as "you have no sound devices", not as "the audio server would not
        // talk to me". The cause was 62 orphaned `pactl subscribe` processes
        // that had been accumulating since the previous day and had exhausted
        // pipewire-pulse's client limit; its own journal says
        // "too many client application connections: Connection refused".
        //
        // Nothing in this repo spawns them, so the source is still open — but
        // an empty list and a broken audio server must never look the same
        // again, whatever caused it.
        stderr: StdioCollector {
            onStreamFinished: {
                const t = text.trim();
                if (t !== "")
                    root.error = t.split("\n")[0];
            }
        }
    }

    property string error: ""

    // pactl reports a per-channel volume; the popup shows ONE number, so it
    // takes the loudest channel — which is also what a balance-aware reader
    // has to do to avoid claiming a stereo sink is quieter than its left ear.
    function volumeOf(o) {
        let pct = 0;
        const v = o.volume || {};
        for (const k in v) {
            const m = String(v[k].value_percent || "").match(/(\d+)/);
            if (m)
                pct = Math.max(pct, parseInt(m[1], 10));
        }
        return pct;
    }

    function mapDevices(list, def) {
        const out = [];
        for (const o of (list || [])) {
            out.push({
                id: o.index,
                name: String(o.name || ""),
                label: String(o.description || o.name || ""),
                volume: root.volumeOf(o),
                muted: o.mute === true,
                isDefault: String(o.name || "") === def,
                stream: false
            });
        }
        return out;
    }

    function mapStreams(list) {
        const out = [];
        for (const o of (list || [])) {
            const props = o.properties || {};
            out.push({
                id: o.index,
                name: String(o.name || ""),
                label: String(props["application.name"]
                    || props["media.name"] || o.name || "stream"),
                volume: root.volumeOf(o),
                muted: o.mute === true,
                isDefault: false,
                stream: true
            });
        }
        return out;
    }

    // 2 s, matching the topbar's own volume poll. Each tick is one short-lived
    // pulse client, and a client limit is a thing this machine has been
    // observed to hit — see the stderr collector above.
    Timer {
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: listProc.running = true
    }

    // ---- ACTIONS ----
    Process { id: actionProc; onExited: listProc.running = true }

    function act(cmd) {
        actionProc.command = cmd;
        actionProc.running = true;
    }

    // The pactl object type for whichever view is showing. A stream's volume
    // is set on sink-input / source-output, not on the device it happens to
    // be playing through — setting the device's instead is the bug where
    // turning one app down turns everything down.
    readonly property string objType: {
        switch (root.view) {
        case "outputs":   return "sink";
        case "inputs":    return "source";
        case "playback":  return "sink-input";
        default:          return "source-output";
        }
    }

    function changeVolume(delta) {
        if (!root.selected)
            return;
        const next = Math.max(0, Math.min(150, root.selected.volume + delta));
        root.act(["pactl", "set-" + root.objType + "-volume",
                  String(root.selected.id), next + "%"]);
    }

    function toggleMute() {
        if (!root.selected)
            return;
        root.act(["pactl", "set-" + root.objType + "-mute",
                  String(root.selected.id), "toggle"]);
    }

    // Return — "use". On a device that means make it the default; on a stream
    // it means move it to the current default, which is that file's
    // send_to_default().
    function activate() {
        if (!root.selected)
            return;
        if (root.view === "outputs")
            root.act(["pactl", "set-default-sink", root.selected.name]);
        else if (root.view === "inputs")
            root.act(["pactl", "set-default-source", root.selected.name]);
        else if (root.view === "playback")
            root.act(["pactl", "move-sink-input",
                      String(root.selected.id), root.defaultSink]);
        else
            root.act(["pactl", "move-source-output",
                      String(root.selected.id), root.defaultSource]);
    }

    onKeyPressed: (key, mods, text) => {
        switch (key) {
        case Qt.Key_J: case Qt.Key_Down: list.move(1); break;
        case Qt.Key_K: case Qt.Key_Up:   list.move(-1); break;
        case Qt.Key_G:
            list.jump(mods & Qt.ShiftModifier ? "bottom" : "top");
            break;
        case Qt.Key_Tab:      root.cycleView(1); break;
        case Qt.Key_Backtab:  root.cycleView(-1); break;
        case Qt.Key_O: root.setView("outputs"); break;
        case Qt.Key_I: root.setView("inputs"); break;
        case Qt.Key_A: root.setView("playback"); break;
        case Qt.Key_H: case Qt.Key_Left:  root.changeVolume(-5); break;
        case Qt.Key_L: case Qt.Key_Right: root.changeVolume(5); break;
        case Qt.Key_M: root.toggleMute(); break;
        case Qt.Key_R: listProc.running = true; break;
        case Qt.Key_Return: case Qt.Key_Enter: root.activate(); break;
        }
    }

    onDismissed: root.requestClose()

    // ---- BODY: THE TAB STRIP, THEN THE LIST ----
    //
    // render_tabs(): the four tabs with the active one filled. Drawn rather
    // than left to the title alone, because Tab cycles them and a cycle with
    // no visible position is a guess.
    Row {
        id: tabStrip
        anchors.top: parent.top
        anchors.left: parent.left
        height: PopupMetrics.s(28)
        spacing: PopupMetrics.s(6)

        Repeater {
            model: root.views
            delegate: Rectangle {
                required property var modelData
                readonly property bool current: modelData === root.view

                width: tabText.implicitWidth + PopupMetrics.s(20)
                height: parent.height
                radius: PopupMetrics.s(6)
                color: current ? root.cHighlight : root.cSurface

                Text {
                    id: tabText
                    anchors.centerIn: parent
                    text: modelData
                    color: parent.current ? root.cHighlightInk : root.cMuted
                    font.family: PopupMetrics.font
                    font.pixelSize: PopupMetrics.hintSize
                    font.bold: parent.current
                    renderType: Text.NativeRendering
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.setView(parent.modelData)
                }
            }
        }
    }

    PopupRowList {
        id: list
        anchors.top: tabStrip.bottom
        anchors.topMargin: PopupMetrics.s(8)
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        rowsVisible: 15
        surface: root.cSurface
        fg: root.cFg
        muted: root.cMuted
        highlight: root.cHighlight
        highlightInk: root.cHighlightInk

        rows: root.rows.map((o) => ({
            mark: o.isDefault ? String.fromCodePoint(0xF012C)
                : o.muted ? String.fromCodePoint(0xF075F)
                : String.fromCodePoint(0xF0765),
            left: o.label.length > 46 ? o.label.substring(0, 45) + "…" : o.label,
            // The bar is drawn in text, as the footer's is in the wallpaper
            // popup, so it lines up with the percentage in the same monospace
            // cell grid rather than being a Rectangle that has to be told the
            // row height.
            right: root.volumeBar(o.volume, o.muted) + "  "
                + (o.volume < 10 ? "  " : o.volume < 100 ? " " : "") + o.volume + "%",
            tone: o.muted ? root.cMuted
                : o.isDefault ? IslandTheme.success : root.cFg
        }))
    }

    function volumeBar(pct, muted) {
        // Ten cells over 0-100, so a sink boosted past 100 fills the bar and
        // shows its real number beside it rather than overflowing the cells.
        const filled = Math.max(0, Math.min(10, Math.round(pct / 10)));
        return (muted ? String.fromCodePoint(0xF075F) + " "
                      : String.fromCodePoint(0xF057E) + " ")
            + "━".repeat(filled) + "─".repeat(10 - filled);
    }

    // ---- FOOTER ----
    footer: Text {
        anchors.centerIn: parent
        text: root.error !== "" ? root.error
            : root.selected
            ? root.selected.label + "   ·   "
                + (root.selected.muted ? "muted" : root.selected.volume + "%")
                + "   ·   " + (list.index + 1) + " / " + root.rows.length
            : "nothing here"
        color: root.error !== "" ? IslandTheme.danger
            : root.selected && root.selected.muted ? root.cMuted : root.cFg
        font.family: PopupMetrics.font
        font.pixelSize: PopupMetrics.footSize
        renderType: Text.NativeRendering
    }
}
