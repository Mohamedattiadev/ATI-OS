import QtQuick
import Quickshell
import Quickshell.Wayland

//
// DIRECTION A — "ghost bar" (macOS/GNOME menu-bar style)
// ========================================================
// Standalone preview: `qs -p redesign-a-flat.qml`.
//
// Zero chip soup, zero per-item boxes. ONE full-width flat backdrop behind
// the whole bar (for contrast against arbitrary wallpaper, same reason
// macOS's menu bar isn't pure glass over content) and everything else is
// plain text/icons floating directly on it. Workspaces are plain NUMBERS,
// not a different glyph per desk — nothing to memorise, and it removes the
// "icon soup" complaint outright rather than trying to tidy it. Icons only
// appear where they carry real information (battery, wifi, nightlight);
// everywhere else is a word. One accent colour, used only for the active
// workspace and the clock.
ShellRoot {
    id: demo

    component Glyph: Text {
        property color fg: BarTheme.alpha(BarTheme.fg, 0.7)
        color: fg
        font.family: "Symbols Nerd Font"
        font.pixelSize: Metrics.s(12)
        renderType: Text.NativeRendering
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
    }

    component Label: Text {
        property color fg: BarTheme.alpha(BarTheme.fg, 0.85)
        color: fg
        font.family: Metrics.textFamily
        font.pixelSize: Metrics.textSize + 1
        renderType: Text.NativeRendering
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
    }

    PanelWindow {
        screen: Quickshell.screens[0]
        anchors { top: true; left: true; right: true }
        implicitHeight: Metrics.barHeight + Metrics.marginV * 2
        margins.top: Metrics.barHeight + Metrics.marginV * 2 + Metrics.s(6)
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Top
        exclusionMode: ExclusionMode.Ignore

        // The ONE backdrop for the entire bar — not per pill, per item, or
        // per cluster. Everything sits on this single flat surface.
        Rectangle {
            anchors.fill: parent
            color: BarTheme.alpha(BarTheme.bg, 0.72)
        }

        Item {
            id: content
            anchors.fill: parent
            anchors.leftMargin: Metrics.s(16)
            anchors.rightMargin: Metrics.s(16)

            // ---- LEFT: workspace numbers, plain ----
            Row {
                id: leftRow
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: Metrics.s(14)

                Glyph { text: String.fromCodePoint(0xF0570); fg: BarTheme.purple; font.pixelSize: Metrics.s(14) }

                Row {
                    spacing: Metrics.s(11)
                    anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                    Repeater {
                        model: [1, 2, 3, 4, 5]
                        delegate: Label {
                            text: String(modelData)
                            fg: modelData === 3 ? BarTheme.accent : BarTheme.alpha(BarTheme.fg, 0.4)
                            font.bold: modelData === 3
                        }
                    }
                }
            }

            // ---- WINDOW TITLE: plain text, no icon, no box ----
            Label {
                anchors.left: leftRow.right
                anchors.leftMargin: Metrics.s(20)
                anchors.verticalCenter: parent.verticalCenter
                text: "ati-os-menu-feature-branch"
                fg: BarTheme.alpha(BarTheme.fg, 0.5)
                width: Math.min(implicitWidth, Metrics.s(220))
                elide: Text.ElideRight
            }

            // ---- RIGHT: words and the odd icon, generous gaps, no boxes ----
            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Metrics.s(18)

                Glyph { text: String.fromCodePoint(0xF0336) }             // tips
                Glyph { text: String.fromCodePoint(0xF240) }              // battery
                Label { text: "100%" }
                Label { text: "EN"; fg: BarTheme.alpha(BarTheme.fg, 0.5) }
                Glyph { text: String.fromCodePoint(0xF1A4C) }             // nightlight
                Label {
                    text: "Fri, Aug 21 · 19:37"
                    fg: BarTheme.accent
                    font.bold: true
                }
            }
        }
    }
}
