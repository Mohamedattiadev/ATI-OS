import QtQuick

//
// One widget box's contents, in the shared expansion area.
//
// ---- WHY THE CONTENTS ARE NOT INSIDE THEIR OWN BOX ----
//
// They were, and they opened between the lamp chip and their own toggle,
// which is where qtile's `close_button_location='right'` puts them. Asked for
// the other arrangement: "the position of opening chips or list with chips
// should be in the left of the lamp chip".
//
// So every box's contents now live in ONE area at the far left of the
// right-hand cluster, immediately left of the lamp, and the boxes themselves
// are toggle chips with nothing inside them. Opening any box grows that one
// area rather than pushing a hole into the middle of the row — which also
// means two boxes open at once read as one list rather than as two gaps.
//
// The boxes stay INDEPENDENT, as qtile's are: each of these is visible on its
// own box's `open`, so more than one can be shown, and they simply sit next
// to each other.
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
