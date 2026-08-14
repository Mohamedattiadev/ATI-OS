import QtQuick

//
// A BARE widget for the bottom bar: text, padding, colour, and no plate.
//
// The top bar's Chip and this are the two halves of config.py's own
// distinction — that bar "is built from chips, where every element already
// carries its own rounded background", this one "is built from bare widgets
// and uses pipes to group them". Giving these a plate would quietly turn the
// bottom bar into a second copy of the top one.
Item {
    id: root

    property string text: ""
    property int pixelSize: Metrics.s(11)
    property int padding: 4
    property color colour: BarTheme.fg
    // Nerd Font rather than the text face. The launcher glyphs and the Arch
    // mark are private-use codepoints; in Ubuntu Bold they are absent, and
    // fontconfig substitutes silently — which in this tree has produced
    // blank widgets that looked like missing data rather than a missing font.
    property bool iconFont: false
    property bool clickable: false
    property string tip: ""
    property var hoverSink: null

    signal pressed(int button)

    visible: text !== ""
    width: visible ? label.implicitWidth + root.padding * 2 : 0
    height: parent ? parent.height : Metrics.bottomBarHeight

    Text {
        id: label
        anchors.centerIn: parent
        text: root.text
        color: root.colour
        font.family: root.iconFont ? "Symbols Nerd Font" : "Ubuntu Bold"
        font.pixelSize: root.pixelSize
        maximumLineCount: 1
        elide: Text.ElideRight
        renderType: Text.NativeRendering
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.clickable || root.tip !== ""
        hoverEnabled: root.tip !== ""
        acceptedButtons: root.clickable
            ? (Qt.LeftButton | Qt.MiddleButton | Qt.RightButton) : Qt.NoButton
        cursorShape: root.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
        onEntered: if (root.hoverSink) root.hoverSink.enter(root, root.tip)
        onExited: if (root.hoverSink) root.hoverSink.exit(root)
        onClicked: (e) => root.pressed(e.button)
    }
}
