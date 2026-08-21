import QtQuick
import Quickshell
import Quickshell.Wayland

//
// ============================================================
//  Topbar redesign — example / mockup, NOT wired to the live bar
// ============================================================
//
// Standalone preview: `qs -p shell-redesign-example.qml`. Mock data only (no
// Hyprland/UPower/tray calls) so it can be judged purely on layout. Reuses
// BarTheme + Metrics (same directory, read-only) so it tracks the live
// palette/scale, but touches none of shell.qml/Chip.qml/etc.
//
// REVISION 2 — the first pass (still in git history) was regrouped into
// pills but was still bad: a chevron glyph bolted onto every toggle icon
// read as a stray typo, the active-workspace dot sat in its own Column and
// fell off the row's baseline, gaps were too tight to read as real
// separation, and — the big one — nine competing hues (purple, red, accent,
// blue, cyan, yellow, green fighting at once) made it noisier than the
// original, not calmer. Fixed here:
//
//   - ONE brand colour (purple, menu glyph only) + ONE accent colour (the
//     active workspace + the clock). Everything else is neutral fg at two
//     opacities — full for primary text, ~65% for icons/secondary — so
//     colour means something again instead of being decoration.
//   - No chevrons, no separator pipes (Chip.qml's own header already
//     recorded why a lone pipe reads as a stray mark — this reused that
//     pipe idea anyway the first time round, which was the mistake).
//   - Active workspace is a background capsule behind the glyph, baseline-
//     aligned with its neighbours, not a dot in a second row.
//   - Clock moved to the true rightmost edge — every desktop from Windows
//     to GNOME ends the bar with the clock, and burying it before the tray
//     was fighting that convention for no reason.
ShellRoot {
    id: demo

    component ClusterPill: Rectangle {
        id: pill
        default property alias content: row.children
        property int hgap: Metrics.s(12)
        height: parent ? parent.height : Metrics.barHeight
        width: row.implicitWidth + hgap * 2
        radius: height / 2
        color: BarTheme.plate

        Row {
            id: row
            anchors.centerIn: parent
            spacing: Metrics.s(10)
        }
    }

    // One size for every functional glyph. The old bar (and this file's
    // first draft) let each widget pick its own 10-15px — a wall of icons at
    // slightly different sizes reads as sloppy even when no one can say
    // exactly why.
    component Glyph: Text {
        property color fg: BarTheme.alpha(BarTheme.fg, 0.65)
        color: fg
        font.family: "Symbols Nerd Font"
        font.pixelSize: Metrics.s(13)
        renderType: Text.NativeRendering
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
    }

    component Label: Text {
        property color fg: BarTheme.fg
        property bool bold: true
        color: fg
        font.family: Metrics.textFamily
        font.bold: bold
        font.pixelSize: Metrics.textSize
        renderType: Text.NativeRendering
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
    }

    PanelWindow {
        id: bar
        screen: Quickshell.screens[0]
        anchors { top: true; left: true; right: true }
        implicitHeight: Metrics.barHeight + Metrics.marginV * 2
        // Pushed down past the real bar's height so both can be compared
        // on screen at once without this one covering it.
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

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 1
                color: BarTheme.alpha(BarTheme.accent, 0.2)
            }

            // ================= LEFT: menu + layout + workspaces =================
            // One pill, not three touching ones — the menu glyph, the
            // layout name and the workspace switcher are all "where am I /
            // where can I go" and read as one unit, not three.
            ClusterPill {
                id: navPill
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter

                Glyph {
                    text: String.fromCodePoint(0xF0570)
                    fg: BarTheme.purple
                    font.pixelSize: Metrics.s(15)
                }
                Label {
                    text: "Max"
                    fg: BarTheme.alpha(BarTheme.fg, 0.55)
                    font.pixelSize: Metrics.s(9)
                }
                Row {
                    spacing: Metrics.s(4)
                    anchors.verticalCenter: parent ? parent.verticalCenter : undefined

                    Repeater {
                        model: [
                            { icon: 0xF0E7, active: false },
                            { icon: 0xF03D, active: false },
                            { icon: 0xF07C, active: true  },
                            { icon: 0xF121, active: false },
                            { icon: 0xF0AC, active: false }
                        ]
                        delegate: Item {
                            width: Metrics.s(20)
                            height: Metrics.s(18)
                            anchors.verticalCenter: parent ? parent.verticalCenter : undefined

                            Rectangle {
                                visible: modelData.active
                                anchors.fill: parent
                                radius: height / 2
                                color: BarTheme.alpha(BarTheme.accent, 0.22)
                            }
                            Glyph {
                                anchors.centerIn: parent
                                text: String.fromCodePoint(modelData.icon)
                                fg: modelData.active ? BarTheme.accent : BarTheme.alpha(BarTheme.fg, 0.5)
                            }
                        }
                    }
                }
            }

            // ================= FOCUSED WINDOW =================
            // The old TaskList drew every open window as its own full-width
            // coloured chip (three, in the screenshot this was asked
            // about). Here: the FOCUSED window only, plus a small "+N" for
            // the rest — click/hover still gets to the others, it just
            // doesn't cost three chips of bar space at rest.
            ClusterPill {
                id: taskPill
                anchors.left: navPill.right
                anchors.leftMargin: Metrics.s(12)
                anchors.verticalCenter: parent.verticalCenter

                Glyph { text: String.fromCodePoint(0xF0574) }
                Label {
                    text: "ati-os-menu-feature-branch"
                    width: Math.min(implicitWidth, Metrics.s(170))
                    elide: Text.ElideRight
                }
                Rectangle {
                    width: Metrics.s(18); height: Metrics.s(15); radius: Metrics.s(4)
                    color: BarTheme.alpha(BarTheme.fg, 0.12)
                    anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                    Label {
                        text: "+2"
                        fg: BarTheme.alpha(BarTheme.fg, 0.6)
                        anchors.centerIn: parent
                        font.pixelSize: Metrics.s(8)
                    }
                }
            }

            // ================= RIGHT SIDE =================
            // Toggles, status and tray each get their own plate with real
            // air between them, in the order every other desktop uses:
            // quick settings, then status readouts, then tray, then the
            // clock LAST — the universal rightmost anchor, not buried
            // in the middle of the group the way the first draft had it.
            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                height: content.height
                spacing: Metrics.s(10)

                ClusterPill {
                    id: togglesPill
                    Glyph { text: String.fromCodePoint(0xF0336) }   // tips
                    Glyph { text: String.fromCodePoint(0xF05AF) }   // CPU/mem box
                    Glyph { text: String.fromCodePoint(0xF0902) }   // updates/disk/vol box
                    Glyph { text: String.fromCodePoint(0xF035C) }   // wallpaper picker
                }

                ClusterPill {
                    id: statusPill
                    Glyph { text: String.fromCodePoint(0xF240); font.pixelSize: Metrics.s(12) }
                    Label { text: "100%" }
                    Label { text: "EN"; fg: BarTheme.alpha(BarTheme.fg, 0.65) }
                }

                ClusterPill {
                    id: trayPill
                    Glyph { text: String.fromCodePoint(0xF1A4C) }  // nightlight
                    Glyph { text: String.fromCodePoint(0xF029) }   // wifi qr
                }

                ClusterPill {
                    id: clockPill
                    hgap: Metrics.s(14)
                    Label {
                        text: "Fri, Aug 21   19:37"
                        fg: BarTheme.accent
                        font.pixelSize: Metrics.textSize + 1
                    }
                }
            }
        }
    }
}
