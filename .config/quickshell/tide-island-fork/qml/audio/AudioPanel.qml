pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import IslandBackend

// FORK: the shared scale factor — see qml/common/Metrics.js.
import "../common/Metrics.js" as Metrics

//
// FORK — new file. The port of qtile's popups/AudioPopup.py (25 bindings),
// the last of the big popup holes the migration left.
//
// WHY THIS EXISTS WHEN THE CONTROL CENTRE ALREADY HAS A SOUND SLIDER
// ------------------------------------------------------------------
// Because a slider on the default sink is one of the eight things that popup
// did. It could not: pick which output is the default AND drag the already
// playing streams across with it, pick the default microphone, set a single
// application's volume, route a single application to a different device
// (browser on the headset, video player on the speakers), switch a card
// PROFILE (A2DP vs HSP/HFP — hi-fi with no microphone versus a working
// microphone that sounds like a telephone), switch an output PORT (speakers
// versus the headphone jack on one and the same card), or show what is
// recording right now. None of those had a keyboard path on Hyprland, and
// pavucontrol is not installed on this machine.
//
// This layer deliberately owns NO knowledge of how PipeWire's pulse shim
// spells anything: every pactl verb, every namespace trap and the card ↔
// device matching heuristic live in hypr/scripts/audio-ctl.py, where they can
// be run from a shell. Same split as DisplayPanel.qml, for the same reason.
//
// KEYMAP — qtile's Audio-Mode, key for key ($alt 3)
// -------------------------------------------------
//   j / k          move the cursor            g / G   top / bottom
//   Tab / S-Tab    cycle the four tabs
//   o i a s        outputs · microphones · playback · recording
//   Return         use the row  (output: set default AND move live streams;
//                  stream: open the device picker; card: open its profiles)
//   h / l          volume down / up           m       mute
//   d              send this stream to the default device
//   p              card profiles of the selected device
//   Shift+P        output/input PORTS of the selected device
//   Shift+C        every card at once — pavucontrol's Configuration tab
//   b / Shift+B    balance left / right       0       re-centre
//   r              re-read                    c       cancel a slow switch
//   q / Escape     close
//
// Not a submap. qtile needed a KeyChord because its popup could not take
// keyboard focus at all; this is a layer surface with an exclusive grab that
// reads its own keys, so none of them can leak to the window behind it.
//
FocusScope {
    id: root

    signal closeRequested

    property bool showCondition: false
    property string textFontFamily: ""
    property string heroFontFamily: ""

    // --- model -------------------------------------------------------------
    property var outputs: []
    property var inputs: []
    property var playback: []
    property var recording: []
    property var cards: []
    property string defaultSink: ""
    property string defaultSource: ""

    readonly property var tabs: ["outputs", "inputs", "playback", "recording"]
    property string view: "outputs"
    // One cursor per view, so leaving a list and coming back puts you where
    // you were. A single shared index would move the outputs cursor every
    // time you scrolled the playback list.
    property var cursor: ({})

    // The card whose profiles the profiles view shows, set when p is pressed:
    // the view keeps describing THAT card even if the outputs cursor moves
    // underneath it. Same for the ports device and the stream being moved.
    property var profileCard: null
    property var portDevice: null
    property bool portIsInput: false
    property var targetStream: null
    property bool targetIsInput: false

    property string statusText: "Ready"
    property string statusLevel: "idle"          // idle | busy | ok | error
    property bool busy: false

    readonly property int volumeStep: 5
    readonly property int volumeMax: 150          // what pavucontrol allows
    readonly property int volumeUnity: 100
    readonly property real balanceStep: 0.1

    readonly property real horizontalPadding: Metrics.pad(18)
    readonly property real headerHeight: Metrics.pad(34)
    readonly property real rowHeight: Metrics.px(26)

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
            root.cursor = ({});
            root.profileCard = null;
            root.portDevice = null;
            root.targetStream = null;
            root.pending = ({});
            root.setStatus("reading devices…", "busy");
            root.refresh();
            pollTimer.start();
            forceActiveFocus();
        } else {
            pollTimer.stop();
        }
    }

    // --- selection ---------------------------------------------------------
    readonly property var currentItems: {
        switch (root.view) {
        case "outputs":   return root.outputs;
        case "inputs":    return root.inputs;
        case "playback":  return root.playback;
        case "recording": return root.recording;
        case "cards":     return root.cards;
        case "ports":     return root.portDevice ? root.portDevice.ports : [];
        case "profiles":  return root.profileCard ? root.profileCard.profiles : [];
        // Where the stream being moved could go.
        case "targets":   return root.targetIsInput ? root.inputs : root.outputs;
        }
        return [];
    }

    readonly property int selectedIndex: {
        const raw = root.cursor[root.view] || 0;
        const count = root.currentItems.length;
        return Math.max(0, Math.min(raw, Math.max(0, count - 1)));
    }

    function selected() {
        const items = root.currentItems;
        if (root.selectedIndex >= 0 && root.selectedIndex < items.length)
            return items[root.selectedIndex];
        return null;
    }

    function setCursor(index) {
        const next = Object.assign({}, root.cursor);
        next[root.view] = Math.max(0, index);
        root.cursor = next;
        listView.positionViewAtIndex(root.selectedIndex, ListView.Contain);
    }

    readonly property bool isStreamView: root.view === "playback" || root.view === "recording"
    // A WHITELIST of the views whose rows carry a volume at all, not a
    // blacklist. Profiles, ports and cards are objects with no vol/mute, and
    // enumerating the views that DO have one means adding a view can never
    // reintroduce the undefined the qtile version hit when `l` was pressed in
    // the cards list.
    readonly property bool hasVolume: root.tabs.indexOf(root.view) >= 0

    function setStatus(text, level) {
        root.statusText = text;
        root.statusLevel = level || "idle";
    }

    // The property that holds the rows of the current view, by NAME — so a
    // local edit can write the list back and not merely poke at a row.
    readonly property string poolProperty: {
        switch (root.view) {
        case "outputs":   return "outputs";
        case "inputs":    return "inputs";
        case "playback":  return "playback";
        case "recording": return "recording";
        }
        return "";
    }

    //
    // Apply a local change to the selected row.
    //
    // It replaces the whole array rather than assigning to a field of the
    // object the delegate is showing, and that is not fussiness: a `var`
    // model holding plain JS objects has NOTHING to notify on when one of
    // their fields changes. Mutating in place worked for the details column
    // (its Repeater model is a JS expression that other things re-evaluate)
    // and left the list row showing the old number — the volume bar simply
    // did not move, while the readout beside it did. Reassigning the property
    // is the only change QML actually sees.
    //
    // Cheap at this size: these lists are single digits of rows, and the
    // alternative — a QAbstractListModel per view — is a large amount of
    // machinery to avoid copying eight objects on a keypress.
    //
    function patchSelected(changes) {
        const name = root.poolProperty;
        if (name === "")
            return null;
        const pool = root[name].slice();
        const at = root.selectedIndex;
        if (at < 0 || at >= pool.length)
            return null;
        const item = Object.assign({}, pool[at], changes);
        pool[at] = item;
        root[name] = pool;
        return item;
    }

    // --- optimistic values -------------------------------------------------
    //
    // A refresh that STARTED before a volume keypress landed comes back
    // carrying the pre-keypress value, and applying it drags the bar
    // backwards under your fingers — which is exactly what makes rapid
    // presses look like they are being ignored. So a locally applied value
    // outranks what the daemon reports until it has had time to agree.
    //
    property var pending: ({})
    readonly property int pendingHoldMs: 1200

    function identityOf(item) {
        if (!item)
            return "";
        // Devices by NAME. Their indices are PipeWire serials that move on
        // their own (see audio-ctl.py). Streams have no name, so they are
        // keyed by app+media, which survives a renumber and is what you are
        // actually pointing at.
        if (item.name !== undefined && item.name !== "")
            return "dev:" + item.name;
        return "stream:" + item.app + "|" + item.media;
    }

    function remember(item, volume, mute) {
        const key = root.identityOf(item);
        if (key === "")
            return;
        const next = Object.assign({}, root.pending);
        const entry = Object.assign({}, next[key] || {});
        if (volume !== undefined && volume !== null)
            entry.vol = volume;
        if (mute !== undefined && mute !== null)
            entry.mute = mute;
        entry.until = Date.now() + root.pendingHoldMs;
        next[key] = entry;
        root.pending = next;
    }

    function applyPending(pool) {
        const now = Date.now();
        for (let i = 0; i < pool.length; i++) {
            const entry = root.pending[root.identityOf(pool[i])];
            if (!entry || entry.until <= now)
                continue;
            if (entry.vol !== undefined)
                pool[i].vol = entry.vol;
            if (entry.mute !== undefined)
                pool[i].mute = entry.mute;
        }
        return pool;
    }

    // --- talking to audio-ctl.py -------------------------------------------
    readonly property string ctl: Quickshell.env("HOME") + "/.config/hypr/scripts/audio-ctl.py"

    function refresh() {
        if (!queryProcess.running)
            queryProcess.running = true;
    }

    Timer {
        id: pollTimer
        // Devices and streams appear and vanish without telling anyone — a
        // headset connects, a video ends. Three seconds is qtile's cadence,
        // and nothing polls while the panel is closed.
        interval: 3000
        repeat: true
        onTriggered: root.refresh()
    }

    Process {
        id: queryProcess
        command: [root.ctl, "query"]
        stdout: StdioCollector {
            onStreamFinished: {
                let parsed = null;
                try {
                    parsed = JSON.parse(text);
                } catch (error) {
                    // Not JSON means audio-ctl.py crashed. Say so, rather
                    // than showing empty lists that read as "you have no
                    // sound devices".
                    root.setStatus("audio-ctl produced no readable output", "error");
                    return;
                }
                root.outputs = root.applyPending(parsed.outputs || []);
                root.inputs = root.applyPending(parsed.inputs || []);
                root.playback = root.applyPending(parsed.playback || []);
                root.recording = root.applyPending(parsed.recording || []);
                root.cards = parsed.cards || [];
                root.defaultSink = String(parsed.defaultSink || "");
                root.defaultSource = String(parsed.defaultSource || "");
                root.reconcileSubViews();
                // Clear the "reading devices…" the open put up. Only when the
                // status is still the busy one: an "output: Headphones" that
                // a poll three seconds later wiped would leave the panel
                // unable to tell you anything ever happened.
                if (root.statusLevel === "busy" && !root.busy)
                    root.setStatus(root.outputs.length + (root.outputs.length === 1 ? " output · " : " outputs · ")
                                   + root.playback.length + (root.playback.length === 1 ? " stream" : " streams"), "idle");
            }
        }
    }

    // Re-bind the sub-views to the objects the refresh just replaced.
    // Without this the ports view keeps marking the PRE-refresh active port,
    // and a profiles view whose card is gone (a Bluetooth device that just
    // disconnected takes its card with it) shows a list of dead profiles.
    function reconcileSubViews() {
        if (root.profileCard !== null) {
            let found = null;
            for (let i = 0; i < root.cards.length; i++) {
                if (root.cards[i].name === root.profileCard.name)
                    found = root.cards[i];
            }
            root.profileCard = found;
            if (found === null && root.view === "profiles")
                root.setView("outputs");
        }
        if (root.portDevice !== null) {
            const pool = root.portIsInput ? root.inputs : root.outputs;
            let found = null;
            for (let i = 0; i < pool.length; i++) {
                if (pool[i].name === root.portDevice.name)
                    found = pool[i];
            }
            root.portDevice = found;
            if (found === null && root.view === "ports")
                root.setView("outputs");
        }
        if (root.targetStream !== null) {
            const pool = root.targetIsInput ? root.recording : root.playback;
            let found = null;
            for (let i = 0; i < pool.length; i++) {
                if (root.identityOf(pool[i]) === root.identityOf(root.targetStream))
                    found = pool[i];
            }
            root.targetStream = found;
            // The app stopped playing while its device picker was open.
            if (found === null && root.view === "targets")
                root.setView(root.targetIsInput ? "recording" : "playback");
        }
    }

    // Mutating calls that the UI waits on: set a default, switch a profile or
    // a port, move a stream. Serialised through one Process on purpose — two
    // of these racing produce a routing neither of them asked for.
    Process {
        id: actionProcess
        property string successText: ""
        // When set, the backend's own status is KEPT and this goes in front of
        // it. Only default-sink needs that, and it needs it badly: the panel
        // knows the device's name and the backend knows how many live streams
        // it dragged across, and dropping either half loses the answer to "did
        // it actually move my music".
        property string successPrefix: ""
        stdout: StdioCollector {
            onStreamFinished: {
                root.busy = false;
                let result = null;
                try {
                    result = JSON.parse(text);
                } catch (error) {
                    root.setStatus("audio-ctl failed", "error");
                    root.refresh();
                    return;
                }
                if (result.ok)
                    root.setStatus(actionProcess.successPrefix !== ""
                                   ? actionProcess.successPrefix + " · " + String(result.status)
                                   : (actionProcess.successText || String(result.status)), "ok");
                else
                    root.setStatus(String(result.status || "failed"), "error");
                // Re-read either way, so the rows agree with what PipeWire
                // actually did rather than with what we asked for.
                root.refresh();
            }
        }
    }

    function act(args, message, successText, successPrefix) {
        if (root.busy)
            return;
        root.busy = true;
        root.setStatus(message, "busy");
        actionProcess.successText = successText || "";
        actionProcess.successPrefix = successPrefix || "";
        actionProcess.command = [root.ctl].concat(args);
        actionProcess.running = true;
    }

    // Volume and mute do NOT go through act(). They must never block on the
    // previous keypress, and holding `l` fires far faster than a process can
    // round-trip: writes are coalesced here, newest per device wins, so ten
    // fast presses cost one or two processes instead of ten. The UI is
    // already showing the new value by then — see remember().
    property var writeQueue: ({})

    Process {
        id: writeProcess
        onExited: root.flushWrites()
    }

    function queueWrite(key, args) {
        const next = Object.assign({}, root.writeQueue);
        next[key] = args;
        root.writeQueue = next;
        if (!writeProcess.running)
            root.flushWrites();
    }

    function flushWrites() {
        const keys = Object.keys(root.writeQueue);
        if (keys.length === 0)
            return;
        const args = root.writeQueue[keys[0]];
        const next = Object.assign({}, root.writeQueue);
        delete next[keys[0]];
        root.writeQueue = next;
        writeProcess.command = [root.ctl].concat(args);
        writeProcess.running = true;
    }

    // --- navigation --------------------------------------------------------
    function move(step) {
        const count = root.currentItems.length;
        if (count === 0)
            return;
        root.setCursor(Math.max(0, Math.min(count - 1, root.selectedIndex + step)));
    }

    function jump(where) {
        const count = root.currentItems.length;
        if (count === 0)
            return;
        root.setCursor(where === "top" ? 0 : count - 1);
    }

    function setView(next) {
        if (next === "profiles" && root.profileCard === null)
            return;
        if (next === "ports" && root.portDevice === null)
            return;
        if (next === "targets" && root.targetStream === null)
            return;
        if (next === "cards" && root.cards.length === 0) {
            root.setStatus("no sound cards found", "idle");
            return;
        }
        root.view = next;
        listView.positionViewAtIndex(root.selectedIndex, ListView.Contain);
    }

    // Tab cycles the four TABS only. Ports and profiles are deliberately
    // outside it: they describe one device rather than standing beside the
    // lists, and Tab landing on a stale port list every time round was worse
    // than reaching it with Shift+P. Tab out of a sub-view returns to the tab
    // it was opened from, so Tab never dead-ends.
    function cycleView(step) {
        const at = root.tabs.indexOf(root.view);
        if (at < 0) {
            if (root.view === "targets")
                root.setView(root.targetIsInput ? "recording" : "playback");
            else if (root.view === "ports" && root.portIsInput)
                root.setView("inputs");
            else
                root.setView("outputs");
            return;
        }
        root.setView(root.tabs[(at + step + root.tabs.length) % root.tabs.length]);
    }

    // --- actions -----------------------------------------------------------
    function activate() {
        const item = root.selected();
        if (item === null || root.busy)
            return;

        if (root.view === "profiles") {
            if (root.profileCard === null)
                return;
            root.act(["card-profile", root.profileCard.name, item.name],
                     "switching to " + item.desc + "…", "profile: " + item.desc);
            return;
        }

        if (root.view === "ports") {
            if (root.portDevice === null)
                return;
            if (!item.available) {
                // pactl accepts the switch, reports success, and routes the
                // sound at a jack with nothing in it — indistinguishable
                // from broken audio. audio-ctl.py refuses it too; this is
                // the version that can explain itself.
                root.setStatus(item.desc + " has nothing plugged in", "error");
                return;
            }
            root.act(["port", root.portIsInput ? "source" : "sink",
                      root.portDevice.name, item.name],
                     "switching to " + item.desc + "…", "port: " + item.desc);
            return;
        }

        // Enter on a card opens its profiles, which is the only thing there
        // is to do with a card.
        if (root.view === "cards") {
            root.openProfilesFor(item);
            return;
        }

        if (root.view === "targets") {
            const stream = root.targetStream;
            if (stream === null)
                return;
            root.act(["move", root.targetIsInput ? "source-output" : "sink-input",
                      String(stream.index), item.name],
                     "moving " + stream.app + "…", stream.app + " → " + item.desc);
            root.setView(root.targetIsInput ? "recording" : "playback");
            return;
        }

        // Enter on a stream opens the device picker rather than assuming the
        // default. Sending everything to the default is the common case but
        // not the interesting one — `d` is the shortcut for that.
        if (root.isStreamView) {
            root.showTargets();
            return;
        }

        if (root.view === "inputs") {
            root.act(["default-source", item.name],
                     "switching to " + item.desc + "…", "microphone: " + item.desc);
            return;
        }

        // The headline action. audio-ctl.py's default-sink also drags every
        // live stream across, because Pulse routes only NEW streams to a new
        // default — set it alone and the music keeps playing out of the
        // device you just switched away from.
        root.act(["default-sink", item.name],
                 "switching to " + item.desc + "…", "", "output: " + item.desc);
    }

    function changeVolume(step) {
        const item = root.selected();
        if (item === null || !root.hasVolume)
            return;
        const target = Math.max(0, Math.min(root.volumeMax, item.vol + step));
        let scope = "sink";
        let ident = item.name;
        let label = item.desc;
        if (root.view === "playback") {
            scope = "sink-input"; ident = String(item.index); label = item.app;
        } else if (root.view === "recording") {
            scope = "source-output"; ident = String(item.index); label = item.app;
        } else if (root.view === "inputs") {
            scope = "source";
        }
        // Optimistic and immediate: set it, draw it, and let the coalescer
        // write it out behind you.
        root.patchSelected({ "vol": target });
        root.remember(item, target, undefined);
        root.setStatus(label + "  " + target + "%", "ok");
        root.queueWrite("vol:" + root.identityOf(item),
                        ["volume", scope, ident, String(target)]);
    }

    function toggleMute() {
        const item = root.selected();
        if (item === null || !root.hasVolume)
            return;
        let scope = "sink";
        let ident = item.name;
        let label = item.desc;
        if (root.view === "playback") {
            scope = "sink-input"; ident = String(item.index); label = item.app;
        } else if (root.view === "recording") {
            scope = "source-output"; ident = String(item.index); label = item.app;
        } else if (root.view === "inputs") {
            scope = "source";
        }
        const muted = !item.mute;
        root.patchSelected({ "mute": muted });
        root.remember(item, undefined, muted);
        root.setStatus(label + "  " + (muted ? "muted" : "unmuted"), "ok");
        root.queueWrite("mute:" + root.identityOf(item),
                        ["mute", scope, ident, "toggle"]);
    }

    function changeBalance(step) {
        const item = root.selected();
        if (item === null || (root.view !== "outputs" && root.view !== "inputs"))
            return;
        if (item.nchannels !== 2) {
            root.setStatus("balance needs a stereo device", "idle");
            return;
        }
        let balance = Number(item.balance) || 0;
        balance = step === 0 ? 0 : Math.max(-1, Math.min(1, balance + step));
        root.patchSelected({ "balance": balance });
        root.setStatus(item.desc + "  balance " + root.balanceLabel(balance), "ok");
        root.queueWrite("bal:" + root.identityOf(item),
                        ["balance", root.view === "inputs" ? "source" : "sink",
                         item.name, String(item.vol), String(balance)]);
    }

    function balanceLabel(balance) {
        if (Math.abs(balance) < 0.005)
            return "centre";
        return Math.round(Math.abs(balance) * 100) + "% " + (balance > 0 ? "R" : "L");
    }

    function showTargets() {
        const stream = root.selected();
        if (!root.isStreamView || stream === null)
            return;
        root.targetIsInput = root.view === "recording";
        const pool = root.targetIsInput ? root.inputs : root.outputs;
        if (pool.length === 0) {
            root.setStatus("nowhere to move it to", "idle");
            return;
        }
        root.targetStream = stream;
        root.view = "targets";
        // Land on the device it is already using, so Enter-Enter is a no-op
        // rather than a surprise move.
        let at = 0;
        for (let i = 0; i < pool.length; i++) {
            if (pool[i].index === stream.target)
                at = i;
        }
        root.setCursor(at);
        root.setStatus("move " + stream.app + " to…", "idle");
    }

    function sendToDefault() {
        const stream = root.selected();
        if (!root.isStreamView || stream === null || root.busy)
            return;
        const playbackView = root.view === "playback";
        const target = playbackView ? root.defaultSink : root.defaultSource;
        if (target === "") {
            root.setStatus("no default device", "error");
            return;
        }
        root.act(["move", playbackView ? "sink-input" : "source-output",
                  String(stream.index), target],
                 "moving " + stream.app + "…", "moved " + stream.app);
    }

    function openProfilesFor(card) {
        if (!card)
            return;
        root.profileCard = card;
        root.view = "profiles";
        let at = 0;
        for (let i = 0; i < card.profiles.length; i++) {
            if (card.profiles[i].name === card.active)
                at = i;
        }
        root.setCursor(at);
    }

    // p — the card of whatever the cursor is on. "Which profile is my headset
    // on" is the question, and the card that answers it is the one owning the
    // row you are looking at.
    function showProfiles() {
        if (root.view === "profiles") {
            root.setView("outputs");
            return;
        }
        let device = (root.view === "outputs" || root.view === "inputs") ? root.selected() : null;
        if (device === null) {
            // From a stream view, fall back to the default output's card, so
            // pressing p there still gets somewhere useful.
            for (let i = 0; i < root.outputs.length; i++) {
                if (root.outputs[i].name === root.defaultSink)
                    device = root.outputs[i];
            }
        }
        const cardName = device ? device.card : "";
        let card = null;
        for (let i = 0; i < root.cards.length; i++) {
            if (root.cards[i].name === cardName)
                card = root.cards[i];
        }
        if (card === null) {
            root.setStatus("no card for this device", "idle");
            return;
        }
        root.openProfilesFor(card);
    }

    // Shift+P — the dropdown at the top of pavucontrol's device rows, and the
    // reason the headphone jack was unreachable from the keyboard: one sink
    // exposes Speakers, Headphones and Line Out and only one of them is live.
    function showPorts() {
        if (root.view === "ports") {
            root.setView("outputs");
            return;
        }
        let device = null;
        let isInput = false;
        if (root.view === "outputs" || root.view === "inputs") {
            device = root.selected();
            isInput = root.view === "inputs";
        } else {
            for (let i = 0; i < root.outputs.length; i++) {
                if (root.outputs[i].name === root.defaultSink)
                    device = root.outputs[i];
            }
        }
        if (device === null || !device.ports || device.ports.length === 0) {
            root.setStatus("this device has no selectable ports", "idle");
            return;
        }
        root.portDevice = device;
        root.portIsInput = isInput;
        root.view = "ports";
        let at = 0;
        for (let i = 0; i < device.ports.length; i++) {
            if (device.ports[i].name === device.port)
                at = i;
        }
        root.setCursor(at);
    }

    // Shift+C — every card at once. The per-device `p` answers "what is THIS
    // thing doing"; this answers "what is everything doing", which is the
    // question when the card in the wrong mode is one you are not pointing at.
    function showCards() {
        root.setView(root.view === "cards" ? "outputs" : "cards");
    }

    function cancel() {
        if (!root.busy) {
            root.setStatus("nothing to cancel", "idle");
            return;
        }
        // Honest, not pretend-undo: killing pactl only drops the client, and
        // PipeWire carries on with the profile change it was asked for. There
        // is no counter-command for a profile switch, so this stops WAITING
        // and lets the follow-up refresh show whatever actually landed.
        actionProcess.running = false;
        root.busy = false;
        root.setStatus("cancelled — the switch may still complete", "idle");
        root.refresh();
    }

    // --- keys --------------------------------------------------------------
    Keys.onPressed: function(event) {
        const shift = (event.modifiers & Qt.ShiftModifier) !== 0;

        switch (event.key) {
        case Qt.Key_Escape:
        case Qt.Key_Q:
            root.closeRequested();
            break;
        case Qt.Key_J:
        case Qt.Key_Down:
            root.move(1);
            break;
        case Qt.Key_K:
        case Qt.Key_Up:
            root.move(-1);
            break;
        case Qt.Key_G:
            root.jump(shift ? "bottom" : "top");
            break;
        case Qt.Key_Tab:
            root.cycleView(1);
            break;
        case Qt.Key_Backtab:
            root.cycleView(-1);
            break;
        case Qt.Key_O:
            root.setView("outputs");
            break;
        case Qt.Key_I:
            root.setView("inputs");
            break;
        case Qt.Key_A:
            root.setView("playback");
            break;
        case Qt.Key_S:
            root.setView("recording");
            break;
        case Qt.Key_P:
            if (shift)
                root.showPorts();
            else
                root.showProfiles();
            break;
        case Qt.Key_C:
            if (shift)
                root.showCards();
            else
                root.cancel();
            break;
        case Qt.Key_D:
            root.sendToDefault();
            break;
        case Qt.Key_B:
            root.changeBalance(shift ? root.balanceStep : -root.balanceStep);
            break;
        case Qt.Key_0:
            root.changeBalance(0);
            break;
        case Qt.Key_Return:
        case Qt.Key_Enter:
            root.activate();
            break;
        case Qt.Key_L:
        case Qt.Key_Right:
            root.changeVolume(root.volumeStep);
            break;
        case Qt.Key_H:
        case Qt.Key_Left:
            root.changeVolume(-root.volumeStep);
            break;
        case Qt.Key_M:
            root.toggleMute();
            break;
        case Qt.Key_R:
            root.setStatus("re-reading devices…", "busy");
            root.refresh();
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
        y: Metrics.pad(10)
        text: "Audio"
        color: "white"
        font.pixelSize: Metrics.font(15)
        font.family: root.heroFontFamily
        font.weight: Font.DemiBold
        font.letterSpacing: -0.2
    }

    // The four tabs, plus whichever sub-view is open. Ports, profiles, cards
    // and the move-to picker only appear once something has opened them —
    // they are not in the Tab cycle, so advertising them permanently would
    // suggest they are.
    Row {
        anchors.left: header.right
        anchors.leftMargin: Metrics.pad(14)
        y: Metrics.pad(12)
        spacing: Metrics.pad(10)

        Repeater {
            model: {
                const labels = [["outputs", "outputs"], ["inputs", "mics"],
                                ["playback", "playback"], ["recording", "recording"]];
                if (root.portDevice !== null || root.view === "ports")
                    labels.push(["ports", "ports"]);
                if (root.profileCard !== null || root.view === "profiles")
                    labels.push(["profiles", "profiles"]);
                if (root.view === "cards")
                    labels.push(["cards", "cards"]);
                if (root.view === "targets")
                    labels.push(["targets", "move to…"]);
                return labels;
            }
            delegate: Text {
                required property var modelData
                text: modelData[1]
                color: root.view === modelData[0] ? "white" : "#6a6a6a"
                font.pixelSize: Metrics.font(11)
                font.family: root.textFontFamily
                font.weight: root.view === modelData[0] ? Font.DemiBold : Font.Normal
            }
        }
    }

    // The default output, which is what this panel is mostly about, in the
    // header's right-hand slot — it is the one fact you want without reading
    // a row, and it is what every other view is relative to.
    Text {
        anchors.right: parent.right
        anchors.rightMargin: root.horizontalPadding
        y: Metrics.pad(12)
        width: Math.min(implicitWidth, root.width * 0.5)
        horizontalAlignment: Text.AlignRight
        elide: Text.ElideRight
        font.pixelSize: Metrics.font(11)
        font.family: root.textFontFamily
        color: root.statusLevel === "error" ? "#ff6b6b"
             : (root.statusLevel === "ok" ? "#9ad18a"
             : (root.statusLevel === "busy" ? "#ffcc66" : "#8a8a8a"))
        text: root.statusText
    }

    ListView {
        id: listView
        x: root.horizontalPadding
        y: root.headerHeight + Metrics.pad(4)
        width: parent.width * 0.56 - root.horizontalPadding
        height: parent.height - root.headerHeight - Metrics.pad(30)
        clip: true
        model: root.currentItems
        currentIndex: root.selectedIndex
        boundsBehavior: Flickable.StopAtBounds
        spacing: 2

        // Nothing here rather than an empty box: an empty list and a broken
        // panel look identical, and every one of these has a different
        // answer to "what do I do about it".
        Text {
            anchors.centerIn: parent
            visible: listView.count === 0
            color: "#6a6a6a"
            font.pixelSize: Metrics.font(11)
            font.family: root.textFontFamily
            text: {
                switch (root.view) {
                case "outputs":   return "no outputs — r to re-read";
                case "inputs":    return "no microphones found";
                case "playback":  return "nothing is playing";
                case "recording": return "nothing is recording";
                case "ports":     return "this device has no selectable ports";
                case "profiles":  return "no card for this device";
                case "cards":     return "no sound cards found";
                case "targets":   return "nowhere to move this stream";
                }
                return "nothing here";
            }
        }

        delegate: Rectangle {
            id: row
            required property int index
            required property var modelData

            width: listView.width
            height: root.rowHeight
            radius: Metrics.px(7)
            color: row.index === root.selectedIndex ? "#22ffffff" : "transparent"

            // Ports, profiles and cards are rows with no volume at all, and
            // their delegates still evaluate the bar's bindings before
            // `visible: false` hides it — undefined/150 is NaN, and a NaN
            // width warns on every frame. Read them once, defensively.
            readonly property int vol: row.modelData.vol === undefined ? 0 : row.modelData.vol
            readonly property bool muted: row.modelData.mute === true

            readonly property bool isDefault: {
                if (root.view === "outputs" || (root.view === "targets" && !root.targetIsInput))
                    return row.modelData.name === root.defaultSink;
                if (root.view === "inputs" || (root.view === "targets" && root.targetIsInput))
                    return row.modelData.name === root.defaultSource;
                if (root.view === "ports")
                    return root.portDevice && row.modelData.name === root.portDevice.port;
                if (root.view === "profiles")
                    return root.profileCard && row.modelData.name === root.profileCard.active;
                return false;
            }

            Text {
                id: label
                anchors.left: parent.left
                anchors.leftMargin: Metrics.pad(10)
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width * (root.hasVolume ? 0.56 : 0.95) - Metrics.pad(14)
                elide: Text.ElideRight
                color: row.isDefault ? "#9ad18a" : "white"
                font.pixelSize: Metrics.font(12)
                font.family: root.textFontFamily
                font.weight: row.isDefault ? Font.DemiBold : Font.Normal
                text: {
                    switch (root.view) {
                    case "cards":
                        return row.modelData.desc + "   " + row.modelData.activeDesc;
                    case "profiles":
                        return row.modelData.desc
                            + (row.modelData.note !== "" ? "   (" + row.modelData.note + ")" : "");
                    case "ports":
                        return row.modelData.desc
                            + (row.modelData.available ? "" : "   unplugged");
                    case "playback":
                    case "recording":
                        return (row.modelData.media !== "" ? row.modelData.media : row.modelData.app)
                            + (row.modelData.corked ? "   paused" : "");
                    case "targets":
                        return row.modelData.desc
                            + (root.targetStream && row.modelData.index === root.targetStream.target
                               ? "   current" : "");
                    }
                    return (row.isDefault ? "● " : "") + row.modelData.desc;
                }
            }

            // The level bar. A real rectangle rather than qtile's box-drawing
            // characters — that popup drew it in text because it had nothing
            // but a Pango layout to draw into.
            //
            // The scale runs to 150%, with the 100% mark drawn on it, so a
            // boosted device reads as "past the line" rather than merely
            // "full". Everything above unity is software amplification and
            // can clip, which is why it turns red rather than being refused:
            // a hard cap at 100 was the one thing the qtile popup could not
            // do that pavucontrol could.
            Item {
                visible: root.hasVolume
                anchors.right: readout.left
                anchors.rightMargin: Metrics.pad(8)
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width * 0.28
                height: Metrics.px(6)

                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: "#26ffffff"
                }
                Rectangle {
                    height: parent.height
                    radius: height / 2
                    width: row.muted
                        ? 0
                        : parent.width * Math.max(0, Math.min(1, row.vol / root.volumeMax))
                    color: row.vol > root.volumeUnity ? "#ff6b6b" : "#9ad18a"
                }
                // The unity mark, so 100% is a place on the bar and not just
                // a number in the readout.
                Rectangle {
                    x: parent.width * root.volumeUnity / root.volumeMax
                    width: 1
                    height: parent.height
                    color: "#88ffffff"
                }
            }

            Text {
                id: readout
                visible: root.hasVolume
                anchors.right: parent.right
                anchors.rightMargin: Metrics.pad(10)
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignRight
                width: Metrics.px(44)
                font.pixelSize: Metrics.font(11)
                font.family: root.textFontFamily
                color: (row.muted || row.vol > root.volumeUnity) ? "#ff6b6b" : "#d0d0d0"
                text: row.muted ? "mute" : row.vol + "%"
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                onEntered: root.setCursor(row.index)
                onClicked: root.activate()
            }
        }
    }

    // Details for whatever the cursor is on. The list alone cannot say what a
    // row IS — which card a sink belongs to, what a profile trades away, what
    // is plugged into a port — and those are exactly the fields with no cue
    // anywhere else on the system.
    Column {
        x: parent.width * 0.58
        y: root.headerHeight + Metrics.pad(6)
        width: parent.width * 0.42 - root.horizontalPadding
        spacing: Metrics.px(3)

        Repeater {
            model: {
                const item = root.selected();
                if (item === null)
                    return [["", "nothing selected"]];

                if (root.view === "profiles") {
                    const active = root.profileCard && item.name === root.profileCard.active;
                    const rows = [
                        ["profile", item.name],
                        ["state", active ? "active" : "available"],
                        ["outputs", String(item.sinks)],
                        ["inputs", String(item.sources)],
                    ];
                    if (item.note !== "")
                        rows.push(["trade-off", item.note]);
                    if (root.profileCard)
                        rows.push(["card", root.profileCard.desc]);
                    return rows;
                }
                if (root.view === "cards") {
                    return [
                        ["card", item.name],
                        ["profile", item.activeDesc],
                        ["trade-off", item.note || "—"],
                        ["choices", item.profiles.length + " selectable"],
                        ["", "Enter opens this card's profiles"],
                    ];
                }
                if (root.view === "ports") {
                    return [
                        ["port", item.name],
                        ["type", item.type || "—"],
                        ["state", root.portDevice && item.name === root.portDevice.port
                            ? "active" : "available"],
                        ["jack", item.availability || "unknown"],
                        ["device", root.portDevice ? root.portDevice.desc : "—"],
                    ];
                }
                if (root.view === "targets") {
                    return [
                        ["moving", root.targetStream ? root.targetStream.app : "—"],
                        ["state", root.targetStream && item.index === root.targetStream.target
                            ? "already here" : "Enter to move"],
                        ["volume", item.vol + "%"],
                        ["driver", item.driver || "—"],
                        ["format", item.spec || "—"],
                    ];
                }
                if (root.isStreamView) {
                    return [
                        [root.view === "playback" ? "playing" : "capturing", item.media || "—"],
                        ["app", item.app],
                        ["state", item.corked ? "paused"
                            : (root.view === "playback" ? "playing" : "recording")],
                        ["volume", item.mute ? "muted" : item.vol + "%"],
                        ["gain", item.db || "—"],
                        [root.view === "playback" ? "output" : "input",
                         item.targetName || "—"],
                    ];
                }

                // A device. Balance is shown only on a stereo device —
                // "0.00" against a mono microphone is noise — and the port
                // line carries the count of the others, which is the hint
                // that Shift+P has somewhere to go.
                const rows = [
                    ["volume", item.mute ? "muted" : item.vol + "%"],
                    ["gain", item.db || "—"],
                    ["state", item.name === (root.view === "inputs" ? root.defaultSource : root.defaultSink)
                        ? "default" : (item.state || "—").toLowerCase()],
                ];
                if (item.nchannels >= 2) {
                    rows.push(["balance", root.balanceLabel(Number(item.balance) || 0)]);
                }
                rows.push(["format", item.spec || "—"]);
                if (item.ports && item.ports.length > 0) {
                    let active = item.port;
                    for (let i = 0; i < item.ports.length; i++) {
                        if (item.ports[i].name === item.port)
                            active = item.ports[i].desc;
                    }
                    rows.push(["port", active + (item.ports.length > 1
                        ? "  (+" + (item.ports.length - 1) + ")" : "")]);
                }
                if (item.card !== "")
                    rows.push(["profile", item.profileDesc
                        + (item.profileNote !== "" ? "  · " + item.profileNote : "")]);
                return rows;
            }

            delegate: Row {
                required property var modelData
                spacing: Metrics.pad(8)
                Text {
                    text: modelData[0]
                    color: "#6a6a6a"
                    font.pixelSize: Metrics.font(11)
                    font.family: root.textFontFamily
                    width: Metrics.px(72)
                }
                Text {
                    text: String(modelData[1] || "—")
                    color: "#d0d0d0"
                    font.pixelSize: Metrics.font(11)
                    font.family: root.textFontFamily
                    elide: Text.ElideRight
                    width: Metrics.px(200)
                }
            }
        }
    }

    Text {
        anchors.left: parent.left
        anchors.leftMargin: root.horizontalPadding
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Metrics.pad(8)
        width: parent.width - root.horizontalPadding * 2
        elide: Text.ElideRight
        color: "#6a6a6a"
        font.pixelSize: Metrics.font(10)
        font.family: root.textFontFamily
        text: root.isStreamView
            ? "j/k move · Enter move to… · d to default · h/l vol · m mute · Tab view · q close"
            : "j/k move · Enter use · h/l vol · m mute · p profile · P port · C cards · b balance · Tab view · q close"
    }
}
