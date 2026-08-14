import QtQuick

//
// FORK — new file. The tour's swipe gestures.
//
// THE QUESTION THIS ANSWERS
// -------------------------
// Asked directly: "the onboarding i want to make it in the island so what
// is the best behavior for this swaping up or what?"
//
// The tour is already an island panel — pages, tabs as the step indicator,
// `$mod SHIFT I`. What it had no answer for was the gesture, and the answer
// is that "swipe up" is right for ONE of the two things a tour needs and
// wrong for the other:
//
//   HORIZONTAL  = the pages.    The tour is a linear sequence and its own
//                               tabs read left to right. Horizontal swipe
//                               already means "move between siblings" in
//                               this island — IslandRootGestureArea swipes
//                               the resting notch between time, lyrics and
//                               custom exactly that way — so paging with it
//                               is the vocabulary that is already here.
//
//   UP          = put it away.  The island hangs from the top edge. Pushing
//                               a panel up sends it back into the notch it
//                               came out of, which is the direction the
//                               shape itself suggests. This is the user's
//                               instinct and it is right; it just belongs
//                               on dismiss rather than on paging.
//
// Down does nothing on purpose. The obvious symmetry — up closes, down
// opens — cannot work from inside a panel that is already open, and giving
// down a second meaning here would make a two-finger scroll ambiguous at
// the exact moment the reader is least sure what anything does.
//
// WHY A WHEEL HANDLER AND NOT A DRAG
// ----------------------------------
// This machine is a laptop. A two-finger swipe on the touchpad arrives as
// wheel events, both axes, so wheel handling IS swipe handling here and a
// DragHandler would additionally need a press — which means claiming mouse
// buttons, which means swallowing clicks on the tabs and the footer. With
// `acceptedButtons: Qt.NoButton` this area is transparent to every click in
// the panel and only ever sees the scroll.
//
MouseArea {
    id: root

    // Called with +1 / -1.
    signal paged(int delta)
    signal dismissed()

    hoverEnabled: false
    acceptedButtons: Qt.NoButton

    // ---- THE THRESHOLDS, AND WHY THEY DIFFER ----
    //
    // Paging is cheap and reversible: the wrong page is one swipe back. It
    // gets the smaller threshold so the tour feels like it is being flicked
    // through rather than argued with.
    //
    // Dismissing throws the panel away, so it costs roughly three times as
    // much travel. That asymmetry is the whole reason these are two numbers
    // instead of one: an accidental vertical component while swiping
    // sideways must never close the tour, and on a touchpad there is ALWAYS
    // a vertical component.
    readonly property real pageThreshold: 55
    readonly property real dismissThreshold: 165

    property real accumulatedX: 0
    property real accumulatedY: 0

    // A gesture ends when the events stop, not when a finger lifts — the
    // wheel protocol has no "up". Everything accumulated is dropped after a
    // pause so the next swipe starts from zero instead of inheriting the
    // tail of the last one.
    Timer {
        id: idle
        interval: 180
        onTriggered: {
            root.accumulatedX = 0;
            root.accumulatedY = 0;
        }
    }

    onWheel: (wheel) => {
        // pixelDelta when the device has one (touchpads do), angleDelta/4
        // otherwise — the same normalisation IslandRootGestureArea uses, and
        // it matters because the two are an order of magnitude apart.
        const dx = wheel.pixelDelta.x !== 0 ? wheel.pixelDelta.x : wheel.angleDelta.x / 4;
        const dy = wheel.pixelDelta.y !== 0 ? wheel.pixelDelta.y : wheel.angleDelta.y / 4;

        root.accumulatedX += dx;
        root.accumulatedY += dy;
        idle.restart();

        // The dominant axis wins outright. Without this a diagonal swipe
        // fires both, and "paged AND dismissed" is not a state the panel can
        // be in — you would land on page three of a tour that is closing.
        if (Math.abs(root.accumulatedX) > Math.abs(root.accumulatedY)) {
            if (Math.abs(root.accumulatedX) >= root.pageThreshold) {
                // Natural scrolling is on for the touchpad here (see
                // hypr/input.conf), so content follows the fingers: pushing
                // the page LEFT means going forward.
                root.paged(root.accumulatedX < 0 ? 1 : -1);
                root.accumulatedX = 0;
                root.accumulatedY = 0;
            }
        } else if (root.accumulatedY >= root.dismissThreshold) {
            root.dismissed();
            root.accumulatedX = 0;
            root.accumulatedY = 0;
        }

        // Not accepted, for the same reason IslandRootGestureArea does not
        // accept: anything underneath that wants to scroll still can.
        wheel.accepted = false;
    }
}
