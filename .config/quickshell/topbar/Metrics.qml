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
    readonly property int marginV: root.s(5)
    readonly property int marginH: root.s(10)

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
