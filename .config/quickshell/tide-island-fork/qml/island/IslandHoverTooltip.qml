import QtQuick

import "../common"
// FORK: one shared scale factor for every island surface.
import "../common/Metrics.js" as Metrics
// FORK: the shared motion system — see qml/common/Motion.js.
import "../common/Motion.js" as Motion

//
// FORK — new file. The resting capsule's tooltip: next prayer, then USD and
// EUR quoted in TL and EGP.
//
// WHAT IT IS A PORT OF
// --------------------
// qtile's clock chip. config.py's `_clock_tooltip_text` runs two scripts and
// joins them with a blank line, and `install_bar_tooltips()` swaps that in as
// the clock's LIVE provider over the static `TOOLTIP_BY_NAME` entry. Both
// halves matter and the second one is the one that is easy to miss — see the
// RULE, "a tooltip that is a LABEL and one that is DATA are different
// things". The provider lives in DynamicIslandWindow.qml beside the Process
// that feeds it; this file is only the surface it is drawn on.
//
// The Quickshell topbar (../../topbar/Tooltip.qml) ported the same thing for
// the native-bar session. This is deliberately NOT that file reused: that one
// is a `PopupWindow` anchored to a chip's rect, because the topbar is 38 px
// tall and anything drawn below a chip inside it is clipped by the panel's own
// surface. The island has no such problem — its layer surface already grows to
// whatever the capsule needs (see `capsuleWindowHeight`) — so this is an Item
// inside the island window, which costs no second surface and lets it ride the
// same fade every other layer in this shell uses.
//
// IT IS NOT IN THE INPUT MASK, AND THAT IS THE POINT
// --------------------------------------------------
// The mask at the top of DynamicIslandWindow.qml is the union of the capsule,
// the gesture strip and the window rings. This card is in none of them, so the
// pointer passes straight through it to whatever is underneath. A tooltip that
// can be hovered is a tooltip that flickers: the pointer would leave the
// capsule to enter the card, the card would hide, the pointer would be back
// over the capsule, and it would show again. Leaving it out of the mask is
// what makes the hover state honest — it is the CAPSULE that is hovered, and
// nothing else can claim it.
//
Item {
    id: root

    // The provider's text. Blank means there is nothing to say and the card
    // does not appear at all — checked here as well as at the call site so
    // the surface can never draw an empty box.
    property string text: ""
    property bool showCondition: false
    property string textFontFamily: ""

    readonly property bool shown: root.showCondition && root.text !== ""

    implicitWidth: label.implicitWidth + Metrics.pad(24)
    implicitHeight: label.implicitHeight + Metrics.pad(16)
    width: implicitWidth
    height: implicitHeight

    // `visible` and not just opacity: an invisible-but-present Item still
    // reports width and height, and the window's own height is derived from
    // this card's extent while it is up. A card that is faded out but still
    // counted would hold the layer surface tall forever.
    visible: opacity > 0.01
    opacity: root.shown ? 1 : 0

    // FORK: one choreography for every layer in the shell. See Motion.js.
    // No PauseAnimation on the way in — unlike a panel, this surface is
    // ALREADY delayed, by the hover timer that decides to show it at all, and
    // stacking a second delay on top of that is how a tooltip ends up feeling
    // like it arrived late rather than deliberately.
    Behavior on opacity {
        NumberAnimation {
            duration: root.shown ? Motion.fadeInDuration() : Motion.fadeOutDuration()
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Motion.fade()
        }
    }

    // A few px of travel under the fade, so it reads as coming OUT of the
    // capsule rather than being switched on beside it. Small on purpose: the
    // card is only ~60 px tall and anything more turns into a slide.
    transform: Translate {
        y: (1 - root.opacity) * -Metrics.px(6)
    }

    Rectangle {
        anchors.fill: parent
        radius: Metrics.px(8)
        // surfaceRaised and not shellFill: this sits UNDER the capsule, which
        // is drawn in shellFill, and two surfaces of the same tone with a
        // hairline between them read as one shape with a crack in it.
        color: IslandTheme.surfaceRaised
        border.width: 1
        border.color: IslandTheme.hairline

        Text {
            id: label
            anchors.centerIn: parent
            text: root.text
            color: IslandTheme.textPrimary
            font.family: root.textFontFamily
            font.pixelSize: Metrics.font(12)
            // qtile's `tooltip_font="Ubuntu"` — the tooltip is the one thing
            // on that bar that is NOT bold, and `_apply_tooltip_style` says so
            // by naming the family without a style. Kept: the weight is what
            // separates a tooltip from the readouts around it.
            font.weight: Font.Normal
            lineHeight: 1.25
            // Three lines — the prayer countdown over the two FX lines — and
            // config.py turns centring on for exactly this widget ("Opt-in
            // centring (w_clock: prayer line over the FX lines)"). The card is
            // sized to its own text, so for a one-line fallback centred and
            // left-aligned are the same pixels.
            horizontalAlignment: Text.AlignHCenter
        }
    }
}
