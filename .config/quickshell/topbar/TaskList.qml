import QtQuick
import Quickshell
import Quickshell.Hyprland

import "TaskName.js" as TaskName

//
// qtile's TaskList, on Hyprland toplevels.
//
// STATE IS CARRIED BY COLOUR AND WEIGHT, NOT BY LETTERS, and that is
// config.py's decision rather than a simplification of it. Every entry there
// used to be prefixed with a private code — "F" focused, "V" floating, "VF"
// both — in the one widget whose entire job is showing window names, and those
// characters cost width the name then lost to truncation. Focus already reads
// from the accent colour and the bold.
//
// THAT ARGUMENT WAS RIGHT ABOUT THE LETTERS AND WRONG ABOUT THE REST, which
// is why the widget was reported as "not behaving like the real qtile".
// Extracted from config.py's AST rather than read off it, `TaskList(...)`
// carries FIVE markup strings and a text parser:
//
//     markup_normal            bg colors[2] 44   fg colors[1]
//     markup_focused           bg colors[0] EE   fg colors[6]  bold
//     markup_floating          bg colors[0] CC   fg colors[5]  + U+F0294
//     markup_focused_floating  bg colors[0] EE   fg colors[5]  bold + U+F0294
//     markup_minimized         bg colors[0] 66   fg colors[3]  + U+F05B0
//     parse_text               parse_task_name
//
// So state is carried by colour AND a background AND, for two of the five, a
// glyph — and none of the backgrounds were being drawn. Dropping the F/V
// letters did not license dropping the plates: they are what makes the
// focused window findable at a glance in a row of same-coloured names.
//
// THE GLYPH COMES FROM THE MARKUP, NOT FROM txt_floating. Checked in the
// installed libqtile, because config.py sets both and only one is used:
// `get_taskname()` builds `state` out of txt_* and then DISCARDS it whenever
// a markup string exists, which here is always. So the floating icon is the
// one inside markup_floating, and a focused non-floating window gets none.
//
// font="JetBrainsMono Nerd Font", fontsize=_s(10), icon_size=_s(16),
// max_title_width=_s(115), spacing=2, margin_x=_s(3), padding_x=3.
//
// Uses `Hyprland.toplevels` and NOT `ToplevelManager.toplevels`, which is the
// opposite choice from Workspaces.qml beside it, and both were measured:
// the Wayland ToplevelManager reported zero entries in this session, while
// Hyprland.toplevels — after an explicit refreshToplevels() — carries a fully
// populated lastIpcObject with class, title, workspace and address. Workspaces
// are the reverse case; see that file.
//
// Its WIDTH is imposed from outside, which is the whole point: config.py pins
// it to a computed length because with stretch=False it sized to content, and
// each opened window shoved the GroupBox right until it was past the bar's
// centre. See the centring note in shell.qml.
Item {
    id: root

    implicitHeight: parent ? parent.height : Metrics.barHeight
    clip: true

    // ---- MINIMIZE, WHICH HYPRLAND DOES NOT HAVE ----
    //
    // libqtile's select_window has two branches and this bar only had one:
    // clicking a window that is NOT current focuses it, and clicking the one
    // that IS current calls toggle_minimize(). So in qtile the focused entry
    // is a minimise button, and here it was a dispatch to the window you were
    // already on — nothing.
    //
    // Hyprland has no minimize. A special workspace is this config's answer
    // to that and always has been: sum-toggle.sh stashes on `special:sum` and
    // its header says so in as many words. This uses `special:minimized`.
    //
    // THE FAIL-OPEN RULE: a stashed window is drawn in EVERY workspace's list,
    // not only in the one it came from. qtile scopes the list to the group and
    // can afford to, because a minimized window is still in its group and the
    // group still exists. Here the only record of where a window came from is
    // this shell's own memory, and a shell that reloads — which it does on
    // every edit — would strand a window nothing else in this desktop has a
    // key for. Showing it everywhere costs a stale row and makes losing a
    // window impossible.
    readonly property string stash: "special:minimized"

    // address -> the workspace it was minimized FROM, so restore puts it back
    // rather than dumping it wherever you happen to be standing. Lost on
    // reload, which is what the fail-open rule above exists to cover.
    property var homeOf: ({})

    // Only the windows on the workspace you are looking at, which is what
    // qtile's TaskList shows: it lists the current GROUP, not every client on
    // the machine. Without this the list is thirteen entries wide on this
    // session and the centring arithmetic has nothing left to give.
    readonly property var entries: {
        const out = [];
        const all = Hyprland.toplevels ? (Hyprland.toplevels.values || []) : [];
        const focusedWs = Hyprland.focusedWorkspace;
        for (let i = 0; i < all.length; i++) {
            const o = all[i].lastIpcObject;
            if (!o || !o.workspace) continue;
            const wsName = o.workspace.name === undefined ? "" : String(o.workspace.name);
            if (wsName === root.stash) {
                out.push(o);
                continue;
            }
            if (focusedWs && o.workspace.name !== undefined
                    && wsName !== String(focusedWs.name))
                continue;
            out.push(o);
        }
        return out;
    }

    function minimize(o) {
        const next = {};
        for (const k in root.homeOf)
            next[k] = root.homeOf[k];
        const ws = Hyprland.focusedWorkspace;
        next[String(o.address)] = ws
            ? (ws.id < 0 ? "name:" + ws.name : String(ws.id)) : "";
        root.homeOf = next;
        // Silent: moving to a special workspace non-silently would SHOW that
        // workspace, which is the opposite of minimising. sum-toggle.sh's
        // header records the same trap.
        Hyprland.dispatch("movetoworkspacesilent " + root.stash
                          + ",address:" + o.address);
    }

    function restore(o) {
        const home = root.homeOf[String(o.address)];
        const ws = Hyprland.focusedWorkspace;
        // No memory of home — this shell reloaded since it was stashed — so
        // it comes back to where you are looking, which is the only answer
        // that cannot strand it.
        const target = (home !== undefined && home !== "")
            ? home
            : (ws ? (ws.id < 0 ? "name:" + ws.name : String(ws.id)) : "");
        if (target === "")
            return;
        Hyprland.dispatch("movetoworkspacesilent " + target
                          + ",address:" + o.address);
        Hyprland.dispatch("focuswindow address:" + o.address);
    }

    Component.onCompleted: Hyprland.refreshToplevels()

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            const n = String(event.name);
            if (n.indexOf("window") >= 0 || n.indexOf("title") >= 0
                    || n.indexOf("workspace") >= 0)
                refreshDebounce.restart();
        }
    }
    Timer {
        id: refreshDebounce
        interval: 90
        repeat: false
        onTriggered: Hyprland.refreshToplevels()
    }

    // `spacing=2`, between task boxes. margin_x=_s(3) is the margin INSIDE
    // each box and is the delegate's left inset below, so the two are not
    // added together here.
    Row {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2

        Repeater {
            model: root.entries

            delegate: Item {
                id: entry
                required property var modelData

                readonly property bool focused: {
                    const a = Hyprland.activeToplevel;
                    return a && a.lastIpcObject
                        && a.lastIpcObject.address === modelData.address;
                }
                readonly property bool floating: entry.modelData.floating === true
                // Hyprland's `fullscreen` is 1 for MAXIMIZE and 2 for real
                // fullscreen, which is the distinction qtile draws between
                // maximized and not. config.py sets no markup_maximized, and
                // libqtile's fallback for a null markup with markup=True is
                // the bare "{}" — so a maximized window deliberately gets NO
                // plate. Reproduced rather than improved.
                readonly property bool maximized: entry.modelData.fullscreen === 1
                readonly property bool minimized:
                    entry.modelData.workspace
                    && String(entry.modelData.workspace.name) === root.stash

                // get_taskname()'s priority, top to bottom. Not a set of
                // independent flags — a focused floating window takes ONE
                // markup, not two.
                readonly property string state:
                    entry.minimized ? "minimized"
                    : entry.maximized ? "maximized"
                    : entry.focused ? (entry.floating ? "focusedFloating" : "focused")
                    : entry.floating ? "floating" : "normal"

                readonly property color plate:
                      entry.state === "normal"   ? BarTheme.alpha(BarTheme.bgAlt, 0x44 / 255)
                    : entry.state === "focused"  ? BarTheme.alpha(BarTheme.bg, 0xEE / 255)
                    : entry.state === "floating" ? BarTheme.alpha(BarTheme.bg, 0xCC / 255)
                    : entry.state === "focusedFloating"
                                                 ? BarTheme.alpha(BarTheme.bg, 0xEE / 255)
                    : entry.state === "minimized" ? BarTheme.alpha(BarTheme.bg, 0x66 / 255)
                    : "transparent"              // maximized: no markup, no plate

                readonly property color ink:
                      entry.state === "focused"   ? BarTheme.blue      // colors[6]
                    : entry.state === "floating"  ? BarTheme.yellow    // colors[5]
                    : entry.state === "focusedFloating" ? BarTheme.yellow
                    : entry.state === "minimized" ? BarTheme.red       // colors[3]
                    : BarTheme.fg                                      // colors[1]

                readonly property bool heavy:
                    entry.state === "focused" || entry.state === "focusedFloating"

                // U+F0294 for the two floating states, U+F05B0 for minimized,
                // and nothing for the rest — the markup strings, exactly.
                readonly property string mark:
                      (entry.state === "floating" || entry.state === "focusedFloating")
                        ? String.fromCodePoint(0xF0294) + " "
                    : entry.state === "minimized"
                        ? String.fromCodePoint(0xF05B0) + " "
                    : ""

                width: leftInset + icon.width + Metrics.s(6) + plateRect.width
                height: root.height

                readonly property int leftInset: Metrics.s(3)   // margin_x

                Image {
                    id: icon
                    anchors.verticalCenter: parent.verticalCenter
                    x: entry.leftInset
                    width: Metrics.s(16)
                    height: Metrics.s(16)
                    sourceSize.width: Metrics.s(32)
                    sourceSize.height: Metrics.s(32)
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    // `true` = fall back rather than warn per frame on a
                    // client whose class matches no installed .desktop file.
                    source: Quickshell.iconPath(entry.modelData.class, true)
                }

                // ---- THE PLATE IS BEHIND THE TEXT, NOT BEHIND THE ENTRY ----
                //
                // highlight_method='text' with borderwidth=0, so qtile draws
                // no box of its own: the colour comes from a pango
                // `<span background=…>`, which paints behind the GLYPHS. The
                // icon is outside the span and keeps the bar's background.
                //
                // Square corners for the same reason — `rounded` applies to
                // the border/block highlight methods, and this is neither.
                //
                // Each markup is " {} ", one space inside the span on each
                // side, and those two spaces are the whole of the plate's
                // horizontal padding. JetBrains Mono sets a space at 0.6 em,
                // the figure PopupChrome's hint bar is spaced on.
                Rectangle {
                    id: plateRect
                    anchors.left: icon.right
                    anchors.leftMargin: Metrics.s(6)
                    anchors.verticalCenter: parent.verticalCenter
                    width: title.width + entry.spaceAdvance * 2
                    height: title.implicitHeight + Metrics.s(4)   // padding_y=2
                    color: entry.plate
                    radius: 0

                    Text {
                        id: title
                        anchors.centerIn: parent
                        // max_title_width=_s(115), and it caps the TITLE
                        // rather than the entry: the icon and the plate's own
                        // padding are paid for outside it.
                        width: Math.min(implicitWidth, Metrics.s(115))
                        text: entry.mark + TaskName.parse(
                            entry.modelData.title || entry.modelData.class || "")
                        color: entry.ink
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: Metrics.s(10)
                        font.bold: entry.heavy
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        renderType: Text.NativeRendering
                    }
                }

                readonly property real spaceAdvance: Metrics.s(10) * 0.6

                // select_window(), both branches. See root.minimize().
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        if (entry.minimized)
                            root.restore(entry.modelData);
                        else if (entry.focused)
                            root.minimize(entry.modelData);
                        else
                            Hyprland.dispatch(
                                "focuswindow address:" + entry.modelData.address);
                    }
                }
            }
        }
    }
}
