import Quickshell

// FORK — new file. The X11 half of RingOsdWindow, for the qtile session.
//
// See ../common/BackendSurface.md for why the split exists. This file is the
// whole of what layer-shell gives us for free and X11 does not:
//
//   WlrLayer.Overlay          -> aboveWindows, which is the only stacking
//                                control an X11 dock has. It is coarser: a
//                                _NET_WM_WINDOW_TYPE_DOCK sits above normal
//                                windows but NOT above a fullscreen client
//                                that has taken the override, so a volume
//                                ring over fullscreen mpv is a known
//                                difference from the Hyprland session rather
//                                than a bug to hunt.
//   WlrKeyboardFocus.None     -> focusable: false. Same meaning, and it is
//                                the important one: this surface covers the
//                                entire output whenever the volume changes,
//                                and taking focus would steal the keyboard
//                                mid-keystroke.
//   WlrLayershell.namespace   -> nothing. X11 has no layer-surface namespace.
//
// `mask: Region {}` in the base still does the input-transparency work on
// both backends — it is on the generic window interface, not the Wayland one,
// which is what makes the desktop clickable under the ring here too.
RingOsdWindow {
    aboveWindows: true
    focusable: false
}
