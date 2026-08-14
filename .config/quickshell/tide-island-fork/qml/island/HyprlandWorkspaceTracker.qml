import QtQuick
import Quickshell.Hyprland

Item {
    id: root

    visible: false
    width: 0
    height: 0

    property var hyprMonitor: null
    property string monitorName: ""
    property bool monitorFocused: false

    // FORK: 0 is "no workspace known", and it is the ONLY invalid value.
    //
    // This used to be `< 1`, and that guard is what made `$mod SHIFT O` look
    // broken. Hyprland numbers ordinary workspaces from 1 but gives NAMED
    // workspaces NEGATIVE ids — `hyprctl workspaces` reports `S` as id
    // -1337 — so `syncWorkspaceState()` returned early on every named
    // workspace, `currentWorkspaceId` was never updated, and the island went
    // on rendering the workspace you had just left. That is the reported
    // "it still writes 4", and it is also why the window strip kept showing
    // the previous workspace's clients.
    //
    // 0 is safe as the sentinel: Hyprland uses it for "no special workspace"
    // and never for a real one.
    readonly property int monitorWorkspaceId: hyprMonitor && hyprMonitor.activeWorkspace
        ? hyprMonitor.activeWorkspace.id
        : 0
    readonly property string monitorWorkspaceName: hyprMonitor && hyprMonitor.activeWorkspace
        ? String(hyprMonitor.activeWorkspace.name || "")
        : ""

    property int currentWorkspaceId: 0
    property string currentWorkspaceName: ""

    // FORK: the name rides along with the id everywhere now.
    //
    // The id stays the IDENTITY — it is what `Hyprland.toplevels[].workspace.id`
    // carries, so it is what the window strip can actually filter on — and the
    // name is what gets DRAWN. A named workspace has no digit to draw and
    // `String(-1337)` is not a label anyone wants on their island.
    signal workspaceSynced(int workspaceId, string workspaceName)
    signal workspaceActivated(int workspaceId, string workspaceName)

    onMonitorWorkspaceIdChanged: syncWorkspaceState()
    onMonitorWorkspaceNameChanged: syncWorkspaceState()
    Component.onCompleted: syncWorkspaceState()

    // FORK: special workspaces are excluded BY NAME, not by sign.
    //
    // `special:term1` and `special:sum` are also negative (-97 and -91 here),
    // so the obvious "reject negatives" test would have swallowed `S` right
    // along with them — which is precisely the bug being fixed. They are
    // excluded for a different reason anyway: a special workspace is an
    // OVERLAY, the monitor keeps its ordinary activeWorkspace underneath it,
    // and the island deliberately keeps drawing that one.
    function isSpecialWorkspaceName(workspaceName) {
        return String(workspaceName === undefined || workspaceName === null ? "" : workspaceName)
            .indexOf("special:") === 0;
    }

    function isTrackableWorkspace(workspaceId, workspaceName) {
        if (workspaceId === 0)
            return false;
        return !isSpecialWorkspaceName(workspaceName);
    }

    function syncWorkspaceState() {
        if (!isTrackableWorkspace(monitorWorkspaceId, monitorWorkspaceName))
            return;

        currentWorkspaceId = monitorWorkspaceId;
        currentWorkspaceName = monitorWorkspaceName;
        workspaceSynced(monitorWorkspaceId, monitorWorkspaceName);
    }

    function showWorkspaceForThisMonitor(workspaceId, workspaceName) {
        if (!isTrackableWorkspace(workspaceId, workspaceName))
            return;
        workspaceActivated(workspaceId, workspaceName);
    }

    // FORK: the event is a TRIGGER, not a source of truth.
    //
    // The old code parsed the workspace out of the event payload, and got it
    // wrong in a way that only named workspaces exposed: the v1 `workspace`
    // event carries a NAME in arg 0, not an id, so it was `parseInt("S")` —
    // NaN — while `workspacev2` carries the id. Numbered workspaces hid it
    // because their name and their id are the same string.
    //
    // Reading `Hyprland.focusedWorkspace` back instead removes that whole
    // class of bug: Quickshell has already resolved the object by the time
    // the callLater runs, it carries id AND name, and "whatever is focused
    // now" is the correct answer anyway when several events arrive at once.
    function handleWorkspaceEvent(event) {
        if (!event)
            return;
        if (monitorName === "")
            return;
        if (event.name !== "workspacev2" && event.name !== "workspace"
            && event.name !== "focusedmonv2" && event.name !== "focusedmon")
            return;

        Qt.callLater(() => {
            const focusedWorkspace = Hyprland.focusedWorkspace;
            if (!root.monitorFocused || !focusedWorkspace)
                return;
            root.showWorkspaceForThisMonitor(focusedWorkspace.id,
                                             String(focusedWorkspace.name || ""));
        });
    }

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            root.handleWorkspaceEvent(event);
        }
    }

    Connections {
        target: root.hyprMonitor

        function onActiveWorkspaceChanged() {
            root.syncWorkspaceState();
        }
    }
}
