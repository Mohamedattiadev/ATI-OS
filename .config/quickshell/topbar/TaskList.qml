import QtQuick
import Quickshell
import Quickshell.Hyprland

//
// qtile's TaskList, on Hyprland toplevels.
//
// STATE IS CARRIED BY COLOUR AND WEIGHT, NOT BY LETTERS, and that is
// config.py's decision rather than a simplification of it. Every entry there
// used to be prefixed with a private code — "F" focused, "V" floating, "VF"
// both — in the one widget whose entire job is showing window names, and those
// characters cost width the name then lost to truncation. Focus already reads
// from the accent colour and the bold.
//
// font="JetBrainsMono Nerd Font", fontsize=_s(10), icon_size=_s(16).
//
// Uses `Hyprland.toplevels` and NOT `ToplevelManager.toplevels`, which is the
// opposite choice from Workspaces.qml beside it, and both were measured:
// the Wayland ToplevelManager reported zero entries in this session, while
// Hyprland.toplevels — after an explicit refreshToplevels() — carries a fully
// populated lastIpcObject with class, title, workspace and address. Workspaces
// are the reverse case; see that file.
//
// Its WIDTH is imposed from outside, which is the whole point: config.py pins
// it to a computed length because with stretch=False it sized to content, and
// each opened window shoved the GroupBox right until it was past the bar's
// centre. See the centring note in shell.qml.
Item {
    id: root

    implicitHeight: parent ? parent.height : Metrics.barHeight
    clip: true

    // Only the windows on the workspace you are looking at, which is what
    // qtile's TaskList shows: it lists the current GROUP, not every client on
    // the machine. Without this the list is thirteen entries wide on this
    // session and the centring arithmetic has nothing left to give.
    readonly property var entries: {
        const out = [];
        const all = Hyprland.toplevels ? (Hyprland.toplevels.values || []) : [];
        const focusedWs = Hyprland.focusedWorkspace;
        for (let i = 0; i < all.length; i++) {
            const o = all[i].lastIpcObject;
            if (!o || !o.workspace) continue;
            if (focusedWs && o.workspace.name !== undefined
                    && String(o.workspace.name) !== String(focusedWs.name))
                continue;
            out.push(o);
        }
        return out;
    }

    Component.onCompleted: Hyprland.refreshToplevels()

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            const n = String(event.name);
            if (n.indexOf("window") >= 0 || n.indexOf("title") >= 0
                    || n.indexOf("workspace") >= 0)
                refreshDebounce.restart();
        }
    }
    Timer {
        id: refreshDebounce
        interval: 90
        repeat: false
        onTriggered: Hyprland.refreshToplevels()
    }

    Row {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0

        Repeater {
            model: root.entries

            delegate: Item {
                id: entry
                required property var modelData

                readonly property bool focused: {
                    const a = Hyprland.activeToplevel;
                    return a && a.lastIpcObject
                        && a.lastIpcObject.address === modelData.address;
                }

                // Each entry is capped so one window with a very long title
                // cannot eat the whole list. qtile's TaskList divides its
                // assigned width between entries; this is the same idea as a
                // per-entry maximum.
                width: Math.min(icon.width + Metrics.s(6) + title.implicitWidth
                                + Metrics.s(14), Metrics.s(180))
                height: root.height

                Image {
                    id: icon
                    anchors.verticalCenter: parent.verticalCenter
                    x: Metrics.s(6)
                    width: Metrics.s(16)
                    height: Metrics.s(16)
                    sourceSize.width: Metrics.s(32)
                    sourceSize.height: Metrics.s(32)
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    // `true` = fall back rather than warn per frame on a
                    // client whose class matches no installed .desktop file.
                    source: Quickshell.iconPath(entry.modelData.class, true)
                }

                Text {
                    id: title
                    anchors.left: icon.right
                    anchors.leftMargin: Metrics.s(6)
                    anchors.right: parent.right
                    anchors.rightMargin: Metrics.s(8)
                    anchors.verticalCenter: parent.verticalCenter
                    text: entry.modelData.title || entry.modelData.class || ""
                    color: entry.focused ? BarTheme.accent : BarTheme.fg
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: Metrics.s(10)
                    font.bold: entry.focused
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    renderType: Text.NativeRendering
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: Hyprland.dispatch(
                        "focuswindow address:" + entry.modelData.address)
                }
            }
        }
    }
}
