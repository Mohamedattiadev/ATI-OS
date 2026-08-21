import QtQuick
import Quickshell
import Quickshell.Io

import "../common"

//
// FORK — new file. popups/WifiPopup.py, in Quickshell.
//
// POPUP_W=940, POPUP_H=600, ROWS_VISIBLE=17, MAX_SSID_LEN=34 — that file's
// numbers. The keys are its chord's, from config.py's Wifi-Mode:
//
//     j k    move            g G    top / bottom
//     ↵      connect         d      disconnect
//     x      forget          n      hidden network
//     t      radio on/off    s      share as QR
//     r      rescan          /      find
//     c      cancel          q Esc  close
//
// WHY nmcli AND NOT THE NetworkManager D-BUS API
// ----------------------------------------------
// WifiPopup.py shells out to nmcli for every one of these, and the reason to
// keep doing so is not laziness: `nmcli device wifi connect` carries the whole
// of the secret-agent dance — asking for a password, retrying, and registering
// the connection — and reimplementing that against the D-Bus API is a great
// deal of code whose failure mode is a network you cannot join.
//
// THE PASSWORD PROMPT IS ROFI
// ---------------------------
// That file drives its own PopupText input because a qtile popup already owns
// the keyboard. This one could too, and deliberately does not: the same rofi
// prompt is what `/` uses for the search here and in the wallpaper picker, and
// the topbar's whole point is that its surfaces are the ones qtile's chips
// open. One prompt, one set of matching rules, and `-password` gets the
// masking right without this file handling a secret at all.
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

    titleIcon: String.fromCodePoint(0xF0928)
    title: "Wi-Fi"
    subtitle: root.iface === "" ? "no wireless device"
        : root.iface + "  ·  " + root.networks.length + " networks"

    badgeLabel: root.radioOn ? "radio on" : "radio off"
    badgeValue: root.connectedTo === "" ? "not connected" : root.connectedTo

    // ONE space, not the wallpaper picker's five — see PopupChrome's
    // hintGap. WifiPopup.py measured this bar and its note is exact:
    // ten chips at two spaces overflow by 6 px, and nothing clips.
    hintGap: PopupMetrics.hintSize * 0.6

    hints: [
        { key: "jk",  desc: "move" },
        { key: "↵", desc: "connect" },
        { key: "d",   desc: "drop" },
        { key: "x",   desc: "forget" },
        { key: "n",   desc: "hidden" },
        { key: "t",   desc: "radio" },
        { key: "s",   desc: "QR" },
        { key: "r",   desc: "rescan" },
        { key: "/",   desc: "find" },
        { key: "Esc", desc: "close" }
    ]

    // ---- STATE ----
    property var networks: []        // [{ ssid, signal, security, active }]
    property string iface: ""
    property bool radioOn: true
    property string connectedTo: ""
    property string status: ""
    // "", "busy", "ok", "error" — render_footer()'s _STATUS_LEVEL, and the
    // same four colours.
    property string statusLevel: ""

    readonly property var selected:
        (root.list.index >= 0 && root.list.index < root.networks.length)
            ? root.networks[root.list.index] : null

    function setStatus(text, level) {
        root.status = text;
        root.statusLevel = level;
    }

    // ---- THE SCAN ----
    //
    // -t -f, i.e. terse and field-selected, so the output is parsed by
    // splitting on ':' rather than by column position — an SSID with a space
    // in it breaks the human-readable form and nothing says so.
    //
    // ESCAPED COLONS: nmcli terse output escapes a literal ':' in a field as
    // '\:', which is exactly what a MAC-shaped SSID or a WPA string can
    // contain. Splitting naively puts the second half of an SSID in the signal
    // column, so the split is done on unescaped separators only.
    Process {
        id: scanProc
        command: ["sh", "-c",
            "nmcli -t -f IN-USE,SSID,SIGNAL,SECURITY device wifi list --rescan no"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                const seen = {};
                for (const line of text.split("\n")) {
                    if (line.trim() === "")
                        continue;
                    const f = root.splitTerse(line);
                    if (f.length < 4)
                        continue;
                    const ssid = f[1];
                    // A hidden network reports an empty SSID and cannot be
                    // connected to by name; `n` is the key for those.
                    if (ssid === "")
                        continue;
                    // nmcli lists one row per BSSID, so a mesh or a repeater
                    // shows the same name several times. Keep the strongest —
                    // but keep IN-USE from ANY of them, which is the half that
                    // was wrong here first time round. Measured on this
                    // machine: three rows for TDV-OGRENCI-KAT-1B at 72, 63 and
                    // 60, and the `*` is on the 63. Folding the flag in only
                    // when the signal improved therefore threw it away, and
                    // the popup said "not connected" while connected.
                    const sig = parseInt(f[2], 10) || 0;
                    if (seen[ssid] !== undefined) {
                        const prev = out[seen[ssid]];
                        prev.active = prev.active || f[0] === "*";
                        if (sig > prev.signal)
                            prev.signal = sig;
                        continue;
                    }
                    seen[ssid] = out.length;
                    out.push({
                        ssid: ssid,
                        signal: sig,
                        security: f[3] === "" ? "open" : f[3],
                        active: f[0] === "*"
                    });
                }
                out.sort((a, b) => b.signal - a.signal);
                root.networks = out;
                for (const n of out) {
                    if (n.active) {
                        root.connectedTo = n.ssid;
                        break;
                    }
                }
            }
        }
    }

    function splitTerse(line) {
        const fields = [];
        let cur = "";
        for (let i = 0; i < line.length; i++) {
            const ch = line[i];
            if (ch === "\\" && i + 1 < line.length) {
                cur += line[i + 1];
                i++;
            } else if (ch === ":") {
                fields.push(cur);
                cur = "";
            } else {
                cur += ch;
            }
        }
        fields.push(cur);
        return fields;
    }

    Process {
        id: stateProc
        command: ["sh", "-c",
            "nmcli -t -f DEVICE,TYPE,STATE device | awk -F: '$2==\"wifi\"{print $1; exit}'; "
            + "echo '---'; nmcli -t radio wifi"]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.split("---");
                root.iface = (parts[0] || "").trim();
                root.radioOn = (parts[1] || "").trim() === "enabled";
            }
        }
    }

    // A poll, not a watch. NetworkManager's signals are on D-Bus and this is
    // a popup that is open for seconds at a time; two nmcli calls every three
    // seconds while it is on screen is cheaper than the machinery to avoid
    // them, and it stops entirely when the Loader deactivates.
    Timer {
        interval: 3000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            stateProc.running = true;
            scanProc.running = true;
        }
    }

    // ---- ACTIONS ----
    //
    // Every one of these reports into the footer, and that is the half a
    // reimplementation usually drops: nmcli takes seconds to fail, and a
    // popup that shows nothing in the meantime is indistinguishable from one
    // that ignored the key. WifiPopup.py has a whole _STATUS_LEVEL for it.
    Process {
        id: actionProc
        onExited: (code, status) => {
            if (code === 0)
                root.setStatus(root.pendingOk, "ok");
            else
                root.setStatus(root.pendingFail + " (exit " + code + ")", "error");
            scanProc.running = true;
            stateProc.running = true;
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

    function connect() {
        if (!root.selected)
            return;
        const ssid = root.selected.ssid;
        // `--ask` would block on a terminal that is not there. A secured
        // network with no saved profile needs the password, and rofi asks for
        // it; an open or already-known one connects without a prompt, which
        // is what nmcli does on its own.
        root.run(["sh", "-c",
            "ssid=\"$1\"\n"
            + "if nmcli -t -f NAME connection show | grep -qxF \"$ssid\"; then\n"
            + "  exec nmcli connection up id \"$ssid\"\n"
            + "fi\n"
            + "sec=\"$2\"\n"
            + "if [ \"$sec\" = open ]; then exec nmcli device wifi connect \"$ssid\"; fi\n"
            + "pw=$(rofi -dmenu -password -p \"Password for $ssid\" </dev/null) || exit 1\n"
            + "[ -n \"$pw\" ] || exit 1\n"
            + "exec nmcli device wifi connect \"$ssid\" password \"$pw\"",
            "sh", ssid, root.selected.security],
            "connecting to " + ssid + "…",
            "connected to " + ssid,
            "could not connect to " + ssid);
    }

    function disconnect() {
        if (root.iface === "")
            return;
        root.run(["nmcli", "device", "disconnect", root.iface],
            "disconnecting…", "disconnected", "disconnect failed");
    }

    function forget() {
        if (!root.selected)
            return;
        const ssid = root.selected.ssid;
        root.run(["nmcli", "connection", "delete", "id", ssid],
            "forgetting " + ssid + "…",
            "forgot " + ssid,
            "no saved profile for " + ssid);
    }

    function connectHidden() {
        root.run(["sh", "-c",
            "ssid=$(rofi -dmenu -p 'Hidden SSID' </dev/null) || exit 1\n"
            + "[ -n \"$ssid\" ] || exit 1\n"
            + "pw=$(rofi -dmenu -password -p \"Password for $ssid\" </dev/null) || exit 1\n"
            + "if [ -n \"$pw\" ]; then\n"
            + "  exec nmcli device wifi connect \"$ssid\" password \"$pw\" hidden yes\n"
            + "fi\n"
            + "exec nmcli device wifi connect \"$ssid\" hidden yes"],
            "joining a hidden network…", "joined", "could not join");
    }

    function toggleRadio() {
        root.run(["nmcli", "radio", "wifi", root.radioOn ? "off" : "on"],
            root.radioOn ? "turning the radio off…" : "turning the radio on…",
            "radio " + (root.radioOn ? "off" : "on"),
            "could not change the radio");
    }

    function rescan() {
        root.run(["nmcli", "device", "wifi", "rescan"],
            "rescanning…", "rescanned", "rescan failed");
    }

    // The QR is the session's own script rather than a second generator —
    // it is the same one the topbar's chip and qtile's w_wifi_qr both call.
    function shareQr() {
        Quickshell.execDetached(
            [Quickshell.env("HOME") + "/.config/hypr/scripts/wifi-qr.py"]);
        root.requestClose();
    }

    // `c` — abort a connect that is hanging. That file's own note: "nmcli
    // connect never returns for an out-of-range device", which is precisely
    // the case where a popup with no cancel leaves you looking at "busy".
    function cancel() {
        if (actionProc.running) {
            actionProc.signal(15);
            root.setStatus("cancelled", "error");
        }
    }

    Process {
        id: findProc
        stdout: StdioCollector {
            onStreamFinished: {
                const name = text.trim();
                if (name === "")
                    return;
                for (let i = 0; i < root.networks.length; i++) {
                    if (root.networks[i].ssid === name) {
                        root.list.index = i;
                        root.list.clampIndex();
                        return;
                    }
                }
            }
        }
    }

    function find() {
        if (root.networks.length === 0)
            return;
        const names = root.networks.map((n) => n.ssid).join("\n");
        findProc.command = ["sh", "-c",
            "printf '%s' \"$1\" | rofi -dmenu -p 'Find network' -i", "sh", names];
        findProc.running = true;
    }

    onKeyPressed: (key, mods, text) => {
        switch (key) {
        case Qt.Key_J: case Qt.Key_Down: root.list.move(1); break;
        case Qt.Key_K: case Qt.Key_Up:   root.list.move(-1); break;
        case Qt.Key_G:
            root.list.jump(mods & Qt.ShiftModifier ? "bottom" : "top");
            break;
        case Qt.Key_Return: case Qt.Key_Enter: root.connect(); break;
        case Qt.Key_D: root.disconnect(); break;
        case Qt.Key_X: root.forget(); break;
        case Qt.Key_N: root.connectHidden(); break;
        case Qt.Key_T: root.toggleRadio(); break;
        case Qt.Key_S: root.shareQr(); break;
        case Qt.Key_R: root.rescan(); break;
        case Qt.Key_C: root.cancel(); break;
        case Qt.Key_Slash: root.find(); break;
        }
    }

    onDismissed: root.requestClose()

    // ---- BODY ----
    property alias list: netList

    PopupRowList {
        id: netList
        anchors.fill: parent
        rowsVisible: 17
        surface: root.cSurface
        fg: root.cFg
        muted: root.cMuted
        highlight: root.cHighlight
        highlightText: root.cAccentText

        rows: root.networks.map((n) => ({
            // A filled dot on the connected network, a hollow one otherwise,
            // so every row is the same width and the names line up — the same
            // trick the wallpaper columns use for their check mark.
            mark: n.active ? String.fromCodePoint(0xF012C)
                           : String.fromCodePoint(0xF0765),
            left: n.ssid.length > 34 ? n.ssid.substring(0, 33) + "…" : n.ssid,
            // The bars glyph plus the number, and a lock when it is secured.
            right: (n.security === "open" ? "     "
                        : String.fromCodePoint(0xF033E) + "  ")
                + root.signalGlyph(n.signal) + "  "
                + (n.signal < 10 ? "  " : n.signal < 100 ? " " : "") + n.signal + "%",
            tone: n.active ? IslandTheme.success : root.cFg
        }))
    }

    // Four bars, as nm-applet and every wifi menu on this desktop draw them.
    function signalGlyph(sig) {
        if (sig >= 75) return String.fromCodePoint(0xF0928);
        if (sig >= 50) return String.fromCodePoint(0xF0925);
        if (sig >= 25) return String.fromCodePoint(0xF0922);
        return String.fromCodePoint(0xF091F);
    }

    // ---- FOOTER ----
    footer: Text {
        anchors.centerIn: parent
        text: root.status === ""
            ? (root.connectedTo === ""
                ? "not connected" : "connected to " + root.connectedTo)
            : root.status
        color: root.statusLevel === "busy" ? IslandTheme.info
            : root.statusLevel === "ok" ? IslandTheme.success
            : root.statusLevel === "error" ? IslandTheme.danger
            : root.cMuted
        font.family: PopupMetrics.font
        font.pixelSize: PopupMetrics.footSize
        renderType: Text.NativeRendering
    }
}
