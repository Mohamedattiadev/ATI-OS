pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

//
// FORK — new file. The X11 session's compositor feed.
//
// WHAT IT REPLACES, AND WHY IT HAD TO EXIST
// -----------------------------------------
// Under qtile the island was blind in two places at once, silently:
//
//   * the workspace digit was frozen at 1 — `Hyprland.focusedMonitor` is
//     null off Hyprland, so HyprlandWorkspaceTracker never syncs and
//     CompositorWorkspaceTracker's INITIAL `currentWorkspaceId: 1` is what
//     stays on screen. Measured with a five-group sweep: qtile on 1, 2, 3,
//     5, 4 in turn, island drawing "1" in every frame.
//   * the window strip was empty — it is built from `ToplevelManager`, the
//     Wayland foreign-toplevel protocol, which reports nothing on X11.
//
// Neither logs anything. Worse, `CompositorBackend.compositor` returns
// "hyprland" in a qtile session — probed directly — so no code downstream
// could have noticed on its own.
//
// The feed is `bin/ewmh-state.py`: one long-lived, event-driven process
// reading the EWMH properties qtile publishes on the root window. See that
// file's header for why EWMH beats both `qtile cmd-obj` polling and pushing
// from qtile hooks.
//
// A SINGLETON, deliberately. The island is built per-screen by a Variants
// block, and a plain Item here would start one helper per monitor, each with
// its own X connection and its own subscription to every client window. The
// data is display-wide, so one process serves all of them.
//
// ---- THE OFF-BY-ONE THAT IS NOT AN OFF-BY-ONE ------------------------------
//
// `workspaceId` is the EWMH desktop index PLUS ONE, and that is load-bearing
// rather than cosmetic. The island's Hyprland path uses 0 as its "no
// workspace known" sentinel — HyprlandWorkspaceTracker says so in as many
// words, and WindowRingStrip's fail-open test keys on it. EWMH numbers
// desktops from 0, so the first desktop would BE the sentinel, and group "1"
// would read as "unknown" everywhere downstream: the strip would take its
// fail-open path and draw every window on the machine.
//
// So ids are 1-based here and the raw index stays available as
// `desktopIndex`. Anything talking to X11 wants the index; anything talking
// to the island wants the id.
//
Singleton {
    id: root

    // False until the first frame arrives. Nothing should draw an EWMH
    // workspace before then — a "1" shown for the 200 ms before the helper's
    // first line lands is exactly the bug this file exists to fix.
    property bool ready: false

    // ---- READ THIS, NOT THE INDIVIDUAL CHANGE SIGNALS ---------------------
    //
    // Emitted once per feed frame, AFTER every property below has been
    // assigned. Consumers must listen to this rather than to
    // `onWorkspaceIdChanged` and friends, and the reason is a bug that was
    // measured rather than imagined.
    //
    // `workspaceId` and `workspaceName` are sibling bindings on the same
    // source, `desktopIndex`. Assigning desktopIndex fires workspaceIdChanged
    // SYNCHRONOUSLY, and a handler on that signal runs before QML has
    // re-evaluated the OTHER binding — so it reads a freshly-correct id
    // beside a stale name. The tracker's own trace, on a switch from group 4
    // to group 5:
    //
    //     X11WS| sync id=5 name=4 index=4
    //
    // The island therefore drew the right workspace one change late, every
    // change, which looks exactly like a laggy feed and is not: the feed was
    // already correct and the frames prove it.
    //
    // One signal after all the writes makes the whole class of ordering
    // question disappear.
    signal frame()

    property int desktopIndex: -1
    property var desktopNames: []
    property int activeWindowId: 0
    // Array of { id, desktop, appId, title, normal }. `desktop` is the RAW
    // EWMH index, matching `desktopIndex` and not `workspaceId`.
    property var windows: []

    readonly property int workspaceId: root.desktopIndex >= 0 ? root.desktopIndex + 1 : 0
    readonly property string workspaceName:
        (root.desktopIndex >= 0 && root.desktopIndex < root.desktopNames.length)
            ? String(root.desktopNames[root.desktopIndex])
            : ""

    // ---- WHY THESE OBJECTS CARRY METHODS ----------------------------------
    //
    // WindowRingStrip's delegate calls `toplevel.activate()` on a left click
    // and `toplevel.close()` on a middle click, because on Wayland it holds a
    // real ToplevelHandle. Giving the X11 entries the same two methods lets
    // the strip stay backend-neutral — it never learns there are two kinds of
    // window — and is the whole reason this is a decorate step rather than
    // the raw parsed JSON.
    //
    // IDENTITY MATTERS MORE THAN IT LOOKS. The delegate decides which icon is
    // focused with `modelData.toplevel === root.activeToplevel`, an identity
    // test chosen deliberately over comparing appIds, because three kitty
    // windows share an appId and a name match lights the wrong ring. So these
    // objects must be built ONCE per frame from the feed and then handed out
    // by reference — never rebuilt inside a binding that the strip and the
    // active-window lookup each evaluate separately, or the two would hold
    // equal-looking objects that are never `===` and no icon would ever ring.
    function decorate(rawWindows) {
        const out = [];
        for (let i = 0; i < rawWindows.length; i++) {
            const w = rawWindows[i];
            if (!w)
                continue;
            const id = Number(w.id);
            // The X window id, spelled as a Hyprland address. The workspace
            // overview keys every window on `toplevel.HyprlandToplevel.address`
            // and looks the same string up in `windowByAddress`, in half a
            // dozen places including its hit-testing and its drag source. A
            // shim here is what lets that whole panel stay backend-neutral
            // instead of growing an X11 branch per call site.
            const address = "0x" + id.toString(16);
            out.push({
                id: id,
                address: address,
                HyprlandToplevel: { address: address },
                // `at` / `size` in the shape `hyprctl clients` reports, which
                // is what the overview lays its tiles out from.
                at: [Number(w.at ? w.at[0] : 0), Number(w.at ? w.at[1] : 0)],
                size: [Number(w.size ? w.size[0] : 0), Number(w.size ? w.size[1] : 0)],
                // 1-based, matching EwmhState.workspaceId and the overview's
                // own `wsId > start && wsId <= end` arithmetic.
                workspace: { id: Number(w.desktop) + 1, name: String(Number(w.desktop) + 1) },
                monitor: 0,
                desktop: Number(w.desktop),
                appId: String(w.appId || ""),
                "class": String(w.appId || ""),
                title: String(w.title || ""),
                normal: !!w.normal,
                activate: function () {
                    return root.focusWindow(id);
                },
                close: function () {
                    return root.closeWindow(id);
                }
            });
        }
        return out;
    }

    // ---- THE OVERVIEW'S TWO VIEWS OF THE SAME LIST -------------------------
    //
    // `windowByAddress` is what WorkspaceOverviewLayer resolves an address to
    // when it needs geometry; the array itself stands in for ToplevelManager.
    // Both are derived from `windows`, so a window cannot appear in one and
    // not the other -- which on the Wayland side is a real failure mode,
    // since there the two come from different protocols.
    readonly property var windowByAddress: {
        const map = ({});
        for (let i = 0; i < root.windows.length; i++)
            map[root.windows[i].address] = root.windows[i];
        return map;
    }

    // One entry per desktop, in EWMH order, in the shape `hyprctl workspaces`
    // reports. ids are 1-based for the same reason workspaceId is.
    readonly property var workspaceList: {
        const out = [];
        for (let i = 0; i < root.desktopNames.length; i++)
            out.push({ id: i + 1, name: String(root.desktopNames[i]) });
        return out;
    }

    // The entry for the focused window, taken from the SAME array the strip
    // is built from so the identity test above can succeed.
    readonly property var activeWindow: {
        for (let i = 0; i < root.windows.length; i++) {
            if (root.windows[i].id === root.activeWindowId)
                return root.windows[i];
        }
        return null;
    }

    // Only the windows on the CURRENT desktop, in EWMH stacking order, with
    // the desktop-wide furniture dropped. qtile puts its own bar and any
    // dock on a desktop too, and a strip that draws them is drawing the bar
    // inside the bar.
    readonly property var currentDesktopWindows: {
        const out = [];
        const here = root.desktopIndex;
        for (let i = 0; i < root.windows.length; i++) {
            const w = root.windows[i];
            if (!w || !w.normal)
                continue;
            // 0xFFFFFFFF is EWMH's "on every desktop" — a sticky window is
            // on this one too, so it belongs in the strip.
            const sticky = w.desktop === -1 || w.desktop === 0xFFFFFFFF;
            if (w.desktop === here || sticky)
                out.push(w);
        }
        return out;
    }

    // ---- THE FEED ----------------------------------------------------------
    //
    // SplitParser rather than StdioCollector, for the reason SystemMonitorPanel
    // sets out at length: a collector accumulates, and this process never
    // exits, so a collector would grow without bound and hand back a buffer
    // containing every frame since login. The helper emits one JSON object per
    // line precisely so a line-oriented parser is enough.
    Process {
        id: feed

        // Guarded on the display server, not on the compositor name.
        // `CompositorBackend.compositor` says "hyprland" under qtile, so it
        // cannot be the test; WAYLAND_DISPLAY is what shell.qml's `onWayland`
        // keys on and the two must never disagree.
        readonly property bool onX11: {
            const wl = Quickshell.env("WAYLAND_DISPLAY");
            return wl === undefined || wl === null || String(wl) === "";
        }

        running: onX11
        command: ["python3",
                  Quickshell.env("HOME")
                  + "/.config/quickshell/tide-island-fork/bin/ewmh-state.py"]

        stdout: SplitParser {
            onRead: function (line) {
                const text = String(line).trim();
                if (text === "")
                    return;

                let payload;
                try {
                    payload = JSON.parse(text);
                } catch (e) {
                    // A partial line cannot happen — SplitParser splits on
                    // newlines and the helper flushes whole objects — so this
                    // means the helper printed something unexpected, which is
                    // worth seeing rather than swallowing.
                    console.warn("EwmhState: unparseable frame:", text.slice(0, 200));
                    return;
                }

                root.desktopIndex = Number(payload.desktop);
                root.desktopNames = payload.names || [];
                root.activeWindowId = Number(payload.active || 0);
                root.windows = root.decorate(payload.windows || []);
                root.ready = true;
                // LAST, and only once everything above has landed.
                root.frame();
            }
        }

        // A traceback from the helper must reach the log. Without this the
        // failure mode is the exact one this file was written to fix — an
        // island that renders perfectly and shows stale state forever, with
        // nothing anywhere saying why.
        stderr: SplitParser {
            onRead: function (line) {
                const text = String(line).trim();
                if (text !== "")
                    console.warn("EwmhState/helper:", text);
            }
        }

        // The helper dying is not fatal and must not be silent. It exits 0
        // when the X server goes away, which is a session ending rather than
        // a fault — but a crash would otherwise leave the island frozen on
        // its last frame forever, which looks exactly like the bug this
        // file fixes.
        onExited: function (exitCode, exitStatus) {
            if (!feed.onX11)
                return;
            console.warn("EwmhState: feed exited, code", exitCode,
                         "— island workspace state is now frozen; retrying");
            respawn.start();
        }
    }

    Timer {
        id: respawn
        interval: 2000
        repeat: false
        onTriggered: {
            if (feed.onX11 && !feed.running)
                feed.running = true;
        }
    }

    // ---- ACTIONS -----------------------------------------------------------
    //
    // Through xdotool rather than by writing the root property ourselves,
    // because a desktop switch is a CLIENT MESSAGE to the WM and not a
    // property write — setting _NET_CURRENT_DESKTOP directly is ignored by
    // every compliant WM, qtile included. xdotool is already a hard
    // dependency of this session (the qdrop scripts shell out to it).
    //
    // Each action gets its own Process and each sets `running = false` first:
    // assigning true to an already-running Process is a no-op, and clicks
    // arrive faster than a spawn returns.
    Process {
        id: actionProcess
        property var argv: []
        command: actionProcess.argv
        running: false
    }

    function runAction(argv) {
        actionProcess.running = false;
        actionProcess.argv = argv;
        actionProcess.running = true;
        return true;
    }

    // Takes the island's 1-based id, not the EWMH index — every caller in
    // the island speaks ids, and doing the conversion at the boundary is
    // what keeps the off-one out of the call sites.
    function focusWorkspace(workspaceId) {
        const index = Math.trunc(Number(workspaceId)) - 1;
        if (!isFinite(index) || index < 0)
            return false;

        return runAction(["xdotool", "set_desktop", String(index)]);
    }

    function focusWindow(windowId) {
        const id = Math.trunc(Number(windowId));
        if (!isFinite(id) || id <= 0)
            return false;

        // windowactivate, not windowfocus: activate asks the WM to switch
        // desktops and raise, which is what clicking a window in the island
        // means. windowfocus sets input focus on a window that may not even
        // be on screen.
        return runAction(["xdotool", "windowactivate", String(id)]);
    }

    function closeWindow(windowId) {
        const id = Math.trunc(Number(windowId));
        if (!isFinite(id) || id <= 0)
            return false;

        // windowclose sends the polite _NET_CLOSE_WINDOW. `windowkill` is
        // the one that severs the client's X connection and loses unsaved
        // work, and it is never what a close button means.
        return runAction(["xdotool", "windowclose", String(id)]);
    }
}
