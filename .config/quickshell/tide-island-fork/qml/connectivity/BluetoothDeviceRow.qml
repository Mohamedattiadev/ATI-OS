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

    width: parent ? parent.width : 0
    // Matched to the Wi-Fi row's new 34: the two lists sit in panels of the
    // same size and a device row half again as tall as a network row made
    // them read as different products.
    height: Metrics.px(34)
    radius: Metrics.px(9)
    // Same three states as the Wi-Fi row, same priority: a CONNECTED device
    // is accent-tinted (a fact about the system), the keyboard cursor is
    // neutral white (a fact about the pointer).
    color: {
        if (root.connected)
            return Qt.rgba(StyleTokens.accent.r, StyleTokens.accent.g,
                           StyleTokens.accent.b, 0.14);
        if (navCurrent)
            return Qt.rgba(1, 1, 1, 0.10);
        return StyleTokens.transparent;
    }
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
        anchors.margins: Metrics.pad(12)

        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: root.hasProvider ? root.provider.bluetoothGlyph : ""
            color: root.iconColor
            font.pixelSize: Metrics.font(14)
            font.family: root.iconFontFamily
        }

        // One line. The subtitle it replaces said "Connected" on a row
        // already tinted with the accent and already showing a tick, and a
        // battery percentage that the action column has room for.
        Text {
            anchors.left: parent.left
            anchors.leftMargin: Metrics.pad(26)
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: actionLabel.left
            anchors.rightMargin: Metrics.pad(8)
            text: root.hasProvider && root.provider.bluetoothDeviceName
                ? root.provider.bluetoothDeviceName(root.device)
                : ""
            color: root.connected ? StyleTokens.accent : StyleTokens.textSecondary
            font.pixelSize: Metrics.font(11.5)
            font.family: root.textFontFamily
            font.weight: root.connected ? Font.DemiBold : Font.Medium
            elide: Text.ElideRight
        }

        // The action column, in ukishima's register: small, letterspaced,
        // uppercase, and dim until it is the live one. It was a 18 px tick
        // and an 11 px "Connect" in full-strength white — two different
        // sizes of shout in a column that is only ever a hint about what
        // Enter will do.
        Text {
            id: actionLabel

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.section === "connected" ? "✓" : root.actionText
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
