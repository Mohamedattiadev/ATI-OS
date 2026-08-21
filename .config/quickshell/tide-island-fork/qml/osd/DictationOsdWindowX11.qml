import Quickshell

// FORK — new file. The X11 half of DictationOsdWindow, for the qtile
// session. See ../common/BackendSurface.md and RingOsdWindowX11.qml, which
// this mirrors exactly: `aboveWindows`/`focusable` are the X11-dock
// equivalents of `WlrLayer.Overlay`/`WlrKeyboardFocus.None`, and
// `mask: Region {}` in the base already does the click-through work on both
// backends without needing anything here.
DictationOsdWindow {
    aboveWindows: true
    focusable: false
}
