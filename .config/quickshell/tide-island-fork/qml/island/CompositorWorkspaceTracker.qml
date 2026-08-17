import QtQuick
import Quickshell
import IslandBackend
import "../common"

Item {
    id: root

    visible: false
    width: 0
    height: 0

    // FORK: the X11 branch, and it is chosen on the DISPLAY SERVER rather
    // than on `compositor` below.
    //
    // `compositor` is fed from `CompositorBackend.compositor`, which returns
    // "hyprland" in a qtile session — probed directly, not inferred. So the
    // property that looks like it should pick the backend is precisely the
    // one that cannot: under qtile it selects the Hyprland tracker, whose
    // `hyprMonitor` is then null forever, so `syncWorkspaceState()` returns
    // early on every call and the INITIAL `currentWorkspaceId: 1` below is
    // what the island draws for the rest of the session. Measured: five
    // group switches, five frames, "1" in all of them.
    //
    // WAYLAND_DISPLAY is the same test shell.qml's `onWayland` uses, so the
    // tracker and the window wrapper can never disagree about the backend.
    readonly property bool onX11: {
        const wl = Quickshell.env("WAYLAND_DISPLAY");
        return wl === undefined || wl === null || String(wl) === "";
    }

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
    Component.onCompleted: {
        syncNiriWorkspace(false);
        // Touches EwmhState, which is what STARTS the helper: the singleton
        // is created lazily on first access, so without a read at startup
        // nothing spawns the feed until something else happens to look at it.
        syncX11Workspace(false);
    }

    function syncNiriWorkspace(announceChange) {
        // `onX11` first: CompositorBackend cannot be trusted to name the
        // compositor here (see the note at `onX11`), and niri is Wayland-only
        // anyway, so an X11 session asking niri for a workspace index is
        // always a mistake.
        if (root.onX11 || compositor !== "niri")
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

        // NOT built on X11. It is harmless there — `Quickshell.Hyprland`
        // imports and resolves fine off Hyprland, which is what let this bug
        // hide for so long — but it is also useless, and leaving it active
        // means two things claiming to own `currentWorkspaceId`.
        active: !root.onX11 && root.compositor !== "niri"
        asynchronous: false
        visible: false
        source: active ? "HyprlandWorkspaceTracker.qml" : ""
    }

    // ---- THE X11 HALF ------------------------------------------------------
    //
    // EwmhState is a singleton reading qtile's EWMH properties off the root
    // window; see qml/common/EwmhState.qml. It is display-wide, so unlike the
    // Hyprland tracker there is nothing per-monitor to bind — X11 has one
    // current desktop for the whole display, and `monitorFocused` is the only
    // thing that decides whether this island announces the change.
    //
    // `ready` is what keeps the initial `currentWorkspaceId: 1` off the
    // screen: until the helper's first line lands there is no workspace to
    // draw, and drawing "1" in the meantime is the original bug in miniature.
    // ONE signal, fired after EwmhState has written every field of a frame.
    // Listening to `workspaceIdChanged` instead is what made the island draw
    // each workspace one change late — see the note on EwmhState.frame.
    Connections {
        target: root.onX11 ? EwmhState : null

        function onFrame() {
            root.syncX11Workspace(true);
        }
    }

    property bool x11StateReady: false

    function syncX11Workspace(announceChange) {
        if (!root.onX11 || !EwmhState.ready)
            return;

        // Derived from the SOURCE properties, not from EwmhState's own
        // `workspaceId`/`workspaceName` bindings. Those are correct for
        // anyone reading them normally, but reading a binding from inside a
        // signal handler is what produced the stale-name bug, and computing
        // both from the same two raw values here means they cannot disagree
        // with each other no matter when this runs.
        const index = EwmhState.desktopIndex;
        if (index < 0)
            return;

        const workspaceId = index + 1;
        const names = EwmhState.desktopNames;
        const workspaceName = (index < names.length && String(names[index]) !== "")
            ? String(names[index])
            : String(workspaceId);

        const changed = root.x11StateReady && workspaceId !== root.currentWorkspaceId;
        root.currentWorkspaceId = workspaceId;
        root.currentWorkspaceName = workspaceName;
        root.x11StateReady = true;
        root.workspaceSynced(workspaceId, workspaceName);

        // The capsule animation fires only for a REAL change on the focused
        // monitor — the same rule the niri path uses. Announcing on the first
        // sync would pop the workspace capsule open at every login.
        if (announceChange && changed && root.monitorFocused)
            root.workspaceActivated(workspaceId, workspaceName);
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
