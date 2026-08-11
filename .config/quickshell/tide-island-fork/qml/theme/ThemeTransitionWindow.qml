pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Qt5Compat.GraphicalEffects

//
// FORK — new file. The circular theme-change animation: REQUIREMENTS.md
// item 5, which depended on both the shell (item 1) and the Hyprland theme
// target (item 4) and could not be written until both existed.
//
// WHAT IT DOES
// ------------
// Freezes the current desktop as an image above everything, runs theme-apply
// underneath it, then erases that frozen frame with a circle growing from the
// centre — so the new theme is revealed rather than switched to. The old
// screen is what gets destroyed; the new one was always there.
//
// The technique is Aylur's Marble Shell (AGS/GTK4), which cannot be ported —
// there is no code path between GTK4 and QML. Only the sequence is borrowed.
//
// THE FIVE TRAPS, all from the notch video's author, who hit each one
// -------------------------------------------------------------------
// He built the same capture-freeze trick for his lock screen and named every
// mistake. They are not optional polish; four of the five are the difference
// between this reading as an effect and reading as a glitch.
//
// 1. JPEG q85, NEVER png. PNG encoding a 2560x1440 desktop cost him ~850 ms,
//    which is longer than the whole animation. The image is annihilated by
//    the mask a few frames later, so every artifact is gone before your eye
//    reaches it: "lossless is worthless when the very thing you do is destroy
//    the detail on purpose."
//
// 2. A SAFETY TIMER. If grim hangs or is missing, proceed anyway. Fail
//    closed, never block on a screenshot — a theme change that silently does
//    nothing because a screenshot tool is wedged is far worse than a theme
//    change with no animation. `safetyTimer` below, and `beginReveal` is
//    idempotent so whichever of the two fires first wins.
//
// 3. ONE BOOLEAN drives everything. He wrote two code paths for the two
//    directions and got a black flash going in and a lingering frame coming
//    out. Here `active` is the only state; every visual property reads off
//    it, so there is no second path to disagree.
//
// 4. A ~90 ms DELAY before animating. The first frame is heavy — JPEG decode
//    plus the OpacityMask's shader compile — and if it lands inside the
//    animation the whole thing stutters at exactly the moment it should be
//    smooth. Do the expensive frame while nothing is moving.
//
// 5. HIDDEN ITEMS SIT AT BARELY ABOVE ZERO, not at zero, because Qt skips
//    buffer allocation for a fully transparent item and you pay for it on the
//    frame it becomes visible. The exception is on the way OUT, which goes to
//    true zero — otherwise you catch a ghost frame of the old desktop.
//
PanelWindow {
    id: root

    required property var themeApplyPath

    // One window per screen, so each output freezes and reveals its OWN
    // desktop — a single fullscreen surface would only ever cover one of
    // them. Exactly one of them runs theme-apply, though: the script is not
    // idempotent-cheap (it regenerates a dozen config files and reloads as
    // many programs) and running it once per monitor would be a second and
    // third repaint racing the first.
    property bool ownsThemeApply: true
    property string outputName: ""

    // THE single boolean. See trap 3.
    property bool active: false
    property string pendingTheme: ""
    property string capturePath: ""
    property real holeRadius: 0

    signal finished(string theme)

    visible: active
    color: "transparent"

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-theme-transition"
    // No keyboard focus and no input region at all. This covers the entire
    // screen for the better part of a second; taking either would mean a
    // click or a keystroke during a theme change goes nowhere, which is a
    // much worse bug than the one it would be protecting against.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    mask: Region {}

    readonly property real maximumRadius:
        Math.sqrt(root.width * root.width + root.height * root.height) / 2

    // --- sequence ----------------------------------------------------------
    function begin(themeName) {
        if (root.active || themeName === "")
            return;
        root.pendingTheme = themeName;
        // Per-run filename. A fixed one lets a second transition read the
        // previous run's file if grim has not finished writing this one, and
        // what you see is the desktop from the LAST theme change — which
        // looks like the animation running backwards.
        root.capturePath = "/tmp/tide-theme-transition-" + Date.now() + ".jpg";
        root.revealStarted = false;

        // JPEG, quality 85. Trap 1.
        // -o <output>: capture THIS screen only. Without it grim writes
        // every output into one image and each overlay would show its
        // neighbour's desktop stretched across it.
        captureProcess.command = root.outputName === ""
            ? ["grim", "-t", "jpeg", "-q", "85", root.capturePath]
            : ["grim", "-o", root.outputName, "-t", "jpeg", "-q", "85", root.capturePath];
        captureProcess.running = true;
        safetyTimer.restart();
    }

    property bool revealStarted: false

    function beginReveal(haveCapture) {
        // Idempotent: grim finishing and the safety timer firing are a race
        // by design, and both call this.
        if (root.revealStarted)
            return;
        root.revealStarted = true;
        safetyTimer.stop();

        if (!haveCapture) {
            // Fail closed. No frozen frame, so no animation — but the theme
            // still changes, which is the part that was actually asked for.
            root.applyTheme();
            root.finish();
            return;
        }

        root.holeRadius = 0;
        root.active = true;
        // Trap 4: let the decode and the shader compile happen on a frame
        // where nothing needs to move.
        warmupTimer.restart();
    }

    function applyTheme() {
        if (root.pendingTheme === "" || !root.ownsThemeApply)
            return;
        applyProcess.command = [String(root.themeApplyPath), root.pendingTheme];
        applyProcess.running = true;
    }

    function finish() {
        const theme = root.pendingTheme;
        root.active = false;
        root.pendingTheme = "";
        root.holeRadius = 0;
        if (root.capturePath !== "") {
            cleanupProcess.command = ["rm", "-f", root.capturePath];
            cleanupProcess.running = true;
            root.capturePath = "";
        }
        root.finished(theme);
    }

    Process {
        id: captureProcess
        onExited: function(exitCode) {
            running = false;
            root.beginReveal(exitCode === 0);
        }
    }

    Timer {
        id: safetyTimer
        interval: 700
        repeat: false
        onTriggered: {
            // grim is still going, or is not there at all. Do not wait on it.
            // The capture may still land later and would then be a stale file
            // nobody reads; cleanupProcess removes it either way.
            root.beginReveal(false);
        }
    }

    Timer {
        id: warmupTimer
        interval: 90
        repeat: false
        onTriggered: {
            // The theme is applied UNDER the frozen frame, so the repaint
            // happens where it cannot be seen and the reveal shows a desktop
            // that has already finished changing. Applying it after the
            // animation would show the old desktop through the hole.
            root.applyTheme();
            revealAnimation.restart();
        }
    }

    NumberAnimation {
        id: revealAnimation
        target: root
        property: "holeRadius"
        from: 0
        to: root.maximumRadius
        // 620 ms across the diagonal of a 1366x768 panel is ~1.3 screen
        // widths a second — fast enough not to be a wait, slow enough that
        // the circle reads as a circle rather than as a flash.
        duration: 620
        easing.type: Easing.InOutQuad
        onFinished: root.finish()
    }

    Process { id: applyProcess }
    Process { id: cleanupProcess }

    // --- the frozen frame --------------------------------------------------
    Item {
        id: frozenFrame
        anchors.fill: parent
        visible: false

        Image {
            anchors.fill: parent
            source: root.capturePath === "" ? "" : "file://" + root.capturePath
            fillMode: Image.PreserveAspectCrop
            cache: false
            asynchronous: false
        }
    }

    // The mask. Its ALPHA is what OpacityMask reads, so the circle is opaque
    // black and everything else is nothing — with `invert: true` that makes
    // the circle the hole and the rest the surviving screenshot.
    Item {
        id: revealMask
        anchors.fill: parent
        visible: false
        layer.enabled: true

        Rectangle {
            anchors.centerIn: parent
            width: root.holeRadius * 2
            height: root.holeRadius * 2
            radius: root.holeRadius
            color: "black"
        }
    }

    OpacityMask {
        anchors.fill: parent
        source: frozenFrame
        maskSource: revealMask
        invert: true
        // Trap 5: barely above zero while idle so Qt allocates the buffers,
        // true zero only once the reveal has finished and the item is on its
        // way out.
        opacity: root.active ? 1 : (root.revealStarted ? 0 : 0.004)
        cached: false
    }
}
