import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

//
// qtile's GroupBox, on Hyprland workspaces.
//
// Its parameters, from config.py, kept by name so the two bars agree:
//
//     fontsize=_s(10)   padding_x=8   margin_x=_s(8)   borderwidth=4
//     highlight_method="text"         hide_unused=True
//     active                     colors[8] cyan   — a workspace with windows
//     inactive                   colors[1] fg     — an empty one
//     this_current_screen_border colors[7] purple — the focused workspace
//     urgent_text                colors[3] red
//
// `highlight_method="text"` is why nothing here draws a box or an underline:
// qtile's GroupBox in that mode colours the LABEL and nothing else, and
// config.py's note on the active group is "no boxes anywhere on this widget".
// A pill would be a different widget that happened to contain the same digits.
//
// ---- WHY THIS SHELLS OUT INSTEAD OF USING Hyprland.workspaces ----
//
// It tried the model first. `Hyprland.workspaces` populates only after an
// explicit refreshWorkspaces(), and even then, measured with a probe against
// this session:
//
//     ws count: 8
//     ws id= -1  name= 4   ipc= {}
//     ws id= -1  name= 5   ipc= {}
//     focused: -1
//
// Every id is -1 and every lastIpcObject is empty. Names are all it gives.
// The GroupBox needs two things names cannot supply: the id, to dispatch a
// click to, and the window COUNT, which is the whole of `hide_unused` and of
// the active/inactive colour split. (`Hyprland.toplevels` is the opposite —
// its lastIpcObject is fully populated, which is why TaskList.qml does use
// the model.)
//
// So this reads `hyprctl -j workspaces` and `activeworkspace`, which is what
// the island's own HyprlandData does for the same reason. TWO calls, not
// HyprlandData's four, and debounced on the same 90 ms: a workspace event
// arrives in bursts while windows are being moved, and refreshing per event
// would be several processes per keypress.
Item {
    id: root

    implicitWidth: row.implicitWidth
    implicitHeight: parent ? parent.height : Metrics.barHeight

    property var workspaces: []
    property int focusedId: -1

    // ---- qtile's GROUP LABELS, WHICH ARE ICONS AND NOT DIGITS ----
    //
    // Reported as "the workspaces part is not identical to the qtile real
    // one", and it was not: this drew the Hyprland workspace NAME, so the
    // group came out "2 3 4 5" where qtile shows glyphs.
    //
    // Read out of config.py's `groups` list by walking its AST. Every group
    // carries a `label=` and the GroupBox renders THAT, not the name — which
    // is why the middle of a real qtile bar shows a lightning bolt rather
    // than a "1".
    //
    //     1  U+F0E7 bolt        6  U+1F441 eye
    //     2  U+F03D camera      7  "7"  (no icon; qtile's own choice)
    //     3  U+F07C folder      8  U+F02D book
    //     4  U+F121 code        9  U+F2C6 ticket
    //     5  U+F0AC globe       S  no label -> its name, "S"
    //
    // Keyed by NAME rather than by id, because a Hyprland workspace's name is
    // what corresponds to a qtile group's name — "S" is a named workspace
    // here and a named group there, and its id is an arbitrary negative.
    readonly property var groupLabels: ({
        "1": String.fromCodePoint(0xF0E7),
        "2": String.fromCodePoint(0xF03D),
        "3": String.fromCodePoint(0xF07C),
        "4": String.fromCodePoint(0xF121),
        "5": String.fromCodePoint(0xF0AC),
        "6": String.fromCodePoint(0x1F441),
        "7": "7",
        "8": String.fromCodePoint(0xF02D),
        "9": String.fromCodePoint(0xF2C6)
    })

    function labelFor(name) {
        const l = root.groupLabels[String(name)];
        // Anything qtile has no group for — a scratchpad, a workspace made by
        // hand — falls back to its own name. Better a digit than a blank.
        return l !== undefined ? l : String(name);
    }

    // U+1F441 is an EMOJI, not a Nerd Font glyph, and the two do not live in
    // the same face. Rendered in Symbols Nerd Font it is a blank; fontconfig
    // will not substitute inside an explicitly-named family. So the one
    // emoji label gets the emoji font and everything else gets the icon font.
    function fontFor(name) {
        const l = root.labelFor(name);
        if (l.length > 0 && l.codePointAt(0) > 0xFFFF && l !== "7")
            return "Noto Color Emoji";
        return root.groupLabels[String(name)] !== undefined
            ? "Symbols Nerd Font" : "Ubuntu Bold";
    }

    Process {
        id: wsProc
        command: ["hyprctl", "-j", "workspaces"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const list = JSON.parse(text);
                    list.sort((a, b) => a.id - b.id);
                    root.workspaces = list;
                } catch (e) {
                    // Keep the last good list. A torn read must not blank the
                    // group — an empty centre reads as a broken bar.
                }
            }
        }
    }

    Process {
        id: activeProc
        command: ["hyprctl", "-j", "activeworkspace"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.focusedId = JSON.parse(text).id;
                } catch (e) {}
            }
        }
    }

    function refresh() {
        wsProc.running = true;
        activeProc.running = true;
    }

    Timer {
        id: debounce
        interval: 90
        repeat: false
        onTriggered: root.refresh()
    }

    Component.onCompleted: root.refresh()

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            // Only the events that can change the answer. `openwindow` and
            // `closewindow` matter as much as the workspace ones, because the
            // window COUNT is what decides whether a workspace is drawn at all.
            const n = String(event.name);
            if (n.indexOf("workspace") >= 0 || n.indexOf("window") >= 0
                    || n === "urgent" || n === "monitoradded" || n === "monitorremoved")
                debounce.restart();
        }
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 0

        Repeater {
            model: root.workspaces

            delegate: Item {
                id: wsItem
                required property var modelData

                readonly property bool focused: modelData.id === root.focusedId
                readonly property bool populated: (modelData.windows || 0) > 0

                // hide_unused=True: an empty, unfocused workspace is not drawn.
                // That is also what keeps this group narrow enough to sit at
                // the bar's true centre with a long TaskList beside it.
                //
                // A special workspace (negative id) is a scratchpad and was
                // never in qtile's group list at all.
                visible: modelData.id > 0 && (populated || focused)
                width: visible ? label.implicitWidth + Metrics.s(8) * 2 : 0
                // root.height, NOT parent.height. The parent is a Row, and a
                // Row derives its height FROM its children — so a child
                // sizing itself from the Row is a loop, which Qt resolves by
                // dropping one side. It resolved to zero: the data was
                // arriving (8 workspaces, focused 4, confirmed by probe) and
                // the group simply had no height to draw in.
                height: root.height

                Text {
                    id: label
                    anchors.centerIn: parent
                    text: root.labelFor(wsItem.modelData.name)
                    font.family: root.fontFor(wsItem.modelData.name)
                    // The icons need more than the digits did. config.py gives
                    // the GroupBox fontsize=_s(10), but that is the size of a
                    // DIGIT in Ubuntu Bold; the same number in a Nerd Font
                    // renders an icon noticeably smaller than qtile draws it,
                    // because qtile-extras scales group icons up against the
                    // bar height. Matched by eye against the real bar.
                    font.pixelSize: root.groupLabels[String(wsItem.modelData.name)] !== undefined
                        ? Metrics.s(13) : Metrics.s(10)
                    renderType: Text.NativeRendering
                    color: wsItem.focused ? BarTheme.purple
                        : wsItem.populated ? BarTheme.cyan
                        : BarTheme.fg
                }

                MouseArea {
                    anchors.fill: parent
                    // disable_drag=True in config.py, so clicks only.
                    onClicked: Hyprland.dispatch("workspace " + wsItem.modelData.id)
                }
            }
        }
    }
}
