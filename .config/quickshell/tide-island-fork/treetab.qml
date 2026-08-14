import QtQuick
import Quickshell

import "qml/common"
import "qml/treetab"
import "qml/workspace"

//
// ============================================================
//  The TreeTab sidebar, on its own — for when the island is not up
// ============================================================
//
// FORK — new file, and a SECOND ENTRY POINT into this same config directory
// rather than a second copy of anything. `qs -p <dir>` and `qs -p <file>` both
// work, and a config's imports resolve against the directory the entry file is
// in, so everything below resolves exactly as it does from shell.qml.
//
// WHY IT EXISTS
// -------------
// Reported: "the tree layout is not working in the qtile-like bar". It was
// not, and the cause is not in the layout — layout-cycle.sh switches to
// treetab identically under either bar. It is that the 180 px sidebar which
// IS the difference between treetab and max is instantiated by shell.qml,
// and AtiScriptsV1/bar-switch STOPS the island to start the topbar. Under
// that bar, treetab and max were the same thing under two names.
//
// That is a real gap rather than a fidelity nicety: in qtile TreeTab is a
// genuine `layout.TreeTab` and works under both of ITS bars, because a layout
// is not part of a bar.
//
// WHY NOT INSTANTIATE IT FROM THE TOPBAR'S OWN CONFIG
// ---------------------------------------------------
// Tried first, and it cannot be done. Quickshell's QML scanner refuses a
// module path outside the config folder — measured, not assumed:
//
//     WARN quickshell.qmlscanner: Module path
//       ".../tide-island-fork/qml/treetab" is outside of the config folder.
//     ERROR: Failed to load configuration
//       caused by @shell.qml: TreeTabSidebarWayland is not a type
//
// and a symlink inside the topbar's folder does not get past it either — the
// scanner resolves the link and rejects the real path. Worth recording twice
// over, because that failed load ALSO stopped the file watcher: the shell
// kept serving its previous build and every later edit did nothing, which is
// the RULES' "a failed reload keeps the OLD BUILD running" with an extra
// tooth.
//
// Copying the 800-line sidebar into the topbar was the other option and is
// the one this tree already knows the price of: the palette that was
// duplicated once made every window border green on twenty-two themes,
// silently, because a wrong colour still renders.
//
// So: one implementation, two entry points. Whichever bar is up, the sidebar
// comes from the same file, and a fix to it is a fix to both.
//
// WHO STARTS AND STOPS IT
// -----------------------
// hypr/scripts/topbar.sh starts it beside the topbar; bar-switch stops it
// when the island comes back, because the island draws its own and two
// instances would stack two 180 px exclusive zones. Both are idempotent, and
// both match on the argv list rather than with `pkill -f` — see bar-switch's
// island_pid() for why.
ShellRoot {
    id: root

    // The same file the island's own LayoutState reads and layout-cycle.sh
    // writes. Not a second mechanism: literally the same component.
    LayoutState { id: layoutState }

    Loader {
        id: dataLoader
        // Constructed only while a treetab workspace is focused, which is
        // shell.qml's own reasoning: HyprlandData re-runs four hyprctl calls
        // per window event, and that is four processes an event for a whole
        // session on a machine whose user never touches treetab.
        active: layoutState.layout === "treetab"
        sourceComponent: Component { HyprlandData {} }
    }

    // Wayland only, as in shell.qml, and for the reason given there: under
    // qtile the real `layout.TreeTab` is already present, so a replica would
    // be the wrong panel. This entry point is only ever launched from
    // topbar.sh, which is Hyprland's.
    Variants {
        model: Quickshell.screens

        TreeTabSidebarWayland {
            required property var modelData

            screen: modelData
            outputName: modelData && modelData.name !== undefined
                ? String(modelData.name) : ""
            layoutIsTreeTab: layoutState.layout === "treetab"
            // Null while the loader is inactive; the sidebar reads that as
            // "nothing to list" and stays retracted, which is the state it is
            // in on every non-treetab workspace anyway.
            hyprlandData: dataLoader.item
        }
    }
}
