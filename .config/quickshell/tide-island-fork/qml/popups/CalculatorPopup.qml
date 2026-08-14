import QtQuick
import Quickshell
import Quickshell.Wayland
import IslandBackend

import "../common"
import "../common/Metrics.js" as Metrics
import "../island"

//
// FORK — new file. `$alt 5` under the topbar.
//
// WHAT THE HANDOFF SAID, AND WHAT THE CONFIG SAYS
// -----------------------------------------------
// The reported cause was that `rofi -show calc` needs the rofi-calc plugin,
// which is absent — measured, and true: `/usr/lib/rofi/` does not exist at
// all, so bar-action fell through to `kitty -e qalc`, a terminal rather than
// the panel that was asked for.
//
// But the premise underneath it was wrong, and the AST says so. qtile's
// `$alt 5` is not rofi-calc:
//
//     Key([mod2], "5", lazy.group["scratchpad"].dropdown_toggle("calc"))
//     ("calc", "env GTK_THEME=Adwaita:dark qalculate-gtk", …)
//
// It is a SCRATCHPAD holding qalculate-gtk. So "restore the rofi menu" was
// never the target; there is no calculator popup in qtile's popups/ either.
// binds.conf already decided where this goes and wrote down why — that
// `GTK_THEME=Adwaita:dark` is a confession that the app cannot follow
// theme-apply, so it is the same grey box under all 22 palettes — and the
// island has answered `$alt 5` with its own panel since. The topbar was the
// only bar still without one.
//
// So this is the island's CalculatorLayer in a window, for the same reason
// DisplayPopup hosts DisplayPanel: the implementation exists, it is the one
// the other bar opens on this key, and a second copy could only disagree
// with it. The engine is `qalc`, libqalculate's CLI and the thing
// qalculate-gtk is a front end FOR, so no package moves and no expression
// answers differently.
//
// The height is ASSIGNED rather than bound. DisplayPopup's header has the
// full post-mortem: these layers declare `anchors.fill: parent` in their own
// files, so binding a window's height to a child's preferredHeight closes a
// cycle that QML resolves to zero — no error, no surface, and an IPC that
// still reports the popup as open.
PanelWindow {
    id: root

    // NOT `closed` — QQuickWindow already has one. See NetworkPopup's header.
    signal requestClose()

    readonly property var userConfig: UserConfig

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.namespace: "quickshell-qtile-popup"
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    readonly property int frameInset: PopupMetrics.s(14)

    // Metrics.px(340) is the island's own width for this state, and its
    // reasoning carries over unchanged: the widest thing in the panel is a
    // result, a result is right-aligned against the edge, and width past what
    // the tape needs is empty space between an expression and its answer.
    implicitWidth: Metrics.px(340) + root.frameInset * 2

    property int panelHeight: Metrics.px(200)
    readonly property int panelHeightCap:
        (root.screen ? root.screen.height : 768) - Metrics.px(60)
            - root.frameInset * 2

    implicitHeight: root.panelHeight + root.frameInset * 2

    function applyPanelHeight() {
        root.panelHeight = Math.max(Metrics.px(100),
            Math.min(panel.preferredHeight, root.panelHeightCap));
    }

    Rectangle {
        anchors.fill: parent
        color: IslandTheme.alpha(IslandTheme.background, 0.949)
        border.color: IslandTheme.mix(IslandTheme.background,
                                      IslandTheme.foreground, 0.14)
        border.width: PopupMetrics.s(2)
        radius: PopupMetrics.s(14)

        // On the CONTENT, never on the window: a PanelWindow has no opacity
        // property and assigning one is a load error.
        opacity: 0
        Component.onCompleted: opacity = 1
        Behavior on opacity {
            NumberAnimation { duration: 280; easing.type: Easing.OutCubic }
        }

        Item {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: root.frameInset
            height: root.panelHeight

            CalculatorLayer {
                id: panel
                anchors.fill: parent

                textFontFamily: root.userConfig.textFontFamily
                heroFontFamily: root.userConfig.heroFontFamily
                iconFontFamily: root.userConfig.iconFontFamily

                // The window is the gate here, not a Loader inside a capsule,
                // so this is simply true for as long as the window exists.
                showCondition: true

                onCloseRequested: root.requestClose()

                // Re-fires as the tape grows, which is when the panel wants
                // more room. See root.applyPanelHeight.
                onPreferredHeightChanged: root.applyPanelHeight()
                Component.onCompleted: root.applyPanelHeight()
            }
        }
    }
}
