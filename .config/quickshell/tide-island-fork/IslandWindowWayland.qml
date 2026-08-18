import Quickshell.Wayland

// FORK — new file. The Wayland half of DynamicIslandWindow.
// Why the split exists: qml/common/BackendSurface.md.
//
// Everything the island IS lives in the base. This file is the three lines
// that only mean something to a layer-shell compositor.
DynamicIslandWindow {
    id: island

    // Top while resting, Overlay the moment anything opens. This is the
    // fullscreen rule, and it has been round-tripped once already — the base
    // file's comment above `islandRestingSurface` records that, so do not
    // "fix" it a third time. Resting hides under a fullscreen window; any
    // panel, OSD or mode promotes the surface and draws over it.
    WlrLayershell.layer: island.islandRestingSurface ? WlrLayer.Top : WlrLayer.Overlay

    // The base decides WHETHER to grab the keyboard — ninety lines of
    // reasoning about panel state that only it can see. This maps its answer
    // onto layer-shell's three-valued field. The mapping is total: every
    // string the base can return is handled, and an unrecognised one falls to
    // None, which is the safe end (a missed grab loses a keystroke to the
    // window behind; a stray grab steals every keystroke until it clears).
    // `island.superHeld` — see its declaration in DynamicIslandWindow.qml —
    // drops Exclusive to OnDemand for exactly as long as Super is
    // physically held, which is the only way a workspace-switch chord can
    // reach Hyprland while a panel is open: measured, Hyprland refuses
    // `hyprctl dispatch workspace N` outright while this surface holds
    // Exclusive, and does not once it is OnDemand.
    WlrLayershell.keyboardFocus: {
        switch (island.islandKeyboardFocus) {
        case "exclusive": return island.superHeld
            ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive;
        case "ondemand":  return WlrKeyboardFocus.OnDemand;
        default:          return WlrKeyboardFocus.None;
        }
    }
}
