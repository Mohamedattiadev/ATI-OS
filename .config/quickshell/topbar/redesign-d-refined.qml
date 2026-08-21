import QtQuick
import Quickshell
import Quickshell.Wayland

//
// DIRECTION D — refines C: real Arch logo, workspace icons back (not
// numbers), a flat non-overlapping window row, reordered so it reads
// "where / what's open / how it's arranged", one clean expand chevron,
// and a slot for the chord/submap indicator the original bar has.
// ============================================================================
// Standalone preview: `qs -p redesign-d-refined.qml`.
//
// FOUR THINGS FIXED FROM C
// -------------------------
// 1. The overlapping/scaled/z-fanned circle stack for open windows read as
//    "tribal" — scrapped. Replaced with a flat ROW of square slots, no
//    overlap, no scale, no z-order. The focused one gets the same
//    background-capsule treatment as the active workspace, nothing fancier.
// 2. Ordering: the window row now comes BEFORE the layout glyph (workspace
//    icons -> open windows -> layout), not after it, and the layout glyph is
//    no longer stranded alone on the far left.
// 3. The menu glyph was U+F0570, fontconfig's own name for it is
//    "md-view_grid" — a generic grid, not a wordmark. U+F303 is
//    "linux-archlinux" (checked against the installed JetBrainsMono Nerd
//    Font's cmap directly), the actual Arch Linux logo. Swapped.
// 4. Workspace numbers are gone — back to the per-workspace glyphs
//    Workspaces.qml already assigns (camera / folder / code / globe...),
//    which is what was actually asked for; the numbers were my own
//    substitution, never a requirement.
//
// PLUS: A CHORD SLOT
// -------------------
// shell.qml's rightGroup leads with a chip for the current Hyprland
// SUBMAP (its keychord equivalent) — plated in a colour that names the
// mode, empty and zero-width the rest of the time. Every draft so far
// dropped it outright. It's back here, mocked ACTIVE (a real one is empty
// 99% of the time) so it's visible in the preview at all.
ShellRoot {
    id: demo

    component Strip: Rectangle {
        id: strip
        default property alias content: row.children
        property int hgap: Metrics.s(11)
        height: parent ? parent.height : Metrics.barHeight
        width: row.implicitWidth + hgap * 2
        radius: Metrics.s(8)
        color: BarTheme.alpha(BarTheme.bg, 0.6)
        border.width: 1
        border.color: BarTheme.alpha(BarTheme.fg, 0.08)

        Row {
            id: row
            anchors.centerIn: parent
            spacing: Metrics.s(10)
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
        property color fg: BarTheme.fg
        color: fg
        font.family: Metrics.textFamily
        font.pixelSize: Metrics.textSize
        renderType: Text.NativeRendering
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
    }

    // One capsule-highlight slot, reused for both the active workspace and
    // the focused window — same visual language for "this one, of this
    // set, is the current one" wherever it shows up.
    component ActivatableIcon: Item {
        property int icon: 0
        property bool active: false
        property color activeColor: BarTheme.accent
        width: Metrics.s(22)
        height: Metrics.s(19)
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined

        Rectangle {
            visible: active
            anchors.fill: parent
            radius: height / 3
            color: BarTheme.alpha(activeColor, 0.2)
        }
        Glyph {
            anchors.centerIn: parent
            text: String.fromCodePoint(icon)
            fg: active ? activeColor : BarTheme.alpha(BarTheme.fg, 0.5)
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

            // ================= LEFT: the actual Arch logo =================
            Strip {
                id: brandStrip
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                Glyph {
                    text: String.fromCodePoint(0xF303)   // linux-archlinux
                    fg: BarTheme.purple
                    font.pixelSize: Metrics.s(14)
                }
            }

            // ================= CENTRE: where / what's open / how =================
            // True bar-centre, same as shell.qml's own centreGroup.
            Strip {
                id: centerStrip
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter

                // WHERE — the workspace glyphs Workspaces.qml already
                // assigns, not numbers.
                Row {
                    spacing: Metrics.s(8)
                    anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                    Repeater {
                        model: [
                            { icon: 0xF0E7, active: false },
                            { icon: 0xF03D, active: false },
                            { icon: 0xF07C, active: true  },
                            { icon: 0xF121, active: false },
                            { icon: 0xF0AC, active: false }
                        ]
                        delegate: ActivatableIcon { icon: modelData.icon; active: modelData.active }
                    }
                }

                Divider {}

                // WHAT'S OPEN — flat row, no overlap/scale/z-fan. Same
                // capsule treatment as the active workspace above.
                Row {
                    spacing: Metrics.s(6)
                    anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                    Repeater {
                        model: [
                            { icon: 0xF120, active: false },  // terminal
                            { icon: 0xF121, active: true  },  // editor — focused
                            { icon: 0xF0AC, active: false },  // browser
                            { icon: 0xF07C, active: false }   // files
                        ]
                        delegate: ActivatableIcon { icon: modelData.icon; active: modelData.active }
                    }
                }

                Divider {}

                // HOW — the layout glyph, now trailing rather than leading.
                // U+F0DB monadtall: the frame split in two — same glyph
                // tide-island-fork/qml/common/LayoutState.qml uses.
                Glyph {
                    text: String.fromCodePoint(0xF0DB)
                    fg: BarTheme.alpha(BarTheme.fg, 0.6)
                    // Not "JetBrainsMono Nerd Font": that family has an EXACT
                    // match installed (fc-list confirms it), so Qt commits to
                    // it and never falls back — and it rendered this glyph as
                    // tofu despite the codepoint being in its own cmap.
                    // "Symbols Nerd Font" has no exact match on this system,
                    // which is what makes Qt search every installed font for
                    // the glyph instead — the fallback every OTHER icon in
                    // this file has been quietly riding on already.
                }
            }

            // ================= RIGHT =================
            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                height: content.height
                spacing: Metrics.s(7)

                // The chord/submap slot — shell.qml's rightGroup leads with
                // exactly this, plated in a colour that names the mode, and
                // it is EMPTY (zero width) whenever no submap is active.
                // Mocked "on" here so the slot is visible at all; most of
                // the time this simply isn't there.
                Rectangle {
                    height: parent.height
                    width: chordLabel.implicitWidth + Metrics.s(14)
                    radius: height / 2
                    color: BarTheme.alpha(BarTheme.yellow, 0.85)
                    anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                    Label {
                        id: chordLabel
                        anchors.centerIn: parent
                        text: "RESIZE"
                        fg: BarTheme.bg
                        font.bold: true
                        font.pixelSize: Metrics.s(9)
                    }
                }

                Strip {
                    id: togglesStrip
                    Glyph { text: String.fromCodePoint(0xF0336) }
                    Glyph { text: String.fromCodePoint(0xF05AF) }
                    Glyph { text: String.fromCodePoint(0xF0902) }
                    Glyph { text: String.fromCodePoint(0xF035C) }

                    // ONE clean expand affordance for the cluster, not one
                    // bolted onto every icon. Plain typographic "<", not an
                    // icon-font glyph — no font-fallback risk, and it is
                    // literally what was asked for.
                    Rectangle {
                        width: Metrics.s(15); height: Metrics.s(15); radius: width / 2
                        color: BarTheme.alpha(BarTheme.fg, 0.1)
                        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                        Label {
                            anchors.centerIn: parent
                            text: "<"
                            fg: BarTheme.alpha(BarTheme.fg, 0.7)
                            font.pixelSize: Metrics.s(9)
                            font.bold: true
                        }
                    }
                }

                Strip {
                    id: statusStrip
                    Glyph { text: String.fromCodePoint(0xF240); font.pixelSize: Metrics.s(11) }
                    Label { text: "100%" }
                    Label { text: "EN"; fg: BarTheme.alpha(BarTheme.fg, 0.55) }
                }

                Strip {
                    id: trayStrip
                    Glyph { text: String.fromCodePoint(0xF1A4C) }
                    Glyph { text: String.fromCodePoint(0xF029) }
                }

                Strip {
                    id: clockStrip
                    hgap: Metrics.s(14)
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
}
