import Quickshell
import Quickshell.Io

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

    // ---- STACKING: ALWAYS ABOVE, and the previous rule was wrong ----------
    //
    // This was `aboveWindows: !island.islandRestingSurface`, on the reasoning
    // that a resting island should sit in "normal dock stacking" so that a
    // fullscreen client covers it, matching what the Wayland Top layer does.
    //
    // The reasoning was right and the mapping was not. `aboveWindows: false`
    // is not "normal stacking" — measured with xprop, it puts
    // _NET_WM_STATE_BELOW on the window, which stacks the capsule UNDER every
    // ordinary window, not merely under fullscreen ones. So any window that
    // reached the top strip — a floating terminal, a dialog, a browser moved
    // up — drew straight over the resting island, and the island only
    // reappeared once a panel opened and flipped this to true. That reads
    // exactly like "the island randomly disappears".
    //
    // Wayland's Top layer has no BELOW equivalent here: X11 offers above,
    // below, and nothing, and of those three "above" is the one that matches
    // Top. Fullscreen is not lost with it — qtile unmaps or raises over docks
    // for a genuine fullscreen client, which is the case the old rule was
    // reaching for, and it is handled by the WM rather than by us.
    aboveWindows: true

    // "exclusive" and "ondemand" both collapse to "can take focus", because
    // that is the only distinction X11 offers. The important half is the
    // false case: the resting capsule must NOT be focusable, or every notch
    // hover would pull focus off the window being typed into.
    readonly property bool wantsKeyboard: island.islandKeyboardFocus !== "none"

    focusable: island.wantsKeyboard

    // ---- AND `focusable` ALONE DOES NOTHING UNDER qtile -------------------
    //
    // Setting it is necessary and is not sufficient, and the gap between
    // those two is where every keyboard-driven panel was quietly broken.
    // Quickshell honours the property — the panel window really does
    // advertise `input focus: True` — but the window is a DOCK, and qtile
    // never hands a dock the keyboard no matter what it advertises. Measured
    // on the live session: with the launcher open, `xdotool type` landed in
    // the terminal behind the island, the picker's filter field ignored every
    // keystroke, and Escape closed nothing.
    //
    // So the focus is taken explicitly, with XSetInputFocus, which does not
    // consult the window manager. bin/x11-panel-focus.sh explains how it
    // finds the right window and why it retries.
    //
    // NO WAYLAND COUNTERPART, deliberately: WlrKeyboardFocus.Exclusive is a
    // real protocol-level grab that the compositor honours, so the Wayland
    // wrapper needs none of this.
    onWantsKeyboardChanged: panelFocus.run(island.wantsKeyboard)

    // ---- THE OPEN CASE ISN'T THE ONLY CASE ----
    //
    // Reported: open a panel, let X focus drift to some other window (any
    // deliberate click elsewhere does it — the follow-mouse suspension
    // above only ever guarded against an ENTER-NOTIFY hover-steal, never a
    // click), then click back into the still-open panel: q/Esc do nothing,
    // because the keypress is going wherever X actually thinks focus is,
    // which is not this window any more. `wantsKeyboard` never changed
    // across any of that — the panel was open the whole time — so
    // `onWantsKeyboardChanged` above never re-fires and the grab is never
    // reclaimed.
    //
    // `islandContainerActiveFocus` is DynamicIslandWindow.qml's own answer
    // to "something just asked this panel for the keyboard" — it is true
    // exactly when QML's `forceActiveFocus()` succeeds, which already
    // happens on a click into the panel's content from ~10 places. Watching
    // it here means every one of those click handlers gets this fix for
    // free, with no call site touched.
    onIslandContainerActiveFocusChanged: {
        if (island.islandContainerActiveFocus && island.wantsKeyboard)
            panelFocus.run(true);
    }

    Process {
        id: panelFocus

        property bool grabbing: false
        command: [Quickshell.env("HOME")
                  + "/.config/quickshell/tide-island-fork/bin/x11-panel-focus.sh",
                  panelFocus.grabbing ? "grab" : "release"]
        running: false

        // `running = false` first: assigning true to an already-running
        // Process is a no-op, and open/close pairs arrive faster than the
        // grab's retry loop can finish — a panel toggled quickly would
        // otherwise never issue its release and leave the keyboard stuck on
        // a panel that is no longer on screen.
        function run(grab) {
            running = false;
            grabbing = grab;
            running = true;
        }
    }
}
