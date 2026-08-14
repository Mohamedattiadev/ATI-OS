import Quickshell

// FORK — new file. The X11 half of ScreenCornersWindow. See
// ../common/BackendSurface.md.
ScreenCornersWindow {
    // FALSE, and this is the one place in the port where `false` is the
    // interesting value. The base wants layer-shell's Top precisely so a
    // fullscreen window covers the corners; `aboveWindows: true` would do the
    // opposite and paint rounded corners over fullscreen video. Normal dock
    // stacking is the X11 spelling of Top, so this is the faithful mapping,
    // not a downgrade.
    aboveWindows: false
    // Mapped and invisible most of the time — it must never take the keyboard.
    focusable: false
}
