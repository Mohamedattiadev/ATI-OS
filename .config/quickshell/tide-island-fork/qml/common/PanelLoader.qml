import QtQuick

import "Motion.js" as Motion

//
// PanelLoader — a Loader that outlives its own dismissal.
//
// FORK — new file.
//
// THE BUG IT EXISTS TO FIX
// ------------------------
// Every panel layer in this shell fades itself:
//
//     opacity: showCondition ? 1 : 0
//     Behavior on opacity { NumberAnimation { ... } }
//
// and every one of them was mounted by
//
//     Loader { active: islandContainer.<panel>LayerVisible }
//
// which is the same boolean. So the instant `showCondition` went false and
// the fade-out was queued, `active` went false in the same event loop turn
// and DESTROYED the item that was about to run it. **The out-fade in all
// thirteen panel layers had never once executed.** It was written, it was
// tuned, it read as deliberate in every file, and it was dead code.
//
// Measured, closing the theme picker with grim frames timed off
// `date +%s%N` around the IPC call: at t=+58 ms the capsule is still ~700
// px wide and the entire 22-tile grid is already gone, with the resting
// clock already at full opacity inside it. The shape then spends another
// ~140 ms travelling to the notch as an empty black box. That is the
// "two-stage" feel: one frame of teleport, then 400 ms of shape.
//
// HOW IT FIXES IT
// ---------------
// `live` is the panel's real visibility and drives `showCondition`.
// `active` is `live` OR "a fade-out is still in flight", so the item
// survives exactly long enough to run the animation it already had.
//
// The hold is a Timer rather than a binding on `item.opacity`, which was
// the first attempt and is the more elegant-looking one:
//
//     active: live || (item && item.opacity > 0.01)
//
// That self-times perfectly for a layer that fades, and NEVER UNLOADS a
// layer that does not — one file forgetting its Behavior turns into a
// permanently mounted panel, which is a leak that presents as "the shell
// got slow after a while". A bounded timer cannot do that.
//
// The +40 ms is slack, not superstition: the Timer is started from
// onLiveChanged and the Behavior from the property write, so they begin in
// the same turn but not on the same frame boundary, and unloading one frame
// early clips the last 16 ms of the fade back into a pop.
//
Loader {
    id: root

    // The panel's actual visibility. Bind this, not `active`.
    property bool live: false

    active: live || holdTimer.running
    visible: active

    // asynchronous stays false, deliberately. These panels are opened by a
    // keypress and an asynchronous Loader would put an indeterminate number
    // of frames between the shape starting to grow and the content existing
    // at all — reintroducing, non-deterministically, the exact mistiming
    // this file is here to remove.
    asynchronous: false

    onLiveChanged: {
        if (live)
            holdTimer.stop();
        else
            holdTimer.restart();
    }

    // In `data` and not as a plain child: Loader's default property is
    // `sourceComponent`, so a bare child element is assigned there and the
    // panel silently becomes a Timer.
    data: [
        Timer {
            id: holdTimer
            interval: Motion.fadeOutDuration() + 40
            repeat: false
        }
    ]
}
