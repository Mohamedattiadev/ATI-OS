import Quickshell

// FORK — new file. The X11 half of ThemeTransitionWindow, for the qtile
// session. See ../common/BackendSurface.md.
//
// The sweep is the one fork feature that is FULLY intact under X11: it is a
// plain fullscreen surface with a shader-free gradient over a screenshot-free
// cover, and none of that is Wayland-specific. What changes is only how the
// surface is stacked and whether it can take the keyboard.
ThemeTransitionWindow {
    // Overlay has no X11 equivalent finer than "above normal windows". Good
    // enough for this one: a theme change is a deliberate act, so the case
    // Overlay exists to beat — a fullscreen client that took the override —
    // is not one you are in when you press the theme key.
    aboveWindows: true
    // The X11 spelling of WlrKeyboardFocus.None, and the sole owner of focus
    // on this backend for the reason the base file's comment gives.
    focusable: false
}
