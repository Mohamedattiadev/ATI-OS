import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

import "../common"

//
// FORK — new file. config.py's `_show_pass_confirm`, in Quickshell.
//
// 360x140, centred, `bg + "F2"` — that file's numbers. The three controls and
// their fractional positions are its own:
//
//     "Exit passthrough mode?"   y 0.15  h 0.30   large, bold, fg
//     "  Yes  (y)  "             x 0.05  w 0.42   bold, green
//     "  No  (n)  "              x 0.53  w 0.42   bold, red
//
// IT MUST NOT TAKE THE KEYBOARD, and that is the one thing to get right.
// config.py says so at length on the Yes control: `can_focus` defaults to
// "auto", which is True for anything with a Button1 callback, and that flips
// the layout's keyboard_navigation on — which makes show() steal focus and
// swallow the chord's own y / n / Escape. Both controls are pinned
// can_focus=False there for that reason.
//
// The same trap exists here in a different spelling. Every other popup in
// this folder takes `WlrKeyboardFocus.Exclusive` because it IS the thing
// reading the keys. This one is not: the compositor's `passthrough-confirm`
// submap owns y, n and Escape, and a surface that grabbed the keyboard would
// take them away from it — leaving a popup you can only dismiss by clicking,
// inside a mode whose whole purpose is that the keyboard goes elsewhere.
//
// So: WlrKeyboardFocus.None. The clicks still work, exactly as they do in
// qtile, because a mouse callback never needed focus in the first place.
PanelWindow {
    id: root

    // NOT `closed` — QQuickWindow has one. See NetworkPopup's header.
    signal yes()
    signal no()


    // ---- WHICH MONITOR, WHICH IS ONLY A QUESTION WITH TWO ----
    //
    // These popups had no `screen` at all, so Quickshell placed them on
    // whichever it picked first — the primary. With one monitor that is
    // always right and the bug is invisible; with two it means every popup
    // opens on the OTHER screen from the one you are working on.
    //
    // Bound to the FOCUSED monitor, not to a configured one: a popup is
    // opened by a keypress, and the screen your keyboard is on is the screen
    // you are looking at. Matched by NAME because Hyprland's monitor object
    // and Quickshell's ShellScreen are different types over the same output.
    //
    // Null when there is no match, which is Quickshell's own default and the
    // right answer while a monitor is being added or removed — a popup on
    // the wrong screen beats a popup on no screen.
    screen: {
        const focused = Hyprland.focusedMonitor;
        if (!focused)
            return null;
        const screens = Quickshell.screens;
        for (let i = 0; i < screens.length; i++)
            if (String(screens[i].name) === String(focused.name))
                return screens[i];
        return null;
    }
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.namespace: "quickshell-passthrough-confirm"
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    // Unanchored, so the compositor centres it — `show(centered=True)`.
    implicitWidth: PopupMetrics.s(360)
    implicitHeight: PopupMetrics.s(140)

    readonly property color cSurfaceAlt: IslandTheme.mix(IslandTheme.background,
                                                         IslandTheme.foreground, 0.14)

    Rectangle {
        anchors.fill: parent
        color: IslandTheme.alpha(IslandTheme.background, 0.949)
        border.color: root.cSurfaceAlt
        border.width: PopupMetrics.s(2)
        radius: PopupMetrics.s(14)

        // fade_in_popup(layout, duration=0.16, steps=10) — shorter than the
        // panel popups' 0.28, and that difference is qtile's: this one is
        // small and it is asking a question, so it should already be there.
        //
        // On the CONTENT, never the window: a PanelWindow has no opacity.
        opacity: 0
        Component.onCompleted: opacity = 1
        Behavior on opacity {
            NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
        }

        Text {
            y: parent.height * 0.15
            width: parent.width
            height: parent.height * 0.30
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: "Exit passthrough mode?"
            color: IslandTheme.textPrimary
            font.family: PopupMetrics.font
            // pango's "large" is 1.2x the base.
            font.pixelSize: Math.round(PopupMetrics.headSize * 1.2)
            font.bold: true
            renderType: Text.NativeRendering
        }

        Rectangle {
            id: yesBtn
            x: parent.width * 0.05
            y: parent.height * 0.55
            width: parent.width * 0.42
            height: parent.height * 0.30
            radius: PopupMetrics.s(8)
            color: yesArea.containsMouse ? root.cSurfaceAlt : "transparent"

            Text {
                anchors.centerIn: parent
                text: "  Yes  (y)  "
                color: IslandTheme.success
                font.family: PopupMetrics.font
                font.pixelSize: PopupMetrics.rowSize
                font.bold: true
                renderType: Text.NativeRendering
            }
            MouseArea {
                id: yesArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.yes()
            }
        }

        Rectangle {
            id: noBtn
            x: parent.width * 0.53
            y: parent.height * 0.55
            width: parent.width * 0.42
            height: parent.height * 0.30
            radius: PopupMetrics.s(8)
            color: noArea.containsMouse ? root.cSurfaceAlt : "transparent"

            Text {
                anchors.centerIn: parent
                text: "  No  (n)  "
                color: IslandTheme.danger
                font.family: PopupMetrics.font
                font.pixelSize: PopupMetrics.rowSize
                font.bold: true
                renderType: Text.NativeRendering
            }
            MouseArea {
                id: noArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.no()
            }
        }
    }
}
