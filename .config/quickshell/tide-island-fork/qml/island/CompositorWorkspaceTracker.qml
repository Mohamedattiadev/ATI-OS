import QtQuick
import IslandBackend

Item {
    id: root

    visible: false
    width: 0
    height: 0

    property string compositor: "hyprland"
    property var hyprMonitor: null
    property string hyprMonitorName: ""
    property string outputName: ""
    property bool monitorFocused: false
    property int currentWorkspaceId: 1
    property string currentWorkspaceName: "1"
    property bool niriStateReady: false

    // FORK: id AND name. See HyprlandWorkspaceTracker for why — the id stays
    // the identity the window strip filters on, the name is what gets drawn,
    // and a NAMED Hyprland workspace has a negative id and no digit to draw.
    signal workspaceSynced(int workspaceId, string workspaceName)
    signal workspaceActivated(int workspaceId, string workspaceName)

    readonly property int compositorRevision: CompositorBackend.revision

    onCompositorChanged: {
        niriStateReady = false;
        syncNiriWorkspace(false);
    }
    onOutputNameChanged: {
        niriStateReady = false;
        syncNiriWorkspace(false);
    }
    onCompositorRevisionChanged: syncNiriWorkspace(true)
    Component.onCompleted: syncNiriWorkspace(false)

    function syncNiriWorkspace(announceChange) {
        if (compositor !== "niri")
            return;

        const workspaceId = CompositorBackend.activeWorkspaceIndexForOutput(outputName);
        if (workspaceId < 1)
            return;

        const changed = niriStateReady && workspaceId !== currentWorkspaceId;
        currentWorkspaceId = workspaceId;
        // niri indexes workspaces by position and has no named-workspace
        // case, so the label is just the index. The property exists so both
        // compositors present one shape to the island.
        currentWorkspaceName = String(workspaceId);
        niriStateReady = true;
        workspaceSynced(workspaceId, currentWorkspaceName);
        if (announceChange && changed && monitorFocused)
            workspaceActivated(workspaceId, currentWorkspaceName);
    }

    Loader {
        id: hyprlandTrackerLoader

        active: root.compositor !== "niri"
        asynchronous: false
        visible: false
        source: active ? "HyprlandWorkspaceTracker.qml" : ""
    }

    Binding {
        target: hyprlandTrackerLoader.item
        property: "hyprMonitor"
        value: root.hyprMonitor
        when: hyprlandTrackerLoader.item !== null
    }

    Binding {
        target: hyprlandTrackerLoader.item
        property: "monitorName"
        value: root.hyprMonitorName
        when: hyprlandTrackerLoader.item !== null
    }

    Binding {
        target: hyprlandTrackerLoader.item
        property: "monitorFocused"
        value: root.monitorFocused
        when: hyprlandTrackerLoader.item !== null
    }

    Connections {
        target: hyprlandTrackerLoader.item

        function onWorkspaceSynced(workspaceId, workspaceName) {
            root.currentWorkspaceId = workspaceId;
            root.currentWorkspaceName = workspaceName;
            root.workspaceSynced(workspaceId, workspaceName);
        }

        function onWorkspaceActivated(workspaceId, workspaceName) {
            root.currentWorkspaceId = workspaceId;
            root.currentWorkspaceName = workspaceName;
            root.workspaceActivated(workspaceId, workspaceName);
        }
    }
}
