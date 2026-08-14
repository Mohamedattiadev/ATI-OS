import QtQuick
import Quickshell
import Quickshell.Wayland
import IslandBackend

import "../common"
import "../common/Metrics.js" as Metrics
import "../display"

//
// FORK — new file. `$alt 4` under the topbar.
//
// WHAT WAS MEASURED
// -----------------
// The key was bound, reached bar-action, and died in the native branch:
//
//     $ python3 scripts/display-ctl.py --menu
//     {"ok": false, "status": "unknown subcommand --menu"}      exit 0
//
// Exit 0 is the whole failure. bar-action ran `--menu || nwg-displays`, and
// a command that fails by PRINTING while exiting 0 never reaches the `||` —
// so the fallback was dead code, and `nwg-displays` is not installed either.
// The script has no `--menu` and never did; it has query/set/rotate/reflect/
// cycle-scale/preset/arrange/layout-*, all of which the island already drives.
//
// WHY THIS HOSTS THE ISLAND'S PANEL INSTEAD OF PORTING DisplayPopup.py
// --------------------------------------------------------------------
// The other popups in this folder are ports of qtile's popups/*.py, because
// the topbar is qtile's bar and its surfaces should be qtile's. That reasoning
// does not produce a second implementation HERE, and the reason is that the
// work was already done once: qml/display/DisplayPanel.qml's own header says
// it is "the port of qtile's popups/DisplayPopup.py (28 bindings)", key for
// key, with the one divergence (`p` cycles scale, because Hyprland has no
// primary output) written down in it.
//
// So qtile fidelity and island consistency are the SAME artifact here, and a
// third copy could only disagree with both. DisplayPopup.py is 1,998 lines;
// the panel is the thing that replaced it.
//
// NO PopupChrome, AND THAT IS NOT AN INCONSISTENCY
// -----------------------------------------------
// PopupChrome supplies a header, a keycap bar and a footer. DisplayPanel
// takes PanelChrome, which supplies a header, TABS, rules, a key-hint line
// and a footer of its own. Wrapping one in the other draws two headers and
// two hint bars around one panel. What this window owns is the FRAME —
// PopupChrome's own background, border and radius, so the surface still reads
// as one of this folder's popups — and nothing inside it.
//
// SIZED BY THE PANEL, CLAMPED BY THE SCREEN, which is what
// DynamicIslandWindow does for the same panel: `Math.min(preferredHeight,
// screen.height - 60)` and `Math.min(900, width - 48)`. The panel sizes
// itself because on a one-output laptop the old flat 300 px left ~45% of it
// as empty black.
PanelWindow {
    id: root

    // NOT `closed` — QQuickWindow already has one and the override is dropped
    // with a warning rather than an error. See NetworkPopup's header.
    signal requestClose()

    readonly property var userConfig: UserConfig

    // Unanchored, so the compositor centres it — `show(centered=True)` in the
    // file this folder copies. Anchoring and then computing a margin would be
    // the same placement done twice, and the second one wrong on any other
    // screen.
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.namespace: "quickshell-qtile-popup"
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    readonly property int frameInset: PopupMetrics.s(14)

    implicitWidth: Math.min(Metrics.px(900),
                            (root.screen ? root.screen.width : 1366) - Metrics.px(48))
    // + the frame's own padding, twice. The panel asks for the height of its
    // CONTENT; the border and the rounded corner are this file's.
    // ---- THE HEIGHT IS ASSIGNED, NOT BOUND ----
    //
    // Written first as `implicitHeight: panel.preferredHeight + inset*2` with
    // the panel on `anchors.fill`, and the window never mapped AT ALL — no
    // error, no layer surface, `popups status` cheerfully reporting `display`.
    // That is a binding cycle: the window's height read the panel and the
    // panel's height came from the window, and QML breaks a cycle by resolving
    // it to zero, silently. The same shape the docs already record for this
    // exact panel ("the panel height was computed from the chrome twice, and
    // both closed a binding cycle"); it does not bite inside the island only
    // because the capsule's height goes through an animating Behavior there.
    //
    // The second attempt — anchor the panel on three sides and let it take its
    // own height — does not work either, and the reason is worth keeping:
    // DisplayPanel declares `anchors.fill: parent` in its OWN file, so its
    // height comes from its parent no matter what the call site says. Probed:
    //
    //     PROBE pref= 201 body= 104 details= 14 list= -2 h= -28 w= 800
    //
    // preferredHeight was a perfectly good 201 the whole way through. Only the
    // panel's actual height had collapsed, to the negative of the inset.
    //
    // So the cycle is cut with an ASSIGNMENT. preferredHeight is content-
    // derived and settles once the outputs arrive; nothing in it reads the
    // panel's height, so writing the answer into a plain property cannot
    // oscillate. This is the island's own arrangement — there the same number
    // lands in a targetHeight that a Behavior animates.
    property int panelHeight: Metrics.px(300)

    readonly property int panelHeightCap:
        (root.screen ? root.screen.height : 768) - Metrics.px(60)
            - root.frameInset * 2

    implicitHeight: root.panelHeight + root.frameInset * 2

    Rectangle {
        anchors.fill: parent
        // PopupChrome's frame, to the number: bg + "F2" is 0xF2/255.
        color: IslandTheme.alpha(IslandTheme.background, 0.949)
        border.color: IslandTheme.mix(IslandTheme.background,
                                      IslandTheme.foreground, 0.14)
        border.width: PopupMetrics.s(2)
        radius: PopupMetrics.s(14)

        // On the CONTENT and not on the window: a PanelWindow has no opacity
        // property at all, and assigning one is a load error rather than a
        // no-op. Same 280 ms as PopupChrome's, so the four popups fade alike.
        opacity: 0
        Component.onCompleted: opacity = 1
        Behavior on opacity {
            NumberAnimation { duration: 280; easing.type: Easing.OutCubic }
        }

        // The panel fills THIS, and this is sized by an assignment — see the
        // note on panelHeight. A plain Item between the two is what gives the
        // panel a parent whose height is not a function of the panel.
        Item {
            id: panelHost
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: root.frameInset
            height: root.panelHeight

            DisplayPanel {
                id: panel
                anchors.fill: parent

                textFontFamily: root.userConfig.textFontFamily
                heroFontFamily: root.userConfig.heroFontFamily

                // The panel gates its own focus, its intro and its first read
                // on this. It is a Loader-driven layer inside the island; here
                // the window IS the gate, so it is simply true for as long as
                // the window exists.
                showCondition: true

                onCloseRequested: root.requestClose()

                // The assignment. Fires on every content change — an output
                // appearing, the mode list opening, a tab switch — which is
                // exactly when the panel wants a different amount of room.
                onPreferredHeightChanged: root.applyPanelHeight()
                Component.onCompleted: root.applyPanelHeight()
            }
        }
    }

    function applyPanelHeight() {
        root.panelHeight = Math.max(Metrics.px(120),
            Math.min(panel.preferredHeight, root.panelHeightCap));
    }
}
