import QtQuick
import Quickshell
import Quickshell.Services.SystemTray

//
// systray_widgetbox's contents: the tray itself.
//
// icon_size=_s(14), padding=6, from config.py's Systray.
//
// One tray per SESSION, not per screen, and that is the same constraint qtile
// has for a different reason. There, X11 allows exactly one tray owner per
// display (_NET_SYSTEM_TRAY_S0) and building a second Systray does not render
// an empty box — it fails to acquire the selection and aborts config load,
// which is why _strip_systray() exists. Here the StatusNotifier host is a bus
// name and the same "only one" rule applies, so this must only ever be
// instantiated on one bar. shell.qml puts it on every screen's PanelWindow;
// that is safe because Quickshell's SystemTray is a singleton VIEW of one
// host, not a second host.
Item {
    id: root

    implicitWidth: row.implicitWidth
    implicitHeight: parent ? parent.height : Metrics.barHeight

    Row {
        id: row
        anchors.centerIn: parent
        spacing: Metrics.s(6)

        Repeater {
            model: SystemTray.items

            delegate: Item {
                id: trayItem
                required property var modelData

                width: Metrics.s(14) + Metrics.s(6) * 2
                // root.height, not parent.height — the parent is a Row and
                // that is a circular binding. See Workspaces.qml.
                height: root.height

                Image {
                    anchors.centerIn: parent
                    width: Metrics.s(14)
                    height: Metrics.s(14)
                    sourceSize.width: Metrics.s(28)
                    sourceSize.height: Metrics.s(28)
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    source: trayItem.modelData.icon
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: (event) => {
                        if (event.button === Qt.LeftButton)
                            trayItem.modelData.activate();
                        else
                            trayItem.modelData.secondaryActivate();
                    }
                }
            }
        }
    }
}
