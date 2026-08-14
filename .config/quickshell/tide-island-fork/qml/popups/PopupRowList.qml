import QtQuick

import "../common"

//
// FORK — new file. The scrolling list card the network and volume popups are
// both built out of.
//
// WifiPopup.py and AudioPopup.py draw the same thing: one surface card
// holding ROWS_VISIBLE=17 padded monospace rows, with the selected row filled
// in the accent and its text in the background colour. They differ in what a
// row SAYS, not in how the list behaves — so the behaviour is here and the
// text is a delegate the caller supplies.
//
// THE SCROLL RULE IS THEIRS
// -------------------------
// Both files keep an _OFFSET per view and move it only when the cursor would
// leave the window, which is why holding `j` walks the cursor down a still
// list and then scrolls the list under a still cursor. A list that re-centres
// on every step is a different, worse thing that also looks busier.
Item {
    id: root

    // [{ mark, left, right, tone }] — `tone` is a colour for the row's text
    // when it is not selected, so a popup can mark a connected network or a
    // muted sink without this file knowing what either is.
    property var rows: []
    property int index: 0
    property int offset: 0
    property int rowsVisible: 17

    property color surface: IslandTheme.background
    property color fg: IslandTheme.foreground
    property color muted: IslandTheme.foreground
    property color highlight: IslandTheme.green
    property color highlightInk: IslandTheme.background

    readonly property int rowHeight: Math.round(PopupMetrics.rowSize * 1.5)

    function clampIndex() {
        if (root.rows.length === 0) {
            root.index = 0;
            root.offset = 0;
            return;
        }
        root.index = Math.max(0, Math.min(root.rows.length - 1, root.index));
        if (root.index < root.offset)
            root.offset = root.index;
        else if (root.index >= root.offset + root.rowsVisible)
            root.offset = root.index - root.rowsVisible + 1;
        root.offset = Math.max(0, Math.min(root.offset,
            Math.max(0, root.rows.length - root.rowsVisible)));
    }

    function move(delta) {
        root.index += delta;
        root.clampIndex();
    }

    function jump(where) {
        root.index = (where === "top") ? 0 : Math.max(0, root.rows.length - 1);
        root.clampIndex();
    }

    onRowsChanged: root.clampIndex()

    Rectangle {
        anchors.fill: parent
        color: root.surface
        radius: PopupMetrics.s(10)
        clip: true

        Column {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: PopupMetrics.s(10)
            anchors.rightMargin: PopupMetrics.s(10)
            anchors.top: parent.top
            anchors.topMargin: PopupMetrics.s(8)
            spacing: 0

            Repeater {
                model: root.rowsVisible

                delegate: Item {
                    required property int index
                    readonly property int rowIndex: root.offset + index
                    readonly property bool exists:
                        rowIndex >= 0 && rowIndex < root.rows.length
                    readonly property var row: exists ? root.rows[rowIndex] : null
                    readonly property bool selected: exists && rowIndex === root.index

                    width: parent.width
                    height: root.rowHeight

                    Rectangle {
                        anchors.fill: parent
                        anchors.rightMargin: PopupMetrics.s(2)
                        visible: parent.selected
                        color: root.highlight
                        radius: PopupMetrics.s(4)
                    }

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: PopupMetrics.s(8)
                        anchors.verticalCenter: parent.verticalCenter
                        // Guarded on `row` and not on `exists`: the two are
                        // separate bindings over the same model, and Qt
                        // re-evaluates them in an order it does not promise —
                        // so mid-reassignment `exists` can already be true
                        // while `row` is still null. The result is a
                        // "Value is null" TypeError per row per refresh, in
                        // the log only, with the list looking correct.
                        text: parent.row
                            ? (parent.row.mark + " " + parent.row.left) : ""
                        color: parent.selected ? root.highlightInk
                            : (parent.row && parent.row.tone !== undefined
                                ? parent.row.tone : root.fg)
                        font.family: PopupMetrics.font
                        font.pixelSize: PopupMetrics.rowSize
                        font.bold: parent.selected
                        renderType: Text.NativeRendering
                    }

                    // The right-hand column — signal, volume, whatever the
                    // popup puts there. Right-aligned rather than padded into
                    // the left string: the two columns then stay aligned
                    // whatever the width of the card, which a padded string
                    // cannot promise once a name is elided.
                    Text {
                        anchors.right: parent.right
                        anchors.rightMargin: PopupMetrics.s(12)
                        anchors.verticalCenter: parent.verticalCenter
                        text: parent.row && parent.row.right !== undefined
                            ? parent.row.right : ""
                        color: parent.selected ? root.highlightInk : root.muted
                        font.family: PopupMetrics.font
                        font.pixelSize: PopupMetrics.rowSize
                        font.bold: parent.selected
                        renderType: Text.NativeRendering
                    }
                }
            }
        }
    }
}
