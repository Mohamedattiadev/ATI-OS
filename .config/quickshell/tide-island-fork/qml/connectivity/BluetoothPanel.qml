pragma ComponentBehavior: Bound

import QtQuick

// FORK: the shared scale factor — see qml/common/Metrics.js.
import "../common/Metrics.js" as Metrics
// FORK: the shared motion system — one spring for geometry, one critically
// damped curve for opacity. See qml/common/Motion.js.
import "../common/Motion.js" as Motion
import "../common"

//
// FORK — new file. The Bluetooth panel, rebuilt from scratch in the idiom of
// qml/audio/AudioPanel.qml and qml/display/DisplayPanel.qml.
//
// WHAT IT REPLACES, AND WHAT IT KEEPS
// -----------------------------------
// ConnectivityDetailPanel.qml served this and the Wi-Fi list from one file
// through a `panelKind` string. Every visible element carried an `isWifi` /
// `isBluetooth` gate, and the panel that came out did not read like the audio
// and display panels for exactly that reason: those are each one panel about
// one thing. This is the Bluetooth half, on its own, with the Wi-Fi half in
// WifiPanel.qml.
//
// ONE RANK-SORTED LIST, and that part is carried across deliberately
// unchanged, because it was a real fix rather than a preference. There are no
// group headers and no hairlines between rows: the grouping is expressed
// purely by SORT ORDER, so a connected device is at the top because it sorts
// there, not because it lives in a box with a heading over it.
//
// Rank is 0/1/2/3 — connected, paired, named, unnamed — with ties broken by
// localeCompare on the display name. The named/unnamed split earns its place:
// a scan fills up with address-only rows from passing phones and earbuds, and
// without that rank they interleave alphabetically with the devices you might
// actually want, since an address sorts as a string like anything else.
//
// THE BUG THAT REMOVED THE SECTIONS. The old section predicates overlapped:
// "connected" was `device.connected` but "available" was `!paired`, so a
// device connected WITHOUT being paired satisfied both and rendered TWICE,
// once in each Repeater. Rank is a single exclusive assignment per device, so
// a device can occupy exactly one position by construction. Do not put the
// sections back.
//
// WHY THE ROWS NO LONGER REGISTER THEMSELVES
// ------------------------------------------
// The old navigation was a registry — every row enrolled itself with a
// (rank, index) pair and the panel sorted the enrolments to recover the
// on-screen order — because one file had to navigate a C++ QAbstractListModel
// (Wi-Fi) and a JS array (Bluetooth) at once. Split in two, the question
// disappears: this list IS an array, so it is navigated the way AudioPanel
// navigates its arrays — one `selectedIndex` on the PANEL, a ListView whose
// currentIndex follows it, and delegates that only draw. Per-row state on the
// delegate would not survive anyway; this array is rebuilt whenever bluez
// reports a device connecting, and a rebuild destroys every delegate.
//
// KEYMAP
// ------
//   j / k · ↓ / ↑   move the cursor          g / G   top / bottom
//   Return          connect · disconnect if already connected · pair if new
//   d               disconnect          x   forget this device
//   s               start / stop scanning    t   adapter on / off
//   Escape / q      close               (Escape cancels a pairing prompt first)
//
FocusScope {
    id: root

    signal closeRequested

    // The control centre as data provider — bluez lives behind it, in
    // Quickshell.Bluetooth. This file is the keyboard and the pixels.
    property var provider: null

    property bool showCondition: false
    property string textFontFamily: ""
    property string heroFontFamily: ""
    property string iconFontFamily: ""

    // ---- COLOUR FOLLOWS THE THEME ----
    //
    // panelFill is IslandTheme.shellFill, passed down from
    // DynamicIslandWindow — the capsule's own material, which re-tints on
    // every theme-apply. The complaint it answers is a panel painted a FIXED
    // near-black that ignores theme_mode. drawBackground is false in the
    // island because the capsule the panel fills is already painted in this
    // exact colour, and a second rounded fill inside it at a smaller radius
    // shows as four pale corner wedges. See WifiPanel.qml for the long form.
    property color panelFill: IslandTheme.surface
    property color accentColor: IslandTheme.accent
    property bool drawBackground: false

    property string statusText: "Ready"
    property string statusLevel: "idle"          // idle | busy | ok | error
    // True only while a connect, disconnect or pair this panel started is in
    // flight, so the settle timer and the device list cannot overwrite the
    // message for the one thing you actually asked for.
    property bool busy: false
    // True while statusText is the panel's own summary rather than a message
    // about something that happened. Only a summary may be rewritten by the
    // list changing underneath it.
    property bool showingSummary: false

    // --- selection ---------------------------------------------------------
    property int selectedIndex: 0
    // What the cursor MEANS, as opposed to where it is. The device array is
    // re-sorted whenever anything about any device changes — a connect moves
    // a row from rank 1 to rank 0, i.e. to the top — and an index alone would
    // leave the cursor pointing at whatever slid into that slot. On a panel
    // whose Enter can disconnect a headset, that is not cosmetic.
    property string selectedAddress: ""

    readonly property real horizontalPadding: Metrics.pad(18)
    readonly property real headerHeight: Metrics.pad(34)
    // 30 rather than the Wi-Fi panel's 26. A device carries state a network
    // does not — paired vs connected vs connecting, plus a battery level —
    // and the extra four pixels are what let the meta caption sit under the
    // name instead of being elided into it.
    readonly property real rowHeight: Metrics.px(30)
    readonly property real rowSpacing: 2
    readonly property int rowsVisible: 6
    readonly property real hintHeight: Metrics.pad(26)

    readonly property bool promptVisible:
        provider !== null && !!provider.bluetoothPairingActive
    readonly property real promptHeight:
        provider && provider.bluetoothPairingRequiresInput ? Metrics.px(72) : Metrics.px(48)

    // --- model -------------------------------------------------------------
    readonly property var devices: provider ? (provider.bluetoothDeviceValues || []) : []
    readonly property bool scanning: provider && provider.bluetoothAdapter
        ? provider.bluetoothAdapter.discovering
        : false

    function safeString(value) {
        return value === undefined || value === null ? "" : String(value);
    }

    // Name for SORTING only, so it must be empty when the device has no real
    // name. provider.bluetoothDeviceName() falls back to the address and then
    // to "Unknown device", which would make every anonymous device look named
    // and collapse rank 3 into rank 2.
    function displayNameOf(device) {
        if (!device)
            return "";
        const preferred = root.safeString(device.deviceName).trim();
        if (preferred.length > 0)
            return preferred;
        return root.safeString(device.name).trim();
    }

    function rankOf(device) {
        if (!device)
            return 3;
        if (device.connected)
            return 0;
        if (device.paired || device.bonded)
            return 1;
        return root.displayNameOf(device).length > 0 ? 2 : 3;
    }

    function sectionOf(rank) {
        if (rank === 0)
            return "connected";
        if (rank === 1)
            return "paired";
        return "available";
    }

    readonly property var currentItems: {
        const pool = root.devices;
        const ranked = [];
        for (let index = 0; index < pool.length; index++) {
            const device = pool[index];
            if (!device)
                continue;
            ranked.push({
                device: device,
                rank: root.rankOf(device),
                name: root.displayNameOf(device),
                address: root.safeString(device.address)
            });
        }
        ranked.sort(function (left, right) {
            if (left.rank !== right.rank)
                return left.rank - right.rank;
            return left.name.localeCompare(right.name);
        });
        return ranked;
    }

    // Re-anchor after every rebuild. Held here rather than in the delegate,
    // because the rebuild is exactly the event that destroys delegates.
    onCurrentItemsChanged: {
        if (root.showingSummary)
            root.setSummary();
        if (root.selectedAddress.length === 0)
            return;
        for (let index = 0; index < root.currentItems.length; index++) {
            if (root.currentItems[index].address === root.selectedAddress) {
                root.selectedIndex = index;
                return;
            }
        }
        // The device went away — out of range, or forgotten. Clamp rather
        // than pointing past the end.
        root.selectedIndex = Math.max(0, Math.min(root.selectedIndex,
                                                  root.currentItems.length - 1));
    }

    function selected() {
        if (root.selectedIndex >= 0 && root.selectedIndex < root.currentItems.length)
            return root.currentItems[root.selectedIndex];
        return null;
    }

    function selectedDevice() {
        const entry = root.selected();
        return entry ? entry.device : null;
    }

    // ---- THE PANEL SIZES ITSELF ----
    //
    // Same arithmetic as the audio and display panels. The old connectivity
    // layer was a flat Metrics.px(404) either way, and this machine has no
    // paired devices and none in range — measured, `bluetoothctl devices` is
    // empty — so that height was 404 px of nothing perhaps most of the time
    // it was opened. It can still reach it; it has to earn it a row at a time.
    readonly property real listBodyHeight:
        Math.max(0, root.currentItems.length) * (root.rowHeight + root.rowSpacing) - root.rowSpacing
    readonly property real detailsBodyHeight: detailsColumn.height
    readonly property real bodyHeight: Math.max(
        4 * (root.rowHeight + root.rowSpacing),
        Math.min(root.rowsVisible * (root.rowHeight + root.rowSpacing), root.listBodyHeight),
        root.detailsBodyHeight)
    readonly property real preferredHeight:
        root.headerHeight + Metrics.pad(4) + root.bodyHeight
            + (root.promptVisible ? root.promptHeight + Metrics.pad(6) : 0)
            + Metrics.pad(8) + root.hintHeight

    focus: showCondition
    activeFocusOnTab: true
    anchors.fill: parent
    opacity: showCondition ? 1 : 0

    // FORK: one choreography for every layer in the shell. Motion.fade() and
    // not Motion.spring(): opacity is clamped 0..1 and an overshooting fade
    // reads as a cut.
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
            root.selectedIndex = 0;
            root.selectedAddress = "";
            // Same reason as WifiPanel: bluetoothError is written once and
            // lives forever, so a panel opened an hour later still shows the
            // failure of an attempt you have forgotten making.
            if (root.provider && root.provider.clearBluetoothMessages)
                root.provider.clearBluetoothMessages();
            root.busy = false;
            // ---- WHY THE SUMMARY IS NOT WRITTEN HERE ----
            //
            // It was, as a ladder of provider checks, and the first live open
            // showed "no Bluetooth backend" in red across the top of a panel
            // whose header said "· On" two inches to the left. Nothing was
            // wrong with the backend: this handler runs during the Loader's
            // build, before controlCenterLoader.item has been assigned to
            // `provider`, so the ladder answered a question about an object
            // that did not exist yet and then LATCHED the answer. The header
            // beside it was right because it is a binding and re-evaluated.
            //
            // The same mistake in WifiPanel produced "Wi-Fi is off" over a
            // list of five networks. Both are one lesson: this panel may not
            // latch a fact it can bind, and where it must latch one — a
            // status line is a latch by definition — it has to wait for the
            // fact to exist.
            root.setStatus("reading devices…", "busy");
            settleTimer.restart();
            forceActiveFocus();
        } else if (root.provider && root.provider.cancelBluetoothPairing
                   && root.provider.bluetoothPairingActive) {
            // A pairing request left standing when the panel closes is an
            // agent still holding the bus. Cancel on the way out, the same
            // way DisplayPanel reverts a provisional mode on close.
            root.provider.cancelBluetoothPairing();
        }
    }

    // Called by the host from the Loader's onLoaded: PanelLoader builds the
    // item with showCondition ALREADY true, so onShowConditionChanged never
    // fires on the open that matters. Both paths are kept, because the host
    // also toggles the flag on a live item.
    function grabKeyboardFocus() {
        root.forceActiveFocus();
    }


    function setStatus(text, level) {
        root.statusText = text;
        root.statusLevel = level || "idle";
        root.showingSummary = false;
    }

    // The idle line: what the adapter is and how many devices it can see.
    // Marked as a SUMMARY so the list can keep it honest as devices appear
    // and vanish. WifiPanel learned this the hard way — its first version
    // latched "0 networks" from the empty first frame and never revised it,
    // leaving a full list under a line saying there were none.
    function setSummary() {
        root.showingSummary = true;
        root.statusLevel = "idle";
        if (!root.provider || !root.provider.bluetoothAvailable) {
            root.statusText = "no adapter";
            root.statusLevel = "error";
            return;
        }
        if (!root.provider.bluetoothEnabled) {
            root.statusText = "Bluetooth is off";
            return;
        }
        const count = root.currentItems.length;
        root.statusText = count + (count === 1 ? " device" : " devices");
    }

    // Everything this panel starts goes through here, so there is exactly one
    // place that can leave `busy` stuck on. bluez publishes no single "the
    // request finished" fact — a pair can end in paired, in a prompt, or in
    // silence — so the flag ends on whichever comes first: the adapter's own
    // status line changing, or a deadline. Twelve seconds is bluez's own
    // pairing timeout rounded down.
    function beginBusy(message) {
        root.busy = true;
        root.setStatus(message, "busy");
        busyTimeout.restart();
    }

    function endBusy(message, level) {
        root.busy = false;
        busyTimeout.stop();
        if (message !== undefined)
            root.setStatus(message, level || "ok");
    }

    Timer {
        id: busyTimeout
        interval: 12000
        repeat: false
        onTriggered: root.endBusy("no answer from bluez", "error")
    }

    Connections {
        target: root.provider
        ignoreUnknownSignals: true

        // buildBluetoothStatusText names the connected device, or says
        // Scanning, or On — so it changes exactly when something this panel
        // could have asked for has happened.
        function onBluetoothStatusTextChanged() {
            if (root.busy)
                root.endBusy(String(root.provider.bluetoothStatusText || ""), "ok");
        }

        function onBluetoothErrorChanged() {
            if (root.busy && String(root.provider.bluetoothError || "").length > 0)
                root.endBusy(undefined);
        }
    }

    // The summary the open used to write inline, delayed until the provider
    // and the bluez singleton behind it are actually there. 400 ms because
    // the panel's own fade-in takes about that long, so the line is written
    // before it is legible rather than visibly rewriting itself in front of
    // you. Guarded on the status still being the open's own, so an action
    // taken inside that window keeps its message.
    Timer {
        id: settleTimer
        interval: 400
        repeat: false
        onTriggered: {
            if (root.statusLevel !== "busy" || root.busy)
                return;
            root.setSummary();
        }
    }

    // --- navigation --------------------------------------------------------
    // Wraps, for the reason DisplayPanel spells out: this list is short, and
    // a cursor that stops dead at the last row reads as a dead key. g / G
    // still go to the ends.
    function move(step) {
        const count = root.currentItems.length;
        if (count === 0)
            return;
        root.setCursor(((root.selectedIndex + step) % count + count) % count);
    }

    function jump(where) {
        const count = root.currentItems.length;
        if (count === 0)
            return;
        root.setCursor(where === "top" ? 0 : count - 1);
    }

    function setCursor(index) {
        root.selectedIndex = Math.max(0, index);
        const entry = root.selected();
        root.selectedAddress = entry ? entry.address : "";
        listView.positionViewAtIndex(root.selectedIndex, ListView.Contain);
    }

    // --- actions -----------------------------------------------------------
    //
    // One activation path for the pointer and the keyboard. When those are
    // two copies, the keyboard one is the copy that quietly stops matching.
    function activateAt(index) {
        if (index !== root.selectedIndex)
            root.setCursor(index);
        root.activate();
    }

    function activate() {
        const device = root.selectedDevice();
        if (!device || !root.provider)
            return;
        if (!root.provider.bluetoothEnabled) {
            root.setStatus("turn Bluetooth on first — t", "idle");
            return;
        }
        const name = root.provider.bluetoothDeviceName(device);
        // The verb depends on the state, and the provider already owns that
        // decision — handleBluetoothDevicePressed disconnects a connected
        // device, connects a paired one, and pairs a new one. Duplicating the
        // ladder here would be a second copy to drift.
        root.beginBusy((device.connected ? "disconnecting " : (device.paired || device.bonded
                        ? "connecting " : "pairing ")) + name + "…");
        root.provider.handleBluetoothDevicePressed(device);
    }

    function disconnectSelected() {
        const device = root.selectedDevice();
        if (!device)
            return;
        if (!device.connected) {
            root.setStatus("not connected", "idle");
            return;
        }
        root.beginBusy("disconnecting " + root.provider.bluetoothDeviceName(device) + "…");
        device.disconnect();
    }

    function forgetSelected() {
        const device = root.selectedDevice();
        if (!device || !root.provider)
            return;
        if (!(device.paired || device.bonded)) {
            // forget() on an unpaired device is a no-op that looks like a
            // dead key. Say which it was.
            root.setStatus("nothing to forget — not paired", "idle");
            return;
        }
        root.setStatus("forgetting " + root.provider.bluetoothDeviceName(device), "ok");
        root.provider.forgetBluetoothDevice(device);
    }

    function toggleScan() {
        if (!root.provider)
            return;
        const starting = !root.scanning;
        root.provider.toggleBluetoothScan();
        root.setStatus(starting ? "scanning…" : "scan stopped", starting ? "busy" : "idle");
    }

    function toggleAdapter() {
        if (!root.provider)
            return;
        const turningOn = !root.provider.bluetoothEnabled;
        root.provider.toggleBluetoothEnabled();
        root.setStatus(turningOn ? "turning Bluetooth on…" : "turning Bluetooth off…", "busy");
    }

    // --- keys --------------------------------------------------------------
    //
    // While a pairing prompt with a field is up, the field holds the focus
    // and this handler never runs — a PIN containing a d or an x must not
    // forget a device. That is enforced by the focus itself rather than by a
    // flag, because a FocusScope's Keys handler only sees what its focused
    // child did not take.
    Keys.onPressed: function (event) {
        const shift = (event.modifiers & Qt.ShiftModifier) !== 0;

        // A confirm-only pairing request has no field to focus, so this
        // handler IS the prompt's keyboard. Enter confirms, Escape rejects,
        // and nothing else may fall through to the list underneath.
        if (root.promptVisible && root.provider
                && !root.provider.bluetoothPairingRequiresInput) {
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                if (root.provider.bluetoothPairingRequiresConfirmation)
                    root.provider.confirmBluetoothPairing();
                event.accepted = true;
                return;
            }
            if (event.key === Qt.Key_Escape) {
                root.provider.cancelBluetoothPairing();
                root.setStatus("pairing cancelled", "idle");
                event.accepted = true;
                return;
            }
        }

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
        case Qt.Key_Return:
        case Qt.Key_Enter:
            root.activate();
            break;
        case Qt.Key_D:
            root.disconnectSelected();
            break;
        case Qt.Key_X:
            root.forgetSelected();
            break;
        case Qt.Key_S:
            root.toggleScan();
            break;
        case Qt.Key_T:
            root.toggleAdapter();
            break;
        default:
            return;
        }
        event.accepted = true;
    }

    onPromptVisibleChanged: {
        if (promptVisible && provider && provider.bluetoothPairingRequiresInput)
            promptFocusTimer.restart();
        else if (showCondition)
            root.forceActiveFocus();
    }

    Timer {
        id: promptFocusTimer
        interval: 0
        repeat: false
        onTriggered: secretField.forceActiveFocus()
    }

    // See panelFill. Off in the island, kept so the panel renders standalone.
    Rectangle {
        anchors.fill: parent
        radius: Metrics.px(28)
        color: root.panelFill
        opacity: 0.97
        visible: root.drawBackground
    }

    // --- chrome ------------------------------------------------------------
    //
    // Letterspaced uppercase at a much smaller size than a title would be,
    // then a "· status" clause carrying the accent only when something is
    // live. No kanji: there was a 藍 here and it was removed on request.
    Text {
        id: header
        x: root.horizontalPadding
        y: Metrics.pad(12)
        text: "BLUETOOTH"
        color: IslandTheme.textMuted
        font.family: root.textFontFamily
        font.pixelSize: Metrics.font(10)
        font.weight: Font.DemiBold
        font.capitalization: Font.AllUppercase
        font.letterSpacing: 1.6
    }

    Text {
        anchors.left: header.right
        anchors.leftMargin: Metrics.pad(8)
        y: Metrics.pad(12)
        text: {
            if (!root.provider)
                return "";
            if (!root.provider.bluetoothAvailable)
                return "· unavailable";
            if (!root.provider.bluetoothEnabled)
                return "· off";
            // buildBluetoothStatusText already names the connected device, or
            // says Scanning, or On. It is what the control centre's own row
            // shows, so the two cannot disagree.
            return "· " + root.provider.bluetoothStatusText;
        }
        // Accent only when a device is actually connected — not merely when
        // the radio is on. "On" is not a thing to point at.
        color: {
            if (!root.provider || !root.provider.bluetoothEnabled)
                return IslandTheme.textMuted;
            const pool = root.currentItems;
            for (let index = 0; index < pool.length; index++) {
                if (pool[index].device && pool[index].device.connected)
                    return root.accentColor;
            }
            return IslandTheme.textMuted;
        }
        font.family: root.textFontFamily
        font.pixelSize: Metrics.font(10)
        font.weight: Font.Medium
        elide: Text.ElideRight
        width: Math.min(implicitWidth, root.width * 0.35)
    }

    Text {
        anchors.right: parent.right
        anchors.rightMargin: root.horizontalPadding
        y: Metrics.pad(12)
        width: Math.min(implicitWidth, root.width * 0.45)
        horizontalAlignment: Text.AlignRight
        elide: Text.ElideRight
        font.pixelSize: Metrics.font(11)
        font.family: root.textFontFamily
        color: root.statusLevel === "error" ? IslandTheme.danger
             : (root.statusLevel === "ok" ? IslandTheme.success
             : (root.statusLevel === "busy" ? IslandTheme.warning : IslandTheme.textMuted))
        text: {
            if (root.provider && String(root.provider.bluetoothError || "").length > 0)
                return String(root.provider.bluetoothError);
            if (root.scanning)
                return "scanning…";
            return root.statusText;
        }
    }

    ListView {
        id: listView
        x: root.horizontalPadding
        y: root.headerHeight + Metrics.pad(4)
        width: parent.width * 0.56 - root.horizontalPadding
        height: root.bodyHeight
        clip: true
        model: root.currentItems
        currentIndex: root.selectedIndex
        boundsBehavior: Flickable.StopAtBounds
        spacing: root.rowSpacing

        // Two different sentences for two different facts. Collapsing
        // "scanning" and "found nothing" into one string is how a scan that
        // has silently died still looks like it is working.
        Text {
            anchors.centerIn: parent
            visible: listView.count === 0
            width: listView.width - Metrics.pad(16)
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            color: IslandTheme.textDisabled
            font.pixelSize: Metrics.font(11)
            font.family: root.textFontFamily
            text: {
                if (!root.provider)
                    return "no Bluetooth backend";
                if (!root.provider.bluetoothAvailable)
                    return "no Bluetooth adapter is available";
                if (!root.provider.bluetoothEnabled)
                    return "Bluetooth is off — t to turn it on";
                return root.scanning ? "scanning…" : "no devices — s to scan";
            }
        }

        // ONE Repeater's worth of rows over the rank-sorted list, with no
        // headers and no hairlines. The row spacing IS the separation; a rule
        // between rows would reintroduce exactly the boxed-group reading the
        // sections were removed for.
        delegate: Rectangle {
            id: deviceRow

            required property int index
            required property var modelData

            readonly property var device: deviceRow.modelData.device
            readonly property string section: root.sectionOf(deviceRow.modelData.rank)
            readonly property bool connected: !!(deviceRow.device && deviceRow.device.connected)
            readonly property bool paired: !!(deviceRow.device
                && (deviceRow.device.paired || deviceRow.device.bonded))

            width: listView.width
            height: root.rowHeight
            radius: Metrics.px(7)
            // NO accent tint for a connected device, and that asymmetry with
            // the Wi-Fi row is deliberate. Exactly one network can be
            // connected, so tinting it marks the singular one; several
            // Bluetooth devices can be connected at once, and a list with
            // four tinted rows has stopped pointing at anything. Connection
            // is carried by the name's weight and colour instead, and the
            // only fill on this list is the keyboard cursor.
            color: deviceRow.index === root.selectedIndex ? IslandTheme.selectionFill : "transparent"

            Text {
                id: rowName
                anchors.left: parent.left
                anchors.leftMargin: Metrics.pad(10)
                anchors.right: rowAction.left
                anchors.rightMargin: Metrics.pad(8)
                anchors.top: parent.top
                anchors.topMargin: Metrics.px(3)
                elide: Text.ElideRight
                color: deviceRow.connected ? root.accentColor : "white"
                font.pixelSize: Metrics.font(12)
                font.family: root.textFontFamily
                font.weight: deviceRow.connected ? Font.DemiBold : Font.Normal
                text: (deviceRow.connected ? "● " : "")
                    + (root.provider ? root.provider.bluetoothDeviceName(deviceRow.device) : "")
            }

            // The caption is what a one-line row had no room for, and it is
            // the answer to "which of these two identical headsets is the one
            // actually connected".
            Text {
                anchors.left: rowName.left
                anchors.right: rowAction.left
                anchors.rightMargin: Metrics.pad(8)
                anchors.top: rowName.bottom
                elide: Text.ElideRight
                color: IslandTheme.textDisabled
                font.pixelSize: Metrics.font(9.5)
                font.family: root.textFontFamily
                text: root.provider ? root.provider.bluetoothDeviceSubtitle(deviceRow.device) : ""
            }

            // What Enter would do to THIS row, as a word rather than a
            // button. The old panel drew a "Pair" chip with a border on
            // unpaired rows; a chip on a keyboard-driven list is a target for
            // a pointer that is not the point here, and it made the one row
            // you can act on look different from the four you can also act on.
            Text {
                id: rowAction
                anchors.right: parent.right
                anchors.rightMargin: Metrics.pad(10)
                anchors.verticalCenter: parent.verticalCenter
                text: {
                    if (deviceRow.device && deviceRow.device.pairing)
                        return "pairing";
                    if (deviceRow.connected)
                        return "connected";
                    return deviceRow.paired ? "connect" : "pair";
                }
                color: deviceRow.connected ? root.accentColor
                     : (deviceRow.index === root.selectedIndex ? IslandTheme.textPrimary : IslandTheme.textDisabled)
                font.pixelSize: Metrics.font(9.5)
                font.family: root.textFontFamily
                font.weight: Font.DemiBold
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 1.0
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                onEntered: root.setCursor(deviceRow.index)
                onClicked: root.activateAt(deviceRow.index)
            }
        }
    }

    // Details for whatever the cursor is on. The list alone cannot say what a
    // row IS — its address, whether it is trusted, what its battery is at —
    // and those are the fields with no cue anywhere else on the system.
    Column {
        id: detailsColumn
        x: parent.width * 0.58
        y: root.headerHeight + Metrics.pad(6)
        width: parent.width * 0.42 - root.horizontalPadding
        spacing: Metrics.px(3)

        Repeater {
            model: {
                const device = root.selectedDevice();
                if (!device)
                    return [["", "nothing selected"]];
                const rows = [
                    ["device", root.provider ? root.provider.bluetoothDeviceName(device) : ""],
                    ["address", root.safeString(device.address) || "—"],
                    ["state", root.provider ? root.provider.bluetoothDeviceStateText(device) : ""],
                    ["paired", (device.paired || device.bonded) ? "yes" : "no"],
                    ["trusted", device.trusted ? "yes" : "no"],
                ];
                if (device.batteryAvailable)
                    rows.push(["battery", root.provider.bluetoothBatteryPercent(device) + "%"]);
                rows.push(["Enter", device.connected ? "disconnect"
                    : ((device.paired || device.bonded) ? "connect" : "pair and connect")]);
                return rows;
            }

            delegate: Row {
                required property var modelData
                spacing: Metrics.pad(8)
                Text {
                    text: modelData[0]
                    color: IslandTheme.textDisabled
                    font.pixelSize: Metrics.font(11)
                    font.family: root.textFontFamily
                    width: Metrics.px(66)
                }
                Text {
                    text: String(modelData[1] || "—")
                    color: IslandTheme.textPrimary
                    font.pixelSize: Metrics.font(11)
                    font.family: root.textFontFamily
                    elide: Text.ElideRight
                    width: Metrics.px(200)
                }
            }
        }
    }

    // ---- THE PAIRING PROMPT ----
    //
    // Below the body and counted in preferredHeight, so raising it GROWS the
    // capsule rather than covering the row that says which device is asking.
    // bluez asks in three shapes — a passkey to type, a code to confirm, or
    // nothing at all — and the height follows, because a field-sized box with
    // no field in it reads as a field that failed to draw.
    Rectangle {
        id: pairingPrompt
        visible: root.promptVisible
        x: root.horizontalPadding
        y: root.headerHeight + Metrics.pad(4) + root.bodyHeight + Metrics.pad(6)
        width: parent.width - root.horizontalPadding * 2
        height: root.promptHeight
        radius: Metrics.px(12)
        color: Qt.rgba(1, 1, 1, 0.05)

        Text {
            id: promptTitle
            anchors.left: parent.left
            anchors.leftMargin: Metrics.pad(12)
            anchors.right: parent.right
            anchors.rightMargin: Metrics.pad(12)
            anchors.top: parent.top
            anchors.topMargin: Metrics.pad(7)
            text: {
                if (!root.provider)
                    return "";
                const title = String(root.provider.bluetoothPairingTitle || "pairing");
                const message = String(root.provider.bluetoothPairingMessage || "");
                return message.length > 0 ? title + " — " + message : title;
            }
            color: IslandTheme.textPrimary
            font.pixelSize: Metrics.font(11)
            font.family: root.textFontFamily
            elide: Text.ElideRight
        }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: Metrics.pad(12)
            anchors.top: promptTitle.bottom
            anchors.topMargin: Metrics.pad(4)
            visible: root.provider && !root.provider.bluetoothPairingRequiresInput
            text: root.provider && root.provider.bluetoothPairingRequiresConfirmation
                ? "Enter to confirm · Escape to reject"
                : "Escape to cancel"
            color: IslandTheme.textDisabled
            font.pixelSize: Metrics.font(10)
            font.family: root.textFontFamily
        }

        Rectangle {
            visible: root.provider && root.provider.bluetoothPairingRequiresInput
            anchors.left: parent.left
            anchors.leftMargin: Metrics.pad(12)
            anchors.right: parent.right
            anchors.rightMargin: Metrics.pad(12)
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Metrics.pad(8)
            height: Metrics.px(26)
            radius: Metrics.px(8)
            color: Qt.rgba(0, 0, 0, 0.35)
            border.width: 1
            border.color: secretField.activeFocus ? root.accentColor : Qt.rgba(1, 1, 1, 0.12)

            TextInput {
                id: secretField
                anchors.fill: parent
                anchors.leftMargin: Metrics.pad(10)
                anchors.rightMargin: Metrics.pad(10)
                verticalAlignment: TextInput.AlignVCenter
                color: "white"
                font.pixelSize: Metrics.font(11)
                font.family: root.textFontFamily
                clip: true
                selectByMouse: true
                cursorVisible: activeFocus
                inputMethodHints: root.provider && root.provider.bluetoothPairingNumericInput
                    ? Qt.ImhDigitsOnly : Qt.ImhNoPredictiveText
                maximumLength: root.provider && root.provider.bluetoothPairingNumericInput ? 6 : 16
                text: root.provider ? root.provider.bluetoothPendingSecretValue : ""
                onTextChanged: {
                    if (root.provider)
                        root.provider.bluetoothPendingSecretValue = text;
                }
                Keys.onReturnPressed: {
                    if (root.provider)
                        root.provider.submitBluetoothPairingSecret();
                }
                Keys.onEnterPressed: {
                    if (root.provider)
                        root.provider.submitBluetoothPairingSecret();
                }
                // Escape backs out of the PROMPT, not out of the panel.
                Keys.onEscapePressed: function (event) {
                    if (root.provider)
                        root.provider.cancelBluetoothPairing();
                    root.setStatus("pairing cancelled", "idle");
                    root.forceActiveFocus();
                    event.accepted = true;
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: secretField.text.length === 0
                    text: root.provider && root.provider.bluetoothPairingNumericInput
                        ? "passkey · Enter to send" : "PIN · Enter to send"
                    color: IslandTheme.textDisabled
                    font.pixelSize: Metrics.font(10)
                    font.family: root.textFontFamily
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
        color: IslandTheme.textDisabled
        font.pixelSize: Metrics.font(10)
        font.family: root.textFontFamily
        text: root.promptVisible
            ? "answer the pairing request · Escape cancels"
            : "j/k move · Enter connect · d disconnect · x forget · s scan · t adapter · q close"
    }
}
