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

    // ---- THE ICON FACE, AND WHY THIS CARD NEEDS ONE ----
    //
    // Reported as "the tooltip ... of the dolar and eruo and pray need fix",
    // and magnifying it is what found it: the prayer line's leading glyph was
    // drawing as a little ECG waveform instead of a mosque.
    //
    // U+F0430 is a Nerd Font Material Design codepoint. `Inter Medium` — the
    // island's textFontFamily, which this card drew ALL of its text in — does
    // not have it, so Qt fell back to whichever installed face does, silently
    // and per the RULES ("font names fall back silently"; "supplementary-plane
    // Nerd Font glyphs DO render — the variable is the FACE").
    //
    // Checked rather than assumed, because the obvious next guess is that the
    // configured icon font is wrong too, and it is not:
    //
    //     fc-list ':charset=f0430'  ->  JetBrainsMono Nerd Font, FiraCode ...
    //     userconfig iconFontFamily ->  JetBrainsMono Nerd Font   (carries it)
    //     fc-match "Symbols Nerd Font" -> Noto Sans CJK KR        (does NOT
    //                                     exist; nothing here asks for it)
    //
    // So the face was right and this surface simply never asked for it.
    //
    // THE FIX IS TWO Texts, NOT A FALLBACK LIST, and the first attempt is
    // worth recording because it looks correct and fails at LOAD:
    //
    //     font.families: [textFontFamily, iconFontFamily]
    //     -> Cannot assign to non-existent property "families"
    //     -> Type IslandHoverTooltip unavailable
    //
    // `families` is QFont C++ API; the QML `font` VALUE TYPE does not expose
    // it. And per the RULES, a property that does not exist fails the whole
    // component, not the line — the island lost its tooltip entirely and said
    // so only in the log. So the glyph gets its own Text in the icon face,
    // which is what every other icon in this shell already does.
    property string iconFontFamily: ""

    // The leading Nerd Font glyph, split off the prayer line so it can be
    // drawn in a face that has it. Tested on the CODEPOINT rather than on a
    // literal: the glyph is chosen by prayer_next.sh and changes with the
    // prayer, so anything that named one would be wrong five times a day.
    // Private-use and supplementary-plane both live above 0xE000.
    readonly property string prayerGlyph: {
        const s = root.prayerBlock;
        if (s === "")
            return "";
        const cp = s.codePointAt(0);
        return cp >= 0xE000 ? String.fromCodePoint(cp) : "";
    }
    // `.length` and not 1: a supplementary-plane codepoint is TWO UTF-16 code
    // units, so slicing one character off by index would leave half a glyph.
    readonly property string prayerLabel: {
        const s = root.prayerBlock;
        return root.prayerGlyph === ""
            ? s : s.substring(root.prayerGlyph.length).trim();
    }

    readonly property bool shown: root.showCondition && root.text !== ""

    // ---- THE BLANK LINE WAS A WHOLE EMPTY ROW ----
    //
    // The provider joins the two blocks with "\n\n" — one prayer line, then
    // the two FX lines — and a real empty line at lineHeight 1.25 is ~16 px
    // here. Magnified, the card read as two cards: the prayer crammed against
    // the top, a hole, then the rates against the bottom.
    //
    // Split on the blank line and let a Column own the gap, so the separation
    // is a layout decision with a number on it instead of a side effect of
    // the string. The provider is untouched — it stays the one place the two
    // scripts are joined, which is the point of it.
    readonly property string prayerBlock: {
        const i = root.text.indexOf("\n\n");
        return i < 0 ? root.text : root.text.substring(0, i);
    }
    readonly property string ratesBlock: {
        const i = root.text.indexOf("\n\n");
        return i < 0 ? "" : root.text.substring(i + 2);
    }

    implicitWidth: body.implicitWidth + Metrics.pad(24)
    implicitHeight: body.implicitHeight + Metrics.pad(16)
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

        Column {
            id: body

            anchors.centerIn: parent
            // The gap the blank line used to be, and a third of its size. Big
            // enough to say "two blocks", small enough that they stay one card.
            spacing: Metrics.pad(5)

            // The glyph and the words are two Texts in two FACES. See above.
            Row {
                visible: root.prayerBlock !== ""
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Metrics.pad(5)

                Text {
                    text: root.prayerGlyph
                    visible: text !== ""
                    anchors.verticalCenter: parent.verticalCenter
                    color: IslandTheme.textPrimary
                    font.family: root.iconFontFamily
                    font.pixelSize: Metrics.font(12)
                    renderType: Text.NativeRendering
                }

                Text {
                    text: root.prayerLabel
                    anchors.verticalCenter: parent.verticalCenter
                    color: IslandTheme.textPrimary
                    font.family: root.textFontFamily
                    font.pixelSize: Metrics.font(12)
                    // qtile's `tooltip_font="Ubuntu"` — the tooltip is the
                    // one thing on that bar that is NOT bold, and
                    // `_apply_tooltip_style` says so by naming the family
                    // without a style. Kept: the weight is what separates a
                    // tooltip from the readouts around it.
                    font.weight: Font.Normal
                }
            }

            Text {
                text: root.ratesBlock
                visible: text !== ""
                anchors.horizontalCenter: parent.horizontalCenter
                color: IslandTheme.textPrimary
                font.family: root.textFontFamily
                font.pixelSize: Metrics.font(12)
                font.weight: Font.Normal
                lineHeight: 1.25
                // config.py turns centring on for exactly this widget
                // ("Opt-in centring (w_clock: prayer line over the FX
                // lines)"). The two currency lines are near enough the same
                // length that centring and left-aligning agree, but the
                // one-line fallback is shorter and this is what keeps it
                // under the middle of the capsule rather than off to a side.
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }
}
