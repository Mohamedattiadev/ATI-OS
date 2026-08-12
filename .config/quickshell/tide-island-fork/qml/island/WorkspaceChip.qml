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

    // ---- THE CHIP IS THE COUNTDOWN'S RING, NOT A PILL ----
    //
    // Was a rounded-rectangle pill: shell fill at 0.92, a 1 px accent border
    // at 0.45 alpha, and the number inside. It worked, but it was the only
    // element in the resting bar with its own shape language — a lozenge
    // sitting next to a row of circles.
    //
    // Asked for directly, alongside the same change to the window strip: use
    // the ring the display panel's countdown draws (DisplayPanel.qml:832).
    // The fit is unusually exact, because that countdown is ALREADY a ring
    // with a number in the middle — it puts its remaining seconds there. A
    // workspace id is the same shape of content in the same size of hole, so
    // this is the shared component being used for the third time rather than
    // a pill restyled to look round.
    //
    // Its parameters, copied not approximated: 26 px, lineWidth 2.5,
    // showCore FALSE, track the same colour as the fill at a fifth alpha.
    // 26 rather than the old 22 so it matches the window rings exactly — the
    // chip and the icons sit on one line and any difference in diameter
    // reads as a mistake.
    //
    // progress is 1 and does not animate. On the window strip the arc means
    // "focused" and moves between icons; here there is only ever one
    // workspace chip and it is always the current one, so a full arc is the
    // honest reading and a partial one would imply a quantity that does not
    // exist.
    ProgressRing {
        id: chip

        // OsdLayer's ring, matching the window strip beside it: stroke 4,
        // white track at 0.16, and the dark CORE DISC. The core is why this
        // changed again — out on the wallpaper a hollow ring leaves the digit
        // floating on whatever photo is behind it, and the OSD ring brings
        // its own plate. The countdown's hollow 2.5 px ring is right only
        // where the countdown lives, on an already-dark panel.
        // 32, matching the timer ring and the window icons beside it.
        width: Metrics.px(32)
        height: width
        lineWidth: Metrics.px(4)
        showCore: true
        progress: 1
        fillColor: root.accentColor
        // No border ring - see the note in WindowRingStrip.qml. The dark
        // disc behind the digit carries it; an outline around it turned the
        // strip into a row of bordered buttons.
        trackColor: "transparent"
        coreColor: "#000000"
        coreBorderColor: "#000000"

        // The number is accent-coloured. The ring is small enough that a
        // grey digit inside it reads as disabled.
        Text {
            id: label
            anchors.centerIn: parent
            text: String(root.workspaceId)
            color: root.accentColor
            font.pixelSize: Metrics.font(12)
            font.family: root.textFontFamily
            font.weight: Font.DemiBold
            // Inter's default figures are already tabular-width for digits,
            // so a 1 and an 8 do not resize anything and the ring cannot
            // twitch on a workspace change.
        }
    }
}
