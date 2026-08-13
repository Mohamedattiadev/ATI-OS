import QtQuick
import QtQuick.Shapes
import Quickshell.Bluetooth
import Quickshell.Io
import IslandBackend

// FORK: one shared scale factor for every island surface.
import "../common/Metrics.js" as Metrics
// FORK: the shared motion system — one spring for geometry, one
// critically damped curve for opacity. See qml/common/Motion.js.
import "../common/Motion.js" as Motion
import "../common"

Item {
    id: controlCenter

    signal connectivityPanelRequested(string kind, bool open)
    // FORK: Escape / q, which this layer was the last big panel not to have.
    // Every other surface in the shell — the pickers, the display and audio
    // panels, the calendar, the power menu, the settings sheet, both
    // connectivity lists — closes on Escape or q, and the control centre
    // could only be dismissed by clicking the capsule again. See the
    // keyboard grab note in DynamicIslandWindow.qml: this layer was never in
    // the keyboardFocus list either, so there was no keystroke to handle.
    signal closeRequested()
    signal focusModeChanged(bool enabled)
    signal nightLightModeChanged(bool enabled)
    signal requestNotification(string appName, string summary, string body)

    readonly property var userConfig: UserConfig

    property bool showCondition: false
    property string iconFontFamily: userConfig.iconFontFamily
    property string textFontFamily: userConfig.textFontFamily
    property string heroFontFamily: userConfig.heroFontFamily

    // FORK: the live palette accent, for the filament faders. Passed down
    // from DynamicIslandWindow's IslandTheme rather than read here — this
    // file has no theme object of its own, and every colour in it comes
    // from the packaged StyleTokens, which has no accent slot that follows
    // theme-apply.
    property color accentColor: IslandTheme.accent
    // ... rest of properties ...

    scale: showCondition ? 1.0 : 0.12
    transformOrigin: Item.Top

    // FORK: the last literal 400 in the shell that was really MORPH_MS.
    //
    // The curve was converted to the spring but the duration was left as a
    // bare number, so Motion.SCALE — the one knob the whole motion system is
    // supposed to hang off — would have moved every other geometry animation
    // in the shell and left this one where it was. That is not a taste
    // difference the comments elsewhere defend; it is the number simply not
    // having been noticed. Same 400 today, sourced.
    //
    // Deliberately morphDuration() and not morphDurationFor(). This is a
    // SCALE, 0.12 to 1, so it has no pixel distance to hand the interpolator,
    // and the capsule it lives inside is a 156 -> 387 px morph on this screen
    // (measured with grim) which morphDurationFor puts at 451 ms. The panel
    // arriving marginally before the shape settles is the choreography
    // Motion.js describes — content lands INSIDE a shape that is already
    // most of the way there — so the shorter of the two is the right one.
    Behavior on scale {
        NumberAnimation {
            duration: Motion.morphDuration()
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Motion.spring()   // FORK: was Easing.OutQuint
        }
    }
    property string currentTime: "00:00"
    property string currentDateLabel: ""
    property int batteryCapacity: 0
    property bool isCharging: false
    property real volumeLevel: -1
    property real brightnessLevel: -1
    property int sliderIntroDelay: 400
    property int currentWorkspace: 1
    property string currentTrack: ""
    property string currentArtist: ""

    property real localVolume: 0.5
    property real localBrightness: 0.5
    property real displayedVolume: 0.5
    property real displayedBrightness: 0.5
    property real pendingVolume: 0.5
    property real pendingBrightness: 0.5
    property real lastAppliedVolume: -1
    property real lastAppliedBrightness: -1
    property bool brightnessSetterRunning: false
    property bool volumeSetterRunning: false
    property bool sliderIntroPending: false
    property bool wifiPanelOpen: false
    property bool bluetoothPanelOpen: false
    // ---- FORK: THIS LAYER IS NOW A DATA PROVIDER WHEN IT IS INVISIBLE ----
    //
    // The Wi-Fi and Bluetooth lists are their own island states now (see
    // qml/connectivity/ConnectivityPanelLayer.qml), and opening one CLOSES
    // the control centre — the capsule is one shape and it can only be one
    // panel at a time. But the models both lists read still live here:
    // wifiController, bluetoothAdapter, the pairing agent, every action
    // method the rows call. So this layer stays mounted, invisible, purely
    // as the provider.
    //
    // That breaks four guards that were written when "visible" and "in use"
    // were the same thing. requestWifiStateRefresh and requestWifiListRefresh
    // both open with `if (!showCondition) return;`, which was correct while
    // the only way to see a network list was through a visible control
    // centre, and which under the new arrangement means the standalone Wi-Fi
    // popup opens onto whatever nmcli last said — with no rescan, ever.
    //
    // connectivityHostActive is set by the host while a standalone popup is
    // up. connectivityDataActive is the predicate those guards should have
    // been asking about all along: not "is this panel on screen" but "is
    // anything looking at this data".
    property bool connectivityHostActive: false
    readonly property bool connectivityDataActive: showCondition || connectivityHostActive
    property bool batteryDrawerOpen: false
    property bool batteryDrawerDragging: false
    property real batteryDrawerProgress: 0
    property bool batteryDrawerSettling: false
    readonly property bool batteryDrawerMoving: batteryDrawerDragging
        || batteryDrawerSettling
        || batteryDrawerProgressAnimation.running
    property bool batteryModeBusy: false
    property bool batteryModeStateRunning: false
    property bool batteryModeSetterRunning: false
    property bool batteryModeSliderDragging: false
    property bool batteryTlpAvailable: false
    property bool batteryTlpChecked: false
    property int batteryModeIndex: 1
    property int batteryModeAppliedIndex: 1
    property int batteryModePendingIndex: 1
    property real batteryModeDragOffset: 0
    property string batteryModeInfoMessage: ""
    property string batteryModeError: ""
    property string batteryModeLastCommandOutput: ""
    property int batteryModeRefreshPollsRemaining: 0
    property bool nightLightEnabled: false
    property bool nightLightBusy: false
    property int nightLightTemperature: 4500
    readonly property bool hyprlandNightLight: CompositorBackend.compositor === "hyprland"
    property bool focusEnabled: false
    // Kept as a property and permanently false. It gated the row while a
    // subprocess was in flight; there is no subprocess now, so there is no
    // in-flight state to gate. Left in place rather than threaded out of
    // three bindings, because the day this row grows an async step again is
    // the day it will be wanted back — and a property that is always false
    // costs nothing, while a half-removed one costs a rebinding.
    property bool focusBusy: false
    // FORK: three-state, and that is the entire point of the rewrite below.
    // `focusEnabled` alone could only say on or off, so "the tool is not
    // there" had to be encoded as one of them — and it was encoded as OFF,
    // which is indistinguishable from a correct reading of an idle daemon.
    // Starts TRUE because the probe has not run yet and a control that
    // flickers disabled on every open would be its own bug; the first
    // reading of the daemon settles it, and it settles it within one frame
    // of the panel opening.
    property bool focusAvailable: true

    property string wifiLocalInfoMessage: ""
    property string wifiLocalError: ""
    property string wifiPendingPasswordSsid: ""
    property string wifiPendingPasswordValue: ""

    property string bluetoothInfoMessage: ""
    property string bluetoothError: ""
    property string bluetoothPairAndConnectPath: ""
    property string bluetoothPendingSecretValue: ""
    readonly property var wifiController: WifiController
    readonly property var bluetoothPairingAgent: BluetoothPairingAgent
    readonly property var wifiNetworks: wifiController ? wifiController.networks : null

    readonly property real sliderKnobSize: 24
    readonly property color panelColor: IslandTheme.surface
    readonly property color moduleColor: IslandTheme.surfaceRaised
    readonly property color moduleHover: IslandTheme.surfaceRaisedHover
    readonly property color trackColor: IslandTheme.trackEmpty
    readonly property color textPrimary: IslandTheme.textPrimary
    readonly property color textSecondary: IslandTheme.textSecondary
    readonly property color cardAccent: IslandTheme.accent
    readonly property color cardAccentPressed: IslandTheme.accentPressed
    readonly property color cardFillActive: IslandTheme.surfaceRaisedActive
    readonly property color cardFillHover: IslandTheme.surfaceRaisedHover
    readonly property color buttonFill: IslandTheme.inverseSurface
    readonly property color buttonFillHover: IslandTheme.inverseSurfaceHover
    readonly property color buttonFillPressed: IslandTheme.inverseSurfacePressed
    readonly property string wifiGlyph: ""
    readonly property string bluetoothGlyph: ""
    readonly property string chargingIconGlyph: "\uf0e7"
    readonly property string brightnessIconGlyph: "\u{F00DF}"
    readonly property string volumeIconGlyph: "\u{F057E}"
    readonly property string nightLightGlyph: "\uf186"
    readonly property var batteryModeGlyphs: ["", "", ""]
    readonly property real batteryDrawerHandleHeight: 20
    readonly property real batteryDrawerContentGap: 8
    readonly property real batteryModeCardHeight: 80
    readonly property real roundToggleButtonSize: 58
    readonly property real roundToggleButtonGap: 18
    readonly property real controlCenterExtraHeight: 12 + batteryDrawerHandleHeight
        + batteryDrawerProgress * (batteryDrawerContentGap + batteryModeCardHeight)
    readonly property real controlCenterMaximumExtraHeight: 12 + batteryDrawerHandleHeight
        + batteryDrawerContentGap + batteryModeCardHeight
    readonly property bool bluetoothAvailable: !!bluetoothAdapter
    readonly property var bluetoothAdapter: Bluetooth.defaultAdapter
    readonly property var bluetoothDeviceValues: bluetoothAdapter ? bluetoothAdapter.devices.values : []
    readonly property bool wifiSupported: wifiController ? wifiController.supported : false
    readonly property bool wifiReadOnly: wifiController ? wifiController.readOnly : true
    readonly property bool wifiAvailable: wifiController ? wifiController.available : false
    readonly property bool wifiEnabled: wifiController ? wifiController.enabled : false
    readonly property bool wifiBusy: wifiController ? wifiController.busy : false
    readonly property bool wifiListRunning: wifiController ? wifiController.scanning : false
    readonly property string wifiCurrentSsid: wifiController ? wifiController.currentSsid : ""
    readonly property string wifiInfoMessage: wifiLocalInfoMessage.length > 0
        ? wifiLocalInfoMessage
        : (wifiController ? wifiController.infoMessage : "")
    readonly property string wifiError: wifiLocalError.length > 0
        ? wifiLocalError
        : (wifiController ? wifiController.errorMessage : "")
    readonly property string wifiUnsupportedReason: wifiController ? wifiController.unsupportedReason : ""
    readonly property string wifiAvailabilityMessage: {
        if (wifiUnsupportedReason.length > 0) return wifiUnsupportedReason;
        if (wifiSupported && !wifiAvailable) return "No Wi-Fi device is available.";
        return "";
    }
    readonly property bool bluetoothEnabled: bluetoothAdapter ? bluetoothAdapter.enabled : false
    readonly property bool bluetoothBusy: bluetoothAdapter
        ? bluetoothAdapter.state === BluetoothAdapterState.Enabling
            || bluetoothAdapter.state === BluetoothAdapterState.Disabling
        : false
    readonly property bool bluetoothPairingActive: bluetoothPairingAgent ? bluetoothPairingAgent.requestActive : false
    readonly property bool bluetoothPairingRequiresInput: bluetoothPairingAgent ? bluetoothPairingAgent.requestRequiresInput : false
    readonly property bool bluetoothPairingNumericInput: bluetoothPairingAgent ? bluetoothPairingAgent.requestNumericInput : false
    readonly property bool bluetoothPairingRequiresConfirmation: bluetoothPairingAgent ? bluetoothPairingAgent.requestRequiresConfirmation : false
    readonly property string bluetoothPairingTitle: bluetoothPairingAgent ? bluetoothPairingAgent.promptTitle : ""
    readonly property string bluetoothPairingMessage: bluetoothPairingAgent ? bluetoothPairingAgent.promptMessage : ""
    readonly property string bluetoothPairingDisplayedCode: bluetoothPairingAgent ? bluetoothPairingAgent.displayedCode : ""
    readonly property bool hasConnectivityPrompt: wifiPendingPasswordSsid.length > 0 || bluetoothPairingActive
    readonly property bool anyConnectivityPanelOpen: wifiPanelOpen || bluetoothPanelOpen
    readonly property string wifiStatusText: wifiController ? wifiController.statusText : "Unavailable"
    readonly property string bluetoothStatusText: buildBluetoothStatusText()
    readonly property string bluetoothAvailabilityMessage: bluetoothAvailable ? "" : "No Bluetooth adapter is available."
    readonly property string batteryModeStatusText: buildBatteryModeStatusText()
    readonly property bool tlpControlsEnabled: trimString(userConfig.tlpPermissionMode) !== "skip"

    function clamp01(value) {
        return Math.max(0, Math.min(1, value));
    }

    function trimString(value) {
        if (value === undefined || value === null) return "";
        return String(value).trim();
    }

    function batteryModeLabel(index) {
        if (index <= 0) return "Power Saver";
        if (index >= 2) return "Performance";
        return "Balanced";
    }

    function batteryModeCommand(index) {
        if (index <= 0) return "power-saver";
        if (index >= 2) return "performance";
        return "balanced";
    }

    function batteryModeIndexForCommand(command) {
        const normalized = trimString(command).toLowerCase();
        if (normalized === "power-saver" || normalized === "bat") return 0;
        if (normalized === "performance" || normalized === "ac") return 2;
        return 1;
    }

    function setBatteryModeVisualIndex(index, animate) {
        const nextIndex = Math.max(0, Math.min(2, index));
        batteryModeIndex = nextIndex;
    }

    function setBatteryDrawerOpen(open) {
        const nextOpen = !!open;
        batteryDrawerOpen = nextOpen;
        batteryDrawerSettling = true;
        batteryDrawerProgress = nextOpen ? 1 : 0;
        batteryDrawerSettleTimer.restart();
        if (nextOpen && tlpControlsEnabled && !batteryTlpChecked)
            refreshBatteryModeState();
    }

    function toggleBatteryDrawer() {
        setBatteryDrawerOpen(!batteryDrawerOpen);
    }

    function refreshBatteryModeState() {
        if (batteryModeStateRunning)
            return;

        batteryModeStateRunning = true;
        SystemServices.requestTlpState();
    }

    function applyBatteryModeState(available, profile, output, errorString) {
        batteryModeStateRunning = false;
        batteryTlpChecked = true;
        batteryTlpAvailable = !!available;

        if (!batteryTlpAvailable) {
            batteryModeBusy = false;
            batteryModeError = trimString(errorString).length > 0 ? errorString : "TLP is not installed.";
            setBatteryModeVisualIndex(batteryModeAppliedIndex, true);
            return;
        }

        if (batteryModeError === "TLP is not installed.")
            batteryModeError = "";

        let resolvedProfile = trimString(profile);
        if (resolvedProfile.length === 0) {
            const profileMatch = String(output || "").match(/TLP profile\s*=\s*([a-z-]+)/i);
            if (profileMatch)
                resolvedProfile = profileMatch[1];
        }

        if (resolvedProfile.length > 0) {
            const nextIndex = batteryModeIndexForCommand(resolvedProfile);
            batteryModeAppliedIndex = nextIndex;
            setBatteryModeVisualIndex(nextIndex, true);

            if (batteryModeRefreshPollsRemaining > 0 && nextIndex === batteryModePendingIndex) {
                batteryModeRefreshPollsRemaining = 0;
                batteryModeRefreshTimer.stop();
                batteryModeError = "";
                batteryModeInfoMessage = batteryModeLabel(nextIndex) + " active.";
            }
        }
    }

    function buildBatteryModeStatusText() {
        if (batteryModeBusy) return "Applying " + batteryModeLabel(batteryModePendingIndex);
        if (trimString(userConfig.tlpPermissionMode) === "skip") return "TLP disabled";
        if (!batteryTlpChecked) return "Checking TLP";
        if (!batteryTlpAvailable) return "TLP is not installed";
        return batteryModeLabel(batteryModeIndex);
    }

    function rollbackBatteryMode(message) {
        batteryModeBusy = false;
        batteryModeError = message;
        batteryModeInfoMessage = "";
        batteryModeDragOffset = 0;
        setBatteryModeVisualIndex(batteryModeAppliedIndex, true);
    }

    function classifyBatteryModeFailure(exitCode) {
        const details = trimString(batteryModeLastCommandOutput).toLowerCase();

        if (details.indexOf("sorry, try again") >= 0 || details.indexOf("incorrect password attempt") >= 0)
            return "The configured sudo password did not work.";
        if (details.indexOf("pkexec") >= 0 && details.indexOf("not installed") >= 0)
            return "Install pkexec or set tlpSudoPassword in userconfig.json.";
        if (details.indexOf("sudo is not installed") >= 0)
            return "sudo is not installed.";
        if (details.indexOf("sudo:") >= 0 && details.indexOf("password") >= 0) {
            if (trimString(userConfig.tlpPermissionMode) === "ask")
                return "Install pkexec or set tlpSudoPassword in userconfig.json.";
            return "sudo needs a password; set tlpSudoPassword in userconfig.json.";
        }
        if (details.indexOf("sudo:") >= 0 && details.indexOf("no new privileges") >= 0)
            return "sudo is blocked by the current process security flags.";
        if (details.indexOf("sudo:") >= 0 && details.indexOf("a terminal is required") >= 0)
            return "sudo needs a real terminal, but the panel could not open one.";
        if (details.indexOf("missing root privilege") >= 0)
            return "TLP needs admin permission.";
        if (details.indexOf("command not found") >= 0 || details.indexOf("not found") >= 0) {
            if (details.indexOf("tlp") >= 0)
                return "TLP is not installed.";
        }

        if (exitCode === 127)
            return "TLP is not installed.";
        if (exitCode === 126)
            return "Install pkexec or set tlpSudoPassword in userconfig.json.";
        return "TLP could not apply that mode.";
    }

    function queueBatteryModeStateRefresh(polls) {
        batteryModeRefreshPollsRemaining = Math.max(0, polls);
        if (batteryModeRefreshPollsRemaining > 0)
            batteryModeRefreshTimer.restart();
        else
            batteryModeRefreshTimer.stop();
    }

    function selectBatteryMode(index) {
        if (batteryModeBusy) {
            if (batteryModeSetterRunning)
                SystemServices.cancelTlpApply();
            batteryModeBusy = false;
            batteryModeSetterRunning = false;
        }

        queueBatteryModeStateRefresh(0);

        const nextIndex = Math.max(0, Math.min(2, index));

        if (trimString(userConfig.tlpPermissionMode) === "skip") {
            rollbackBatteryMode("TLP mode switching is disabled in userconfig.json.");
            return;
        }

        if (!batteryTlpChecked) {
            refreshBatteryModeState();
            rollbackBatteryMode("Checking TLP. Try again in a moment.");
            return;
        }

        if (!batteryTlpAvailable) {
            rollbackBatteryMode("TLP is not installed.");
            return;
        }

        if (nextIndex === batteryModeAppliedIndex) {
            batteryModeError = "";
            batteryModeInfoMessage = batteryModeLabel(nextIndex) + " active.";
            setBatteryModeVisualIndex(nextIndex, true);
            return;
        }

        batteryModePendingIndex = nextIndex;
        batteryModeBusy = true;
        batteryModeSetterRunning = true;
        batteryModeError = "";
        batteryModeInfoMessage = "Applying " + batteryModeLabel(nextIndex) + "...";
        setBatteryModeVisualIndex(nextIndex, true);
        batteryModeLastCommandOutput = "";
        const permissionMode = trimString(userConfig.tlpPermissionMode);
        const sudoPassword = permissionMode === "password"
            ? trimString(userConfig.tlpSudoPassword)
            : "";
        SystemServices.setTlpMode(batteryModeCommand(nextIndex), sudoPassword, permissionMode === "ask");
    }

    function finishBatteryModeApply(success, exitCode, output, errorString) {
        batteryModeSetterRunning = false;
        batteryModeBusy = false;
        batteryModeLastCommandOutput = trimString(output);
        if (batteryModeLastCommandOutput.length === 0)
            batteryModeLastCommandOutput = trimString(errorString);

        if (!success) {
            rollbackBatteryMode(classifyBatteryModeFailure(exitCode));
            return;
        }

        batteryModeAppliedIndex = batteryModePendingIndex;
        batteryModeError = "";
        batteryModeInfoMessage = batteryModeLabel(batteryModeAppliedIndex) + " active.";
        setBatteryModeVisualIndex(batteryModeAppliedIndex, true);
        refreshBatteryModeState();
    }

    function toggleNightLight() {
        if (nightLightBusy)
            return;

        nightLightBusy = true;
        if (nightLightEnabled) {
            nightLightDisableProcess.running = true;
        } else {
            nightLightEnableProcess.running = true;
        }
    }

    // One place that re-reads the daemon, because three callers want it —
    // opening the panel, and each of the two writes. Guarded against being
    // restarted while already running: Quickshell treats `running = true` on
    // a live Process as a no-op, but the guard makes the intent explicit and
    // means a slow read cannot be interleaved with a second one.
    // ---- SILENT IS THE ISLAND'S OWN STATE NOW, NOT DUNST'S ----
    //
    // This row used to shell out to `dunstctl is-paused` / `set-paused`,
    // and before that to `swaync-client`, which was not installed at all —
    // the write failure silently flipped the row to off, which is the bug
    // the dunstctl rewrite existed to fix.
    //
    // The dunstctl version was correct and is now pointing at nothing. The
    // island SERVES org.freedesktop.Notifications itself, and dunst is out
    // of autostart.conf, so `dunstctl is-paused` fails and the row goes
    // permanently "unavailable" — honest, and useless.
    //
    // So Silent stops asking a daemon and reads the thing that actually
    // decides: `shellRoot.focusEnabled`, which showNotificationAll already
    // checks before drawing anything. That is a strictly better position
    // than any of the three that came before it — there is no subprocess to
    // fail, no exit code to misread, and no second opinion to drift from.
    // `focusAvailable` is therefore always true: the island can always
    // answer a question about itself.
    //
    // The state still comes from the host rather than being written here,
    // for the same reason the dunstctl version re-read the daemon: one
    // owner, asked every time, so a write that did not land shows up as the
    // row not moving.
    property bool hostFocusEnabled: false

    function refreshFocusState() {
        controlCenter.focusAvailable = true;
        controlCenter.focusEnabled = controlCenter.hostFocusEnabled;
    }

    onHostFocusEnabledChanged: refreshFocusState()

    function toggleFocus() {
        if (focusBusy)
            return;

        // No busy window any more — there is no process to wait for. The
        // property is set on the shell root and comes straight back down
        // through hostFocusEnabled, within the same frame.
        controlCenter.focusModeChanged(!controlCenter.focusEnabled);
    }

    function clearWifiPrompt() {
        wifiPendingPasswordSsid = "";
        wifiPendingPasswordValue = "";
        wifiLocalInfoMessage = "";
        wifiLocalError = "";
    }

    function clearWifiMessages() {
        wifiLocalInfoMessage = "";
        wifiLocalError = "";
        if (wifiController)
            wifiController.clearMessages();
    }

    function clearBluetoothMessages() {
        bluetoothInfoMessage = "";
        bluetoothError = "";
    }

    function submitBluetoothPairingSecret() {
        if (!bluetoothPairingAgent || !bluetoothPairingRequiresInput)
            return;

        const secret = trimString(bluetoothPendingSecretValue);
        if (!secret) {
            bluetoothError = bluetoothPairingNumericInput
                ? "Enter the 6-digit passkey first."
                : "Enter the PIN first.";
            return;
        }

        if (bluetoothPairingNumericInput && !/^\d{1,6}$/.test(secret)) {
            bluetoothError = "Passkeys must be 1 to 6 digits.";
            return;
        }

        bluetoothError = "";
        bluetoothPairingAgent.submitSecret(secret);
        bluetoothPendingSecretValue = "";
    }

    function confirmBluetoothPairing() {
        if (!bluetoothPairingAgent)
            return;

        bluetoothError = "";
        bluetoothPairingAgent.confirmRequest();
    }

    function cancelBluetoothPairing() {
        if (!bluetoothPairingAgent)
            return;

        bluetoothPairingAgent.cancelRequest();
        bluetoothPendingSecretValue = "";
    }

    function isConnectivityPanelOpen(kind) {
        if (kind === "wifi") return wifiPanelOpen;
        if (kind === "bluetooth") return bluetoothPanelOpen;
        return false;
    }

    function setConnectivityPanelOpen(kind, open, emitSignal) {
        if (emitSignal === undefined)
            emitSignal = true;

        const nextOpen = !!open;
        let changed = false;

        if (kind === "wifi") {
            changed = wifiPanelOpen !== nextOpen;
            wifiPanelOpen = nextOpen;

            if (nextOpen) {
                if (connectivityDataActive) {
                    requestWifiStateRefresh();
                    if (wifiSupported && wifiEnabled)
                        requestWifiListRefresh(true);
                }
            } else {
                clearWifiPrompt();
                clearWifiMessages();
            }
        } else if (kind === "bluetooth") {
            changed = bluetoothPanelOpen !== nextOpen;
            bluetoothPanelOpen = nextOpen;

            if (!nextOpen) {
                if (bluetoothPairingActive)
                    cancelBluetoothPairing();
                if (bluetoothAdapter && bluetoothAdapter.discovering)
                    bluetoothAdapter.discovering = false;
                bluetoothScanStopTimer.stop();
                bluetoothPairAndConnectPath = "";
                bluetoothPendingSecretValue = "";
                clearBluetoothMessages();
            }
        } else {
            return;
        }

        if (changed && emitSignal)
            connectivityPanelRequested(kind, nextOpen);
    }

    function toggleConnectivityOverlay(kind) {
        setConnectivityPanelOpen(kind, !isConnectivityPanelOpen(kind));
    }

    function closeConnectivityPanels(emitSignals) {
        if (emitSignals === undefined)
            emitSignals = true;

        setConnectivityPanelOpen("wifi", false, emitSignals);
        setConnectivityPanelOpen("bluetooth", false, emitSignals);
        clearWifiPrompt();
        clearWifiMessages();
        clearBluetoothMessages();
    }

    function requestWifiStateRefresh() {
        if (!connectivityDataActive || !wifiController) return;
        wifiController.refreshState();
    }

    function requestWifiListRefresh(rescan) {
        if (!connectivityDataActive || !wifiController) return;
        if (!wifiSupported || !wifiAvailable || !wifiEnabled) return;
        wifiController.refreshNetworks(!!rescan);
    }

    function toggleWifiEnabled() {
        clearWifiPrompt();
        clearWifiMessages();
        if (wifiController)
            wifiController.setEnabled(!wifiEnabled);
    }

    function disconnectWifi() {
        if (!wifiSupported || !wifiAvailable) {
            wifiLocalError = wifiAvailabilityMessage.length > 0 ? wifiAvailabilityMessage : "No Wi-Fi device is available.";
            return;
        }

        clearWifiPrompt();
        clearWifiMessages();
        if (wifiController)
            wifiController.disconnectCurrent();
    }

    function connectWifiNetwork(network) {
        if (!network) return;
        if (!wifiSupported) {
            wifiLocalError = wifiAvailabilityMessage.length > 0 ? wifiAvailabilityMessage : "Wi-Fi control is unavailable.";
            return;
        }
        if (!wifiAvailable) {
            wifiLocalError = wifiAvailabilityMessage.length > 0 ? wifiAvailabilityMessage : "No Wi-Fi device is available.";
            return;
        }
        if (!wifiEnabled) {
            wifiLocalError = "Turn on Wi-Fi first.";
            return;
        }
        if (network.connected) return;

        const ssid = trimString(network.ssid);
        const networkType = trimString(network.type);
        const secure = !!network.secure;
        const savedConnection = !!network.savedConnection;

        if (!ssid) {
            wifiLocalError = "Hidden networks are not supported in this panel yet.";
            return;
        }

        if (!savedConnection && networkType === "wep") {
            wifiLocalError = "WEP networks aren't supported by this panel.";
            return;
        }

        if (!savedConnection && networkType === "8021x") {
            wifiLocalError = "802.1X networks need to be provisioned first.";
            return;
        }

        clearWifiPrompt();
        clearWifiMessages();

        if (savedConnection) {
            if (wifiController)
                wifiController.connectToNetwork(ssid);
            return;
        }

        if (!secure) {
            if (wifiController)
                wifiController.connectToNetwork(ssid);
            return;
        }

        wifiPendingPasswordSsid = ssid;
        wifiPendingPasswordValue = "";
        wifiLocalInfoMessage = "Enter the password for " + ssid + ".";
    }

    function submitWifiPassword() {
        const ssid = trimString(wifiPendingPasswordSsid);
        if (!ssid) return;

        if (trimString(wifiPendingPasswordValue).length === 0) {
            wifiLocalError = "Enter a password first.";
            return;
        }

        const password = wifiPendingPasswordValue;
        clearWifiPrompt();
        clearWifiMessages();
        if (wifiController)
            wifiController.connectToNetwork(ssid, password);
    }

    function applyBrightnessSnapshot(value) {
        if (value >= 0)
            syncBrightnessFromLevel(value);
    }

    function applyVolumeSnapshot(value) {
        if (value >= 0)
            syncVolumeFromLevel(value);
    }

    function flushBrightness(force) {
        const nextValue = clamp01(pendingBrightness);
        if (!force && Math.abs(nextValue - lastAppliedBrightness) < 0.01) return;
        if (brightnessSetterRunning) {
            brightnessApplyTimer.restart();
            return;
        }

        lastAppliedBrightness = nextValue;
        brightnessSetterRunning = true;
        SystemServices.setBrightness(nextValue);
    }

    function queueBrightness(value) {
        localBrightness = clamp01(value);
        if (showCondition && !sliderIntroPending) displayedBrightness = localBrightness;
        pendingBrightness = localBrightness;
        brightnessApplyTimer.restart();
    }

    function flushVolume(force) {
        const nextValue = clamp01(pendingVolume);
        if (!force && Math.abs(nextValue - lastAppliedVolume) < 0.01) return;
        if (volumeSetterRunning) {
            volumeApplyTimer.restart();
            return;
        }

        lastAppliedVolume = nextValue;
        volumeSetterRunning = true;
        SystemServices.setVolume(nextValue);
    }

    function queueVolume(value) {
        localVolume = clamp01(value);
        if (showCondition && !sliderIntroPending) displayedVolume = localVolume;
        pendingVolume = localVolume;
        volumeApplyTimer.restart();
    }

    function syncBrightnessFromLevel(level) {
        if (level < 0) return;
        localBrightness = clamp01(level);
        if (showCondition && !sliderIntroPending) displayedBrightness = localBrightness;
        pendingBrightness = localBrightness;
        lastAppliedBrightness = localBrightness;
    }

    function syncVolumeFromLevel(level) {
        if (level < 0) return;
        localVolume = clamp01(level);
        if (showCondition && !sliderIntroPending) displayedVolume = localVolume;
        pendingVolume = localVolume;
        lastAppliedVolume = localVolume;
    }

    function syncLevelsFromProps() {
        syncBrightnessFromLevel(brightnessLevel);
        syncVolumeFromLevel(volumeLevel);
    }

    function bluetoothDeviceName(device) {
        if (!device) return "Unknown device";
        const preferred = trimString(device.deviceName);
        if (preferred.length > 0) return preferred;

        const alias = trimString(device.name);
        if (alias.length > 0) return alias;

        const address = trimString(device.address);
        return address.length > 0 ? address : "Unknown device";
    }

    function bluetoothDeviceStateText(device) {
        if (!device) return "";
        if (device.pairing) return "Pairing";

        switch (device.state) {
        case BluetoothDeviceState.Connecting:
            return "Connecting";
        case BluetoothDeviceState.Connected:
            return "Connected";
        case BluetoothDeviceState.Disconnecting:
            return "Disconnecting";
        default:
            break;
        }

        if (device.paired || device.bonded) return "Paired";
        return "Available";
    }

    function bluetoothDeviceSubtitle(device) {
        const parts = [];
        const stateLabel = bluetoothDeviceStateText(device);
        if (stateLabel.length > 0) parts.push(stateLabel);
        if (device && device.batteryAvailable) parts.push(bluetoothBatteryPercent(device) + "%");
        return parts.join(" • ");
    }

    function bluetoothBatteryPercent(device) {
        if (!device || !device.batteryAvailable)
            return -1;

        const rawValue = Math.max(0, Number(device.battery) || 0);
        return Math.max(0, Math.min(100, Math.round(rawValue <= 1 ? rawValue * 100 : rawValue)));
    }

    function bluetoothDeviceMatchesSection(device, section) {
        if (!device) return false;

        const paired = device.paired || device.bonded;
        if (section === "connected") return device.connected;
        if (section === "paired") return !device.connected && paired;
        if (section === "available") return !paired;
        return false;
    }

    function buildBluetoothStatusText() {
        if (!bluetoothAvailable) return "Unavailable";
        if (!bluetoothEnabled) return "Off";

        const devices = bluetoothDeviceValues || [];
        const connectedNames = [];

        for (let index = 0; index < devices.length; index++) {
            const device = devices[index];
            if (device && device.connected)
                connectedNames.push(bluetoothDeviceName(device));
        }

        if (connectedNames.length === 1) return connectedNames[0];
        if (connectedNames.length > 1) return connectedNames[0] + " +" + (connectedNames.length - 1);
        if (bluetoothAdapter.discovering) return "Scanning";
        return bluetoothBusy ? "Working..." : "On";
    }

    function toggleBluetoothEnabled() {
        if (!bluetoothAdapter) {
            bluetoothError = "No Bluetooth adapter is available.";
            return;
        }

        bluetoothError = "";
        bluetoothInfoMessage = "";
        bluetoothPairAndConnectPath = "";

        if (bluetoothAdapter.discovering)
            bluetoothAdapter.discovering = false;

        bluetoothAdapter.enabled = !bluetoothAdapter.enabled;
    }

    function toggleBluetoothScan() {
        if (!bluetoothAdapter) {
            bluetoothError = "No Bluetooth adapter is available.";
            return;
        }
        if (!bluetoothEnabled) {
            bluetoothError = "Turn on Bluetooth first.";
            return;
        }

        bluetoothError = "";
        if (bluetoothAdapter.discovering) {
            bluetoothAdapter.discovering = false;
            bluetoothInfoMessage = "";
            bluetoothScanStopTimer.stop();
        } else {
            bluetoothAdapter.discovering = true;
            bluetoothInfoMessage = "Scanning for nearby devices...";
            bluetoothScanStopTimer.restart();
        }
    }

    function handleBluetoothDevicePressed(device) {
        if (!device) return;
        if (!bluetoothAdapter || !bluetoothEnabled) {
            bluetoothError = "Turn on Bluetooth first.";
            return;
        }

        bluetoothError = "";

        if (device.connected) {
            bluetoothInfoMessage = "";
            device.disconnect();
            return;
        }

        if (device.paired || device.bonded) {
            bluetoothInfoMessage = "";
            device.connect();
            return;
        }

        bluetoothPairAndConnectPath = device.dbusPath;
        bluetoothInfoMessage = "Pairing " + bluetoothDeviceName(device) + "...";
        device.pair();
    }

    function forgetBluetoothDevice(device) {
        if (!device) return;
        if (bluetoothPairAndConnectPath === device.dbusPath)
            bluetoothPairAndConnectPath = "";
        device.forget();
    }

    anchors.fill: parent
    anchors.margins: Metrics.pad(12)
    opacity: showCondition ? 1 : 0
    visible: opacity > 0

    // Not `focus: true`. This layer outlives its own visibility — it stays
    // mounted as the data provider for the standalone Wi-Fi and Bluetooth
    // lists (see connectivityDataActive above), and an invisible provider
    // holding the focus item would eat the keys of the panel that is
    // actually on screen.
    focus: showCondition
    activeFocusOnTab: true

    Keys.onPressed: function(event) {
        switch (event.key) {
        case Qt.Key_Escape:
        case Qt.Key_Q:
            // Innermost thing first, the same rule the power menu applies to
            // its confirm step. Three levels now, unwound outside-in:
            // the grid cursor is the shallowest — it is a highlight, not a
            // mode, so it should cost the cheapest Escape — then the drawer,
            // then the panel. Closing the control centre out from under a
            // pulled-open drawer would lose the pull as well as the panel.
            if (quickGrid.cursor >= 0)
                quickGrid.cursor = -1;
            else if (controlCenter.batteryDrawerOpen)
                controlCenter.setBatteryDrawerOpen(false);
            else
                controlCenter.closeRequested();
            event.accepted = true;
            break;

        // ---- THE GRID, FROM THE KEYBOARD ----
        //
        // FORK: the control centre is opened by $mod SHIFT A — a KEYBOARD
        // binding — and until now could not be operated from the keyboard at
        // all. upgread_UI_UX.md P0-3 counts it: 6 MouseAreas, 0 Keys
        // handlers, against nine fork panels that are keyboard-only with no
        // hover states. Two disjoint interaction models split by who wrote
        // the file, and no panel supporting both.
        //
        // The arrows adopt the grid on first press rather than requiring a
        // separate "enter grid" key: with cursor at -1 any direction lands
        // on tile 0, which is what someone who just pressed Right meant.
        // hjkl alongside the arrows, on request. Every OTHER panel in this
        // shell is already j/k driven — the pickers, the audio and display
        // panels, both connectivity lists — so the arrows were the odd
        // convention here, not the vim keys. They are listed as fallthrough
        // cases on the same branches rather than as a second block, because
        // two branches doing the same thing is how the pair drifts.
        //
        // `q` is NOT remapped to anything vim-ish and stays as close. It is
        // already the quit key on every panel in the tree and vim's own
        // habit agrees with that.
        case Qt.Key_H:
        case Qt.Key_Left:   quickGrid.moveCursor(-1, 0); event.accepted = true; break;
        case Qt.Key_K:
        case Qt.Key_Up:     quickGrid.moveCursor(0, -1); event.accepted = true; break;
        case Qt.Key_J:
        case Qt.Key_Down:   quickGrid.moveCursor(0, 1);  event.accepted = true; break;

        case Qt.Key_L:
        case Qt.Key_Right:
            // Right is overloaded and the order matters. On a tile that owns
            // a list, Right opens it — mirroring the chevron, which points
            // that way and sits on that side. On a tile that does not, Right
            // is just movement, and openList() returning false is what lets
            // it fall through instead of being swallowed.
            if (!quickGrid.openList())
                quickGrid.moveCursor(1, 0);
            event.accepted = true;
            break;

        case Qt.Key_Space:
        case Qt.Key_Return:
        case Qt.Key_Enter:
            // Space and Enter both commit, because the grid is reachable
            // from two conventions and neither is wrong here. No-op at
            // cursor -1 rather than defaulting to tile 0: a blind Space
            // should not toggle a radio.
            if (quickGrid.cursor >= 0)
                quickGrid.activate();
            event.accepted = true;
            break;

        default:
            break;
        }
    }

    onBrightnessLevelChanged: syncBrightnessFromLevel(brightnessLevel)
    onVolumeLevelChanged: syncVolumeFromLevel(volumeLevel)
    onShowConditionChanged: {
        if (showCondition) {
            // ---- THE PANEL HAD KEYS AND NEVER RECEIVED ONE ----
            //
            // FORK: `focus: showCondition` above is necessary and is NOT
            // sufficient, and this is the line that was missing. Proven
            // rather than reasoned: with the control centre open, `wtype j`
            // and `wtype l` did nothing, while the same wtype typing "zqx"
            // into the application launcher's search field landed all three
            // characters. So the compositor grab is fine, the island is
            // receiving keys, and the problem is entirely inside the scene.
            //
            // `focus: true` only nominates an item as the focus child OF ITS
            // PARENT SCOPE. The parent here is a PanelLoader, and a Loader
            // is not a FocusScope — so the nomination stops there and never
            // reaches the window. islandContainer.forceActiveFocus(), which
            // DynamicIslandWindow fires on a 0 ms timer for exactly this
            // purpose, gives focus to the FocusScope and then hands it to
            // ITS focus child, which is the loader, not the layer inside it.
            //
            // The panels that do work are the ones whose loaders declare
            // `onLoaded: item.forceActiveFocus()` — PanelLoader's own header
            // records that wifiPanelLoader and bluetoothPanelLoader do this.
            // The control centre's loader never did.
            //
            // Claiming it from the layer rather than adding a fourth
            // onLoaded at the instantiation site, because forceActiveFocus()
            // walks UP and takes focus for this item regardless of how many
            // non-scope wrappers are in between — so it cannot be broken
            // again by someone changing the loader. And on showCondition
            // rather than onLoaded, because `retain` keeps this instance
            // alive across closes: onLoaded fires once ever, and the panel
            // is opened many times.
            Qt.callLater(function() {
                if (controlCenter.showCondition)
                    controlCenter.forceActiveFocus();
            });
            syncLevelsFromProps();
            sliderIntroPending = true;
            displayedBrightness = localBrightness;
            displayedVolume = localVolume;
            sliderIntroTimer.interval = sliderIntroDelay;
            sliderIntroTimer.restart();
            refreshBatteryModeState();
            requestWifiStateRefresh();
            if (wifiPanelOpen && wifiSupported && wifiEnabled)
                requestWifiListRefresh(true);
        } else {
            sliderIntroTimer.stop();
            sliderIntroPending = false;
            displayedBrightness = localBrightness;
            displayedVolume = localVolume;
            // Not while a standalone connectivity popup is the reason this
            // layer went invisible. Clicking the Wi-Fi row switches the
            // island from control_center to wifi_panel, which makes
            // showCondition false in the same turn — and this line, written
            // when the lists were a wing of a visible control centre, would
            // then stop the Bluetooth scan and clear the Wi-Fi prompt of the
            // panel that was just opened.
            //
            // The ordering between showCondition and connectivityHostActive
            // is NOT guaranteed (they are two bindings on the same island
            // state and QML does not promise which updates first), so the
            // host also re-asserts the panel through setConnectivityPanelOpen
            // on the next event-loop turn. This guard is what makes the
            // common ordering cost nothing; that callLater is what makes the
            // other ordering harmless.
            if (!connectivityHostActive)
                closeConnectivityPanels();
        }
    }

    Component.onCompleted: {
        syncLevelsFromProps();
        displayedBrightness = localBrightness;
        displayedVolume = localVolume;
        SystemServices.requestBrightness();
        SystemServices.requestVolume();
        refreshBatteryModeState();
        refreshFocusState();
    }

    // FORK: one choreography for every layer in the shell.
    // Was `showCondition ? 240 : 100` on Easing.InOutQuad — one of
    // eight hand-picked in-durations and six out-durations that agreed
    // with neither each other nor the 400 ms the shape takes. See
    // Motion.js, "CONTENT CHOREOGRAPHY", for the measurement.
    Behavior on opacity {
        SequentialAnimation {
            // The delay is what keeps the content from being painted
            // inside a capsule that is still the wrong size for it.
            PauseAnimation { duration: showCondition ? Motion.contentDelay() : 0 }
            NumberAnimation {
                duration: showCondition ? Motion.fadeInDuration() : Motion.fadeOutDuration()
                // Critically damped: opacity is clamped 0-1 and an
                // overshooting fade reads as a cut. Motion.js says why.
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Motion.fade()
            }
        }
    }

    Behavior on displayedBrightness {
        enabled: controlCenter.showCondition && !controlCenter.sliderIntroPending && !brightnessCard.pressed

        NumberAnimation {
            duration: 130
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Motion.fade()   // FORK: was Easing.OutCubic
        }
    }

    Behavior on displayedVolume {
        enabled: controlCenter.showCondition && !controlCenter.sliderIntroPending && !volumeCard.pressed

        NumberAnimation {
            duration: 130
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Motion.fade()   // FORK: was Easing.OutCubic
        }
    }

    Behavior on batteryDrawerProgress {
        enabled: !controlCenter.batteryDrawerDragging

        NumberAnimation {
            id: batteryDrawerProgressAnimation
            duration: 240
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Motion.fade()   // FORK: was Easing.OutCubic
        }
    }

    // ---- WHY THERE IS NO FOCUS PROCESS HERE ANY MORE ----
    //
    // Two rewrites of this row are gone from this file, and the reasoning
    // is worth keeping even though the code is not, because the SHAPE of
    // the bug recurs:
    //
    //   1. It was `["swaync-client", "--get-dnd"]`. swaync-client is not
    //      installed on this machine and never has been. All three of the
    //      row's commands — read, enable, disable — failed to start. The
    //      read failing was harmless-looking; the WRITES were the bug, both
    //      writing `focusEnabled = exitCode === 0`, so a command that could
    //      not start reported "not enabled" and the row settled to off. It
    //      did not fail visibly stuck. It failed by silently agreeing with
    //      itself, which is why it looked like it worked.
    //
    //   2. Rewritten onto `dunstctl is-paused` / `set-paused`, which was
    //      right — dunst owned the bus then — and which took care never to
    //      infer state from an exit code, because "the command failed" and
    //      "the answer is false" are the same value. It also measured the
    //      polarity from the daemon rather than taking it from the brief,
    //      which had it backwards.
    //
    // Both are now moot: the island SERVES org.freedesktop.Notifications
    // itself and dunst is out of autostart.conf, so `dunstctl is-paused`
    // asks a daemon that is not running and the row would sit permanently
    // "unavailable" — honest, and useless.
    //
    // The general lesson survives all three versions and is the reason this
    // comment stays: a control whose state is derived from a subprocess
    // will lie the next time the tool is missing. The current version has
    // no subprocess at all. See toggleFocus() and hostFocusEnabled.

    Process {
        id: nightLightEnableProcess
        command: [
            "sh",
            "-c",
            controlCenter.hyprlandNightLight
                ? "temp=\"$1\"\n"
                    + "if ! command -v hyprsunset >/dev/null 2>&1; then exit 127; fi\n"
                    + "if hyprctl hyprsunset temperature \"$temp\" >/dev/null 2>&1; then exit 0; fi\n"
                    + "if ! command -v pgrep >/dev/null 2>&1 || ! pgrep -x hyprsunset >/dev/null 2>&1; then\n"
                    + "  if command -v setsid >/dev/null 2>&1; then\n"
                    + "    setsid hyprsunset >/dev/null 2>&1 < /dev/null &\n"
                    + "  else\n"
                    + "    nohup hyprsunset >/dev/null 2>&1 < /dev/null &\n"
                    + "  fi\n"
                    + "fi\n"
                    + "i=0\n"
                    + "while [ \"$i\" -lt 24 ]; do\n"
                    + "  if hyprctl hyprsunset temperature \"$temp\" >/dev/null 2>&1; then exit 0; fi\n"
                    + "  i=$((i + 1))\n"
                    + "  sleep 0.04\n"
                    + "done\n"
                    + "exit 1"
                : "temp=\"$1\"\n"
                    + "if ! command -v gammastep >/dev/null 2>&1; then exit 127; fi\n"
                    + "gammastep -m wayland -P -O \"$temp\" >/dev/null 2>&1",
            "tide-night-light",
            controlCenter.nightLightTemperature.toString()
        ]
        running: false

        onExited: function(exitCode) {
            if (exitCode === 0) {
                controlCenter.nightLightBusy = false;
                controlCenter.nightLightEnabled = true;
                controlCenter.nightLightModeChanged(true);
                controlCenter.requestNotification("Night Light", "Night Light enabled", controlCenter.nightLightTemperature + "K");
                return;
            }

            controlCenter.nightLightBusy = false;
            controlCenter.nightLightEnabled = false;
            controlCenter.nightLightModeChanged(false);
            controlCenter.requestNotification("Night Light", "Night Light unavailable",
                controlCenter.hyprlandNightLight
                    ? "Install hyprsunset to use Night Light."
                    : "Install gammastep to use Night Light.");
        }
    }

    Process {
        id: nightLightDisableProcess
        command: [
            "sh",
            "-c",
            controlCenter.hyprlandNightLight
                ? "hyprctl hyprsunset identity >/dev/null 2>&1 || true"
                : "if ! command -v gammastep >/dev/null 2>&1; then exit 127; fi\n"
                    + "gammastep -m wayland -x >/dev/null 2>&1 || true"
        ]
        running: false

        onExited: function(exitCode) {
            controlCenter.nightLightBusy = false;
            controlCenter.nightLightEnabled = false;
            controlCenter.nightLightModeChanged(false);
            if (exitCode === 127)
                controlCenter.requestNotification("Night Light", "Night Light unavailable",
                    controlCenter.hyprlandNightLight
                        ? "Install hyprsunset to use Night Light."
                        : "Install gammastep to use Night Light.");
            else
                controlCenter.requestNotification("Night Light", "Night Light disabled", "");
        }
    }


    Connections {
        target: SystemServices

        function onTlpStateReady(available, profile, output, errorString) {
            controlCenter.applyBatteryModeState(available, profile, output, errorString);
        }

        function onTlpSetFinished(success, exitCode, output, errorString) {
            controlCenter.finishBatteryModeApply(success, exitCode, output, errorString);
        }

        function onBrightnessSnapshotReady(value, errorString) {
            if (errorString === "")
                controlCenter.applyBrightnessSnapshot(value);
        }

        function onBrightnessSetFinished(value, success, errorString) {
            controlCenter.brightnessSetterRunning = false;
            if (success)
                controlCenter.applyBrightnessSnapshot(value);
            if (success && Math.abs(controlCenter.pendingBrightness - controlCenter.lastAppliedBrightness) >= 0.01)
                brightnessApplyTimer.restart();
        }

        function onVolumeSnapshotReady(value, muted, errorString) {
            if (errorString === "")
                controlCenter.applyVolumeSnapshot(value);
        }

        function onVolumeSetFinished(value, success, errorString) {
            controlCenter.volumeSetterRunning = false;
            if (success)
                controlCenter.applyVolumeSnapshot(value);
            if (success && Math.abs(controlCenter.pendingVolume - controlCenter.lastAppliedVolume) >= 0.01)
                volumeApplyTimer.restart();
        }
    }

    Timer {
        id: brightnessApplyTimer
        interval: 55
        repeat: false
        onTriggered: controlCenter.flushBrightness(false)
    }

    Timer {
        id: volumeApplyTimer
        interval: 55
        repeat: false
        onTriggered: controlCenter.flushVolume(false)
    }

    Timer {
        id: sliderIntroTimer
        interval: controlCenter.sliderIntroDelay
        repeat: false

        onTriggered: {
            controlCenter.sliderIntroPending = false;
            controlCenter.displayedBrightness = controlCenter.localBrightness;
            controlCenter.displayedVolume = controlCenter.localVolume;
        }
    }

    Timer {
        id: batteryModeRefreshTimer
        interval: 1500
        repeat: true
        onTriggered: {
            if (controlCenter.batteryModeRefreshPollsRemaining <= 0) {
                stop();
                return;
            }

            controlCenter.batteryModeRefreshPollsRemaining -= 1;
            controlCenter.refreshBatteryModeState();

            if (controlCenter.batteryModeRefreshPollsRemaining <= 0)
                stop();
        }
    }

    Timer {
        id: bluetoothScanStopTimer
        interval: 8000
        repeat: false
        onTriggered: {
            if (controlCenter.bluetoothAdapter && controlCenter.bluetoothAdapter.discovering)
                controlCenter.bluetoothAdapter.discovering = false;
            controlCenter.bluetoothInfoMessage = "";
        }
    }

    Timer {
        id: batteryDrawerSettleTimer
        interval: 300
        repeat: false
        onTriggered: controlCenter.batteryDrawerSettling = false
    }

    Connections {
        target: wifiController

        function onEnabledChanged() {
            if (!controlCenter.wifiEnabled)
                controlCenter.clearWifiPrompt();
        }
    }

    Connections {
        target: bluetoothAdapter

        // FORK: `bluetoothScanStopTimer`, NOT `controlCenter.bluetoothScanStopTimer`.
        //
        // An `id` is not a property. It is a name in the component's
        // compilation scope, so it resolves bare from anywhere inside this
        // file — which is how the three other call sites (614, 921, 925)
        // have always written it — but it is NOT a member of the root
        // object, so qualifying it returns `undefined` and calling `.stop()`
        // on that throws.
        //
        // Both handlers in this Connections block had the qualified form and
        // both were dead. Found in the live log rather than by reading:
        //
        //   WARN scene: ControlCenterLayer.qml[1327]: TypeError:
        //   Cannot read property 'stop' of undefined
        //
        // repeating on a 60 s cadence, which is the scan poll.
        //
        // The consequence is not cosmetic and is visible on the panel: these
        // are the two paths that stop a Bluetooth discovery scan when the
        // adapter is switched off or the daemon reports discovery already
        // ended. Neither ever ran, so the timer kept restarting the scan, the
        // row read "Scanning" permanently, and the adapter logged
        // "Failed to stop discovery ... No discovery started" in pairs for
        // the life of the session. A radio scanning forever on a laptop is a
        // battery cost, not just a wrong label.
        function onEnabledChanged() {
            if (!controlCenter.bluetoothAdapter.enabled) {
                controlCenter.bluetoothPairAndConnectPath = "";
                controlCenter.bluetoothInfoMessage = "";
                controlCenter.bluetoothError = "";
                bluetoothScanStopTimer.stop();
            }
        }

        function onDiscoveringChanged() {
            if (!controlCenter.bluetoothAdapter.discovering)
                bluetoothScanStopTimer.stop();
        }
    }

    Connections {
        target: bluetoothPairingAgent

        function onRequestChanged() {
            controlCenter.bluetoothPendingSecretValue = "";
            if (controlCenter.bluetoothPairingActive) {
                controlCenter.bluetoothError = "";
                controlCenter.setConnectivityPanelOpen("bluetooth", true);
            }
        }

        function onRegistrationErrorChanged() {
            if (!controlCenter.bluetoothPairingAgent)
                return;

            if (!controlCenter.bluetoothPairingAgent.registered
                    && controlCenter.bluetoothPairingAgent.registrationError.length > 0
                    && controlCenter.bluetoothPanelOpen) {
                controlCenter.bluetoothError = controlCenter.bluetoothPairingAgent.registrationError;
            }
        }
    }

    Column {
        anchors.fill: parent
        spacing: Metrics.px(12)

        // ---- THE HEADER IS A HERO NUMBER, NOT A TITLE BAR ----
        //
        // Was `16:37  Wed, Aug 12` set side by side on one baseline, which is
        // the layout of a status bar: two facts of apparently equal weight,
        // the clock only larger because it is a clock. ukishima never sets
        // two things on one baseline like that. Their pattern — Calendar.qml
        // around line 261, and the battery surface's percentage — is a HERO
        // NUMBER with a small caption beneath it: 26 px DemiBold over a
        // 10 px sub, stacked, with the number owning the block.
        //
        // So the date drops under the clock and becomes a caption in the
        // letterspaced-uppercase register this shell already uses for every
        // field name (the faders, and ConnectivityDetailPanel's own header,
        // which was ported from ukishima and kept). Nothing is invented here
        // and nothing is lost: the same two facts, re-ranked.
        //
        // font.features tnum: tabular figures, so the clock does not shuffle
        // sideways as the minute digits change width. ukishima sets it on
        // every number that updates in place.
        Item {
            width: parent.width
            height: Metrics.px(42)

            Column {
                anchors.left: parent.left
                anchors.leftMargin: Metrics.pad(6)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Metrics.px(1)

                Text {
                    id: timeLabel
                    text: currentTime
                    color: IslandTheme.textPrimary
                    // 19 -> 24 and Bold -> DemiBold. A hero number carries by
                    // SIZE; at 19 px it needed Bold to look deliberate, and
                    // bold-plus-negative-tracking is the register of a badge,
                    // not of a display figure.
                    font.pixelSize: Metrics.font(24)
                    font.family: heroFontFamily
                    font.weight: Font.DemiBold
                    font.features: ({ "tnum": 1 })
                }

                Text {
                    text: currentDateLabel
                    color: IslandTheme.textMuted
                    font.pixelSize: Metrics.font(10)
                    font.family: textFontFamily
                    font.weight: Font.Medium
                    font.capitalization: Font.AllUppercase
                    // The letterspacing is the treatment. Without it this is
                    // just a small grey date. 1.0 rather than the header
                    // rule's 1.6 because this sits UNDER a number and has to
                    // read as its caption, not as a second heading.
                    font.letterSpacing: 1.0
                }
            }

            Row {
                anchors.right: parent.right
                anchors.rightMargin: Metrics.pad(2)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Metrics.px(5)

                Text {
                    text: controlCenter.chargingIconGlyph
                    color: IslandTheme.textPrimary
                    font.pixelSize: Metrics.font(13)
                    font.family: iconFontFamily
                    visible: isCharging
                    anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                    text: batteryCapacity + "%"
                    color: IslandTheme.textPrimary
                    font.pixelSize: Metrics.font(13)
                    font.family: textFontFamily
                    font.weight: Font.DemiBold
                    anchors.verticalCenter: parent.verticalCenter
                }

                Item {
                    width: Metrics.px(28)
                    height: Metrics.px(14)
                    anchors.verticalCenter: parent.verticalCenter

                    Rectangle {
                        anchors.fill: parent
                        anchors.rightMargin: Metrics.pad(2)
                        radius: Metrics.px(4)
                        color: "transparent"
                        border.color: IslandTheme.textSecondary
                        border.width: 1

                        Rectangle {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            anchors.margins: Metrics.pad(2)
                            radius: Metrics.px(2)
                            width: (parent.width - 4) * (batteryCapacity / 100.0)
                            // ONE OF THE FOUR DELIBERATE EXCEPTIONS TO THE
                            // TOKEN LAYER — the battery bar, where the
                            // colour IS the reading rather than the
                            // styling. Bound to IslandTheme.danger /
                            // warning / success, "8% battery" would draw in
                            // gruvbox yellow on one theme and matrix green
                            // on another.
                            //
                            // Written as literals rather than left on
                            // StyleTokens, which happens to freeze them to
                            // exactly these three values but freezes them
                            // by accident — the reason would have lived in
                            // a package binary instead of here, and the
                            // next person removing the last StyleTokens
                            // import would have taken the exception with
                            // it without noticing. Same ladder as
                            // BluetoothExpandedLayer.qml, same values.
                            color: {
                                if (batteryCapacity <= 10) return "#ff3b30";
                                if (batteryCapacity <= 20) return "#ffcc00";
                                return "#34c759";
                            }

                            Behavior on width {
                                NumberAnimation {
                                    duration: 300
                                    easing.type: Easing.BezierSpline
                                    easing.bezierCurve: Motion.spring()   // FORK: was Easing.OutCubic
                                }
                            }
                        }
                    }

                    Rectangle {
                        width: Metrics.px(2)
                        height: Metrics.px(6)
                        radius: 1
                        color: IslandTheme.textSecondary
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }
        }

        // ---- FLAT ROWS WITH A HAIRLINE, NOT TWO ROUNDED CARDS ----
        //
        // Was two 80 px cards side by side, radius 13, each on its own matte
        // surface — the last structural thing in this panel that ukishima
        // does not do anywhere. Their settings surfaces have NO cards: every
        // line is a full-width row on the panel's own material, transparent
        // until hovered, separated only by a one-pixel hairline, and the last
        // row in a group drops its hairline (components/SettingsRow.qml).
        //
        // A card says "this is a separate object on a background". A row says
        // "this is a line in a list". Wi-Fi and Bluetooth are two lines in the
        // same list, and boxing them was making the panel read as a grid of
        // widgets rather than as one instrument.
        //
        // Going full-width also buys back what the cards were short of: the
        // SSID had half a panel to elide into and routinely lost its tail.
        //
        // Numbers taken from SettingsRow.qml rather than chosen: hover fill
        // is cream at 0.055 (Theme.frameBg) with radius 9 inset 3 px top and
        // bottom, the name is 12.5 px DemiBold over a 10.5 px faint sub, and
        // the hairline is cream at 0.08 (Theme.hairSoft). height 1 unscaled,
        // like every other hairline in this tree, so it stays exactly one
        // device pixel instead of rounding to 2 at some scales.
        // ============================================================
        //  THE QUICK GRID
        // ============================================================
        //
        // FORK — this replaces the two-row Wi-Fi / Bluetooth list that used
        // to sit here, and it is a restructure rather than a restyle.
        //
        // WHAT WAS ACTUALLY WRONG. Reported as "the control system ui not
        // good ... and u missed the nightlight eff add it also". The second
        // half is the one that explains the first, and it is not what it
        // looks like: Night mode was never missing. `toggleNightLight()` has
        // always been here, wired to a real daemon, and so has Focus — both
        // fully built, both with busy and unavailable states.
        //
        // They were inside `quickTogglesCard`, which lives inside the
        // BATTERY DRAWER, and `batteryDrawerOpen` defaults to false. So the
        // two most useful switches in the panel were behind a 40 px pull
        // handle that gives no indication of what it is hiding, and the
        // panel that opened on $mod SHIFT A showed exactly two controls.
        // That is the whole of "the UI is not good": it was not sparse
        // because nothing had been built, it was sparse because half of what
        // had been built was filed inside a drawer about batteries.
        //
        // So the fix is promotion, not addition. All four toggles come up to
        // one grid at the top of the panel, at equal weight, because they
        // are peers — none of them is a sub-setting of the battery.
        //
        // WHY A GRID AND NOT FOUR MORE ROWS. Four full-width rows is 184 px
        // of panel to say four words. These are binary switches with a
        // one-line status; the row form spends its width on a gutter between
        // the label and a toggle pill parked at the right margin, and at
        // four items that gutter becomes the dominant feature. A tile puts
        // the state in the FILL, which needs no width at all, and gets the
        // whole set into two rows instead of four.
        //
        // TWO ACTIONS PER TILE, AND WHY THE CHEVRON IS A SEPARATE TARGET.
        // Wi-Fi and Bluetooth each do two things: toggle the radio, and open
        // a list. The old row gave the toggle a 28 px pill and the list the
        // entire rest of the row, which is backwards — turning Wi-Fi off is
        // the rarer act and it had the smaller target only by accident of
        // where a switch conventionally sits. Here the tile BODY toggles and
        // the chevron opens, so the common action gets the large target. The
        // chevron carries `Metrics.px(30)` of hit area rather than its own
        // ink size, because a 10 px glyph is not a pointer target.
        //
        // Focus and Night mode have no list, so they have no chevron, and
        // their tile body is the only target. The absence is the signal.
        Item {
            id: quickGrid
            width: parent.width
            height: gridFlow.height

            // -1 is "the pointer is driving". Any arrow key adopts the grid
            // and lights a tile; Escape hands it back. Kept on the grid
            // rather than on the root because the root's Keys handler is
            // shared with the battery drawer and the connectivity overlays,
            // and a cursor that survived those would light a tile behind an
            // open list.
            property int cursor: -1
            readonly property int columns: 2
            readonly property int count: 4

            function moveCursor(dx, dy) {
                if (cursor < 0) {
                    cursor = 0;
                    return;
                }
                let col = cursor % columns;
                let row = Math.floor(cursor / columns);
                col = Math.max(0, Math.min(columns - 1, col + dx));
                row = Math.max(0, Math.min(Math.ceil(count / columns) - 1, row + dy));
                const next = row * columns + col;
                if (next < count)
                    cursor = next;
            }

            function activate() {
                switch (cursor) {
                case 0: controlCenter.toggleWifiEnabled(); break;
                case 1: controlCenter.toggleBluetoothEnabled(); break;
                case 2: controlCenter.toggleFocus(); break;
                case 3: controlCenter.toggleNightLight(); break;
                }
            }

            // Only the two that have one. Returns false so the caller can
            // fall through and let the key mean something else on a tile
            // with no list, rather than silently swallowing it.
            function openList() {
                if (cursor === 0) {
                    controlCenter.toggleConnectivityOverlay("wifi");
                    return true;
                }
                if (cursor === 1) {
                    controlCenter.toggleConnectivityOverlay("bluetooth");
                    return true;
                }
                return false;
            }

            component QuickTile: Item {
                id: tile

                property string glyph: ""
                property string label: ""
                property string status: ""
                property bool on: false
                property bool busy: false
                property bool available: true
                property bool hasList: false
                property bool listOpen: false
                property int index: -1

                signal toggled()
                signal listRequested()

                readonly property bool cursored: quickGrid.cursor === tile.index
                readonly property bool interactive: tile.available && !tile.busy

                width: (quickGrid.width - Metrics.px(10)) / 2
                // 76, not 62. At 62 the glyph and the label OVERLAPPED —
                // caught in the first capture, not in the source, because
                // nothing about anchoring a label to the bottom and a glyph
                // to the top says they will collide; the arithmetic does.
                // Glyph 17 px from a top pad of 10 runs to ~31, and a
                // 12.5 px label sitting above a 10.5 px status inside a
                // 10 px bottom pad starts at ~28. Three stacked elements
                // need to be anchored as a stack, which is what they are
                // below — top-down off each other, so the height is a
                // consequence of the content instead of a guess the content
                // has to fit into.
                height: Metrics.px(76)

                HoverHandler {
                    id: tileHover
                    enabled: tile.interactive
                }

                Rectangle {
                    id: tilePlate
                    anchors.fill: parent
                    radius: Metrics.px(12)

                    // The fill IS the state. On is the accent at low alpha —
                    // the same 0.18 `selectionFill` uses, so a lit tile and a
                    // selected row read as one family rather than as two
                    // different ideas about "active".
                    color: tile.on
                        ? IslandTheme.alpha(controlCenter.accentColor, 0.18)
                        : (tileHover.hovered
                            ? Qt.rgba(0.925, 0.925, 0.925, 0.075)
                            : Qt.rgba(0.925, 0.925, 0.925, 0.035))

                    // Focus and hover are two different states and both are
                    // drawn — the rule Phase 3 of upgread_UI_UX.md adopts.
                    // Hover is a fill change, the keyboard cursor is a
                    // border, so a hovered tile under a moved cursor shows
                    // both at once without either hiding the other.
                    border.width: tile.cursored ? 1 : 0
                    border.color: IslandTheme.alpha(controlCenter.accentColor, 0.85)

                    opacity: tile.available ? 1 : 0.38

                    Behavior on color {
                        ColorAnimation { duration: IslandTheme.durationFast }
                    }
                    Behavior on opacity {
                        NumberAnimation { duration: IslandTheme.durationFast }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: tile.interactive
                    hoverEnabled: true
                    onClicked: {
                        quickGrid.cursor = tile.index;
                        tile.toggled();
                    }
                }

                Text {
                    id: tileGlyph
                    anchors.left: parent.left
                    anchors.leftMargin: Metrics.pad(12)
                    anchors.top: parent.top
                    anchors.topMargin: Metrics.pad(11)
                    text: tile.glyph
                    // The glyph takes the accent when lit and the muted ink
                    // when not. It is NOT accentInk: the plate behind it is
                    // the accent at 18%, i.e. still essentially the surface,
                    // so ink solved against a solid accent would be the
                    // wrong answer to a question nobody asked here.
                    color: tile.on ? controlCenter.accentColor : IslandTheme.textDisabled
                    font.pixelSize: Metrics.font(17)
                    font.family: controlCenter.iconFontFamily
                    opacity: tile.busy ? 0.45 : 1

                    Behavior on color {
                        ColorAnimation { duration: IslandTheme.durationFast }
                    }
                }

                // The list affordance. A 30 px box around a small glyph —
                // see the note at the top of the grid about pointer targets.
                Item {
                    id: tileChevron
                    visible: tile.hasList
                    anchors.right: parent.right
                    anchors.rightMargin: Metrics.pad(4)
                    anchors.top: parent.top
                    anchors.topMargin: Metrics.pad(3)
                    width: Metrics.px(30)
                    height: Metrics.px(30)

                    HoverHandler { id: chevHover }

                    Text {
                        anchors.centerIn: parent
                        text: "›"
                        color: (tile.listOpen || chevHover.hovered)
                            ? IslandTheme.textPrimary : IslandTheme.textMuted
                        font.pixelSize: Metrics.font(17)
                        font.family: controlCenter.textFontFamily
                        font.weight: Font.DemiBold
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            quickGrid.cursor = tile.index;
                            tile.listRequested();
                        }
                    }
                }

                Text {
                    id: tileLabel
                    anchors.left: parent.left
                    anchors.leftMargin: Metrics.pad(12)
                    anchors.right: parent.right
                    anchors.rightMargin: Metrics.pad(10)
                    // Hung off the GLYPH, not off the tile's bottom edge.
                    // The bottom-anchored version is what collided with the
                    // glyph at the old height: two elements measured from
                    // opposite edges of a fixed box will meet in the middle
                    // as soon as the box is a little too small, and neither
                    // one's declaration shows it.
                    anchors.top: tileGlyph.bottom
                    anchors.topMargin: Metrics.px(5)
                    // EXPLICIT height, and this is the second correction to
                    // this stack. Anchoring `tileStatus.top` to
                    // `tileLabel.bottom` is right and still produced an
                    // overlap, because a Text's implicit height is its FONT
                    // line height and these two are anchored the moment they
                    // are constructed — before the font is resolved and the
                    // line box is measured. The anchor is then evaluated
                    // against a height that is not yet the final one, and
                    // nothing re-runs it, so the pair settles ~9 px too
                    // close. Stating the height makes the anchor arithmetic
                    // independent of when the font arrives.
                    height: Metrics.px(16)
                    verticalAlignment: Text.AlignVCenter
                    text: tile.label
                    color: tile.on ? controlCenter.textPrimary : IslandTheme.textSecondary
                    font.pixelSize: Metrics.font(12.5)
                    font.family: controlCenter.textFontFamily
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }

                Text {
                    id: tileStatus
                    anchors.left: parent.left
                    anchors.leftMargin: Metrics.pad(12)
                    anchors.right: parent.right
                    anchors.rightMargin: Metrics.pad(10)
                    anchors.top: tileLabel.bottom
                    anchors.topMargin: Metrics.px(1)
                    height: Metrics.px(14)   // see tileLabel
                    verticalAlignment: Text.AlignVCenter
                    text: tile.status
                    color: IslandTheme.textMuted
                    font.pixelSize: Metrics.font(10.5)
                    font.family: controlCenter.textFontFamily
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                }
            }

            Grid {
                id: gridFlow
                width: parent.width
                columns: quickGrid.columns
                columnSpacing: Metrics.px(10)
                rowSpacing: Metrics.px(10)

                QuickTile {
                    index: 0
                    glyph: controlCenter.wifiGlyph
                    label: "Wi-Fi"
                    status: controlCenter.wifiStatusText
                    on: controlCenter.wifiEnabled
                    busy: controlCenter.wifiBusy
                    available: controlCenter.wifiSupported && controlCenter.wifiAvailable
                    hasList: true
                    listOpen: controlCenter.wifiPanelOpen
                    onToggled: controlCenter.toggleWifiEnabled()
                    onListRequested: controlCenter.toggleConnectivityOverlay("wifi")
                }

                QuickTile {
                    index: 1
                    glyph: controlCenter.bluetoothGlyph
                    label: "Bluetooth"
                    status: controlCenter.bluetoothStatusText
                    on: controlCenter.bluetoothEnabled
                    busy: controlCenter.bluetoothBusy
                    available: controlCenter.bluetoothAvailable
                    hasList: true
                    listOpen: controlCenter.bluetoothPanelOpen
                    onToggled: controlCenter.toggleBluetoothEnabled()
                    onListRequested: controlCenter.toggleConnectivityOverlay("bluetooth")
                }

                // Focus keeps the bell/bell-slash pair rather than the Shape
                // the drawer version drew. That Shape was a hand-built path
                // with a CurveRenderer and an animated slash, which is a lot
                // of machinery for a 17 px mark, and it was the only icon in
                // the panel not coming from the icon font — so it was also
                // the only one that would not follow a font change. The
                // glyph swap says the same thing in the same typeface as its
                // three neighbours.
                QuickTile {
                    index: 2
                    glyph: controlCenter.focusEnabled ? "" : ""
                    label: "Focus"
                    // Silent is the island's own state and always knowable —
                    // see the long note on refreshFocusState. So this never
                    // says "unavailable", unlike the three before it.
                    status: controlCenter.focusEnabled ? "Notifications silenced" : "Notifications on"
                    on: controlCenter.focusEnabled
                    busy: controlCenter.focusBusy
                    available: controlCenter.focusAvailable
                    onToggled: controlCenter.toggleFocus()
                }

                QuickTile {
                    index: 3
                    glyph: controlCenter.nightLightGlyph
                    label: "Night mode"
                    status: controlCenter.nightLightEnabled ? "Warm" : "Off"
                    on: controlCenter.nightLightEnabled
                    busy: controlCenter.nightLightBusy
                    onToggled: controlCenter.toggleNightLight()
                }
            }
        }

        // The rule that used to be the last ConnectivityRow's bottom border.
        // It is a separate element now because the grid's tiles have their
        // own plates and a border on the bottom pair would sit inside the
        // rounded corners rather than under them.
        Item {
            width: parent.width
            height: Metrics.px(9)

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: 1
                color: Qt.rgba(0.925, 0.925, 0.925, 0.08)
            }
        }

        Item {
            id: batteryDrawer
            // Was `(width - connectivityCardsRow.spacing) / 2`, which is how
            // this drawer inherited its half-width from the two connectivity
            // cards that used to sit above it. Those are rows now and there
            // is no card grid to line up with, so the 12 px gutter is stated
            // here instead of being read off a sibling that no longer exists.
            readonly property real cardWidth: (width - Metrics.px(12)) / 2
            readonly property real modeSlotWidth: 44
            readonly property real openDistance: controlCenter.batteryModeCardHeight
                + controlCenter.batteryDrawerContentGap

            width: parent.width
            height: controlCenter.batteryDrawerHandleHeight
                + controlCenter.batteryDrawerProgress * openDistance
            clip: true

            Rectangle {
                id: batteryModeCard
                anchors.left: parent.left
                y: -height + controlCenter.batteryDrawerProgress * height
                width: batteryDrawer.cardWidth
                height: controlCenter.batteryModeCardHeight
                radius: Metrics.px(20)
                color: "transparent"
                visible: controlCenter.tlpControlsEnabled
                opacity: controlCenter.tlpControlsEnabled ? Math.min(1, controlCenter.batteryDrawerProgress * 1.35) : 0
                clip: true

                MatteSurface {
                    anchors.fill: parent
                    radius: parent.radius
                    hovered: controlCenter.batteryModeSliderDragging
                }

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: Metrics.pad(14)
                    anchors.top: parent.top
                    anchors.topMargin: Metrics.pad(11)
                    text: "Battery"
                    color: textPrimary
                    font.pixelSize: Metrics.font(13)
                    font.family: textFontFamily
                    font.weight: Font.DemiBold
                }

                Text {
                    anchors.right: parent.right
                    anchors.rightMargin: Metrics.pad(12)
                    anchors.top: parent.top
                    anchors.topMargin: Metrics.pad(12)
                    width: Math.max(0, parent.width - 88)
                    text: controlCenter.batteryModeError.length > 0
                        ? controlCenter.batteryModeError
                        : (controlCenter.batteryModeInfoMessage.length > 0
                            ? controlCenter.batteryModeInfoMessage
                            : controlCenter.batteryModeStatusText)
                    color: controlCenter.batteryModeError.length > 0 ? IslandTheme.danger : IslandTheme.textMuted
                    horizontalAlignment: Text.AlignRight
                    font.pixelSize: Metrics.font(9)
                    font.family: textFontFamily
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                }

                Item {
                    id: batteryModeCarousel
                    anchors.left: parent.left
                    anchors.leftMargin: Metrics.pad(12)
                    anchors.right: parent.right
                    anchors.rightMargin: Metrics.pad(12)
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: Metrics.pad(8)
                    height: Metrics.px(34)
                    clip: true

                    Item {
                        id: batteryModeItems
                        width: batteryDrawer.modeSlotWidth * 3
                        height: parent.height
                        x: batteryModeCarousel.width / 2
                            - batteryDrawer.modeSlotWidth / 2
                            - controlCenter.batteryModeIndex * batteryDrawer.modeSlotWidth
                            + controlCenter.batteryModeDragOffset

                        Behavior on x {
                            enabled: !controlCenter.batteryModeSliderDragging

                            NumberAnimation {
                                duration: 180
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Motion.spring()   // FORK: was Easing.OutCubic
                            }
                        }

                        Repeater {
                            model: 3

                            delegate: Item {
                                x: index * batteryDrawer.modeSlotWidth
                                width: batteryDrawer.modeSlotWidth
                                height: batteryModeCarousel.height
                                opacity: index === controlCenter.batteryModeIndex ? 1 : 0.42

                                Behavior on opacity {
                                    NumberAnimation {
                                        duration: 140
                                        easing.type: Easing.BezierSpline
                                        easing.bezierCurve: Motion.fade()   // FORK: was Easing.OutCubic
                                    }
                                }

                                Rectangle {
                                    anchors.centerIn: parent
                                    width: index === controlCenter.batteryModeIndex ? 32 : 28
                                    height: index === controlCenter.batteryModeIndex ? 28 : 24
                                    radius: Metrics.px(12)
                                    color: index === controlCenter.batteryModeIndex ? IslandTheme.textPrimary : IslandTheme.surfaceRaised

                                    Behavior on width {
                                        NumberAnimation {
                                            duration: 140
                                            easing.type: Easing.BezierSpline
                                            easing.bezierCurve: Motion.spring()   // FORK: was Easing.OutCubic
                                        }
                                    }

                                    Behavior on height {
                                        NumberAnimation {
                                            duration: 140
                                            easing.type: Easing.BezierSpline
                                            easing.bezierCurve: Motion.spring()   // FORK: was Easing.OutCubic
                                        }
                                    }

                                    Behavior on color {
                                        ColorAnimation {
                                            duration: 140
                                        }
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        text: controlCenter.batteryModeGlyphs[index]
                                        color: index === controlCenter.batteryModeIndex ? IslandTheme.inverseSurfaceInk : IslandTheme.textSecondary
                                        font.pixelSize: index === controlCenter.batteryModeIndex ? Metrics.font(15) : Metrics.font(13)
                                        font.family: iconFontFamily
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        width: Metrics.px(22)
                        height: Metrics.px(2)
                        radius: 1
                        color: IslandTheme.textDisabled
                        opacity: 0.75
                    }

                    MouseArea {
                        anchors.fill: parent
                        property real startX: 0
                        property int startIndex: 1
                        property bool moved: false

                        function clampDrag(delta) {
                            return Math.max(-batteryDrawer.modeSlotWidth, Math.min(batteryDrawer.modeSlotWidth, delta));
                        }

                        onPressed: function(mouse) {
                            startX = mouse.x;
                            startIndex = controlCenter.batteryModeIndex;
                            moved = false;
                            controlCenter.batteryModeInfoMessage = "";
                            controlCenter.batteryModeError = "";
                            controlCenter.batteryModeSliderDragging = true;
                            controlCenter.batteryModeDragOffset = 0;
                        }

                        onPositionChanged: function(mouse) {
                            if (!pressed)
                                return;

                            const delta = mouse.x - startX;
                            if (!moved && Math.abs(delta) < 4)
                                return;

                            moved = true;
                            controlCenter.batteryModeDragOffset = clampDrag(delta);
                        }

                        onReleased: function(mouse) {
                            const delta = mouse.x - startX;
                            let nextIndex = startIndex;

                            if (delta <= -18)
                                nextIndex = Math.min(2, startIndex + 1);
                            else if (delta >= 18)
                                nextIndex = Math.max(0, startIndex - 1);
                            else if (mouse.x < width / 2 - batteryDrawer.modeSlotWidth / 2)
                                nextIndex = Math.max(0, startIndex - 1);
                            else if (mouse.x > width / 2 + batteryDrawer.modeSlotWidth / 2)
                                nextIndex = Math.min(2, startIndex + 1);

                            controlCenter.batteryModeSliderDragging = false;
                            controlCenter.batteryModeDragOffset = 0;
                            controlCenter.selectBatteryMode(nextIndex);
                        }

                        onCanceled: {
                            controlCenter.batteryModeSliderDragging = false;
                            controlCenter.batteryModeDragOffset = 0;
                            controlCenter.setBatteryModeVisualIndex(controlCenter.batteryModeAppliedIndex, true);
                        }
                    }
                }
            }

            Rectangle {
                id: quickTogglesCard
                // Same 12 px gutter batteryDrawer.cardWidth is derived from.
                // Was reading connectivityCardsRow.spacing, which vanished
                // with the connectivity cards — and an undefined id inside a
                // binding is only a runtime ReferenceError, so the config
                // still loaded clean and this card simply sat at x 0.
                x: controlCenter.tlpControlsEnabled ? batteryDrawer.cardWidth + Metrics.px(12) : 0
                y: batteryModeCard.y
                width: batteryDrawer.cardWidth
                height: controlCenter.batteryModeCardHeight
                radius: Metrics.px(20)
                color: "transparent"
                opacity: Math.min(1, controlCenter.batteryDrawerProgress * 1.35)
                clip: true
                readonly property real toggleIconTop: 12
                readonly property real toggleIconBoxHeight: 32
                readonly property real toggleLabelTop: 55

                Behavior on x {
                    NumberAnimation {
                        duration: 180
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Motion.spring()   // FORK: was Easing.OutCubic
                    }
                }

                MatteSurface {
                    anchors.fill: parent
                    radius: parent.radius
                    hovered: focusButtonMouse.containsMouse || nightLightButtonMouse.containsMouse
                    pressed: focusButtonMouse.pressed || nightLightButtonMouse.pressed
                }

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.verticalCenter: parent.verticalCenter
                    width: 1
                    height: parent.height - 34
                    radius: 1
                    color: IslandTheme.hairline
                }

                Item {
                    id: focusButton
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: parent.width / 2
                    property real slashProgress: controlCenter.focusEnabled ? 1 : 0
                    property color iconColor: controlCenter.focusEnabled ? IslandTheme.textPrimary : IslandTheme.textSecondary

                    // The click is already refused when the daemon cannot be
                    // reached; this is what SAYS so. Without it the row
                    // refuses presses while looking exactly like a working
                    // one, which is the same "dead control that looks alive"
                    // failure the swaync rewrite above exists to end — moved
                    // from the state to the pointer rather than removed.
                    //
                    // Two levels, not one. Busy is a flicker between a press
                    // and the daemon answering; unavailable is a standing
                    // condition that will still be true next time. Dimming
                    // both to 0.5 would say "wait" where it means "cannot",
                    // so unavailable goes further down than anything else in
                    // this card ever does, which is what reads as disabled
                    // rather than as slow.
                    // NOT readonly, and that is not an oversight. A Behavior
                    // WRITES the property it animates, so `readonly` here
                    // fails with "Invalid property assignment: contentOpacity
                    // is a read-only property" — and that failure takes down
                    // the whole shell load, not just this card, because the
                    // error propagates up through ControlCenterLayer to
                    // DynamicIslandWindow to shell.qml. The binding below
                    // still owns the value; the Behavior only intercepts the
                    // transitions between the values the binding produces.
                    property real contentOpacity: !controlCenter.focusAvailable
                        ? 0.32
                        : (controlCenter.focusBusy ? 0.5 : 1.0)

                    // Animated because focusAvailable is discovered rather
                    // than known: the probe answers a frame or two after the
                    // panel opens, and a row that snapped to 32% on the
                    // second frame would read as a rendering glitch. fade(),
                    // not spring() — opacity is clamped, per Motion.js.
                    Behavior on contentOpacity {
                        NumberAnimation {
                            duration: Motion.fadeInDuration()
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Motion.fade()
                        }
                    }

                    Behavior on slashProgress {
                        NumberAnimation {
                            duration: 830
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Motion.fade()   // FORK: was Easing.OutCubic
                        }
                    }

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: Metrics.pad(4)
                        radius: Metrics.px(16)
                        color: focusButtonMouse.containsMouse ? IslandTheme.alpha(IslandTheme.ink, 0.03) : "transparent"

                        Behavior on color {
                            ColorAnimation {
                                duration: IslandTheme.durationFast
                            }
                        }
                    }

                    MouseArea {
                        id: focusButtonMouse
                        anchors.fill: parent
                        // Unavailable is a THIRD reason to refuse the click,
                        // beside busy. Previously there was no such reason,
                        // because there was no way to know — the row happily
                        // accepted presses that ran a binary that did not
                        // exist and reported the failure as "now off".
                        enabled: !controlCenter.focusBusy && controlCenter.focusAvailable
                        hoverEnabled: true
                        onClicked: controlCenter.toggleFocus()
                    }

                    Item {
                        id: focusIconSlot
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: quickTogglesCard.toggleIconTop
                        width: parent.width
                        height: quickTogglesCard.toggleIconBoxHeight

                        Shape {
                            id: focusIcon
                            anchors.centerIn: parent
                            width: Metrics.px(24)
                            height: Metrics.px(24)
                            scale: focusButtonMouse.pressed ? 0.94 : 1.0
                            opacity: focusButton.contentOpacity
                            preferredRendererType: Shape.CurveRenderer

                            Behavior on scale {
                                NumberAnimation {
                                    duration: 120
                                    easing.type: Easing.BezierSpline
                                    easing.bezierCurve: Motion.spring()   // FORK: was Easing.OutCubic
                                }
                            }

                            ShapePath {
                                fillColor: "transparent"
                                strokeColor: focusButton.iconColor
                                strokeWidth: 2
                                capStyle: ShapePath.RoundCap
                                joinStyle: ShapePath.RoundJoin

                                PathSvg {
                                    path: "M22 17H2a3 3 0 0 0 3-3V9a7 7 0 0 1 14 0v5a3 3 0 0 0 3 3zm-8.27 4a2 2 0 0 1-3.46 0"
                                }
                            }

                            ShapePath {
                                fillColor: "transparent"
                                strokeColor: focusButton.iconColor
                                strokeWidth: 2.1
                                capStyle: ShapePath.RoundCap
                                joinStyle: ShapePath.RoundJoin

                                PathMove {
                                    x: 1
                                    y: 1
                                }

                                PathLine {
                                    x: 1 + 22 * focusButton.slashProgress
                                    y: 1 + 22 * focusButton.slashProgress
                                }
                            }
                        }
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: quickTogglesCard.toggleLabelTop
                        width: parent.width
                        text: "Silent"
                        color: controlCenter.focusEnabled ? IslandTheme.textPrimary : IslandTheme.textMuted
                        horizontalAlignment: Text.AlignHCenter
                        font.pixelSize: Metrics.font(10)
                        font.family: textFontFamily
                        font.weight: Font.Medium
                        elide: Text.ElideRight
                        opacity: focusButton.contentOpacity
                    }
                }

                Item {
                    id: nightLightButton
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: parent.width / 2

                    MouseArea {
                        id: nightLightButtonMouse
                        anchors.fill: parent
                        enabled: !controlCenter.nightLightBusy
                        hoverEnabled: true
                        onClicked: controlCenter.toggleNightLight()
                    }

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: Metrics.pad(4)
                        radius: Metrics.px(16)
                        color: nightLightButtonMouse.containsMouse ? IslandTheme.alpha(IslandTheme.ink, 0.03) : "transparent"

                        Behavior on color {
                            ColorAnimation {
                                duration: IslandTheme.durationFast
                            }
                        }
                    }

                    Item {
                        id: nightLightIconSlot
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: quickTogglesCard.toggleIconTop
                        width: parent.width
                        height: quickTogglesCard.toggleIconBoxHeight

                        Text {
                            anchors.centerIn: parent
                            anchors.verticalCenterOffset: 1
                            text: controlCenter.nightLightGlyph
                            color: IslandTheme.alpha(IslandTheme.inverseSurfaceInk, 0.27)
                            font.pixelSize: Metrics.font(29)
                            font.family: iconFontFamily
                            scale: nightLightButtonMouse.pressed ? 0.94 : 1.0
                            opacity: controlCenter.nightLightBusy ? 0.1 : 0.22
                        }

                        Text {
                            id: nightLightIcon
                            anchors.centerIn: parent
                            text: controlCenter.nightLightGlyph
                            color: controlCenter.nightLightEnabled ? IslandTheme.textPrimary : IslandTheme.textSecondary
                            font.pixelSize: Metrics.font(29)
                            font.family: iconFontFamily
                            scale: nightLightButtonMouse.pressed ? 0.94 : 1.0
                            opacity: controlCenter.nightLightBusy ? 0.5 : 1.0

                            Behavior on scale {
                                NumberAnimation {
                                    duration: 120
                                    easing.type: Easing.BezierSpline
                                    easing.bezierCurve: Motion.spring()   // FORK: was Easing.OutCubic
                                }
                            }
                        }
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: quickTogglesCard.toggleLabelTop
                        width: parent.width
                        text: "Night mode"
                        color: controlCenter.nightLightEnabled ? IslandTheme.textPrimary : IslandTheme.textMuted
                        horizontalAlignment: Text.AlignHCenter
                        font.pixelSize: Metrics.font(10)
                        font.family: textFontFamily
                        font.weight: Font.Medium
                        elide: Text.ElideRight
                        opacity: controlCenter.nightLightBusy ? 0.5 : 1.0
                    }
                }
            }

            Rectangle {
                id: batteryDrawerTunnelShade
                anchors.left: parent.left
                anchors.top: parent.top
                width: batteryDrawer.cardWidth
                height: Math.max(1, controlCenter.batteryDrawerContentGap * 0.35)
                z: 6
                opacity: Math.min(0.34, controlCenter.batteryDrawerProgress * 0.45)
                gradient: Gradient {
                    GradientStop {
                        position: 0
                        color: IslandTheme.alpha(IslandTheme.inverseSurfaceInk, 0.60)
                    }
                    GradientStop {
                        position: 1
                        color: "transparent"
                    }
                }
            }

            Item {
                id: batteryDrawerHandle
                anchors.left: parent.left
                anchors.right: parent.right
                y: controlCenter.batteryDrawerProgress * batteryDrawer.openDistance
                height: controlCenter.batteryDrawerHandleHeight
                z: 10

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: Metrics.px(8)
                    width: Metrics.px(48)
                    height: Metrics.px(5)
                    radius: Metrics.px(3)
                    color: controlCenter.batteryDrawerOpen ? IslandTheme.textSecondary : IslandTheme.textMuted
                    opacity: 0.88
                }

                MouseArea {
                    id: batteryDrawerHandleArea
                    anchors.fill: parent
                    property real pointerGrabOffset: 0
                    property bool moved: false
                    property bool suppressClick: false

                    function pointerY(mouse) {
                        return batteryDrawerHandle.mapToItem(controlCenter, mouse.x, mouse.y).y;
                    }

                    function itemTop(item) {
                        return item.mapToItem(controlCenter, 0, 0).y;
                    }

                    onPressed: function(mouse) {
                        batteryDrawerSettleTimer.stop();
                        controlCenter.batteryDrawerSettling = false;
                        pointerGrabOffset = pointerY(mouse) - itemTop(batteryDrawerHandle);
                        moved = false;
                        suppressClick = false;
                        controlCenter.batteryDrawerDragging = true;
                    }

                    onPositionChanged: function(mouse) {
                        const nextHandleY = pointerY(mouse) - pointerGrabOffset - itemTop(batteryDrawer);
                        if (!moved && Math.abs(nextHandleY - batteryDrawerHandle.y) < 4)
                            return;

                        moved = true;
                        suppressClick = true;
                        controlCenter.batteryDrawerProgress = controlCenter.clamp01(nextHandleY / batteryDrawer.openDistance);
                    }

                    onReleased: {
                        controlCenter.batteryDrawerDragging = false;
                        if (moved)
                            controlCenter.setBatteryDrawerOpen(controlCenter.batteryDrawerProgress >= 0.55);
                    }

                    onCanceled: {
                        controlCenter.batteryDrawerDragging = false;
                        controlCenter.setBatteryDrawerOpen(controlCenter.batteryDrawerOpen);
                    }

                    onClicked: {
                        if (suppressClick) {
                            suppressClick = false;
                            return;
                        }

                        controlCenter.toggleBatteryDrawer();
                    }
                }
            }
        }

        ControlSliderCard {
            id: brightnessCard
            width: parent.width
            // 76 -> 62. The old card carried a 30 px pill track plus its own
            // padding; the fader is a label row and a 2 px thread, so the
            // remaining 14 px was empty card.
            height: Metrics.px(62)
            accentColor: controlCenter.accentColor
            title: "Display"
            iconText: controlCenter.brightnessIconGlyph
            iconFontFamily: controlCenter.iconFontFamily
            textFontFamily: controlCenter.textFontFamily
            value: controlCenter.displayedBrightness
            knobSize: controlCenter.sliderKnobSize
            moduleColor: controlCenter.moduleColor
            moduleHover: controlCenter.moduleHover
            trackColor: controlCenter.trackColor
            textPrimary: controlCenter.textPrimary
            textSecondary: controlCenter.textSecondary

            onInteractionStarted: {
                if (controlCenter.sliderIntroPending) {
                    sliderIntroTimer.stop();
                    controlCenter.sliderIntroPending = false;
                    controlCenter.displayedBrightness = controlCenter.localBrightness;
                    controlCenter.displayedVolume = controlCenter.localVolume;
                }
            }
            onValueMoved: function(value) {
                controlCenter.queueBrightness(value);
            }
            onCommitRequested: {
                brightnessApplyTimer.stop();
                controlCenter.flushBrightness(true);
            }
            onCancelRequested: SystemServices.requestBrightness()
        }

        ControlSliderCard {
            id: volumeCard
            width: parent.width
            height: Metrics.px(62)
            accentColor: controlCenter.accentColor
            title: "Sound"
            iconText: controlCenter.volumeIconGlyph
            iconFontFamily: controlCenter.iconFontFamily
            textFontFamily: controlCenter.textFontFamily
            value: controlCenter.displayedVolume
            knobSize: controlCenter.sliderKnobSize
            moduleColor: controlCenter.moduleColor
            moduleHover: controlCenter.moduleHover
            trackColor: controlCenter.trackColor
            textPrimary: controlCenter.textPrimary
            textSecondary: controlCenter.textSecondary

            onInteractionStarted: {
                if (controlCenter.sliderIntroPending) {
                    sliderIntroTimer.stop();
                    controlCenter.sliderIntroPending = false;
                    controlCenter.displayedBrightness = controlCenter.localBrightness;
                    controlCenter.displayedVolume = controlCenter.localVolume;
                }
            }
            onValueMoved: function(value) {
                controlCenter.queueVolume(value);
            }
            onCommitRequested: {
                volumeApplyTimer.stop();
                controlCenter.flushVolume(true);
            }
            onCancelRequested: SystemServices.requestVolume()
        }
    }

}
