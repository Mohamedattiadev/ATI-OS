import Quickshell.Wayland

// FORK — new file. The Wayland half of TreeTabSidebar, and the ONLY half:
// there is no TreeTabSidebarX11.qml, because under qtile the real
// `layout.TreeTab` is already there. See the base file's root comment.
//
// Why the split exists at all: ../common/BackendSurface.md.
TreeTabSidebar {
    // Bottom, not Top. The sidebar subtracts its width from the tiling area
    // through `exclusiveZone`, exactly as tree.py's layout() hsplits
    // panel_width off the screen rect — so no window ever overlaps it and
    // there is nothing to sit above. Bottom keeps it below the island.
    WlrLayershell.layer: WlrLayer.Bottom
    // The panel is a readout, not a control surface: every key that drives it
    // is a compositor bind. Taking focus would break those binds.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.namespace: "quickshell-treetab"
}
