import Quickshell.Wayland

// FORK — new file. The Wayland half of ThemeTransitionWindow.
// See ../common/BackendSurface.md for why the base/wrapper split exists.
ThemeTransitionWindow {
    // Overlay is load-bearing here and was arrived at by measurement, not
    // taste — the note in the base file records it: on any lower layer the
    // cover does not cover the one surface that sits above the whole desktop,
    // so the island repainted live on the new palette while the rest of the
    // screen stayed frozen on the old one for another second and a half.
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-theme-transition"
    // The sole owner of focus for this surface on Wayland. The base
    // deliberately does not also set `focusable`; both drive the same
    // layer-shell field and two owners means evaluation order decides.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
}
