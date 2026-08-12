import QtQuick
import IslandBackend

// FORK: one shared scale factor for every island surface.
import "../common/Metrics.js" as Metrics

Rectangle {
    id: root

    property var provider: null
    property var device: null
    property string section: "available"
    property string iconFontFamily: ""
    property string textFontFamily: ""

    readonly property bool hasProvider: provider !== null && provider !== undefined
    readonly property bool hasDevice: device !== null && device !== undefined
    readonly property bool canInteract: hasProvider && hasDevice && provider.bluetoothEnabled
    readonly property bool paired: hasDevice && (device.paired || device.bonded)
    readonly property bool connected: hasDevice && device.connected
    readonly property bool pairing: hasDevice && device.pairing
    readonly property string actionText: {
        if (section === "connected") return "✓";
        if (section === "paired") return "Connect";
        return pairing ? "Pairing" : "Pair";
    }
    readonly property string subtitleText: section === "connected"
        ? "Connected"
        : (hasProvider && provider.bluetoothDeviceSubtitle
            ? provider.bluetoothDeviceSubtitle(device)
            : "")
    readonly property color iconColor: section === "available" ? StyleTokens.textTertiary : StyleTokens.accent

    // FORK: keyboard navigation, driven from ConnectivityDetailPanel. The
    // row does not decide whether it is selected — it is told, so that one
    // place owns the selection across all three Bluetooth sections plus the
    // Wi-Fi list. See the registry note in ConnectivityDetailPanel.qml.
    property bool navCurrent: false

    // Only the "Pair" affordance is drawn as a chip. Connect/✓ stay as bare
    // labels, so the one row you can act on to ADD a device is the one with
    // a hit-looking target on it.
    readonly property bool isChip: section === "available" && !pairing

    width: parent ? parent.width : 0
    // 38 and two lines, NOT the Wi-Fi row's 30. Matching them was the
    // instinct and it is wrong: ukishima's Bluetooth row is deliberately
    // taller than its Wi-Fi row because a device carries state a network
    // does not — paired vs connected vs connecting, plus an address, plus a
    // battery level. A network is an SSID and a signal, which fits on one
    // line; a device does not.
    height: Metrics.px(38)
    radius: Metrics.px(9)
    // NO accent tint for the connected device, and that asymmetry with the
    // Wi-Fi row is theirs and deliberate. Exactly one Wi-Fi network can be
    // connected, so tinting it marks the singular one; several Bluetooth
    // devices can be connected at once, and a list with four tinted rows has
    // stopped pointing at anything. Connection is carried by the tile glyph
    // and the name's weight instead. The keyboard cursor is the only fill.
    color: navCurrent ? Qt.rgba(1, 1, 1, 0.10) : StyleTokens.transparent
    clip: true

    // One activation path for pointer and keyboard.
    function navActivate() {
        if (!root.canInteract)
            return;
        if (root.provider && root.provider.handleBluetoothDevicePressed)
            root.provider.handleBluetoothDevicePressed(root.device);
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.canInteract

        onClicked: root.navActivate()
    }

    Item {
        anchors.fill: parent

        // The leading tile: 26x26 at radius 8, a glyph inside it. The Wi-Fi
        // row has no leading element at all — also theirs, also deliberate.
        // A network has nothing to depict; a device has a KIND, and the
        // glyph is how you find the mouse among four headsets.
        Rectangle {
            id: deviceTile
            anchors.left: parent.left
            anchors.leftMargin: Metrics.pad(6)
            anchors.verticalCenter: parent.verticalCenter
            width: Metrics.px(26)
            height: width
            radius: Metrics.px(8)
            color: Qt.rgba(1, 1, 1, 0.04)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.10)

            Text {
                anchors.centerIn: parent
                text: root.hasProvider ? root.provider.bluetoothGlyph : ""
                color: root.connected ? StyleTokens.accent : StyleTokens.textTertiary
                font.pixelSize: Metrics.font(13)
                font.family: root.iconFontFamily
            }
        }

        // Two lines, spacing 1: the name over a meta caption. The caption is
        // what the single-line version had no room for, and it is the answer
        // to "which of these two identical headsets is the one that is
        // actually connected".
        Column {
            anchors.left: deviceTile.right
            anchors.leftMargin: Metrics.pad(10)
            anchors.right: actionLabel.left
            anchors.rightMargin: Metrics.pad(8)
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1

            Text {
                width: parent.width
                text: root.hasProvider && root.provider.bluetoothDeviceName
                    ? root.provider.bluetoothDeviceName(root.device)
                    : ""
                color: root.connected ? StyleTokens.textPrimary : StyleTokens.textSecondary
                font.pixelSize: Metrics.font(11.5)
                font.family: root.textFontFamily
                font.weight: root.connected ? Font.DemiBold : Font.Medium
                elide: Text.ElideRight
            }

            Text {
                width: parent.width
                visible: text.length > 0
                text: root.subtitleText
                color: StyleTokens.textMuted
                font.pixelSize: Metrics.font(9.5)
                font.family: root.textFontFamily
                font.weight: Font.Medium
                elide: Text.ElideRight
            }
        }

        // The action affordance. For an unpaired device this is their "Pair"
        // chip: a real chip with a fill and a border, because pairing is the
        // one thing on this row you can START. For everything else it stays
        // a small dim label — a hint about what Enter does, not a button.
        Rectangle {
            id: actionLabel

            anchors.right: parent.right
            anchors.rightMargin: Metrics.pad(8)
            anchors.verticalCenter: parent.verticalCenter
            width: actionText.implicitWidth + (root.isChip ? Metrics.px(16) : 0)
            height: root.isChip ? Metrics.px(18) : actionText.implicitHeight
            radius: height / 2
            color: root.isChip ? Qt.rgba(1, 1, 1, 0.05) : StyleTokens.transparent
            border.width: root.isChip ? 1 : 0
            border.color: Qt.rgba(1, 1, 1, 0.12)

            Text {
                id: actionText
                anchors.centerIn: parent
                text: root.section === "connected" ? "\u2713" : root.actionText
                color: root.section === "connected"
                    ? StyleTokens.accent
                    : (root.navCurrent ? StyleTokens.textSecondary : StyleTokens.textTertiary)
                font.pixelSize: root.section === "connected" ? Metrics.font(12) : Metrics.font(9.5)
                font.family: root.textFontFamily
                font.weight: Font.DemiBold
                font.capitalization: root.section === "connected"
                    ? Font.MixedCase : Font.AllUppercase
                font.letterSpacing: root.section === "connected" ? 0 : 1.0
            }
        }
    }

    Connections {
        target: root.device
        ignoreUnknownSignals: true

        function onPairedChanged() {
            if (!root.provider || !root.device)
                return;
            if (root.provider.bluetoothPairAndConnectPath !== root.device.dbusPath)
                return;

            if (root.device.paired || root.device.bonded) {
                root.device.trusted = true;
                root.device.connect();
                root.provider.bluetoothInfoMessage = "Connecting to "
                    + root.provider.bluetoothDeviceName(root.device) + "...";
            }
        }

        function onPairingChanged() {
            if (!root.provider || !root.device)
                return;
            if (root.provider.bluetoothPairAndConnectPath !== root.device.dbusPath)
                return;

            if (!root.device.pairing && !(root.device.paired || root.device.bonded)) {
                root.provider.bluetoothPairAndConnectPath = "";
                root.provider.bluetoothInfoMessage = "";
                if (!root.provider.bluetoothPairingActive)
                    root.provider.bluetoothError = "Pairing failed or was canceled.";
            }
        }

        function onConnectedChanged() {
            if (!root.provider || !root.device)
                return;
            if (root.provider.bluetoothPairAndConnectPath !== root.device.dbusPath)
                return;

            if (root.device.connected) {
                root.provider.bluetoothPairAndConnectPath = "";
                root.provider.bluetoothInfoMessage = "";
                root.provider.bluetoothError = "";
            }
        }
    }
}
