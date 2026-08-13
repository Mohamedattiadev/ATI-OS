import QtQuick

Item {
    id: root

    property var screen: null
    property bool showCondition: false
    property bool previewsEnabled: false
    property string textFontFamily: ""
    property string heroFontFamily: ""
    property string wallpaperPath: ""
    property real windowCornerRadius: 22

    property alias overviewView: overviewView
    property alias overviewDataReady: hyprlandData.ready

    signal closeRequested()

    anchors.fill: parent

    // FORK: P0-3 / Phase 3.4. This scene is a plain Item between the loader
    // and the layer that owns the keys, so without a focus claim here the
    // chain stops at this level exactly as it stopped at `islandContainer`
    // for the three panels the earlier audit fixed. Bound to showCondition
    // rather than `true` because this loader is ALWAYS active — it is
    // `active: !compositorIsNiri`, never unloaded — so an unconditional
    // claim would compete with whichever panel is genuinely open.
    focus: showCondition

    // `focus: true` only NOMINATES this item as its parent scope's focus
    // child. Something still has to walk the chain with forceActiveFocus(),
    // and for the panels that is `keyPanelFocusTimer` in DynamicIslandWindow
    // — which is restarted for the control centre, the notification centre
    // and the settings panel, and not for the overview. So the window took
    // an Exclusive keyboard grab (it always did, line 323) and the keystroke
    // then arrived at an item that had never been given active focus.
    //
    // Measured before this line existed: with the overview open, `wtype l`
    // left the workspace on 4 and `wtype -k Escape` left the layer at
    // 1366x322. Both keys were being delivered to the window and dropped
    // inside it.
    //
    // Claimed from the item itself, which is what NotificationCenterLayer
    // ended up doing for the same reason — the item exists by definition at
    // the moment its own handler runs, so there is no race against a timer
    // observing the same boolean. Qt.callLater for the ordering reason
    // recorded there: a timer may still fire after us and hand focus back to
    // the scope, so the claim has to land in the same turn rather than
    // before it.
    onShowConditionChanged: {
        if (showCondition)
            Qt.callLater(function() {
                if (root.showCondition)
                    overviewView.forceActiveFocus();
            });
    }

    HyprlandData {
        id: hyprlandData
    }

    WorkspaceOverviewLayer {
        id: overviewView

        anchors.centerIn: parent
        focus: root.showCondition
        screen: root.screen
        hyprlandData: hyprlandData
        showCondition: root.showCondition
        previewsEnabled: root.previewsEnabled
        textFontFamily: root.textFontFamily
        heroFontFamily: root.heroFontFamily
        wallpaperPath: root.wallpaperPath
        windowCornerRadius: root.windowCornerRadius
        onCloseRequested: root.closeRequested()
    }
}
