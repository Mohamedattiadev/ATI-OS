import QtQuick
import IslandBackend

// FORK: one shared scale factor for every island surface.
import "../common/Metrics.js" as Metrics
// FORK: the shared motion system — one spring for geometry, one
// critically damped curve for opacity. See qml/common/Motion.js.
import "../common/Motion.js" as Motion
import "../common"

Item {
    id: root

    readonly property var userConfig: UserConfig

    property var items: []
    property var cavaLevels: []
    property string timeText: ""
    property var configSource: null
    readonly property var activeConfig: configSource || userConfig
    property string iconFontFamily: activeConfig.iconFontFamily
    property string textFontFamily: activeConfig.textFontFamily
    property string timeFontFamily: activeConfig.timeFontFamily
    property bool showCondition: false
    property bool showSecondaryText: true
    property bool recordingActive: false
    property real transitionProgress: 0
    property real minimumWidth: Metrics.px(220)
    property real maximumWidth: minimumWidth
    property real horizontalPadding: Metrics.pad(14)
    property real hiddenLeftPadding: Metrics.pad(18)
    property real hiddenRightPadding: Metrics.pad(18)
    property real groupSpacing: 16
    property real iconSpacing: 8
    property int textPixelSize: userConfig.bodyFontSize
    property int iconPixelSize: userConfig.iconFontSize

    // ---- WHY THE STAT GLYPHS GET THEIR OWN, LARGER SIZE ----
    //
    // FORK: reported as "the icon of ram and cpu in the swipe to right is
    // too small". The obvious reading — that iconFontSize is below
    // bodyFontSize — is FALSE, and checking it is what found the real
    // cause. `iconFontSize` is 13 against `bodyFontSize` 12, so the glyphs
    // are nominally the LARGER of the two, which is why nobody had touched
    // this.
    //
    // Nominal size is the wrong measure. Rendered with PIL against the
    // actual faces fontconfig resolves (JetBrainsMonoNerdFont-Regular.ttf
    // and Inter.ttc), measuring INK bounding boxes rather than em boxes:
    //
    //     Inter Medium @12   digit "3"        cap height   9 px
    //     Nerd Font    @13   cpu  U+F035B     ink height  11 px
    //     Nerd Font    @13   ram  U+F061A     ink height  10 px
    //
    // So the glyph is 1-2 px taller than the digit beside it and still
    // reads smaller — because a digit is one stroke and these are
    // PICTOGRAMS. U+F035B is a chip with eight pins and a lettered core;
    // U+F061A is a memory stick with a notch and contact fingers. At 10 px
    // of ink that detail is below the point where it resolves, so the
    // shape turns to grey texture while the numeral beside it stays sharp.
    // A pictogram needs roughly 1.5x a cap height to carry the same
    // presence, not 1.0x.
    //
    // Solved for from the same measurements — target ink ~14-15 px:
    //
    //     size   cpu ink   ram ink   max width
    //       13      11        10        11
    //       17      14        12        14
    //       18      15        13        15     <- chosen
    //
    // 18 rather than 17 because `ram` is the laggard of the pair and 13 px
    // is where its contact fingers separate. Width 15 still clears
    // `iconBoxSize`, which goes to 20 below for the same reason — the box
    // was sized for the old ink and would now clip the disk glyph
    // (U+F1C0, ink 17 at this size) if that slot is ever configured.
    //
    // Derived from `iconFontSize` rather than written as a literal 18, so
    // a user who scales the island's icon font still gets the correction
    // applied on top of their choice instead of having it silently
    // overridden.
    property int statIconPixelSize: userConfig.iconFontSize + 5
    property int iconBoxSize: 20
    // ---- THE BATTERY PILL, SCALED DOWN ONE STEP ----
    //
    // FORK: asked for after the stat glyphs went up — "the battery icon when
    // I swipe to right needs to be a bit smaller". The two changes are
    // related and the order matters: the pill did not grow, its neighbours
    // did, and a pill that read as balanced against 10 px of glyph ink reads
    // as heavy against 15.
    //
    // It also carries a weight the glyphs do not. The cpu and ram marks are
    // strokes on the shell fill; the battery is a FILLED white capsule with
    // dark numerals inside it, so at equal height it has several times the
    // ink and pulls the eye first. It is the one item on the row that is not
    // an outline, which is deliberate — charge is the reading you glance for
    // — but it was overshooting that job rather than doing it.
    //
    // Scaled as a set at ~0.87 rather than by shaving the one dimension that
    // looked worst, because the tip, the radii and the numerals are all in
    // proportion to the body and moving one alone is what makes a drawn
    // object look wrong in a way nobody can name:
    //
    //     width   37 -> 32     font          13 -> 11
    //     height  17 -> 15     font charging 12 -> 10
    //     radius   6 ->  5     bolt          10 ->  9
    //     tip h    5 ->  4
    //
    // tipWidth and innerRadius hold at 2 and 3: both are already at the
    // smallest value that survives rounding at this scale, and taking either
    // to 1 and 2 loses the shape rather than shrinking it. "100" at font 11
    // is ~19 px of Inter against 32 px of body, so the widest reading still
    // clears its capsule.
    property int batteryIconWidth: 32
    property int batteryIconHeight: 15
    property int batteryFontSize: 11
    property int batteryFontSizeCharging: 10
    property int batteryBoltSize: 9
    property int batteryTipWidth: 2
    property int batteryTipHeight: 4
    property int batteryOuterRadius: 5
    property int batteryInnerRadius: 3
    property real iconVerticalOffset: 1
    property int recordingDotSpacing: 12
    property real batteryChargingXOffset: 0
    property real batteryChargingYOffset: 0
    readonly property string chargingIconGlyph: "\uf0e7"

    // ---- COLOUR ON THIS CARD ----
    //
    // FORK: every glyph and every numeral here was the literal "white". That
    // is not a neutral choice on a shell whose whole surface follows pywal \u2014
    // it is the one colour that cannot follow it, so the card stayed the same
    // card under every theme while the notch around it changed.
    //
    // The rule is: the ACCENT identifies, the DANGER colour warns, and both
    // come from IslandTheme, which derives them from the palette and then
    // runs them through _toContrast against the shell fill. No literal hues
    // are introduced \u2014 a red invented here would be the one thing on the card
    // that a theme switch could not reach.
    //
    // Only the numerals stay ink-white while healthy. Tinting the glyph AND
    // its number in the accent gives a row of three identical blue blocks
    // with no focal point; the glyph carries the hue, the number carries the
    // reading, and they agree only when the reading is bad.
    property real highUsageThreshold: 85
    readonly property color iconColor: IslandTheme.accent
    readonly property color valueColor: "white"
    readonly property color alarmColor: IslandTheme.danger

    // A stat is in trouble when it has an actual reading (-1 is "not sampled
    // yet", see IslandSystemState.buildCustomSwipeItem) and that reading is
    // at or past the threshold. Items with no `value` at all \u2014 volume,
    // brightness, the clock \u2014 are never in trouble.
    function usageIsHigh(rawValue) {
        if (rawValue === undefined || rawValue === null)
            return false;
        const numericValue = Number(rawValue);
        return isFinite(numericValue)
            && numericValue >= 0
            && numericValue >= highUsageThreshold;
    }

    readonly property real clampedProgress: Math.max(0, Math.min(1, -transitionProgress))
    readonly property real textWidth: Math.max(0, width - horizontalPadding * 2)
    readonly property real centeredTimeX: horizontalPadding
    readonly property real centeredItemsX: (width - contentRow.implicitWidth) / 2
    readonly property real timeHiddenLeftX: -textWidth - hiddenLeftPadding
    readonly property real itemsHiddenRightX: width + hiddenRightPadding
    readonly property real timeExitDistance: Math.max(0, centeredTimeX - timeHiddenLeftX)
    readonly property real itemsEntryDistance: Math.max(0, itemsHiddenRightX - centeredItemsX)
    readonly property real dragDistance: Math.max(timeExitDistance, itemsEntryDistance)
    readonly property real itemsX: centeredItemsX + (1 - clampedProgress) * dragDistance
    readonly property real timeX: centeredTimeX - clampedProgress * dragDistance
    readonly property real visibleTimeWidth: Math.min(textWidth, Math.max(0, timeMetrics.advanceWidth))
    readonly property real timeRecordingDotX: Math.max(
        4,
        timeX + (textWidth - visibleTimeWidth) / 2 - recordingDotSpacing - timeRecordingIndicator.width
    )
    readonly property real preferredWidth: Math.max(
        minimumWidth,
        Math.min(Math.max(minimumWidth, maximumWidth), contentRow.implicitWidth + horizontalPadding * 2 + 28)
    )

    anchors.fill: parent
    clip: true
    opacity: showCondition ? 1 : 0

    // FORK: one choreography for every layer in the shell.
    // Was `showCondition ? 220 : 140` on Easing.InOutQuad — one of
    // eight hand-picked in-durations and six out-durations that agreed
    // with neither each other nor the 400 ms the shape takes. See
    // Motion.js, "CONTENT CHOREOGRAPHY", for the measurement.
    Behavior on opacity {
        NumberAnimation {
            duration: showCondition ? Motion.fadeInDuration() : Motion.fadeOutDuration()
            // Critically damped: opacity is clamped 0-1 and an
            // overshooting fade reads as a cut. Motion.js says why.
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Motion.fade()
        }
    }

    TextMetrics {
        id: timeMetrics
        font.family: timeFontFamily
        font.pixelSize: root.textPixelSize + 1
        font.weight: Font.Bold
        text: timeText
    }

    Row {
        id: contentRow
        x: itemsX
        height: parent.height
        anchors.verticalCenter: parent.verticalCenter
        opacity: clampedProgress
        spacing: groupSpacing

        Repeater {
            model: root.items

            delegate: Item {
                readonly property bool hasIcon: modelData.icon !== ""
                readonly property bool isCava: modelData.kind === "cava"
                readonly property bool isBattery: modelData.kind === "battery"
                readonly property bool hasLeadingVisual: hasIcon || isBattery
                readonly property bool usageHigh: root.usageIsHigh(modelData.value)
                implicitWidth: isCava
                    ? cavaBars.implicitWidth
                    : isBattery
                      ? root.batteryIconWidth
                      : leadingVisual.width + (hasLeadingVisual ? root.iconSpacing : 0) + valueText.implicitWidth
                implicitHeight: root.height
                width: implicitWidth
                height: implicitHeight

                SwipeCavaBars {
                    id: cavaBars
                    visible: parent.isCava
                    anchors.centerIn: parent
                    levels: root.cavaLevels
                }

                Item {
                    id: leadingVisual
                    visible: !parent.isCava && parent.hasLeadingVisual
                    width: parent.isBattery ? root.batteryIconWidth : (parent.hasIcon ? root.iconBoxSize : 0)
                    height: parent.isBattery ? Math.max(root.batteryIconHeight, valueText.implicitHeight) : root.iconBoxSize
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: root.iconVerticalOffset
                        visible: parent.parent.hasIcon && !parent.parent.isBattery
                        text: modelData.icon || ""
                        color: parent.parent.usageHigh ? root.alarmColor : root.iconColor
                        // statIconPixelSize, not iconPixelSize — see the
                        // measurement block at the top of this file. These
                        // are pictograms sitting next to numerals and need
                        // the optical correction; `iconPixelSize` stays as
                        // it was for anything that is a plain symbol.
                        font.pixelSize: root.statIconPixelSize
                        font.family: root.iconFontFamily

                        // The same 300 ms the battery's fill and tip already
                        // use. A glyph that SNAPS to red on one 3-second poll
                        // and back on the next reads as a rendering glitch;
                        // crossed on a fade it reads as a reading changing.
                        Behavior on color {
                            ColorAnimation { duration: 300 }
                        }
                    }

                    Item {
                        id: batteryShape
                        visible: parent.parent.isBattery
                        width: root.batteryIconWidth
                        height: root.batteryIconHeight
                        anchors.verticalCenter: parent.verticalCenter

                        readonly property real level: Math.max(0, Math.min(100, Number(modelData.level || 0)))
                        readonly property bool charging: modelData.isCharging || false
                        readonly property bool roundedEnd: level >= 85
                        readonly property color bodyColor: {
                            if (charging)
                                return "white";
                            if (level <= 20)
                                return IslandTheme.danger;
                            return "white";
                        }
                        readonly property color emptyColor: IslandTheme.alpha(IslandTheme.ink, 0.56)

                        Rectangle {
                            id: batteryBody
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - root.batteryTipWidth - 1
                            height: parent.height
                            radius: root.batteryOuterRadius
                            color: batteryShape.emptyColor
                            border.width: 0
                            clip: true

                            Rectangle {
                                id: batteryFill
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                radius: 0
                                topLeftRadius: root.batteryOuterRadius
                                bottomLeftRadius: root.batteryOuterRadius
                                topRightRadius: batteryShape.roundedEnd ? root.batteryOuterRadius : 0
                                bottomRightRadius: batteryShape.roundedEnd ? root.batteryOuterRadius : 0
                                width: Math.max(root.batteryOuterRadius * 2, parent.width * (batteryShape.level / 100.0))
                                color: batteryShape.bodyColor

                                Behavior on width {
                                    NumberAnimation {
                                        duration: 300
                                        easing.type: Easing.BezierSpline
                                        easing.bezierCurve: Motion.spring()   // FORK: was Easing.OutCubic
                                    }
                                }
                                Behavior on color {
                                    ColorAnimation { duration: 300 }
                                }
                            }

                            Row {
                                visible: batteryShape.charging
                                anchors.centerIn: parent
                                anchors.horizontalCenterOffset: root.batteryChargingXOffset
                                anchors.verticalCenterOffset: root.batteryChargingYOffset
                                spacing: Metrics.px(2)
                                z: 2

                                Text {
                                    text: batteryShape.level + ""
                                    color: "black"
                                    font.pixelSize: root.batteryFontSizeCharging
                                    font.family: root.textFontFamily
                                    font.weight: Font.DemiBold
                                    verticalAlignment: Text.AlignVCenter
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                Text {
                                    text: root.chargingIconGlyph
                                    color: IslandTheme.surfaceRaised
                                    font.pixelSize: root.batteryBoltSize
                                    font.family: root.iconFontFamily
                                    verticalAlignment: Text.AlignVCenter
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            Text {
                                visible: !batteryShape.charging
                                anchors.centerIn: parent
                                text: batteryShape.level + ""
                                color: batteryShape.level <= 20 ? "white" : "black"
                                font.pixelSize: root.batteryFontSize
                                font.family: root.textFontFamily
                                font.weight: batteryShape.level <= 20 ? Font.Bold : Font.DemiBold
                                verticalAlignment: Text.AlignVCenter
                                horizontalAlignment: Text.AlignHCenter
                                z: 2
                            }
                        }

                        Rectangle {
                            width: root.batteryTipWidth
                            height: root.batteryTipHeight
                            radius: Math.round(root.batteryTipWidth / 2)
                            color: batteryShape.level >= 100 ? batteryShape.bodyColor : batteryShape.emptyColor
                            anchors.left: batteryBody.right
                            anchors.leftMargin: 1
                            anchors.verticalCenter: parent.verticalCenter

                            Behavior on color {
                                ColorAnimation { duration: 300 }
                            }
                        }
                    }
                }

                Text {
                    id: valueText
                    visible: !parent.isCava && !parent.isBattery
                    anchors.left: leadingVisual.right
                    anchors.leftMargin: parent.hasLeadingVisual && !parent.isBattery ? root.iconSpacing : 0
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.text || ""
                    color: IslandTheme.textPrimary
                    font.pixelSize: root.textPixelSize
                    font.family: root.textFontFamily
                    font.weight: Font.Bold
                    font.letterSpacing: -0.15
                    wrapMode: Text.NoWrap
                }
            }
        }
    }

    RecordingIndicator {
        id: timeRecordingIndicator
        active: root.recordingActive
            && root.showSecondaryText
            && root.timeText !== ""
            && root.clampedProgress < 0.001
        contentOpacity: 1 - root.clampedProgress
        x: root.timeRecordingDotX
        anchors.verticalCenter: parent.verticalCenter
    }

    Text {
        visible: timeText !== "" && showSecondaryText
        x: timeX
        width: textWidth
        anchors.verticalCenter: parent.verticalCenter
        text: timeText
        color: IslandTheme.textPrimary
        opacity: 1 - clampedProgress
        font.pixelSize: root.textPixelSize + 1
        font.family: timeFontFamily
        font.weight: Font.Bold
        font.letterSpacing: -0.25
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        wrapMode: Text.NoWrap
    }
}
