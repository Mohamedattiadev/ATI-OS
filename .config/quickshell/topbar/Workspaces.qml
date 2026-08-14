import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

//
// qtile's GroupBox, on Hyprland workspaces.
//
// Its parameters, from config.py, kept by name so the two bars agree:
//
//     fontsize=_s(10)   padding_x=8   margin_x=_s(8)   borderwidth=4
//     highlight_method="text"         hide_unused=True
//     active                     colors[8] cyan   — a workspace with windows
//     inactive                   colors[1] fg     — an empty one
//     this_current_screen_border colors[7] purple — the focused workspace
//     urgent_text                colors[3] red
//
// `highlight_method="text"` is why nothing here draws a box or an underline:
// qtile's GroupBox in that mode colours the LABEL and nothing else, and
// config.py's note on the active group is "no boxes anywhere on this widget".
// A pill would be a different widget that happened to contain the same digits.
//
// ---- WHY THIS SHELLS OUT INSTEAD OF USING Hyprland.workspaces ----
//
// It tried the model first. `Hyprland.workspaces` populates only after an
// explicit refreshWorkspaces(), and even then, measured with a probe against
// this session:
//
//     ws count: 8
//     ws id= -1  name= 4   ipc= {}
//     ws id= -1  name= 5   ipc= {}
//     focused: -1
//
// Every id is -1 and every lastIpcObject is empty. Names are all it gives.
// The GroupBox needs two things names cannot supply: the id, to dispatch a
// click to, and the window COUNT, which is the whole of `hide_unused` and of
// the active/inactive colour split. (`Hyprland.toplevels` is the opposite —
// its lastIpcObject is fully populated, which is why TaskList.qml does use
// the model.)
//
// So this reads `hyprctl -j workspaces` and `activeworkspace`, which is what
// the island's own HyprlandData does for the same reason. TWO calls, not
// HyprlandData's four, and debounced on the same 90 ms: a workspace event
// arrives in bursts while windows are being moved, and refreshing per event
// would be several processes per keypress.
Item {
    id: root

    implicitWidth: row.implicitWidth
    implicitHeight: parent ? parent.height : Metrics.barHeight

    property var workspaces: []
    property int focusedId: -1

    Process {
        id: wsProc
        command: ["hyprctl", "-j", "workspaces"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const list = JSON.parse(text);
                    list.sort((a, b) => a.id - b.id);
                    root.workspaces = list;
                } catch (e) {
                    // Keep the last good list. A torn read must not blank the
                    // group — an empty centre reads as a broken bar.
                }
            }
        }
    }

    Process {
        id: activeProc
        command: ["hyprctl", "-j", "activeworkspace"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.focusedId = JSON.parse(text).id;
                } catch (e) {}
            }
        }
    }

    function refresh() {
        wsProc.running = true;
        activeProc.running = true;
    }

    Timer {
        id: debounce
        interval: 90
        repeat: false
        onTriggered: root.refresh()
    }

    Component.onCompleted: root.refresh()

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            // Only the events that can change the answer. `openwindow` and
            // `closewindow` matter as much as the workspace ones, because the
            // window COUNT is what decides whether a workspace is drawn at all.
            const n = String(event.name);
            if (n.indexOf("workspace") >= 0 || n.indexOf("window") >= 0
                    || n === "urgent" || n === "monitoradded" || n === "monitorremoved")
                debounce.restart();
        }
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 0

        Repeater {
            model: root.workspaces

            delegate: Item {
                id: wsItem
                required property var modelData

                readonly property bool focused: modelData.id === root.focusedId
                readonly property bool populated: (modelData.windows || 0) > 0

                // hide_unused=True: an empty, unfocused workspace is not drawn.
                // That is also what keeps this group narrow enough to sit at
                // the bar's true centre with a long TaskList beside it.
                //
                // A special workspace (negative id) is a scratchpad and was
                // never in qtile's group list at all.
                visible: modelData.id > 0 && (populated || focused)
                width: visible ? label.implicitWidth + Metrics.s(8) * 2 : 0
                // root.height, NOT parent.height. The parent is a Row, and a
                // Row derives its height FROM its children — so a child
                // sizing itself from the Row is a loop, which Qt resolves by
                // dropping one side. It resolved to zero: the data was
                // arriving (8 workspaces, focused 4, confirmed by probe) and
                // the group simply had no height to draw in.
                height: root.height

                Text {
                    id: label
                    anchors.centerIn: parent
                    text: wsItem.modelData.name
                    font.family: "Ubuntu Bold"
                    font.pixelSize: Metrics.s(10)
                    renderType: Text.NativeRendering
                    color: wsItem.focused ? BarTheme.purple
                        : wsItem.populated ? BarTheme.cyan
                        : BarTheme.fg
                }

                MouseArea {
                    anchors.fill: parent
                    // disable_drag=True in config.py, so clicks only.
                    onClicked: Hyprland.dispatch("workspace " + wsItem.modelData.id)
                }
            }
        }
    }
}
