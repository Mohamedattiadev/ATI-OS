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

    // "the tooltip for the topbar should be a bit under the bar, a bit
    // gap, and for the bottom one the tooltip should be a bit up" — now
    // that this bar actually has a working bottom position, hanging
    // BELOW the target unconditionally would try to render off the
    // bottom of the screen down there. true = hang below (top-bar case,
    // the only case this ever had to handle before); false = hang above.
    property bool belowTarget: true
    // The bar's own edge already has margins.top/bottom around it; this
    // is the EXTRA breathing room between the bar and the tooltip beyond
    // that, asked for directly ("a bit gap") against the flush-against-
    // the-bar look it had.
    property int gap: 6

    visible: root.target !== null && root.text !== ""

    anchor {
        window: root.target ? root.target.QsWindow.window : null
        rect.x: root.target ? root.target.mapToItem(null, 0, 0).x : 0
        rect.y: root.target ? (root.belowTarget ? root.target.height + root.gap : -root.gap) : 0
        rect.width: root.target ? root.target.width : 0
        // Centred under/over the chip depending on belowTarget.
        edges: root.belowTarget ? Edges.Bottom : Edges.Top
        gravity: root.belowTarget ? Edges.Bottom : Edges.Top
    }

    // ---- CAPPED, AND WRAPPED RATHER THAN LEFT TO GROW ----
    //
    // Reported: a long window title (a browser tab's page title, easily
    // 60+ characters) stretched this into one very wide single-line strip
    // instead of a tooltip. The bar's own task chip caps at max_title_width
    // and ellipses (TaskList.qml) precisely because a title is unbounded
    // text — the tooltip showing the FULL title on hover is still the
    // right idea (that is the whole reason it exists), it just cannot do
    // that by growing implicitWidth without a ceiling. Capped and wrapped
    // instead: short tooltips (the common case — one word, one phrase)
    // still render as one line at their natural width, exactly as before;
    // only a title past the cap wraps to a second/third line rather than
    // pushing the popup off the edge of a 1366 px bar.
    readonly property real maxLabelWidth: Metrics.s(260)

    implicitWidth: Math.min(label.implicitWidth, maxLabelWidth) + Metrics.s(20)
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
            width: Math.min(implicitWidth, root.maxLabelWidth)
            wrapMode: Text.WordWrap
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
            // and left-aligned are the same pixels — and now for a wrapped
            // long title too, where each line should still sit centred
            // rather than ragged-left.
            horizontalAlignment: Text.AlignHCenter
        }
    }
}
