import QtQuick
import Quickshell
import Quickshell.Wayland

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
        Item {
            id: bodyArea
            x: root.popupWidth * 0.035
            y: PopupMetrics.s(138)
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
