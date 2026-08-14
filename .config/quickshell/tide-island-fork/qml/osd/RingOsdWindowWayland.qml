import Quickshell.Wayland

// FORK — new file. The Wayland half of RingOsdWindow.
//
// Why this file exists at all is written up once, in ../common/BackendSurface.md.
// The short version: `WlrLayershell.*` is an ATTACHED property, and an attached
// object that cannot be created fails the whole component rather than the one
// line. Under X11 that turned RingOsdWindow.qml into "Component is not ready"
// and the OSD simply never appeared, with no error naming the OSD.
//
// So the base file keeps every pixel of the OSD and none of the backend, and
// the three lines that only exist on Wayland live here.
RingOsdWindow {
    // Overlay, not Top: the ring is feedback about an adjustment the user is
    // making RIGHT NOW, so it has to be legible over a fullscreen video — the
    // single most likely thing to be on screen when the volume key is pressed.
    WlrLayershell.layer: WlrLayer.Overlay
    // None, never OnDemand. This surface spans the whole output and is mapped
    // whenever the volume changes; taking keyboard focus for it would mean a
    // volume key press stole the keyboard from whatever you were typing into.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    // The namespace is the only handle a compositor has on a layer surface:
    // it is what `hyprctl layers` prints and what a `layerrule` matches on.
    // Nothing in hypr/looks.conf keys on this one today — grepped, only
    // `selection` has rules — so it is carried for identification, not
    // because a rule depends on it. X11 has no equivalent and needs none.
    WlrLayershell.namespace: "quickshell-ring-osd"
}
