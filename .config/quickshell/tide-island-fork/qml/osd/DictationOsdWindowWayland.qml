import Quickshell.Wayland

// FORK — new file. The Wayland half of DictationOsdWindow, split out for the
// same reason RingOsdWindowWayland.qml is: see ../common/BackendSurface.md.
// `WlrLayershell.*` is an attached property, and declaring one that cannot
// be created (X11, no compositor Wayland protocol) fails the whole
// component, not just the line — so the base file stays loadable under both
// backends and these three lines live only where they can succeed.
DictationOsdWindow {
    // Overlay, not Top, matching RingOsdWindow: this is feedback about
    // something happening RIGHT NOW (you are being recorded), so it has to
    // stay legible over a fullscreen window the same way the volume ring
    // does.
    WlrLayershell.layer: WlrLayer.Overlay
    // None: this surface is mapped for the duration of a dictation session,
    // and taking keyboard focus for it would steal keystrokes from whatever
    // window is actually being typed into — including, absurdly, from the
    // dictation output itself landing via xdotool in a focused window.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.namespace: "quickshell-dictation-osd"
}
