import Quickshell

// FORK — new file. The X11 half of DynamicIslandWindow: the island as qtile's
// bar. Why the split exists: qml/common/BackendSurface.md.
//
// This file is the entire cost of running the island under qtile. Everything
// else in the fork is backend-neutral, which was not obvious in advance and is
// the reason the port was worth attempting — the failure under X11 looked like
// "the island does not render", and was four attached-property declarations.
//
// ---- WHERE X11 IS GENUINELY POORER, so it is not re-diagnosed later --------
//
//  * There are two layers here, not layer-shell's four, so the resting/active
//    distinction is all that survives. See the mapping below.
//  * There is no EXCLUSIVE keyboard grab. `focusable` is a bool: the window
//    can take focus or it cannot. For the arrow-key and search-field panels
//    that is enough in practice, because taking focus is what makes the keys
//    arrive. What is lost is the guarantee — under Wayland an exclusive grab
//    cannot be stolen, and here a focus-follows-mouse move can take it back
//    mid-panel. qtile's `follow_mouse_focus = True` makes that reachable.
//  * `WlrLayershell.namespace` has no equivalent and needs none: it exists so
//    a compositor rule can match the surface, and qtile matches on WM_CLASS.
DynamicIslandWindow {
    id: island

    // The two-layer mapping of the base's Top/Overlay rule. Resting sits in
    // normal dock stacking, so a fullscreen client covers it exactly as the
    // Wayland Top layer intends; anything open goes above, which is the
    // Overlay half. The behaviour is therefore the SAME as Hyprland's at both
    // ends, and only the middle — Bottom and Background, which the island
    // never asks for — is missing.
    aboveWindows: !island.islandRestingSurface

    // "exclusive" and "ondemand" both collapse to "can take focus", because
    // that is the only distinction X11 offers. The important half is the
    // false case: the resting capsule must NOT be focusable, or every notch
    // hover would pull focus off the window being typed into.
    focusable: island.islandKeyboardFocus !== "none"
}
