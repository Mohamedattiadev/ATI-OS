import QtQuick
import IslandBackend

// FORK: one shared scale factor for every island surface.
import "../common/Metrics.js" as Metrics
import "../common/Motion.js" as Motion

//
// FORK — the Display/Sound control, restyled onto amanhex/ukishima's
// "filament fader" idiom on request ("i want the other repo's ones").
//
// WHAT IT LOOKED LIKE, AND WHY IT WAS THE UGLY PART
// -------------------------------------------------
// A Metrics.px(24)-radius card holding a 30 px pill track with a 1 px
// border, a fill in #eceef2 and a 24 px knob in #f4f5f7 with a near-white
// border. Two large slabs of near-white, at the widest part of the panel,
// on a surface whose whole identity is a near-black shape imitating bezel.
// The knob alone is 24 px of #f4f5f7 — brighter and larger than any other
// element in the shell, for a control that is read at a glance and adjusted
// by dragging.
//
// UKISHIMA'S ANSWER, from components/VFader.qml
// ---------------------------------------------
// A 2 px matte thread, a gradient fill in the accent, and a small flat tick
// instead of a knob. "Dim at rest; saturates and reveals its readout when
// focused. No knob, no glow." The value is not drawn until you are actually
// touching the thing — at rest the fader is the fill length and nothing
// else, which is all a glance needs.
//
// TWO DELIBERATE DEPARTURES
// -------------------------
// 1. HORIZONTAL, where theirs is vertical. Theirs sits in a row of four
//    columns in a wide panel; ours is two full-width rows in a 385 px one.
//    Rotating their layout would have meant rebuilding the control centre's
//    column into a row and re-deriving every height in it — the idiom is
//    the thread, the fill and the tick, not the axis.
// 2. THE ACCENT IS OURS, not their vermillion. Theme.qml hardcodes
//    "#c0442b" because ukishima ships one identity; this shell follows
//    whatever theme-apply last wrote, and a fixed vermillion would be the
//    one element on screen ignoring the palette — the exact complaint that
//    got the island's own fill changed earlier. accentColor comes down from
//    IslandTheme.accent.
//
Item {
    id: root

    signal interactionStarted()
    signal valueMoved(real value)
    signal commitRequested()
    signal cancelRequested()

    property string title: ""
    property string iconText: ""
    property string iconFontFamily: ""
    property string textFontFamily: ""
    property real value: 0
    // Kept so ControlCenterLayer's existing bindings still resolve. The fader
    // has no knob, so it is deliberately unused — removing it would mean
    // editing two instantiation sites for no visual gain.
    property real knobSize: 24
    property color moduleColor: StyleTokens.module
    property color moduleHover: StyleTokens.moduleHover
    property color trackColor: StyleTokens.track
    property color textPrimary: StyleTokens.textPrimary
    property color textSecondary: StyleTokens.textSecondary
    property color accentColor: "#e0563b"

    readonly property bool pressed: sliderArea.pressed
    // "lit" is ukishima's word for it: hovered or being dragged. Everything
    // that brightens, brightens on this one boolean rather than on hover and
    // press separately, so a drag that leaves the row does not dim halfway.
    readonly property bool lit: sliderArea.containsMouse || sliderArea.pressed

    function clamp01(nextValue) {
        return Math.max(0, Math.min(1, nextValue));
    }

    // Their token set, mapped onto ours. threadBg is alpha(cream, 0.13) and
    // that ratio is what keeps the unfilled thread visible on a near-black
    // surface without becoming a line you read as content.
    readonly property color threadBg: Qt.rgba(0.925, 0.925, 0.925, 0.13)
    readonly property color creamColor: "#ececec"
    readonly property color dimColor: "#8c8c8c"
    readonly property color faintColor: "#6a6a6a"

    // No card. The old one drew a rounded rectangle with a MatteSurface over
    // it; ukishima's mixer draws faders straight onto the panel and lets the
    // panel be the surface. One less nested rounded shape in a stack that
    // already has the capsule's own.
    Item {
        anchors.fill: parent
        anchors.leftMargin: Metrics.pad(14)
        anchors.rightMargin: Metrics.pad(14)

        // ---- Label row: ICON · TITLE ............ VALUE ----
        //
        // Uppercase and letterspaced, which is ukishima's header treatment
        // everywhere (WIFI, MIXER, BATTERY, RATE, CAPACITY). It is what makes
        // a 10 px label read as a field name rather than as small body text.
        Text {
            id: glyph
            anchors.left: parent.left
            anchors.verticalCenter: label.verticalCenter
            text: root.iconText
            color: root.lit ? root.creamColor : root.dimColor
            font.pixelSize: Metrics.font(13)
            font.family: root.iconFontFamily
            Behavior on color { ColorAnimation { duration: Motion.fadeOutDuration() } }
        }

        Text {
            id: label
            anchors.left: glyph.right
            anchors.leftMargin: Metrics.pad(9)
            y: Metrics.pad(13)
            text: root.title.toUpperCase()
            color: root.lit ? root.creamColor : root.dimColor
            font.pixelSize: Metrics.font(10)
            font.family: root.textFontFamily
            font.weight: Font.DemiBold
            font.letterSpacing: 0.8
            Behavior on color { ColorAnimation { duration: Motion.fadeOutDuration() } }
        }

        // The readout only exists while you are touching it — VFader.qml's
        // `opacity: root.lit ? 1 : 0` on its readout Text. At rest the fill
        // length IS the value, and a number that is always on screen is a
        // number you stop reading.
        Text {
            id: readout
            anchors.right: parent.right
            anchors.verticalCenter: label.verticalCenter
            text: Math.round(root.clamp01(root.value) * 100) + "%"
            color: root.creamColor
            opacity: root.lit ? 1 : 0
            font.pixelSize: Metrics.font(10)
            font.family: root.textFontFamily
            font.weight: Font.DemiBold
            Behavior on opacity { NumberAnimation { duration: Motion.fadeOutDuration() } }
        }

        // ---- The thread ----
        Item {
            id: threadArea
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: label.bottom
            anchors.topMargin: Metrics.pad(13)
            height: Metrics.px(14)

            Rectangle {
                id: thread
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                height: Metrics.px(2)
                radius: height / 2
                color: root.threadBg

                Rectangle {
                    id: fill
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: parent.width * root.clamp01(root.value)
                    radius: parent.radius

                    // Their gradient runs dim -> deep at rest and lit -> burn
                    // when focused. Derived from the live accent with
                    // Qt.darker rather than written out, because the accent
                    // changes with the theme and four hand-picked hex values
                    // would only be right for one of them.
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop {
                            position: 0.0
                            color: root.lit ? Qt.lighter(root.accentColor, 1.08)
                                            : Qt.darker(root.accentColor, 1.5)
                        }
                        GradientStop {
                            position: 1.0
                            color: root.lit ? Qt.darker(root.accentColor, 1.25)
                                            : Qt.darker(root.accentColor, 2.2)
                        }
                    }

                    // Not animated while dragging: the fill must track the
                    // pointer exactly or the thread lags under the finger,
                    // which reads as the control being unresponsive rather
                    // than as smoothing. Same guard VFader.qml uses.
                    Behavior on width {
                        enabled: !sliderArea.pressed
                        NumberAnimation {
                            duration: Motion.fadeOutDuration()
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Motion.fade()
                        }
                    }
                }
            }

            // The tick. 11 x 2.5 in theirs, rotated here: a 2.5 px wide,
            // 11 px tall flat marker. It FADES OUT while lit, which looks
            // backwards and is not — once you are dragging, the fill edge is
            // under your pointer and the tick is a second marker in the same
            // place drawing a hard bright line across it.
            Rectangle {
                id: tick
                x: Math.max(0, Math.min(threadArea.width - width,
                    threadArea.width * root.clamp01(root.value) - width / 2))
                anchors.verticalCenter: parent.verticalCenter
                width: Metrics.px(2.5)
                height: Metrics.px(11)
                radius: Metrics.px(2)
                color: "#c2c2c2"
                opacity: root.lit ? 0 : 1
                Behavior on opacity { NumberAnimation { duration: Motion.fadeOutDuration() } }
                Behavior on x {
                    enabled: !sliderArea.pressed
                    NumberAnimation {
                        duration: Motion.fadeOutDuration()
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Motion.fade()
                    }
                }
            }

            MouseArea {
                id: sliderArea
                anchors.fill: parent
                // Generous vertical target: the thread is 2 px and nobody can
                // hit 2 px with a mouse. Theirs does the same with
                // `anchors.margins: -10`.
                anchors.topMargin: -Metrics.px(9)
                anchors.bottomMargin: -Metrics.px(9)
                hoverEnabled: true

                function update(mouseX) {
                    root.valueMoved(root.clamp01(mouseX / width));
                }

                onPressed: function(mouse) {
                    root.interactionStarted();
                    update(mouse.x);
                }
                onPositionChanged: function(mouse) {
                    if (pressed)
                        update(mouse.x);
                }
                onReleased: root.commitRequested()
                onCanceled: root.cancelRequested()
            }
        }
    }
}
