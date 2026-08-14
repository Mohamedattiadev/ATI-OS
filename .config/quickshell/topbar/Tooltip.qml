import QtQuick
import Quickshell

//
// qtile's bar tooltips, which are a whole layer there: TooltipMixin injected
// into each widget instance's class, a per-widget delay timer, and
// _kill_all_tooltips() so two cannot be on screen at once.
//
// The strings are TOOLTIP_BY_NAME's, verbatim, so hovering the same chip says
// the same thing in either session.
//
// A POPUP WINDOW AND NOT AN ITEM IN THE BAR
// -----------------------------------------
// The bar is 38 px tall. Anything drawn below a chip inside it is clipped by
// the panel's own surface, so the tooltip has to be its own window anchored to
// the chip's rect. That is what PopupWindow is for, and it is the only window
// type here that positions itself against another window's geometry.
//
// ONE AT A TIME
// -------------
// qtile needs _kill_all_tooltips() because its tooltips are per-widget objects
// that outlive the pointer leaving. This does not: visibility is bound to one
// shared hover target in the bar, so a new hover replaces the old by
// construction and there is no second one to kill.
PopupWindow {
    id: root

    property string text: ""
    // The chip being hovered, in bar-window coordinates. Null means nothing is
    // hovered and the popup is not shown.
    property var target: null

    visible: root.target !== null && root.text !== ""

    anchor {
        window: root.target ? root.target.QsWindow.window : null
        rect.x: root.target ? root.target.mapToItem(null, 0, 0).x : 0
        rect.y: root.target ? root.target.height : 0
        rect.width: root.target ? root.target.width : 0
        // Centred under the chip, hanging below the bar.
        edges: Edges.Bottom
        gravity: Edges.Bottom
    }

    implicitWidth: label.implicitWidth + Metrics.s(20)
    implicitHeight: label.implicitHeight + Metrics.s(12)
    color: "transparent"

    Rectangle {
        anchors.fill: parent
        radius: Metrics.s(6)
        color: BarTheme.bgAlt
        border.width: 1
        border.color: BarTheme.alpha(BarTheme.fg, 0.14)

        Text {
            id: label
            anchors.centerIn: parent
            text: root.text
            color: BarTheme.fg
            // tooltip_font="Ubuntu" in config.py — the tooltip is the one
            // thing on this bar that is NOT bold, and _apply_tooltip_style
            // says so by naming the family without a style.
            font.family: Metrics.textFamily
            font.pixelSize: Metrics.s(10)
            renderType: Text.NativeRendering
            // The clock's tooltip is three lines — the prayer countdown over
            // the two FX lines — and config.py's tooltip block turns centring
            // on for exactly that widget ("Opt-in centring (w_clock: prayer
            // line over the FX lines)"). Unconditional here because the popup
            // is sized to its own text, so for the one-line tooltips centred
            // and left-aligned are the same pixels.
            horizontalAlignment: Text.AlignHCenter
        }
    }
}
