import QtQuick
import Quickshell
import Quickshell.Io

import "../common"

//
// FORK — new file. popups/BluetoothPopup.py, in Quickshell.
//
// POPUP_W=940, POPUP_H=600, ROWS_VISIBLE=17, MAX_NAME_LEN=30 — that file's
// numbers. The keys are its chord's, from config.py's Bluetooth-Mode (Rofi
// mode, then `b`):
//
//     j k    move            g G    top / bottom
//     ↵      pair+trust+connect     d      disconnect
//     x      remove (twice)  t      power on/off
//     r      rescan          /      find
//     c      cancel          q Esc  close
//
// WHY THIS IS A PORT AND THE DISPLAY/CALCULATOR ONES ARE NOT
// ----------------------------------------------------------
// Those two host the island's own layers, because the island's layers ARE the
// ports of qtile's DisplayPopup.py and of the calculator scratchpad — their
// headers say so. This one cannot take that shortcut and it is worth writing
// down why: qml/connectivity/BluetoothPanel.qml's header says it was "rebuilt
// from scratch in the idiom of AudioPanel and DisplayPanel", so it is a good
// panel that is not qtile's. The topbar is qtile's bar, so its Bluetooth
// surface is qtile's popup, beside NetworkPopup which is the same shape.
//
// FOUR TRAPS, ALL bluez 5.87's, ALL FROM THAT FILE'S HEADER
// ---------------------------------------------------------
// Every one of these is a thing that looks like a bug in this file if it is
// "cleaned up":
//
//   * `bluetoothctl connect <mac>` on an out-of-range device NEVER RETURNS.
//     Hence `c`, and hence the timeouts below.
//   * `bluetoothctl devices` embeds ANSI colour escapes EVEN WHEN PIPED, so
//     every line is stripped before it is parsed.
//   * bluez FORGETS UNPAIRED DEVICES as soon as discovery stops, so a
//     scan-then-list design shows a list that empties itself seconds later.
//     Discovery runs for as long as this popup is open and is killed when it
//     closes — leaving it up would keep the radio discovering for nothing.
//   * `bluetoothctl info <mac>` costs one process PER DEVICE, so the list is
//     built from the cheap `devices [Paired|Connected]` queries instead and
//     `info` is asked only for the selected row.
PopupChrome {
    id: root

    // NOT `closed`: a PanelWindow is a QQuickWindow and already has one.
    // See NetworkPopup's header for the full note.
    signal requestClose()

    popupWidth: PopupMetrics.s(940)
    popupHeight: PopupMetrics.s(600)

    titleIcon: String.fromCodePoint(0xF00AF)
    title: "Bluetooth"
    subtitle: root.adapter === "" ? "no controller"
        : root.adapter + "  ·  " + root.devices.length + " devices"

    badgeLabel: root.powered ? "powered" : "off"
    badgeValue: root.connectedName === "" ? "not connected" : root.connectedName

    // Nine chips on a 940 px bar — the same crowding WifiPopup.py measured at
    // ten, so the same one-space gap rather than the wallpaper picker's five.
    hintGap: PopupMetrics.hintSize * 0.6

    hints: [
        { key: "jk",  desc: "move" },
        { key: "↵", desc: "connect" },
        { key: "d",   desc: "drop" },
        { key: "x",   desc: "remove" },
        { key: "t",   desc: "power" },
        { key: "r",   desc: "scan" },
        { key: "/",   desc: "find" },
        { key: "c",   desc: "cancel" },
        { key: "Esc", desc: "close" }
    ]

    // ---- STATE ----
    // [{ mac, name, anonymous, paired, connected, icon, battery }]
    property var devices: []
    property string adapter: ""
    property bool powered: true
    property bool discovering: false
    property string connectedName: ""
    property string status: ""
    property string statusLevel: ""
    // x is two presses, like the wifi popup's forget. Holds the mac that is
    // one press away from being removed.
    property string pendingRemove: ""

    readonly property var selected:
        (root.list.index >= 0 && root.list.index < root.devices.length)
            ? root.devices[root.list.index] : null

    function setStatus(text, level) {
        root.status = text;
        root.statusLevel = level;
    }

    // bluetoothctl colours its output even when piped — sed cannot be trusted
    // to know the escape forms, so it is stripped here where the whole string
    // is in hand.
    function stripAnsi(text) {
        // The ESC is written as an ESCAPE, not as a literal byte. It was a
        // literal one first — invisible in the source, survives a copy only
        // by luck, and indistinguishable from a typo in a review.
        return String(text).replace(/\x1b\[[0-9;]*[A-Za-z]/g, "");
    }

    // ---- THE LIST ----
    //
    // One process for four queries, so the four answers are consistent with
    // each other. Split on a marker rather than run separately: `devices` and
    // `devices Connected` a second apart can disagree, and the row would flip
    // its dot for one refresh.
    Process {
        id: listProc
        command: ["sh", "-c",
            "bluetoothctl show; echo '@@@'; bluetoothctl devices; echo '@@@'; "
            + "bluetoothctl devices Paired; echo '@@@'; bluetoothctl devices Connected"]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = root.stripAnsi(text).split("@@@");
                if (parts.length < 4)
                    return;

                let adapter = "";
                let powered = false;
                let discovering = false;
                for (const line of parts[0].split("\n")) {
                    const t = line.trim();
                    if (t.indexOf("Name:") === 0)
                        adapter = t.substring(5).trim();
                    else if (t.indexOf("Powered:") === 0)
                        powered = t.substring(8).trim() === "yes";
                    else if (t.indexOf("Discovering:") === 0)
                        discovering = t.substring(12).trim() === "yes";
                }
                root.adapter = adapter;
                root.powered = powered;
                root.discovering = discovering;

                const macsIn = (block) => {
                    const set = {};
                    for (const line of block.split("\n")) {
                        const f = line.trim().split(/\s+/);
                        if (f.length >= 2 && f[0] === "Device")
                            set[f[1]] = true;
                    }
                    return set;
                };
                const paired = macsIn(parts[2]);
                const connected = macsIn(parts[3]);

                const out = [];
                let connectedName = "";
                for (const line of parts[1].split("\n")) {
                    const t = line.trim();
                    if (t.indexOf("Device ") !== 0)
                        continue;
                    // split(None, 2): the NAME may contain spaces, so only the
                    // first two fields are split off.
                    const rest = t.substring(7);
                    const sp = rest.indexOf(" ");
                    const mac = sp < 0 ? rest : rest.substring(0, sp);
                    const name = sp < 0 ? mac : rest.substring(sp + 1);
                    const isConn = connected[mac] === true;
                    if (isConn && connectedName === "")
                        connectedName = name;
                    out.push({
                        mac: mac,
                        name: name,
                        // bluez names an unidentified device after its own MAC
                        // with dashes; showing that twice per row is noise.
                        anonymous: name.replace(/-/g, ":").toUpperCase()
                            === mac.toUpperCase(),
                        paired: paired[mac] === true,
                        connected: isConn
                    });
                }

                // The panel's rank order: connected, then paired, then named,
                // then address-only. A scan fills up with passing phones and
                // earbuds, and without the named/unnamed split they interleave
                // alphabetically with the devices you might actually want.
                const rank = (d) => d.connected ? 0 : d.paired ? 1
                    : d.anonymous ? 3 : 2;
                out.sort((a, b) => rank(a) - rank(b)
                    || a.name.localeCompare(b.name));

                root.devices = out;
                root.connectedName = connectedName;
            }
        }
    }

    // ---- DISCOVERY RUNS FOR AS LONG AS THIS IS OPEN ----
    //
    // Not a one-shot. bluez drops every unpaired device the moment discovery
    // stops, so a finite scan gives a list that empties itself. `--timeout` is
    // the file's 300 s ceiling so a forgotten popup cannot discover forever,
    // and the process is killed on close either way.
    // STDOUT IS REDIRECTED IN THE SHELL, NOT LEFT TO QUICKSHELL.
    //
    // Measured: with a bare ["bluetoothctl", …] command the Process reported
    // `running: true` and no bluetoothctl existed two seconds later —
    //
    //     PROBE startDiscovery powered= true wasRunning= false
    //     PROBE after set running= true
    //     $ ps -eo args | grep bluetoothctl        (nothing)
    //
    // while the identical command from a shell with `</dev/null` ran happily
    // for its full timeout. A Process with no stdout consumer has its pipe
    // closed, and `scan on` is CHATTY — it prints a line per device found —
    // so the first discovery event kills it with SIGPIPE. The failure looks
    // exactly like "discovery does not work on this adapter".
    Process {
        id: discoveryProc
        command: ["sh", "-c",
            "exec bluetoothctl --timeout 300 scan on >/dev/null 2>&1"]
    }

    function startDiscovery() {
        if (!root.powered)
            return;
        if (discoveryProc.running)
            return;
        discoveryProc.running = true;
    }

    Component.onCompleted: {
        listProc.running = true;
        root.startDiscovery();
    }
    Component.onDestruction: discoveryProc.running = false

    Timer {
        interval: 3000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: listProc.running = true
    }

    // ---- ACTIONS ----
    Process {
        id: actionProc
        onExited: (code, status) => {
            if (code === 0)
                root.setStatus(root.pendingOk, "ok");
            else
                root.setStatus(root.pendingFail, "error");
            listProc.running = true;
        }
    }
    property string pendingOk: ""
    property string pendingFail: ""

    function run(cmd, busy, ok, fail) {
        root.setStatus(busy, "busy");
        root.pendingOk = ok;
        root.pendingFail = fail;
        actionProc.command = cmd;
        actionProc.running = true;
    }

    // Enter: pair (if needed), trust, then connect — that order, and `trust`
    // is deliberately not fatal. Trusting is what lets the device reconnect on
    // its own next time, and a failure there is not worth aborting a working
    // connect over. `timeout` wraps every call because a connect to an
    // out-of-range device never returns.
    function connectSelected() {
        if (!root.selected)
            return;
        const d = root.selected;
        if (d.connected) {
            root.setStatus("Already connected to " + d.name, "ok");
            return;
        }
        root.pendingRemove = "";
        root.run(["sh", "-c",
            "mac=\"$1\"; paired=\"$2\"\n"
            + "if [ \"$paired\" != yes ]; then\n"
            + "  timeout 45 bluetoothctl pair \"$mac\" || exit 1\n"
            + "  timeout 10 bluetoothctl trust \"$mac\" || true\n"
            + "fi\n"
            + "exec timeout 45 bluetoothctl connect \"$mac\"",
            "sh", d.mac, d.paired ? "yes" : "no"],
            (d.paired ? "Connecting to " : "Pairing with ") + d.name + "…",
            "Connected to " + d.name,
            "Could not connect to " + d.name);
    }

    // d: the selected device, or whatever IS connected if the selection is
    // not. That fallback is the file's, and it is what makes `d` work without
    // hunting for the right row first.
    function disconnectSelected() {
        root.pendingRemove = "";
        let d = root.selected;
        if (!d || !d.connected) {
            d = null;
            for (const c of root.devices) {
                if (c.connected) {
                    d = c;
                    break;
                }
            }
        }
        if (!d) {
            root.setStatus("Nothing connected", "");
            return;
        }
        root.run(["sh", "-c", "exec timeout 45 bluetoothctl disconnect \"$1\"",
                  "sh", d.mac],
            "Disconnecting " + d.name + "…",
            "Disconnected " + d.name,
            "Disconnect failed");
    }

    // x twice. A single press on a paired device is one keystroke away from
    // losing a pairing that took a passkey to make.
    function removeSelected() {
        if (!root.selected)
            return;
        const d = root.selected;
        if (!d.paired) {
            root.pendingRemove = "";
            root.setStatus(d.name + " is not paired", "");
            return;
        }
        if (root.pendingRemove !== d.mac) {
            root.pendingRemove = d.mac;
            root.setStatus("Press x again to remove " + d.name, "error");
            return;
        }
        root.pendingRemove = "";
        root.run(["sh", "-c", "exec timeout 45 bluetoothctl remove \"$1\"",
                  "sh", d.mac],
            "Removing " + d.name + "…",
            "Removed " + d.name,
            "Could not remove " + d.name);
    }

    function togglePower() {
        root.pendingRemove = "";
        const on = !root.powered;
        root.run(["sh", "-c", "exec timeout 10 bluetoothctl power \"$1\"",
                  "sh", on ? "on" : "off"],
            on ? "Turning Bluetooth on…" : "Turning Bluetooth off…",
            on ? "Bluetooth on" : "Bluetooth off",
            "Could not change the radio");
        // Discovery cannot outlive the radio, and restarting it is the only
        // way the list repopulates after a power cycle.
        if (on)
            restartDiscovery.restart();
        else
            discoveryProc.running = false;
    }

    Timer {
        id: restartDiscovery
        interval: 800
        repeat: false
        onTriggered: root.startDiscovery()
    }

    function rescan() {
        root.pendingRemove = "";
        if (!root.powered) {
            root.setStatus("Bluetooth is off — press t first", "error");
            return;
        }
        root.startDiscovery();
        root.setStatus("Discovering…", "busy");
        listProc.running = true;
    }

    // c: killing bluetoothctl only drops the D-BUS CLIENT — bluez carries on
    // with the pairing it was asked for. `cancel-pairing` and `disconnect` are
    // what actually stop it, so both are sent.
    function cancel() {
        if (!actionProc.running) {
            root.setStatus("Nothing to cancel", "");
            return;
        }
        const mac = root.selected ? root.selected.mac : "";
        actionProc.signal(15);
        if (mac !== "") {
            cancelProc.command = ["sh", "-c",
                "timeout 10 bluetoothctl cancel-pairing \"$1\" >/dev/null 2>&1; "
                + "timeout 10 bluetoothctl disconnect \"$1\" >/dev/null 2>&1",
                "sh", mac];
            cancelProc.running = true;
        }
        root.setStatus("Cancelled", "error");
    }

    Process { id: cancelProc }

    Process {
        id: findProc
        stdout: StdioCollector {
            onStreamFinished: {
                const name = text.trim();
                if (name === "")
                    return;
                for (let i = 0; i < root.devices.length; i++) {
                    if (root.devices[i].name === name) {
                        root.list.index = i;
                        root.list.clampIndex();
                        return;
                    }
                }
            }
        }
    }

    function find() {
        if (root.devices.length === 0)
            return;
        const names = root.devices.map((d) => d.name).join("\n");
        findProc.command = ["sh", "-c",
            "printf '%s' \"$1\" | rofi -dmenu -p 'Find device' -i", "sh", names];
        findProc.running = true;
    }

    onKeyPressed: (key, mods, text) => {
        switch (key) {
        case Qt.Key_J: case Qt.Key_Down: root.list.move(1); break;
        case Qt.Key_K: case Qt.Key_Up:   root.list.move(-1); break;
        case Qt.Key_G:
            root.list.jump(mods & Qt.ShiftModifier ? "bottom" : "top");
            break;
        case Qt.Key_Return: case Qt.Key_Enter: root.connectSelected(); break;
        case Qt.Key_D: root.disconnectSelected(); break;
        case Qt.Key_X: root.removeSelected(); break;
        case Qt.Key_T: root.togglePower(); break;
        case Qt.Key_R: root.rescan(); break;
        case Qt.Key_C: root.cancel(); break;
        case Qt.Key_Slash: root.find(); break;
        }
    }

    // Moving the cursor cancels a pending remove. Otherwise `x`, `j`, `x`
    // removes the device you just moved onto, which is the one keystroke
    // sequence a two-press guard exists to make impossible.
    onSelectedChanged: root.pendingRemove = ""

    onDismissed: root.requestClose()

    // ---- BODY ----
    property alias list: devList

    PopupRowList {
        id: devList
        anchors.fill: parent
        rowsVisible: 17
        surface: root.cSurface
        fg: root.cFg
        muted: root.cMuted
        highlight: root.cHighlight
        highlightText: root.cAccentText

        rows: root.devices.map((d) => ({
            mark: root.deviceIcon(d),
            left: d.name.length > 30 ? d.name.substring(0, 29) + "…" : d.name,
            right: (d.connected ? "connected" : d.paired ? "paired" : "")
                + (root.pendingRemove === d.mac ? "   remove?" : ""),
            tone: d.connected ? IslandTheme.success
                : d.anonymous ? root.cMuted : root.cFg
        }))
    }

    // _ICONS, by codepoint. Written with String.fromCodePoint and never as
    // literals: these are private-use characters and the RULES record that
    // they do not survive a round trip through a source file being read back.
    readonly property var iconByClass: ({
        "audio-headset":    0xF02CB,
        "audio-headphones": 0x0F025,
        "audio-card":       0x0F028,
        "audio-speakers":   0x0F028,
        "input-mouse":      0xF037D,
        "input-keyboard":   0x0F11C,
        "input-gaming":     0x0F11B,
        "input-tablet":     0x0F11C,
        "phone":            0x0F10B,
        "computer":         0x0F109,
        "watch":            0xF0B39,
        "printer":          0x0F02F,
        "camera-photo":     0x0F030,
        "camera-video":     0x0F030
    })

    // The list view has no `icon` — that comes from `bluetoothctl info`, one
    // process PER DEVICE, which is exactly the cost that file's header says
    // not to pay for a list. The generic device glyph until then.
    function deviceIcon(d) {
        const cp = root.iconByClass[d.icon || ""];
        return String.fromCodePoint(cp !== undefined ? cp : 0xF00AF);
    }

    // ---- FOOTER ----
    footer: Text {
        anchors.centerIn: parent
        text: root.status !== "" ? root.status
            : (!root.powered ? "Bluetooth is off — press t"
               : root.discovering ? "Discovering…"
               : root.connectedName !== ""
                 ? "Connected to " + root.connectedName
                 : "No device connected")
        color: root.statusLevel === "busy" ? IslandTheme.info
            : root.statusLevel === "ok" ? IslandTheme.success
            : root.statusLevel === "error" ? IslandTheme.danger
            : root.cMuted
        font.family: PopupMetrics.font
        font.pixelSize: PopupMetrics.footSize
        renderType: Text.NativeRendering
    }
}
