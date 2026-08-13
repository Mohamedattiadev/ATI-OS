import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland

import "../common"
import "../common/Metrics.js" as Metrics

//
// ScreenCornersWindow — the four rounded display corners.
//
// FORK — new file. DESIGN-SPEC.md item; upgread_UI_UX.md P1-6.
//
// WHY THEY EXIST
// --------------
// The notch's entire argument is that it is BEZEL rather than a widget parked
// at the top of the screen. Bezel that stops at the top edge and leaves four
// hard 90° screen corners is bezel with a seam in it: the corners are what
// make the notch read as part of the machine.
//
// ---- HOW THEY HIDE OVER FULLSCREEN, WHICH COST NOTHING ----
//
// The user's call was "build them, but not over fullscreen video". The
// obvious implementation is to bind visibility to the focused window's
// fullscreen state — a Hyprland event subscription, a per-monitor lookup, and
// a race every time the state changes.
//
// None of that is needed, and DynamicIslandWindow.qml already had the answer
// written down: **Hyprland draws a fullscreen window ABOVE the Top layer and
// BELOW the Overlay layer.** That is the mechanism behind the island's own
// `islandRestingSurface` rule — the resting notch is on Top precisely so that
// it disappears under fullscreen, and only transient content promotes itself
// to Overlay.
//
// So these are on Top and the compositor does the hiding. No state to track,
// nothing to get out of sync, and it is the same rule the notch follows — so
// the bezel appears and disappears as ONE piece, which it would not if the
// corners had their own separate notion of when to be visible.
//
// That is also why this file is in qml/osd/ beside RingOsdWindow rather than
// in qml/island/: it is a standalone layer-shell surface, not an island state.
//
// ---- IT MUST NOT TAKE INPUT. THIS IS THE TRAP THE SPEC NAMES. ----
//
// "If you build anything full screen and decorative, that's a trap and it
// will confuse you for an hour." A transparent fullscreen surface with a
// default input region eats every click on the desktop for as long as it is
// mapped — and unlike the ring OSD, which is mapped only while shown, this
// one is mapped ALL THE TIME. The failure would be total and permanent.
//
// `mask: Region {}` is a region with no rects, i.e. nothing is interactive.
// The technique is RingOsdWindow's, which is why P1-6 was recorded as
// low-risk: the dangerous part was already solved and proven in this tree.
//
PanelWindow {
    id: root

    // The corner radius. Metrics.px(28) is the capsule's own radius — the
    // plan asks for the two to match so they read as one piece of bezel, and
    // matching it here means a future change to the capsule's shape carries
    // the screen corners with it instead of leaving them behind.
    readonly property real cornerRadius: Metrics.px(28)

    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true

    color: "transparent"

    // ---- IT RESERVES NOTHING AND IGNORES EVERY OTHER RESERVATION ----
    //
    // Measured on the first run: the surface came up 1366x735 on a 768 px
    // screen, at y=33. The missing 33 px is the ISLAND's own exclusive zone —
    // layer-shell hands a surface the area left over after earlier surfaces
    // have taken their reservations, so the top corners were being drawn a
    // third of an inch down the screen, tucked under the bar, curving around
    // nothing. A decoration of the DISPLAY has to be positioned against the
    // display, not against whatever is left of it.
    //
    // `exclusionMode: Ignore` is BOTH halves of that: this window claims no
    // zone of its own AND is laid out against the full output. The first
    // attempt wrote `exclusiveZone: 0` as well, on the reasoning that being
    // explicit about claiming nothing could not hurt — and it silently undid
    // the fix, because assigning `exclusiveZone` at all puts the window into
    // Normal mode. The geometry came back byte-identical at 1366x735 with no
    // warning, which is what made it worth a second measurement rather than a
    // glance.
    exclusionMode: ExclusionMode.Ignore

    // Top, not Overlay. See the header — this IS the hide-on-fullscreen
    // behaviour, not a compromise with it.
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.namespace: "quickshell-screen-corners"

    // THE INPUT MASK. See the header. Without this the desktop is unclickable
    // for the entire session.
    mask: Region {}

    // ---- ONE SHAPE, ROTATED FOUR TIMES ----
    //
    // Not four hand-written paths. Four copies of a curve is four chances for
    // one of them to be a pixel off, and the failure mode is the worst kind —
    // it looks fine until you notice one corner is wrong and then you cannot
    // stop seeing it. Rotating a single component makes them identical by
    // construction.
    //
    // The path fills the region OUTSIDE the quarter circle: the square corner
    // minus the rounded screen. So the fill is what you see and the arc is
    // where the desktop shows through.
    component Corner: Shape {
        id: corner

        // 0 = top-left, and the other three are this rotated about the
        // window's centre.
        property int quadrant: 0

        width: root.cornerRadius
        height: root.cornerRadius

        // The arcs are the only curved geometry in this shell that is drawn
        // once and never animates, so the higher-quality renderer is free.
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: 0
            strokeColor: "transparent"
            // The same material as the capsule. The island's fill follows the
            // theme — the user's explicit override of DESIGN-SPEC.md — so the
            // corners follow it too; a black corner beside a themed notch is
            // two different bezels.
            fillColor: IslandTheme.shellFill

            startX: 0
            startY: 0
            PathLine { x: corner.width; y: 0 }
            // Centre of the arc is the inner corner (r, r), so this sweeps
            // from directly above it to directly left of it — the quarter
            // that bulges toward the screen's corner, which is the edge of
            // the rounded display.
            PathArc {
                x: 0
                y: corner.height
                radiusX: corner.width
                radiusY: corner.height
                direction: PathArc.Counterclockwise
            }
            PathLine { x: 0; y: 0 }
        }
    }

    Corner {
        anchors.left: parent.left
        anchors.top: parent.top
    }

    Corner {
        anchors.right: parent.right
        anchors.top: parent.top
        rotation: 90
    }

    Corner {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        rotation: 180
    }

    Corner {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        rotation: 270
    }
}
