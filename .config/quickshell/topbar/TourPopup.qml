import QtQuick
import Quickshell
import Quickshell.Wayland

//
// FORK — new file. The onboarding tour, ported off eww's
// ~/.dotfiles/.config/eww/onboarding/*.yuck (welcome/workspaces/
// keybindings/finish, plus the bar_tooltip overlay) into QML.
//
// "make it qml and update its style to fit while style of the menu and
// display popup wifi etc" — asked directly, after the lamp's eww toggle
// was pointed out as the odd one out (a whole separate GTK app, `eww open
// onboarding-welcome`, next to every other popup on this desktop being a
// Quickshell surface).
//
// WHY THIS ISN'T LITERALLY PopupChrome (tide-island-fork/qml/popups)
// --------------------------------------------------------------------
// First attempt imported it directly, cross-directory
// (`import "../tide-island-fork/qml/popups"`). Quickshell refused it at
// load:
//
//     WARN  quickshell.qmlscanner: Module path ".../tide-island-fork/qml/
//           common" is outside of the config folder.
//     ERROR caused by @TourPopup.qml: PopupChrome is not a type
//
// Each `qs -p <file>` run scopes its module resolution to that file's OWN
// directory — which is also why shell.qml (topbar) and the island are
// separate processes in production (bar-switch stops one to start the
// other), not two directories one `qs` reads from at once. So "match the
// island's popups" has to mean reproducing their LOOK from here, not
// literally subclassing their QML.
//
// It is a close reproduction rather than a guess: BarTheme already reads
// the identical ~/.cache/tide-island/colors.json IslandTheme does (see
// BarTheme.qml's own header — "ONE SOURCE, NOT A SECOND COPY"), so the
// colours are not approximated, they are the same values under different
// property names. The geometry (10px corner radius, 1px hairline border,
// header / hint-row / footer-with-top-hairline stacking) is PopupChrome's
// own documented rhythm, copied by hand since the type itself is out of
// reach.
//
// WHAT CHANGED FROM THE EWW CONTENT, AND WHY
// -------------------------------------------
// The yuck source describes the QTILE desktop this repo has since left:
// mod4/mod2, config.py's `main_icon_chip`, a `2nd_system_widgetbox`.
// Cross-checked line by line against this session's own hypr/binds.conf,
// hypr/submaps.conf and hypr/rules.conf rather than carried over as-is:
//
//   * workspaces.yuck claimed "7 and 8 are free". rules.conf now assigns
//     workspace 8 to LibreOffice/Okular/Zathura (`windowrule = workspace 8
//     silent, match:class ^(libreoffice-...|okular|zathura)$`) — only 7 is
//     still free. wsIcons in redesign-e-final.qml already carries a book
//     glyph for "8", which only makes sense if this was already
//     anticipated and the tour text just hadn't caught up.
//   * keybindings.yuck's tip named only `k` after the Win+Shift+K chord.
//     submaps.conf's `cheatsheet` submap actually binds four: k (Hyprland),
//     v (vim), f (fish), i (island keymap) — all four are named now.
//   * Its "Cheatsheet" button ran `ati-onboarding-cheatsheet`, a script
//     whose own header is `qtile cmd-obj` end to end — dead on this
//     session. Replaced with the real path submaps.conf's own `k` binding
//     uses: `ati-bar-action tide showCheatsheet hypr` (`$tide` is defined
//     as exactly that alias in that file).
//   * bar_tooltip.yuck's "Right-side widgets" legend was config.py's
//     `2nd_system_widgetbox` icon set (tray/cpu/updates/wallpaper/tooltip).
//     Rewritten to what redesign-e-final.qml's own utilStrip actually
//     shows: one merged CPU/RAM/volume/brightness box, one merged
//     nightlight/Wi-Fi-QR/updates box, battery + keyboard layout, clock —
//     there is no separate wallpaper button or systray icon in this bar.
//   * bar_tooltip.yuck's main-icon click map (L docs / M terminal / R
//     launcher) is shell.qml's config.py-ported map, not this bar's.
//     redesign-e-final.qml's brand icon is L-click -> the menu
//     (`ati-bar-action tide toggleMenu`, which folds the old docs menu in
//     as one of its own entries) and R-click -> a terminal. Described
//     that way here since this popup is being carried INTO the new bar.
//   * The Alt+`/Win+`/Alt+Tab line (system widgets / second set / tray) was
//     checked against binds.conf too and was NOT stale — kept verbatim.
PanelWindow {
    id: tour

    signal requestClose()

    property int step: 1
    readonly property int stepCount: 5

    screen: Quickshell.screens.length ? Quickshell.screens[0] : null
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "topbar-tour-popup"
    // Exclusive while open — this is a modal step-through, not a glanceable
    // readout, so it should own the keyboard the way the island's own
    // popups do (see PopupChrome's header on why theirs do the same).
    WlrLayershell.keyboardFocus: tour.visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    // eww's five windows were 400-420 wide, 200-220 tall. This chrome's own
    // header/hints/footer need more air than that around the body before it
    // reads as one of this desktop's popups rather than a cramped dialog.
    readonly property int popupWidth: Math.min(Metrics.s(560),
        (tour.screen ? tour.screen.width : 1366) - Metrics.s(40))
    readonly property int popupHeight: Math.min(Metrics.s(360),
        (tour.screen ? tour.screen.height : 768) - Metrics.s(48))
    implicitWidth: tour.popupWidth
    implicitHeight: tour.popupHeight

    readonly property var pageIcon: ({
        1: String.fromCodePoint(0xF303),    // linux-archlinux — welcome
        2: String.fromCodePoint(0xF0AC),    // globe — the bar overview
        3: String.fromCodePoint(0xF0E7),    // flash — workspaces
        4: String.fromCodePoint(0xF11C),    // keyboard — keybindings
        5: String.fromCodePoint(0xF303)     // arch again — "you're set"
    })
    readonly property var pageTitle: ({
        1: "Welcome", 2: "Top Bar", 3: "Workspaces", 4: "Keybindings", 5: "You're all set"
    })
    readonly property var stepHints: ({
        4: [{ key: "k", desc: "hypr" }, { key: "v", desc: "vim" },
            { key: "f", desc: "fish" }, { key: "i", desc: "island" }]
    })

    onVisibleChanged: {
        if (tour.visible)
            tour.step = 1;
        else
            tour.requestClose();
    }

    function openCheatsheet() {
        tour.visible = false;
        Quickshell.execDetached(["ati-bar-action", "tide", "showCheatsheet", "hypr"]);
    }

    // ---- SHARED BITS ----

    component PageText: Text {
        color: BarTheme.fg
        font.family: Metrics.textFamily
        font.pixelSize: Metrics.textSize + 1
        wrapMode: Text.WordWrap
        renderType: Text.NativeRendering
    }

    component MutedText: Text {
        color: BarTheme.alpha(BarTheme.fg, 0.6)
        font.family: Metrics.textFamily
        font.pixelSize: Metrics.textSize
        wrapMode: Text.WordWrap
        renderType: Text.NativeRendering
    }

    // A workspace legend chip — "N Name", coloured per rules.conf's own
    // groups, doubling as the legend workspaces.yuck's own markup carried.
    component WsChip: Row {
        property string num: ""
        property string label: ""
        property color tint: BarTheme.fg
        spacing: Metrics.s(4)
        Rectangle {
            width: numText.implicitWidth + Metrics.s(8)
            height: numText.implicitHeight + Metrics.s(2)
            radius: Metrics.s(4)
            color: BarTheme.alpha(parent.tint, 0.18)
            anchors.verticalCenter: parent.verticalCenter
            Text {
                id: numText
                anchors.centerIn: parent
                text: parent.parent.num
                color: parent.parent.tint
                font.family: Metrics.textFamily
                font.pixelSize: Metrics.textSize
                font.bold: true
                renderType: Text.NativeRendering
            }
        }
        MutedText {
            anchors.verticalCenter: parent.verticalCenter
            text: parent.label
        }
    }

    component NavBtn: Rectangle {
        id: btn
        property string label: ""
        property bool primary: false
        signal clicked()
        implicitWidth: lbl.implicitWidth + Metrics.s(20)
        implicitHeight: lbl.implicitHeight + Metrics.s(10)
        radius: Metrics.s(6)
        color: btn.primary ? BarTheme.accent : BarTheme.alpha(BarTheme.fg, 0.12)
        Text {
            id: lbl
            anchors.centerIn: parent
            text: btn.label
            color: btn.primary ? BarTheme.bg : BarTheme.fg
            font.family: Metrics.textFamily
            font.pixelSize: Metrics.textSize
            font.bold: btn.primary
            renderType: Text.NativeRendering
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.clicked()
        }
    }

    // ---- CHROME ----

    Rectangle {
        id: card
        anchors.fill: parent
        radius: Metrics.s(10)
        color: BarTheme.bg
        border.width: 1
        border.color: BarTheme.alpha(BarTheme.fg, 0.24)

        opacity: 0
        Component.onCompleted: opacity = 1
        Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

        Item {
            id: head
            x: card.width * 0.05
            y: Metrics.s(18)
            width: card.width * 0.9
            height: Metrics.s(40)
            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: Metrics.s(2)
                Text {
                    text: tour.pageIcon[tour.step] + "  " + tour.pageTitle[tour.step]
                    color: BarTheme.fg
                    font.family: Metrics.textFamily
                    font.pixelSize: Metrics.textSize + 6
                    font.bold: true
                    renderType: Text.NativeRendering
                }
                Text {
                    text: "Step " + tour.step + " of " + tour.stepCount
                    color: BarTheme.alpha(BarTheme.fg, 0.6)
                    font.family: Metrics.textFamily
                    font.pixelSize: Metrics.textSize - 1
                    renderType: Text.NativeRendering
                }
            }
        }

        // Key hints — only step 4 has any (the cheatsheet chord's four
        // sheets), same as CheatsheetPopup's own hint bar.
        Row {
            x: card.width * 0.05
            y: Metrics.s(62)
            spacing: Metrics.s(16)
            visible: (tour.stepHints[tour.step] || []).length > 0
            Repeater {
                model: tour.stepHints[tour.step] || []
                delegate: Row {
                    required property var modelData
                    spacing: Metrics.s(5)
                    Text {
                        text: modelData.key
                        color: BarTheme.fg
                        font.family: Metrics.textFamily
                        font.pixelSize: Metrics.textSize
                        font.bold: true
                        renderType: Text.NativeRendering
                    }
                    Text {
                        text: modelData.desc
                        color: BarTheme.alpha(BarTheme.fg, 0.6)
                        font.family: Metrics.textFamily
                        font.pixelSize: Metrics.textSize
                        renderType: Text.NativeRendering
                    }
                }
            }
        }

        Item {
            id: body
            x: card.width * 0.05
            y: Metrics.s(92)
            width: card.width * 0.9
            height: footer.y - y - Metrics.s(10)

            Column {
                visible: tour.step === 1
                width: parent.width
                spacing: Metrics.s(8)
                PageText {
                    width: parent.width
                    text: "This short tour walks through the essentials and gets you ready to work."
                }
                MutedText {
                    width: parent.width
                    text: "Cancel skips it entirely; Next starts with the bar itself."
                }
            }

            Column {
                visible: tour.step === 2
                width: parent.width
                spacing: Metrics.s(6)
                PageText { width: parent.width; text: "Left — Arch menu, workspaces, open windows." }
                PageText { width: parent.width; text: "Centre — the active workspace and its window stack." }
                PageText { width: parent.width; text: "Right — CPU/RAM/volume/brightness, updates, battery, layout, clock." }
                MutedText {
                    width: parent.width
                    text: "Arch icon: Left-click opens the menu · Right-click opens a terminal."
                }
                MutedText {
                    width: parent.width
                    text: "Alt+` system widgets · Win+` the second set · Alt+Tab the tray."
                }
            }

            Column {
                visible: tour.step === 3
                width: parent.width
                spacing: Metrics.s(8)
                PageText {
                    width: parent.width
                    text: "Win + 1–9 switches workspaces · Win + Shift + 1–9 moves the focused window there."
                }
                Flow {
                    width: parent.width
                    spacing: Metrics.s(6)
                    WsChip { num: "1"; label: "Tasks";           tint: BarTheme.yellow }
                    WsChip { num: "2"; label: "Web & Video";     tint: BarTheme.purple }
                    WsChip { num: "3"; label: "Files";           tint: BarTheme.blue }
                    WsChip { num: "4"; label: "Code & Terminal"; tint: BarTheme.cyan }
                    WsChip { num: "5"; label: "Brave";           tint: BarTheme.purple }
                    WsChip { num: "6"; label: "Chrome";          tint: BarTheme.purple }
                    WsChip { num: "8"; label: "Docs & Office";   tint: BarTheme.blue }
                    WsChip { num: "9"; label: "Chat";            tint: BarTheme.red }
                    WsChip { num: "S"; label: "Obsidian & Anki"; tint: BarTheme.green }
                }
                MutedText { width: parent.width; text: "7 is free." }
            }

            Column {
                visible: tour.step === 4
                width: parent.width
                spacing: Metrics.s(8)
                PageText {
                    width: parent.width
                    text: "Keybindings are what makes the workflow fast — give them a few days to become muscle memory."
                }
                MutedText {
                    width: parent.width
                    text: "Win + Shift + K enters the cheatsheet chord, then one of the keys below opens its sheet."
                }
            }

            Column {
                visible: tour.step === 5
                width: parent.width
                spacing: Metrics.s(6)
                PageText { width: parent.width; text: "You've covered the bar, workspaces and keybindings." }
                MutedText { width: parent.width; text: "Win + Shift + K then k/v/f/i opens the cheatsheet anytime." }
                MutedText { width: parent.width; text: "ati-update pulls the newest settings when this desktop changes." }
            }
        }

        Item {
            id: footer
            x: card.width * 0.05
            y: card.height - Metrics.s(20) - Metrics.s(40)
            width: card.width * 0.9
            height: Metrics.s(40)

            Rectangle {
                anchors { left: parent.left; right: parent.right; top: parent.top }
                height: 1
                color: BarTheme.alpha(BarTheme.fg, 0.15)
            }

            Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                anchors.topMargin: Metrics.s(8)
                y: Metrics.s(8)
                spacing: Metrics.s(6)
                Repeater {
                    model: tour.stepCount
                    delegate: Rectangle {
                        required property int index
                        width: Metrics.s(6)
                        height: Metrics.s(6)
                        radius: width / 2
                        color: (index + 1 === tour.step) ? BarTheme.accent : BarTheme.alpha(BarTheme.fg, 0.3)
                    }
                }
            }

            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                y: Metrics.s(8)
                spacing: Metrics.s(8)

                NavBtn {
                    visible: tour.step === 1
                    label: "Cancel"
                    onClicked: tour.visible = false
                }
                NavBtn {
                    visible: tour.step > 1
                    label: "Back"
                    onClicked: tour.step -= 1
                }
                NavBtn {
                    visible: tour.step === 4
                    label: "Cheatsheet"
                    onClicked: tour.openCheatsheet()
                }
                NavBtn {
                    visible: tour.step < tour.stepCount
                    primary: true
                    label: tour.step === 4 ? "Done" : "Next"
                    onClicked: tour.step += 1
                }
                NavBtn {
                    visible: tour.step === tour.stepCount
                    primary: true
                    label: "Finish"
                    onClicked: tour.visible = false
                }
            }
        }
    }

    // Escape closes it — the one thing every popup on this desktop agrees
    // on (see PopupChrome's own header on why that surface takes the
    // keyboard itself rather than relying on a compositor bind).
    FocusScope {
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: tour.visible = false
    }
}
