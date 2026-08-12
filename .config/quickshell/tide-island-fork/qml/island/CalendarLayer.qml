pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

// FORK: the shared scale factor — see qml/common/Metrics.js.
import "../common/Metrics.js" as Metrics
// FORK: the shared motion system — one spring for geometry, one
// critically damped curve for opacity. See qml/common/Motion.js.
import "../common/Motion.js" as Motion
import "../common"

//
// FORK — new file. The CALENDAR, which DESIGN-SPEC.md lists as one of the
// island's states ("launcher · control center · calendar · power menu ·
// Polkit password prompt · wallpaper picker · theme switcher") and which
// upstream Tide Island does not have in any form.
//
// THIS ONE HAS NO ANCESTOR, AND THAT CHANGES HOW IT WAS BUILT
// -----------------------------------------------------------
// Every other panel in this fork is a port with something to be measured
// against: the display panel had qtile's DisplayPopup and its 28 bindings,
// the audio panel had AudioPopup's 25, the Wi-Fi QR had popups/WifiQR.py.
// qtile has `widget.Clock` and nothing else — no calendar popup, no
// calendar widget, no chord. Checked before writing anything:
//
//     grep -rin "calendar\|cal_popup\|khal\|calcurse" ../qtile/config.py
//                ../qtile/popups/ ../qtile/scripts/     -> no hits
//
// So there is nothing to be faithful TO here, and the risk is the opposite
// of the usual one: with no ancestor to constrain it, a calendar grows an
// agenda, a week view, a year view and a settings page. The spec's own rule
// about the resting state is the one applied instead — "subtraction as a
// feature", the thing that "earned permanent screen real estate by being
// occasionally relevant" being a bad trade. One month, the days, today, and
// the days you have something on. Nothing else.
//
// WHAT THE SPEC DOES SAY, AND WHAT IT IS RELATED TO
// -------------------------------------------------
// The nearest existing relative is the media card's "date carousel
// top-right (inspired by the Notcho Mac app)" — the one place the spec puts
// a date in the island. That is a carousel of *upcoming* days, not a grid,
// and it is a decoration on a card about something else. It is the reason
// the header here leads with the long-form day ("Wednesday · 12 August
// 2026") rather than with a bare "August 2026": a date in this shell has so
// far always been the human-readable one, and a month header alone would be
// the first place it was not.
//
// THE DOTS ARE NOT DECORATION
// ---------------------------
// A calendar with no data on it is a worse `date`. The one dated store this
// machine already has is `~/ATITODOS/TODOS.md`, and `clock_popup` ($alt P,
// a live qtile port) already parses exactly the same syntax out of exactly
// the same file:
//
//     awk '/- \[ \] .*@([0-9]{4}-[0-9]{2}-[0-9]{2})/ ...'
//
// so this layer marks a day when an OPEN task is dated to it. Deliberately
// only open ones — `- [x]` entries are history, and a calendar covered in
// dots for things already done tells you nothing you can act on.
//
// It is read through a WATCHED FileView rather than a Process, unlike every
// other data source in this fork. That is not inconsistency for its own
// sake: this is one 813-byte local file with no computation to do, and the
// alternative is a subprocess spawn per open to run a regex. The watch also
// means editing TODOS.md in the other window updates the dots without
// reopening the panel.
//
// MEASURED, and worth writing down because it looks like a bug: at the time
// of writing TODOS.md contains ZERO dated entries (`grep -c "@20"` -> 0), so
// the calendar shows no dots at all. That is the correct output, not a
// broken parser. To prove the parser, add a line dated to a day in the
// current month and the dot appears without touching this file.
//
// WEEK START IS ASKED FOR, NOT ASSUMED
// ------------------------------------
// `Qt.locale().firstDayOfWeek` rather than a hardcoded Monday or Sunday.
// A calendar whose columns are off by one is wrong in the specific way
// nobody notices for a week and then cannot un-see, and the system already
// knows the answer.
//
FocusScope {
    id: root

    signal closeRequested

    property bool showCondition: false
    property string textFontFamily: ""
    property string heroFontFamily: ""

    // ---- STATE ----
    //
    // `cursor` is a real JS Date and is the single source of truth: the
    // month on screen is the cursor's month, the highlighted cell is the
    // cursor's day. Holding a separate "displayed month" alongside it was
    // the first shape and it desynchronised the moment a movement crossed a
    // month boundary — j from the last week of August selected a day in
    // September while the grid still drew August, so the highlight simply
    // disappeared with nothing on screen to say where it had gone.
    property var cursor: new Date()
    property var today: new Date()

    // Days of the current month carrying at least one OPEN dated task, as
    // an integer day-of-month set. Rebuilt from the file text; see the
    // header for why it is a FileView and not a Process.
    property var markedDays: ({})

    readonly property int columns: 7
    readonly property real horizontalPadding: Metrics.pad(18)
    readonly property real headerHeight: Metrics.pad(38)
    readonly property real weekdayRowHeight: Metrics.px(18)
    readonly property real cellSize: Metrics.px(34)
    readonly property real footerHeight: Metrics.px(20)

    // The first weekday column, 0=Sunday..6=Saturday, taken from the
    // locale. Qt reports Sunday as 0 in `Locale.Sunday`, which matches
    // JS `Date.getDay()` exactly, so no remapping is needed — verified
    // rather than assumed, because an off-by-one here is invisible for
    // a week and then permanent.
    readonly property int weekStart: Qt.locale().firstDayOfWeek

    function startOfMonth(date) {
        return new Date(date.getFullYear(), date.getMonth(), 1);
    }

    function daysInMonth(date) {
        // Day 0 of the NEXT month is the last day of this one. The
        // alternative — a 12-entry table plus a leap-year rule — is three
        // more lines and one more thing that can be wrong in February.
        return new Date(date.getFullYear(), date.getMonth() + 1, 0).getDate();
    }

    // How many leading blanks the first row needs, i.e. how far the 1st is
    // from the locale's first column. The `+ 7` before the modulo is not
    // cosmetic: JS `%` keeps the sign of the dividend, so a Monday-first
    // locale with a Sunday 1st gives -1 and one whole row is drawn off the
    // left edge of the grid.
    readonly property int leadingBlanks:
        (root.startOfMonth(root.cursor).getDay() - root.weekStart + 7) % 7

    readonly property int monthLength: root.daysInMonth(root.cursor)

    // Rows follow the month, they are not a fixed six. A 28-day February
    // starting on the first column needs four rows, and a fixed six would
    // leave two empty rows of black under it — which is the same "panels
    // that were mostly empty" complaint the display and audio panels were
    // already resized for. See MIGRATION.md.
    readonly property int rowCount:
        Math.ceil((root.leadingBlanks + root.monthLength) / root.columns)

    readonly property real gridHeight: root.rowCount * root.cellSize

    // What DynamicIslandWindow asks for when sizing the capsule. Only this
    // file knows the row count, so only this file can compute it — the same
    // contract ModeKeysLayer, ThemePickerLayer, DisplayPanel and AudioPanel
    // all use.
    readonly property real preferredHeight:
        root.headerHeight + root.weekdayRowHeight + root.gridHeight
        + root.footerHeight + Metrics.pad(16)

    readonly property bool cursorIsToday:
        root.cursor.getFullYear() === root.today.getFullYear()
        && root.cursor.getMonth() === root.today.getMonth()
        && root.cursor.getDate() === root.today.getDate()

    function isToday(day) {
        return root.cursor.getFullYear() === root.today.getFullYear()
            && root.cursor.getMonth() === root.today.getMonth()
            && day === root.today.getDate();
    }

    // ---- MOVEMENT ----
    //
    // Every move goes through a real Date and is then read back, so the
    // month rolls over for free: `new Date(2026, 7, 32)` is 1 September,
    // not an error and not a clamp. Arithmetic on the day number with a
    // hand-written wrap was the obvious alternative and it is where the
    // February bugs live.
    function moveDays(delta) {
        const next = new Date(root.cursor.getFullYear(),
                              root.cursor.getMonth(),
                              root.cursor.getDate() + delta);
        root.cursor = next;
    }

    function moveMonths(delta) {
        // Clamped to the target month's length, because the naive version
        // loses days silently: 31 March minus one month is `new Date(2026,
        // 1, 31)` which JS normalises to 3 March, so pressing `p` twice
        // from 31 March lands in February and then in *March again*.
        const target = new Date(root.cursor.getFullYear(),
                                root.cursor.getMonth() + delta, 1);
        const length = root.daysInMonth(target);
        target.setDate(Math.min(root.cursor.getDate(), length));
        root.cursor = target;
    }

    function goToday() {
        root.today = new Date();
        root.cursor = new Date();
    }

    // ---- THE DATED-TASK MARKS ----
    //
    // Matches clock_popup's own pattern: an unchecked box, then anything,
    // then an @-dated ISO day. `- [x]` is deliberately excluded — see the
    // header.
    function rebuildMarks(text) {
        const marks = {};
        if (text) {
            const year = root.cursor.getFullYear();
            const month = root.cursor.getMonth() + 1;
            const pattern = /- \[ \][^\n]*@(\d{4})-(\d{2})-(\d{2})/g;
            let match = pattern.exec(text);
            while (match !== null) {
                if (Number(match[1]) === year && Number(match[2]) === month)
                    marks[Number(match[3])] = true;
                match = pattern.exec(text);
            }
        }
        root.markedDays = marks;
    }

    // The file text is kept so a month change can re-scan it without
    // re-reading the file. `onCursorChanged` fires on every j/k, and
    // re-reading a file 30 times while scrolling a month would be wasteful
    // for no gain — the text has not changed, only the window onto it.
    property string todoText: ""
    onTodoTextChanged: root.rebuildMarks(root.todoText)
    onCursorChanged: root.rebuildMarks(root.todoText)

    FileView {
        // `clock_popup` derives this path from `whoami | tr` — ATITODOS for
        // ati, SUSUTODOS for susu. That indirection exists so one script can
        // serve several accounts; this shell is one user's config tree and
        // the same trick here would be a path that cannot be grepped for.
        path: Quickshell.env("HOME") + "/ATITODOS/TODOS.md"
        watchChanges: true
        preload: true
        // Quiet: a machine with no TODOS.md is a calendar with no dots, not
        // an error. The panel has nothing useful to say about it and the
        // log already carries enough.
        printErrors: false

        onLoaded: root.todoText = text()
        onFileChanged: {
            reload();
            root.todoText = text();
        }
    }

    focus: showCondition
    activeFocusOnTab: true
    anchors.fill: parent
    opacity: showCondition ? 1 : 0

    // FORK: one choreography for every layer in the shell. See Motion.js,
    // "CONTENT CHOREOGRAPHY".
    Behavior on opacity {
        SequentialAnimation {
            // The delay is what keeps the content from being painted
            // inside a capsule that is still the wrong size for it.
            PauseAnimation { duration: root.showCondition ? Motion.contentDelay() : 0 }
            NumberAnimation {
                duration: root.showCondition ? Motion.fadeInDuration() : Motion.fadeOutDuration()
                // Critically damped: opacity is clamped 0-1 and an
                // overshooting fade reads as a cut. Motion.js says why.
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Motion.fade()
            }
        }
    }

    onShowConditionChanged: {
        if (showCondition) {
            // Snap to today on every open, not on construction. The panel
            // is a PanelLoader child so it does get rebuilt — but the hold
            // timer keeps it alive across a fast close/open, and a calendar
            // that reopened in March because that is where you left it is
            // the wrong default for a surface you open to answer "what is
            // the date".
            root.goToday();
            forceActiveFocus();
        }
    }

    Keys.onPressed: function(event) {
        switch (event.key) {
        case Qt.Key_Escape:
        case Qt.Key_Q:
            root.closeRequested();
            event.accepted = true;
            break;
        // hjkl beside the arrows, as every other panel in this shell reads
        // them. This is a grid like the theme picker, so h/l step one cell
        // and j/k step one ROW — which for a calendar is one week, and is
        // the motion that makes a month grid navigable at all.
        case Qt.Key_Left:
        case Qt.Key_H:
            root.moveDays(-1);
            event.accepted = true;
            break;
        case Qt.Key_Right:
        case Qt.Key_L:
            root.moveDays(1);
            event.accepted = true;
            break;
        case Qt.Key_Up:
        case Qt.Key_K:
            root.moveDays(-7);
            event.accepted = true;
            break;
        case Qt.Key_Down:
        case Qt.Key_J:
            root.moveDays(7);
            event.accepted = true;
            break;
        // Month steps. Both spellings on purpose: `[`/`]` is what a vim
        // hand reaches for to step a section, and n/p is what a calendar
        // reads as. Neither is spent on anything else in this panel.
        case Qt.Key_BracketLeft:
        case Qt.Key_P:
            root.moveMonths(-1);
            event.accepted = true;
            break;
        case Qt.Key_BracketRight:
        case Qt.Key_N:
            root.moveMonths(1);
            event.accepted = true;
            break;
        // Year steps, on SHIFT of the month keys.
        case Qt.Key_BraceLeft:
            root.moveMonths(-12);
            event.accepted = true;
            break;
        case Qt.Key_BraceRight:
            root.moveMonths(12);
            event.accepted = true;
            break;
        // t for today, which is the one destination this panel always has.
        case Qt.Key_T:
            root.goToday();
            event.accepted = true;
            break;
        // g / G to the ends of the month, same as the audio and display
        // panels use them for the ends of a list.
        case Qt.Key_G:
            if ((event.modifiers & Qt.ShiftModifier) !== 0)
                root.cursor = new Date(root.cursor.getFullYear(),
                                       root.cursor.getMonth(),
                                       root.monthLength);
            else
                root.cursor = new Date(root.cursor.getFullYear(),
                                       root.cursor.getMonth(), 1);
            event.accepted = true;
            break;
        default:
            break;
        }
    }

    // ---- HEADER ----
    //
    // The long-form date, not "August 2026". See the header comment: the
    // date carousel this is descended from is a human-readable date, and
    // the month is already spelled out by the grid underneath.
    Text {
        id: header
        x: root.horizontalPadding
        y: Metrics.pad(11)
        text: Qt.formatDate(root.cursor, "dddd")
        color: "white"
        font.pixelSize: Metrics.font(15)
        font.family: root.heroFontFamily
        font.weight: Font.DemiBold
        font.letterSpacing: -0.2
    }

    Text {
        anchors.right: parent.right
        anchors.rightMargin: root.horizontalPadding
        y: Metrics.pad(13)
        text: Qt.formatDate(root.cursor, "d MMMM yyyy")
        // Green when the cursor is on today, muted otherwise — so a month
        // you have paged away from is visibly not now. This is the same
        // green the Wi-Fi QR uses for a good state, rather than a fourth
        // accent invented here.
        color: root.cursorIsToday ? IslandTheme.success : IslandTheme.textSecondary
        font.pixelSize: Metrics.font(12)
        font.family: root.textFontFamily
        font.weight: Font.DemiBold
    }

    // ---- WEEKDAY HEADINGS ----
    Row {
        id: weekdays
        x: root.horizontalPadding
        y: root.headerHeight
        width: parent.width - root.horizontalPadding * 2
        height: root.weekdayRowHeight

        Repeater {
            model: root.columns

            Text {
                required property int index
                width: (weekdays.width) / root.columns
                height: root.weekdayRowHeight
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                // Qt.locale().dayName wants 0=Sunday..6=Saturday, which is
                // the same numbering weekStart uses, so the column index
                // maps straight through.
                text: Qt.locale().dayName((root.weekStart + index) % 7, Locale.ShortFormat)
                color: IslandTheme.textDisabled
                font.pixelSize: Metrics.font(10)
                font.family: root.textFontFamily
                font.weight: Font.Medium
            }
        }
    }

    // ---- THE MONTH ----
    //
    // A Grid over `leadingBlanks + monthLength` cells rather than a
    // GridView: the model is at most 37 items, it never scrolls, and a
    // view's delegate recycling buys nothing at that size while costing
    // the straightforward index-to-day mapping below.
    Grid {
        id: monthGrid
        x: root.horizontalPadding
        y: root.headerHeight + root.weekdayRowHeight
        width: parent.width - root.horizontalPadding * 2
        columns: root.columns
        rowSpacing: 0
        columnSpacing: 0

        Repeater {
            model: root.leadingBlanks + root.monthLength

            Item {
                id: cell
                required property int index

                // Negative for the leading blanks, 1..monthLength for a
                // real day.
                readonly property int day: cell.index - root.leadingBlanks + 1
                readonly property bool isBlank: cell.day < 1
                readonly property bool isSelected: !cell.isBlank && cell.day === root.cursor.getDate()
                readonly property bool isNow: !cell.isBlank && root.isToday(cell.day)
                readonly property bool isMarked: !cell.isBlank && root.markedDays[cell.day] === true

                width: monthGrid.width / root.columns
                height: root.cellSize

                Rectangle {
                    anchors.centerIn: parent
                    width: Math.min(parent.width, root.cellSize) - Metrics.px(4)
                    height: root.cellSize - Metrics.px(4)
                    radius: Metrics.px(8)
                    visible: !cell.isBlank

                    // Three visual states, and they are deliberately
                    // distinguishable from each other rather than being two
                    // shades of one: TODAY is a filled chip (it is a fact
                    // about the world), the CURSOR is an outline (it is a
                    // fact about where your hand is), and a day that is both
                    // gets the filled chip plus the outline. The first
                    // version used the same fill for both and paging away
                    // from today looked like today had moved.
                    color: cell.isNow ? IslandTheme.successFill : "transparent"
                    border.width: cell.isSelected ? 1 : 0
                    border.color: IslandTheme.success

                    Text {
                        anchors.centerIn: parent
                        text: cell.day
                        color: cell.isNow ? IslandTheme.success
                             : (cell.isSelected ? IslandTheme.textPrimary : IslandTheme.textSecondary)
                        font.pixelSize: Metrics.font(12)
                        font.family: root.textFontFamily
                        font.weight: (cell.isNow || cell.isSelected) ? Font.DemiBold : Font.Normal
                    }

                    // The dated-task dot. Under the number, not beside it:
                    // beside it the cell has to grow to fit both and the
                    // grid stops being square, which at seven columns is
                    // the difference between a calendar and a table.
                    Rectangle {
                        visible: cell.isMarked
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: Metrics.px(3)
                        width: Metrics.px(4)
                        height: width
                        radius: width / 2
                        color: IslandTheme.warning
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: {
                            if (!cell.isBlank)
                                root.cursor = new Date(root.cursor.getFullYear(),
                                                       root.cursor.getMonth(),
                                                       cell.day);
                        }
                    }
                }
            }
        }
    }

    // ---- FOOTER ----
    //
    // The keys, spelled out. Every panel in this fork does this, and it is
    // the reason the chord HUD exists at all: a surface that reads its own
    // keys and does not say which ones is a surface you have to have read
    // the source of.
    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Metrics.pad(8)
        text: "hjkl move  ·  n/p month  ·  t today  ·  q close"
        color: IslandTheme.textDisabled
        font.pixelSize: Metrics.font(10)
        font.family: root.textFontFamily
    }
}
