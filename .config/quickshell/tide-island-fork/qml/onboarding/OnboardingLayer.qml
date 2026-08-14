pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
// Metrics is a .js library and has to be imported by every file that
// names it — it is not a singleton and does not come in with the
// directory import below. Omitting it is silent at load: the file
// compiles, and every px()/pad()/font() call resolves to undefined at
// RUNTIME, which collapsed every chip to zero width and stacked the rows
// on top of each other. The only sign was `ReferenceError: Metrics is not
// defined` in the shell log.
import "../common/Metrics.js" as Metrics
import "../common"

// FORK: the tour, ported from eww.
//
// qtile has one — .config/eww/onboarding/*.yuck, five windows opened in
// sequence by config.py's toggle_onboarding() — and Hyprland had nothing.
// This is the same five pages in the notch.
//
// WHAT WAS COPIED AND WHAT WAS NOT
//
// The five-page shape, the step indicator and the Cancel/Next footer are
// eww's and are kept: they are the part that makes a tour feel like a
// tour rather than a chain of dialogs, and steps.yuck's own comment says
// the dots exist so the reader knows how much is left.
//
// What is NOT copied is eww's structure. There, each page is its own
// WINDOW, and every button closes five named windows by hand:
//
//     eww close onboarding-welcome bar-tooltip onboarding-workspaces
//                onboarding-keybindings onboarding-finish
//
// Five windows means five places to forget one, and that list is
// duplicated on every button of every page. Here the pages are DATA in
// one layer, `page` is an index, and closing is one state change.
//
// THE TABS ARE THE STEP INDICATOR
//
// PanelChrome already draws tabs and already emits tabRequested, so the
// dots come free — and they are better than dots, because they name the
// pages and let you jump straight to the one you wanted. An onboarding
// you can only read forwards is one nobody re-reads.
//
// REACHABLE AGAIN, AND DRIVABLE. Both are requirements, not niceties: an
// onboarding that can only be seen once cannot be tested, and a panel
// with no IPC is one whose bugs only the user finds. See `tide
// showOnboarding` / `hideOnboarding` / `onboardingPage` in shell.qml.
Item {
    id: root

    property bool showCondition: false
    property string textFontFamily: ""
    property string heroFontFamily: ""
    property string iconFontFamily: ""

    property int page: 0

    signal closeRequested
    signal finishRequested

    readonly property var pages: [
        {
            tab: "WELCOME",
            title: "Welcome",
            blurb: "A short tour of this desktop. Six pages, and you can "
                 + "leave at any point — $mod SHIFT I brings it back.",
            rows: [
                { k: "$mod", v: "the Super / Windows key, used by almost everything" },
                { k: "$alt", v: "Caps Lock, remapped by keyd — this laptop's real Alt is dead in hardware" },
                { k: "$mod SHIFT /", v: "the docs, keymaps and troubleshooting sheets" },
                { k: "$mod SHIFT K", v: "the same sheets, on qtile's key" }
            ]
        },
        {
            tab: "THE ISLAND",
            title: "The island",
            blurb: "The notch at the top is the shell. It rests as a clock "
                 + "and grows into whatever you ask it for.",
            rows: [
                { k: "hover", v: "the resting capsule shows the workspace and the focused window" },
                { k: "swipe left", v: "lyrics, CPU, RAM and the other left-swipe items" },
                { k: "$mod SHIFT GRAVE", v: "the workspace overview" },
                { k: "click", v: "every panel is reachable by pointer as well as by key" }
            ]
        },
        {
            tab: "WORKSPACES",
            title: "Workspaces",
            blurb: "Nine numbered workspaces, plus named ones for the apps "
                 + "that deserve a home of their own.",
            rows: [
                { k: "$mod 1..9", v: "go to a workspace" },
                { k: "$mod SHIFT 1..9", v: "move the focused window there" },
                { k: "$mod SHIFT O", v: "Obsidian, on the S workspace" },
                { k: "$alt SHIFT A", v: "Anki, sharing S with it" },
                { k: "$alt 1..3", v: "the scratchpad terminals" }
            ]
        },
        {
            tab: "KEYS",
            title: "The keys worth knowing first",
            blurb: "Everything else is in the cheatsheet, which is generated "
                 + "from the live compositor and cannot drift.",
            rows: [
                { k: "$mod N", v: "terminal" },
                { k: "$mod B", v: "browser" },
                { k: "$mod V", v: "qutebrowser" },
                { k: "$mod M", v: "files" },
                { k: "$mod Q", v: "close the focused window" },
                { k: "$mod SPACE", v: "the language submap" },
                { k: "$mod /", v: "the media submap" }
            ]
        },
        {
            tab: "THEMES",
            title: "Themes and wallpaper",
            blurb: "Twenty-one themes. Changing one repaints every "
                 + "application and draws a new wallpaper in the same "
                 + "animation.",
            rows: [
                { k: "theme-apply <name>", v: "apply a theme everywhere" },
                { k: "picker", v: "each theme draws at random from its own set of wallpapers" },
                { k: "pick one by hand", v: "and that theme is bound to it from then on" },
                { k: "theme-wallpaper forget", v: "hands a theme back to its random set" }
            ]
        },
        {
            tab: "DONE",
            title: "That is the tour",
            blurb: "Everything here is in the documentation sheets, and "
                 + "this tour is always one key away.",
            rows: [
                { k: "$mod SHIFT I", v: "open this tour again" },
                { k: "$mod SHIFT /", v: "docs, keymaps, troubleshooting" },
                { k: "~/.config/hypr/README.md", v: "the written version, including troubleshooting" },
                { k: "onboarding-first-run --arm", v: "show the tour again at the next login" }
            ]
        }
    ]

    readonly property int pageCount: pages.length

    // FORK: the height the tallest page needs, so the island can be FIXED
    // and still correct.
    //
    // mode_keys already does this — the layer knows its own row count and
    // nothing else does. The difference here is that it is the maximum over
    // all six pages rather than the current page's, which is what keeps the
    // panel from resizing on every Next while still fitting the seven-row
    // KEYS page. Guessing the number instead clipped that page under its
    // own footer twice, at 300 and again at 390.
    readonly property int maxRowCount: {
        let n = 0;
        for (let i = 0; i < pages.length; i++)
            n = Math.max(n, pages[i].rows.length);
        return n;
    }
    //
    // CALIBRATED, and deliberately not derived from the chrome.
    //
    // Two attempts to compute it from the panel's own geometry failed the
    // same way, and the second failed loudly: the island's height binding
    // reads this property, PanelChrome fills the island, so reading
    // `chrome.chromeHeight` — let alone `blurbText.implicitHeight`, which
    // lives INSIDE that chrome — closes a cycle through the value being
    // computed. QML broke the cycle by leaving everything at zero and the
    // panel rendered empty apart from its footer.
    //
    // So: one constant for everything above and below the rows (header,
    // tab strip, blurb, gaps, footer), plus the rows themselves, which are
    // the only part that varies. 248 was read off the screen — at 390 the
    // seven-row page showed six and a half rows — and then checked by
    // looking at the longest page again.
    readonly property real preferredHeight:
        Metrics.px(248) + maxRowCount * Metrics.px(26)

    readonly property var current: pages[Math.max(0, Math.min(page, pageCount - 1))]
    readonly property var tabNames: {
        const out = [];
        for (let i = 0; i < pages.length; i++)
            out.push(pages[i].tab);
        return out;
    }

    // Clamped rather than wrapped. A tour has a beginning and an end, and
    // "Next" on the last page rolling back to Welcome would be a loop with
    // no exit — eww's finish page has a Done button for exactly this
    // reason, and here the last page's Next becomes Done.
    function goto(index) {
        page = Math.max(0, Math.min(index, pageCount - 1));
    }

    function next() {
        if (page >= pageCount - 1) {
            root.finishRequested();
            root.closeRequested();
            return;
        }
        goto(page + 1);
    }

    function prev() {
        goto(page - 1);
    }

    function grabKeyboardFocus() {
        keyScope.forceActiveFocus();
    }

    onShowConditionChanged: {
        if (showCondition)
            Qt.callLater(grabKeyboardFocus);
    }

    anchors.fill: parent

    PanelChrome {
        id: chrome

        anchors.fill: parent
        title: root.current ? root.current.title : ""
        statusClause: root.current
            ? ("step " + (root.page + 1) + " of " + root.pageCount)
            : ""
        // PanelChrome takes only textFontFamily — the hero face is its own
        // business, chosen inside it. Passing a heroFontFamily here is what
        // the first reload rejected.
        textFontFamily: root.textFontFamily

        tabs: root.tabNames
        currentTab: root.current ? root.current.tab : ""
        onTabRequested: function(name) {
            for (let i = 0; i < root.pages.length; i++) {
                if (root.pages[i].tab === name) {
                    root.goto(i);
                    return;
                }
            }
        }

        // Only the verbs that do something HERE. "back" is dropped on the
        // first page and "next" becomes "done" on the last, because a
        // footer advertising a key that no-ops is how a panel teaches you
        // to stop reading its footer.
        hints: {
            const out = [];
            if (root.page > 0)
                out.push({ key: "h/p", label: "back" });
            out.push({ key: "l/n/Space",
                       label: root.page >= root.pageCount - 1 ? "done" : "next" });
            out.push({ key: "1-" + root.pageCount, label: "jump" });
            out.push({ key: "q", label: "close" });
            return out;
        }

        Column {
            id: body

            x: chrome.contentX
            y: chrome.contentY
            width: chrome.contentWidth
            spacing: Metrics.pad(10)

            Text {
                id: blurbText

                width: body.width
                text: root.current ? root.current.blurb : ""
                color: IslandTheme.textSecondary
                font.family: root.textFontFamily
                font.pixelSize: Metrics.font(12)
                wrapMode: Text.WordWrap
            }

            Repeater {
                model: root.current ? root.current.rows : []

                PanelRow {
                    id: rowItem

                    required property var modelData

                    width: body.width
                    // Nothing here is selectable: the tour has no cursor and
                    // no per-row action. PanelRow is used for its metrics and
                    // its divider, so these rows sit on the same grid as every
                    // other panel's — which is the point of the shared
                    // components.
                    selected: false

                    // Children go straight into contentItem — PanelRow's
                    // default property aliases to it, and it ALREADY applies
                    // contentPadding as anchor margins. The first version
                    // wrapped these in an Item and re-applied that padding,
                    // which double-indented the chip and left the label
                    // anchored inside a collapsed parent, so the two drew on
                    // top of each other and escaped the panel.
                    Rectangle {
                        id: keyChip

                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.max(Metrics.px(22),
                                        keyText.implicitWidth + Metrics.pad(10))
                        height: Metrics.px(17)
                        radius: Metrics.px(4)
                        color: IslandTheme.surfaceRaised

                        Text {
                            id: keyText

                            anchors.centerIn: parent
                            text: rowItem.modelData.k
                            color: IslandTheme.textPrimary
                            font.family: root.textFontFamily
                            font.pixelSize: Metrics.font(11)
                            font.weight: Font.DemiBold
                        }
                    }

                    Text {
                        anchors.left: keyChip.right
                        anchors.leftMargin: Metrics.pad(9)
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: rowItem.modelData.v
                        color: IslandTheme.textSecondary
                        font.family: root.textFontFamily
                        font.pixelSize: Metrics.font(11)
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }

    // The keyboard grab.
    //
    // It is scoped to this Item and released the moment the layer goes
    // away, so the desktop behind keeps working — which is a requirement
    // and not an accident: a tour that swallows every key on first login
    // is a tour you cannot escape from on the one day you most want to.
    // Escape and q both leave, and neither is trapped anywhere else.
    FocusScope {
        id: keyScope

        anchors.fill: parent
        focus: root.showCondition

        Keys.onPressed: function(event) {
            switch (event.key) {
            case Qt.Key_Escape:
            case Qt.Key_Q:
                root.closeRequested();
                event.accepted = true;
                return;
            case Qt.Key_Right:
            case Qt.Key_L:
            case Qt.Key_N:
            case Qt.Key_Space:
            case Qt.Key_Return:
            case Qt.Key_Enter:
                root.next();
                event.accepted = true;
                return;
            case Qt.Key_Left:
            case Qt.Key_H:
            case Qt.Key_P:
            case Qt.Key_Backspace:
                root.prev();
                event.accepted = true;
                return;
            }

            // 1..N jump straight to a page. The tour is six pages and the
            // digits are already on the row above the letters, so this is
            // the cheapest possible "go back and read that again".
            if (event.key >= Qt.Key_1 && event.key <= Qt.Key_9) {
                const wanted = event.key - Qt.Key_1;
                if (wanted < root.pageCount) {
                    root.goto(wanted);
                    event.accepted = true;
                }
            }
        }
    }
}
