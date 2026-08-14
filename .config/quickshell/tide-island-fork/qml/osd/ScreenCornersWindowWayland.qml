import Quickshell.Wayland

// FORK — new file. The Wayland half of ScreenCornersWindow.
// See ../common/BackendSurface.md.
ScreenCornersWindow {
    // Top, not Overlay. The base file's header is emphatic that this IS the
    // hide-on-fullscreen behaviour and not a compromise with it: Hyprland
    // draws fullscreen windows above Top and below Overlay, so Top is what
    // makes the rounded corners get out of the way of a fullscreen video.
    WlrLayershell.layer: WlrLayer.Top
    // Sole owner of focus on this backend. Never OnDemand — this surface is
    // mapped and invisible most of the time.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.namespace: "quickshell-screen-corners"
}
