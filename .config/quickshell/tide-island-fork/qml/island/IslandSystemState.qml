import QtQuick
import IslandBackend
import Quickshell.Io

Item {
    id: root

    visible: false
    width: 0
    height: 0

    // FORK: `rawPercent` is a fourth argument, and it is additive on purpose.
    // A QML signal handler may declare FEWER parameters than the signal
    // carries, so every existing `function(icon, progress, text)` handler
    // keeps working untouched; only the emit sites below had to change.
    //
    // It exists because `progress` is a 0..1 quantity to be PLOTTED, and
    // above 100% volume that is a lossy thing to read a number back out of:
    // 125%, 120% and 114% are all progress == 1.0, so a readout derived from
    // progress says "100%" for every one of them. The arc genuinely cannot
    // show more than a full circle; the LABEL can, and should, tell the
    // truth. -1 means "no raw value, derive the label from progress" and is
    // what the non-gauge callers (battery, bluetooth) pass.
    signal transientRequested(string icon, real progress, string text, real rawPercent)

    property var configuredLeftSwipeItems: []
    property string timeText: "00:00"
    property string dateText: "Mon, Jan 01"
    property int currentWorkspace: 1
    property bool customSwipeActive: false
    property bool lyricsCavaActive: false

    readonly property var configuredLeftSwipeIds: buildNormalizedSwipeItemIds(configuredLeftSwipeItems)
    readonly property bool usesSystemStatsModule: configuredLeftSwipeIds.indexOf("cpu") !== -1
        || configuredLeftSwipeIds.indexOf("ram") !== -1
    readonly property bool usesStorageModule: configuredLeftSwipeIds.indexOf("storage") !== -1
    readonly property bool usesCavaModule: configuredLeftSwipeIds.indexOf("cava") !== -1
    readonly property bool hasCustomLeftItems: customLeftItems.length > 0
    readonly property string systemServicesClientId: "island-system-state-" + Math.random().toString(36).slice(2)
    readonly property string defaultStatusIcon: "\ud83c\udfa7"
    readonly property string volumeStatusIcon: "\u{F057E}"
    readonly property string muteStatusIcon: "\u{F075F}"
    readonly property string brightnessLowStatusIcon: "\u{F00DE}"
    readonly property string brightnessMediumStatusIcon: "\u{F00DF}"
    readonly property string brightnessHighStatusIcon: "\u{F00E0}"
    readonly property string chargingStatusIcon: "\uf0e7"
    readonly property string dischargingStatusIcon: "\uf244"
    readonly property string cpuStatusIcon: "\u{F035B}"
    readonly property string ramStatusIcon: "\u{F061A}"
    readonly property string bluetoothStatusIcon: "\u{F02CB}"

    property int batteryCapacity: SysBackend.batteryCapacity
    property bool isCharging: SysBackend.batteryStatus === "Charging" || SysBackend.batteryStatus === "Full"
    property real currentVolume: -1
    property bool isMuted: false
    property real currentBrightness: -1
    property real currentCpuUsage: -1
    property real currentRamUsage: -1
    property var cavaLevels: [0, 0, 0, 0, 0, 0, 0, 0]
    property real currentStorageUsage: -1
    readonly property string storageStatusIcon: "\u{F1C0}"
    property var customLeftItems: []

    property string _lastChargeStatus: SysBackend.batteryStatus
    property string _pendingVolType: ""
    property real _pendingVolVal: 0.0
    property string _lastVolType: ""
    property real _lastVolVal: -1.0
    // The volume as PipeWire reports it, 0..150+, NOT clamped to the ring's
    // 0..1. Two separate gates below ask "did the volume actually change?",
    // and both used to ask it of the clamped value. Above 100% the clamp
    // pins every distinct volume to exactly 1.0, so 125% -> 120% -> 115%
    // all compared equal and the OSD never fired once — on a machine whose
    // sink sits at 125%, the volume OSD simply did not exist. The ring can
    // only PLOT 0..1, but that is a drawing limit, not a change-detection
    // one, so the test is done on these and the clamp is applied only where
    // the value is drawn.
    property real _pendingVolRaw: -1.0
    property real _lastVolRaw: -1.0
    property bool _bluetoothVolumeSuppressed: false
    property real _pendingBrightnessValue: 0.0
    property string _customLeftItemsSignature: ""

    onConfiguredLeftSwipeIdsChanged: {
        syncCustomLeftItems();
        refreshMissingValues();
        updateCavaSubscription();
    }
    onUsesSystemStatsModuleChanged: refreshMissingValues()
    onUsesStorageModuleChanged: refreshMissingValues()
    onUsesCavaModuleChanged: updateCavaSubscription()
    onCustomSwipeActiveChanged: updateCavaSubscription()
    onLyricsCavaActiveChanged: updateCavaSubscription()
    onBatteryCapacityChanged: syncCustomLeftItems()
    onIsChargingChanged: syncCustomLeftItems()
    onCurrentVolumeChanged: syncCustomLeftItems()
    onIsMutedChanged: syncCustomLeftItems()
    onCurrentBrightnessChanged: syncCustomLeftItems()
    onCurrentCpuUsageChanged: syncCustomLeftItems()
    onCurrentRamUsageChanged: syncCustomLeftItems()
    onCurrentStorageUsageChanged: syncCustomLeftItems()
    onCurrentWorkspaceChanged: syncCustomLeftItems()
    onTimeTextChanged: syncCustomLeftItems()
    onDateTextChanged: syncCustomLeftItems()
    Component.onCompleted: {
        syncCustomLeftItems();
        refreshMissingValues();
        updateCavaSubscription();
    }

    Component.onDestruction: {
        SystemServices.setCavaClientActive(systemServicesClientId, false);
    }

    function statusIcon(name) {
        switch (name) {
        case "default":
            return defaultStatusIcon;
        case "volume":
            return volumeStatusIcon;
        case "mute":
            return muteStatusIcon;
        case "brightnessLow":
            return brightnessLowStatusIcon;
        case "brightnessMedium":
            return brightnessMediumStatusIcon;
        case "brightnessHigh":
            return brightnessHighStatusIcon;
        case "charging":
            return chargingStatusIcon;
        case "discharging":
            return dischargingStatusIcon;
        case "cpu":
            return cpuStatusIcon;
        case "ram":
            return ramStatusIcon;
        case "bluetooth":
            return bluetoothStatusIcon;
        default:
            return "";
        }
    }

    function normalizeSwipeItemId(rawId) {
        return String(rawId === undefined || rawId === null ? "" : rawId).trim().toLowerCase();
    }

    function listValues(rawItems) {
        if (!rawItems)
            return [];
        if (Array.isArray(rawItems))
            return rawItems;

        const length = Number(rawItems.length);
        if (!isFinite(length) || length < 0)
            return [];

        const resolved = [];
        for (let index = 0; index < Math.floor(length); index++)
            resolved.push(rawItems[index]);
        return resolved;
    }

    function formatPercentText(value) {
        return Math.round(Math.max(0, value) * 100) + "%";
    }

    function clamp01(value) {
        return Math.max(0, Math.min(1, value));
    }

    function brightnessStatusIcon(value) {
        if (value < 0.3) return statusIcon("brightnessLow");
        if (value < 0.7) return statusIcon("brightnessMedium");
        return statusIcon("brightnessHigh");
    }

    function refreshMissingValues() {
        if (currentBrightness < 0)
            SystemServices.requestBrightness();
        if (currentVolume < 0)
            SystemServices.requestVolume();
        if (usesSystemStatsModule)
            SystemServices.requestSystemStats();
        if (usesStorageModule)
            storagePollTimer.restart();
    }

    function updateCavaSubscription() {
        const active = (usesCavaModule && customSwipeActive) || lyricsCavaActive;
        SystemServices.setCavaClientActive(systemServicesClientId, active);
        if (active)
            cavaLevels = SystemServices.cavaLevels;
    }

    function buildNormalizedSwipeItemIds(rawItems) {
        const source = listValues(rawItems);
        const resolved = [];
        const seen = {};

        for (let index = 0; index < source.length; index++) {
            const itemId = normalizeSwipeItemId(source[index]);
            if (itemId === "" || seen[itemId]) continue;
            seen[itemId] = true;
            resolved.push(itemId);
        }

        return resolved;
    }

    function buildCustomSwipeItem(itemId) {
        switch (itemId) {
        case "time":
            return { id: itemId, icon: "", text: timeText };
        case "date":
            return { id: itemId, icon: "", text: dateText };
        case "battery":
            if (batteryCapacity < 0) return null;
            return {
                id: itemId,
                kind: "battery",
                level: Math.max(0, Math.min(100, batteryCapacity)),
                isCharging: isCharging,
                icon: "",
                text: Math.max(0, batteryCapacity) + "%"
            };
        case "volume":
            if (currentVolume < 0) return null;
            return {
                id: itemId,
                icon: isMuted ? statusIcon("mute") : statusIcon("volume"),
                text: formatPercentText(currentVolume)
            };
        case "brightness":
            if (currentBrightness < 0) return null;
            return {
                id: itemId,
                icon: brightnessStatusIcon(currentBrightness),
                text: formatPercentText(currentBrightness)
            };
        case "workspace":
            return { id: itemId, icon: "", text: "Workspace " + currentWorkspace };
        // FORK: `value` is the reading as a 0..100 PERCENT, carried beside the
        // already-formatted `text`. The card colours a glyph red once the
        // thing it names is in trouble, and it cannot get that out of `text`:
        // "43%" is a string, and parsing a number back out of a label that is
        // "--%" whenever the value is missing is exactly the kind of thing
        // that reads 0 and calls it healthy. -1 means "no reading yet" and is
        // what the layer tests, so a stat that has not been sampled is drawn
        // neutral rather than accidentally alarming.
        //
        // Only the three LOAD readings carry it. Volume and brightness have
        // no bad end — 100% brightness is not a fault — so giving them a
        // severity would make the colour mean nothing.
        case "cpu":
            return {
                id: itemId,
                icon: statusIcon("cpu"),
                value: currentCpuUsage >= 0 ? currentCpuUsage * 100 : -1,
                text: currentCpuUsage >= 0 ? formatPercentText(currentCpuUsage) : "--%"
            };
        case "ram":
            return {
                id: itemId,
                icon: statusIcon("ram"),
                value: currentRamUsage >= 0 ? currentRamUsage * 100 : -1,
                text: currentRamUsage >= 0 ? formatPercentText(currentRamUsage) : "--%"
            };
        case "cava":
            return { id: itemId, kind: "cava" };
        case "storage":
            return {
                id: itemId,
                icon: storageStatusIcon,
                value: currentStorageUsage >= 0 ? currentStorageUsage : -1,
                text: currentStorageUsage >= 0 ? Math.round(currentStorageUsage) + "%" : "--%"
            };
        default:
            return null;
        }
    }

    function buildCustomSwipeItems(itemIds) {
        const source = listValues(itemIds);
        const resolved = [];

        for (let index = 0; index < source.length; index++) {
            const itemId = String(source[index] || "");
            if (itemId === "") continue;

            const nextItem = buildCustomSwipeItem(itemId);
            if (nextItem) resolved.push(nextItem);
        }

        return resolved;
    }

    function customSwipeItemsSignature(items) {
        const source = listValues(items);
        let signature = "";

        for (let index = 0; index < source.length; index++) {
            const item = source[index] || {};
            signature += String(item.id || "")
                + "\u001f" + String(item.kind || "")
                + "\u001f" + String(item.icon || "")
                + "\u001f" + String(item.text || "")
                + "\u001f" + String(item.level === undefined ? "" : item.level)
                + "\u001f" + String(item.isCharging === undefined ? "" : item.isCharging)
                + "\u001e";
        }

        return signature;
    }

    function syncCustomLeftItems() {
        const nextItems = buildCustomSwipeItems(configuredLeftSwipeIds);
        const nextSignature = customSwipeItemsSignature(nextItems);
        if (nextSignature === _customLeftItemsSignature)
            return;

        _customLeftItemsSignature = nextSignature;
        customLeftItems = nextItems;
    }

    Timer {
        id: bluetoothVolumeSuppressionTimer

        interval: 2000

        onTriggered: root._bluetoothVolumeSuppressed = false
    }

    Timer {
        id: volumeDebounce

        interval: 16

        onTriggered: {
            if (root._bluetoothVolumeSuppressed) return;
            // The SECOND clamped gate. Fixing only the one in onVolumeChanged
            // would have changed nothing: above 100% every raw step still
            // arrived here as _pendingVolVal == 1.0 == _lastVolVal and was
            // dropped a second time. Both gates test the raw percentage now.
            if (root._pendingVolType !== root._lastVolType
                    || Math.abs(root._pendingVolRaw - root._lastVolRaw) > 0.05) {
                root._lastVolType = root._pendingVolType;
                root._lastVolVal = root._pendingVolVal;
                root._lastVolRaw = root._pendingVolRaw;
                root.transientRequested(
                    root._pendingVolType === "MUTE" ? root.statusIcon("mute") : root.statusIcon("volume"),
                    root._pendingVolVal,
                    "",
                    root._pendingVolRaw
                );
            }
        }
    }

    Timer {
        id: brightnessDebounce

        interval: 16

        // Brightness cannot exceed 100%, so its raw value is just the
        // fraction scaled back up — passed explicitly rather than left at -1
        // so the label goes through one code path, not two.
        onTriggered: root.transientRequested(
            root.brightnessStatusIcon(root._pendingBrightnessValue),
            root._pendingBrightnessValue,
            "",
            root._pendingBrightnessValue * 100.0
        )
    }

    Timer {
        id: systemStatsPollTimer

        interval: 3000
        repeat: true
        running: root.usesSystemStatsModule
        triggeredOnStart: true

        onTriggered: SystemServices.requestSystemStats()
    }
    Process {
        id: storagePollProcess
        command: ["df", "--output=pcent", "/"]
        running: false

        stdout: SplitParser {
            onRead: function(line) {
                const trimmed = line.trim();
                if (trimmed === "" || trimmed.indexOf("Use%") >= 0)
                    return;
                const pct = parseInt(trimmed.replace("%", ""));
                if (!isNaN(pct))
                    root.currentStorageUsage = pct;
            }
        }
    }

    Timer {
        id: storagePollTimer

        interval: 10000
        repeat: true
        running: root.usesStorageModule
        triggeredOnStart: true

        onTriggered: storagePollProcess.running = true
    }


    Connections {
        target: SystemServices

        function onBrightnessSnapshotReady(value, errorString) {
            if (errorString === "" && value >= 0)
                root.currentBrightness = root.clamp01(value);
        }

        function onVolumeSnapshotReady(value, muted, errorString) {
            if (errorString !== "" || value < 0)
                return;
            root.currentVolume = root.clamp01(value);
            root.isMuted = muted;
        }

        function onSystemStatsReady(cpuUsage, ramUsage, errorString) {
            if (errorString !== "")
                return;
            if (cpuUsage >= 0)
                root.currentCpuUsage = root.clamp01(cpuUsage);
            if (ramUsage >= 0)
                root.currentRamUsage = root.clamp01(ramUsage);
        }

        function onCavaLevelsChanged() {
            root.cavaLevels = SystemServices.cavaLevels;
        }
    }

    Connections {
        target: SysBackend

        function onVolumeChanged(volPercentage, isMuted) {
            const nextVolType = isMuted ? "MUTE" : "VOL";
            const nextVolValue = root.clamp01(volPercentage / 100.0);
            // Compared on the RAW percentage, not on nextVolValue — see
            // _pendingVolRaw. 0.05 rather than 0.001 because the unit is now
            // a percent, not a 0..1 fraction: the smallest step anything
            // here produces is `wpctl 5%-`, and a hair of float noise on a
            // percentage must not read as a real change.
            const unchanged = root.isMuted === isMuted
                && root._pendingVolType === nextVolType
                && Math.abs(root._pendingVolRaw - volPercentage) <= 0.05;

            if (unchanged)
                return;

            root._pendingVolType = nextVolType;
            root._pendingVolVal = nextVolValue;
            root._pendingVolRaw = volPercentage;
            root.currentVolume = nextVolValue;
            root.isMuted = isMuted;
            volumeDebounce.restart();
        }

        function onBatteryChanged(capacity, statusString) {
            root.batteryCapacity = capacity;
            root.isCharging = (statusString === "Charging" || statusString === "Full");
            if (root._lastChargeStatus !== "" && root._lastChargeStatus !== statusString) {
                if (statusString === "Charging")
                    root.transientRequested(root.statusIcon("charging"), -1.0, "", -1.0);
                else if (statusString === "Discharging")
                    root.transientRequested(root.statusIcon("discharging"), -1.0, "", -1.0);
            }
            root._lastChargeStatus = statusString;
        }

        function onBrightnessChanged(value) {
            root._pendingBrightnessValue = value;
            root.currentBrightness = value;
            brightnessDebounce.restart();
        }

        function onBluetoothChanged(isConnected) {
            root._bluetoothVolumeSuppressed = true;
            bluetoothVolumeSuppressionTimer.restart();
            if (isConnected)
                return;

            root.transientRequested(root.statusIcon("bluetooth"), -1.0, "Disconnected", -1.0);
        }
    }
}
