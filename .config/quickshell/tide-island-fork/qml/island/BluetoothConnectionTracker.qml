import QtQuick
import Quickshell.Bluetooth

Item {
    id: root

    visible: false
    width: 0
    height: 0

    signal newConnection(var device)

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property var devices: adapter ? adapter.devices.values : []

    property string connectedSignature: ""
    property bool baselineReady: false

    function deviceText(value) {
        return String(value === undefined || value === null ? "" : value).trim();
    }

    function deviceName(device) {
        if (!device) return "Bluetooth device";

        const preferred = deviceText(device.deviceName);
        if (preferred.length > 0) return preferred;

        const alias = deviceText(device.name);
        if (alias.length > 0) return alias;

        const address = deviceText(device.address);
        return address.length > 0 ? address : "Bluetooth device";
    }

    function deviceKey(device) {
        if (!device) return "";

        const path = deviceText(device.dbusPath);
        if (path.length > 0) return path;

        const address = deviceText(device.address);
        if (address.length > 0) return address;

        return deviceName(device);
    }

    function connectedDevices() {
        const source = devices || [];
        const connected = [];

        for (let index = 0; index < source.length; index++) {
            const device = source[index];
            if (device && device.connected)
                connected.push(device);
        }

        return connected;
    }

    function connectedDevicesSignature(sourceDevices) {
        const keys = [];

        for (let index = 0; index < sourceDevices.length; index++) {
            const key = deviceKey(sourceDevices[index]);
            if (key.length > 0)
                keys.push(key);
        }

        keys.sort();
        return keys.join("\u001f");
    }

    function previousKeyMap() {
        const previousKeys = {};
        if (connectedSignature.length === 0)
            return previousKeys;

        const keys = connectedSignature.split("\u001f");
        for (let index = 0; index < keys.length; index++) {
            if (keys[index].length > 0)
                previousKeys[keys[index]] = true;
        }

        return previousKeys;
    }

    function findNewDevice(sourceDevices) {
        const previousKeys = previousKeyMap();

        for (let index = 0; index < sourceDevices.length; index++) {
            const key = deviceKey(sourceDevices[index]);
            if (key.length > 0 && !previousKeys[key])
                return sourceDevices[index];
        }

        return sourceDevices.length > 0 ? sourceDevices[0] : null;
    }

    function sync(showNewConnection) {
        const connected = connectedDevices();
        const nextSignature = connectedDevicesSignature(connected);

        if (!baselineReady || baselineTimer.running) {
            connectedSignature = nextSignature;
            return;
        }

        if (nextSignature === connectedSignature)
            return;

        const newDevice = findNewDevice(connected);
        connectedSignature = nextSignature;

        if (showNewConnection && newDevice && nextSignature.length > 0)
            root.newConnection(newDevice);
    }

    onAdapterChanged: {
        connectedSignature = "";
        baselineReady = false;
        baselineTimer.restart();
        sync(false);
    }

    onDevicesChanged: sync(true)

    Timer {
        id: baselineTimer

        interval: 1000
        repeat: false
        running: true

        onTriggered: {
            root.baselineReady = true;
            root.sync(false);
        }
    }

    Repeater {
        model: root.devices

        delegate: Item {
            width: 0
            height: 0
            visible: false

            property var bluetoothDevice: modelData

            Component.onCompleted: root.sync(true)

            // FORK: `root` is captured into a local BEFORE the deferral, and
            // that is the whole fix. The previous form was
            //
            //     Component.onDestruction: Qt.callLater(function() {
            //         root.sync(true);
            //     })
            //
            // which threw on every device removal:
            //
            //   WARN scene: BluetoothConnectionTracker.qml[153]:
            //   ReferenceError: root is not defined
            //   (exception occurred during delayed function evaluation)
            //
            // `root` is not a captured variable there — it is a name resolved
            // through the QML scope chain at CALL time, and the call is the
            // one thing that has been deferred. By the time Qt.callLater runs
            // the closure, the delegate whose scope would have resolved it has
            // finished being destroyed, so the lookup fails. The deferral is
            // the point of the code and is also what breaks it.
            //
            // Assigning to a plain JS local first puts the object reference in
            // the closure's own environment, which is heap-allocated and
            // outlives the delegate. The deferral itself must stay: sync()
            // walks `root.devices`, and during onDestruction the Repeater has
            // not yet dropped this delegate, so calling it synchronously
            // counts a device that is on its way out.
            Component.onDestruction: {
                const tracker = root;
                Qt.callLater(function() {
                    tracker.sync(true);
                });
            }

            Connections {
                target: bluetoothDevice
                ignoreUnknownSignals: true

                function onConnectedChanged() {
                    root.sync(true);
                }
            }
        }
    }
}
