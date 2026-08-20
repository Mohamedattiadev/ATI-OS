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

    // FORK: whether the focused window on ANY monitor is fullscreen. Fed by
    // `fullscreen>>1` / `fullscreen>>0` on Hyprland's own event socket — the
    // same event, read the same way, as the topbar's `focusedFullscreen`
    // (quickshell/topbar/shell.qml). DynamicIslandWindow.qml uses it to stop
    // pinning the resting capsule to the Overlay layer only while something
    // is actually covering it, instead of promoting on every panel/OSD/mode
    // open the way `islandRestingSurface` used to force. See the long note
    // beside `focusedFullscreen` there for why that was worth doing.
    //
    // Not scoped to `screenObject`'s monitor: Hyprland's `fullscreen>>`
    // event does not carry a monitor, only a 1/0, and this machine is
    // single-monitor. A multi-monitor session would need the same
    // per-output care `monitorFocused` already takes above; left as the
    // honest limit rather than guessed at.
    property bool fullscreenActive: false

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (String(event.name) === "fullscreen")
                root.fullscreenActive = String(event.data || "").trim() === "1";
        }
    }

    HyprlandDispatch {
        id: dispatch
    }

    function focusWorkspace(workspace) {
        return dispatch.focusWorkspace(workspace);
    }
}
