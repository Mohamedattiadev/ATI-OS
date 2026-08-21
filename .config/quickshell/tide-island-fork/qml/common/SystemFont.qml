pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

//
// SystemFont — the island's text follows the same shared `monospace`
// fontconfig alias every other surface in this repo already does (dunst,
// eww, qtile popups, and ati-menu's own base font — see
// `.config/AtiScriptsV1/omarchy-font-set`'s header comment for why that
// alias is the deliberately shared one).
//
// THIS REVERSES A DOCUMENTED PRIOR DECISION, ON PURPOSE
// -------------------------------------------------------
// userconfig.json's own `_typography` comment records that Inter/Inter
// Display/Inter Medium were chosen deliberately, substituting for macOS's
// SF Pro Text/Display per DESIGN-SPEC.md, and verified with fc-match to
// resolve to themselves. That choice stands as a record of what was
// decided and why — this file is a later, explicit reversal: asked
// directly whether the island's typography should match ati-menu's (the
// Super+Shift+/ command menu) rather than keep its own separate Inter
// pinning, given the whole-island blast radius that implies. Confirmed
// before writing this file. `iconFontFamily` (JetBrainsMono Nerd Font, for
// glyphs, not text) is untouched — this is about the TEXT registers only.
//
// NOT the same mechanism as `omarchy-font-set`/OMARCHY_MENU_FONT: that
// pair is deliberately scoped to the ati-menu POPUP ONLY, specifically so
// a menu font pick does not silently reach the system-wide alias (see its
// own header comment, and the "silent-substitution bug" it guards
// against). Following OMARCHY_MENU_FONT here would undo exactly the
// isolation that mechanism exists for. This singleton resolves the BASE
// `monospace` alias instead — the same fallback ati-menu's own Style.qml
// uses whenever OMARCHY_MENU_FONT is unset, which is the common case — so
// the island and the menu read as the same typeface without the menu's
// per-popup override leaking system-wide.
Singleton {
    id: root

    readonly property string family: root.resolvedFamily.length > 0 ? root.resolvedFamily : "monospace"
    property string resolvedFamily: ""

    function resolve() {
        fcMatchProc.running = true;
    }

    property Process fcMatchProc: Process {
        command: ["fc-match", "-f", "%{family[0]}", "monospace"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                const name = String(text || "").trim();
                if (name.length > 0)
                    root.resolvedFamily = name;
            }
        }
    }

    // `omarchy-font-current`'s own header explains why this is the one file
    // to watch: `fonts.conf`'s `monospace` alias is the single point every
    // one of these surfaces (dunst, eww, qtile popups, this island, and
    // ati-menu's own fallback) already reads.
    property FileView fontconfigFile: FileView {
        path: Quickshell.env("HOME") + "/.config/fontconfig/fonts.conf"
        watchChanges: true
        printErrors: false
        onFileChanged: root.resolve()
        onLoaded: root.resolve()
        onLoadFailed: root.resolve()
    }

    Component.onCompleted: resolve()
}
