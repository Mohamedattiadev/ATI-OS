import QtQuick
import QtQuick.Controls

import "Metrics.js" as Metrics
import "Motion.js" as Motion

//
// IslandScrollBar — the shell's one scroll indicator.
//
// FORK — new file.
//
// WHY IT EXISTS
// -------------
// upgread_UI_UX.md P1-3 counts the scroll indicators in this shell and finds
// two, in 31k lines of QML. Audited per file rather than per occurrence, it
// is worse than that number suggests: ELEVEN files carry a ListView, GridView
// or Flickable and exactly ONE of them — NotificationHistory — draws anything
// to say the content continues past the edge. The launcher, the theme picker,
// the settings list, both connectivity lists, the cheatsheet, the pickers and
// the treetab sidebar all scroll silently.
//
// The reason to make this a component rather than to paste the working one
// into ten more files is Phase 4's argument arriving early. This shell's
// stated disease is inventories where there should be systems — 11 type
// sizes, 15 spacings, 16 radii — and ten hand-placed scrollbars would be the
// twelfth inventory before the first one has been paid off. One file means
// the width, the colour and the fade rule are decided once.
//
// WHY `active` IS NOT THE QT DEFAULT
// ----------------------------------
// Qt's ScrollBar defaults to `active: false` and only shows itself while the
// attached view reports interaction. That is right for a mouse-driven list
// and wrong for this shell, where the most-used lists — settings, the
// launcher, the theme picker — are driven from the KEYBOARD. Arrowing down
// past the fold moves `contentY` without ever setting `moving` or `dragging`,
// so a purely interaction-gated bar is invisible exactly when the user most
// needs to know there is more below.
//
// So `active` also follows the view's own position: any programmatic scroll
// counts as activity. The bar still fades out when nothing is happening, so
// it is not permanent furniture over a short list.
//
ScrollBar {
    id: root

    // The Flickable this bar is attached to. Optional — without it the bar
    // still works as a plain Qt ScrollBar, it just loses the keyboard-scroll
    // reveal above, which needs to watch contentY.
    property Flickable view: null

    policy: ScrollBar.AsNeeded
    // Never steal the wheel from the view: this is an INDICATOR. Making it
    // interactive puts a 3 px drag target over the edge of every panel, and
    // on a shell whose panels are 3 px from the screen edge that is a
    // pointer trap rather than a control.
    interactive: false

    // Cross-axis size via IMPLICIT width and height rather than `width: 3`,
    // so one component serves both orientations. The launcher's GridView
    // flows TopToBottom with cellHeight bound to its own height, which makes
    // it a single-row HORIZONTAL scroller — a hardcoded `width` there would
    // have produced a 3 px-wide horizontal bar stretched across the panel.
    implicitWidth: Metrics.px(3)
    implicitHeight: Metrics.px(3)

    active: view
        ? (view.moving || view.dragging || revealTimer.running)
        : false

    // Both axes, for the same reason `active` is not left at Qt's default:
    // whichever one this bar is on, a programmatic scroll must count as
    // activity. Watching only contentY would leave the launcher — the most
    // keyboard-driven list in the shell — silent again.
    Connections {
        target: root.view
        enabled: root.view !== null

        function onContentYChanged() { revealTimer.restart(); }
        function onContentXChanged() { revealTimer.restart(); }
    }

    // Holds `active` up for a moment after a keyboard scroll stops, so the
    // bar is visible for the movement AND briefly after it, rather than
    // flickering off between two arrow presses.
    Timer {
        id: revealTimer
        interval: 900
        repeat: false
    }

    contentItem: Rectangle {
        radius: Metrics.px(1.5)
        color: IslandTheme.textDisabled

        // Critically damped, because this is opacity — see Motion.js on why
        // an overshooting fade reads as a cut.
        opacity: root.active ? 0.9 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: 180
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Motion.fade()
            }
        }
    }

    background: Rectangle {
        color: "transparent"
    }
}
