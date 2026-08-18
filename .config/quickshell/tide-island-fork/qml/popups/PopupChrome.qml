import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

import "../common"

//
// FORK — new file. The frame every qtile-style popup is drawn in.
//
// WHAT IT IS A COPY OF
// --------------------
// popups/WallpaperPopup.py builds a `PopupRelativeLayout` and the three
// popups here share its whole visual grammar, so it is written once:
//
//     background   COLORS["bg"] + "F2"     high opacity, not opaque
//     border       COLORS["surface_alt"], border_width=2
//     head_y/h     28 / 54     title block
//     hint_y/h     92 / 30     the keycap bar
//     body_y/h     138 / 436   the cards
//     foot_y/h     588 / 62    the status bar
//     cards        COLORS["surface"], highlight_radius 8-10
//     font         JetBrainsMono Nerd Font
//
// Those y/h numbers are absolute pixels against POPUP_H=680 in that file —
// it writes them as `28 / POPUP_H` fractions with the pixel value in the
// comment — so they are used here as pixels and the height is a property.
//
// THE PALETTE IS IslandTheme, NOT A SECOND WAL READER
// ---------------------------------------------------
// popups/_wal_colors.py reads the pywal output directly and derives
// surface/surface_alt/line from it. IslandTheme reads the same pipeline
// through ~/.cache/tide-island/colors.json and derives the same kind of
// tones, so the derivations are ported (mix bg toward fg by 0.07, 0.14 and
// 0.22) rather than the loader. A second reader of one palette is how every
// window border ended up green on twenty-two themes.
//
// WHY IT TAKES THE KEYBOARD
// -------------------------
// qtile's popups are driven entirely by a KeyChord — the popup itself never
// has focus, the chord does. There is no chord here to hold the keys, so the
// surface takes them itself, which is also what makes Escape work without a
// compositor bind. WlrKeyboardFocus.Exclusive rather than OnDemand: these are
// modal pickers, and a picker that answers only when you remember to click it
// first is a worse picker.
PanelWindow {
    id: root

    // POPUP_W / POPUP_H. Overridable so the network and volume popups can be
    // the sizes their own files are.
    property int popupWidth: PopupMetrics.s(1120)
    property int popupHeight: PopupMetrics.s(680)

    property string titleIcon: ""
    property string title: ""
    property string subtitle: ""
    // The right-hand header chip. Rendered as plain text so a popup can put
    // whatever it wants there; the wallpaper one puts the theme mode in it.
    property string badgeLabel: ""
    property string badgeValue: ""

    // [{ key: "hjkl", desc: "move" }, …] — render_hints()' pairs.
    property var hints: []

    // ---- THE OPTIONAL TABS ROW ----
    //
    // DisplayPopup.py is the one popup in that folder with FOUR views, and it
    // has a row the others do not: render_tabs(), at y=126 between the hint
    // bar and the body, carrying the current view's name in a filled chip
    // plus a line of keys that only apply inside that view.
    //
    // Optional rather than a fifth popup shape: `tabsLabel` empty leaves the
    // rhythm exactly as the other four have it, so nothing moves for them.
    // When it is set the body starts lower, by that file's own numbers —
    // body 138 -> 162, which is the 24 px this row occupies plus its gap.
    property string tabsLabel: ""
    property string tabsExtra: ""

    // ---- THE GAP BETWEEN KEYCAPS IS PER POPUP, AND MEASURED ----
    //
    // Not one number. render_hints() joins its pairs with a run of spaces and
    // the two files use different runs, each with its reason written down:
    //
    //   WallpaperPopup.py  five spaces — five pairs on a 1120 px bar
    //   WifiPopup.py       ONE space, and it says why: "ten of them at two
    //                      spaces overflow the 874px bar by 6px, and nothing
    //                      clips a control — it would spill over the cards
    //                      below. Drop a pair before widening the gap again."
    //
    // A shared constant reproduced the overflow it warns about: the network
    // popup's first chip ran off the left edge. So the gap is the caller's,
    // in the same units — a space of the monospace face at HINT_SIZE, which
    // JetBrains Mono sets at 0.6 em.
    property real hintGap: PopupMetrics.hintSize * 0.6 * 5

    // The status bar. Its own item, because each popup's footer is a
    // different shape: the wallpaper one has a scroll bar in the middle of it.
    default property alias body: bodyArea.data
    property alias footer: footerArea.data

    signal keyPressed(int key, int modifiers, string text)
    signal dismissed()

    // ---- THE SURFACE ----
    //
    // No anchors at all: an unanchored layer surface is CENTRED, which is
    // `show(centered=True)` in the file this copies. Anchoring it and then
    // computing a margin would be the same placement done twice, and the
    // second one would be wrong on any other screen size.

    // ---- WHICH MONITOR, WHICH IS ONLY A QUESTION WITH TWO ----
    //
    // These popups had no `screen` at all, so Quickshell placed them on
    // whichever it picked first — the primary. With one monitor that is
    // always right and the bug is invisible; with two it means every popup
    // opens on the OTHER screen from the one you are working on.
    //
    // Bound to the FOCUSED monitor, not to a configured one: a popup is
    // opened by a keypress, and the screen your keyboard is on is the screen
    // you are looking at. Matched by NAME because Hyprland's monitor object
    // and Quickshell's ShellScreen are different types over the same output.
    //
    // Null when there is no match, which is Quickshell's own default and the
    // right answer while a monitor is being added or removed — a popup on
    // the wrong screen beats a popup on no screen.
    screen: {
        const focused = Hyprland.focusedMonitor;
        if (!focused)
            return null;
        const screens = Quickshell.screens;
        for (let i = 0; i < screens.length; i++)
            if (String(screens[i].name) === String(focused.name))
                return screens[i];
        return null;
    }
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.namespace: "quickshell-qtile-popup"
    exclusionMode: ExclusionMode.Ignore

    implicitWidth: root.popupWidth
    implicitHeight: root.popupHeight
    color: "transparent"

    // ---- THE DERIVED TONES ----
    //
    // _load_colors()' three, by the same derivation. `line` is the separator
    // and the trough; `surface` is every card; `surfaceAlt` is the border and
    // the keycaps.
    readonly property color cLine: IslandTheme.mix(IslandTheme.background,
                                                   IslandTheme.foreground, 0.22)
    readonly property color cSurface: IslandTheme.mix(IslandTheme.background,
                                                      IslandTheme.foreground, 0.07)
    readonly property color cSurfaceAlt: IslandTheme.mix(IslandTheme.background,
                                                         IslandTheme.foreground, 0.14)
    // highlight_bg = the dominant accent, highlight_fg = bg "so selected text
    // pops against accent".
    readonly property color cHighlight: IslandTheme.green
    readonly property color cHighlightInk: IslandTheme.background
    readonly property color cMuted: IslandTheme.textMuted
    readonly property color cFg: IslandTheme.textPrimary

    Rectangle {
        anchors.fill: parent
        // background=COLORS["bg"] + "F2" — 0xF2/255 = 0.949.
        color: IslandTheme.alpha(IslandTheme.background, 0.949)
        border.color: root.cSurfaceAlt
        border.width: PopupMetrics.s(2)
        radius: PopupMetrics.s(14)

        // ---- THE FADE, AND WHY IT IS ON THIS RECTANGLE ----
        //
        // fade_in_popup(layout, duration=0.28, steps=18). Longer than that
        // module's own default, and the file says why: "a fade that reads
        // fine on a small cheatsheet is over before the eye tracks it on a
        // panel this large."
        //
        // On the CONTENT and not on the window: a PanelWindow has no opacity
        // property at all, and assigning one is a load error rather than a
        // no-op — "Cannot assign to non-existent property", which takes the
        // whole config down with it.
        opacity: 0
        Component.onCompleted: opacity = 1
        Behavior on opacity {
            NumberAnimation { duration: 280; easing.type: Easing.OutCubic }
        }

        // ---- HEADER ----
        //
        // PROMPT-NEXT.md item 4 asked whether this surface has the same
        // fixed-radius-vs-text defect PanelChrome (the island's own chrome)
        // had. AUDITED, not fixed — no defect found. Against the smallest
        // popup this shell has (WifiQrPopup, 420x560), the header's x-inset
        // (popupWidth*0.035 = 14.7px) still clears the 14px corner radius,
        // and its y-inset (28px) clears it with 2x margin; the footer's
        // reserved gap (30px, see footerArea below) is more generous still.
        // Confirmed by screenshot on three sizes — WifiQrPopup (smallest),
        // VolumePopup (the 940-wide default), CheatsheetPopup — none show
        // text under the curve. This chrome has no notch morph (PanelChrome's
        // actual defect was the corner state CHANGING under fixed text
        // insets), so there was never a state transition here to get wrong.
        // The report was very likely made under `bar-mode=island`, whose
        // separate PanelChrome already got this fix (commit 4c15615).
        Item {
            id: head
            x: root.popupWidth * 0.035
            y: PopupMetrics.s(28)
            width: root.popupWidth * 0.93
            height: PopupMetrics.s(54)

            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: PopupMetrics.s(2)

                Text {
                    // size="x-large" weight="bold". pango's x-large is 1.44x
                    // the base, which is HEAD_SIZE here.
                    text: root.titleIcon + "  " + root.title
                    color: root.cFg
                    font.family: PopupMetrics.font
                    font.pixelSize: Math.round(PopupMetrics.headSize * 1.44)
                    font.bold: true
                    renderType: Text.NativeRendering
                }
                Text {
                    // size="small" — pango's small is 0.833x.
                    text: root.subtitle
                    color: root.cMuted
                    font.family: PopupMetrics.font
                    font.pixelSize: Math.round(PopupMetrics.headSize * 0.833)
                    renderType: Text.NativeRendering
                }
            }

            // render_header_badge(): muted words, then a keycap-style chip.
            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: PopupMetrics.s(6)
                visible: root.badgeValue !== ""

                Text {
                    text: root.badgeLabel
                    color: root.cMuted
                    font.family: PopupMetrics.font
                    font.pixelSize: PopupMetrics.hintSize
                    anchors.verticalCenter: parent.verticalCenter
                    renderType: Text.NativeRendering
                }
                Rectangle {
                    color: root.cSurfaceAlt
                    radius: PopupMetrics.s(5)
                    width: badgeText.implicitWidth + PopupMetrics.s(14)
                    height: badgeText.implicitHeight + PopupMetrics.s(6)
                    anchors.verticalCenter: parent.verticalCenter
                    Text {
                        id: badgeText
                        anchors.centerIn: parent
                        text: root.badgeValue
                        color: IslandTheme.info
                        font.family: PopupMetrics.font
                        font.pixelSize: PopupMetrics.hintSize
                        font.bold: true
                        renderType: Text.NativeRendering
                    }
                }
            }
        }

        // ---- KEY HINTS ----
        Rectangle {
            id: hintBar
            x: root.popupWidth * 0.035
            y: PopupMetrics.s(92)
            width: root.popupWidth * 0.93
            height: PopupMetrics.s(30)
            color: root.cSurface
            radius: PopupMetrics.s(8)

            Row {
                anchors.centerIn: parent
                spacing: root.hintGap

                Repeater {
                    model: root.hints
                    delegate: Row {
                        required property var modelData
                        spacing: PopupMetrics.s(6)

                        Rectangle {
                            color: root.cSurfaceAlt
                            radius: PopupMetrics.s(4)
                            width: capText.implicitWidth + PopupMetrics.s(12)
                            height: capText.implicitHeight + PopupMetrics.s(4)
                            anchors.verticalCenter: parent.verticalCenter
                            Text {
                                id: capText
                                anchors.centerIn: parent
                                text: modelData.key
                                color: root.cFg
                                font.family: PopupMetrics.font
                                font.pixelSize: PopupMetrics.hintSize
                                font.bold: true
                                renderType: Text.NativeRendering
                            }
                        }
                        Text {
                            text: modelData.desc
                            color: root.cMuted
                            font.family: PopupMetrics.font
                            font.pixelSize: PopupMetrics.hintSize
                            anchors.verticalCenter: parent.verticalCenter
                            renderType: Text.NativeRendering
                        }
                    }
                }
            }
        }

        // ---- BODY, AND THE FOOTER IT IS MEASURED AGAINST ----
        //
        // The original's vertical rhythm, at POPUP_H=680:
        //
        //     head   28 ..  82
        //     hints  92 .. 122
        //     body  138 .. 574
        //     foot  588 .. 650      leaving 30 px below it
        //
        // Everything except the body is a FIXED height, so a popup that is
        // not 680 tall gives the difference to the body rather than scaling
        // the header and the keycaps with it — which is what "the network
        // popup is shorter" should mean and not "the network popup has
        // smaller keycaps". Hence the footer is placed from the BOTTOM and
        // the body simply fills what is between them, with the original's
        // 14 px gap (574 -> 588) kept.
        // render_tabs(): the view chip, then the keys that belong to it.
        // Drawn only when a popup sets it; see the property's note.
        Row {
            id: tabsRow
            visible: root.tabsLabel !== ""
            x: root.popupWidth * 0.035
            y: PopupMetrics.s(126)
            height: PopupMetrics.s(26)
            spacing: PopupMetrics.s(8)

            Rectangle {
                // highlight_bg with highlight_fg on it — the same filled chip
                // the selected row uses, so "which view" reads the same as
                // "which row" does.
                color: root.cHighlight
                radius: PopupMetrics.s(5)
                width: tabsLabelText.implicitWidth + PopupMetrics.s(16)
                height: tabsLabelText.implicitHeight + PopupMetrics.s(6)
                anchors.verticalCenter: parent.verticalCenter
                Text {
                    id: tabsLabelText
                    anchors.centerIn: parent
                    text: root.tabsLabel
                    color: root.cHighlightInk
                    font.family: PopupMetrics.font
                    font.pixelSize: PopupMetrics.hintSize
                    font.bold: true
                    renderType: Text.NativeRendering
                }
            }
            Text {
                text: root.tabsExtra
                color: root.cMuted
                font.family: PopupMetrics.font
                font.pixelSize: PopupMetrics.hintSize
                anchors.verticalCenter: parent.verticalCenter
                renderType: Text.NativeRendering
            }
        }

        Item {
            id: bodyArea
            x: root.popupWidth * 0.035
            // 138 without the tabs row, 162 with it — DisplayPopup.py's own
            // body_y, which is this row's height plus the same gap.
            y: root.tabsLabel !== "" ? PopupMetrics.s(162) : PopupMetrics.s(138)
            width: root.popupWidth * 0.93
            height: Math.max(0, footerArea.y - y - PopupMetrics.s(14))
        }

        Rectangle {
            id: footerArea
            x: root.popupWidth * 0.035
            y: root.popupHeight - PopupMetrics.s(30) - PopupMetrics.s(62)
            width: root.popupWidth * 0.93
            height: PopupMetrics.s(62)
            color: root.cSurface
            radius: PopupMetrics.s(10)
        }
    }

    // ---- KEYS ----
    //
    // One FocusScope over the whole surface. Escape and q are handled here
    // because every one of qtile's chords ends the same way and none of the
    // three popups wants to spell it out again; everything else is forwarded
    // to whichever popup this is.
    FocusScope {
        anchors.fill: parent
        focus: true

        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_Escape
                    || (event.key === Qt.Key_Q && event.modifiers === Qt.NoModifier)) {
                root.dismissed();
                event.accepted = true;
                return;
            }
            root.keyPressed(event.key, event.modifiers, event.text);
            event.accepted = true;
        }
    }
}
