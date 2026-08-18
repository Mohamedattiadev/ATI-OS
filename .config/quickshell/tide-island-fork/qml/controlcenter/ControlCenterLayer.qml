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
    // FORK: 400 -> 1500, and it is now a CEILING rather than the gate.
    //
    // What this gate is for: while it is pending the two `displayed*`
    // Behaviors are disabled, so an assignment SNAPS instead of animating.
    // That is right — the first reading should appear, not slide in from
    // wherever the slider happened to be.
    //
    // What went wrong is that it closed on a clock while the value it was
    // waiting for arrives on a process. `volumeLevel` and `brightnessLevel`
    // default to -1 for "not known yet" and are filled in by SystemServices
    // asynchronously; measured, that lands WELL after 400 ms. So the gate
    // opened first, and the real reading then arrived into an enabled
    // Behavior and animated the slider away from a value that had never
    // been true.
    //
    // Caught by differencing two frames of one control-centre open rather
    // than by timing it: at +621 ms against +990 ms the brightness bar is
    // still travelling, long after the shape and the content fade are done.
    // It is not a flourish — it is a stale value being corrected in public.
    //
    // HONESTLY: this is a correctness fix and NOT the cure for the panel's
    // ~800 ms settle. Measured before and after, same harness, warm loader:
    // 806 ms against 804 ms. The slider was one of two things still moving
    // late and it was the smaller one. The other — the whole content block
    // below the clock shifting ~17 px vertically somewhere between +560 ms
    // and +1080 ms, on every open, warm or cold — is still unexplained and
    // is the one that actually owns the number. It is not morphDurationFor
    // (760 vs 520 measured identical), not this gate, and not the loader
    // building cold (second and third opens measure the same).
    //
    // The gate now closes on DATA (see onSliderLevelsKnownChanged), so the
    // first real reading snaps. This number is only the fallback for a
    // reading that never comes, and it can be generous because the cards
    // stay interactive throughout — `enabled` here is the Behavior's, not
    // the control's, and a drag cancels the intro explicitly.
    property int sliderIntroDelay: 1500

    // Both readings present. -1 is SystemServices' "not known yet" sentinel
    // and is exactly what syncBrightnessFromLevel/syncVolumeFromLevel bail
    // on, so this is the same test they already make, hoisted to where the
    // gate can see it.
    readonly property bool sliderLevelsKnown: brightnessLevel >= 0 && volumeLevel >= 0

    onSliderLevelsKnownChanged: {
        if (!sliderLevelsKnown || !sliderIntroPending || !showCondition)
            return;

        localBrightness = clamp01(brightnessLevel);
        localVolume = clamp01(volumeLevel);
        pendingBrightness = localBrightness;
        pendingVolume = localVolume;
        lastAppliedBrightness = localBrightness;
        lastAppliedVolume = localVolume;

        // Assigned while sliderIntroPending is STILL true, which is the
        // whole point: the Behaviors are disabled, so these two land
        // instantly rather than animating from the placeholder.
        displayedBrightness = localBrightness;
        displayedVolume = localVolume;

        sliderIntroTimer.stop();
        sliderIntroPending = false;
    }
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
    property bool nightLightEnabled: false
    property bool nightLightBusy: false
    property int nightLightTemperature: 4500
    // The shell root, which owns the night-light mechanism. Null only in a
    // throwaway instance with no shell root; toggleNightLight() says so out
    // loud rather than presenting a tile that does nothing.
    property var nightLightController: null
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
    readonly property real roundToggleButtonSize: 58
    readonly property real roundToggleButtonGap: 18
    // ---- WHAT THE FOOTER COSTS, WRITTEN AS THE DIFFERENCE IT IS ----
    //
    // The panel used to end at a pad(12) bottom margin; it now ends at the
    // chrome's gap plus its key-hint strip. Spelt as the DELTA rather than
    // folded into a new constant so that the height this panel asks the island
    // for still visibly derives from the same px(320) it always did, and so
    // that changing chromeFooter() moves this panel with it.
    readonly property real chromeFooterCost:
        Metrics.chromeGap() + Metrics.chromeFooter() - Metrics.pad(12)

    // Was `12 + batteryDrawerHandleHeight + chromeFooterCost + <the drawer's
    // own open progress>` — the battery mode drawer's height budget, read
    // by DynamicIslandWindow.qml when sizing the capsule. The drawer is
    // gone (PROMPT-NEXT.md item 10); kept as a name rather than deleted
    // outright because the music player embed the same item asks for is
    // about to need this exact plumbing for its own height, at which point
    // these two stop being "12 + chromeFooterCost" and start being
    // "12 + chromeFooterCost + the player's own height".
    readonly property real controlCenterExtraHeight: 12 + chromeFooterCost
    readonly property real controlCenterMaximumExtraHeight: 12 + chromeFooterCost
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

    function clamp01(value) {
        return Math.max(0, Math.min(1, value));
    }

    function trimString(value) {
        if (value === undefined || value === null) return "";
        return String(value).trim();
    }

    // FORK: the row asks, the shell root does.
    //
    // The two Processes that used to live in this file moved to shell.qml.
    // They are the only way to reach night light, and this layer is loaded
    // only while the control-centre panel is on screen — so owning them here
    // meant the feature could not be bound to a key or driven by a script,
    // and its owner was a component that may never have been instantiated.
    // See the block above shell.qml's setNightLight().
    //
    // This layer still owns the ROW: its busy state, its tile, and the
    // notification, which it raises from nightLightResult so that clicking
    // the tile and calling `qs ipc call nightlight toggle` look identical.
    function toggleNightLight() {
        if (nightLightBusy)
            return;

        if (!nightLightController) {
            // Loudly, rather than a dead tile. A throwaway instance with no
            // shell root is the only way to get here.
            requestNotification("Night Light", "Night Light unavailable",
                                "No shell controller — night light cannot be driven.");
            return;
        }

        nightLightBusy = true;
        nightLightController.toggleNightLight();
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

    // ---- THE MARGIN MOVED INTO PanelChrome ----
    //
    // This was `anchors.margins: Metrics.pad(12)`, and combined with the
    // header's own `leftMargin: Metrics.pad(6)` it put the clock at 18 from
    // the capsule — which is exactly Metrics.chromePadX(), arrived at by two
    // numbers that did not know about each other. The sliders, which took the
    // root margin and added nothing, sat at 12.
    //
    // PanelChrome owns the inset now, so both land on 18 and the panel gains a
    // footer where the bottom margin used to be. The sliders move in by 6.
    anchors.fill: parent
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
            // its confirm step. The grid cursor is a highlight, not a mode,
            // so it costs the cheapest Escape; the battery drawer that used
            // to sit between it and the panel is gone (item 10).
            if (quickGrid.cursor >= 0)
                quickGrid.cursor = -1;
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

    // FORK: the night-light Processes that stood here moved to shell.qml.
    //
    // They are the whole mechanism, and this layer only exists while the
    // control-centre panel is open — so as long as they lived here, night
    // light could not be bound to a key, could not be driven by a script,
    // and had an owner that may never have been instantiated. The full
    // account, including why the gammastep fallback was deleted rather than
    // demoted, is in shell.qml above setNightLight().
    //
    // What stays here is the ROW. The controller does the work and reports
    // through nightLightResult; the notification is raised from this side so
    // that clicking the tile and calling the IPC produce the same visible
    // result.
    Connections {
        target: controlCenter.nightLightController

        function onNightLightResult(ok, enabled, message) {
            controlCenter.nightLightBusy = false;
            controlCenter.nightLightEnabled = enabled;
            controlCenter.nightLightModeChanged(enabled);

            if (!ok) {
                controlCenter.requestNotification("Night Light", "Night Light unavailable", message);
                return;
            }

            if (enabled) {
                controlCenter.requestNotification("Night Light", "Night Light enabled",
                                                  controlCenter.nightLightTemperature + "K");
            } else {
                controlCenter.requestNotification("Night Light", "Night Light disabled", "");
            }
        }
    }


    Connections {
        target: SystemServices

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
        id: bluetoothScanStopTimer
        interval: 8000
        repeat: false
        onTriggered: {
            if (controlCenter.bluetoothAdapter && controlCenter.bluetoothAdapter.discovering)
                controlCenter.bluetoothAdapter.discovering = false;
            controlCenter.bluetoothInfoMessage = "";
        }
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

    // ---- THE CHROME, SHARED WITH NINETEEN OTHER SURFACES ----
    //
    // This panel keeps its own header — see the hero-number note below, which
    // is why PanelChrome has a replaceable header slot at all — and takes the
    // rules, the footer and the four content-geometry numbers from the shared
    // component.
    //
    // The key hints are NEW. This panel is opened by a keyboard chord, has
    // arrows and hjkl, Space/Enter to toggle, Right to open a list and an
    // Escape that unwinds cursor -> drawer -> panel, and it had no legend for
    // any of it — the one panel in the shell with the richest keyboard model
    // and the only one of the nine that never got a hint strip.
    PanelChrome {
        id: chrome
        textFontFamily: controlCenter.textFontFamily
        heroHeaderHeight: Metrics.px(42)
        // A hero block needs more air under it than a 10 px label does — the
        // old layout gave it the Column's own px(12) spacing. Declared here
        // rather than added to the Column's y so the chrome can centre its
        // header rule in the gap; see PanelChrome.bodyOffset.
        bodyOffset: Metrics.px(8)
        hints: [
            { key: "h/l", label: "move" },
            { key: "Space", label: "toggle" },
            { key: "→", label: "list" },
            { key: "q", label: "close" }
        ]

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
            // The header SLOT, so `parent` is already inset by chrome.padX and
            // sits at chromeTop(). The pad(6) and pad(2) edge margins that used
            // to be here are gone with it — they were the second half of the
            // 12 + 6 that added up to 18.
            anchors.fill: parent

            Column {
                anchors.left: parent.left
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
    }

    // The body, in the region the chrome reserves for it. The extra air under
    // the hero header is chrome.bodyOffset and is already in contentY.
    Column {
        x: chrome.contentX
        y: chrome.contentY
        width: chrome.contentWidth
        spacing: Metrics.px(12)

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
        //  THE QUICK ROW
        // ============================================================
        //
        // FORK. This is the second pass at the same problem and the first
        // one is worth recording, because the mistake was a process mistake
        // rather than a taste one.
        //
        // The panel originally showed two full-width rows, Wi-Fi and
        // Bluetooth, and nothing else — Focus and Night mode existed, fully
        // wired, but lived inside the BATTERY DRAWER, which defaults closed.
        // Pass one promoted all four into a 2x2 grid of large tiles. That
        // fixed the real bug (the toggles are reachable now) and produced a
        // worse-looking panel: four 76 px slabs, each holding a 17 px glyph
        // and two short strings, so most of every tile was empty. Rejected
        // on sight, correctly.
        //
        // The lesson is that the grid was designed in an ASCII sketch, where
        // a tile is as big as the words inside it. On a real 1366 px panel a
        // half-width tile is 300 px wide and the words do not grow to fill
        // it. A sketch cannot show you dead space; only a capture can.
        //
        // WHAT THIS DOES INSTEAD. The toggles stop being cards and become
        // what they actually are — four buttons. A 44 px square each, in one
        // row, icon centred, name underneath in the caption register. That
        // is the smallest form that still gives a comfortable pointer target
        // (44 is the usual floor for a touch/pointer hit area, and it is
        // also exactly `iconBox * 2 + padding` here), and it returns roughly
        // 90 px of panel height to the sliders, which are the controls
        // actually used every day.
        //
        // WHAT IS LOST, DELIBERATELY. The per-tile status line goes —
        // "TDV-OGRENCI-ORTAK", "Scanning", "Notifications on". A 44 px
        // button has no room for it and shrinking the type to fit is how
        // panels end up with 8 px text nobody reads. The network name still
        // has a home: it is one chevron away, in the list the tile opens,
        // where it is the heading rather than a subtitle. What the button
        // must convey is ON or OFF, and the fill says that at a glance from
        // across the room, which the old subtitle never did.
        Item {
            id: quickGrid
            width: parent.width
            height: quickRow.height

            // -1 is "the pointer is driving". Any motion key adopts the row
            // and lights a button; Escape hands it back. Kept here rather
            // than on the root because the root's Keys handler is shared
            // with the battery drawer and the connectivity overlays, and a
            // cursor that survived those would light a button behind an
            // open list.
            property int cursor: -1
            readonly property int count: 4

            // One row now, so vertical motion has nothing to move BETWEEN
            // and is folded onto the horizontal axis. j/k and Up/Down still
            // work rather than being dead keys — they just step along the
            // row, which is what someone pressing them here means.
            function moveCursor(dx, dy) {
                if (cursor < 0) {
                    cursor = 0;
                    return;
                }
                const step = dx !== 0 ? dx : dy;
                cursor = Math.max(0, Math.min(count - 1, cursor + step));
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
            // fall through and let the key mean movement on a button with no
            // list, rather than silently swallowing it.
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

            component QuickButton: Item {
                id: qb

                property string glyph: ""
                property string label: ""
                property bool on: false
                property bool busy: false
                property bool available: true
                property bool hasList: false
                property bool listOpen: false
                property int index: -1

                signal toggled()
                signal listRequested()

                readonly property bool cursored: quickGrid.cursor === qb.index
                readonly property bool interactive: qb.available && !qb.busy

                width: Metrics.px(44)
                height: buttonPlate.height + Metrics.px(5) + qbLabel.height

                HoverHandler {
                    id: qbHover
                    enabled: qb.interactive
                }

                Rectangle {
                    id: buttonPlate
                    width: parent.width
                    height: Metrics.px(44)
                    radius: Metrics.px(14)

                    // ---- DEPTH, WHICH THE FLAT VERSION HAD NONE OF ----
                    //
                    // "The whole thing feels flat" was the third complaint
                    // and it is a separate fault from the sizing. Every
                    // surface in the old panel was one cream wash at one
                    // alpha on one background, so nothing sat in front of
                    // anything.
                    //
                    // Off is a RAISED plate: a lighter fill with a hairline
                    // top edge, which is the cheapest honest way to suggest
                    // a light source above. On is the accent, near-solid, so
                    // a lit button is unmistakably a different material and
                    // not merely a slightly bluer rectangle.
                    //
                    // The two off-state fills were `Qt.rgba(0.925, 0.925,
                    // 0.925, 0.105)` and the same at 0.06 — a cream wash,
                    // written as a literal, which is the one thing a shell
                    // with 45 derived colour roles must not do. It is the
                    // "white" problem in another spelling: a light wash over a
                    // LIGHT surface is not raised, it is invisible, and
                    // mono-light is a real palette on this machine.
                    //
                    // surfaceRaised / surfaceRaisedHover are 7% and 12% toward
                    // the ink, i.e. the same two steps in the direction that is
                    // actually "up" for whatever surface is underneath.
                    color: qb.on
                        ? IslandTheme.alpha(controlCenter.accentColor, 0.92)
                        : (qbHover.hovered
                            ? IslandTheme.surfaceRaisedHover
                            : IslandTheme.surfaceRaised)
                    opacity: qb.available ? 1 : 0.35

                    Behavior on color { ColorAnimation { duration: Motion.controlDuration() } }
                    Behavior on opacity { NumberAnimation { duration: Motion.controlDuration() } }

                    // The top-edge highlight. Inset by the radius so it does
                    // not run past the curve and read as a stray line, and
                    // hidden when the button is lit — a raised edge on a
                    // solid accent looks like a rendering seam.
                    Rectangle {
                        visible: !qb.on
                        anchors.top: parent.top
                        anchors.topMargin: 1
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width - parent.radius
                        height: 1
                        // Toward the INK, not toward white. A highlight is
                        // "the side the light comes from"; on a light surface
                        // that direction is darker, not brighter, and
                        // `IslandTheme.alpha(IslandTheme.ink, 0.07)` gets it backwards there.
                        color: IslandTheme.alpha(IslandTheme.ink, 0.07)
                    }

                    // The keyboard cursor. A ring OUTSIDE the fill rather
                    // than a border on it, so it reads at a glance on both
                    // the lit and unlit state — a 1 px border inside a solid
                    // accent plate is invisible.
                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width + Metrics.px(6)
                        height: parent.height + Metrics.px(6)
                        radius: parent.radius + Metrics.px(3)
                        color: "transparent"
                        border.width: qb.cursored ? 2 : 0
                        border.color: IslandTheme.alpha(controlCenter.accentColor, 0.9)
                        visible: qb.cursored
                    }

                    Text {
                        anchors.centerIn: parent
                        text: qb.glyph
                        // Ink solved against the plate, which is now a real
                        // fill rather than an 18% tint — so on a lit button
                        // this genuinely has to be accentInk, and on an
                        // unlit one it must not be.
                        color: qb.on ? IslandTheme.accentInk : IslandTheme.textSecondary
                        font.pixelSize: Metrics.font(18)
                        font.family: controlCenter.iconFontFamily
                        opacity: qb.busy ? 0.45 : 1

                        Behavior on color { ColorAnimation { duration: Motion.controlDuration() } }
                    }

                    // The list affordance, as a corner dot rather than a
                    // chevron. At 44 px there is no room for a 30 px chevron
                    // box beside the glyph, and the dot says the same thing
                    // — "there is more behind this" — in 5 px. The whole
                    // button opens the list on a RIGHT click for the same
                    // reason, since the dot itself is too small to aim at.
                    Rectangle {
                        visible: qb.hasList
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Metrics.px(6)
                        width: Metrics.px(4)
                        height: width
                        radius: width / 2
                        color: qb.on
                            ? IslandTheme.alpha(IslandTheme.accentInk, qb.listOpen ? 0.95 : 0.5)
                            : IslandTheme.alpha(IslandTheme.textPrimary, qb.listOpen ? 0.95 : 0.35)
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: qb.interactive
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: function(mouse) {
                            quickGrid.cursor = qb.index;
                            if (mouse.button === Qt.RightButton && qb.hasList)
                                qb.listRequested();
                            else
                                qb.toggled();
                        }
                    }
                }

                Text {
                    id: qbLabel
                    anchors.top: buttonPlate.bottom
                    anchors.topMargin: Metrics.px(5)
                    // WIDER THAN THE BUTTON, centred on it. At the button's
                    // own 44 px "Bluetooth" elided to "Blueto..." — caught in
                    // a capture. A caption under an icon is not constrained
                    // by the icon's box in any other design and should not be
                    // here: the Row's 14 px gap absorbs the overhang, and the
                    // label is centred on its button so the association is
                    // unambiguous even when it is wider than what it names.
                    width: parent.width + Metrics.px(14)
                    x: -Metrics.px(7)
                    height: Metrics.px(13)
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: qb.label
                    color: qb.on ? controlCenter.textPrimary : IslandTheme.textMuted
                    font.pixelSize: Metrics.font(10)
                    font.family: controlCenter.textFontFamily
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                }
            }

            Row {
                id: quickRow
                // ---- SPREAD, NOT CENTRED ----
                //
                // Four 44 px buttons at 14 px spacing is 199 px of a ~385 px
                // panel: the row sat as an island in the middle with ~90 px
                // of nothing on each side, while the sliders directly under
                // it ran the full width. That mismatch is the other half of
                // "a lot of empty spaces no needded" — the panel looked like
                // two different layouts stacked.
                //
                // Spreading to the content width lines the first and last
                // button up with the ends of the sliders, so the panel reads
                // as one grid. The buttons keep their 44 px plate: they are
                // round, and stretching them to fill would make them ovals.
                //
                // Math.max keeps the old 14 px as a FLOOR, so a narrow panel
                // (or a fifth toggle) degrades to the previous layout instead
                // of computing a negative spacing and overlapping them.
                width: parent.width
                spacing: Math.max(Metrics.px(14),
                                  (width - 4 * Metrics.px(44)) / 3)

                QuickButton {
                    index: 0
                    glyph: controlCenter.wifiGlyph
                    label: "Wi-Fi"
                    on: controlCenter.wifiEnabled
                    busy: controlCenter.wifiBusy
                    available: controlCenter.wifiSupported && controlCenter.wifiAvailable
                    hasList: true
                    listOpen: controlCenter.wifiPanelOpen
                    onToggled: controlCenter.toggleWifiEnabled()
                    onListRequested: controlCenter.toggleConnectivityOverlay("wifi")
                }

                QuickButton {
                    index: 1
                    glyph: controlCenter.bluetoothGlyph
                    label: "Bluetooth"
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
                // with a CurveRenderer and an animated slash — a lot of
                // machinery for an 18 px mark, and the only icon in the
                // panel not coming from the icon font, so also the only one
                // that would not follow a font change.
                //
                // The pair is written as \u escapes and NOT as literal
                // private-use characters. Same codepoints, same order —
                // U+F1F6 bell-slash when focus is on, U+F0F3 bell when it is
                // off — but a literal U+F0F3 is three bytes of private-use
                // plane that tooling can drop without saying so, and a
                // dropped glyph is invisible in a diff. nightLightGlyph two
                // tiles over is already written this way; wifiGlyph and
                // bluetoothGlyph are still literals.
                //
                // Coverage checked rather than assumed, per the rule about
                // font families falling back silently: U+F0F3 and U+F1F6 are
                // both in JetBrainsMono Nerd Font, the configured
                // iconFontFamily, confirmed with fc-list :charset=.
                //
                // This tile was REPORTED as the icon-less one and it is not:
                // magnified 3x it draws its bell correctly. At 1:1 an 18 px
                // glyph in textSecondary on an unlit plate is faint enough
                // to read as an empty square, which is a contrast finding
                // about the unlit state, not a missing asset.
                QuickButton {
                    index: 2
                    glyph: controlCenter.focusEnabled ? "\uf1f6" : "\uf0f3"
                    label: "Focus"
                    on: controlCenter.focusEnabled
                    busy: controlCenter.focusBusy
                    available: controlCenter.focusAvailable
                    onToggled: controlCenter.toggleFocus()
                }

                QuickButton {
                    index: 3
                    glyph: controlCenter.nightLightGlyph
                    label: "Night"
                    on: controlCenter.nightLightEnabled
                    busy: controlCenter.nightLightBusy
                    onToggled: controlCenter.toggleNightLight()
                }
            }
        }

        // PROMPT-NEXT.md item 10: "no need for the battery thing... control
        // center should be more minimal and simpler." The battery mode
        // drawer (its handle, the pull gesture, the three-mode carousel,
        // the TLP integration behind it) lived here — see
        // `git show HEAD~1:.config/quickshell/tide-island-fork/qml/controlcenter/ControlCenterLayer.qml`
        // for the full ~600 lines if TLP battery-mode switching is wanted
        // back some other way. `controlCenterExtraHeight` and
        // `controlCenterMaximumExtraHeight`, which this fed into the
        // capsule's own sizing in DynamicIslandWindow.qml, are removed in
        // the same commit — see there for what depended on them.

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
