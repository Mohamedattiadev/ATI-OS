pragma ComponentBehavior: Bound

import QtQuick

import "Metrics.js" as Metrics
import "Motion.js" as Motion

//
// PanelTabs — the section switcher, once.
//
// FORK — new file.
//
// WHAT IT REPLACES
// ----------------
// DisplayPanel's four views, AudioPanel's six, and the control centre's
// drawers were each a bare Row of Texts distinguished only by weight and
// colour:
//
//     color:  view === modelData ? textPrimary : textDisabled
//     weight: view === modelData ? DemiBold : Normal
//
// That is a real distinction and it is a weak one. Both of its channels are
// properties of the GLYPHS, so the difference between the selected tab and
// the rest is only visible if you can compare them — and on the panels where
// two tabs have very different word lengths ("outputs" vs "arrange") the
// weight difference reads as a font mismatch rather than as a state.
//
// ---- THE INDICATOR IS AN EDGE, AND THAT IS THE SAME WORD PanelRow USES ----
//
// A sliding underline in the accent. It is the same idea as PanelRow's
// leading bar deliberately: in this shell, an accent EDGE means "you are
// here", and an accent WASH means "this is true of the system". Two shapes,
// two meanings, used the same way on every surface — which is the thing
// twenty separately-styled panels could not have.
//
// It slides rather than cuts because the tabs are walked with Tab and ⇧Tab as
// well as clicked, and a cut gives no cue about WHICH WAY you moved. On a
// four-tab row where Tab wraps from the last to the first, that direction is
// the only thing distinguishing "wrapped around" from "went back one".
//
// Motion.spring() and not fade(): this is geometry, and geometry in this
// shell overshoots slightly. See Motion.js.
//
Item {
    id: root

    // ["outputs", "modes", "layouts", "arrange"], or, where the word on screen
    // is not the word in the code, [{ value: "inputs", label: "mics" },
    // { value: "targets", label: "move to…" }].
    //
    // Both forms in one property rather than a parallel `labels` array: two
    // arrays that must stay the same length and the same order is the
    // `selectedIndex`/`selectedMount` bug with extra steps.
    property var model: []

    function valueOf(entry) {
        return (entry && entry.value !== undefined) ? String(entry.value) : String(entry);
    }

    function labelOf(entry) {
        if (entry && entry.label !== undefined)
            return String(entry.label);
        return (entry && entry.value !== undefined) ? String(entry.value) : String(entry);
    }

    // The selected entry, by value rather than by index — every caller in the
    // tree already stores a `view` string, and an index would make them keep
    // two representations of one fact in sync. That exact bug is written up in
    // the P1-3 audit as `selectedIndex` / `selectedMount`.
    property string current: ""

    property string textFontFamily: ""

    signal tabRequested(string name)

    readonly property real tabSpacing: Metrics.pad(14)
    readonly property real indicatorHeight: Metrics.px(2)

    // ---- WHERE THE INDICATOR IS, PUSHED UP BY THE DELEGATE ----
    //
    // These are written by whichever delegate is current, not read from the
    // Repeater. See the long note above the indicator for why the obvious
    // version silently never draws anything.
    property real indicatorX: 0
    property real indicatorW: 0
    property bool indicatorReady: false

    function _placeIndicator(x, w) {
        root.indicatorX = x;
        root.indicatorW = w;
        root.indicatorReady = w > 0;
    }

    implicitWidth: strip.width
    implicitHeight: strip.height + Metrics.pad(5) + root.indicatorHeight

    Row {
        id: strip
        anchors.left: parent.left
        anchors.top: parent.top
        spacing: root.tabSpacing

        Repeater {
            model: root.model

            delegate: Text {
                id: tab

                required property var modelData
                readonly property string value: root.valueOf(tab.modelData)
                readonly property bool isCurrent: root.current === tab.value

                text: root.labelOf(tab.modelData)
                color: tab.isCurrent ? IslandTheme.textPrimary : IslandTheme.textMuted
                font.family: root.textFontFamily
                font.pixelSize: Metrics.TYPE.body
                // Kept, but no longer load-bearing — the indicator carries the
                // state now and the weight is a supporting cue. textDisabled
                // became textMuted for the same reason: with an indicator
                // present the unselected tabs no longer have to be pushed all
                // the way down to stay out of the way, and textDisabled on the
                // lighter palettes was genuinely hard to read.
                font.weight: tab.isCurrent ? Font.DemiBold : Font.Normal

                // Every input the indicator's position has: which tab is
                // current, where this tab sits once the Row has laid out, and
                // how wide it is once the type has shaped. All three arrive at
                // different times, so all three push.
                onIsCurrentChanged: if (tab.isCurrent) root._placeIndicator(tab.x, tab.width)
                onXChanged: if (tab.isCurrent) root._placeIndicator(tab.x, tab.width)
                onWidthChanged: if (tab.isCurrent) root._placeIndicator(tab.x, tab.width)
                Component.onCompleted: if (tab.isCurrent) root._placeIndicator(tab.x, tab.width)
                // A tab list that SHRINKS — AudioPanel's ports/profiles/cards
                // appear only once something opens them — can destroy the
                // delegate the indicator is sitting under. Nothing else would
                // ever tell it, so it would keep drawing at a stale x.
                Component.onDestruction: if (tab.isCurrent) root.indicatorReady = false

                Behavior on color {
                    ColorAnimation {
                        duration: Motion.fadeInDuration()
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Motion.fade()
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    // A little slack so a 11 px word is not a 11 px target.
                    anchors.topMargin: -Metrics.pad(4)
                    anchors.bottomMargin: -Metrics.pad(6)

                    // ---- A TAB IS CLICKED, NOT HOVERED, AND THAT IS NOT AN
                    //      EXCEPTION TO "HOVER MOVES THE CURSOR" ----
                    //
                    // The rule that rule encodes is that BROWSING is free:
                    // moving a row cursor has no side effect, so the pointer
                    // and the keyboard can drive the same indicator. Entering
                    // a tab is not browsing. It replaces the panel's whole
                    // body and resets the row selection underneath it, so
                    // dragging the pointer across the header on its way
                    // somewhere else would flip AudioPanel through four views
                    // and land the cursor somewhere it was not.
                    //
                    // Same shape of reasoning as the workspace overview, where
                    // an arrow COMMITS rather than browses: what the action
                    // costs decides how it is reached, not a blanket rule.
                    onClicked: root.tabRequested(tab.value)
                }
            }
        }
    }

    // ---- WHY THE DELEGATE PUSHES AND THE INDICATOR DOES NOT PULL ----
    //
    // The obvious version of this is a binding that looks the delegate up:
    //
    //     readonly property Item target: repeater.itemAt(indexOfCurrent)
    //     x: target ? target.x : 0
    //
    // It was written that way first, and it drew NOTHING — no error, no
    // warning, a correct-looking file and a permanently invisible indicator,
    // caught only by capturing the component and zooming into the tab row.
    //
    // `Repeater.itemAt()` is a FUNCTION, not a bindable property. QML records
    // no dependency on it, so the binding evaluates exactly once — at
    // construction, when the Repeater has not built its delegates yet — gets
    // null, and is never re-evaluated for the rest of the process. It is the
    // same shape of bug as the panels whose Keys handlers never fired: the
    // code is right about what it wants and wrong about when it runs.
    //
    // So the delegate pushes instead. That is reactive to all three inputs
    // that can move the indicator — the current tab changing, the Row laying
    // out, and the text re-shaping when the user's font family or size changes
    // — and none of them depends on a lookup happening at the right moment.
    Rectangle {
        id: indicator

        x: root.indicatorX
        width: root.indicatorW
        y: strip.height + Metrics.pad(5)
        height: root.indicatorHeight
        radius: height / 2
        color: IslandTheme.accent
        opacity: root.indicatorReady ? 1 : 0

        Behavior on x {
            NumberAnimation {
                duration: Motion.controlDuration()
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Motion.spring()
            }
        }

        Behavior on width {
            NumberAnimation {
                duration: Motion.controlDuration()
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Motion.spring()
            }
        }
    }
}
