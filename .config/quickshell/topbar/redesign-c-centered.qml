import QtQuick
import Quickshell
import Quickshell.Wayland

//
// DIRECTION C — rounded strips (kept from B, that part landed) + centred
// workspaces + an overlapping app-icon stack instead of a text/badge title
// ============================================================================
// Standalone preview: `qs -p redesign-c-centered.qml`.
//
// Feedback on A/B, folded in:
//   1. The ROUNDED strip look (border + radius, direction B's right side)
//      is the container language now — used on every pill, not just one.
//   2. Workspaces move to the true centre of the bar (anchors.horizontalCenter
//      on the window, same as the original shell.qml's centreGroup), not
//      left-anchored next to the menu icon.
//   3. The window/title slot is no longer a text label + "+2" badge. It's a
//      STACK of overlapping app-icon chips, one per open window, fanned like
//      a hand of cards — the focused one drawn on top, ringed in accent and
//      a touch larger, exactly the "()))) and the open one is here" ask.
//   4. The layout indicator is a real bracket glyph — U+F0DB / U+F096 /
//      U+F00B, JetBrainsMono Nerd Font — pulled directly from
//      tide-island-fork/qml/common/LayoutState.qml rather than invented
//      here: monadtall is the frame split in two, max is the frame empty,
//      treetab is the frame ruled. Same three marks the island already
//      uses, so this bar and the island agree on what a layout looks like.
ShellRoot {
    id: demo

    component Strip: Rectangle {
        id: strip
        default property alias content: row.children
        property int hgap: Metrics.s(14)
        height: parent ? parent.height : Metrics.barHeight
        width: row.implicitWidth + hgap * 2
        radius: Metrics.s(8)
        color: BarTheme.alpha(BarTheme.bg, 0.6)
        border.width: 1
        border.color: BarTheme.alpha(BarTheme.fg, 0.08)

        Row {
            id: row
            anchors.centerIn: parent
            spacing: Metrics.s(14)
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

    // One overlapping chip per open window, fanned left to right. The
    // FOCUSED one is drawn last (highest z, so it sits on top of its
    // neighbours like the top card in a hand), ringed in accent and
    // scaled up slightly so "which one is open" needs no label at all.
    component AppStack: Item {
        id: stack
        property var apps: []
        property int chip: Metrics.s(19)
        property int step: Metrics.s(11)
        implicitWidth: apps.length > 0 ? chip + step * (apps.length - 1) : 0
        implicitHeight: chip + Metrics.s(4)

        Repeater {
            model: stack.apps
            delegate: Rectangle {
                width: stack.chip
                height: stack.chip
                radius: width / 2
                x: index * stack.step
                anchors.verticalCenter: parent.verticalCenter
                z: modelData.active ? 100 : (stack.apps.length - index)
                scale: modelData.active ? 1.18 : 1.0
                color: BarTheme.alpha(BarTheme.bg, 0.95)
                border.width: modelData.active ? 2 : 1
                border.color: modelData.active
                    ? BarTheme.accent
                    : BarTheme.alpha(BarTheme.fg, 0.18)

                Text {
                    anchors.centerIn: parent
                    text: String.fromCodePoint(modelData.icon)
                    color: modelData.active ? BarTheme.accent : BarTheme.alpha(BarTheme.fg, 0.55)
                    font.family: "Symbols Nerd Font"
                    font.pixelSize: Metrics.s(10)
                    renderType: Text.NativeRendering
                }
            }
        }
    }

    PanelWindow {
        id: bar
        screen: Quickshell.screens[0]
        anchors { top: true; left: true; right: true }
        implicitHeight: Metrics.barHeight + Metrics.marginV * 2
        margins.top: Metrics.barHeight + Metrics.marginV * 2 + Metrics.s(6)
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

            // ================= LEFT: layout glyph + menu =================
            Strip {
                id: leftStrip
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter

                // monadtall — U+F0DB, the frame split in two. Same glyph
                // and same font LayoutState.qml uses for the island.
                Glyph {
                    text: String.fromCodePoint(0xF0DB)
                    fg: BarTheme.accent
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: Metrics.s(13)
                }
                Divider {}
                Glyph { text: String.fromCodePoint(0xF0570); fg: BarTheme.purple; font.pixelSize: Metrics.s(13) }
            }

            // ================= CENTRE: workspaces + open apps =================
            // True centre of the bar — anchors.horizontalCenter on the
            // window, same as shell.qml's own centreGroup — not left-
            // anchored beside the menu the way the last two drafts had it.
            Strip {
                id: centerStrip
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter

                Row {
                    spacing: Metrics.s(11)
                    anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                    Repeater {
                        model: [1, 2, 3, 4, 5]
                        delegate: Label {
                            text: String(modelData)
                            fg: modelData === 3 ? BarTheme.fg : BarTheme.alpha(BarTheme.fg, 0.4)
                            font.bold: modelData === 3
                            anchors.verticalCenter: undefined
                        }
                    }
                }

                Divider {}

                // The open windows on this workspace, fanned — kitty,
                // this editor, a browser, a file manager — with the
                // editor as the focused one.
                AppStack {
                    apps: [
                        { icon: 0xF120, active: false },   // terminal
                        { icon: 0xF121, active: true  },   // editor — focused
                        { icon: 0xF0AC, active: false },   // browser
                        { icon: 0xF07C, active: false }    // files
                    ]
                }
            }

            // ================= RIGHT: unchanged from direction B =================
            // This half is the part that already landed — kept as-is.
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
