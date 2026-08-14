pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
// No `import Quickshell.Wayland` — backend-neutral BASE, must load under X11.
// ThemeTransitionWindowWayland.qml carries the layer-shell half.
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
//    smooth. Do the expensive frame while nothing is moving. `warmupTimer`
//    below still owns that delay; what it no longer owns is the start of the
//    sweep, for the reason in the sixth trap.
//
// 5. HIDDEN ITEMS SIT AT BARELY ABOVE ZERO, not at zero, because Qt skips
//    buffer allocation for a fully transparent item and you pay for it on the
//    frame it becomes visible. The exception is on the way OUT, which goes to
//    true zero — otherwise you catch a ghost frame of the old desktop.
//
// THE SIXTH TRAP, which is this machine's own
// -------------------------------------------
// 6. THE SWEEP MUST WAIT FOR theme-apply, NOT FOR A TIMER. warmupTimer used
//    to call applyTheme() and revealAnimation.restart() on the SAME tick, so
//    the frozen frame was guaranteed to be gone 620 ms later no matter what
//    the script was doing. Nothing in this file ever read applyProcess's
//    exit — it had no onExited at all.
//
//    Measured on this machine (1366x768, 4 cores): theme-apply takes 1.6 s
//    idle with the browser restart skipped, 3.7–9.6 s under load with it,
//    median ~5 s. That is 3 to 15 times the length of the sweep. So the
//    frozen frame was always swept away mid-change and the remaining two
//    thirds of the theme then popped in AFTER the animation had ended —
//    which is the exact opposite of the effect's whole premise, that the new
//    screen was always there and only the old one gets destroyed. Reported
//    as "the animation finishes before it fully changed the theme".
//
//    The reveal is now gated on theme-apply, in the idempotent-race shape
//    beginReveal() already used: `sweepStarted` is the boolean, and the
//    script's signal and `applyCapTimer` both call beginSweep(), whichever
//    gets there first. The cap exists because a hung or missing theme-apply
//    must never leave a fullscreen frozen frame on the desktop forever.
//
// THE SEVENTH TRAP, which is the sixth one's own bill
// ----------------------------------------------------
// 7. "theme-apply HAS EXITED" IS NOT "THE DESKTOP HAS FINISHED CHANGING",
//    and gating on the exit bought correctness by paying five seconds of
//    dead screen for it. Reported the same day as "the theming thing is
//    still too clunky, the change animation" — and it was worse than the
//    bug it replaced, because a wipe that lands early is a wrong-looking
//    animation whereas this was a desktop that appeared to have HUNG.
//
//    Measured, one theme change, timed grim frames diffed against each
//    other (`magick compare -metric RMSE`), overlay map/unmap taken from
//    Hyprland's socket2 openlayer/closelayer rather than by polling:
//
//        t=  155 ms   overlay maps, frozen frame up
//        t=  537 ms   last change of any kind
//        t=  888 ms   \
//        ...           |  d(prev) = 0.00, TWELVE consecutive frames,
//        t= 4039 ms   /   3.5 seconds of a literally identical image
//        t= 4293 ms   the sweep finally starts
//        t= 5051 ms   overlay unmaps
//
//    Not "barely moving" — a pixel difference of exactly zero, for three
//    and a half seconds, on a fullscreen surface.
//
//    The fix is that the script now says when the VISIBLE part is done
//    instead of only when it is done. theme-apply prints one line,
//    THEME_APPLY_VISIBLE_DONE, at the point past which everything it still
//    has to do is invisible under a frozen frame — the Chromium theme
//    repack, the brave/chrome kill-and-relaunch, firefox's userChrome, and
//    a backgrounded initramfs rebuild. Two thirds of its runtime, and none
//    of it repaints a window that is on screen: a killed browser does not
//    repaint, it vanishes and returns seconds later on its own schedule,
//    which no overlay of any length can cover.
//
//    Measured with the marker, same clock and same method:
//
//        t=  174 ms   overlay maps
//        t=  858 ms   \  d(prev) = 0.00, the static stretch, now 960 ms
//        t= 1818 ms   /   instead of 3151 ms
//        t= 2122 ms   the sweep runs
//        t= 2485 ms   overlay unmaps
//        t= 4106 ms   theme-apply finally exits, behind a live desktop
//
//    Overlay lifetime 4896 -> 2311 ms, static stretch 3151 -> 960 ms, and
//    the sweep now starts 2.5 s before the script it used to wait for.
//
//    And the sweep still does not lie about what it is revealing: the
//    frame right after the wipe differs from the fully settled desktop by
//    an RMSE of 0.76, which is the clock digits and the cursor. The
//    desktop under the frozen frame really had finished changing — at
//    622 ms, in fact, measured by running theme-apply bare against timed
//    frames, which is 836 ms before the marker even fires. See settleTimer.
//
//    The exit is KEPT as a fallback, not deleted — an older theme-apply,
//    or one that dies under `set -e` before the marker, prints nothing and
//    must still reveal without waiting for the cap.
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

    // Where grim WILL write (capturePath) versus what the Image is allowed to
    // read (frozenSource). They are deliberately two properties; see the note
    // on the Image below.
    property string frozenSource: ""

    // 0 = the frozen frame is untouched, 1 = it has been swept away entirely.
    property real sweep: 0

    signal finished(string theme)

    visible: active
    color: "transparent"

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    // ---- IT MUST BE LAID OUT AGAINST THE OUTPUT, NOT AGAINST WHAT IS LEFT ----
    //
    // This read `exclusiveZone: 0`, and that is the SAME one-line bug
    // ScreenCornersWindow.qml already documents at length — including the
    // detail that writing `exclusiveZone` at all is what causes it, because
    // assigning it puts the window into Normal mode and Normal mode is laid
    // out inside other surfaces' reservations. Being explicit about claiming
    // nothing does not claim nothing; it opts into the thing being avoided.
    //
    // Measured here, sampling `hyprctl layers -j` through a real change:
    //
    //     L2 quickshell                  1366x58  @ 0,0     the island
    //     L3 quickshell-theme-transition 1366x735 @ 0,33    the cover
    //
    // 33 px is the island's own exclusive zone, and a cover that starts 33 px
    // down the screen produces every symptom the user reported, in one:
    //
    //   * "the island glitch" — the frozen frame is a FULL-SCREEN 1366x768
    //     grab drawn into a 1366x735 box at y=33, so the island inside the
    //     image lands 33 px below the live island it is supposed to be
    //     hiding. You see the notch twice, one ghosted under the other.
    //   * "a small part of new theme" — the top 33 px of the island is never
    //     covered at all, so it repaints LIVE the moment theme-apply writes
    //     colors.json at 0.11 s, while the other 735 px stay frozen on the
    //     old palette for another second and a half.
    //   * "and then changes" — the sweep, arriving long afterwards.
    //
    // So the cover was never covering the one surface that sits above the
    // whole desktop. Verified after the change: 1366x768 @ 0,0.
    exclusionMode: ExclusionMode.Ignore
    // FORK: the WlrLayershell lines moved to ThemeTransitionWindowWayland.qml
    // so this file stays loadable under X11 — see ../common/BackendSurface.md.
    // Focus is set per-backend in the two wrappers rather than as a generic
    // `focusable` here, DELIBERATELY: on Wayland `focusable` and
    // `WlrLayershell.keyboardFocus` both drive the same layer-shell field, and
    // setting one in the base and the other in the wrapper leaves which wins
    // to evaluation order. One owner per backend, no interaction to reason
    // about. Either way the answer is "none" — this surface covers the whole
    // screen for the better part of a second, and taking a keystroke during a
    // theme change is a worse bug than the one it protects against.
    //
    // The input region IS generic, and stays here: no rects = nothing
    // interactive, on both backends.
    mask: Region {}

    // ---- THE SWEEP GEOMETRY -------------------------------------------------
    //
    // This used to be a circle growing from the centre (Aylur's Marble Shell).
    // It is now a diagonal wipe, because the ask was for the theme change to
    // animate "like the wallpaper change does" and the wallpaper change is not
    // a circle. hypr/scripts/wallpaper-sync.sh drives awww with
    //
    //     --transition-type wave --transition-angle 30
    //     --transition-wave "60,30" --transition-fps 60 --transition-step 90
    //
    // so what the eye has been trained on by every wallpaper change on this
    // machine is a front crossing the screen at 30 degrees. Matching the ANGLE
    // is what makes the two read as the same gesture; see the note on
    // wavefront below for the part of awww's wave that is deliberately not
    // reproduced.
    readonly property real sweepAngle: 30

    // How far the front must travel to clear the screen: the screen's extent
    // measured along the sweep axis, which for a rotated rectangle is
    // W|cos| + H|sin| -- NOT the diagonal. Using the diagonal would overshoot
    // by ~200px here and spend the last fifth of the animation with the screen
    // already fully cleared, which reads as the effect hanging at the end.
    readonly property real sweepLength: {
        const r = root.sweepAngle * Math.PI / 180;
        return root.width * Math.abs(Math.cos(r))
             + root.height * Math.abs(Math.sin(r));
    }

    readonly property real diagonal:
        Math.sqrt(root.width * root.width + root.height * root.height)

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
        root.sweepStarted = false;

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

    // The second of the two races, and deliberately a SECOND boolean rather
    // than a reuse of revealStarted: that one means "the frozen frame is up
    // and grim is no longer being waited on", this one means "the frame is on
    // its way out". Between them is the window in which theme-apply runs, and
    // it is the whole point of the file. Collapsing them into one flag is what
    // the old code effectively did.
    property bool sweepStarted: false

    // Emitted by the window that owns theme-apply, once the script has exited.
    // shell.qml relays it to every other output's window, because those never
    // run applyProcess and so have no exit of their own to wait on; see
    // noteThemeApplied().
    signal themeApplied()

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

        root.sweep = 0;
        // Only now, with the file known to be on disk and grim exited 0.
        root.frozenSource = root.capturePath;
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

    // theme-apply has finished. Called on THIS window by applyProcess's own
    // onExited, and on every other output's window by shell.qml relaying
    // themeApplied() — a window with ownsThemeApply false has no process of
    // its own and would otherwise sit frozen until the cap fired, revealing
    // seconds after its neighbour.
    //
    // Not straight to beginSweep(): the script exits when it has finished
    // WRITING configs and sending reloads, and the reloaded programs repaint
    // slightly after that. See settleTimer.
    function noteThemeApplied() {
        if (!root.active || root.sweepStarted || settleTimer.running)
            return;
        settleTimer.restart();
    }

    function beginSweep() {
        // Idempotent, exactly as beginReveal() is: the script exiting and the
        // cap timer firing are a race by design and both land here.
        if (root.sweepStarted)
            return;
        root.sweepStarted = true;
        applyCapTimer.stop();
        settleTimer.stop();
        revealAnimation.restart();
    }

    function finish() {
        const theme = root.pendingTheme;
        root.active = false;
        root.pendingTheme = "";
        root.sweep = 0;
        applyCapTimer.stop();
        settleTimer.stop();
        // Released before the file is deleted below, so the Image is not
        // holding a path that cleanupProcess is about to remove.
        root.frozenSource = "";
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
            // Trap 4's delay, and now ONLY trap 4's delay. The theme is
            // applied UNDER the frozen frame, so the repaint happens where it
            // cannot be seen and the reveal shows a desktop that has already
            // finished changing. Applying it after the animation would show
            // the old desktop through the hole.
            //
            // The sweep is NOT started here. It used to be, on this same
            // tick, and that is the sixth trap: 90 ms + 620 ms is a promise
            // about theme-apply that theme-apply cannot keep. beginSweep()
            // is reached from applyProcess.onExited or from applyCapTimer.
            root.applyTheme();
            // Started unconditionally, including on the outputs where
            // applyTheme() just returned without doing anything: the cap is
            // the only thing that is guaranteed to fire on every window.
            applyCapTimer.restart();
        }
    }

    Timer {
        id: settleTimer
        // A signal from theme-apply is not the last repaint: it means
        // "configs written, reloads SENT", and Hyprland, kitty and dunst each
        // repaint on their own next frame. This absorbs that tail.
        //
        // It was 260 ms, measured against the script's EXIT: the script
        // exited at 1974 ms, the bulk of the visible swap landed at 2078 ms,
        // and the frame difference reached its noise floor at 2269 ms — a
        // 100–300 ms tail, because the last reloads were dispatched moments
        // before that exit.
        //
        // The gate is now the visible-repaint marker, which sits ~2.5 s
        // EARLIER in the script, so the tail had to be re-measured rather
        // than inherited. Ran theme-apply bare with no overlay at all,
        // timestamping its marker line on stdout against timed grim frames of
        // the real desktop, and diffed every frame against the settled one:
        //
        //     t= 182 ms   d=9.55   hyprctl reload landing
        //     t= 622 ms   d=0.86   <- the visible swap is DONE here
        //     t= 755..1605         d flat at 0.86-0.98 (clock digits, cursor)
        //     marker at 1458 ms
        //
        // The desktop stopped changing 836 ms BEFORE the marker, not after
        // it. That is not luck: the last dispatch that repaints an
        // already-open window (dunst restart, GTK settings.ini) happens at
        // 1.10 s, so the marker at ~1.3-1.5 s already absorbs ~350 ms of its
        // own settle.
        //
        // So the honest requirement here is close to zero, and 140 ms is
        // slack rather than a measured need — a handful of frames against a
        // machine more loaded than this one was. Charged only on the
        // signalled path; the cap path skips it, having already waited far
        // longer.
        interval: 140
        repeat: false
        onTriggered: root.beginSweep()
    }

    Timer {
        id: applyCapTimer
        // THE HARD CAP. Not a tuning knob — a guarantee that a theme-apply
        // that hangs, or that is not on disk at all, cannot leave a
        // fullscreen frozen screenshot sitting on the user's desktop for the
        // rest of the session. Whichever of this and theme-apply's marker
        // arrives first wins; beginSweep() is idempotent.
        //
        // 12 s when the gate was the script's EXIT, sized against a whole run
        // (1.6 s idle, 3.7–9.6 s under load — the tail being the browser
        // kill, .crx repack and relaunch). The gate is now the marker, and
        // the marker is reached at 1.27–1.46 s measured, so the cap is
        // guarding a much shorter stretch of script and 12 s of frozen
        // desktop is no longer a proportionate failure mode.
        //
        // 8 s, and the number is set by the SECOND click, not the first.
        // Measured marker times on this machine:
        //
        //     settled, 5 kitty + brave + qutebrowser up ... 1.27–1.46 s
        //     second theme change fired while the previous
        //     one's brave relaunch was still starting ..... 4.57 s, 5.21 s
        //
        // The slow case is self-inflicted and unavoidable: every apply kills
        // and relaunches brave, so flicking through themes — which
        // theme-apply's own comments call out as the expected way to use it
        // — means each run's pgreps and hyprctl calls land on a box that is
        // busy starting twelve brave processes. 4x the settled path.
        //
        // Everything else before the marker is bounded or backgrounded: the
        // kitty fan-out is `timeout 1` in parallel behind one `wait`; dunst
        // is a fixed `sleep 0.2`; papirus-folders, the eww restart, the file
        // manager and the qtile restart are all `& disown` or `setsid -f`
        // and cannot hold it. So 8 s is ~55% over the worst run seen rather
        // than the ~25% the old 12 s allowed itself, because a cap that
        // fires is the sixth trap coming back for one theme change and the
        // rapid-switch case must not trip it.
        interval: 8000
        repeat: false
        onTriggered: {
            // Straight to the sweep, not via noteThemeApplied(): there is no
            // repaint to settle for, because as far as this window knows
            // nothing has happened yet.
            root.beginSweep();
        }
    }

    NumberAnimation {
        id: revealAnimation
        target: root
        property: "sweep"
        from: 0
        to: 1
        // 620 ms was tuned for the circle and is kept: over the 1567 px this
        // front has to travel it is ~2.5 screen widths a second, which is the
        // same order as awww's own wave at step 90 / 60 fps.
        duration: 620
        // LINEAR, where the circle used InOutQuad. A wipe and a circle want
        // different curves: a circle's area grows as r^2, so easing the radius
        // is what stops the middle of the animation from feeling like a burst.
        // A straight front covers area at a constant rate already, and easing
        // it makes the front visibly accelerate and brake — which awww does
        // not do. Constant velocity is what reads as "the same effect".
        easing.type: Easing.Linear
        onFinished: root.finish()
    }

    // The token theme-apply prints at its visible-repaint marker. Kept as a
    // property rather than inlined so the string that has to match the
    // script's `printf` is stated once, next to the comment that explains it.
    readonly property string visibleDoneToken: "THEME_APPLY_VISIBLE_DONE"

    Process {
        id: applyProcess
        // The thing that was missing. Without this the frozen frame had no
        // way of knowing the theme had changed and could only guess with a
        // timer; see the sixth trap.
        //
        // The exit code is deliberately ignored. theme-apply exiting non-zero
        // means part of the theme did not apply, which is a reason to show
        // the user the desktop, not a reason to keep it frozen. The only
        // question these handlers answer is "has the desktop finished
        // changing".

        // SplitParser and not StdioCollector, for the same reason
        // SystemMonitorPanel gives: a collector hands back its text once, at
        // EOF, which is precisely the event this is trying not to wait for.
        // The whole point is to hear a line while the process is still
        // running.
        //
        // The compare is against a trimmed line and an exact token, not a
        // prefix or a substring match. theme-apply's backgrounded children
        // (papirus-folders' notify-send fallback, the file-manager relaunch)
        // inherit this pipe, so this parser is not guaranteed to see only
        // lines the script meant to send it.
        stdout: SplitParser {
            onRead: function (line) {
                if (String(line).trim() !== root.visibleDoneToken)
                    return;
                root.noteThemeApplied();
                // The other outputs, which never ran the script; shell.qml
                // relays this to them. Emitted here rather than only at exit
                // so every screen sweeps on the same tick — a relay that
                // fired at exit would hold the second monitor's frozen frame
                // for the two seconds of browser restarts this marker exists
                // to skip.
                root.themeApplied();
            }
        }

        // THE FALLBACK, not the gate. It still has to exist: a theme-apply
        // that dies under `set -e` before reaching the marker, or an older
        // copy of the script that does not print one at all, must not strand
        // the overlay on the cap. noteThemeApplied() is idempotent, so on the
        // normal path — marker at 1.27 s, exit at 3.39 s — this is a no-op
        // that runs after the sweep has already finished.
        //
        // The thing that could have sunk this and does not: theme-apply's
        // last act is to background `boot-splash generate && boot-splash
        // autosync`, which rebuilds the initramfs and therefore OUTLIVES its
        // parent by minutes — a `theme-apply` from four minutes ago is still
        // visible in ps with a boot-splash child. That grandchild inherits
        // this Process's stdout and stderr, so if Quickshell waited for the
        // pipes to close rather than for the child to be reaped, onExited
        // would land minutes late. That would no longer delay the sweep, but
        // it WOULD leave `running` true, and applyTheme() assigns to
        // `command` — which Quickshell refuses on a running Process, so the
        // NEXT theme change would silently not run the script at all.
        // Measured with the pipe in place rather than assumed: marker at
        // 1.46 s, onExited at 4.11 s, matching theme-apply's own runtime.
        onExited: {
            running = false;
            root.noteThemeApplied();
            root.themeApplied();
        }
    }
    Process { id: cleanupProcess }

    // --- the frozen frame --------------------------------------------------
    Item {
        id: frozenFrame
        anchors.fill: parent
        visible: false

        // Bound to `frozenSource` and NOT to `capturePath`, and this is the
        // difference between the effect existing and not existing.
        //
        // `capturePath` is assigned at the TOP of begin(), because grim needs
        // to be told where to write before it is started. Binding the Image to
        // it therefore pointed the Image at a file that was, by construction,
        // guaranteed not to exist yet: Qt tried to open it on the spot, failed
        // with "Cannot open: file:///tmp/tide-theme-transition-<ts>.jpg" in
        // the log, and — because a failed Image does not retry when the file
        // later appears — never loaded it at all. The overlay then ran its
        // whole animation masking an image that was never there, which is
        // invisible. The theme changed, nothing moved, and nothing errored
        // loudly enough to notice; the only trace was one WARN per theme
        // change.
        //
        // `frozenSource` is assigned in beginReveal(), which only runs once
        // grim has exited 0, so the file is on disk before anything reads it.
        Image {
            anchors.fill: parent
            source: root.frozenSource === "" ? "" : "file://" + root.frozenSource
            fillMode: Image.PreserveAspectCrop
            cache: false
            asynchronous: false
        }
    }

    // The mask. Its ALPHA is what OpacityMask reads, so the swept region is
    // opaque black and everything else is nothing — with `invert: true` that
    // makes the swept region the hole and the rest the surviving screenshot.
    Item {
        id: revealMask
        anchors.fill: parent
        visible: false
        layer.enabled: true

        // THE FRONT.
        //
        // A plain Rectangle rotated to the sweep angle, translated along its
        // own local x. Order matters and is the whole trick: Translate is
        // listed FIRST, so the rotation is applied to the already-translated
        // geometry and the net motion is R(p + t*x) = R(p) + t*R(x) — i.e.
        // travel along the ROTATED axis, which is what a wipe at 30 degrees
        // is. Listing Rotation first instead gives a shape that slides
        // horizontally while sitting at an angle, which is a different and
        // much worse-looking effect.
        //
        // width is the sweep length so that sweep=1 covers exactly the
        // screen's extent along the axis and no more; height is 2x the
        // diagonal purely so the front is long enough that its ends never
        // come into view at any angle.
        //
        // ---- WHAT IS DELIBERATELY NOT REPRODUCED ----
        //
        // awww's front is not straight: --transition-wave "60,30" gives it a
        // 60 px period, 30 px amplitude sine edge. That is not reproduced
        // here, and the honest reason is the tooling rather than taste. A sine
        // edge in QML means either a ShaderEffect — which needs a precompiled
        // .qsb and therefore a build step this config does not have — or a
        // Canvas, which per this tree's own notes does not paint while its
        // item is invisible, and this mask is `visible: false` by
        // construction. A Repeater of ~260 thin slices would resolve a 60 px
        // period across 1567 px, and is the fallback if the straight edge ever
        // reads as too clean. At 60 px period on a 1366 px screen the ripple
        // is a fine detail; the angle is what carries the resemblance.
        Rectangle {
            id: wavefront
            anchors.centerIn: parent
            width: root.sweepLength
            height: root.diagonal * 2
            color: "black"
            transform: [
                Translate {
                    x: (root.sweep - 1) * root.sweepLength
                },
                Rotation {
                    origin.x: wavefront.width / 2
                    origin.y: wavefront.height / 2
                    angle: root.sweepAngle
                }
            ]
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
