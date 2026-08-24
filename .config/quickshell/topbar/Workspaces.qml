import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.UPower

//
// qtile's GroupBox, on Hyprland workspaces.
//
// Its parameters, from config.py, kept by name so the two bars agree:
//
//     fontsize=_s(10)   padding_x=8   margin_x=_s(8)   borderwidth=4
//     highlight_method="text"         hide_unused=True
//     active                     colors[8] cyan — a workspace with windows
//     inactive                   colors[1] fg   — an empty one
//     this_current_screen_border ACCENT         — the focused workspace,
//                                                  matching the window
//                                                  border and layout glyph
//     urgent_text                colors[3] red
//
// `highlight_method="text"` is why nothing here draws a box or an underline:
// qtile's GroupBox in that mode colours the LABEL and nothing else, and
// config.py's note on the active group is "no boxes anywhere on this widget".
// A pill would be a different widget that happened to contain the same digits.
//
// ---- BUT borderwidth AND spacing STILL COST WIDTH ----
//
// Reported as the group looking "a bit weird" beside the task list, and the
// cause is not in config.py at all — it is in the installed libqtile, which
// is where this tree's rule says to look:
//
//     box_width  = text + padding_x*2 + borderwidth*2      <- +8, ALWAYS
//     spacing    = None -> margin_x                        <- 8 between boxes
//     length     = margin_x*2 + (n-1)*spacing + Σ box_width
//
// `borderwidth` is reserved in the WIDTH whether or not a border is drawn;
// 'text' mode passes bordercolor=None, which only zeroes the border at DRAW
// time. And `spacing` defaults to None, which _configure() resolves to
// margin_x rather than to zero.
//
// So every group here was 8 px narrower than qtile's and butted against its
// neighbour with no gap: at the four groups on screen, 56 px of a 136 px
// widget. That is the whole of "the glyphs are packed together".
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

    // calculate_length(): margin_x*2 + (n-1)*spacing + Σ box_width. The Row
    // contributes the middle and last terms; the margins are this item's.
    implicitWidth: row.implicitWidth + Metrics.s(8) * 2
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

    // Backs the low-battery marker at the end of the Row, below.
    readonly property var battery: UPower.displayDevice
    readonly property bool batteryLow: root.battery && root.battery.isLaptopBattery
        && root.battery.percentage <= 0.10

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

    // ---- urgent_text=colors[3], WHICH NOTHING WAS DRAWING ----
    //
    // The header lists urgent among the GroupBox's four colours and the
    // delegate had three. qtile gets this for free — X11 windows set the
    // urgency hint and the group knows — and Hyprland does not put it in
    // `hyprctl workspaces` at all. The ONLY signal is the event socket's
    //
    //     urgent>><windowaddress>
    //
    // which names a WINDOW, so the workspace has to be looked up. Done on the
    // event rather than polled: an urgency hint is rare and a poll for it
    // would be a `hyprctl clients` every tick for something that happens twice
    // a day.
    //
    // Cleared when the workspace is FOCUSED, which is what qtile does — the
    // point of the mark is "something happened over there", and going there is
    // the answer to it.
    property var urgentIds: []

    function markUrgent(id) {
        if (root.urgentIds.indexOf(id) >= 0 || id === root.focusedId)
            return;
        const next = root.urgentIds.slice();
        next.push(id);
        root.urgentIds = next;
    }

    onFocusedIdChanged: {
        const at = root.urgentIds.indexOf(root.focusedId);
        if (at < 0)
            return;
        const next = root.urgentIds.slice();
        next.splice(at, 1);
        root.urgentIds = next;
    }

    Process {
        id: urgentProc
        property string address: ""
        command: ["hyprctl", "-j", "clients"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    for (const c of JSON.parse(text)) {
                        if (String(c.address) === urgentProc.address && c.workspace) {
                            root.markUrgent(c.workspace.id);
                            return;
                        }
                    }
                } catch (e) {}
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
            if (n === "urgent") {
                // The payload is the window address, with no 0x prefix in the
                // event and WITH one in `hyprctl clients` — normalised here
                // rather than at the comparison, so the lookup below reads as
                // an equality and not as a string puzzle.
                const addr = String(event.data || "").trim();
                urgentProc.address = addr.indexOf("0x") === 0 ? addr : "0x" + addr;
                urgentProc.running = true;
                return;
            }
            if (n.indexOf("workspace") >= 0 || n.indexOf("window") >= 0
                    || n === "monitoradded" || n === "monitorremoved")
                debounce.restart();
        }
    }

    // ---- qtile's OWN NUMBERS, BY THEIR OWN NAMES ----
    //
    // margin_x and margin_y go through _s(); padding_x, padding_y and
    // borderwidth are plain literals in config.py and are NOT scaled. Kept
    // apart here rather than folded into one figure, because on a machine
    // with ui_scale != 1 folding them would silently scale the three that
    // qtile leaves alone. This machine reads 1.00, so the difference is
    // latent — which is exactly why it would otherwise never be found.
    readonly property int qMarginX: Metrics.s(8)
    readonly property int qPaddingX: 8
    readonly property int qBorderWidth: 4
    // spacing=None in config.py, and _configure() resolves that to margin_x.
    readonly property int qSpacing: root.qMarginX

    // ---- THE WHEEL, WHICH IS A DEFAULT AND NOT A SETTING ----
    //
    // `use_mouse_wheel` defaults to True, so GroupBox.__init__ adds Button4
    // and Button5 to prev_group/next_group — over the VISIBLE groups only,
    // which is what the `while group not in self.groups` loop in each of them
    // is doing. config.py sets nothing, and an empty mouse map means "keep
    // the defaults", exactly as w_volume's did.
    //
    // Placed on the whole widget rather than on a delegate because that is
    // where qtile has it: the wheel is the WIDGET's callback, so it works
    // anywhere over the group including the margins between the labels.
    function cycle(step) {
        const shown = [];
        for (let i = 0; i < root.workspaces.length; i++) {
            const w = root.workspaces[i];
            if ((w.windows || 0) > 0 || w.id === root.focusedId
                    || root.urgentIds.indexOf(w.id) >= 0)
                shown.push(w);
        }
        if (shown.length === 0)
            return;
        let at = -1;
        for (let i = 0; i < shown.length; i++) {
            if (shown[i].id === root.focusedId) {
                at = i;
                break;
            }
        }
        // itertools.cycle: it wraps, in both directions.
        const next = shown[((at < 0 ? 0 : at + step) % shown.length
                            + shown.length) % shown.length];
        Hyprland.dispatch(next.id < 0 ? "workspace name:" + next.name
                                      : "workspace " + next.id);
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        onWheel: (wheel) => root.cycle(wheel.angleDelta.y > 0 ? -1 : 1)
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: root.qSpacing

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
                // hide_unused, plus the one exception qtile makes: an
                // urgent group is drawn whether or not you have been there.
                visible: populated || focused
                    || root.urgentIds.indexOf(modelData.id) >= 0
                // box_width(): text + padding_x*2 + borderwidth*2. The border
                // is never PAINTED here — highlight_method is 'text' — but
                // libqtile reserves it in the width regardless, so leaving it
                // out makes every group 8 px narrower than qtile's.
                width: visible
                    ? label.implicitWidth + root.qPaddingX * 2
                      + root.qBorderWidth * 2
                    : 0
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
                    // urgent OUTRANKS the rest, which is the order qtile
                    // resolves them in: an urgent group is red even while it
                    // is populated, because the whole point is that it is the
                    // one to look at.
                    // BarTheme.accent for the focused group, not .purple:
                    // qtile's own GroupBox now colours the CURRENT group
                    // with this_current_screen_border=ACCENT (the same
                    // value as the window border and layout glyph) and
                    // keeps merely-populated groups on colors[8]/.cyan —
                    // .purple here was the pre-ACCENT colors[7] value and
                    // no longer matches what config.py actually draws.
                    color: root.urgentIds.indexOf(wsItem.modelData.id) >= 0
                        ? BarTheme.red
                        : wsItem.focused ? BarTheme.accent
                        : wsItem.populated ? BarTheme.cyan
                        : BarTheme.fg
                }

                MouseArea {
                    anchors.fill: parent
                    // disable_drag=True in config.py, so no drag — but the
                    // wheel is a separate default and it IS on; see the note
                    // on root.cycle().
                    acceptedButtons: Qt.LeftButton

                    // ---- CLICKING THE GROUP YOU ARE ON GOES BACK ----
                    //
                    // Another behaviour config.py never mentions and the
                    // widget has anyway. go_to_group():
                    //
                    //     screen.group != group  -> set_group(group)
                    //     else                   -> toggle_group(group)
                    //
                    // and `toggle` defaults to True with disable_drag set, so
                    // the else branch is live: clicking the ACTIVE group in
                    // qtile returns you to the one you came from. Here it did
                    // nothing at all — a dispatch to the workspace you are
                    // already on.
                    //
                    // `workspace previous` is Hyprland's own name for it, so
                    // no history has to be kept on this side.
                    onClicked: {
                        if (wsItem.focused) {
                            Hyprland.dispatch("workspace previous");
                            return;
                        }
                        // By NAME for a named workspace, by id for a numbered
                        // one. Not interchangeable: the workspace dispatcher
                        // reads a SIGNED number as a relative move, so
                        // "workspace -1337" is not S, it is 1337 workspaces
                        // backwards.
                        Hyprland.dispatch(
                            wsItem.modelData.id < 0
                                ? "workspace name:" + wsItem.modelData.name
                                : "workspace " + wsItem.modelData.id);
                    }
                }
            }
        }

        // ---- LOW-BATTERY MARKER, PINNED TO THE RIGHT OF THE GROUP ----
        //
        // Not part of the qtile GroupBox this file otherwise mirrors — added
        // because a battery at 10% or under is easy to miss in the far-right
        // battery chip while attention is on the workspace pill itself. A
        // "|" then the bare glyph — no percentage, the colour and position
        // already say "low" — as the LAST two children of the Row, so it
        // always reads as the rightmost thing in the plate regardless of how
        // many workspaces are visible. Row skips invisible children for both
        // spacing and position, so both collapse away together when the
        // battery isn't low.
        Text {
            visible: root.batteryLow
            text: "|"
            color: BarTheme.fg
            font.family: Metrics.textFamily
            font.pixelSize: root.labelPixelSize
            renderType: Text.NativeRendering
            anchors.verticalCenter: parent.verticalCenter
        }

        Text {
            visible: root.batteryLow
            text: String.fromCharCode(0xF240)
            color: BarTheme.red
            font.family: "Symbols Nerd Font"
            font.pixelSize: root.labelPixelSize
            renderType: Text.NativeRendering
            anchors.verticalCenter: parent.verticalCenter
        }
    }
}
