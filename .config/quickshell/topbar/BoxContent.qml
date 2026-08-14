import QtQuick

//
// One widget box's contents, in the shared expansion area.
//
// ---- WHERE THE CONTENTS SIT, WHICH IS NOT THE SAME FOR EVERY BOX ----
//
// This is one box's contents; WHERE it is placed is the caller's choice, and
// shell.qml makes that choice per box because config.py does:
//
//     system_widgetbox      insert_before_name="tooltip_widgetbox"
//     2nd_system_widgetbox  insert_before_name="tooltip_widgetbox"
//     systray_widgetbox     — nothing, so it opens in its OWN slot
//
// So the two system boxes collect in one shared area immediately left of the
// lamp, which is also what was asked for directly ("the position of opening
// chips should be in the left of the lamp chip"), and the tray opens beside
// its own triangle — "the triangle chip should show the icons near to it".
// Both are the same rule read from the two ends.
//
// The boxes stay INDEPENDENT, as qtile's are: each of these is visible on its
// own box's `open`, so more than one can be shown at once.
//
// The Row is anchored RIGHT so a box grows LEFTWARDS as it opens, which is
// what `close_button_location='right'` means — the toggle keeps its place and
// the contents appear in front of it, rather than the toggle being shoved
// along the bar every time it is pressed.
Item {
    id: root

    default property alias content: row.data
    property bool open: false

    clip: true
    width: root.open ? row.implicitWidth : 0
    height: parent ? parent.height : Metrics.barHeight

    // NO `visible: width > 0`. It deadlocks: this Item's visibility would
    // depend on its width, its width on the Row's implicitWidth, and a Row
    // counts only VISIBLE children — which its children are not, because an
    // item whose parent is invisible reports visible false. Nothing in that
    // cycle can become non-zero. It cost a debugging session the first time;
    // WidgetBox.qml carried the same note before the contents moved here.
    Behavior on width {
        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
    }

    Row {
        id: row
        height: parent.height
        spacing: 0
        // Anchored RIGHT so the group grows leftwards, away from the lamp,
        // instead of shoving the lamp along as it opens.
        anchors.right: parent.right
    }
}
