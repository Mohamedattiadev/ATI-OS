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

        BarText {
            text: String.fromCodePoint(0xF0570)      // ARCH_ICON_MAIN
            pixelSize: Metrics.s(19)
            padding: 16
            colour: BarTheme.purple                  // colors[7]
            iconFont: true
            clickable: true
            onPressed: (b) => {
                if (b === Qt.LeftButton) Quickshell.execDetached(["rofi_docs"]);
                else if (b === Qt.MiddleButton) Quickshell.execDetached(["kitty"]);
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
    }

    // ---- RIGHT ----
    Row {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: root.height
        spacing: 0

        BarText {
            text: root.shell && root.shell.submapLabel !== ""
                ? " " + root.shell.submapLabel + " " : ""
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
