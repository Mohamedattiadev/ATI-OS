import QtQuick
import Quickshell
import Quickshell.Wayland

//
// DIRECTION B — "two strips" (Windows 11 / modern-Waybar style)
// ================================================================
// Standalone preview: `qs -p redesign-b-strips.qml`.
//
// Not zero chrome like direction A, and not six little pills like the
// earlier drafts either — exactly TWO solid strips: everything on the left
// (menu, workspaces, window title) shares one, everything on the right
// (toggles, status, tray, clock) shares the other. Inside a strip, items
// are separated by spacing and the very occasional hairline divider — never
// their own background. Active workspace is an underline bar beneath the
// number (the Windows 11 taskbar convention for "this one is open"), not a
// capsule behind it. Icons are monochrome and one size everywhere; the only
// colour is the accent, spent on the active workspace's underline and the
// clock.
ShellRoot {
    id: demo

    component Strip: Rectangle {
        id: strip
        default property alias content: row.children
        property int hgap: Metrics.s(16)
        height: parent ? parent.height : Metrics.barHeight
        width: row.implicitWidth + hgap * 2
        radius: Metrics.s(8)
        color: BarTheme.alpha(BarTheme.bg, 0.6)
        border.width: 1
        border.color: BarTheme.alpha(BarTheme.fg, 0.08)

        Row {
            id: row
            anchors.centerIn: parent
            spacing: Metrics.s(16)
        }
    }

    component Divider: Rectangle {
        width: 1
        height: Metrics.s(14)
        color: BarTheme.alpha(BarTheme.fg, 0.12)
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
    }

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
        font.pixelSize: Metrics.textSize
        renderType: Text.NativeRendering
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
    }

    PanelWindow {
        screen: Quickshell.screens[0]
        anchors { top: true; left: true; right: true }
        implicitHeight: Metrics.barHeight + Metrics.marginV * 2
        // Stacked below direction A (which sits right under the real bar),
        // so real bar / A / B all show at once for a three-way comparison.
        margins.top: (Metrics.barHeight + Metrics.marginV * 2 + Metrics.s(6)) * 2
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Top
        exclusionMode: ExclusionMode.Ignore

        Item {
            id: content
            anchors.fill: parent
            anchors.topMargin: Metrics.marginV
            anchors.bottomMargin: Metrics.marginV
            anchors.leftMargin: Metrics.marginH
            anchors.rightMargin: Metrics.marginH

            // ================= LEFT STRIP =================
            Strip {
                id: leftStrip
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter

                Glyph { text: String.fromCodePoint(0xF0570); fg: BarTheme.purple; font.pixelSize: Metrics.s(14) }

                Divider {}

                Row {
                    spacing: Metrics.s(12)
                    anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                    Repeater {
                        model: [1, 2, 3, 4, 5]
                        delegate: Column {
                            spacing: Metrics.s(3)
                            Label {
                                text: String(modelData)
                                fg: modelData === 3 ? BarTheme.fg : BarTheme.alpha(BarTheme.fg, 0.4)
                                font.bold: modelData === 3
                                anchors.verticalCenter: undefined
                                anchors.horizontalCenter: parent.horizontalCenter
                            }
                            Rectangle {
                                width: Metrics.s(12); height: Metrics.s(2); radius: 1
                                color: modelData === 3 ? BarTheme.accent : "transparent"
                                anchors.horizontalCenter: parent.horizontalCenter
                            }
                        }
                    }
                }

                Divider {}

                Label {
                    text: "ati-os-menu-feature-branch"
                    fg: BarTheme.alpha(BarTheme.fg, 0.6)
                    width: Math.min(implicitWidth, Metrics.s(180))
                    elide: Text.ElideRight
                }
            }

            // ================= RIGHT STRIP =================
            Strip {
                id: rightStrip
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter

                Glyph { text: String.fromCodePoint(0xF0336) }
                Glyph { text: String.fromCodePoint(0xF05AF) }
                Glyph { text: String.fromCodePoint(0xF0902) }

                Divider {}

                Glyph { text: String.fromCodePoint(0xF240); font.pixelSize: Metrics.s(11) }
                Label { text: "100%" }
                Label { text: "EN"; fg: BarTheme.alpha(BarTheme.fg, 0.55) }

                Divider {}

                Glyph { text: String.fromCodePoint(0xF1A4C) }
                Glyph { text: String.fromCodePoint(0xF029) }

                Divider {}

                Label {
                    text: "Fri, Aug 21  19:37"
                    fg: BarTheme.accent
                    font.bold: true
                    font.pixelSize: Metrics.textSize + 1
                }
            }
        }
    }
}
