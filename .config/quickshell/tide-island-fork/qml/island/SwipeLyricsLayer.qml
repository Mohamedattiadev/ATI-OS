import QtQuick
import Qt5Compat.GraphicalEffects
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

    property string lyricText: ""
    property string currentArtUrl: ""
    property var cavaLevels: []
    property string timeText: ""
    property var configSource: null
    readonly property var activeConfig: configSource || userConfig
    property string textFontFamily: activeConfig.textFontFamily
    property string timeFontFamily: activeConfig.timeFontFamily
    property bool showCondition: false
    property bool showSecondaryText: true
    // FORK: whether sound is actually coming out right now, not whether a
    // player exists. Gates the resting EQ — see restingEq below.
    property bool musicPlaying: false
    property bool recordingActive: false
    property real transitionProgress: 0
    property int textPixelSize: userConfig.bodyFontSize
    // FORK: the workspace digit is CONTENT OF THIS LAYER now, not an overlay.
    //
    // It began life as a sibling of mainCapsule positioned by absolute x over
    // the capsule (see the deleted WorkspaceChip wiring in
    // DynamicIslandWindow.qml). That worked for exactly one state and broke in
    // every other, because an absolutely-placed overlay knows nothing about
    // the layers crossfading underneath it — swiping to lyrics or to the
    // custom card left the digit sitting on top of whatever had replaced the
    // clock. The workaround was a four-clause `visible` gate naming every
    // state it must not appear in, and that gate was recorded at the time as a
    // workaround rather than a fix.
    //
    // This is the fix. The digit is laid out beside the clock, in the clock's
    // own layer, so it inherits the clock's entire life cycle for free:
    // it fades on `1 - clampedProgress` with the time text on a lyrics swipe,
    // it is unloaded with this whole layer on a left swipe (lyricsSwipeVisible
    // goes false the moment swipeTransitionProgress does), and it disappears
    // for the workspace popup because showSecondaryText already does.
    property int workspaceId: 1
    property bool workspaceShown: false
    property color accentColor: IslandTheme.accent

    // FORK: the layout indicator — qtile's CurrentLayout widget, which the
    // island has never had. Same argument as the workspace digit above and
    // the same seam: a glyph handed down rather than a state this layer
    // fetches, so the layer draws and the shell decides. Empty string means
    // "nothing to say" and draws nothing at all — see LayoutState.known.
    property string layoutGlyph: ""
    property bool layoutShown: false
    property string iconFontFamily: ""

    property real minimumWidth: Metrics.px(220)
    property real maximumWidth: minimumWidth
    property real horizontalPadding: Metrics.pad(14)
    property real coverSize: Metrics.px(24)
    property real coverRadius: Metrics.px(7)
    property real visualSpacing: Metrics.px(35)
    property real hiddenLeftPadding: Metrics.pad(18)
    property real hiddenRightPadding: Metrics.pad(16)
    property string activeLyricText: lyricText
    property string previousLyricText: ""
    property real lyricChangeProgress: 1
    property int recordingDotSpacing: 12

    // Gap between the clock and the resting EQ, and the total the collapsed
    // capsule has to grow by to fit it. Exported so DynamicIslandWindow can
    // widen the capsule on the same spring rather than clipping the bars.
    readonly property real restingEqGap: 7
    readonly property real restingEqWidth: 4 * 3 + 3 * 3
    readonly property real restingEqAllowance: restingEqWidth + restingEqGap

    // The same two numbers for the workspace digit. They are deliberately
    // IDENTICAL to root.restingWorkspaceAllowance in DynamicIslandWindow.qml,
    // which is what the collapsed capsule actually grows by — restingEq
    // already duplicates its allowance the same way, with the same
    // cross-reference, because the capsule has to know the width without
    // instantiating this component to ask it.
    //
    // FIXED and not measured off the glyph, unlike the EQ's placement which
    // reads visibleTimeWidth. A width derived from the digit's own ink would
    // change when you move from workspace 9 to workspace 10, and since the
    // capsule sizes itself from this number, the capsule would MORPH on a
    // workspace switch — a shape change caused by a text change, which is the
    // opposite of everything else in this shell. Two tabular figures at 13 px
    // DemiBold fit inside the slot; a third would clip, and a machine with
    // 100 workspaces has other problems.
    readonly property real restingWorkspaceGap: Metrics.px(12)
    readonly property real restingWorkspaceWidth: Metrics.px(10)
    readonly property real restingWorkspaceAllowance:
        restingWorkspaceWidth + restingWorkspaceGap
    readonly property bool workspaceVisible:
        workspaceShown && showSecondaryText && timeText !== ""

    // The same two numbers again for the layout glyph, and deliberately a
    // FIXED slot width for the same reason the digit has one: the capsule
    // sizes itself from this sum, so a width taken from the glyph's own ink
    // would morph the capsule whenever the layout changed. A square, a
    // columns pair and a list do not have identical advance widths.
    //
    // ---- IT LEADS THE CLOCK, IT DOES NOT TRAIL IT ----
    //
    // User-directed, and it also happens to be the better reading. The digit
    // and the EQ both QUALIFY the clock — which workspace, what is playing —
    // and the digit's own note argues they trail it because "the clock is the
    // subject and the workspace qualifies it, so it reads as a suffix". The
    // layout is not a qualifier of the time at all; it is a property of the
    // whole session. Putting it on the far side keeps the clock's suffixes
    // together and stops a third trailing item turning the group into a row
    // of four.
    //
    // The gap is smaller than the workspace gap because this one binds to the
    // capsule's left edge rather than to a neighbour.
    readonly property real restingLayoutGap: Metrics.px(7)
    readonly property real restingLayoutWidth: Metrics.px(12)
    readonly property real restingLayoutAllowance:
        restingLayoutWidth + restingLayoutGap
    readonly property bool layoutVisible:
        layoutShown && layoutGlyph !== "" && showSecondaryText && timeText !== ""

    // The clock and the EQ are one centred group, so the clock slides left
    // by half the allowance when the bars appear rather than staying put
    // and letting the pair sit off-centre. Animated on its own short curve
    // because it is content shifting inside the capsule, not the capsule
    // moving — those two settling at different times is what makes the
    // bars look bolted on.
    //
    // FORK: the digit is a second trailing occupant of that same group, so it
    // enters the same sum rather than getting a shift of its own. Both sit to
    // the RIGHT of the clock's ink — the digit first, then the bars — so the
    // group's total trailing width is the sum of the two allowances and the
    // clock slides left by half of it. Trailing and not leading was decided
    // in 4a0e2ac and is kept: the clock is the subject and the workspace
    // qualifies it, so it reads as a suffix rather than as a heading.
    readonly property real restingTrailingAllowance:
        ((musicPlaying && showSecondaryText) ? restingEqAllowance : 0)
        + (workspaceVisible ? restingWorkspaceAllowance : 0)

    // FORK: the layout glyph LEADS the clock, so it is the first thing this
    // group has ever had on that side. Order left to right is now
    // glyph · clock · digit · EQ.
    readonly property real restingLeadingAllowance:
        layoutVisible ? restingLayoutAllowance : 0

    // ---- WHY THIS IS A DIFFERENCE AND NOT A SUM ----
    //
    // The shift exists to keep the whole cluster optically centred in the
    // capsule: the clock slides LEFT by half of whatever hangs off its right,
    // so the pair reads as centred rather than as a clock sitting dead centre
    // with things bolted to one side.
    //
    // A leading occupant pushes the other way, so it SUBTRACTS. Adding it —
    // the obvious edit — would slide the clock left to make room for
    // something that is already to its left, moving the group off centre by
    // the full width of the glyph and in the wrong direction. When both are
    // present the shifts partly cancel, which is correct: the group is more
    // nearly symmetric than it was, so it needs less correction, not more.
    readonly property real restingGroupShift:
        (restingTrailingAllowance - restingLeadingAllowance) / 2

    readonly property real clampedProgress: Math.max(0, Math.min(1, transitionProgress))
    readonly property bool lyricMostlyVisible: clampedProgress > 0.92
    readonly property real textWidth: Math.max(0, width - horizontalPadding * 2)
    readonly property real lyricTextWidth: Math.max(
        0,
        textWidth - coverSize - cavaBars.implicitWidth - visualSpacing * 2
    )
    readonly property real centeredX: horizontalPadding
    readonly property real lyricHiddenLeftX: -textWidth - hiddenLeftPadding
    readonly property real timeHiddenRightX: width + hiddenRightPadding
    readonly property real lyricEntryDistance: Math.max(0, centeredX - lyricHiddenLeftX)
    readonly property real timeExitDistance: Math.max(0, timeHiddenRightX - centeredX)
    readonly property real dragDistance: Math.max(lyricEntryDistance, timeExitDistance)
    readonly property real lyricX: centeredX - (1 - clampedProgress) * dragDistance
    readonly property real timeX: centeredX + clampedProgress * dragDistance
    property real animatedGroupShift: restingGroupShift
    readonly property real shiftedTimeX: timeX - animatedGroupShift

    // The right-hand edge of the clock's ACTUAL INK, not of its full-width
    // centred box. Everything that trails the clock hangs off this, so the
    // group reads as one centred cluster instead of three things scattered
    // across a 220 px box. Was inlined in restingEq's x; pulled out because
    // the digit now needs the same origin and two copies of this expression
    // drifting apart is how the bars ended up misplaced once already.
    readonly property real restingInkRight:
        shiftedTimeX + (textWidth + visibleTimeWidth) / 2

    // The other edge of the same ink, for the one thing that leads the clock.
    // Same construction, minus instead of plus: the time Text is a full-width
    // centred box, so its visible ink starts half the slack in from the box's
    // left edge. Derived rather than measured off the glyph's neighbours so
    // it cannot drift from restingInkRight above.
    readonly property real restingInkLeft:
        shiftedTimeX + (textWidth - visibleTimeWidth) / 2

    Behavior on animatedGroupShift {
        NumberAnimation {
            duration: 180
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Motion.spring()   // FORK: was Easing.InOutQuad
        }
    }
    readonly property real lyricBaselineY: lyricBaselineGuide.y + lyricBaselineGuide.baselineOffset
    readonly property real timeBaselineY: timeBaselineGuide.y + timeBaselineGuide.baselineOffset
    readonly property real visibleLyricWidth: Math.min(lyricTextWidth, Math.max(0, lyricMetrics.advanceWidth))
    readonly property real visibleTimeWidth: Math.min(textWidth, Math.max(0, timeMetrics.advanceWidth))
    readonly property real timeRecordingDotX: Math.max(
        4,
        timeX + (textWidth - visibleTimeWidth) / 2 - recordingDotSpacing - timeRecordingIndicator.width
    )
    readonly property real preferredWidth: Math.max(
        minimumWidth,
        Math.min(
            Math.max(minimumWidth, maximumWidth),
            lyricMetrics.advanceWidth
                + horizontalPadding * 2
                + coverSize
                + cavaBars.implicitWidth
                + visualSpacing * 2
        )
    )

    onLyricTextChanged: {
        if (lyricText === activeLyricText) return;

        if (activeLyricText === "" || !lyricMostlyVisible) {
            lyricChangeAnimation.stop();
            previousLyricText = "";
            activeLyricText = lyricText;
            lyricChangeProgress = 1;
            return;
        }

        previousLyricText = activeLyricText;
        activeLyricText = lyricText;
        lyricChangeProgress = 0;
        lyricChangeAnimation.restart();
    }

    onShowConditionChanged: {
        if (showCondition) return;
        lyricChangeAnimation.stop();
        previousLyricText = "";
        activeLyricText = lyricText;
        lyricChangeProgress = 1;
    }

    onTransitionProgressChanged: {
        if (lyricMostlyVisible) return;
        lyricChangeAnimation.stop();
        previousLyricText = "";
        activeLyricText = lyricText;
        lyricChangeProgress = 1;
    }

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
        id: lyricMetrics
        font.family: textFontFamily
        font.pixelSize: textPixelSize
        font.weight: Font.DemiBold
        text: activeLyricText !== "" ? activeLyricText : lyricText
    }

    TextMetrics {
        id: timeMetrics
        font.family: timeFontFamily
        font.pixelSize: textPixelSize + 1
        font.weight: Font.Bold
        text: timeText
    }

    Text {
        id: lyricBaselineGuide
        anchors.verticalCenter: parent.verticalCenter
        text: "Ag国"
        opacity: 0
        font.pixelSize: textPixelSize
        font.family: textFontFamily
        font.weight: Font.DemiBold
        font.letterSpacing: -0.15
        wrapMode: Text.NoWrap
    }

    Text {
        id: timeBaselineGuide
        anchors.verticalCenter: parent.verticalCenter
        text: "00:00"
        opacity: 0
        font.pixelSize: textPixelSize + 1
        font.family: timeFontFamily
        font.weight: Font.Bold
        font.letterSpacing: -0.25
        wrapMode: Text.NoWrap
    }

    SequentialAnimation {
        id: lyricChangeAnimation

        NumberAnimation {
            target: root
            property: "lyricChangeProgress"
            from: 0
            to: 1
            duration: 260
            // Drives a CROSSFADE between two lyric lines, so it is opacity in
            // all but name and must not overshoot: past 1 the outgoing line
            // has already been discarded and the incoming one clips flat.
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Motion.fade()   // FORK: was Easing.OutCubic
        }

        ScriptAction {
            script: root.previousLyricText = ""
        }
    }

    Item {
        id: lyricContent

        x: root.lyricX
        width: root.textWidth
        height: parent.height
        opacity: root.clampedProgress

        Rectangle {
            id: coverFrame

            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: root.coverSize
            height: root.coverSize
            radius: root.coverRadius
            color: IslandTheme.surfaceRaised
            antialiasing: true

            Rectangle {
                id: coverMask

                anchors.fill: parent
                radius: root.coverRadius
                antialiasing: true
                visible: false
                layer.enabled: true
            }

            Image {
                anchors.fill: parent
                source: root.currentArtUrl
                fillMode: Image.PreserveAspectCrop
                visible: source.toString() !== ""
                sourceSize: Qt.size(root.coverSize * 2, root.coverSize * 2)
                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: coverMask
                }
            }
        }

        Item {
            id: lyricViewport

            anchors.left: coverFrame.right
            anchors.leftMargin: root.visualSpacing
            anchors.right: cavaBars.left
            anchors.rightMargin: root.visualSpacing
            height: parent.height
            clip: true

            Text {
                visible: root.previousLyricText !== ""
                y: root.lyricBaselineY - baselineOffset - 14 * root.lyricChangeProgress
                width: parent.width
                text: root.previousLyricText
                color: "white"
                opacity: 1 - root.lyricChangeProgress
                font.pixelSize: root.textPixelSize
                font.family: root.textFontFamily
                font.weight: Font.DemiBold
                font.letterSpacing: -0.15
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                wrapMode: Text.NoWrap
            }

            Text {
                visible: root.activeLyricText !== ""
                y: root.lyricBaselineY - baselineOffset
                    + (root.previousLyricText !== "" ? 12 * (1 - root.lyricChangeProgress) : 0)
                width: parent.width
                text: root.activeLyricText
                color: "white"
                opacity: root.previousLyricText !== "" ? root.lyricChangeProgress : 1
                font.pixelSize: root.textPixelSize
                font.family: root.textFontFamily
                font.weight: Font.DemiBold
                font.letterSpacing: -0.15
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                wrapMode: Text.NoWrap
            }
        }

        SwipeCavaBars {
            id: cavaBars

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            levels: root.cavaLevels
            barCount: 5
            barWidth: Metrics.px(3)
            barSpacing: Metrics.px(3)
            minimumBarHeight: Metrics.px(4)
            barColor: "white"
        }
    }

    Text {
        visible: timeText !== "" && showSecondaryText
        x: shiftedTimeX
        y: timeBaselineY - baselineOffset
        width: textWidth
        text: timeText
        color: "white"
        opacity: 1 - clampedProgress
        font.pixelSize: textPixelSize + 1
        font.family: timeFontFamily
        font.weight: Font.Bold
        font.letterSpacing: -0.25
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        wrapMode: Text.NoWrap
    }

    // FORK: the workspace digit, laid out with the clock rather than floated
    // over it. See the property block at the top of this file for why it moved
    // here; this is the drawing half.
    //
    // Everything about how it LOOKS was settled while it was still
    // WorkspaceChip.qml and is carried over unchanged: plain type and not a
    // ring, because a ring's dark disc was IslandTheme.shellFill and is
    // therefore invisible against the capsule made of the same material; one
    // step under the clock's size, because two numbers at the same size beside
    // each other read as one value split in half; the accent, because nothing
    // else in the resting capsule is accent-coloured and that alone says "this
    // is live"; tabular figures, so a 1 and an 8 occupy the same width and the
    // clock does not shuffle sideways on a workspace change.
    //
    // What is NEW is that it has no life cycle of its own. No Behavior on
    // opacity, no reveal progress, no visibility gate naming island states:
    //
    //   * `1 - clampedProgress` is the identical expression the time text
    //     uses, so a lyrics swipe carries the two off together. This is the
    //     whole point of the move — the digit cannot outlive the clock,
    //     because it is drawn by the same thing on the same term.
    //   * autoHide is already applied to mainCapsule's own opacity, so the old
    //     `revealProgress: root.autoHideProgress` was a second, redundant
    //     multiplier on a value the parent had already faded.
    //   * showSecondaryText is false whenever the workspace popup or the split
    //     view owns this side, which covers the popup case the old gate
    //     handled explicitly: the popup says the workspace in words, and
    //     showing the digit at the same moment states one fact twice.
    Text {
        id: workspaceDigit

        visible: root.workspaceVisible
        // Left edge of the slot, which starts one gap past the clock's ink.
        // The glyph is centred in the slot rather than left-aligned in it, so
        // a two-digit workspace grows symmetrically and does not walk into the
        // EQ.
        x: root.restingInkRight + root.restingWorkspaceGap
            + (root.restingWorkspaceWidth - width) / 2
        y: root.timeBaselineY - baselineOffset
        opacity: 1 - root.clampedProgress

        text: String(root.workspaceId)
        color: root.accentColor
        font.pixelSize: Metrics.font(13)
        font.family: root.textFontFamily
        font.weight: Font.DemiBold
        font.features: ({ "tnum": 1 })
    }

    // FORK: the layout indicator. qtile's bar had a CurrentLayout widget and
    // this shell has never had one; hypr/scripts/layout-cycle.sh says so in
    // its own comment and its transient showText popup was the stand-in.
    //
    // It sits here, in the clock's layer, for the same reason the digit was
    // moved here rather than left as a floating sibling: it inherits the
    // clock's whole life cycle instead of needing a gate that names every
    // island state it must not appear in. Same `1 - clampedProgress`, so a
    // lyrics swipe carries clock, digit and glyph off together.
    //
    // ---- WHY MUTED AND NOT THE ACCENT ----
    //
    // The digit's own note says it is accent-coloured "because nothing else
    // in the resting capsule is accent-coloured and that alone says 'this is
    // live'". A second accent element spends exactly that. These two are also
    // not equals: the workspace is where you ARE and changes constantly; the
    // layout is how this workspace is arranged and changes rarely. Muted ink
    // puts the glyph a step behind the digit, which is the true relationship
    // and keeps the digit's accent doing the job it was chosen for.
    Text {
        id: layoutGlyphText

        visible: root.layoutVisible
        // LEADS the clock: one gap to the left of the clock's ink, with the
        // glyph centred in its fixed slot so the three different glyph widths
        // all sit on the same centre line and none of them walks into the
        // clock. Hung off restingInkLeft — the ink, not the box — for the
        // reason everything trailing hangs off restingInkRight: the time Text
        // is a 220 px centred box and its left edge is nowhere near its
        // first digit.
        x: root.restingInkLeft - root.restingLayoutGap - root.restingLayoutWidth
            + (root.restingLayoutWidth - width) / 2
        // Centred on the DIGIT's box, not sat on the clock's baseline. A Nerd
        // Font box glyph has no descender and nearly fills its em, so sharing
        // the digits' baseline hangs it visibly low beside them. Expressed
        // against workspaceDigit rather than as an offset from timeBaselineY
        // so the two cannot drift apart if either font size is ever changed;
        // an invisible Item still has valid geometry, so this holds when the
        // digit is hidden.
        y: workspaceDigit.y + (workspaceDigit.height - height) / 2
        opacity: 1 - root.clampedProgress

        text: root.layoutGlyph
        color: IslandTheme.textMuted
        // The icon font, not the text font. These are Nerd Font private-use
        // codepoints: in the text font they are not "wrong looking", they are
        // absent, and fontconfig substitutes silently — which in this tree has
        // already meant a family resolving to Noto Sans CJK with nothing in
        // any log to say so.
        font.family: root.iconFontFamily
        font.pixelSize: Metrics.font(11)
    }

    // FORK: the resting-state EQ. DESIGN-SPEC.md's resting island shows
    // exactly two things — "the time, and a 4-bar EQ visualiser that
    // animates only while music actually plays".
    //
    // Upstream already draws cava bars, but only inside the lyrics row,
    // which lives at clampedProgress 1 — i.e. only after you swipe. At
    // rest that row is fully transparent and all you get is the clock.
    // This is a second, smaller instance that lives on the clock's side of
    // the crossfade instead: its opacity is 1 - clampedProgress, exactly
    // like the time text, so swiping to lyrics hands the EQ over to the
    // big one rather than showing two.
    //
    // Four bars, not upstream's five, because the spec says four and
    // because the collapsed capsule is 96 px wide on this panel — the
    // fifth bar costs 6 px that the clock needs.
    //
    // "Animates only while music plays" is taken literally: with nothing
    // playing the bars are not idling at their minimum height, they are
    // gone, and the capsule is just a clock. cavaLevels stays pinned at
    // zero unless the cava module is present, so a flat row of dots would
    // have been the permanent state on a machine without it — a
    // decoration that never moves, which is the exact trade the spec
    // deletes battery and Wi-Fi for.
    SwipeCavaBars {
        id: restingEq
        levels: root.cavaLevels
        barCount: 4
        barWidth: Metrics.px(3)
        barSpacing: Metrics.px(3)
        minimumBarHeight: Metrics.px(3)
        barColor: "white"
        height: Metrics.px(14)

        readonly property bool shown: root.musicPlaying && root.showSecondaryText

        anchors.verticalCenter: parent.verticalCenter
        // Sits just right of the clock's own ink, not of its full-width
        // centred box, so the pair reads as one centred group — and now to
        // the right of the workspace digit as well when that is showing, so
        // the two trailing occupants queue rather than overlap.
        x: root.restingInkRight
            + (root.workspaceVisible ? root.restingWorkspaceAllowance : 0)
            + root.restingEqGap
        opacity: shown ? (1 - root.clampedProgress) : 0
        visible: opacity > 0.001

        Behavior on opacity {
            NumberAnimation {
                duration: 180
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Motion.fade()   // FORK: was Easing.InOutQuad
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
}
