pragma ComponentBehavior: Bound

import QtQuick

import "Metrics.js" as Metrics
import "Motion.js" as Motion

//
// PanelRow — the selected-row treatment, once.
//
// FORK — new file.
//
// WHAT IT OWNS, AND WHAT IT DELIBERATELY DOES NOT
// -----------------------------------------------
// It owns the SURFACE of a list row: its height, its radius, how the cursor
// is drawn on it, how a row that is ALSO a fact about the system is drawn,
// the divider under it, and the MouseArea that moves the cursor.
//
// It does NOT own the row's content. Nine delegates lay out genuinely
// different things — an SSID with a signal bar and a percentage, a sink with
// a volume level, a filesystem with a usage ring — and folding those into one
// component would mean nine sets of optional slots, which is a bigger tangle
// than the nine delegates are. The thing that actually diverged across those
// nine files is the treatment, not the content, so the treatment is what gets
// extracted. Children are laid out by the caller inside `contentItem`.
//
// ---- THE CURSOR IS NEUTRAL AND THE STATE IS ACCENT. NOT THE OTHER WAY. ----
//
// This is WifiPanel's rule, promoted rather than invented, and its reason is
// the strongest argument in any of the nine files:
//
//     the CONNECTED row is accent-tinted because it is a fact about the
//     system; the keyboard cursor is neutral because it is a fact about the
//     pointer. If the cursor used the accent too, moving it would look like
//     connecting.
//
// So `active` (connected, current sink, default output) takes a faint accent
// wash and `selected` (where the cursor is) takes a neutral raised fill. The
// two are legible together, which matters because the cursor starts on the
// active row in most of these panels.
//
// ---- WHY THERE IS A LEADING BAR ----
//
// A neutral fill alone is weak. `surfaceRaised` is the surface mixed 7%
// toward the ink, and on the lighter palettes in this shell's 21 that is a
// difference you have to look for — the cursor was legible on catppuccin and
// nearly invisible on the light ones, which is the class of bug a theme
// system is supposed to remove rather than create.
//
// The bar is 2 px of accent on the leading edge, and it is unambiguous
// BECAUSE only one row in a list ever has one. It does not collide with the
// accent-means-state rule above: state is a wash across the whole row, the
// cursor is an edge. They are different shapes, not different intensities of
// the same shape, which is what makes them readable at a glance instead of by
// comparison.
//
// ---- HOVER MOVES THE CURSOR ----
//
// `containsMouse` is not read here and that is the settled interaction model,
// not an omission: one selection indicator driven by BOTH the keyboard and
// the pointer. `onEntered` moves the cursor; there is no second highlight
// beside it. See the P1-3 audit in upgread_UI_UX.md for why the grep that
// says otherwise is misleading.
//
Rectangle {
    id: root

    // Where the cursor is.
    property bool selected: false

    // A fact about the system: connected, current, default. Not the cursor.
    property bool active: false

    // ---- ARMED: THE NEXT KEYSTROKE DOES SOMETHING YOU CANNOT UNDO ----
    //
    // PowerMenuLayer is the case and the reason this is a THIRD state rather
    // than a caller-supplied colour. Its note is the argument: "the confirming
    // row goes RED, not merely highlighted. The state it is announcing is 'the
    // next keystroke does this', and a selection colour is what the row already
    // had — a second shade of the same thing would be a change you can miss."
    //
    // It outranks both of the others, because a row can be armed while it is
    // also the cursor (it always is) and the cursor is the less urgent fact.
    property bool armed: false

    // Rows that cannot be chosen — an unavailable device, a header row in a
    // mixed list. Drawn at rest and takes no pointer.
    property bool enabled: true

    // The divider under this row. Defaulted rather than always-on: a rule
    // under a filled row is noise, and the fill already separates it from
    // what follows.
    property bool dividerVisible: !root.selected && !root.active && !root.armed

    // Emitted instead of the caller reaching into the MouseArea, so every row
    // in the shell reports the same two events.
    signal cursorRequested()
    signal activated()

    // Content goes here. `default` so a caller writes children directly.
    default property alias contentData: contentItem.data
    readonly property alias contentItem: contentItem

    // The inset the content sits at, exposed so a caller aligning something
    // to the row's text can use the same number rather than guess it.
    readonly property real contentPadding: Metrics.pad(10)

    height: Metrics.px(26)
    radius: Metrics.RADIUS.card

    color: {
        if (root.armed)
            return IslandTheme.dangerFill;
        if (root.active)
            return IslandTheme.alpha(IslandTheme.accent, 0.14);
        if (root.selected)
            return IslandTheme.surfaceRaised;
        return "transparent";
    }

    // The fill changes on every cursor move, so it is animated — an
    // instantaneous swap between two low-contrast fills reads as a flicker
    // rather than as movement. Motion.fade() and not spring(): a colour is
    // clamped and an overshooting colour is a different colour.
    Behavior on color {
        ColorAnimation {
            duration: Motion.fadeInDuration()
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Motion.fade()
        }
    }

    // ---- THE CURSOR BAR ----
    //
    // Inset vertically so it reads as a mark ON the row rather than as the
    // row's own left edge, and rounded on its own so it does not fight the
    // row's corner radius at the top-left.
    Rectangle {
        id: cursorBar
        x: Metrics.px(3)
        anchors.verticalCenter: parent.verticalCenter
        width: Metrics.px(2)
        height: parent.height - Metrics.px(8)
        radius: width / 2
        // Danger, not accent, on an armed row: the bar is the cursor and the
        // cursor is still there — it just stops being the most important
        // thing about the row.
        color: root.armed ? IslandTheme.danger : IslandTheme.accent
        opacity: root.selected ? 1 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: Motion.fadeInDuration()
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Motion.fade()
            }
        }
    }

    Item {
        id: contentItem
        anchors.fill: parent
        anchors.leftMargin: root.contentPadding
        anchors.rightMargin: root.contentPadding
    }

    // ---- THE DIVIDER SITS OUTSIDE THE RADIUS ----
    //
    // Drawn at the row's bottom edge and inset by the content padding on both
    // sides, so a column of rows reads as one ruled block rather than as a
    // stack of separate cards. Full-bleed rules touch the panel's own inner
    // edge and make the list look like it is falling out of the shell.
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: root.contentPadding
        anchors.rightMargin: root.contentPadding
        anchors.bottom: parent.bottom
        height: Metrics.RADIUS.hairline
        color: IslandTheme.hairline
        visible: root.dividerVisible
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        enabled: root.enabled
        onEntered: root.cursorRequested()
        onClicked: {
            root.cursorRequested();
            root.activated();
        }
    }
}
