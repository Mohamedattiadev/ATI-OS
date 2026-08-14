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

    // ---- IT SITS ON A PLATE, LIKE EVERY OTHER WIDGET ON THAT BAR ----
    //
    // config.py's groupbox_widget() is `chip(ewidget.GroupBox, ...)` — the
    // GroupBox is wrapped in the SAME RectDecoration every other widget on
    // the top bar carries. This drew bare glyphs on the wallpaper, which is
    // the "workspace's bg part" that was missing.
    //
    // margin_x=_s(8) / margin_y=_s(2) are the widget's margins INSIDE that
    // chip, distinct from padding_x=8 which is each group's own padding. Both
    // are reproduced: the margins here, the padding on the delegate.
    property bool plated: true

    implicitWidth: row.implicitWidth + (root.plated ? Metrics.s(8) * 2 : 0)
    implicitHeight: parent ? parent.height : Metrics.barHeight

    Rectangle {
        visible: root.plated
        anchors.fill: parent
        // The chip plate's own inset and radius, identical to Chip.qml's —
        // RectDecoration padding_x=3 / padding_y=2, radius = half the plate.
        anchors.leftMargin: Metrics.s(3)
        anchors.rightMargin: Metrics.s(3)
        anchors.topMargin: Metrics.s(2)
        anchors.bottomMargin: Metrics.s(2)
        radius: height / 2
        color: BarTheme.plate
    }

    // config.py gives the top bar's GroupBox fontsize=_s(10) and the bottom
    // bar's _s(12), so the size is the caller's to set rather than a constant.
    property int labelPixelSize: Metrics.s(10)

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
            ? "Symbols Nerd Font" : Metrics.textFamily;
    }

    // ---- WHERE "S" GOES, AND WHY SORTING BY ID PUT IT NOWHERE ----
    //
    // qtile's group list is 1..8, then S, then 9 — S is a NAMED group and sits
    // where it was declared, not where its name sorts. Hyprland has the same
    // group and gives it an id of -1337, because a named workspace there is
    // allocated out of the negative range.
    //
    // Two consequences, and the bar hit both. Sorting on id put S at the far
    // LEFT, in front of 1; and the delegate's `id > 0` guard — written to keep
    // scratchpads out — dropped it entirely, which is how it was reported:
    // "the S session not appearing in the qtile-like bar".
    //
    // So the order is qtile's own, by NAME, and anything not in that list
    // keeps sorting after it by id. Scratchpads are excluded by the thing that
    // actually identifies them, the "special:" name prefix, rather than by a
    // sign test that catches every named workspace with them.
    readonly property var groupOrder: ["1","2","3","4","5","6","7","8","S","9"]

    function orderOf(ws) {
        const i = root.groupOrder.indexOf(String(ws.name));
        // 100 + id, so the strays keep their own relative order and none of
        // them can sort in among the declared groups.
        return i >= 0 ? i : 100 + ws.id;
    }

    Process {
        id: wsProc
        command: ["hyprctl", "-j", "workspaces"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const list = JSON.parse(text).filter(
                        (w) => String(w.name).indexOf("special:") !== 0);
                    list.sort((a, b) => root.orderOf(a) - root.orderOf(b));
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
                // Scratchpads are already gone — filtered by NAME in wsProc,
                // not by `id > 0` here, which also swallowed "S": a named
                // workspace in Hyprland is negative too (S is -1337), so the
                // sign test could not tell a group from a scratchpad.
                visible: populated || focused
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
                    // The GroupBox inherits widget_defaults, so the labels
                    // that are plain characters — "7" and "S" — are BOLD.
                    // Only on the text face; see Metrics.textFamily.
                    font.bold: root.fontFor(wsItem.modelData.name) === Metrics.textFamily
                    // ONE size for every group, which is what config.py has:
                    // fontsize=_s(10) and nothing per-label. An earlier
                    // revision bumped the icons by 3 px "matched by eye" —
                    // that was a guess, and a guess is exactly what "make it
                    // identical" rules out. qtile renders the icon glyphs at
                    // the same size as the digits.
                    font.pixelSize: root.labelPixelSize
                    renderType: Text.NativeRendering
                    color: wsItem.focused ? BarTheme.purple
                        : wsItem.populated ? BarTheme.cyan
                        : BarTheme.fg
                }

                MouseArea {
                    anchors.fill: parent
                    // disable_drag=True in config.py, so clicks only.
                    //
                    // By NAME for a named workspace, by id for a numbered one.
                    // Not interchangeable: the workspace dispatcher reads a
                    // SIGNED number as a relative move, so "workspace -1337"
                    // is not S, it is 1337 workspaces backwards.
                    onClicked: Hyprland.dispatch(
                        wsItem.modelData.id < 0
                            ? "workspace name:" + wsItem.modelData.name
                            : "workspace " + wsItem.modelData.id)
                }
            }
        }
    }
}
