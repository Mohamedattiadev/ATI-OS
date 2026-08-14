pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

//
// The bar's scale, and the one place its size lives.
//
// qtile's `_s()` is a UI scale factor read from a file the wizard writes, and
// EVERY size in config.py's bar goes through it. Copying its outputs as
// literals would produce a bar that is correct on this laptop and wrong on
// any other display — so the factor is read here from the same file and
// applied the same way, including the floor of 1 so nothing rounds away to
// zero.
Singleton {
    id: root

    property real scale: 1.0

    function s(px) {
        return Math.max(1, Math.round(px * root.scale));
    }

    // 28, and it must stay in step with the chip radius derivation — Chip.qml
    // takes the radius from the plate's own height, so this is the only place
    // the number appears.
    readonly property int barHeight: root.s(28)

    // bar.Bar(margin=[5, 10, 5, 10]) — top, right, bottom, left.
    // config.py's bottom bar is size=_s(40) against the top bar's _s(28).
    readonly property int bottomBarHeight: root.s(40)

    readonly property int marginV: root.s(5)
    readonly property int marginH: root.s(10)

    // ---- THE TEXT FACE, AND WHY IT IS NOT "Ubuntu Bold" ----
    //
    // config.py's widget_defaults are `font="Ubuntu Bold", fontsize=_s(10)`,
    // and this bar copied that string into every `font.family`. It is not a
    // family name. pango parses a font DESCRIPTION — "Ubuntu Bold" is the
    // family Ubuntu plus the style Bold, which is why it works there — and Qt
    // parses a family, finds nothing called that, and falls back.
    //
    // Asked directly, which is the only way this shows at all:
    //
    //     fc-match "Ubuntu Bold"   ->  Noto Sans CJK KR, Regular
    //     fc-match "Ubuntu:bold"   ->  Ubuntu-B.ttf, Ubuntu Bold
    //
    // So every word on this bar was being drawn in Noto Sans CJK at regular
    // weight while every binding looked correct — reported as "the font in
    // the topbar is not the same font as the qtile bar", which it was not.
    //
    // Split into the family and the weight, which is what pango was doing
    // with the string all along. Named here rather than in each component so
    // the bold flag has one thing to compare against: an icon face is asked
    // for by name and must NOT be emboldened, since Symbols Nerd Font has no
    // bold cut and Qt would synthesise one.
    readonly property string textFamily: "Ubuntu"

    // fontsize=_s(10) in widget_defaults. qtile's fontsize is PIXELS — it
    // reaches pango through set_absolute_size(), which takes device units —
    // so it maps onto font.pixelSize directly and not through a point
    // conversion. Every chip that does not name its own size gets this, as
    // every qtile widget that does not name one gets widget_defaults'.
    readonly property int textSize: root.s(10)

    FileView {
        // The wizard's gpu/scale module writes this; absent on a machine that
        // has never run it, which is the common case and means scale 1.
        path: Quickshell.env("HOME") + "/.cache/qtile/ui_scale"
        watchChanges: true
        preload: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            const v = parseFloat(text());
            // The same 0.5-4.0 clamp config.py applies, and for the reason it
            // gives: refuse absurd values rather than rendering a 28 px bar as
            // 4 px and leaving no readable way to fix it.
            if (isFinite(v) && v >= 0.5 && v <= 4.0)
                root.scale = v;
        }
    }
}
