import QtQuick
import IslandBackend

// FORK: one shared scale factor for every island surface.
import "../common/Metrics.js" as Metrics
import "../common"

Item {
    id: root

    readonly property var userConfig: UserConfig

    signal buttonPressed()
    signal clicked()

    property string kind: "play"
    property string textFontFamily: ""
    readonly property bool down: controlArea.pressed
    readonly property string iconText: {
        if (kind === "previous") return "⏮";
        if (kind === "next") return "⏭";
        if (kind === "pause") return "⏸";
        return "▶";
    }

    width: Metrics.px(28)
    height: Metrics.px(28)
    scale: controlArea.pressed ? 0.8 : 1.0
    opacity: enabled ? 1.0 : 0.45

    Behavior on scale {
        NumberAnimation {
            duration: 100
        }
    }

    Text {
        anchors.centerIn: parent
        text: root.iconText
        color: controlArea.pressed ? IslandTheme.textMuted : IslandTheme.textPrimary
        // The transport glyphs are the one place where scaling by the shared
        // factor was not enough. Upstream sized them at iconFontSize + 7/+5
        // against an 18px icon font — 25 and 23 px in a 28px box, a ratio of
        // ~0.85. Preserving that ratio through the rescale kept them
        // proportionally the largest thing on the card, and next to a 12px
        // title they read as oversized rather than as prominent. They are the
        // user's "< = > elements are big".
        //
        // Brought down to the surrounding type instead: play gets +2 for the
        // extra weight a filled triangle needs to match a glyph's optical
        // size, and the skip arrows sit at the icon size itself.
        // Absolute sizes, not offsets from iconFontSize. These four glyphs
        // (U+23EE/23ED/23F8/25B6) do not come from JetBrainsMono at all —
        // fontconfig falls them through to an emoji face, which draws them at
        // very nearly the full em box where a text glyph uses about two
        // thirds of it. So the same pixelSize buys a visibly larger mark here
        // than anywhere else on the card, which is why matching iconFontSize
        // still looked oversized. Sized by eye against the 12px title.
        font.pixelSize: root.kind === "play" ? Metrics.font(17) : Metrics.font(15)
        font.family: root.textFontFamily
        font.weight: Font.DemiBold
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    MouseArea {
        id: controlArea
        anchors.fill: parent
        anchors.margins: Metrics.pad(-15)
        enabled: root.enabled
        preventStealing: true

        onPressed: function(mouse) {
            root.buttonPressed();
            mouse.accepted = true;
        }
        onClicked: root.clicked()
    }
}
