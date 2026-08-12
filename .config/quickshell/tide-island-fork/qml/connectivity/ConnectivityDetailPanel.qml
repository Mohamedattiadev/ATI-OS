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

    // ------------------------------------------------------------------
    //  FORK: keyboard navigation. This panel had no Keys handler at all.
    // ------------------------------------------------------------------
    //  It was not that the motions were bound to the wrong keys — there was
    //  no key handling in this file, none in ConnectivityDetailShell.qml,
    //  and none in ControlCenterLayer.qml either. The panels were mouse-only
    //  end to end, and the island's WlrLayershell.keyboardFocus never went
    //  above None while one was open unless a password prompt was up. So
    //  nothing could have received a keystroke to ignore.
    //
    //  ---- WHY THE ROWS REGISTER THEMSELVES ----
    //
    //  The obvious implementation is to flatten the four lists in JS and
    //  index that array. It cannot be done here: `provider.wifiNetworks` is
    //  `wifiController.networks` from the COMPILED IslandBackend, and its
    //  type is not visible from QML — the Wi-Fi delegate reads bare `ssid`
    //  and `secure`, which is the spelling for a QAbstractListModel with
    //  roles, and such a model cannot be subscripted from JavaScript at all.
    //  Bluetooth's three lists ARE plain arrays. Writing one traversal for
    //  two different kinds of container, one of which may not be traversable,
    //  is how this ends up with a navigation order that silently disagrees
    //  with what is on screen.
    //
    //  So every row registers itself as it is created and unregisters as it
    //  is destroyed, and the order comes from (section rank, index within
    //  section) rather than from re-deriving the models. That is
    //  container-agnostic, it is exactly the visual order because the four
    //  Repeaters sit in that order in contentColumn, and a row that is
    //  filtered out cannot be selected because it never registers.
    //
    //  Sorting by mapped y would also give visual order and was rejected:
    //  positions are not settled while the panel is still animating in, so
    //  the first keypress after opening would navigate a list sorted by
    //  wherever the rows happened to be mid-flight.

    signal closeRequested()

    // Set by the host while this panel is the open one. Gates BOTH the
    // focus grab and the highlight: a highlighted row in a panel that is
    // sliding away is an invitation to press Enter on it.
    property bool keyboardActive: false

    property var navEntries: []
    // Bumped on every registration, removal and visibility change. navRows
    // reads it so the list recomputes; without it, a row appearing or
    // vanishing leaves a stale selection pointing at a destroyed item.
    property int navRevision: 0
    property int navSelected: 0

    readonly property var navRows: {
        navRevision;
        const live = [];
        for (let index = 0; index < navEntries.length; index++) {
            const entry = navEntries[index];
            if (entry && entry.item && entry.item.visible && entry.item.height > 0)
                live.push(entry);
        }
        live.sort(function (left, right) {
            return left.rank !== right.rank ? left.rank - right.rank
                                            : left.index - right.index;
        });
        return live;
    }

    readonly property var navCurrent: navRows.length > 0
        ? navRows[Math.max(0, Math.min(navSelected, navRows.length - 1))]
        : null

    onNavRowsChanged: {
        if (navRows.length === 0) {
            navSelected = 0;
            return;
        }
        if (navSelected > navRows.length - 1)
            navSelected = navRows.length - 1;
        if (navSelected < 0)
            navSelected = 0;
    }

    function navRegister(rank, index, item) {
        navEntries.push({ rank: rank, index: index, item: item });
        navRevision++;
    }

    function navUnregister(item) {
        for (let index = 0; index < navEntries.length; index++) {
            if (navEntries[index].item === item) {
                navEntries.splice(index, 1);
                break;
            }
        }
        navRevision++;
    }

    function navIsCurrent(item) {
        return keyboardActive && navCurrent !== null && navCurrent.item === item;
    }

    function navMove(delta) {
        const count = navRows.length;
        if (count === 0)
            return;
        // Clamped, not wrapped. A list that jumps from the last network back
        // to the first on one extra `j` is a list you overshoot silently;
        // these are actions with consequences (joining a network, pairing a
        // device) and the cursor should stop at the end.
        navSelected = Math.max(0, Math.min(count - 1, navSelected + delta));
        navEnsureVisible();
    }

    function navEnsureVisible() {
        const current = root.navCurrent;
        if (!current || !current.item)
            return;
        const item = current.item;
        const position = item.mapToItem(contentColumn, 0, 0);
        const margin = Metrics.px(8);
        const top = position.y - margin;
        const bottom = position.y + item.height + margin;
        const maxContentY = Math.max(0, contentFlick.contentHeight - contentFlick.height);

        if (top < contentFlick.contentY)
            contentFlick.contentY = Math.max(0, Math.min(maxContentY, top));
        else if (bottom > contentFlick.contentY + contentFlick.height)
            contentFlick.contentY = Math.max(0, Math.min(maxContentY, bottom - contentFlick.height));
    }

    function navActivate() {
        const current = root.navCurrent;
        if (current && current.item && current.item.navActivate)
            current.item.navActivate();
    }

    // The password/pairing field wins every key while it is up: typing a
    // WPA passphrase containing a j or a k must not move the selection.
    readonly property bool navBlockedByPrompt:
        wifiPasswordPrompt.visible || bluetoothPairingPrompt.visible

    focus: keyboardActive
    Keys.onPressed: function (event) {
        if (root.navBlockedByPrompt) {
            // Escape still has to work, or a prompt with nothing typed into
            // it is a panel you can only leave with the mouse.
            if (event.key === Qt.Key_Escape) {
                root.closeRequested();
                event.accepted = true;
            }
            return;
        }

        switch (event.key) {
        case Qt.Key_Escape:
        case Qt.Key_Q:
            root.closeRequested();
            event.accepted = true;
            break;
        case Qt.Key_Down:
        case Qt.Key_J:
            root.navMove(1);
            event.accepted = true;
            break;
        case Qt.Key_Up:
        case Qt.Key_K:
            root.navMove(-1);
            event.accepted = true;
            break;
        case Qt.Key_Return:
        case Qt.Key_Enter:
        case Qt.Key_Space:
            root.navActivate();
            event.accepted = true;
            break;
        case Qt.Key_G:
            root.navSelected = (event.modifiers & Qt.ShiftModifier) !== 0
                ? Math.max(0, root.navRows.length - 1)
                : 0;
            root.navEnsureVisible();
            event.accepted = true;
            break;
        default:
            break;
        }
    }

    onKeyboardActiveChanged: {
        if (keyboardActive) {
            navSelected = 0;
            forceActiveFocus();
        }
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
                        id: wifiRow

                        width: contentColumn.width
                        height: visible ? 52 : 0
                        radius: Metrics.px(14)
                        // The keyboard highlight. Deliberately the same
                        // shape the row already is, filled rather than
                        // outlined: an outline at this radius reads as a
                        // text field, and there is one of those on screen.
                        color: root.navIsCurrent(wifiRow)
                            ? Qt.rgba(1, 1, 1, 0.10)
                            : StyleTokens.transparent
                        visible: root.wifiEntryVisible(connected)
                        clip: true

                        // Rank 0: the Wi-Fi list is the only section on this
                        // panel, and it sits above all three Bluetooth ones
                        // in contentColumn. See navRegister.
                        Component.onCompleted: root.navRegister(0, index, wifiRow)
                        Component.onDestruction: root.navUnregister(wifiRow)
                        // A filtered-out row keeps its place in the Repeater
                        // but must leave the navigation, or `j` walks onto a
                        // zero-height row and appears to do nothing.
                        onVisibleChanged: root.navRevision++

                        // One activation path for pointer and keyboard. When
                        // these were two copies, the keyboard one is the copy
                        // that quietly stops matching.
                        function navActivate() {
                            if (!root.provider) return;
                            if (!(root.provider.wifiSupported
                                    && root.provider.wifiAvailable
                                    && root.provider.wifiEnabled
                                    && !root.provider.wifiBusy))
                                return;
                            root.provider.connectWifiNetwork({
                                ssid: ssid,
                                type: type,
                                secure: secure,
                                savedConnection: savedConnection,
                                connected: connected
                            });
                        }

                        MouseArea {
                            anchors.fill: parent
                            enabled: root.provider
                                && root.provider.wifiSupported
                                && root.provider.wifiAvailable
                                && root.provider.wifiEnabled
                                && !root.provider.wifiBusy
                            onClicked: wifiRow.navActivate()
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
                                id: connectedRow
                                width: btConnectedSection.width
                                provider: root.provider
                                device: modelData
                                section: "connected"
                                iconFontFamily: root.iconFontFamily
                                textFontFamily: root.textFontFamily

                                // Ranks 1/2/3 follow contentColumn's order:
                                // connected, then paired, then available.
                                navCurrent: root.navIsCurrent(connectedRow)
                                Component.onCompleted: root.navRegister(1, index, connectedRow)
                                Component.onDestruction: root.navUnregister(connectedRow)
                                onVisibleChanged: root.navRevision++
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
                                id: pairedRow
                                width: btPairedSection.width
                                provider: root.provider
                                device: modelData
                                section: "paired"
                                iconFontFamily: root.iconFontFamily
                                textFontFamily: root.textFontFamily

                                // Ranks 1/2/3 follow contentColumn's order:
                                // connected, then paired, then available.
                                navCurrent: root.navIsCurrent(pairedRow)
                                Component.onCompleted: root.navRegister(2, index, pairedRow)
                                Component.onDestruction: root.navUnregister(pairedRow)
                                onVisibleChanged: root.navRevision++
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
                                id: availableRow
                                width: btAvailableSection.width
                                provider: root.provider
                                device: modelData
                                section: "available"
                                iconFontFamily: root.iconFontFamily
                                textFontFamily: root.textFontFamily

                                // Ranks 1/2/3 follow contentColumn's order:
                                // connected, then paired, then available.
                                navCurrent: root.navIsCurrent(availableRow)
                                Component.onCompleted: root.navRegister(3, index, availableRow)
                                Component.onDestruction: root.navUnregister(availableRow)
                                onVisibleChanged: root.navRevision++
                            }
                        }
                    }
                }
            }
        }

    }
}
