pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import IslandBackend

// FORK: the shared scale factor — see qml/common/Metrics.js.
import "../common/Metrics.js" as Metrics
// FORK: the shared motion system — one spring for geometry, one critically
// damped curve for opacity. See qml/common/Motion.js.
import "../common/Motion.js" as Motion
import "../common"

//
// FORK — new file. The Wi-Fi panel, rebuilt from scratch in the idiom of
// qml/audio/AudioPanel.qml and qml/display/DisplayPanel.qml.
//
// WHAT IT REPLACES
// ----------------
// ConnectivityDetailPanel.qml served BOTH Wi-Fi and Bluetooth through a
// `panelKind` string, with `isWifi` / `isBluetooth` branches on nearly every
// visible element: two headers, two empty states, two prompt blocks, two sets
// of message lines, and one Flickable holding both lists at once with every
// child gated on which kind was showing. That is why it never read like the
// audio and display panels — those are each ONE panel about ONE thing, and
// the shape of the file says so.
//
// It also navigated by a "nav registry": every row called navRegister(rank,
// index, item) on creation and navUnregister on destruction, and the panel
// sorted the registrations to recover the on-screen order. The reason given
// for it was real — `provider.wifiNetworks` is a QAbstractListModel from the
// compiled backend and cannot be subscripted from JavaScript, while
// Bluetooth's list is a plain array, so no single JS traversal covers both.
// The conclusion drawn from it was wrong. The two containers do not need one
// traversal; they need one CONTAINER, and QML already has it: a ListView
// takes either kind, keeps `currentIndex` for you, and hands the row back as
// `currentItem`. That is exactly what AudioPanel and DisplayPanel do, and it
// is what this file does. Measured in a throwaway before writing a line of
// it (qs -p on a probe against the live WifiController): the delegate's
// `required property string ssid` binds to the model role under
// ComponentBehavior: Bound, and `listView.currentItem.ssid` reads back the
// selected row's SSID from JavaScript. So the model that "cannot be
// subscripted" can still be pointed at, which is all navigation ever needed.
//
// WHY SELECTION IS RE-ANCHORED BY SSID
// ------------------------------------
// The same throwaway measured the thing that actually bites here.
// WifiNetworkModel::setNetworks calls beginResetModel/endResetModel, so every
// rescan destroys and rebuilds every delegate — and the order changes with
// it. In one four-second probe TDV-OGRENCI-KAT-2B moved from index 1 to
// index 3 as signal strengths were re-read. A cursor that is only an integer
// would silently walk onto a different network between the moment you look at
// it and the moment you press Enter, on a panel whose Enter joins a network.
// So the panel remembers the SSID as well as the index, and a delegate that
// finds itself carrying the remembered SSID at a different index says so.
// That is three lines in the delegate, not a registry: nothing is enrolled,
// nothing is unenrolled, and there is no second ordering to disagree with the
// first.
//
// KEYMAP
// ------
//   j / k · ↓ / ↑   move the cursor          g / G   top / bottom
//   Return          join · or disconnect, if the cursor is on the current one
//   d               disconnect the current network
//   r               rescan          t   Wi-Fi radio on / off
//   Escape / q      close           (Escape cancels the password prompt first)
//
FocusScope {
    id: root

    signal closeRequested

    // The control centre, used as the data provider — the same object the old
    // panel was handed. Everything about NetworkManager lives behind it in the
    // compiled backend; this file is the keyboard and the pixels, the same
    // split DisplayPanel keeps against display-ctl.py.
    property var provider: null

    property bool showCondition: false
    property string textFontFamily: ""
    property string heroFontFamily: ""
    property string iconFontFamily: ""

    // ---- COLOUR FOLLOWS THE THEME ----
    //
    // panelFill is IslandTheme.shellFill, passed down from
    // DynamicIslandWindow: the theme background darkened toward black with 8%
    // of the accent mixed in — the capsule's own material, which re-tints on
    // every theme-apply. The repeat complaint it answers is a panel painted a
    // FIXED near-black that ignores theme_mode entirely.
    //
    // drawBackground is false in the island, because the capsule the panel
    // fills is ALREADY painted in exactly this colour, and a second rounded
    // fill inside it at a smaller radius shows up as four pale corner wedges
    // where the smaller radius cuts inside the larger one. The fill stays in
    // the file so the panel is instantiable on its own — and so the colour it
    // would use is stated here rather than assumed.
    property color panelFill: IslandTheme.surface
    property color accentColor: IslandTheme.accent
    property bool drawBackground: false

    property string statusText: "Ready"
    property string statusLevel: "idle"          // idle | busy | ok | error
    // True only while a join or a disconnect this panel started is in flight.
    // It is what stops the list's own "8 networks" from wiping "joining X…"
    // the moment a rescan lands underneath it — the same guard AudioPanel
    // puts on its post-query status line.
    property bool busy: false
    // True while statusText is the panel's own row-count summary rather than
    // a message about something that happened. Only a summary may be
    // rewritten by the list changing underneath it.
    property bool showingSummary: false

    // --- selection ---------------------------------------------------------
    property int selectedIndex: 0
    // See the header note. The index is where the cursor IS; the SSID is what
    // the cursor MEANS, and only the second one survives a rescan.
    property string selectedSsid: ""

    readonly property real horizontalPadding: Metrics.pad(18)
    readonly property real headerHeight: Metrics.pad(34)
    readonly property real rowHeight: Metrics.px(26)
    readonly property real rowSpacing: 2
    // Seven rather than the audio panel's six. A Wi-Fi list is longer than a
    // device list by nature — this machine sees ten networks from one desk —
    // and the extra row is one more SSID visible before it starts scrolling.
    readonly property int rowsVisible: 7
    readonly property real hintHeight: Metrics.pad(26)

    readonly property bool promptVisible:
        provider !== null && String(provider.wifiPendingPasswordSsid || "").length > 0
    readonly property real promptHeight: Metrics.px(66)

    // ---- THE PANEL SIZES ITSELF ----
    //
    // Same reasoning as the audio and display panels, which is why the
    // arithmetic is theirs unchanged: a flat height is a height drawn for the
    // worst case, and the worst case is not what is on screen. The old
    // connectivity layer was a flat Metrics.px(404) whichever way — with two
    // networks in range that is most of a panel of nothing, and with fifteen
    // it scrolls anyway.
    //
    // Floors at four rows so a panel with one network is still a panel and
    // not a strip; ceilings at rowsVisible so a long list scrolls instead of
    // growing past the screen; and takes the details column into account so a
    // one-network list cannot clip the description beside it.
    readonly property real listBodyHeight:
        Math.max(0, listView.count) * (root.rowHeight + root.rowSpacing) - root.rowSpacing
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

    // FORK: one choreography for every layer in the shell — the delay is what
    // keeps the content from being painted inside a capsule that is still the
    // wrong size for it. Motion.fade() and not Motion.spring(): opacity is
    // clamped 0..1 and an overshooting fade reads as a cut.
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
            root.selectedSsid = "";
            // A message left over from an earlier attempt is not news. The
            // provider's clearWifiMessages also clears the CONTROLLER's, which
            // is the half that outlives the panel.
            if (root.provider && root.provider.clearWifiMessages)
                root.provider.clearWifiMessages();
            root.busy = false;
            // ---- WHY THIS TEXT IS NOT CONDITIONAL ----
            //
            // It was, and the first live open showed the cost: the right-hand
            // slot read "Wi-Fi is off" in amber while the header beside it
            // read "· TDV-OGRENCI-ORTAK" and the list under it showed five
            // networks. The theory chased first was a stale error message left
            // in the controller, and clearing those changed nothing — because
            // the string was this panel's OWN, latched from
            // `provider.wifiEnabled` at the instant of opening. WifiController
            // is a lazily constructed singleton: the log has
            // "[Wifi] WifiController constructor called" AFTER the panel's
            // first activeFocus, so at open the radio state is not merely
            // stale, it does not exist yet and reads false.
            //
            // The lesson generalises past this line: a panel must not LATCH a
            // fact it can BIND. The status here now says only what the panel
            // itself is doing, and the list count clears it when the answer
            // arrives.
            root.setStatus("reading networks…", "busy");
            root.rescan();
            pollTimer.start();
            forceActiveFocus();
        } else {
            pollTimer.stop();
            // A password half-typed into a panel that is closing must not be
            // waiting for you the next time it opens — that is a prompt
            // pointing at a network you may no longer be near.
            if (root.provider && root.provider.clearWifiPrompt)
                root.provider.clearWifiPrompt();
        }
    }

    // Called by the host from the Loader's onLoaded. It cannot be left to
    // onShowConditionChanged alone: PanelLoader builds the item with
    // showCondition ALREADY true, so that handler never fires on the open
    // that matters. Both paths are kept because both are real — the host
    // toggles the flag on a live item when the island returns from overview.
    function grabKeyboardFocus() {
        root.forceActiveFocus();
    }


    function setStatus(text, level) {
        root.statusText = text;
        root.statusLevel = level || "idle";
        root.showingSummary = false;
    }

    // The idle line: how many networks there are. Marked as a SUMMARY so the
    // list can keep it honest as networks come and go — see onCountChanged.
    function setSummary() {
        root.statusText = listView.count + (listView.count === 1
                                            ? " network" : " networks");
        root.statusLevel = "idle";
        root.showingSummary = true;
    }

    // Everything this panel starts goes through here, so there is exactly one
    // place that can leave `busy` stuck on. NetworkManager can take a long
    // time to fail a join and can also fail it without saying anything the
    // provider surfaces, so the flag is on a deadline as well as on an
    // outcome: an association that has not resolved in twenty seconds is one
    // the panel should stop claiming to be waiting for.
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
        interval: 20000
        repeat: false
        onTriggered: root.endBusy("no answer from NetworkManager", "error")
    }

    // The outcome, from the two facts the provider publishes: which network
    // is current, and whether it has an error to report.
    Connections {
        target: root.provider
        ignoreUnknownSignals: true

        function onWifiCurrentSsidChanged() {
            if (!root.busy)
                return;
            const ssid = String(root.provider.wifiCurrentSsid || "");
            root.endBusy(ssid.length > 0 ? "connected to " + ssid : "disconnected", "ok");
        }

        function onWifiErrorChanged() {
            if (root.busy && String(root.provider.wifiError || "").length > 0)
                root.endBusy(undefined);
        }
    }

    // --- backend -----------------------------------------------------------
    Timer {
        id: pollTimer
        // Networks come and go without telling anyone. nmcli's own list is
        // already event-driven behind the controller, so this is a rescan
        // request rather than a re-read: eight seconds, because a rescan is
        // seconds of radio time and a list that reshuffles under the cursor
        // every three is worse than one that is ten seconds stale. Nothing
        // polls while the panel is closed.
        interval: 8000
        repeat: true
        onTriggered: root.rescan()
    }

    function rescan() {
        if (!root.provider)
            return;
        if (!root.provider.wifiEnabled)
            return;
        root.provider.requestWifiListRefresh(true);
    }

    // --- navigation --------------------------------------------------------
    // Wraps, for the reason DisplayPanel spells out: these lists are short
    // enough that a cursor stopping dead at the last row reads as a dead key,
    // and g / G still reach the ends.
    function move(step) {
        const count = listView.count;
        if (count === 0)
            return;
        root.setCursor(((root.selectedIndex + step) % count + count) % count);
    }

    function jump(where) {
        const count = listView.count;
        if (count === 0)
            return;
        root.setCursor(where === "top" ? 0 : count - 1);
    }

    function setCursor(index) {
        root.selectedIndex = Math.max(0, index);
        listView.positionViewAtIndex(root.selectedIndex, ListView.Contain);
        // Remember what the cursor is pointing AT, not only where it is. The
        // delegate re-anchors off this after a model reset.
        if (listView.currentItem)
            root.selectedSsid = String(listView.currentItem.ssid || "");
    }

    // --- actions -----------------------------------------------------------
    //
    // One activation path for the pointer and the keyboard, because when
    // those are two copies the keyboard one is the copy that quietly stops
    // matching. The row itself calls this.
    function activateRow(item) {
        if (!item || !root.provider)
            return;
        if (!(root.provider.wifiSupported && root.provider.wifiAvailable)) {
            root.setStatus(String(root.provider.wifiAvailabilityMessage
                                  || "no Wi-Fi device"), "error");
            return;
        }
        if (!root.provider.wifiEnabled) {
            root.setStatus("turn Wi-Fi on first — t", "idle");
            return;
        }
        if (root.provider.wifiBusy) {
            root.setStatus("busy…", "busy");
            return;
        }
        // Enter on the network you are already on DISCONNECTS. The old panel
        // hid the connected network from the list entirely and put it in a
        // banner above, which meant the one row you always want to act on was
        // the one row the cursor could not reach.
        if (item.connected) {
            root.beginBusy("disconnecting from " + item.ssid + "…");
            root.provider.disconnectWifi();
            return;
        }
        root.beginBusy("joining " + item.ssid + "…");
        // connectWifiNetwork decides for itself whether a password is needed:
        // a saved connection or an open network connects immediately, and a
        // secure one it has never seen sets wifiPendingPasswordSsid, which is
        // what raises the prompt below. That decision stays in the provider —
        // it is the half that knows what is in NetworkManager's keyring.
        root.provider.connectWifiNetwork({
            ssid: item.ssid,
            type: item.type,
            secure: item.secure,
            savedConnection: item.savedConnection,
            connected: item.connected
        });
    }

    function activate() {
        root.activateRow(listView.currentItem);
    }

    function disconnectCurrent() {
        if (!root.provider)
            return;
        const ssid = String(root.provider.wifiCurrentSsid || "");
        if (ssid.length === 0) {
            root.setStatus("not connected to anything", "idle");
            return;
        }
        root.beginBusy("disconnecting from " + ssid + "…");
        root.provider.disconnectWifi();
    }

    function toggleRadio() {
        if (!root.provider)
            return;
        const turningOn = !root.provider.wifiEnabled;
        root.provider.toggleWifiEnabled();
        // Not beginBusy: the radio coming up is not an association, and
        // nothing publishes a "the radio finished" fact to end it on. The
        // list filling in is the answer, and that clears an unguarded busy
        // status on its own.
        root.setStatus(turningOn ? "turning Wi-Fi on…" : "turning Wi-Fi off…", "busy");
    }

    // --- keys --------------------------------------------------------------
    //
    // The prompt takes every key while it is up — a WPA passphrase containing
    // a j or a k must not move the selection — and it does so by holding the
    // focus rather than by a flag here: a FocusScope's Keys handler only sees
    // what its focused child did not take. Escape inside the field cancels
    // the prompt; see wifiPasswordField.
    Keys.onPressed: function (event) {
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
        case Qt.Key_Return:
        case Qt.Key_Enter:
            root.activate();
            break;
        case Qt.Key_D:
            root.disconnectCurrent();
            break;
        case Qt.Key_R:
            root.setStatus("rescanning…", "busy");
            root.rescan();
            break;
        case Qt.Key_T:
            root.toggleRadio();
            break;
        default:
            return;
        }
        event.accepted = true;
    }

    // The prompt appears because the PROVIDER decided a password is needed,
    // which can happen a round-trip after Enter. Focus has to follow it, and
    // it has to come back here when it goes away, or the panel is left with a
    // keyboard grab and nothing focused to use it.
    onPromptVisibleChanged: {
        if (promptVisible)
            promptFocusTimer.restart();
        else if (showCondition)
            root.forceActiveFocus();
    }

    Timer {
        id: promptFocusTimer
        interval: 0
        repeat: false
        onTriggered: wifiPasswordField.forceActiveFocus()
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
    // ---- THE HEADER REGISTER ----
    //
    // Letterspaced uppercase at a much smaller size than a title would be,
    // then a "· status" clause that carries the accent only when something is
    // live. It reads as a label on an instrument rather than as a window
    // title. No kanji: there was a 波 here and it was removed on request, and
    // the letterspacing is the part of that treatment doing the work anyway.
    Text {
        id: header
        x: root.horizontalPadding
        y: Metrics.pad(12)
        text: "WI-FI"
        color: IslandTheme.textMuted
        font.family: root.textFontFamily
        font.pixelSize: Metrics.font(10)
        font.weight: Font.DemiBold
        font.capitalization: Font.AllUppercase
        font.letterSpacing: 1.6
    }

    Text {
        id: headerStatus
        anchors.left: header.right
        anchors.leftMargin: Metrics.pad(8)
        y: Metrics.pad(12)
        text: {
            if (!root.provider)
                return "";
            if (!root.provider.wifiSupported || !root.provider.wifiAvailable)
                return "· unavailable";
            if (!root.provider.wifiEnabled)
                return "· off";
            const ssid = String(root.provider.wifiCurrentSsid || "");
            return ssid.length > 0 ? "· " + ssid : "· not connected";
        }
        // Accent only when there is something live to point at. A status
        // clause that is always accented has stopped being a status.
        color: {
            if (!root.provider)
                return IslandTheme.textMuted;
            const live = root.provider.wifiEnabled
                && String(root.provider.wifiCurrentSsid || "").length > 0;
            return live ? root.accentColor : IslandTheme.textMuted;
        }
        font.family: root.textFontFamily
        font.pixelSize: Metrics.font(10)
        font.weight: Font.Medium
        elide: Text.ElideRight
        width: Math.min(implicitWidth, root.width * 0.35)
    }

    // The right-hand slot, exactly where the audio and display panels put it:
    // what the panel is doing right now, in the colour of how it went.
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
            if (root.provider) {
                if (String(root.provider.wifiError || "").length > 0)
                    return String(root.provider.wifiError);
                if (root.provider.wifiListRunning)
                    return "searching networks…";
            }
            return root.statusText;
        }
    }

    ListView {
        id: listView
        // FORK: P1-3. One shared indicator; see qml/common/IslandScrollBar.qml
        // for why `active` does not gate on pointer interaction alone.
        ScrollBar.vertical: IslandScrollBar { view: listView }
        x: root.horizontalPadding
        y: root.headerHeight + Metrics.pad(4)
        width: parent.width * 0.56 - root.horizontalPadding
        // Built from the same numbers preferredHeight is, so the list and the
        // shape around it cannot disagree about how tall a row is.
        height: root.bodyHeight
        clip: true
        // The compiled model, straight in. See the header note: this is the
        // container that made the old nav registry unnecessary.
        model: root.provider ? root.provider.wifiNetworks : null
        currentIndex: root.selectedIndex
        boundsBehavior: Flickable.StopAtBounds
        spacing: root.rowSpacing

        // The answer arriving is what clears "reading networks…", and every
        // later answer keeps it current.
        //
        // The first version fired only while the status was still the open's
        // "reading networks…", and it was wrong in a way worth keeping: the
        // model is EMPTY for the first frames, so count changed to 0, the
        // summary latched "0 networks", and the seven networks that arrived a
        // second later found the status no longer busy and left it alone. The
        // panel sat there with a full list under a line saying there were
        // none — photographed, at 21:36. A summary is not an event; it is a
        // fact that has to keep being re-stated, so it is re-stated for as
        // long as it is what the line is showing.
        onCountChanged: {
            if (root.showingSummary || (root.statusLevel === "busy" && !root.busy))
                root.setSummary();
        }

        // Nothing here rather than an empty box: an empty list and a broken
        // panel look identical, and each of these has a different answer to
        // "what do I do about it".
        Text {
            anchors.centerIn: parent
            visible: listView.count === 0
            color: IslandTheme.textDisabled
            font.pixelSize: Metrics.font(11)
            font.family: root.textFontFamily
            text: {
                if (!root.provider)
                    return "no Wi-Fi backend";
                if (!root.provider.wifiSupported || !root.provider.wifiAvailable)
                    return String(root.provider.wifiAvailabilityMessage
                                  || "no Wi-Fi device is available");
                if (!root.provider.wifiEnabled)
                    return "Wi-Fi is off — t to turn it on";
                if (root.provider.wifiListRunning)
                    return "searching networks…";
                return "no networks in range — r to rescan";
            }
        }

        delegate: Rectangle {
            id: wifiRow

            required property int index
            required property string ssid
            required property string displayName
            required property string type
            required property int signal
            required property bool secure
            required property bool savedConnection
            required property bool connected

            width: listView.width
            height: root.rowHeight
            radius: Metrics.px(7)
            // Two facts, two colours, in priority order. The CONNECTED row is
            // accent-tinted because it is a fact about the system; the
            // keyboard cursor is neutral white because it is a fact about the
            // pointer. If the cursor used the accent too, moving it would
            // look like connecting.
            color: {
                if (wifiRow.connected)
                    return Qt.rgba(root.accentColor.r, root.accentColor.g,
                                   root.accentColor.b, 0.16);
                if (wifiRow.index === root.selectedIndex)
                    return IslandTheme.hairline;
                return "transparent";
            }

            // ---- RE-ANCHORING, the whole of it ----
            //
            // A rescan resets the model, which destroys every delegate and
            // rebuilds it in a new order (measured: index 1 to index 3 in one
            // four-second probe). If the row being built is the one the cursor
            // MEANS, it takes the cursor with it. Held on the panel and not on
            // the delegate, because delegate state does not survive the reset
            // that causes the problem in the first place.
            Component.onCompleted: {
                if (root.selectedSsid.length > 0
                        && wifiRow.ssid === root.selectedSsid
                        && wifiRow.index !== root.selectedIndex)
                    root.selectedIndex = wifiRow.index;
            }

            Text {
                id: rowLabel
                anchors.left: parent.left
                anchors.leftMargin: Metrics.pad(10)
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: rowMeta.left
                anchors.rightMargin: Metrics.pad(8)
                elide: Text.ElideRight
                color: wifiRow.connected ? root.accentColor : "white"
                font.pixelSize: Metrics.font(12)
                font.family: root.textFontFamily
                font.weight: wifiRow.connected ? Font.DemiBold : Font.Normal
                text: (wifiRow.connected ? "● " : "")
                    + (wifiRow.displayName.length > 0 ? wifiRow.displayName : wifiRow.ssid)
            }

            Row {
                id: rowMeta
                anchors.right: parent.right
                anchors.rightMargin: Metrics.pad(10)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Metrics.px(6)

                // A lock, for security. The word "Secure network" used to sit
                // on a second line under every SSID, restating what one glyph
                // says and halving how many networks fit.
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: ""
                    visible: wifiRow.secure
                    color: wifiRow.savedConnection ? IslandTheme.success : IslandTheme.textMuted
                    font.pixelSize: Metrics.font(10)
                    font.family: root.iconFontFamily
                }

                // The bar is the audio panel's level bar, deliberately: this
                // shell has one way of drawing "a fraction of a thing" and a
                // second one would be a second vocabulary for the same idea.
                // Red under 30% because that is where a join starts failing
                // rather than merely being slow.
                Item {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Metrics.px(34)
                    height: Metrics.px(6)

                    Rectangle {
                        anchors.fill: parent
                        radius: height / 2
                        color: IslandTheme.trackSubtle
                    }
                    Rectangle {
                        height: parent.height
                        radius: height / 2
                        width: parent.width * Math.max(0, Math.min(1, wifiRow.signal / 100))
                        color: wifiRow.signal < 30 ? IslandTheme.danger
                             : (wifiRow.connected ? root.accentColor : IslandTheme.success)
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: Text.AlignRight
                    width: Metrics.px(30)
                    text: wifiRow.signal + "%"
                    color: IslandTheme.textMuted
                    font.pixelSize: Metrics.font(10)
                    font.family: root.textFontFamily
                }
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                onEntered: root.setCursor(wifiRow.index)
                onClicked: {
                    root.setCursor(wifiRow.index);
                    root.activateRow(wifiRow);
                }
            }
        }
    }

    // Details for whatever the cursor is on. The list alone cannot say what a
    // row IS — whether joining it will ask for a password, whether this
    // machine has been on it before — and those are exactly the fields with
    // no cue anywhere else on the system.
    //
    // It reads listView.currentItem rather than an array, because the model
    // is a QAbstractListModel and currentItem is the only handle JavaScript
    // gets on a row of one. ListView keeps the current delegate alive for
    // precisely this.
    Column {
        id: detailsColumn
        x: parent.width * 0.58
        y: root.headerHeight + Metrics.pad(6)
        width: parent.width * 0.42 - root.horizontalPadding
        spacing: Metrics.px(3)

        Repeater {
            model: {
                const item = listView.currentItem;
                if (!item)
                    return [["", "nothing selected"]];
                const secure = item.secure;
                const saved = item.savedConnection;
                return [
                    ["network", item.ssid],
                    ["security", secure ? (item.type || "secure") : "open"],
                    ["signal", item.signal + "%"],
                    ["saved", saved ? "yes — joins without a password" : "no"],
                    ["state", item.connected ? "connected"
                        : (secure && !saved ? "Enter asks for a password" : "Enter joins")],
                ];
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

    // ---- THE PASSWORD PROMPT ----
    //
    // Below the body rather than over it, and counted in preferredHeight, so
    // raising it GROWS the capsule instead of covering the row that says
    // which network you are being asked about.
    Rectangle {
        id: passwordPrompt
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
            anchors.top: parent.top
            anchors.topMargin: Metrics.pad(8)
            text: "password for " + (root.provider ? root.provider.wifiPendingPasswordSsid : "")
            color: IslandTheme.textPrimary
            font.pixelSize: Metrics.font(11)
            font.family: root.textFontFamily
            elide: Text.ElideRight
            width: parent.width - Metrics.pad(24)
        }

        Rectangle {
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
            border.color: wifiPasswordField.activeFocus
                ? root.accentColor
                : Qt.rgba(1, 1, 1, 0.12)

            TextInput {
                id: wifiPasswordField
                anchors.fill: parent
                anchors.leftMargin: Metrics.pad(10)
                anchors.rightMargin: Metrics.pad(10)
                verticalAlignment: TextInput.AlignVCenter
                color: "white"
                font.pixelSize: Metrics.font(11)
                font.family: root.textFontFamily
                echoMode: TextInput.Password
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
                Keys.onEnterPressed: {
                    if (root.provider)
                        root.provider.submitWifiPassword();
                }
                // Escape backs out of the PROMPT, not out of the panel. A
                // prompt you can only leave by closing the whole surface is
                // the reason the old one had a Cancel button to reach for
                // with the mouse.
                Keys.onEscapePressed: function (event) {
                    if (root.provider)
                        root.provider.clearWifiPrompt();
                    root.setStatus("cancelled", "idle");
                    root.forceActiveFocus();
                    event.accepted = true;
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: wifiPasswordField.text.length === 0
                    text: "Enter to join · Escape to cancel"
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
            ? "type the password · Enter join · Escape cancel"
            : "j/k move · Enter join · d disconnect · r rescan · t radio · q close"
    }
}
