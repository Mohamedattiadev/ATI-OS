pragma ComponentBehavior: Bound

import QtQuick

import "Metrics.js" as Metrics
import "Motion.js" as Motion

//
// PanelChrome — header, rules, tabs and footer. Once, for twenty panels.
//
// FORK — new file. This is P2-7 and the restyle in one piece, and they are
// one piece on purpose: extracting the chrome is the only moment at which
// changing the look is a four-file edit instead of a twenty-file one. Doing
// the extraction first and the restyle after would mean deciding the same
// question twenty times again, which is precisely how the spread below was
// produced in the first place.
//
// WHAT WAS THERE BEFORE, COUNTED
// ------------------------------
//     the key-hint footer   9 panels, TWO property names
//                           (`hintHeight` x5, `footerHeight` x4),
//                           FOUR heights (pad(26), px(22), px(20), raw 24),
//                           TWO colours (textDisabled, textMuted),
//                           THREE bottom margins (pad(8), pad(10), raw 10)
//     the header height     pad(34) x6, pad(36) x2, pad(38) x1, raw 34 x1
//     the content inset     pad(18) x9, raw 18 x1
//
// Nobody decided any of that. It is one question answered nine separate
// times by nine files that could not see each other.
//
// ---- THE HEADER REGISTER: ONE OF TWO, AND THIS IS WHY IT IS THIS ONE ----
//
// The tree had two, cleanly split:
//
//   A. hero      heroFontFamily, font(15), DemiBold, letterSpacing -0.2,
//                `color: "white"`   — Audio, Settings, Calendar, Power,
//                                     Display
//   B. instrument textFontFamily, font(10), DemiBold, AllUppercase,
//                letterSpacing 1.6, textMuted, then a "· status" clause that
//                carries the accent only when something is live
//                                   — Wi-Fi, Bluetooth, System monitor
//
// B wins, for three reasons that are not taste:
//
//   1. It leaves the top-left free. The control centre's header is a HERO
//      NUMBER — the battery percentage — and register A puts a window title
//      exactly where that number wants to be. Only B composes with a panel
//      whose header is its own content.
//   2. Register A's colour is the literal `"white"`. There are 29 of those
//      across 19 files, and on `mono-light` — the one palette of 21 whose
//      surface lands on the light side of IslandTheme's 0.18 threshold —
//      white is the WRONG ink. The header of five panels is unreadable on
//      that theme today. Moving to a role fixes it by construction.
//   3. It already carries a second channel. The "· SSID", "· 3 devices",
//      "· off" clause is a fact about the panel's subject, accented only
//      when there is something live to point at, and no register-A panel
//      has anywhere to put that.
//
// A title you have to read is a title doing no work: every one of these
// panels is opened by its own chord, so you always know which one you asked
// for. The label is confirmation, and confirmation belongs at 10 px.
//
// ---- THE TWO RULES ----
//
// A hairline under the header and a hairline over the footer. Nothing in the
// tree had either — the header simply floated above the body and the hints
// floated below it — and they are the cheapest thing on this list that makes
// twenty surfaces read as one system: 1 px, no layout cost, and they define
// the body as a REGION rather than as whatever is left over.
//
// They are inset by the content padding rather than full-bleed. A rule that
// touches the capsule's inner edge makes the content look like it is falling
// out of the shell; one that stops short of it reads as a rule ON the panel.
//
Item {
    id: root

    // --- the header -------------------------------------------------------

    // "WI-FI", "AUDIO", "DISPLAY". Rendered uppercase, so callers write it in
    // whatever case reads best in source.
    property string title: ""

    // The "· SSID" / "· 3 paired" clause. Callers include their own leading
    // separator, because some of them want "· off" and some want a bare count.
    property string statusClause: ""

    // Is the clause pointing at something live? Accent if so, muted if not —
    // a status clause that is ALWAYS accented has stopped being a status.
    property bool statusClauseLive: false

    // The right-hand slot: what the panel is doing right now, in the colour of
    // how it went. Audio, Wi-Fi, Bluetooth and Display all had this in the
    // same corner already; it is promoted rather than invented.
    property string status: ""
    property string statusLevel: "idle"        // idle | busy | ok | error

    // --- the tabs ---------------------------------------------------------

    property var tabs: []
    property string currentTab: ""
    signal tabRequested(string name)

    // --- the footer -------------------------------------------------------

    // [{ key: "j/k", label: "move" }, …]. See KeyHint for why it is a list.
    property var hints: []

    // --- shared ------------------------------------------------------------

    property string textFontFamily: ""

    // Off in the island, on when a panel is rendered standalone — the same
    // `drawBackground` every fork panel already carried, moved here so the
    // capsule's radius is written once.
    property bool drawBackground: false
    property color panelFill: IslandTheme.surface

    // ---- GEOMETRY THE CALLER ANCHORS ITS BODY TO ----
    //
    // Exposed as numbers rather than as a content Item the body must be
    // reparented into. Nine panels position their bodies with `x:` and `y:`
    // against their own `headerHeight`, and rewriting all of that into anchors
    // inside a container is a large diff whose only verification is "it still
    // looks right" — the class of change this repo has twice been burned by.
    // Reading four numbers from here instead is a one-line change per panel
    // and puts the same four numbers in every one of them.
    readonly property real padX: Metrics.chromePadX()
    readonly property real headerHeight: Metrics.chromeHeader()
    readonly property real tabsHeight: (root.tabs && root.tabs.length > 0)
        ? tabStrip.implicitHeight + Metrics.pad(6) : 0
    readonly property real footerHeight: Metrics.chromeFooter()
    readonly property real gap: Metrics.chromeGap()

    // Everything the chrome costs vertically. A caller's preferredHeight is
    // `chrome.chromeHeight + bodyHeight` and nothing else.
    readonly property real chromeHeight:
        root.headerHeight + root.tabsHeight + root.gap + root.footerHeight

    readonly property real contentX: root.padX
    readonly property real contentY: root.headerHeight + root.tabsHeight
    readonly property real contentWidth: Math.max(0, root.width - root.padX * 2)
    readonly property real contentHeight:
        Math.max(0, root.height - root.contentY - root.gap - root.footerHeight)

    // ---- A CALLER MAY REPLACE THE HEADER ENTIRELY ----
    //
    // The control centre's header is the battery percentage at DISPLAY.large
    // with a charge state beside it, not a title. Rather than bolt a "hero
    // mode" onto the title row, a caller can drop its own item in here and
    // keep the rules, the tabs, the footer and every one of the four geometry
    // numbers. `headerReplaced` is derived from the slot having children, so
    // there is no second flag to keep in sync with it.
    default property alias headerContent: headerSlot.data
    readonly property bool headerReplaced: headerSlot.children.length > 0

    anchors.fill: parent

    // The capsule. See panelFill — off in the island, kept so a panel renders
    // standalone. px(28) is the island's own shape and is deliberately NOT
    // Metrics.RADIUS.panel: the RADIUS table describes surfaces INSIDE a
    // panel, and the capsule belongs to the island.
    Rectangle {
        anchors.fill: parent
        radius: Metrics.px(28)
        color: root.panelFill
        opacity: 0.97
        visible: root.drawBackground
    }

    Item {
        id: headerSlot
        x: root.padX
        y: 0
        width: root.width - root.padX * 2
        height: root.headerHeight
        visible: root.headerReplaced
    }

    // --- the standard header row -------------------------------------------

    Text {
        id: titleText
        x: root.padX
        y: Metrics.chromeTop()
        visible: !root.headerReplaced
        text: root.title
        color: IslandTheme.textMuted
        font.family: root.textFontFamily
        font.pixelSize: Metrics.TYPE.small
        font.weight: Font.DemiBold
        font.capitalization: Font.AllUppercase
        font.letterSpacing: 1.6
    }

    Text {
        id: clauseText
        anchors.left: titleText.right
        anchors.leftMargin: Metrics.pad(8)
        y: Metrics.chromeTop()
        visible: !root.headerReplaced && root.statusClause.length > 0
        text: root.statusClause
        color: root.statusClauseLive ? IslandTheme.accent : IslandTheme.textMuted
        font.family: root.textFontFamily
        font.pixelSize: Metrics.TYPE.small
        font.weight: Font.Medium
        elide: Text.ElideRight
        width: Math.min(implicitWidth, root.width * 0.35)

        Behavior on color {
            ColorAnimation {
                duration: Motion.fadeInDuration()
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Motion.fade()
            }
        }
    }

    Text {
        id: statusText
        anchors.right: parent.right
        anchors.rightMargin: root.padX
        y: Metrics.chromeTop()
        visible: root.status.length > 0
        width: Math.min(implicitWidth, root.width * 0.45)
        horizontalAlignment: Text.AlignRight
        elide: Text.ElideRight
        text: root.status
        font.family: root.textFontFamily
        font.pixelSize: Metrics.TYPE.body
        color: root.statusLevel === "error" ? IslandTheme.danger
             : (root.statusLevel === "ok" ? IslandTheme.success
             : (root.statusLevel === "busy" ? IslandTheme.warning
             : IslandTheme.textMuted))
    }

    // --- tabs ---------------------------------------------------------------

    PanelTabs {
        id: tabStrip
        x: root.padX
        y: root.headerHeight - Metrics.pad(2)
        visible: root.tabs && root.tabs.length > 0
        model: root.tabs
        current: root.currentTab
        textFontFamily: root.textFontFamily
        onTabRequested: name => root.tabRequested(name)
    }

    // --- the two rules -------------------------------------------------------

    Rectangle {
        id: headerRule
        x: root.padX
        y: root.contentY - Metrics.pad(4)
        width: root.contentWidth
        height: Metrics.RADIUS.hairline
        color: IslandTheme.hairline
        // A rule under a tab strip would sit directly beneath the tab
        // indicator and read as a second, permanently-full indicator. The
        // strip's own baseline is already the separator there.
        visible: !(root.tabs && root.tabs.length > 0)
    }

    Rectangle {
        x: root.padX
        y: root.height - root.footerHeight
        width: root.contentWidth
        height: Metrics.RADIUS.hairline
        color: IslandTheme.hairline
    }

    // --- the footer ----------------------------------------------------------

    KeyHint {
        x: root.padX
        y: root.height - root.footerHeight
        width: root.contentWidth
        height: root.footerHeight
        hints: root.hints
        textFontFamily: root.textFontFamily
    }
}
