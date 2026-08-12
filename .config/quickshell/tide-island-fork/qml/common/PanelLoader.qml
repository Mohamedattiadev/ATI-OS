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
//
// ---------------------------------------------------------------------------
// `retain` — THE EMPTY-PANEL FLASH
// ---------------------------------------------------------------------------
//
// The hold above fixed the fade-out. It did not fix what happens on the way
// back IN, and that turned out to be the bigger of the two.
//
// Measured, driving every ordered pair of panels over IPC and counting "ink"
// (pixels inside the capsule that are not the flat fill) frame by frame at
// ~45 ms:
//
//     wifi     -> bluetooth   ink falls to 17% of the smaller endpoint at 117 ms
//     settings -> display     ink falls to  9% at 116 ms
//     audio    -> display     ink falls to 53% at  98 ms
//     calendar -> power       ink never falls below 97%
//
// The capsule is very nearly EMPTY for two to three frames in the middle of
// the swap, and then the content pops in. That is the "glitchy". Caught in a
// screenshot at +104 ms, the display panel has drawn its title, its tabs and
// its footer hints, and its body says "no output selected".
//
// The cause is not the fade and not the morph. It is this Loader. A panel is
// destroyed `fadeOutDuration + 40` ms after it closes, so every open builds a
// FRESH instance whose model is empty — DisplayPanel starts at `outputs: []`,
// AudioPanel at no devices — and every one of them fetches asynchronously in
// `onShowConditionChanged`. So the panel renders its EMPTY STATE first and its
// real content one process round-trip later. Calendar and the power menu are
// the control group: their content is computed, not fetched, so they never
// flash, which is exactly the split the numbers show.
//
// `retain` keeps the instance alive once built. `live` still drives
// `showCondition`, so the fades, the focus grabs and the poll timers behave
// exactly as before — the only thing that changes is that the panel's
// last-known data survives the close, so the reopen paints real content on
// frame one and the refresh updates it in place.
//
// It is safe to leave these mounted, and that was checked rather than assumed:
// AudioPanel and WifiPanel start their poll timers in the `showCondition` true
// branch and stop them in the false branch, so a retained-but-hidden panel
// polls nothing. A panel that polled unconditionally would be a battery leak
// dressed up as a fix.
//
// It is opt-in rather than the default because retention costs whatever the
// panel holds — for the four data panels that is a few rows of text, but the
// wallpaper picker holds decoded thumbnails and that is a memory question with
// a different answer.
//
Loader {
    id: root

    // The panel's actual visibility. Bind this, not `active`.
    property bool live: false

    // Keep the instance once it has been built. See the note above.
    property bool retain: false
    property bool everLoaded: false

    active: live || holdTimer.running || (retain && everLoaded)

    // NOT `active`. With `retain` the loader stays active forever, and binding
    // visibility to it would leave every retained panel painted on top of the
    // resting island permanently. Visibility is still the panel's real
    // lifetime — live, plus the hold that lets the out-fade finish.
    visible: live || holdTimer.running

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
        },

        // `everLoaded` is latched through a Connections and NOT through a
        // plain `onLoaded:` handler on this Loader, and that is not style.
        //
        // A signal handler written at the INSTANTIATION site replaces the one
        // written in the component definition — it does not run in addition to
        // it. bluetoothPanelLoader and wifiPanelLoader both declare their own
        // `onLoaded:` to grab keyboard focus, so a handler here would have
        // been silently discarded for exactly the two panels this is for, and
        // `retain` would have looked like it simply did not work on them —
        // with no warning, because overriding a handler is legal QML.
        //
        // A Connections object is a separate receiver, so it fires alongside
        // whatever the instantiation site declares.
        Connections {
            target: root
            function onLoaded() {
                root.everLoaded = true;
            }
        }
    ]
}
