import QtQuick
import Quickshell
import Quickshell.Services.UPower

//
// qtile's "normal user" bar — its SECOND bar, the one $mod SHIFT Z swaps to.
//
// config.py builds two: a top bar of chips and this, at the bottom, 40 px
// tall on an OPAQUE colors[2] background. It is a different bar rather than
// the same one moved, and the difference is deliberate — its own note says
// the top bar "is built from chips, where every element already carries its
// own rounded background", while this one "is built from bare widgets and
// uses pipes to group them".
//
// So: no chips, no plates, literal "|" separators, and a solid background.
// Reproducing it with chips would be reproducing the wrong bar.
//
// The launcher row is the other thing this bar has and the top one does not:
// five fixed application icons, which is what makes it the "normal user"
// bar — everything reachable by pointer.
Item {
    id: root

    property var shell: null
    property var sink: null

    // widget.LaunchBar's progs, verbatim from config.py. Glyphs by codepoint,
    // never pasted: U+F0A1E is supplementary-plane and a literal would not
    // survive being read back out of this file.
    readonly property var launchers: [
        { cp: 0xF269,  cmd: "brave",       name: "Brave Browser"  },
        { cp: 0xF484,  cmd: "qutebrowser", name: "Qutebrowser"    },
        { cp: 0xEBC4,  cmd: "kitty",       name: "Kitty Terminal" },
        { cp: 0xF07B,  cmd: "pcmanfm-qt",  name: "File Manager"   },
        { cp: 0xF0A1E, cmd: "code",        name: "VS Code"        }
    ]

    // ---- LEFT ----
    Row {
        id: leftRow
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        // EXPLICIT height, from the bar and not from the Row's own children.
        // A Row derives its height FROM its children, so a child asking for
        // `parent.height` inside one is circular and Qt resolves it to zero —
        // the launchers and the readouts both rendered nothing while their
        // text was correct. Third time in this bar; see TOPBAR-SPEC.md.
        height: root.height
        spacing: 0

        // ---- THE LOGO HAS A DIFFERENT MAP ON THIS BAR ----
        //
        // It was the top bar's, copied: L docs, M terminal, R launcher. That
        // is main_icon_chip. THIS one is main_icon_chip_nu and config.py gives
        // it two callbacks and the opposite sense —
        //
        //     "Button1": open_launcher     "Button3": open_terminal
        //
        // which its own tooltip states: "Arch menu · L-click → launcher ·
        // R-click → terminal".
        //
        // The two bars USED to disagree about right-click — the top one had
        // qtile's launcher there — and that disagreement is what got
        // reported. The top chip's right button is the terminal now, so this
        // bar's habit is the one both follow; see the note in shell.qml. Left
        // still differs, because these really are two different chips in
        // config.py with two different first buttons.
        BarText {
            text: String.fromCodePoint(0xF0570)      // ARCH_ICON_MAIN
            pixelSize: Metrics.s(19)
            padding: 16
            colour: BarTheme.purple                  // colors[7]
            iconFont: true
            clickable: true
            tip: "Arch menu \u00b7 L-click \u2192 launcher \u00b7 R-click \u2192 terminal"
            hoverSink: root.sink
            onPressed: (b) => {
                if (b === Qt.RightButton) Quickshell.execDetached(["kitty"]);
                else Quickshell.execDetached(["rofi", "-show", "drun", "-show-icons"]);
            }
        }

        BarText { text: "|"; pixelSize: Metrics.s(14); padding: 3; colour: BarTheme.fg }

        Repeater {
            model: root.launchers
            delegate: BarText {
                required property var modelData
                text: String.fromCodePoint(modelData.cp)
                pixelSize: Metrics.s(14)
                padding: 12
                colour: BarTheme.fg                  // colors[1]
                iconFont: true
                clickable: true
                tip: modelData.name
                hoverSink: root.sink
                onPressed: Quickshell.execDetached([modelData.cmd])
            }
        }

        BarText {
            text: String.fromCodePoint(0xF0E51)      // screenshot_chip_nu
            pixelSize: Metrics.s(16)
            padding: 10
            colour: BarTheme.fg
            iconFont: true
            clickable: true
            tip: "Screenshot area → clipboard"
            hoverSink: root.sink
            onPressed: Quickshell.execDetached(["dm-satty"])
        }
    }

    // ---- CENTRE ----
    //
    // Between two STRETCH spacers in config.py, which on this bar is honest:
    // the left side is a fixed row of launchers and the right side a fixed row
    // of readouts, so neither grows the way the top bar's TaskList does. The
    // arithmetic that bar needs is not needed here.
    Workspaces {
        id: centre
        anchors.horizontalCenter: parent.horizontalCenter
        height: parent.height
        labelPixelSize: Metrics.s(12)

        // NO PLATE, and that is this bar's whole distinction rather than an
        // oversight. The top bar's group is `chip(ewidget.GroupBox, ...)`; this
        // one is a bare `widget.GroupBox` in normal_user_bar(), like every
        // other widget down here. Reported as the workspaces having a
        // background that did not match the bar — they did not, because a
        // plate at 70% of the background sat on top of an OPAQUE colors[2]
        // bar instead of on the transparent one it was drawn for.
        plated: false
    }

    // ---- RIGHT ----
    Row {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: root.height
        spacing: 0

        // chord_chip_nu — the same CHORD_CHIP_LABELS as the top bar's, since
        // config.py gives both widgets the same name_transform. What differs
        // is the colouring: this one is foreground=colors[7] on the bar, with
        // no plate to carry the mode's identity.
        BarText {
            icon: root.shell ? root.shell.submapIcon : ""
            text: root.shell ? root.shell.submapLabel : ""
            pixelSize: Metrics.s(11)
            padding: 11
            colour: BarTheme.purple                  // colors[7]
        }
        BarText { text: "|"; pixelSize: Metrics.s(14); padding: 0; colour: BarTheme.fg }

        BarText {
            visible: UPower.displayDevice && UPower.displayDevice.isLaptopBattery
            text: root.shell ? root.shell.batteryText : ""
            pixelSize: Metrics.s(11)
            padding: 4
            colour: root.shell && root.shell.batteryLow ? BarTheme.red : BarTheme.blue
        }
        // The separator that goes WITH the battery, and only with it.
        // config.py splices the pair in together and says why: "the separator
        // goes with it, or a desktop draws two pipes with nothing between".
        // This bar had the battery and not its pipe, so on a laptop the
        // readouts ran together where qtile divides them.
        BarText {
            visible: UPower.displayDevice && UPower.displayDevice.isLaptopBattery
            text: "|"; pixelSize: Metrics.s(14); padding: 4; colour: BarTheme.fg
        }

        BarText {
            text: root.shell ? root.shell.cpuText : ""
            pixelSize: Metrics.s(10); padding: 4; colour: BarTheme.yellow
        }
        BarText { text: "|"; pixelSize: Metrics.s(14); padding: 4; colour: BarTheme.fg }
        BarText {
            text: root.shell ? root.shell.memText : ""
            pixelSize: Metrics.s(10); padding: 4; colour: BarTheme.cyan
        }
        BarText { text: "|"; pixelSize: Metrics.s(14); padding: 0; colour: BarTheme.fg }
        BarText {
            text: root.shell ? root.shell.clockText : ""
            pixelSize: Metrics.s(11); padding: 14; colour: BarTheme.fg
        }
    }
}
