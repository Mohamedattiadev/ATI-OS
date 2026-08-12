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
    // FORK: IslandTheme.shellFill, passed down from DynamicIslandWindow. The
    // default is the old hardcoded near-black, so a bare instantiation still
    // renders rather than resolving to transparent.
    property color panelFill: "#101014"
    // FORK: false when the panel is hosted AS the capsule rather than beside
    // it — see ConnectivityPanelLayer.qml. The capsule already paints the
    // island's material, and a second rounded fill inside it at a smaller
    // radius shows as four pale corner wedges.
    property bool drawBackground: true
    property real presentationProgress: 1

    readonly property bool isWifi: panelKind === "wifi"
    readonly property bool isBluetooth: panelKind === "bluetooth"
    readonly property var bluetoothDevices: provider ? provider.bluetoothDeviceValues || [] : []
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

    // ------------------------------------------------------------------
    //  FORK: ONE LIST, SORTED BY RANK — not three labelled sections.
    // ------------------------------------------------------------------
    //  The last structural difference between this panel and ukishima's.
    //  Their BtSurface has no group headers and no hairlines between rows
    //  at all: the grouping is expressed purely by SORT ORDER, so a
    //  connected device is at the top because it sorts there, not because
    //  it lives in a box with a heading over it. Three Repeaters with three
    //  visibility gates were producing the same visual order by three times
    //  the machinery.
    //
    //  Rank is 0/1/2/3 — connected, paired, named, unnamed — with ties
    //  broken by localeCompare on the display name. The named/unnamed split
    //  is theirs and it earns its place: a Bluetooth scan fills up with
    //  address-only rows from passing phones and earbuds, and without that
    //  rank they interleave alphabetically with the devices you might
    //  actually want, since an address sorts as a string like anything else.
    //
    //  A REAL BUG THIS REMOVES, not just tidying. The section predicates in
    //  ControlCenterLayer overlap: "connected" is `device.connected`, but
    //  "available" is `!paired` — so a device that is connected WITHOUT
    //  being paired satisfies both, and today it renders twice, once in each
    //  Repeater. Rank is a single exclusive assignment per device, so a
    //  device can occupy exactly one position by construction.
    //
    //  The `section` string still exists per row, because BluetoothDeviceRow
    //  reads it for its affordances — the action reads "✓", "Connect" or
    //  "Pair", and the icon dims for an unknown device. It is now DERIVED
    //  from the same rank rather than being carried by which Repeater the
    //  row happened to be in, so the label a row shows and the place it
    //  sorts to can no longer disagree.
    function bluetoothRank(device) {
        if (!device)
            return 3;
        if (device.connected)
            return 0;
        if (device.paired || device.bonded)
            return 1;
        return root.bluetoothDisplayName(device).length > 0 ? 2 : 3;
    }

    function bluetoothSectionForRank(rank) {
        if (rank === 0)
            return "connected";
        if (rank === 1)
            return "paired";
        return "available";
    }

    // Name for SORTING only, so it must be empty when the device has no
    // real name. bluetoothDeviceName() falls back to the address and then
    // to "Unknown device", which would make every anonymous device look
    // named and collapse rank 3 into rank 2.
    function bluetoothDisplayName(device) {
        if (!device)
            return "";
        const preferred = root.safeString(device.deviceName).trim();
        if (preferred.length > 0)
            return preferred;
        return root.safeString(device.name).trim();
    }

    readonly property var bluetoothSortedDevices: {
        const devices = root.bluetoothDevices || [];
        const ranked = [];
        for (let index = 0; index < devices.length; index++) {
            const device = devices[index];
            if (!device)
                continue;
            ranked.push({
                device: device,
                rank: root.bluetoothRank(device),
                name: root.bluetoothDisplayName(device)
            });
        }
        ranked.sort(function (left, right) {
            if (left.rank !== right.rank)
                return left.rank - right.rank;
            return left.name.localeCompare(right.name);
        });
        return ranked;
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

    // ---- THE PANEL IS MADE OF THE SAME MATERIAL AS THE ISLAND ----
    //
    // Was StyleTokens.module at 0.9 opacity — a FIXED near-black from the
    // packaged tokens, which follows nothing. Reported as: every popup looks
    // the same colour as the terminal behind it, and it should be the
    // island's colour instead. That is exactly right, and it is the same
    // class of bug as the toggles that were a hardcoded iOS green: an
    // element that ignores the palette while everything around it follows
    // it.
    //
    // panelFill is IslandTheme.shellFill, the capsule's own material —
    // the theme background darkened 45% toward black with 8% of the accent
    // mixed in, so the panel is recognisably a piece of the island rather
    // than a grey box that happens to be near it, and it re-tints with
    // every theme-apply like the notch does.
    //
    // Opacity 0.9 -> 0.97. At 0.9 over a dark terminal the wallpaper and the
    // text behind bled through enough to muddy the tint that is the whole
    // point of the change; 0.97 is what RingOsdWindow already uses for the
    // same material over the same wallpaper.
    Rectangle {
        anchors.fill: parent
        radius: Metrics.px(28)
        color: root.panelFill
        opacity: 0.97
        visible: root.drawBackground
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

        // ---- HEADER, in ukishima's vocabulary ----
        //
        // Their surfaces open with a kanji glyph, then the surface name in
        // letterspaced uppercase at a much smaller size than you would
        // expect, then a "· status" clause that carries the accent when the
        // thing is live. It reads as a label on an instrument rather than as
        // a window title, which is the whole difference between their panels
        // and a 15 px bold "Wi-Fi".
        //
        // THE KANJI IS GONE, and everything else about the register stays.
        // There was a 波 ("wave") here for Wi-Fi and a 藍 ("indigo") for
        // Bluetooth. Removed on request — the ask was about the wallpaper
        // picker's 壁, but removing it there and keeping these would leave
        // the shell speaking two languages depending on which popup you
        // opened, which is worse than either choice on its own. It is also
        // the one part of ukishima's identity that is theirs rather than a
        // technique worth adapting; the fork's own rule is adapt, never
        // transplant. The letterspaced uppercase label is the part of that
        // header doing the work, and it stays.
        Row {
            id: headerRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: Metrics.px(24)
            spacing: Metrics.px(8)

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.isWifi ? "WIFI" : "BLUETOOTH"
                color: StyleTokens.textMuted
                font.family: root.textFontFamily
                font.pixelSize: Metrics.font(10)
                font.weight: Font.DemiBold
                font.capitalization: Font.AllUppercase
                // The letterspacing is the point of the treatment. Without
                // it this is just a small grey word.
                font.letterSpacing: 1.6
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(0, headerRow.width - x - Metrics.px(4))
                text: {
                    if (!root.provider)
                        return "";
                    if (root.isWifi) {
                        if (!root.provider.wifiEnabled)
                            return "· off";
                        const ssid = root.safeString(root.provider.wifiCurrentSsid);
                        return ssid.length > 0 ? "· " + ssid : "· not connected";
                    }
                    return root.provider.bluetoothEnabled ? "· on" : "· off";
                }
                // Accent only when there is something live to point at. A
                // status clause that is always accented stops being a status.
                color: {
                    if (!root.provider)
                        return StyleTokens.textTertiary;
                    const live = root.isWifi
                        ? (root.provider.wifiEnabled
                           && root.safeString(root.provider.wifiCurrentSsid).length > 0)
                        : !!root.provider.bluetoothEnabled;
                    return live ? StyleTokens.accent : StyleTokens.textTertiary;
                }
                font.family: root.textFontFamily
                font.pixelSize: Metrics.font(10)
                font.weight: Font.Medium
                elide: Text.ElideRight
            }
        }

        // The one piece of chrome ukishima's connectivity surfaces have: a
        // single hairline under the header, 9 px below it, and then 8 px of
        // air before the list. Nothing separates the ROWS — see the note on
        // sections in the Bluetooth repeaters.
        //
        // height 1 and NOT Metrics.px(1): every hairline in their tree is
        // unscaled on purpose, so it stays exactly one device pixel and
        // stays crisp instead of rounding to 2 at some scales.
        Rectangle {
            id: headerRule
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: headerRow.bottom
            anchors.topMargin: Metrics.pad(9)
            height: 1
            // Theme.hair — cream at 0.13.
            color: Qt.rgba(0.925, 0.925, 0.925, 0.13)
        }

        Column {
            id: topSection
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: headerRule.bottom
            anchors.topMargin: Metrics.pad(8)
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
                    // Their wording and their ellipsis: one U+2026 character,
                    // not three periods. Three periods in a proportional face
                    // set wider than the glyph and wobble as the label
                    // repaints.
                    text: "Searching networks\u2026"
                    color: StyleTokens.textMuted
                    font.pixelSize: Metrics.font(12)
                    font.family: root.textFontFamily
                }

                Repeater {
                    model: root.isWifi && root.provider ? root.provider.wifiNetworks : null

                    delegate: Rectangle {
                        id: wifiRow

                        width: contentColumn.width
                        // 52 -> 34, and the subtitle line went with it. A
                        // two-line row carrying "Secure network" under every
                        // SSID spends half its height restating what the
                        // padlock on the right already says, and five
                        // networks then fill a panel that could hold nine.
                        // ukishima's equivalent row is 30 px.
                        height: visible ? Metrics.px(30) : 0
                        radius: Metrics.px(9)
                        // Three states, in priority order. The CONNECTED row
                        // is accent-tinted because it is a fact about the
                        // system; the keyboard cursor is neutral white
                        // because it is a fact about the pointer. If the
                        // cursor also used the accent, moving it would look
                        // like connecting.
                        color: {
                            if (connected)
                                return Qt.rgba(StyleTokens.accent.r, StyleTokens.accent.g,
                                               StyleTokens.accent.b, 0.14);
                            if (root.navIsCurrent(wifiRow))
                                return Qt.rgba(1, 1, 1, 0.10);
                            return StyleTokens.transparent;
                        }
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

                            // One line, centred. The weight and colour carry
                            // "this is the one you are on" — ukishima leans
                            // on exactly this rather than on a badge.
                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: Metrics.pad(26)
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.right: rightInfo.left
                                anchors.rightMargin: Metrics.pad(8)
                                text: displayName
                                color: connected ? StyleTokens.accent : StyleTokens.textSecondary
                                font.pixelSize: Metrics.font(11.5)
                                font.family: root.textFontFamily
                                font.weight: connected ? Font.DemiBold : Font.Medium
                                elide: Text.ElideRight
                            }

                            Row {
                                id: rightInfo
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: Metrics.px(6)

                                // Dimmed and smaller. Signal strength is a
                                // tiebreak between two networks you already
                                // recognise, never the thing you are reading
                                // the row for, and at #f0f0f3 it was
                                // outshouting the SSID beside it.
                                Text {
                                    text: signal + "%"
                                    color: StyleTokens.textTertiary
                                    font.pixelSize: Metrics.font(10)
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

                // One Repeater over the rank-sorted list. Was three, one per
                // section, each wrapped in an Item whose height collapsed to
                // zero when its section was empty — the wrapper existed only
                // because an empty Column still contributed its parent's
                // spacing. With one list there is nothing to collapse.
                Item {
                    width: parent.width
                    height: btDeviceList.visible ? btDeviceList.implicitHeight : 0
                    visible: root.isBluetooth && root.bluetoothSortedDevices.length > 0

                    Column {
                        id: btDeviceList
                        width: parent.width
                        // No hairlines between rows, matching ukishima's
                        // BtSurface. The 8 px of air IS the separation; a
                        // rule between every row would reintroduce exactly
                        // the boxed-group reading the sections were removed
                        // for.
                        spacing: Metrics.px(8)

                        Repeater {
                            model: root.bluetoothSortedDevices

                            delegate: BluetoothDeviceRow {
                                id: deviceRow
                                required property var modelData
                                required property int index

                                width: btDeviceList.width
                                provider: root.provider
                                device: modelData.device
                                section: root.bluetoothSectionForRank(modelData.rank)
                                iconFontFamily: root.iconFontFamily
                                textFontFamily: root.textFontFamily

                                // ONE registry rank for every Bluetooth row,
                                // where there used to be three. The registry
                                // sorts by (rank, index) and the model is
                                // already in visual order, so a single rank
                                // with the model's own index reproduces the
                                // visual order exactly — which is the whole
                                // contract that registry was built to keep.
                                // Wi-Fi rows register rank 0 and are never on
                                // screen at the same time as these.
                                navCurrent: root.navIsCurrent(deviceRow)
                                Component.onCompleted: root.navRegister(1, index, deviceRow)
                                Component.onDestruction: root.navUnregister(deviceRow)
                                onVisibleChanged: root.navRevision++
                            }
                        }
                    }
                }

                // ---- THE BLUETOOTH EMPTY STATE, WHICH DID NOT EXIST ----
                //
                // With no devices in range this panel rendered as a titled
                // rectangle of nothing. That is indistinguishable from a
                // panel that has failed, and it is the state a Bluetooth
                // list is in most of the time it is opened.
                //
                // Two different sentences, because "scanning" and "found
                // nothing" are different facts and collapsing them into one
                // string is how a spinner that has silently died still looks
                // like it is working.
                Item {
                    width: parent.width
                    height: visible ? Metrics.px(72) : 0
                    visible: root.isBluetooth && root.bluetoothSortedDevices.length === 0

                    Text {
                        anchors.centerIn: parent
                        text: root.bluetoothScanning
                            ? "Scanning\u2026"
                            : (root.provider && root.provider.bluetoothEnabled
                               ? "No devices found"
                               : "Turn on Bluetooth to see nearby devices.")
                        color: StyleTokens.textMuted
                        font.pixelSize: Metrics.font(10.5)
                        font.family: root.textFontFamily
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
            }
        }

    }
}
