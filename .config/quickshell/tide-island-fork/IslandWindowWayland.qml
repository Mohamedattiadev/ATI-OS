import Quickshell.Wayland

// FORK — new file. The Wayland half of DynamicIslandWindow.
// Why the split exists: qml/common/BackendSurface.md.
//
// Everything the island IS lives in the base. This file is the three lines
// that only mean something to a layer-shell compositor.
DynamicIslandWindow {
    id: island

    // Pinned to Overlay, not toggled, when `focusedFullscreen` is trackable
    // (Hyprland) — see the base file's long note beside that property for
    // why: the toggle reconfigured a real layer-shell layer on every panel/
    // OSD/mode open, which is the island's busiest signal, and `visible`
    // there now carries the one case that toggle actually existed for.
    //
    // Falls back to the OLD toggle under niri, where `focusedFullscreen` has
    // no tracking and is always false: `island.visible` would then always
    // be true regardless of fullscreen, so hiding while resting still has
    // to be the layer's job there, exactly as it was before this file
    // changed. Round-tripped once already on Hyprland — the base file's
    // comment above `islandRestingSurface` records that — so this is not
    // "fixed" a third time on the path that already works.
    WlrLayershell.layer: island.fullscreenTrackingAvailable
        ? WlrLayer.Overlay
        : (island.islandRestingSurface ? WlrLayer.Top : WlrLayer.Overlay)

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
