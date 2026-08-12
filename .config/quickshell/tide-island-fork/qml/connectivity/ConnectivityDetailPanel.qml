import QtQuick
import IslandBackend

// FORK: one shared scale factor for every island surface.
import "../common/Metrics.js" as Metrics
// FORK: the shared motion system — one generated spring for geometry,
// one critically damped curve for opacity. See qml/common/Motion.js.
import "../common/Motion.js" as Motion

Item {
    id: root

    property var provider: null
    property string panelKind: "wifi"
    property string iconFontFamily: ""
    property string textFontFamily: ""
    property string heroFontFamily: textFontFamily
    property real presentationProgress: 1

    readonly property bool isWifi: panelKind === "wifi"
    readonly property bool isBluetooth: panelKind === "bluetooth"
    readonly property var bluetoothDevices: provider ? provider.bluetoothDeviceValues || [] : []
    readonly property var bluetoothConnectedDevices: bluetoothDevicesForSection("connected")
    readonly property var bluetoothPairedDevices: bluetoothDevicesForSection("paired")
    readonly property var bluetoothAvailableDevices: bluetoothDevicesForSection("available")
    readonly property bool bluetoothScanning: provider && provider.bluetoothAdapter
        ? provider.bluetoothAdapter.discovering
        : !!(provider && provider.bluetoothListRunning)

    function safeString(value) {
        return value === undefined || value === null ? "" : String(value);
    }

    function wifiEntryVisible(connected) {
        if (!root.provider) return false;
        return !(connected && root.provider.wifiEnabled && safeString(root.provider.wifiCurrentSsid).length > 0);
    }

    function bluetoothDeviceVisible(device, section) {
        return root.provider && root.provider.bluetoothDeviceMatchesSection
            ? root.provider.bluetoothDeviceMatchesSection(device, section)
            : false;
    }

    function bluetoothDevicesForSection(section) {
        const devices = root.bluetoothDevices || [];
        const filtered = [];

        for (let index = 0; index < devices.length; index++) {
            const device = devices[index];
            if (root.bluetoothDeviceVisible(device, section))
                filtered.push(device);
        }

        return filtered;
    }

    function focusPromptField() {
        if (wifiPasswordPrompt.visible) {
            wifiPasswordField.forceActiveFocus();
            return;
        }

        if (bluetoothPairingPrompt.visible && bluetoothSecretField.visible)
            bluetoothSecretField.forceActiveFocus();
    }

    Timer {
        id: promptFocusTimer
        interval: 0
        repeat: false
        onTriggered: root.focusPromptField()
    }

    Connections {
        target: root.provider
        ignoreUnknownSignals: true

        function onWifiPendingPasswordSsidChanged() {
            promptFocusTimer.restart();
        }

        function onBluetoothPairingActiveChanged() {
            promptFocusTimer.restart();
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: Metrics.px(28)
        color: StyleTokens.module
        opacity: 0.9
    }

    Item {
        id: contentRoot
        anchors.fill: parent
        anchors.margins: Metrics.pad(16)
        opacity: 0.45 + root.presentationProgress * 0.55

        Behavior on opacity {
            NumberAnimation {
                duration: 140
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Motion.fade()   // FORK: was Easing.OutCubic
            }
        }

        Row {
            id: headerRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: Metrics.px(24)

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.isWifi ? "Wi-Fi" : "Bluetooth"
                color: StyleTokens.textPrimary
                font.pixelSize: Metrics.font(15)
                font.family: root.heroFontFamily
                font.weight: Font.Bold
            }
        }

        Column {
            id: topSection
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: headerRow.bottom
            anchors.topMargin: Metrics.pad(14)
            spacing: Metrics.px(10)

            Rectangle {
                width: parent.width
                height: visible ? 64 : 0
                radius: Metrics.px(16)
                color: StyleTokens.transparent
                visible: root.isWifi && root.provider && root.provider.wifiEnabled && root.provider.wifiCurrentSsid.length > 0

                MouseArea {
                    anchors.fill: parent
                    enabled: root.provider
                        && root.provider.wifiSupported
                        && root.provider.wifiAvailable
                        && !root.provider.wifiBusy
                    onClicked: {
                        if (root.provider)
                            root.provider.disconnectWifi();
                    }
                }

                Item {
                    anchors.fill: parent
                    anchors.margins: Metrics.pad(14)

                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.provider ? root.provider.wifiGlyph : ""
                        color: StyleTokens.accent
                        font.pixelSize: Metrics.font(16)
                        font.family: root.iconFontFamily
                    }

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: Metrics.pad(28)
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.rightMargin: Metrics.pad(24)
                        text: root.provider ? root.provider.wifiCurrentSsid : ""
                        color: StyleTokens.textPrimary
                        font.pixelSize: Metrics.font(12)
                        font.family: root.textFontFamily
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: Metrics.pad(28)
                        anchors.bottom: parent.bottom
                        text: "Connected"
                        color: StyleTokens.textSoft
                        font.pixelSize: Metrics.font(11)
                        font.family: root.textFontFamily
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: "✓"
                        color: StyleTokens.success
                        font.pixelSize: Metrics.font(18)
                        font.family: root.textFontFamily
                        font.weight: Font.DemiBold
                    }
                }
            }

            Text {
                width: parent.width
                visible: root.provider && root.provider.wifiAvailabilityMessage.length > 0 && root.isWifi
                text: root.provider ? root.provider.wifiAvailabilityMessage : ""
                color: StyleTokens.textMuted
                font.pixelSize: Metrics.font(11)
                font.family: root.textFontFamily
                wrapMode: Text.Wrap
            }

            Text {
                width: parent.width
                visible: root.provider && root.provider.wifiInfoMessage.length > 0 && root.isWifi
                text: root.provider ? root.provider.wifiInfoMessage : ""
                color: StyleTokens.accentSoft
                font.pixelSize: Metrics.font(11)
                font.family: root.textFontFamily
                wrapMode: Text.Wrap
            }

            Text {
                width: parent.width
                visible: root.provider && root.provider.wifiError.length > 0 && root.isWifi
                text: root.provider ? root.provider.wifiError : ""
                color: StyleTokens.error
                font.pixelSize: Metrics.font(11)
                font.family: root.textFontFamily
                wrapMode: Text.Wrap
            }

            Text {
                width: parent.width
                visible: root.provider && root.provider.bluetoothAvailabilityMessage.length > 0 && root.isBluetooth
                text: root.provider ? root.provider.bluetoothAvailabilityMessage : ""
                color: StyleTokens.textMuted
                font.pixelSize: Metrics.font(11)
                font.family: root.textFontFamily
                wrapMode: Text.Wrap
            }

            Text {
                width: parent.width
                visible: root.provider && root.provider.bluetoothInfoMessage.length > 0 && root.isBluetooth
                text: root.provider ? root.provider.bluetoothInfoMessage : ""
                color: StyleTokens.accentSoft
                font.pixelSize: Metrics.font(11)
                font.family: root.textFontFamily
                wrapMode: Text.Wrap
            }

            Text {
                width: parent.width
                visible: root.provider && root.provider.bluetoothError.length > 0 && root.isBluetooth
                text: root.provider ? root.provider.bluetoothError : ""
                color: StyleTokens.error
                font.pixelSize: Metrics.font(11)
                font.family: root.textFontFamily
                wrapMode: Text.Wrap
            }

            Rectangle {
                id: bluetoothPairingPrompt
                width: parent.width
                height: visible
                    ? ((root.provider && root.provider.bluetoothPairingRequiresInput)
                        ? 122
                        : ((root.provider && root.provider.bluetoothPairingRequiresConfirmation) ? 110 : 82))
                    : 0
                radius: Metrics.px(16)
                color: StyleTokens.prompt
                visible: root.isBluetooth && root.provider && root.provider.bluetoothPairingActive
                clip: true

                onVisibleChanged: {
                    if (visible)
                        promptFocusTimer.restart();
                }

                Item {
                    anchors.fill: parent
                    anchors.margins: Metrics.pad(12)

                    Column {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        spacing: Metrics.px(10)

                        Text {
                            width: parent.width
                            text: root.provider ? root.provider.bluetoothPairingTitle : ""
                            color: StyleTokens.textPrimary
                            font.pixelSize: Metrics.font(12)
                            font.family: root.textFontFamily
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }

                        Text {
                            width: parent.width
                            text: root.provider ? root.provider.bluetoothPairingMessage : ""
                            color: "#d2d4da"
                            font.pixelSize: Metrics.font(11)
                            font.family: root.textFontFamily
                            wrapMode: Text.Wrap
                        }
                    }

                    Row {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        spacing: Metrics.px(8)
                        visible: root.provider
                            && (root.provider.bluetoothPairingRequiresInput
                                || root.provider.bluetoothPairingRequiresConfirmation)

                        Rectangle {
                            id: bluetoothSecretFieldFrame
                            width: visible
                                ? Math.max(0, parent.width - bluetoothPrimaryButton.width - bluetoothCancelButton.width - 16)
                                : 0
                            height: Metrics.px(34)
                            radius: Metrics.px(12)
                            color: StyleTokens.input
                            border.color: StyleTokens.inputBorder
                            border.width: 1
                            visible: root.provider && root.provider.bluetoothPairingRequiresInput

                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: Metrics.pad(12)
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.provider && root.provider.bluetoothPairingNumericInput
                                    ? "Passkey"
                                    : "PIN"
                                color: StyleTokens.textTertiary
                                font.pixelSize: Metrics.font(11)
                                font.family: root.textFontFamily
                                visible: bluetoothSecretField.text.length === 0 && !bluetoothSecretField.activeFocus
                            }

                            TextInput {
                                id: bluetoothSecretField
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: Metrics.pad(12)
                                anchors.rightMargin: Metrics.pad(12)
                                height: Math.min(parent.height - 8, implicitHeight + 2)
                                color: StyleTokens.textPrimary
                                font.pixelSize: Metrics.font(11)
                                font.family: root.textFontFamily
                                verticalAlignment: TextInput.AlignVCenter
                                topPadding: 0
                                bottomPadding: 0
                                leftPadding: 0
                                rightPadding: 0
                                clip: true
                                selectByMouse: true
                                cursorVisible: activeFocus
                                inputMethodHints: root.provider && root.provider.bluetoothPairingNumericInput
                                    ? Qt.ImhDigitsOnly
                                    : Qt.ImhNoPredictiveText
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
                            }
                        }

                        Rectangle {
                            id: bluetoothPrimaryButton
                            width: root.provider && root.provider.bluetoothPairingRequiresInput ? 50 : 76
                            height: Metrics.px(34)
                            radius: Metrics.px(12)
                            color: StyleTokens.accent

                            Text {
                                anchors.centerIn: parent
                                text: root.provider && root.provider.bluetoothPairingRequiresConfirmation
                                    ? "Confirm"
                                    : "Pair"
                                color: StyleTokens.white
                                font.pixelSize: Metrics.font(11)
                                font.family: root.textFontFamily
                                font.weight: Font.DemiBold
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    if (!root.provider)
                                        return;

                                    if (root.provider.bluetoothPairingRequiresConfirmation)
                                        root.provider.confirmBluetoothPairing();
                                    else
                                        root.provider.submitBluetoothPairingSecret();
                                }
                            }
                        }

                        Rectangle {
                            id: bluetoothCancelButton
                            width: Metrics.px(58)
                            height: Metrics.px(34)
                            radius: Metrics.px(12)
                            color: StyleTokens.secondaryButton

                            Text {
                                anchors.centerIn: parent
                                text: "Cancel"
                                color: StyleTokens.textPrimary
                                font.pixelSize: Metrics.font(11)
                                font.family: root.textFontFamily
                                font.weight: Font.DemiBold
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    if (root.provider)
                                        root.provider.cancelBluetoothPairing();
                                }
                            }
                        }
                    }
                }
            }

            Rectangle {
                id: wifiPasswordPrompt
                width: parent.width
                height: visible ? 92 : 0
                radius: Metrics.px(16)
                color: StyleTokens.prompt
                visible: root.isWifi && root.provider && root.provider.wifiPendingPasswordSsid.length > 0
                clip: true

                onVisibleChanged: {
                    if (visible)
                        promptFocusTimer.restart();
                }

                Item {
                    anchors.fill: parent
                    anchors.margins: Metrics.pad(12)

                    Text {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.right: parent.right
                        text: "Enter password for " + (root.provider ? root.provider.wifiPendingPasswordSsid : "")
                        color: StyleTokens.textPrimary
                        font.pixelSize: Metrics.font(12)
                        font.family: root.textFontFamily
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: joinButton.left
                        anchors.rightMargin: Metrics.pad(8)
                        anchors.bottom: parent.bottom
                        height: Metrics.px(34)
                        radius: Metrics.px(12)
                        color: StyleTokens.input
                        border.color: StyleTokens.inputBorder
                        border.width: 1

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: Metrics.pad(12)
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Password"
                            color: StyleTokens.textTertiary
                            font.pixelSize: Metrics.font(11)
                            font.family: root.textFontFamily
                            visible: root.provider && root.provider.wifiPendingPasswordValue.length === 0 && !wifiPasswordField.activeFocus
                        }

                        TextInput {
                            id: wifiPasswordField
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: Metrics.pad(12)
                            anchors.rightMargin: Metrics.pad(12)
                            height: Math.min(parent.height - 8, implicitHeight + 2)
                            color: StyleTokens.textPrimary
                            font.pixelSize: Metrics.font(11)
                            font.family: root.textFontFamily
                            echoMode: TextInput.Password
                            verticalAlignment: TextInput.AlignVCenter
                            topPadding: 0
                            bottomPadding: 0
                            leftPadding: 0
                            rightPadding: 0
                            clip: true
                            selectByMouse: true
                            cursorVisible: activeFocus
                            text: root.provider ? root.provider.wifiPendingPasswordValue : ""
                            onTextChanged: {
                                if (root.provider)
                                    root.provider.wifiPendingPasswordValue = text;
                            }
                            Keys.onReturnPressed: {
                                if (root.provider)
                                    root.provider.submitWifiPassword();
                            }
                        }
                    }

                    Rectangle {
                        id: joinButton
                        anchors.right: cancelButton.left
                        anchors.rightMargin: Metrics.pad(8)
                        anchors.bottom: parent.bottom
                        width: Metrics.px(50)
                        height: Metrics.px(34)
                        radius: Metrics.px(12)
                        color: StyleTokens.accent

                        Text {
                            anchors.centerIn: parent
                            text: "Join"
                            color: StyleTokens.white
                            font.pixelSize: Metrics.font(11)
                            font.family: root.textFontFamily
                            font.weight: Font.DemiBold
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                if (root.provider)
                                    root.provider.submitWifiPassword();
                            }
                        }
                    }

                    Rectangle {
                        id: cancelButton
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        width: Metrics.px(50)
                        height: Metrics.px(34)
                        radius: Metrics.px(12)
                        color: StyleTokens.secondaryButton

                        Text {
                            anchors.centerIn: parent
                            text: "Cancel"
                            color: StyleTokens.textPrimary
                            font.pixelSize: Metrics.font(11)
                            font.family: root.textFontFamily
                            font.weight: Font.DemiBold
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                if (root.provider)
                                    root.provider.clearWifiPrompt();
                            }
                        }
                    }
                }
            }
        }

        Flickable {
            id: contentFlick
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: topSection.bottom
            anchors.bottom: parent.bottom
            clip: true
            contentWidth: width
            contentHeight: contentColumn.implicitHeight
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: contentColumn
                width: contentFlick.width
                spacing: Metrics.px(8)

                Text {
                    width: parent.width
                    visible: root.isWifi && root.provider
                        && root.provider.wifiSupported
                        && root.provider.wifiAvailable
                        && !root.provider.wifiEnabled
                    text: "Turn on Wi-Fi to see nearby networks."
                    color: StyleTokens.textMuted
                    font.pixelSize: Metrics.font(12)
                    font.family: root.textFontFamily
                    wrapMode: Text.Wrap
                }

                Text {
                    width: parent.width
                    visible: root.isWifi && root.provider && root.provider.wifiListRunning
                    text: "Scanning nearby networks..."
                    color: StyleTokens.textMuted
                    font.pixelSize: Metrics.font(12)
                    font.family: root.textFontFamily
                }

                Repeater {
                    model: root.isWifi && root.provider ? root.provider.wifiNetworks : null

                    delegate: Rectangle {
                        width: contentColumn.width
                        height: visible ? 52 : 0
                        radius: Metrics.px(14)
                        color: StyleTokens.transparent
                        visible: root.wifiEntryVisible(connected)
                        clip: true

                        MouseArea {
                            anchors.fill: parent
                            enabled: root.provider
                                && root.provider.wifiSupported
                                && root.provider.wifiAvailable
                                && root.provider.wifiEnabled
                                && !root.provider.wifiBusy
                            onClicked: {
                                if (!root.provider) return;
                                root.provider.connectWifiNetwork({
                                    ssid: ssid,
                                    type: type,
                                    secure: secure,
                                    savedConnection: savedConnection,
                                    connected: connected
                                });
                            }
                        }

                        Item {
                            anchors.fill: parent
                            anchors.margins: Metrics.pad(12)

                            Text {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.provider ? root.provider.wifiGlyph : ""
                                color: connected ? StyleTokens.accent : StyleTokens.disabledControl
                                font.pixelSize: Metrics.font(14)
                                font.family: root.iconFontFamily
                            }

                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: Metrics.pad(26)
                                anchors.top: parent.top
                                anchors.right: rightInfo.left
                                anchors.rightMargin: Metrics.pad(8)
                                text: displayName
                                color: StyleTokens.textPrimary
                                font.pixelSize: Metrics.font(12)
                                font.family: root.textFontFamily
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }

                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: Metrics.pad(26)
                                anchors.bottom: parent.bottom
                                anchors.right: rightInfo.left
                                anchors.rightMargin: Metrics.pad(8)
                                text: secure ? "Secure network" : "Open network"
                                color: StyleTokens.textMuted
                                font.pixelSize: Metrics.font(10)
                                font.family: root.textFontFamily
                                elide: Text.ElideRight
                            }

                            Row {
                                id: rightInfo
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: Metrics.px(6)

                                Text {
                                    text: signal + "%"
                                    color: "#f0f0f3"
                                    font.pixelSize: Metrics.font(11)
                                    font.family: root.textFontFamily
                                    visible: signal >= 0
                                }

                                Text {
                                    text: ""
                                    color: StyleTokens.textSubtle
                                    font.pixelSize: Metrics.font(11)
                                    font.family: root.iconFontFamily
                                    visible: secure
                                }
                            }
                        }
                    }
                }

                Text {
                    width: parent.width
                    visible: root.isBluetooth && root.provider && root.provider.bluetoothAvailable && !root.provider.bluetoothEnabled
                    text: "Turn on Bluetooth to see nearby devices."
                    color: StyleTokens.textMuted
                    font.pixelSize: Metrics.font(12)
                    font.family: root.textFontFamily
                    wrapMode: Text.Wrap
                }

                Text {
                    width: parent.width
                    visible: root.isBluetooth && root.provider
                        && root.provider.bluetoothEnabled
                        && root.bluetoothScanning
                    text: "Scanning nearby devices..."
                    color: StyleTokens.textMuted
                    font.pixelSize: Metrics.font(12)
                    font.family: root.textFontFamily
                }

                Item {
                    width: parent.width
                    height: btConnectedSection.visible ? btConnectedSection.implicitHeight : 0
                    visible: root.isBluetooth && root.bluetoothConnectedDevices.length > 0

                    Column {
                        id: btConnectedSection
                        width: parent.width
                        spacing: Metrics.px(8)

                        Repeater {
                            model: root.bluetoothConnectedDevices

                            delegate: BluetoothDeviceRow {
                                width: btConnectedSection.width
                                provider: root.provider
                                device: modelData
                                section: "connected"
                                iconFontFamily: root.iconFontFamily
                                textFontFamily: root.textFontFamily
                            }
                        }
                    }
                }

                Item {
                    width: parent.width
                    height: btPairedSection.visible ? btPairedSection.implicitHeight : 0
                    visible: root.isBluetooth && root.bluetoothPairedDevices.length > 0

                    Column {
                        id: btPairedSection
                        width: parent.width
                        spacing: Metrics.px(8)

                        Repeater {
                            model: root.bluetoothPairedDevices

                            delegate: BluetoothDeviceRow {
                                width: btPairedSection.width
                                provider: root.provider
                                device: modelData
                                section: "paired"
                                iconFontFamily: root.iconFontFamily
                                textFontFamily: root.textFontFamily
                            }
                        }
                    }
                }

                Item {
                    width: parent.width
                    height: btAvailableSection.visible ? btAvailableSection.implicitHeight : 0
                    visible: root.isBluetooth && root.bluetoothAvailableDevices.length > 0

                    Column {
                        id: btAvailableSection
                        width: parent.width
                        spacing: Metrics.px(8)

                        Repeater {
                            model: root.bluetoothAvailableDevices

                            delegate: BluetoothDeviceRow {
                                width: btAvailableSection.width
                                provider: root.provider
                                device: modelData
                                section: "available"
                                iconFontFamily: root.iconFontFamily
                                textFontFamily: root.textFontFamily
                            }
                        }
                    }
                }
            }
        }

    }
}
