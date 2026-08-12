import QtQuick
import Quickshell
import Quickshell.Wayland

import "../common"
import "../common/Metrics.js" as Metrics
import "../common/Motion.js" as Motion

//
// FORK — new file. The volume/brightness OSD as a standalone circular ring,
// off the island entirely, on request.
//
// WHY IT IS A SEPARATE WINDOW AND NOT ANOTHER ISLAND STATE
// --------------------------------------------------------
// The island already HAS a ring: OsdLayer.qml draws one, using the shared
// qml/common/ProgressRing.qml, inside the "split" capsule at the top of the
// screen. The request was not for a ring — it was for the ring to stop being
// part of the notch. A layer at the top edge that grows sideways is reading
// as "the bar changed", and the thing being adjusted is the whole machine,
// not the bar.
//
// So this is its own layer-shell surface in the middle of the screen, which
// is where every other desktop puts this and where the eye already is.
//
// IT MUST NOT TAKE INPUT
// ----------------------
// keyboardFocus None and an EMPTY input mask. Without the mask the surface
// is a 1366x768 transparent rectangle that eats every click on the desktop
// for as long as it is mapped — and it is mapped, invisible, most of the
// time. `aboveWindows`/Overlay is not the hazard; a fullscreen input sink
// is. The mask is set to a zero-size region rather than left default,
// because the default is "the whole surface".
//
// WHY Overlay AND NOT Top
// -----------------------
// Same reason the island promotes: Hyprland draws fullscreen windows above
// Top and below Overlay, and a volume OSD you cannot see while watching
// something fullscreen is a volume OSD that does not work when it is most
// used. Unlike the island this surface has no resting state to worry about
// — it is invisible unless something just changed.
//
PanelWindow {
    id: root

    required property var shellRootController

    property string iconText: ""
    property real progress: 0
    property string iconFontFamily: ""
    property color accentColor: "#e0563b"
    property color shellFill: "#1a1a1a"
    property bool shown: false

    // Full-screen surface, anchored on all four sides, with the ring placed
    // by anchors inside it. A small surface positioned by margins would have
    // to be re-placed on every resolution change; this one never moves.
    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true

    color: "transparent"
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.namespace: "quickshell-ring-osd"

    // THE INPUT MASK. See the header — without this the desktop is
    // unclickable. Region with no rects = nothing is interactive.
    mask: Region {}

    // Mapped only while visible, so the compositor is not compositing a
    // fullscreen transparent surface on every frame for the 99% of the time
    // nothing is being adjusted.
    visible: root.shown || fade.opacity > 0.01

    Item {
        id: fade
        anchors.fill: parent
        opacity: root.shown ? 1 : 0

        // Critically damped, like every other opacity in this shell: an
        // overshooting fade clips at 1.0 and reads as a cut. See Motion.js.
        Behavior on opacity {
            NumberAnimation {
                duration: root.shown ? Motion.fadeInDuration() : Motion.fadeOutDuration()
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Motion.fade()
            }
        }

        Rectangle {
            id: plate
            anchors.horizontalCenter: parent.horizontalCenter
            // Lower third rather than dead centre: centred puts it over the
            // subtitle line of anything being watched fullscreen, which is
            // the one case this exists to be visible in.
            //
            // Measured from the BOTTOM EDGE, not as a fraction of height.
            // `parent.height * 0.68` put the plate's top at 522 on this
            // 768 px screen and its bottom at 650 — 118 px of clearance,
            // which reads as jammed against the bottom rather than as
            // placed. Worse, the fraction makes the gap scale with the
            // screen: the same 0.68 on a 1440 px panel leaves 460 px and on
            // a 400 px one leaves nothing at all. A fixed clearance is what
            // "sitting above the bottom edge" actually means.
            y: parent.height - height - Metrics.px(170)
            width: Metrics.px(128)
            height: Metrics.px(128)
            radius: Metrics.px(30)
            // 0.97, not 0.92. Measured against a terminal: at 0.92 the text
            // behind the plate was legible THROUGH it, and a gauge you read
            // over someone else's words is a gauge you read twice. The
            // island's own surface is fully opaque for the same reason —
            // islandBackgroundOpacity defaults to 100 here because "bezel is
            // not translucent".
            color: Qt.rgba(root.shellFill.r, root.shellFill.g, root.shellFill.b, 0.97)

            // A hair of lift off the wallpaper. The island gets its
            // separation from being flush to the bezel; a floating plate has
            // nothing behind it, so it needs an edge.
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.07)

            // The plate scales very slightly on appear. 0.96 -> 1, which is
            // enough to read as arriving without being a pop.
            scale: root.shown ? 1 : 0.96
            Behavior on scale {
                NumberAnimation {
                    duration: Motion.morphDuration()
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Motion.spring()
                }
            }

            ProgressRing {
                id: ring
                anchors.centerIn: parent
                width: Metrics.px(84)
                height: width
                progress: root.progress
                lineWidth: Metrics.px(4)
                trackColor: Qt.rgba(1, 1, 1, 0.14)
                fillColor: root.accentColor
                // No core disc: the plate behind it already is one, and two
                // concentric fills is what made the island's first OSD read
                // as a target rather than a gauge.
                showCore: false

                Text {
                    anchors.centerIn: parent
                    text: root.iconText
                    color: "#f2f4f7"
                    // 40% of the ring, matching OsdLayer's 62%-of-a-smaller
                    // ring: this ring is bigger, so the same glyph ratio
                    // would crowd the stroke.
                    font.pixelSize: Math.round(ring.width * 0.40)
                    font.family: root.iconFontFamily
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Metrics.pad(11)
                text: Math.round(Math.max(0, Math.min(1, root.progress)) * 100) + "%"
                color: "#a8aeb8"
                font.pixelSize: Metrics.font(11)
                font.family: root.iconFontFamily
                font.weight: Font.DemiBold
            }
        }
    }
}
