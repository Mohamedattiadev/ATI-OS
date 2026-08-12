import QtQuick
import "../common"

Item {
    id: root

    property real radius: 20
    property bool hovered: false
    property bool pressed: false
    readonly property real innerRadius: Math.max(0, radius - 1)

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: root.pressed ? IslandTheme.surfaceRaised : (root.hovered ? IslandTheme.surfaceRaisedHover : IslandTheme.surfaceRaisedActive)
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        radius: root.innerRadius
        color: root.pressed ? IslandTheme.surfaceSunken : (root.hovered ? IslandTheme.surfaceRaised : IslandTheme.surface)
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        radius: root.innerRadius
        color: "transparent"
        border.width: 1
        border.color: root.hovered ? IslandTheme.hairlineStrong : IslandTheme.hairline
    }
}
