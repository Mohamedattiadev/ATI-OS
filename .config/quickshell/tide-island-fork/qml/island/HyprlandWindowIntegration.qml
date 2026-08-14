import QtQuick
import Quickshell.Hyprland
import "../common"

Item {
    id: root

    visible: false
    width: 0
    height: 0

    property var screenObject: null

    readonly property var monitor: screenObject
        ? Hyprland.monitorFor(screenObject)
        : Hyprland.focusedMonitor
    readonly property string monitorName: monitor && monitor.name ? String(monitor.name) : ""
    readonly property bool monitorFocused: monitor ? !!monitor.focused : false
    // FORK: 0, not 1, is "unknown" — and the name rides beside the id.
    //
    // A NAMED Hyprland workspace has a NEGATIVE id (`S` is -1337), so any
    // caller testing this against `> 0` to mean "valid" silently discards
    // every named workspace. See HyprlandWorkspaceTracker for the full
    // account; this is the same value arriving by a second route.
    readonly property int workspaceId: monitor && monitor.activeWorkspace
        ? monitor.activeWorkspace.id
        : 0
    readonly property string workspaceName: monitor && monitor.activeWorkspace
        ? String(monitor.activeWorkspace.name || "")
        : ""

    HyprlandDispatch {
        id: dispatch
    }

    function focusWorkspace(workspace) {
        return dispatch.focusWorkspace(workspace);
    }
}
