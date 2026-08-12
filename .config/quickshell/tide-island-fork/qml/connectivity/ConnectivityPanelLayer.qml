import QtQuick

// FORK: one shared scale factor for every island surface.
import "../common/Metrics.js" as Metrics
// FORK: the shared motion system — one spring for geometry, one critically
// damped curve for opacity. See qml/common/Motion.js.
import "../common/Motion.js" as Motion

//
// FORK — new file. The Wi-Fi and Bluetooth lists as ISLAND STATES.
//
// ---- WHAT THIS REPLACES, AND WHY THE OLD SHAPE WAS WRONG ----
//
// ConnectivityDetailShell.qml (deleted with this file's arrival) positioned
// the same ConnectivityDetailPanel by reading the capsule's geometry:
// capsuleX, capsuleWidth, a shownX clamped against the screen edge, a
// hiddenX 28 px inside the capsule, and a Scale transform whose origin was
// `Math.min(height - 32, Math.max(36, capsuleHeight - 215))`. Every one of
// those numbers exists to make a rectangle hang off the SIDE of the control
// centre. It was a wing, not a surface: it could only be opened from the
// control centre, it inherited its vertical origin from a panel it was not
// part of, and on a 1366 px panel the left-hand one was already pushed
// against Metrics.pad(16) by its own clamp.
//
// Asked for directly: the Wi-Fi and Bluetooth lists should be their own
// popups, the way the wallpaper picker and the theme picker are. Those two
// are not positioned at all — they ARE the capsule. The shape morphs to the
// panel's size and the panel fills it, which is the whole idea the notch is
// built on ("states of the one shape", DESIGN-SPEC.md), and it is why they
// need no geometry of their own.
//
// So this file is deliberately thin. It is the same wrapper every other
// island layer is: a FocusScope that fills the capsule, fades on
// showCondition through the shared choreography, publishes a preferredHeight
// for the capsule to size itself from, and forwards closeRequested. The
// panel it wraps is unchanged apart from one property — see drawBackground
// below.
//
FocusScope {
    id: root

    signal closeRequested()

    property string panelKind: "wifi"
    property var provider: null
    property bool showCondition: false
    property string iconFontFamily: ""
    property string textFontFamily: ""
    property string heroFontFamily: ""

    // The height the capsule morphs to. The old wing was Metrics.px(404)
    // tall and that number is kept rather than recomputed: it is not a
    // content measurement — a network list has no fixed row count — it is a
    // frame that scrolls, chosen so a Wi-Fi list shows about seven networks
    // before it starts flicking. The host clamps it against the screen, as
    // it does for every other content-sized panel.
    //
    // Deliberately NOT sized to the number of networks in range. That count
    // changes on every rescan, and a panel that changed height each time
    // nmcli answered would walk the row under the cursor out from under it.
    // Same argument PickerLayer's preferredHeight makes about filtering.
    readonly property real preferredHeight: Metrics.px(404)

    anchors.fill: parent
    focus: showCondition
    opacity: showCondition ? 1 : 0

    // FORK: one choreography for every layer in the shell. Same block as
    // ThemePickerLayer and the rest — the delay is what keeps the content
    // from being painted inside a capsule that is still the wrong size for
    // it.
    Behavior on opacity {
        SequentialAnimation {
            PauseAnimation { duration: root.showCondition ? Motion.contentDelay() : 0 }
            NumberAnimation {
                duration: root.showCondition ? Motion.fadeInDuration() : Motion.fadeOutDuration()
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Motion.fade()
            }
        }
    }

    // Called by the host from the Loader's onLoaded, exactly as the
    // wallpaper picker and the application launcher are focused.
    //
    // It cannot be left to the panel's own onKeyboardActiveChanged: the
    // Loader builds the item with keyboardActive ALREADY true, so that
    // handler never fires on the open that matters. The panel keeps its
    // handler anyway for the case where the host toggles the flag on a live
    // item; this is the path that actually runs.
    function grabKeyboardFocus() {
        root.forceActiveFocus();
        panel.forceActiveFocus();
    }

    ConnectivityDetailPanel {
        id: panel

        anchors.fill: parent
        provider: root.provider
        panelKind: root.panelKind
        iconFontFamily: root.iconFontFamily
        textFontFamily: root.textFontFamily
        heroFontFamily: root.heroFontFamily

        // The capsule is the surface now, and it is already painted in
        // IslandTheme.shellFill at the user's islandBackgroundOpacity. The
        // panel's own rounded fill would be a second copy of the same
        // material at a different radius (28 against the capsule's 34) and a
        // different alpha (a flat 0.97), which shows up as four pale corner
        // wedges where the smaller radius cuts inside the larger one.
        //
        // Turning it off rather than deleting it: the fill still has to
        // exist for the panel to be instantiable on its own, and it is the
        // line that answers "the popup should be the island's colour, not a
        // fixed near-black". That reasoning now lives one level up, in the
        // capsule, which is where it was always trying to get to.
        drawBackground: false

        // Fully presented. presentationProgress existed to cross-fade the
        // content against the wing's scale-in; the capsule's own morph plus
        // this layer's opacity Behavior do that job now, and a second fade
        // riding on top of them was double-dipping.
        presentationProgress: 1

        // Gated on showCondition and NOT on the Loader being alive.
        // PanelLoader deliberately keeps a dismissed layer mounted for the
        // length of its fade-out (that is the bug it exists to fix), so
        // "mounted" outlives "open" by ~200 ms. A panel that still answered
        // j/k during that window would be taking keys the user meant for the
        // window behind. This is the same distinction ConnectivityDetailShell
        // drew between `open` and `mounted`, carried across unchanged.
        keyboardActive: root.showCondition

        onCloseRequested: root.closeRequested()
    }
}
