import QtQuick

// ProgressRing lives here — the shared ring the countdown, the volume OSD and
// the window strip all draw. Directory import, not a file import.
import "../common"
import "../common/Metrics.js" as Metrics
import "../common/Motion.js" as Motion

//
// FORK — new file. The persistent "which workspace am I on" readout.
//
// WHY IT IS NOT INSIDE THE PILL
// -----------------------------
// The island already had a workspace display: WorkspaceLayer.qml, the
// "Workspace 5" long capsule that appears for a moment when you switch and
// then goes away. That answers "did the switch happen", which is a different
// question from "where am I", and it answers it only in the two seconds when
// you already know.
//
// The obvious fix is to put a number in the resting capsule beside the
// clock. That capsule is `islandWidth` wide — 135 px on this machine, and
// already holding a 24-hour clock plus, when music plays, four EQ bars it
// had to grow `restingEqAllowance` to fit. Adding a second permanent
// occupant means widening it again, and every one of the ~20 `islandState`
// cases in mainCapsule.baseTargetWidth is arithmetic against that width.
//
// So the chip is a SIBLING of mainCapsule, not a child, sitting in the empty
// bar to its left. The layer surface is the full screen width (1366 px here)
// against a 135 px pill, so there are ~615 px of unused bar on each side;
// this costs the capsule nothing and cannot perturb a morph.
//
// IT IS NOT INTERACTIVE, BY CONSTRUCTION
// --------------------------------------
// The island window's input Region is built from mainCapsule's rectangle
// alone (see the mask near the top of DynamicIslandWindow.qml). Anything
// outside that rectangle is drawn but unclickable, which is exactly right
// for a readout — and it means this cannot steal a click from the desktop
// the way a naive full-width surface would.
//
Item {
    id: root

    // 0 when the island is hidden, 1 when it rests. Bound to the same
    // autoHideProgress the capsule uses so the chip cannot linger on screen
    // after the thing it belongs to has gone.
    property real revealProgress: 1
    property int workspaceId: 1
    property string textFontFamily: ""
    property color accentColor: "#51afef"
    property color fillColor: "#1a1a1a"
    property bool showCondition: true

    implicitWidth: chip.width
    implicitHeight: chip.height

    opacity: showCondition ? revealProgress : 0
    visible: opacity > 0.01

    Behavior on opacity {
        NumberAnimation {
            duration: root.showCondition ? Motion.fadeInDuration() : Motion.fadeOutDuration()
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Motion.fade()
        }
    }

    // ---- INSIDE THE CAPSULE IT IS TYPE, NOT A RING ----
    //
    // History, because this element has now been three things and each change
    // was driven by WHERE it sits rather than by taste.
    //
    //   1. a rounded pill with a border  - the only lozenge in a row of circles
    //   2. the timer's ring on a dark disc - correct while it sat OUT ON THE
    //      WALLPAPER beside the pill, where the disc separated the digit from
    //      whatever photo was behind it and the ring gave that disc an edge
    //   3. plain type - now that it lives INSIDE the capsule
    //
    // The ring did not survive the move and could not have. Its disc was
    // IslandTheme.shellFill, which is the capsule's own material, so against
    // the capsule the disc is invisible by construction and all that remained
    // on screen was a heavy 4 px accent stroke floating next to the clock.
    // Every reason the ring existed was a reason about wallpaper, and there is
    // no wallpaper in here.
    //
    // So the workspace id is set as type, in the register the capsule already
    // speaks: the clock is white hero type, and this is the same type one step
    // smaller and in the accent, which is exactly how the connectivity headers
    // carry their "· status" clause. A companion to the clock rather than a
    // second object competing with it.
    //
    // No ring, no plate, no border. The accent alone says "this is the live
    // workspace"; nothing else in the resting capsule is accent-coloured.
    Text {
        id: chip

        text: String(root.workspaceId)
        color: root.accentColor
        // A step under the clock. Deliberately not equal to it: two numbers at
        // the same size next to each other read as one value split in half,
        // which is how a workspace id starts looking like part of the time.
        font.pixelSize: Metrics.font(13)
        font.family: root.textFontFamily
        font.weight: Font.DemiBold
        // Tabular figures so a 1 and an 8 occupy the same width. The capsule
        // reserves a fixed allowance for this, and a proportional digit would
        // make the clock shift sideways on a workspace change.
        font.features: ({ "tnum": 1 })
    }
}
