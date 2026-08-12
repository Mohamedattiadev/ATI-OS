import QtQuick

// ProgressRing lives here — the shared ring the countdown and the volume
// OSD draw. Importing the DIRECTORY, not the file: a QML component is
// reached through its module path, and only the two .js helpers below are
// imported by filename.
import "../common"
import "../common/Metrics.js" as Metrics
import "../common/Motion.js" as Motion

//
// FORK — new file. One ring per open window, in the empty bar beside the
// notch: the first window left, the second right, the third left again.
//
// WHY ALTERNATING AND NOT "ALL ON ONE SIDE"
// -----------------------------------------
// Asked for directly — two terminals should read as one ring on each flank.
// It also happens to be the only split that keeps the island symmetric
// without needing to know anything about the windows: any rule that sorts
// by workspace, or by app, or by age makes the two sides different lengths
// and the notch stops sitting in the middle of its own furniture.
//
// The parity is on the INDEX in the source list, and this component filters
// for its own side rather than being handed a pre-split array. Two strips
// reading the same list with opposite parity cannot disagree; two arrays
// built by a parent can, and the failure is a window that appears on both
// sides or on neither.
//
// WHERE THE LIST COMES FROM
// -------------------------
// Quickshell.Wayland's ToplevelManager, not `hyprctl clients`. It is the
// foreign-toplevel protocol, so it is live — an ObjectModel that updates on
// open/close with no polling — and it carries appId and title directly.
//
// Measured caveat, because it cost a probe to find: ToplevelManager reports
// ZERO toplevels until the shell owns a real surface. A ShellRoot with no
// PanelWindow gets an empty list forever and no warning, which reads exactly
// like "this compositor does not support the protocol". The island has
// surfaces, so this is only a trap for the throwaway instance you test in.
//
// NOT INTERACTIVE: the island's input Region is mainCapsule's rectangle
// alone, so everything out here is drawn and unclickable. A ring you could
// click would need the mask widened, and a full-width clickable strip at the
// top of the screen eats desktop clicks for the whole session.
//
Item {
    id: root

    // Array of { appId, title, active }.
    property var windows: []
    // "left" takes the even indices, "right" the odd ones.
    property string side: "left"
    property real revealProgress: 1
    property bool showCondition: true
    property string textFontFamily: ""
    property color accentColor: "#51afef"
    property color fillColor: "#1a1a1a"

    readonly property int parity: side === "left" ? 0 : 1

    readonly property var mine: {
        const picked = [];
        const source = windows || [];
        for (let index = 0; index < source.length; index++) {
            if (index % 2 === parity)
                picked.push(source[index]);
        }
        // The left strip grows AWAY from the notch, so its first window has
        // to sit nearest the pill — that is the right-hand end of a Row.
        // Reversing here rather than mirroring the layout keeps the ring
        // contents upright; LayoutMirroring would flip the glyphs too.
        return side === "left" ? picked.reverse() : picked;
    }

    implicitWidth: strip.implicitWidth
    implicitHeight: Metrics.px(22)

    opacity: showCondition ? revealProgress : 0
    visible: opacity > 0.01 && mine.length > 0

    Behavior on opacity {
        NumberAnimation {
            duration: root.showCondition ? Motion.fadeInDuration() : Motion.fadeOutDuration()
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Motion.fade()
        }
    }

    // A stable hue per application, so the two kitty rings match each other
    // and neither matches brave. Hashing the appId rather than assigning
    // from a palette in order: order changes every time a window opens, and
    // a ring that changes colour when an unrelated window closes is worse
    // than no colour at all.
    function hueFor(appId) {
        let hash = 0;
        const text = String(appId || "?");
        for (let index = 0; index < text.length; index++)
            hash = (hash * 31 + text.charCodeAt(index)) & 0xffffffff;
        return (Math.abs(hash) % 360) / 360.0;
    }

    function initialFor(appId) {
        const text = String(appId || "?").replace(/^org\./, "");
        return text.length ? text.charAt(0).toUpperCase() : "?";
    }

    Row {
        id: strip
        anchors.verticalCenter: parent.verticalCenter
        spacing: Metrics.px(5)

        Repeater {
            model: root.mine

            // ---- THE RING IS ProgressRing, NOT A BORDERED Rectangle ----
            //
            // The first version drew each window as a circle with a coloured
            // border, and it read as a row of buttons rather than as part of
            // this shell. The ring that already looks right here is the one
            // the countdown and the volume OSD use — dark core disc, a track
            // circle, and an arc from twelve o'clock with round caps. It was
            // extracted into qml/common/ProgressRing.qml precisely so more
            // than one thing could draw it, and this is the second thing.
            //
            // A window has no natural 0..1 quantity, so the arc is used for
            // the one binary fact worth showing: the FOCUSED window sweeps a
            // full circle, everything else sweeps none. The app's colour
            // still identifies an unfocused ring, because it is carried in
            // the TRACK rather than in the arc — without that, progress 0
            // would leave every inactive ring an identical grey.
            delegate: ProgressRing {
                required property var modelData

                readonly property color appColor: Qt.hsla(root.hueFor(modelData.appId),
                                                          0.55, 0.66, 1.0)
                readonly property bool isActive: !!modelData.active

                // ---- MATCHED TO THE COUNTDOWN RING, NOT APPROXIMATED ----
                //
                // The first pass used ProgressRing but kept showCore on, and
                // the dark disc is what made these read as filled coins with
                // a letter stamped on them rather than as rings. The ring
                // being copied is the timer's — DisplayPanel.qml's
                // revertRing, the one that appears when a countdown is armed
                // — and its parameters are: 26 px, lineWidth 2.5, showCore
                // FALSE, and a track that is the SAME hue as the fill at
                // about a fifth alpha (#33ffcc66 over #ffcc66). The hole in
                // the middle is the whole idea; filling it in was the bug.
                width: Metrics.px(26)
                height: width
                lineWidth: 2.5
                showCore: false

                progress: isActive ? 1 : 0
                Behavior on progress {
                    NumberAnimation {
                        duration: Motion.morphDuration()
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Motion.spring()
                    }
                }

                fillColor: appColor
                // The timer ring's ratio is 0.20. Unfocused rings hold 0.45
                // rather than 0.20 because that ring sits on a dark panel and
                // these sit on the wallpaper, where a fifth-alpha stroke
                // stops being a stroke. The focused ring still separates
                // cleanly: it lays a full-strength arc over its own track.
                trackColor: Qt.rgba(appColor.r, appColor.g, appColor.b,
                                    isActive ? 0.20 : 0.45)

                Text {
                    anchors.centerIn: parent
                    text: root.initialFor(modelData.appId)
                    color: modelData.active
                        ? appColor
                        : Qt.rgba(appColor.r, appColor.g, appColor.b, 0.92)
                    font.pixelSize: Metrics.font(9)
                    font.family: root.textFontFamily
                    font.weight: Font.DemiBold
                }
            }
        }
    }
}
