import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Mpris
import IslandBackend
import "qml/audio"
import "qml/cheatsheet"
import "qml/common"
import "qml/controlcenter"
import "qml/connectivity"
import "qml/display"
import "qml/island"
import "qml/wifi"
import "qml/workspace"
// FORK: the motion system. Upstream hardcodes Easing.OutQuint / OutCubic
// durations inline; DESIGN-SPEC.md calls for a generated spring instead.
// Motion.js explains why there are two curves and not one — and carries a
// loud warning about Qt's undocumented 10-segment BezierSpline limit,
// which crashed the whole shell the first time this was attempted.
import "qml/common/Motion.js" as Motion
// FORK: one scale factor for every surface — see qml/common/Metrics.js.
// The island was resized to qtile's 28px bar height; changing the config
// alone reached only the fonts, because every panel dimension in here is a
// literal that UserConfig cannot see.
import "qml/common/Metrics.js" as Metrics

PanelWindow {
    id: root
    property var shellRootController: null
    property string overviewPhase: "closed"
    property bool overviewPreloading: false
    readonly property bool overviewPreparing: overviewPhase === "preparing"
    readonly property bool overviewVisible: overviewPhase === "preparing" || overviewPhase === "opening" || overviewPhase === "open"
    readonly property bool overviewMounted: overviewPhase !== "closed" || overviewPreloading
    readonly property bool overviewLoaderActive: !compositorIsNiri
        && (overviewMounted || overviewUnloadGraceTimer.running)
    readonly property bool overviewDataReady: overviewLoader.item
        ? !!overviewLoader.item.overviewDataReady
        : false
    readonly property bool overviewWallpaperReady: overviewWallpaperCache.ready
    readonly property bool overviewVisualReady: overviewDataReady && overviewWallpaperReady
    readonly property bool overviewContentVisible: (overviewPhase === "opening" || overviewPhase === "open")
        && overviewVisualReady
    readonly property bool compositorIsNiri: CompositorBackend.compositor === "niri"
    readonly property int compositorRevision: CompositorBackend.revision
    readonly property string screenOutputName: screen && screen.name !== undefined ? String(screen.name) : ""
    readonly property var hyprlandIntegration: hyprlandIntegrationLoader.item
    readonly property var hyprMonitor: hyprlandIntegration ? hyprlandIntegration.monitor : null
    readonly property string hyprMonitorName: hyprlandIntegration ? hyprlandIntegration.monitorName : ""
    readonly property string compositorOutputName: compositorIsNiri ? screenOutputName : hyprMonitorName
    readonly property bool monitorFocused: {
        compositorRevision;
        return compositorIsNiri
            ? CompositorBackend.isOutputFocused(screenOutputName)
            : (hyprlandIntegration ? hyprlandIntegration.monitorFocused : false);
    }
    readonly property bool connectivityPromptActive: controlCenterLoader.item
        ? controlCenterLoader.item.hasConnectivityPrompt
        : false
    readonly property var controlCenterRef: controlCenterLoader.item
    readonly property int currentMonitorWorkspaceId: {
        compositorRevision;
        return compositorIsNiri
            ? CompositorBackend.activeWorkspaceIndexForOutput(screenOutputName)
            : (hyprlandIntegration ? hyprlandIntegration.workspaceId : 1);
    }
    readonly property bool screenRecordingActive: shellRootController
        && shellRootController.screenRecordingActive !== undefined
        ? !!shellRootController.screenRecordingActive
        : false
    // Diagnostic for the flank workspace filter, off by default. Left in
    // because the filter fails OPEN: if it silently stopped filtering, the
    // strip would look merely busy rather than broken, and this is the only
    // thing that tells the two apart. Flip to true and read `qs log`.
    property bool flankDebug: false
    property bool autoHideVisible: false
    property bool autoHidePointerInside: false
    property bool autoHideForcedHidden: false
    property string autoHideRevealSource: "none"

    readonly property var userConfig: UserConfig

    Loader {
        id: hyprlandIntegrationLoader

        active: !root.compositorIsNiri
        asynchronous: false
        source: active ? "qml/island/HyprlandWindowIntegration.qml" : ""
    }

    Binding {
        target: hyprlandIntegrationLoader.item
        property: "screenObject"
        value: root.screen
        when: hyprlandIntegrationLoader.item !== null
    }

    color: StyleTokens.transparent
    anchors { top: true; left: true; right: true }
    mask: Region {
        // Input is the union of the island's visible surfaces plus a compact top
        // gesture strip. The gesture strip must not grow with expanded content.
        Region {
            x: Math.floor(root.topGestureInputX)
            y: 0
            width: Math.ceil(root.topGestureInputWidth)
            height: Math.ceil(root.topGestureInputHeight)
        }

        Region {
            intersection: Intersection.Combine
            x: Math.floor(mainCapsule.x)
            y: Math.floor(mainCapsule.y)
            width: Math.ceil(mainCapsule.width)
            height: Math.ceil(mainCapsule.height)
        }
        
        // Add existing detail shells
        Region {
            intersection: Intersection.Combine
            x: Math.floor(wifiConnectivityDetailShell.x)
            y: Math.floor(wifiConnectivityDetailShell.y)
            width: wifiConnectivityDetailShell.visible ? Math.ceil(wifiConnectivityDetailShell.width) : 0
            height: wifiConnectivityDetailShell.visible ? Math.ceil(wifiConnectivityDetailShell.height) : 0
        }

        Region {
            intersection: Intersection.Combine
            x: Math.floor(bluetoothConnectivityDetailShell.x)
            y: Math.floor(bluetoothConnectivityDetailShell.y)
            width: bluetoothConnectivityDetailShell.visible ? Math.ceil(bluetoothConnectivityDetailShell.width) : 0
            height: bluetoothConnectivityDetailShell.visible ? Math.ceil(bluetoothConnectivityDetailShell.height) : 0
        }
    }
    // FORK: the slack below the capsule is no longer a bare 12.
    //
    // The layer surface is sized from `targetHeight` — the value the spring
    // is animating TOWARDS — and a spring at zeta 0.8 deliberately goes
    // PAST its target: Motion.js measures the overshoot at 1.54% of the
    // travel. So the surface has to be big enough for the overshoot, not
    // just for the target, or the tallest ~6 px of the capsule is clipped
    // by its own window for the ~100 ms around the peak.
    //
    // Worked at the two extremes on this 1366x768 panel: the audio panel's
    // Metrics.px(360) = 331 overshoots by 5.1 px, the cheatsheet's
    // Metrics.px(460) = 423 by 6.5 px. The old flat 12 happened to cover
    // both — but only by accident, and it would have stopped covering them
    // the moment a panel went past ~780 px tall. Deriving it from the same
    // number Motion.js publishes means it cannot silently stop being true.
    //
    // Doubled (2x) rather than exact, because the shadow and the border are
    // also painted outside the fill, and because a surface a few pixels too
    // tall is invisible while one a few pixels too short is a clipped edge.
    readonly property real capsuleOvershootAllowance:
        Math.ceil(mainCapsule.targetHeight * Motion.overshoot() * 2)
    readonly property real capsuleWindowHeight: Math.ceil(
        userConfig.islandTopMargin + mainCapsule.targetHeight
            + Math.max(12, root.capsuleOvershootAllowance)
    )
    readonly property real connectivityDetailWindowHeight: root.anyConnectivityDetailMounted
        ? Math.ceil(userConfig.islandTopMargin + root.connectivityDetailHeight + 12)
        : 0
    readonly property real overviewWindowHeight: root.overviewVisible
        ? Math.ceil(userConfig.islandTopMargin + root.overviewCapsuleHeight + 8)
        : 0
    readonly property real requestedWindowHeight: Math.max(
        root.notificationCenterWindowHeight,
        root.capsuleWindowHeight,
        root.connectivityDetailWindowHeight,
        root.overviewWindowHeight,
        Math.ceil(root.controlCenterWindowHeight)
    )
    // Grow the layer surface immediately, but keep the old extent while the
    // capsule finishes its collapse animation. A later expansion interrupts
    // the pending shrink instead of letting a stale timer clip new content.
    property real retainedWindowHeight: 0
    implicitHeight: Math.max(root.requestedWindowHeight, root.retainedWindowHeight)

    function reconcileWindowHeight() {
        if (root.requestedWindowHeight >= root.retainedWindowHeight) {
            windowShrinkTimer.stop();
            root.retainedWindowHeight = root.requestedWindowHeight;
            return;
        }

        windowShrinkTimer.restart();
    }

    onRequestedWindowHeightChanged: root.reconcileWindowHeight()
    Component.onCompleted: root.retainedWindowHeight = root.requestedWindowHeight

    exclusiveZone: Math.ceil(root.baseExclusiveZone * root.exclusiveZoneProgress)
    // ---- Top WHILE RESTING, Overlay WHILE SHOWING ANYTHING ----
    //
    // Hyprland draws a fullscreen window ABOVE the Top layer and BELOW the
    // Overlay layer. So anything the island puts on Top is invisible the
    // moment a window goes fullscreen — which was reported as "in
    // fullscreen I open $mod P and cannot see the notch", and was exactly
    // that: the chord HUD is a Top-layer surface underneath the fullscreen
    // window.
    //
    // This used to be a hand-written list of nine panels. The list was the
    // bug. It named the ones somebody had hit the problem with, so the
    // wallpaper picker and the settings panel were visible in fullscreen
    // while the chord HUD, the cheatsheet, notifications, the notification
    // centre, the control centre, the expanded player and the workspace
    // indicator were not — and every panel added later would default to
    // invisible-in-fullscreen with nothing to suggest why.
    //
    // The general rule instead: the island is on Top while it is RESTING,
    // and on Overlay whenever it is showing something. "Resting" is the
    // same three states the rest of this file already tests for (see
    // canShowSideSwipe and the sideSwipe guards) — normal, lyrics, custom.
    //
    // The polkit prompt kept its own note because the reasoning is stronger
    // there than convenience: whatever asked for the password is usually a
    // window that just took the focus, and a prompt underneath a fullscreen
    // surface means the request appears to hang. It is covered by the
    // general rule now, and would have been covered by it anyway.
    //
    // Why resting stays on Top: a resting notch on Overlay would sit on top
    // of fullscreen video permanently, which is the opposite complaint. Only
    // transient content earns the promotion, and all of it is transient by
    // construction — every non-resting state returns to a resting one.
    //
    // ---- THIS WAS BRIEFLY Overlay ALWAYS, AND IS PUT BACK ----
    //
    // Reported as "I cannot screenshot the island", so resting was promoted
    // to Overlay unconditionally. The diagnosis was right and the fix was
    // wrong, and the mechanism is worth keeping written down: a fullscreen
    // window draws ABOVE Top and BELOW Overlay, so a resting island on Top
    // is genuinely not on screen while anything is fullscreen. Reproduced by
    // fullscreening a throwaway window and capturing the top strip, which
    // came back with no island in it at all — it is not a capture bug, the
    // pixels were never there.
    //
    // But the answer to that is not to pin the notch over fullscreen video.
    // Asked for directly afterwards: in fullscreen there is no need to show
    // the icons or the island, only when a mode opens. Which is what this
    // conditional already did — resting hides under fullscreen, and any
    // panel, OSD or mode promotes the surface to Overlay and draws over it.
    // So the original rule is restored unchanged, and the round trip is
    // recorded so it is not "fixed" a third time.
    readonly property bool islandRestingSurface:
        islandContainer.islandState === "normal"
        || islandContainer.islandState === "lyrics"
        || islandContainer.islandState === "custom"
    WlrLayershell.layer: root.islandRestingSurface ? WlrLayer.Top : WlrLayer.Overlay
    WlrLayershell.keyboardFocus: {
        // Exclusive, not OnDemand: the theme picker is arrow-key driven,
        // and without an exclusive grab the arrows go to whatever window
        // was focused behind it.
        if (islandContainer.wallpaperPickerLayerVisible
                || islandContainer.applicationLauncherLayerVisible
                || islandContainer.themePickerLayerVisible
                || islandContainer.displayPanelLayerVisible
                || islandContainer.audioPanelLayerVisible
                || islandContainer.wifiQrLayerVisible
                // The cheatsheet is the one READ-ONLY panel that still
                // needs an exclusive grab, and the search field is why:
                // every letter you type has to land in it rather than in
                // the window behind. ModeKeysLayer, which is also
                // read-only, deliberately does the opposite — it has no
                // field to type into and its keys belong to the submap.
                || islandContainer.cheatsheetLayerVisible
                || islandContainer.calendarLayerVisible
                || islandContainer.powerMenuLayerVisible
                || islandContainer.settingsLayerVisible
                // The generic picker, for the reason the cheatsheet is here
                // and ModeKeysLayer deliberately is not: it has a search
                // field, so every letter typed has to land in it rather
                // than in the window behind. On the `processes` menu that
                // window is frequently a terminal, and a stray "kill" typed
                // into a shell is a keystroke you cannot take back.
                || islandContainer.pickerLayerVisible
                // Exclusive for the password prompt for the obvious reason
                // and one less obvious one: without the grab, keystrokes
                // meant for the field land in the window behind, which for
                // a password means typing it into whatever has focus.
                || islandContainer.polkitPromptLayerVisible
                // FORK: the Wi-Fi and Bluetooth detail panels. They had NO
                // keyboard handling of any kind, and this line is half the
                // reason — focus never rose above None while one was open
                // unless a password prompt happened to be up, so there was
                // no keystroke for a Keys handler to receive. Exclusive for
                // the same reason the theme picker is here: the panels are
                // j/k driven, and without the grab those letters go to
                // whatever window is behind, which for `k` on a terminal is
                // a command you did not mean to start typing.
                || root.wifiConnectivityDetailOpen
                || root.bluetoothConnectivityDetailOpen)
            return WlrKeyboardFocus.Exclusive;
        // Keep keyboard focus on the overview until an overview action closes it.
        // Click-to-focus closes the overview before focusing the selected client.
        if (root.monitorFocused && root.overviewVisible)
            return WlrKeyboardFocus.Exclusive;
        if (islandContainer.expandedPlayerKeyboardFocusRequested)
            return WlrKeyboardFocus.OnDemand;
        if (root.monitorFocused && root.connectivityPromptActive)
            return WlrKeyboardFocus.OnDemand;
        return WlrKeyboardFocus.None;
    }
    readonly property string iconFontFamily: userConfig.iconFontFamily
    readonly property string textFontFamily: userConfig.textFontFamily
    readonly property string heroFontFamily: userConfig.heroFontFamily
    readonly property string timeFontFamily: userConfig.timeFontFamily
    readonly property int bodyFontSize: userConfig.bodyFontSize
    readonly property int titleFontSize: userConfig.titleFontSize
    readonly property int iconFontSize: userConfig.iconFontSize
    readonly property string defaultSplitIcon: "\ud83c\udfa7"
    readonly property string notificationStatusIcon: "\uf0f3"
    readonly property real overviewWindowCornerRadius: 12
    readonly property int dynamicIslandAcceptedButtons: userConfig.mouseButtonsMask([
        1,
        userConfig.dynamicIslandPrimaryButton,
        userConfig.dynamicIslandSecondaryButton
    ])
    readonly property int configuredHoverExpandAction: {
        const action = Number(userConfig.hoverExpandAction);
        return isNaN(action) ? 0 : Math.max(0, Math.min(2, Math.round(action)));
    }
    readonly property real baseExclusiveZone: userConfig.islandExclusiveZone

    // ------------------------------------------------------------------
    // FORK: the notch form. DESIGN-SPEC.md, "Geometry" and "The morph".
    // ------------------------------------------------------------------
    //
    // Upstream only has the floating pill: islandTopMargin below the top
    // edge, all four corners rounded. The spec has TWO forms of the SAME
    // shape, and the one that makes it read as a notch rather than as a
    // widget is the flush one:
    //
    //   floating — islandTopMargin below the top, all corners rounded
    //   notch    — flush to the top edge, TOP CORNERS SQUARE, a concave
    //              flare each side where it meets the screen top, and a
    //              few px of overshoot past the top that gets clipped
    //
    // notchProgress is the single value the spec insists on:
    //
    //   "This is one shape morphing and not two shapes swapping. A single
    //    path interpolated by one value."
    //
    // He tried the obvious way first — a rounded rect and a teardrop
    // flipped with `visible` — and it popped, "looked cheap instantly",
    // because one shape vanished while the other appeared mid-animation.
    //
    // The interpolation is deliberately TWO-PHASE, because an outline
    // cannot be both round-topped and flared at once: the flare grows out
    // of a square corner, so the corner has to finish un-rounding before
    // the flare has anywhere to attach. Phase 1 un-rounds the top corners
    // and slides the shape flush; phase 2 grows the flares. Both are
    // driven by notchProgress alone, so there is only ever one shape and
    // one value.
    property real notchProgress: root.notchModeEnabled ? 1 : 0

    // Default form. The spec's whole argument is that a notch is
    // pretending to be bezel — so the resting, everyday state is the
    // flush one, and the floating pill is the alternative rather than the
    // norm.
    //
    // NOW READ FROM CONFIG. This was `property bool notchModeEnabled: true`
    // — a hardcoded literal — under a comment claiming it was "toggled live
    // over IPC (`island setNotchMode`)". No such IPC exists: `qs ipc show`
    // lists setNotchMode nowhere, and nothing in the tree assigned this
    // property. So the settings panel's "Notch mode" switch wrote
    // forkNotchMode to userconfig.json and the shape never moved.
    //
    // The fallback stays `true` so a shell with no config, or one whose
    // ForkConfig has not loaded yet, draws the same resting shape it always
    // did rather than flickering through the floating pill on startup —
    // which is the reason ForkConfig's FileView sets preload.
    property bool notchModeEnabled: shellRootController && shellRootController.forkSettings
        ? shellRootController.forkSettings.notchMode
        : true

    readonly property real notchUnround: Math.max(0, Math.min(1, root.notchProgress * 2))
    readonly property real notchFlareProgress: Math.max(0, Math.min(1, root.notchProgress * 2 - 1))

    // The morph rides the same generated spring as every other geometry
    // change in the shell — see Motion.js. It has to: a shape that
    // un-rounds on a spring and flares on an ease would read as two
    // animations, which is the thing the single-path rule exists to
    // prevent.
    Behavior on notchProgress {
        NumberAnimation {
            duration: Motion.morphDuration()
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Motion.spring()
        }
    }

    // PROPORTION, not pixels. REQUIREMENTS.md: every number in the spec was
    // measured off the author's 2560x1440 display, and applying them
    // literally to this 1366x768 panel doubles them in proportional terms —
    // which is exactly why islandWidth is 96 and not the spec's 150.
    //
    // The flare is a feature OF the island, not of the screen, so it is
    // scaled by the island's own factor (96/150 = 0.64) rather than by the
    // screen-width ratio: 14 * 0.64 = 9.0 -> 9 px. Scaling by screen width
    // instead would have given 7.5, and both are defensible; the island
    // ratio wins because the flare has to look right against the island's
    // 38 px height, which did NOT get scaled down.
    readonly property real notchFlareSize: Math.round(14 * (userConfig.islandWidth / 150.0))

    // The overshoot is the ONE number here that is NOT scaled, and that is
    // deliberate. Its job is not aesthetic: the spec records that when the
    // shape was first made flush, a 1-2 px line of desktop showed above it,
    // and the cause was the drop shadow's own padding insetting the painted
    // shape inside its layer. That padding is an absolute pixel count and
    // does not shrink with the panel, so shrinking the overshoot to match
    // would reintroduce the exact gap it exists to cover. Stays at 4.
    //
    // It scales to zero as the shape morphs back to floating, because the
    // floating form needs its islandTopMargin gap back.
    readonly property real notchOvershoot: 4

    // Kept on root so the capsule can size itself for the resting EQ
    // without instantiating SwipeLyricsLayer to ask it. 4 bars of 3 px with
    // 3 px gaps, plus the 7 px gap after the clock.
    readonly property real restingEqAllowance: 4 * 3 + 3 * 3 + 7
    // FORK: the workspace ring now rides INSIDE the resting capsule, so the
    // capsule has to carry it the same way it carries the EQ bars — as extra
    // width, not as ink squeezed into the padding. islandWidth is sized for
    // the clock alone. Ring diameter plus the gap to the clock.
    // A digit and the gap to the clock, not a 32 px ring — the workspace
    // readout became type when it moved inside the capsule.
    readonly property real restingWorkspaceAllowance: Metrics.px(12) + Metrics.px(10)
    readonly property bool hoverExpandEnabled: configuredHoverExpandAction > 0
    readonly property bool topGestureInputActive: !root.overviewVisible && islandContainer.canShowSideSwipe
    readonly property bool autoHideRuntimeEnabled: !shellRootController
        || shellRootController.islandAutoHideRuntimeEnabled === undefined
        || !!shellRootController.islandAutoHideRuntimeEnabled
    readonly property bool autoHideEnabled: userConfig.islandAutoHideEnabled && autoHideRuntimeEnabled
    readonly property bool autoHideRestingState: islandContainer.islandState === "normal"
        || islandContainer.islandState === "custom"
        || islandContainer.islandState === "lyrics"
    readonly property bool autoHideCanHideNow: autoHideEnabled
        && autoHideRestingState
        && !root.overviewVisible
        && !root.connectivityPromptActive
        && !root.anyConnectivityDetailMounted
    readonly property bool autoHideMustShow: !autoHideRestingState
        || root.overviewVisible
        || root.connectivityPromptActive
        || root.anyConnectivityDetailMounted
    readonly property bool autoHideTargetVisible: autoHideMustShow
        || (!autoHideForcedHidden && (!autoHideEnabled || autoHideVisible))
    readonly property bool autoHideSuppressesTransientReveal: (autoHideEnabled || autoHideForcedHidden)
        && !autoHideTargetVisible
    property real autoHideProgress: autoHideTargetVisible ? 1 : 0
    readonly property bool exclusiveZoneTargetActive: (!autoHideEnabled && autoHideTargetVisible)
        || (autoHideRevealSource === "edge" && autoHideTargetVisible)
        || islandContainer.notificationLayerVisible
    property real exclusiveZoneProgress: exclusiveZoneTargetActive ? 1 : 0
    readonly property real autoHideRevealWidth: Math.min(root.width, Math.max(userConfig.islandWidth + 120, 240))
    readonly property real autoHideRevealHeight: autoHideEnabled ? 10 : 0
    readonly property real autoHideRevealX: Math.max(
        0,
        Math.min(root.width - autoHideRevealWidth, root.width * userConfig.islandPositionX / 100 - autoHideRevealWidth / 2)
    )
    readonly property real topGestureInputX: autoHideEnabled ? autoHideRevealX : 0
    readonly property real topGestureInputWidth: topGestureInputActive
        ? (autoHideEnabled ? autoHideRevealWidth : root.width)
        : 0
    readonly property real topGestureInputHeight: topGestureInputActive
        ? (autoHideEnabled ? autoHideRevealHeight : root.baseExclusiveZone)
        : 0
    readonly property real overviewCapsuleWidth: islandContainer.overviewView ? islandContainer.overviewView.width : 760
    readonly property real overviewCapsuleHeight: islandContainer.overviewView ? islandContainer.overviewView.height : 308
    readonly property real overviewCapsuleRadius: islandContainer.overviewView
        ? islandContainer.overviewView.largeWorkspaceRadius + islandContainer.overviewView.outerPadding
        : 44
    readonly property color overviewCapsuleColor: islandContainer.overviewView
        ? islandContainer.overviewView.cardColor
        : StyleTokens.overviewCard
    readonly property color overviewCapsuleBorderColor: islandContainer.overviewView
        ? islandContainer.overviewView.cardBorderColor
        : StyleTokens.overviewBorder
    property bool wifiConnectivityDetailOpen: false
    property bool wifiConnectivityDetailMounted: false
    property bool bluetoothConnectivityDetailOpen: false
    property bool bluetoothConnectivityDetailMounted: false
    readonly property bool anyConnectivityDetailMounted: wifiConnectivityDetailMounted || bluetoothConnectivityDetailMounted
    // FORK: these override ConnectivityDetailShell's own defaults, which is
    // why scaling them there alone changed nothing. Missed on the first
    // rescale pass because the names are local rather than QML's width and
    // height; the symptom was an unscaled 318x404 network list hanging off a
    // 310x221 control centre, nearly twice its height.
    readonly property real connectivityDetailWidth: Metrics.px(318)
    readonly property real connectivityDetailHeight: Metrics.px(404)
    readonly property real controlCenterMaximumExtraHeight: controlCenterLoader.item
        ? controlCenterLoader.item.controlCenterMaximumExtraHeight
        : 120
    readonly property real controlCenterWindowHeight: islandContainer.controlCenterLayerVisible
        ? userConfig.islandTopMargin + 320 + root.controlCenterMaximumExtraHeight + 12
        : 0

    readonly property real notificationCenterWindowHeight: islandContainer.notificationCenterLayerVisible
        ? userConfig.islandTopMargin + (notificationCenterLoader.item ? notificationCenterLoader.item.contentHeight : 400) + 6
        : 0
    readonly property real connectivityDetailGap: Metrics.px(16)
    readonly property int connectivityDetailAnimationDuration: 360
    readonly property string overviewWallpaperSource: overviewWallpaperCache.effectiveSource
    property string wallpaperPickerActiveWallpaper: userConfig.wallpaperPath

    // FORK: autoHideProgress drives BOTH the capsule's y offset and its
    // opacity (see mainCapsule), so it is a mixed channel. It therefore
    // takes the critically damped `fade` curve rather than the spring:
    // opacity is clamped 0-1, and a curve that overshoots on the way in
    // would try to exceed fully opaque, get clipped, and read as a cut.
    // Position loses a little character here; opacity would lose more.
    //
    // Upstream used 120ms OutCubic in / 300ms InCubic out. The asymmetry
    // is deliberate and kept — appearing should be immediate, leaving
    // should be unhurried — but both now run on the same generated curve
    // so the reveal and the hide are the same motion at two speeds.
    Behavior on autoHideProgress {
        NumberAnimation {
            duration: root.autoHideTargetVisible ? 140 : Motion.morphDuration()
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Motion.fade()
        }
    }

    // Exclusive zone is a compositor-side reservation, not something the
    // eye tracks — it just needs to not fight the capsule's own motion,
    // so it matches it.
    Behavior on exclusiveZoneProgress {
        NumberAnimation {
            duration: root.exclusiveZoneTargetActive ? 140 : Motion.morphDuration()
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Motion.fade()
        }
    }

    function setAutoHideRevealSource(source) {
        if (source === undefined || source === null)
            return;

        const nextSource = String(source);
        autoHideRevealSource = nextSource === "edge" || nextSource === "state" || nextSource === "manual"
            ? nextSource
            : "manual";
    }

    function showAutoHiddenIsland(source) {
        setAutoHideRevealSource(source);
        autoHideForcedHidden = false;
        if (!autoHideEnabled) {
            autoHideHideTimer.stop();
            autoHideVisible = true;
            return;
        }

        autoHideHideTimer.stop();
        autoHideVisible = true;
    }

    function scheduleAutoHide() {
        if (!autoHideEnabled) {
            autoHideHideTimer.stop();
            autoHideVisible = true;
            return;
        }

        if (!autoHideCanHideNow) {
            autoHideHideTimer.stop();
            showAutoHiddenIsland("state");
            return;
        }

        if (autoHidePointerInside) {
            autoHideHideTimer.stop();
            return;
        }

        autoHideHideTimer.interval = Math.max(100, Math.min(10000, userConfig.islandAutoHideDelayMs));
        autoHideHideTimer.restart();
    }

    function hideAutoHiddenIsland(force) {
        if (force === undefined) force = false;
        if (!autoHideEnabled) {
            autoHideHideTimer.stop();
            if (!force && autoHideMustShow)
                return;
            autoHideForcedHidden = true;
            autoHideRevealSource = "none";
            autoHideVisible = false;
            return;
        }

        if (!force && (!autoHideCanHideNow || autoHidePointerInside))
            return;

        autoHideHideTimer.stop();
        autoHideForcedHidden = false;
        autoHideRevealSource = "none";
        autoHideVisible = false;
    }

    function toggleAutoHiddenIsland() {
        if (autoHideTargetVisible)
            hideAutoHiddenIsland(false);
        else
            showAutoHiddenIsland("manual");
    }

    function showIslandWindow() {
        showAutoHiddenIsland("manual");
    }

    function hideIslandWindow() {
        autoHidePointerInside = false;
        hideAutoHiddenIsland(false);
    }

    function toggleIslandWindow() {
        toggleAutoHiddenIsland();
    }

    function refreshAutoHideWindow() {
        if (autoHideEnabled)
            scheduleAutoHide();
        else
            showAutoHiddenIsland("manual");
    }

    function beginOverviewOpening() {
        if (!overviewPreparing) return;
        if (overviewLoader.status !== Loader.Ready || !overviewVisualReady) return;
        overviewPreloading = false;
        overviewPhase = "opening";
        overviewRevealTimer.restart();
    }

    function prepareOverview() {
        if (compositorIsNiri) return;
        if (overviewPhase !== "closed") return;
        overviewUnloadGraceTimer.stop();
        overviewPreloading = true;
        overviewPreloadExpireTimer.restart();
    }

    function cancelPreparedOverview() {
        if (compositorIsNiri) return;
        if (overviewPhase !== "closed") return;
        overviewPreloadExpireTimer.stop();
        overviewPreloading = false;
    }

    function openOverview() {
        if (compositorIsNiri)
            return;
        if (overviewPhase !== "closed") return;
        overviewUnloadGraceTimer.stop();
        overviewPreloadExpireTimer.stop();
        overviewPreloading = true;
        overviewPhase = "preparing";
        if (overviewLoader.status === Loader.Ready) {
            beginOverviewOpening();
        }
    }

    function closeOverview() {
        if (compositorIsNiri)
            return;
        if (!overviewMounted) return;
        if (overviewLoader.status === Loader.Ready)
            overviewUnloadGraceTimer.restart();
        overviewRevealTimer.stop();
        overviewPreloadExpireTimer.stop();
        islandContainer.restoreRestingCapsule(true);
        overviewPreloading = false;
        overviewPhase = "closed";
    }

    function closeOverviewEverywhere() {
        if (shellRootController && shellRootController.closeOverviewAll) {
            shellRootController.closeOverviewAll();
            return;
        }

        closeOverview();
    }

    function setConnectivityDetailVisible(kind, open) {
        const nextOpen = !!open;

        if (kind === "wifi") {
            if (nextOpen) {
                wifiConnectivityDetailCleanupTimer.stop();
                wifiConnectivityDetailMounted = true;
                wifiConnectivityDetailOpen = true;
            } else {
                if (!wifiConnectivityDetailMounted && !wifiConnectivityDetailOpen)
                    return;
                wifiConnectivityDetailOpen = false;
                wifiConnectivityDetailCleanupTimer.restart();
            }
            return;
        }

        if (kind === "bluetooth") {
            if (nextOpen) {
                bluetoothConnectivityDetailCleanupTimer.stop();
                bluetoothConnectivityDetailMounted = true;
                bluetoothConnectivityDetailOpen = true;
            } else {
                if (!bluetoothConnectivityDetailMounted && !bluetoothConnectivityDetailOpen)
                    return;
                bluetoothConnectivityDetailOpen = false;
                bluetoothConnectivityDetailCleanupTimer.restart();
            }
        }
    }

    function closeAllConnectivityDetails() {
        setConnectivityDetailVisible("wifi", false);
        setConnectivityDetailVisible("bluetooth", false);
    }

    function openOverviewEverywhere() {
        if (shellRootController && shellRootController.openOverviewAll) {
            shellRootController.openOverviewAll();
            return;
        }

        openOverview();
    }

    function prepareOverviewEverywhere() {
        if (shellRootController && shellRootController.prepareOverviewAll) {
            shellRootController.prepareOverviewAll();
            return;
        }

        prepareOverview();
    }

    function cancelPreparedOverviewEverywhere() {
        if (shellRootController && shellRootController.cancelPreparedOverviewAll) {
            shellRootController.cancelPreparedOverviewAll();
            return;
        }

        cancelPreparedOverview();
    }

    function toggleOverviewEverywhere() {
        if (compositorIsNiri)
            return;

        if (shellRootController && shellRootController.toggleOverviewAll) {
            shellRootController.toggleOverviewAll();
            return;
        }

        if (overviewMounted)
            closeOverviewEverywhere();
        else
            openOverviewEverywhere();
    }

    function prewarmWallpaperCache() {
        overviewWallpaperCache.prewarm();
    }

    function handleWallpaperApplySucceeded(filePath) {
        wallpaperPickerActiveWallpaper = filePath;
        if (shellRootController && shellRootController.refreshOverviewWallpaperCaches)
            shellRootController.refreshOverviewWallpaperCaches(filePath);
        else
            prewarmWallpaperCache();
    }

    function showNotification(appName, summary, body) {
        islandContainer.showNotificationCapsule(appName, summary, body);
    }

    function showClockWindow() {
        islandContainer.showTimeCapsule();
        showAutoHiddenIsland("manual");
        scheduleAutoHide();
    }
    function showModeIndicatorWindow(icon, text) {
        islandContainer.showModeIndicator(icon, text);
        showAutoHiddenIsland("manual");
    }

    // FORK: the chord heads-up display's window-level entry points, beside
    // the mode INDICATOR's. The two are different things and both are kept:
    // the indicator is a name in the capsule and survives a transient OSD,
    // this is the expanded key list. showModeKeys clears the indicator so
    // the two never draw at once.
    function showModeKeysWindow(name) {
        islandContainer.clearModeIndicator();
        islandContainer.showModeKeys(name);
    }

    function clearModeKeysWindow() {
        islandContainer.clearModeKeys();
    }

    // FORK: the cheatsheets. `which` is hypr | vim | fish — the three keys
    // of qtile's CheatSheet-Mode, which the panel can also cycle with Tab
    // once it is open.
    //
    // Toggling on the SHEET and not just on the state: pressing the chord's
    // `v` while the WM sheet is open should switch to vim, not close the
    // panel. Only the same sheet again means "I am done".
    function toggleCheatsheetWindow(which) {
        if (islandContainer.islandState === "cheatsheet"
                && islandContainer.cheatsheetWhich === which)
            islandContainer.smartRestoreState();
        else
            islandContainer.showCheatsheet(which);
    }

    function clearModeIndicatorWindow() {
        islandContainer.clearModeIndicator();
    }

    function showCustomInfoWindow() {
        islandContainer.showCustomCapsule();
        showAutoHiddenIsland("manual");
        scheduleAutoHide();
    }
    function showLyricsWindow() {
        islandContainer.showLyricsCapsule();
        showAutoHiddenIsland("manual");
        scheduleAutoHide();
    }

    function swipeRightWindow() {
        if (islandContainer.restingState === "lyrics")
            islandContainer.showTimeCapsule();
        else if (islandContainer.restingState === "normal") {
            if (islandContainer.hasCustomLeftItems)
                islandContainer.showCustomCapsule();
            else
                islandContainer.showLyricsCapsule();
        }
        else
            islandContainer.showLyricsCapsule();

        showAutoHiddenIsland("manual");
        scheduleAutoHide();
    }

    function swipeLeftWindow() {
        if (islandContainer.restingState === "custom")
            islandContainer.showTimeCapsule();
        else if (islandContainer.restingState === "normal")
            islandContainer.showLyricsCapsule();
        else if (islandContainer.hasCustomLeftItems)
            islandContainer.showCustomCapsule();
        else
            islandContainer.showTimeCapsule();

        showAutoHiddenIsland("manual");
        scheduleAutoHide();
    }

    function togglePlayerWindow() {
        if (islandContainer.islandState === "expanded")
            islandContainer.smartRestoreState();
        else
            islandContainer.showExpandedPlayer(false);
    }

    function toggleControlCenterWindow() {
        if (islandContainer.islandState === "control_center")
            islandContainer.smartRestoreState();
        else
            islandContainer.showControlCenter();
    }

    // FORK: land directly in the Wi-Fi or Bluetooth list, which is what
    // qtile's WifiPopup ($mod P then n) and BluetoothPopup ($mod P then b)
    // did in one chord. The control centre already owns both lists — they
    // were simply only reachable by opening it and clicking a chevron, so
    // 26 bindings' worth of function was present and unbound.
    //
    // Opening the control centre and opening the sub-panel cannot happen in
    // the same tick: controlCenterLoader is not instantiated until the
    // island is in the control_center state, so `controlCenterLoader.item`
    // is still null on the line after showControlCenter(). Deferred by one
    // event-loop turn with Qt.callLater, which is enough — the Loader is
    // synchronous (asynchronous: false), so it exists by the next turn.
    function openConnectivityPanelWindow(kind) {
        const wasOpen = islandContainer.islandState === "control_center"
            && controlCenterLoader.item
            && controlCenterLoader.item.isConnectivityPanelOpen(kind);

        if (wasOpen) {
            // Pressing the same chord again closes it, matching the toggle
            // behaviour every other island panel has.
            islandContainer.smartRestoreState();
            return;
        }

        if (islandContainer.islandState !== "control_center")
            islandContainer.showControlCenter();

        Qt.callLater(function() {
            if (!controlCenterLoader.item)
                return;
            controlCenterLoader.item.closeConnectivityPanels(false);
            controlCenterLoader.item.setConnectivityPanelOpen(kind, true);
        });
    }

    function toggleNotificationCenterWindow() {
        if (islandContainer.islandState === "notification_center")
            islandContainer.smartRestoreState();
        else
            islandContainer.showNotificationCenter();
    }

    function toggleWallpaperPickerWindow() {
        if (islandContainer.islandState === "wallpaper_picker")
            islandContainer.smartRestoreState();
        else
            islandContainer.showWallpaperPicker();
    }

    function toggleDisplayPanelWindow() {
        if (islandContainer.islandState === "display_panel")
            islandContainer.smartRestoreState();
        else
            islandContainer.showDisplayPanel();
    }

    function toggleAudioPanelWindow() {
        if (islandContainer.islandState === "audio_panel")
            islandContainer.smartRestoreState();
        else
            islandContainer.showAudioPanel();
    }

    function toggleWifiQrWindow() {
        if (islandContainer.islandState === "wifi_qr")
            islandContainer.smartRestoreState();
        else
            islandContainer.showWifiQr();
    }

    function toggleThemePickerWindow() {
        if (islandContainer.islandState === "theme_picker")
            islandContainer.smartRestoreState();
        else
            islandContainer.showThemePicker();
    }

    // FORK: the four states DESIGN-SPEC.md listed that nothing answered.
    function toggleCalendarWindow() {
        if (islandContainer.islandState === "calendar")
            islandContainer.smartRestoreState();
        else
            islandContainer.showCalendar();
    }

    function togglePowerMenuWindow() {
        if (islandContainer.islandState === "power_menu")
            islandContainer.smartRestoreState();
        else
            islandContainer.showPowerMenu();
    }

    // FORK: the generic list picker. Toggling on the MENU and not just on
    // the state, exactly like toggleCheatsheetWindow: pressing the chord's
    // key for `processes` while the `windows` picker is open should switch
    // menus, not close the panel. Only the same menu again means "done".
    function showPickerWindow(name) {
        if (islandContainer.islandState === "picker"
                && islandContainer.pickerMenu === name)
            islandContainer.smartRestoreState();
        else
            islandContainer.showPicker(name);
    }

    function clearPickerWindow() {
        islandContainer.clearPicker();
    }

    function toggleSettingsWindow() {
        if (islandContainer.islandState === "settings")
            islandContainer.smartRestoreState();
        else
            islandContainer.showSettings();
    }

    // NOT a toggle, and that is deliberate. Every other panel here is
    // opened by a key you pressed, so a second press meaning "close" is
    // right. This one is opened by a process waiting on an answer, and a
    // toggle would give the same call two opposite meanings depending on
    // state — a second authorisation request arriving while the first is up
    // would DISMISS the prompt instead of showing the new one.
    function showPolkitPromptWindow() {
        islandContainer.showPolkitPrompt();
    }

    function clearPolkitPromptWindow() {
        if (islandContainer.islandState === "polkit_prompt")
            islandContainer.smartRestoreState();
    }

    function toggleApplicationLauncherWindow() {
        if (islandContainer.islandState === "application_launcher")
            islandContainer.smartRestoreState();
        else
            islandContainer.showApplicationLauncher();
    }

    onOverviewVisibleChanged: {
        if (overviewVisible && monitorFocused) overviewFocusTimer.restart();
        if (overviewVisible)
            showAutoHiddenIsland("state");
        else
            scheduleAutoHide();
    }
    onConnectivityPromptActiveChanged: {
        if (connectivityPromptActive && monitorFocused)
            connectivityPromptFocusTimer.restart();
        if (connectivityPromptActive)
            showAutoHiddenIsland("state");
        else
            scheduleAutoHide();
    }
    onAutoHideEnabledChanged: {
        if (autoHideEnabled)
            scheduleAutoHide();
        else
            showAutoHiddenIsland("manual");
    }
    onAutoHideCanHideNowChanged: {
        if (autoHideCanHideNow)
            scheduleAutoHide();
        else
            showAutoHiddenIsland("state");
    }
    onOverviewVisualReadyChanged: {
        if (overviewVisualReady) beginOverviewOpening();
    }
    onMonitorFocusedChanged: {
        if (overviewVisible && monitorFocused) overviewFocusTimer.restart();
        if (connectivityPromptActive && monitorFocused) connectivityPromptFocusTimer.restart();
    }

    Timer {
        id: overviewFocusTimer
        interval: 0
        repeat: false
        onTriggered: islandContainer.forceActiveFocus()
    }

    Timer {
        id: connectivityPromptFocusTimer
        interval: 0
        repeat: false
        onTriggered: islandContainer.forceActiveFocus()
    }

    Timer {
        id: expandedPlayerFocusTimer
        interval: 0
        repeat: false
        onTriggered: {
            islandContainer.forceActiveFocus();
        }
    }

    Timer {
        id: windowShrinkTimer
        // FORK: derived, not 1000. Its job is to hold the layer surface at
        // the old extent until the capsule has finished collapsing INTO the
        // new one — so the number it must cover is the morph, plus the
        // content fade that now runs alongside it (see PanelLoader.qml,
        // which keeps a dismissed panel mounted for exactly that long), plus
        // a frame of slack at 60 Hz. 1000 was a guess that happened to be
        // long enough; this cannot come adrift if either duration changes.
        interval: Motion.morphDuration() + Motion.fadeOutDuration() + 32
        repeat: false
        onTriggered: root.retainedWindowHeight = root.requestedWindowHeight
    }

    Timer {
        id: autoHideHideTimer
        interval: Math.max(100, Math.min(10000, userConfig.islandAutoHideDelayMs))
        repeat: false
        onTriggered: root.hideAutoHiddenIsland(false)
    }

    function focusWallpaperPicker() {
        islandContainer.forceActiveFocus();
        if (wallpaperPickerLoader.item && wallpaperPickerLoader.item.grabKeyboardFocus)
            wallpaperPickerLoader.item.grabKeyboardFocus();
    }

    function focusApplicationLauncher() {
        islandContainer.forceActiveFocus();
        if (applicationLauncherLoader.item && applicationLauncherLoader.item.grabKeyboardFocus)
            applicationLauncherLoader.item.grabKeyboardFocus();
    }

    Timer {
        id: overviewRevealTimer
        interval: 0
        repeat: false
        onTriggered: {
            if (root.overviewPhase === "opening") root.overviewPhase = "open";
        }
    }

    Timer {
        id: overviewPreloadExpireTimer
        interval: 1200
        repeat: false
        onTriggered: {
            if (root.overviewPhase === "closed")
                root.overviewPreloading = false;
        }
    }

    Timer {
        id: overviewUnloadGraceTimer
        interval: 260
        repeat: false
    }

    Timer {
        id: wifiConnectivityDetailCleanupTimer
        interval: root.connectivityDetailAnimationDuration
        repeat: false
        onTriggered: root.wifiConnectivityDetailMounted = false
    }

    Timer {
        id: bluetoothConnectivityDetailCleanupTimer
        interval: root.connectivityDetailAnimationDuration
        repeat: false
        onTriggered: root.bluetoothConnectivityDetailMounted = false
    }

    OverviewWallpaperCacheController {
        id: overviewWallpaperCache

        active: root.overviewLoaderActive
        wallpaperPath: userConfig.wallpaperCustomCommandEnabled === true && root.wallpaperPickerActiveWallpaper !== ""
            ? root.wallpaperPickerActiveWallpaper
            : userConfig.wallpaperPath
        hyprMonitor: root.hyprMonitor
        screenObject: root.screen
    }

    // FORK: the live palette, watched from theme-apply's generated file.
    IslandTheme {
        id: islandTheme
    }

    IslandClock {
        id: timeObj
        clockFormat: userConfig.clockFormat
    }

    // --- 灵动岛主容器与全局状态 ---
    FocusScope {
        id: islandContainer
        anchors.fill: parent
        focus: wallpaperPickerLayerVisible
            || applicationLauncherLayerVisible
            || themePickerLayerVisible
            || displayPanelLayerVisible
            // Qualified through the id where its neighbours are unqualified.
            // The bare name logged "audioPanelLayerVisible is not defined"
            // from this binding while the file was being edited under a live
            // shell — Quickshell hot-reloads on write, so a save that lands
            // between the property's USE and its DECLARATION compiles a
            // component that really is missing it. This form cannot have that
            // window at all, which is worth the inconsistency: the failure is
            // a warning per evaluation, and warnings in this log are numerous
            // enough to be scrolled past.
            || islandContainer.audioPanelLayerVisible
            || islandContainer.wifiQrLayerVisible
            || islandContainer.cheatsheetLayerVisible
            // Qualified through the id, for the same reason the audio panel
            // above is: a hot reload landing between a new property's use
            // and its declaration compiles a component that really is
            // missing it.
            || islandContainer.calendarLayerVisible
            || islandContainer.powerMenuLayerVisible
            || islandContainer.settingsLayerVisible
            // Qualified through the id, for the same reason its neighbours
            // are: a hot reload landing between a new property's use and its
            // declaration compiles a component that really is missing it.
            || islandContainer.pickerLayerVisible
            || islandContainer.polkitPromptLayerVisible
            || expandedPlayerKeyboardFocusRequested
            || (root.monitorFocused && (root.overviewVisible || root.connectivityPromptActive))

        property string islandState: "normal"
        property string splitIcon: root.defaultSplitIcon
        property real osdProgress: -1.0
        property bool osdProgressAnimationEnabled: true
        property string osdCustomText: ""
        property int currentWs: root.currentMonitorWorkspaceId > 0 ? root.currentMonitorWorkspaceId : 1
        readonly property int batteryCapacity: systemState.batteryCapacity
        readonly property bool isCharging: systemState.isCharging
        readonly property real currentVolume: systemState.currentVolume
        readonly property bool isMuted: systemState.isMuted
        readonly property real currentBrightness: systemState.currentBrightness
        readonly property real currentCpuUsage: systemState.currentCpuUsage
        readonly property real currentRamUsage: systemState.currentRamUsage
        property string notificationAppName: ""
        property string notificationSummary: ""
        property string notificationBody: ""
        property bool notificationExpanded: false
        property var bluetoothExpandedDevice: null
        property var notificationHistoryModel: ListModel {}
        readonly property var cavaLevels: systemState.cavaLevels
        // FORK: gates the resting-state EQ. See SwipeLyricsLayer.restingEq.
        //
        // forkRestingEqEnabled is folded in HERE rather than at the bars
        // themselves, because this one property gates both halves of the
        // feature: the bars' visibility in SwipeLyricsLayer, and the
        // restingEqAllowance the collapsed capsule grows by (line ~2701).
        // Gating only the bars would have left the capsule widening by 21 px
        // for an EQ that was not drawn — a resting notch that is silently
        // too wide, which is the kind of thing that gets measured later and
        // blamed on islandWidth.
        readonly property bool musicPlaying: mediaController.musicPlaying
            && !(shellRootController && shellRootController.forkSettings
                 && !shellRootController.forkSettings.restingEqEnabled)

        // FORK: whether the media/lyrics surface has anything to be ABOUT.
        // Upstream guards the left-hand custom surface on
        // hasCustomLeftItems but leaves the right-hand media surface
        // ungated, and that asymmetry is a real bug: with no player at all,
        // resting on "lyrics" renders lyricsBridge.displayText, which falls
        // through to the literal string "No music playing" beside an empty
        // album-art square. So the island's resting state became a card
        // announcing the absence of media.
        //
        // DESIGN-SPEC.md rules that out twice over — the resting state is
        // "exactly two things: the time, and a 4-bar EQ", and media is
        // supposed to "swap the content while the shape stays put", never
        // to own the rest state. Note this is deliberately activePlayer,
        // not musicPlaying: a paused track is still a media surface worth
        // showing, no player at all is not.
        readonly property bool hasMediaSurface: mediaController.activePlayer !== null

        // FORK: arbitrary, PERSISTENT text in the island.
        //
        // Upstream can already draw text in the capsule — showTransientCapsule
        // does it, and it is what every OSD uses — but it is transient by
        // construction: it restarts autoHideTimer, which calls
        // smartRestoreState a couple of seconds later. That is right for a
        // volume bubble and wrong for a mode indicator, which has to stay up
        // for exactly as long as the mode is active and not one moment
        // longer.
        //
        // The upstream IPC that sounds like this, `tide showCustom()`, takes
        // no arguments at all — it switches to the custom-info surface, whose
        // content comes from the config's own item list. There was no way to
        // push a string in from outside.
        property bool modeIndicatorActive: false
        property string modeIndicatorText: ""
        property string modeIndicatorIcon: ""
        property real swipeTransitionProgress: 0
        property string workspaceOriginSide: "none"
        property string splitOriginSide: "none"
        property string restingState: "normal"
        property bool expandedByPlayerAutoOpen: false
        property real customCapsuleWidth: 220
        property real lyricsCapsuleWidth: 220
        property bool sideSwipeSettling: false
        property bool hoverExpandedActive: false
        property bool expandedPlayerKeyboardFocusRequested: false
        property bool openTimerPageWhenExpanded: false
        property int timerSelectedHours: 0
        property int timerSelectedMinutes: 5
        property int timerTotalSeconds: 300
        property int timerRemainingSeconds: 0
        property bool timerRunning: false
        property bool timerActive: false
        property bool timerCompletionAnimating: false
        property real timerCompletionPulse: 0
        property real timerCompletionFlash: 0
        readonly property int defaultAutoHideInterval: 1250
        readonly property int notificationAutoHideInterval: 4200
        readonly property int bluetoothExpandedAutoHideInterval: 2500
        readonly property int swipeAnimationDuration: 220
        readonly property real timerProgress: timerActive && timerTotalSeconds > 0
            ? Math.max(0, Math.min(1, timerRemainingSeconds / timerTotalSeconds))
            : 0
        readonly property bool timerBubbleWanted: (timerActive && timerRemainingSeconds > 0 || timerCompletionAnimating)
            && !root.overviewVisible
            && (islandState === "normal" || islandState === "lyrics" || islandState === "custom")
        // FORK: split into TWO predicates, because there were two guards in
        // this file pretending to be one and only ONE of them consulted the
        // list.
        //
        // MEASURED: with the chord HUD up, `hyprctl dispatch workspace 4`
        // replaced it with the "Workspace 4" long capsule, every time. The
        // HUD was correctly listed in blocksTransientSplit and it made no
        // difference, because `showWorkspaceCapsule` never read that
        // property — it carried its own hand-written guard,
        //
        //     if (islandState === "control_center" || islandState === "notification") return;
        //
        // written before any of these panels existed and never extended.
        // `showNotificationCapsule` and `showBluetoothExpanded` carried
        // their own copies of the same two-item list. So a volume OSD (which
        // does go through showTransientCapsule) was blocked and a workspace
        // switch was not — which is the worst possible split, since the
        // chords themselves bind `1-9 workspace` and therefore fire the one
        // interrupt that gets through, constantly.
        //
        // openPanelState is every state a PERSON deliberately opened and is
        // looking at. Nothing spontaneous may replace one of those.
        // blocksTransientSplit adds `notification`, which is itself
        // transient: an OSD must not stomp a notification, but a second
        // notification legitimately replaces the first.
        readonly property bool openPanelState: islandState === "expanded"
            || islandState === "bluetooth_expanded"
            || islandState === "control_center"
            || islandState === "notification_center"
            || islandState === "wallpaper_picker"
            || islandState === "application_launcher"
            || islandState === "theme_picker"
            || islandState === "display_panel"
            || islandState === "audio_panel"
            || islandState === "wifi_qr"
            || islandState === "mode_keys"
            || islandState === "cheatsheet"
            || islandState === "calendar"
            || islandState === "power_menu"
            || islandState === "settings"
            || islandState === "picker"
            // The polkit prompt is the one entry here that is NOT opened by
            // a person — it is opened by whatever asked for authorisation.
            // It belongs in the list anyway, and more urgently than the
            // rest: a volume OSD replacing a password field mid-type would
            // drop the keystrokes into nothing.
            || islandState === "polkit_prompt"
        readonly property bool blocksTransientSplit: openPanelState
            || islandState === "notification"
        readonly property bool splitShowsProgress: islandState === "split" && osdProgress >= 0
        readonly property bool splitShowsText: islandState === "split" && osdProgress < 0 && osdCustomText !== ""
        readonly property bool splitShowsIconOnly: islandState === "split" && osdProgress < 0 && osdCustomText === ""
        readonly property bool splitUsesExtendedLayout: splitShowsProgress || splitShowsText
        readonly property real splitCapsuleWidth: splitShowsProgress ? Metrics.px(248) : (splitShowsText ? Metrics.px(220) : userConfig.islandWidth)
        readonly property bool canShowSideSwipe: islandState === "normal"
            || islandState === "custom"
            || islandState === "lyrics"
            || (islandState === "long_capsule" && workspaceOriginSide === "none")
        readonly property real rightSwipeProgress: Math.max(0, swipeTransitionProgress)
        readonly property var customLeftItems: systemState.customLeftItems
        readonly property bool hasCustomLeftItems: systemState.hasCustomLeftItems
        readonly property bool customSwipeVisible: !root.overviewVisible
            && hasCustomLeftItems
            && (
                capsuleMouseArea.sideSwipeInteractive
                ? swipeTransitionProgress < 0
                : (
                    islandState === "custom"
                    || (islandState === "normal" && swipeTransitionProgress < 0)
                    || (islandState === "split" && splitOriginSide === "left")
                    || (islandState === "long_capsule"
                        && (workspaceOriginSide === "left" || swipeTransitionProgress < 0))
                )
            )
        readonly property bool lyricsSwipeVisible: !root.overviewVisible && (
            capsuleMouseArea.sideSwipeInteractive
            ? swipeTransitionProgress >= 0
            : (
                islandState === "lyrics"
                || (islandState === "normal" && swipeTransitionProgress >= 0)
                || (islandState === "split" && splitOriginSide === "right")
                || (islandState === "long_capsule"
                    && (workspaceOriginSide === "right" || swipeTransitionProgress > 0))
            )
        )
        readonly property bool expandedLayerVisible: !root.overviewVisible && islandState === "expanded"
        readonly property bool bluetoothExpandedLayerVisible: !root.overviewVisible && islandState === "bluetooth_expanded"
        readonly property bool notificationLayerVisible: !root.overviewVisible && islandState === "notification"
        readonly property bool controlCenterLayerVisible: !root.overviewVisible && islandState === "control_center"
        readonly property bool notificationCenterLayerVisible: !root.overviewVisible && islandState === "notification_center"
        readonly property bool wallpaperPickerLayerVisible: !root.overviewVisible && islandState === "wallpaper_picker"
        readonly property bool applicationLauncherLayerVisible: !root.overviewVisible && islandState === "application_launcher"
        readonly property bool themePickerLayerVisible: !root.overviewVisible && islandState === "theme_picker"

        // FORK: the chord heads-up display. NOT in the keyboardFocus or
        // focus lists on purpose — see qml/island/ModeKeysLayer.qml. The
        // keys belong to the compositor's submap; grabbing them here would
        // swallow the keys this panel exists to advertise.
        property string modeKeysName: ""
        readonly property bool modeKeysLayerVisible: !root.overviewVisible && islandState === "mode_keys"
        // Height of each submap's key grid, remembered across opens so the
        // capsule can size itself before `cheatsheet.py` has answered. See
        // ModeKeysLayer's `pendingHeight` for the measurement that made this
        // necessary. A plain object and not a notifying property on purpose:
        // it is read once, imperatively, at the moment the panel opens, so
        // there is nothing for a missing change signal to get wrong.
        property var modeKeysHeights: ({})
        function modeKeysHeightFor(name) {
            const remembered = modeKeysHeights[name];
            return remembered === undefined ? 0 : remembered;
        }
        function rememberModeKeysHeight(name, height) {
            if (name !== "" && height > 0)
                modeKeysHeights[name] = height;
        }
        // FORK: the cheatsheets, moved off rofi and into the notch.
        property string cheatsheetWhich: "hypr"
        readonly property bool cheatsheetLayerVisible: !root.overviewVisible && islandState === "cheatsheet"
        // FORK: the display panel, the port of qtile's DisplayPopup.
        readonly property bool displayPanelLayerVisible: !root.overviewVisible && islandState === "display_panel"
        // FORK: the audio panel, the port of qtile's AudioPopup — the detail
        // the control centre's single Sound slider does not cover.
        readonly property bool audioPanelLayerVisible: !root.overviewVisible && islandState === "audio_panel"
        // FORK: the Wi-Fi QR — qtile's WifiQR, `s` inside its WiFi chord.
        readonly property bool wifiQrLayerVisible: !root.overviewVisible && islandState === "wifi_qr"
        // FORK: the four remaining states from DESIGN-SPEC.md's list. None
        // of these existed upstream; `calendar`, `power menu` and `Polkit
        // password prompt` are named in the spec, and the settings surface
        // is the fork's answer to a packaged config app it must not patch.
        readonly property bool calendarLayerVisible: !root.overviewVisible && islandState === "calendar"
        readonly property bool powerMenuLayerVisible: !root.overviewVisible && islandState === "power_menu"
        readonly property bool settingsLayerVisible: !root.overviewVisible && islandState === "settings"
        // FORK: the generic list picker — one panel behind three (so far) of
        // the rofi chord's menus. `pickerMenu` is the menu name the backing
        // script builds, and it is set BEFORE islandState flips so the
        // Loader's first fetch is already the right one; showCheatsheet does
        // the same with cheatsheetWhich and for the same reason.
        // See qml/island/PickerLayer.qml.
        property string pickerMenu: "windows"
        readonly property bool pickerLayerVisible: !root.overviewVisible && islandState === "picker"
        readonly property bool polkitPromptLayerVisible: !root.overviewVisible && islandState === "polkit_prompt"
        readonly property var activePlayer: mediaController.activePlayer
        readonly property string lyricsDisplayText: mediaController.displayText
        readonly property string currentTrack: mediaController.currentTrack
        readonly property string currentArtist: mediaController.currentArtist
        readonly property string currentArtUrl: mediaController.currentArtUrl
        readonly property real trackProgress: mediaController.trackProgress
        readonly property string timePlayed: mediaController.timePlayed
        readonly property string timeTotal: mediaController.timeTotal
        readonly property bool screenRecordingActive: root.screenRecordingActive
        readonly property var bluetoothDevices: bluetoothConnectionTracker.devices
        readonly property var overviewView: overviewLoader.item && overviewLoader.item.overviewView
            ? overviewLoader.item.overviewView
            : null

        onExpandedLayerVisibleChanged: {
            if (!expandedLayerVisible)
                expandedPlayerKeyboardFocusRequested = false;
        }

        onControlCenterLayerVisibleChanged: {
            if (!controlCenterLayerVisible) {
                if (controlCenterLoader.item)
                    controlCenterLoader.item.closeConnectivityPanels();
                else
                    root.closeAllConnectivityDetails();
            }
        }

        // FORK: mirrors onCustomLeftItemsChanged below. When the last
        // player goes away while the island is resting on the media
        // surface, fall back to the clock instead of sitting on a card
        // about a player that no longer exists.
        onHasMediaSurfaceChanged: {
            if (hasMediaSurface || restingState !== "lyrics")
                return;

            restingState = "normal";

            if (islandState === "lyrics"
                    || (islandState === "split" && splitOriginSide === "right")
                    || (islandState === "long_capsule" && workspaceOriginSide === "right")) {
                restoreRestingCapsule(true);
            } else {
                applyRestingVisuals();
            }
        }

        onCustomLeftItemsChanged: {
            if (restingState === "custom" && !hasCustomLeftItems) {
                restingState = "normal";

                if (islandState === "custom"
                        || (islandState === "split" && splitOriginSide === "left")
                        || (islandState === "long_capsule" && workspaceOriginSide === "left")) {
                    restoreRestingCapsule(true);
                } else {
                    applyRestingVisuals();
                }
            } else if (restingState === "custom") {
                syncCustomCapsuleWidth();
            }
        }

        IslandMprisController {
            id: mediaController

            expanded: islandContainer.islandState === "expanded"
            clientId: "island-mpris-" + root.screenOutputName
        }

        BluetoothConnectionTracker {
            id: bluetoothConnectionTracker

            onAdapterChanged: islandContainer.bluetoothExpandedDevice = null

            onNewConnection: function(device) {
                islandContainer.showBluetoothExpanded(device);
            }
        }

        IslandSystemState {
            id: systemState

            configuredLeftSwipeItems: userConfig.dynamicIslandLeftSwipeItems
            timeText: timeObj.currentTime
            dateText: timeObj.currentDateLabel
            currentWorkspace: islandContainer.currentWs
            customSwipeActive: customSwipeLoader.active
            // FORK: `|| musicPlaying` is the resting EQ's subscription, and
            // without it that EQ is decoration that can never move.
            //
            // cava is polled only while some client asks for it — upstream
            // asks only while the lyrics card is actually swiped into view
            // (rightSwipeProgress > 0.001), which is correct for upstream
            // because the bars only exist inside that card. The fork put a
            // second 4-bar instance on the CLOCK's side of the crossfade,
            // where rightSwipeProgress is exactly 0. So the bars rendered,
            // read their levels from a feed nobody had subscribed to, and
            // sat at zero forever. Nothing logs this: an unsubscribed cava
            // is not an error, it is just silence.
            lyricsCavaActive: (islandContainer.lyricsSwipeVisible
                    && islandContainer.rightSwipeProgress > 0.001)
                || islandContainer.musicPlaying

            onTransientRequested: function(icon, progress, text, rawPercent) {
                islandContainer.showTransientCapsule(icon, progress, text, rawPercent);
            }
        }

        CompositorWorkspaceTracker {
            id: workspaceTracker

            compositor: CompositorBackend.compositor
            hyprMonitor: root.hyprMonitor
            hyprMonitorName: root.hyprMonitorName
            outputName: root.compositorOutputName
            monitorFocused: root.monitorFocused

            onWorkspaceSynced: function(workspaceId) {
                islandContainer.currentWs = workspaceId;
            }

            onWorkspaceActivated: function(workspaceId) {
                islandContainer.showWorkspaceCapsule(workspaceId);
            }
        }

        Behavior on osdProgress {
            enabled: islandContainer.osdProgressAnimationEnabled

            SmoothedAnimation { velocity: 1.2; duration: 180; easing.type: Easing.InOutQuad }
        }
        // FORK: the swipe settle. This one keeps its shorter budget — it is
        // the release of a direct-manipulation gesture, and a gesture that
        // keeps travelling for 400ms after your finger stops feels detached
        // from the finger. But it springs, because the overshoot is exactly
        // the "it has mass" cue that makes a flick read as a flick.
        // Duration 0 while the gesture is live is upstream's, and correct:
        // the capsule must track the finger 1:1.
        Behavior on swipeTransitionProgress {
            NumberAnimation {
                duration: capsuleMouseArea.sideSwipeInteractive ? 0 : islandContainer.swipeAnimationDuration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Motion.spring()
            }
        }

        Keys.onPressed: (event) => {
            if (!root.overviewVisible) return;

            const view = islandContainer.overviewView;
            if (event.key === Qt.Key_H) {
                if (view)
                    view.focusAdjacentWorkspace(0, -1);
                event.accepted = true;
            } else if (event.key === Qt.Key_J) {
                if (view)
                    view.focusAdjacentWorkspace(1, 0);
                event.accepted = true;
            } else if (event.key === Qt.Key_K) {
                if (view)
                    view.focusAdjacentWorkspace(-1, 0);
                event.accepted = true;
            } else if (event.key === Qt.Key_L) {
                if (view)
                    view.focusAdjacentWorkspace(0, 1);
                event.accepted = true;
            } else if ((event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier)) || event.key === Qt.Key_Backtab) {
                if (root.hyprlandIntegration)
                    root.hyprlandIntegration.focusWorkspace("r-1");
                event.accepted = true;
            } else if (event.key === Qt.Key_Tab) {
                if (root.hyprlandIntegration)
                    root.hyprlandIntegration.focusWorkspace("r+1");
                event.accepted = true;
            }
        }

        function handleConfiguredClickAction(actionName) {
            switch (actionName) {
            case "":
            case "none":
                return;
            case "toggleExpandedPlayer":
                if (islandState === "expanded") {
                    autoHideTimer.stop();
                    smartRestoreState();
                } else {
                    showExpandedPlayer(false);
                }
                return;
            case "openExpandedPlayer":
                showExpandedPlayer(false);
                return;
            case "closeExpandedPlayer":
                if (islandState === "expanded")
                    smartRestoreState();
                return;
            case "toggleNotificationCenter":
                if (islandState === "notification_center")
                    smartRestoreState();
                else
                    showNotificationCenter();
                return;
            case "openNotificationCenter":
                showNotificationCenter();
                return;
            case "closeNotificationCenter":
                if (islandState === "notification_center")
                    smartRestoreState();
                return;
            case "toggleControlCenter":
                if (islandState === "control_center")
                    smartRestoreState();
                else
                    showControlCenter();
                return;
            case "openControlCenter":
                showControlCenter();
                return;
            case "closeControlCenter":
                if (islandState === "control_center")
                    smartRestoreState();
                return;
            case "toggleOverview":
                root.toggleOverviewEverywhere();
                return;
            case "openOverview":
                root.openOverviewEverywhere();
                return;
            case "closeOverview":
                root.closeOverviewEverywhere();
                return;
            case "toggleLyrics":
                if (restingState === "lyrics")
                    showTimeCapsule();
                else
                    showLyricsCapsule();
                return;
            case "showLyrics":
                showLyricsCapsule();
                return;
            case "showTime":
                showTimeCapsule();
                return;
            case "restoreRestingCapsule":
                smartRestoreState();
                return;
            default:
            }
        }

        function clamp01(value) {
            return Math.max(0, Math.min(1, value));
        }

        function normalizeRestingState(nextState) {
            // FORK: `&& hasMediaSurface`. Was unconditional, which is what
            // let the island rest on a "No music playing" card. Now
            // symmetric with the custom branch below it.
            if (nextState === "lyrics" && hasMediaSurface) return "lyrics";
            if (nextState === "custom" && hasCustomLeftItems) return "custom";
            return "normal";
        }

        function restingStateProgress(nextState) {
            switch (normalizeRestingState(nextState)) {
            case "custom":
                return -1;
            case "lyrics":
                return 1;
            default:
                return 0;
            }
        }

        function restingStateSide(nextState) {
            switch (normalizeRestingState(nextState)) {
            case "custom":
                return "left";
            case "lyrics":
                return "right";
            default:
                return "none";
            }
        }

        function swipeRestProgressForState() {
            switch (islandState) {
            case "custom":
                return -1;
            case "lyrics":
                return 1;
            default:
                return 0;
            }
        }

        function currentTransientOriginSide() {
            switch (islandState) {
            case "custom":
                return "left";
            case "lyrics":
                return "right";
            case "long_capsule":
                return workspaceOriginSide;
            case "split":
                return splitOriginSide;
            default:
                return "none";
            }
        }

        function setOsdProgress(nextProgress, animate) {
            osdProgressAnimationReset.stop();
            osdProgressAnimationEnabled = animate;
            osdProgress = nextProgress;
            if (!animate) osdProgressAnimationReset.restart();
        }

        function abortSideTransientMode() {
            sideTransientRestoreTimer.stop();
            workspaceOriginSide = "none";
            splitOriginSide = "none";
        }

        function clearTransientCapsule() {
            setOsdProgress(-1.0, false);
            osdCustomText = "";
            notificationAppName = "";
            notificationSummary = "";
            notificationBody = "";
            notificationExpanded = false;
            bluetoothExpandedDevice = null;
        }

        function cleanNotificationText(text) {
            return String(text === undefined || text === null ? "" : text)
                .replace(/<[^>]*>/g, " ")
                .replace(/&nbsp;/g, " ")
                .replace(/&amp;/g, "&")
                .replace(/&quot;/g, "\"")
                .replace(/&lt;/g, "<")
                .replace(/&gt;/g, ">")
                .replace(/\s+/g, " ")
                .trim();
        }

        function prepareRestingCapsuleGeometry() {
            if (restingState === "custom")
                syncCustomCapsuleWidth();
            if (restingState === "lyrics")
                syncLyricsCapsuleWidth();
        }

        function applyRestingVisuals() {
            prepareRestingCapsuleGeometry();
            swipeTransitionProgress = restingStateProgress(restingState);
        }

        function sideSwipeRestProgressForProgress(progressValue) {
            if (progressValue <= -0.5) return -1;
            if (progressValue >= 0.5) return 1;
            return 0;
        }

        function sideSwipeRestWidthForProgress(progressValue) {
            if (progressValue <= -0.5) return customCapsuleWidth;
            if (progressValue >= 0.5) return lyricsCapsuleWidth;
            return userConfig.islandWidth;
        }

        function customSideSwipeDragDistance() {
            const view = customSwipeLoader.item;
            if (view && view.dragDistance > 0) return view.dragDistance;
            return Math.max(userConfig.islandWidth, customCapsuleWidth + 4);
        }

        function lyricsSideSwipeDragDistance() {
            const view = lyricsSwipeLoader.item;
            if (view && view.dragDistance > 0) return view.dragDistance;
            return Math.max(userConfig.islandWidth, lyricsCapsuleWidth + 2);
        }

        function sideSwipeDragDistanceForDirection(direction) {
            if (direction === "left") return customSideSwipeDragDistance();
            if (direction === "right") return lyricsSideSwipeDragDistance();
            return userConfig.islandWidth;
        }

        function advanceSideSwipeProgress(currentProgress, deltaX) {
            const minProgress = hasCustomLeftItems ? -1 : 0;
            let nextProgress = Math.max(minProgress, Math.min(1, currentProgress));
            let remainingDelta = deltaX;

            if (remainingDelta > 0) {
                if (nextProgress < 0) {
                    const leftDistance = Math.max(1, sideSwipeDragDistanceForDirection("left"));
                    const progressToCenter = Math.min(-nextProgress, remainingDelta / leftDistance);
                    nextProgress += progressToCenter;
                    remainingDelta -= progressToCenter * leftDistance;
                }

                if (remainingDelta > 0 && nextProgress < 1) {
                    const rightDistance = Math.max(1, sideSwipeDragDistanceForDirection("right"));
                    nextProgress = Math.min(1, nextProgress + remainingDelta / rightDistance);
                }
            } else if (remainingDelta < 0) {
                if (nextProgress > 0) {
                    const rightDistance = Math.max(1, sideSwipeDragDistanceForDirection("right"));
                    const progressToCenter = Math.min(nextProgress, -remainingDelta / rightDistance);
                    nextProgress -= progressToCenter;
                    remainingDelta += progressToCenter * rightDistance;
                }

                if (remainingDelta < 0 && nextProgress > minProgress) {
                    const leftDistance = Math.max(1, sideSwipeDragDistanceForDirection("left"));
                    nextProgress = Math.max(minProgress, nextProgress + remainingDelta / leftDistance);
                }
            }

            return Math.max(minProgress, Math.min(1, nextProgress));
        }

        function resolveSideSwipeSettle(startProgress, finalProgress) {
            let settleAction = "";
            let settleProgress = sideSwipeRestProgressForProgress(startProgress);
            let settleWidth = sideSwipeRestWidthForProgress(startProgress);

            // FORK: `hasMediaSurface &&`. Without it a right-swipe with no
            // player running settles onto the empty media card and stays
            // there, which is the same bug reachable by gesture.
            if (hasMediaSurface && finalProgress >= 0.56) {
                settleAction = "lyrics";
                settleProgress = 1;
                settleWidth = lyricsCapsuleWidth;
            } else if (hasCustomLeftItems && finalProgress <= -0.56) {
                settleAction = "custom";
                settleProgress = -1;
                settleWidth = customCapsuleWidth;
            } else if (startProgress <= -0.5) {
                if (finalProgress >= -0.44) {
                    settleAction = "time";
                    settleProgress = 0;
                    settleWidth = userConfig.islandWidth;
                }
            } else if (startProgress >= 0.5) {
                if (finalProgress <= 0.44) {
                    settleAction = "time";
                    settleProgress = 0;
                    settleWidth = userConfig.islandWidth;
                }
            } else {
                settleAction = "time";
                settleProgress = 0;
                settleWidth = userConfig.islandWidth;
            }

            return {
                action: settleAction,
                progress: settleProgress,
                width: settleWidth
            };
        }

        function beginSideSwipeSettle(targetWidth) {
            sideSwipeSettling = true;
            mainCapsule.displayedWidth = targetWidth;
            sideSwipeSettleReset.restart();
        }

        function cancelSideSwipeSettle() {
            sideSwipeSettleReset.stop();
            sideSwipeSettling = false;
        }

        function finishSideSwipeSettle() {
            sideSwipeSettling = false;
            mainCapsule.displayedWidth = mainCapsule.baseTargetWidth;
        }

        function restartAutoHideTimer(duration) {
            autoHideTimer.interval = duration === undefined ? defaultAutoHideInterval : duration;
            autoHideTimer.restart();
        }

        function stopAutoHideTimer() {
            autoHideTimer.stop();
            autoHideTimer.interval = defaultAutoHideInterval;
        }

        function requestExpandedPlayerKeyboardFocus() {
            const shouldGrabFocus = !expandedPlayerKeyboardFocusRequested;
            expandedPlayerKeyboardFocusRequested = true;
            if (shouldGrabFocus)
                expandedPlayerFocusTimer.restart();
        }

        function releaseExpandedPlayerKeyboardFocus() {
            expandedPlayerKeyboardFocusRequested = false;
        }

        function clampTimerInput(value, minValue, maxValue) {
            const parsed = parseInt(value, 10);
            if (isNaN(parsed)) return minValue;
            return Math.max(minValue, Math.min(maxValue, parsed));
        }

        function syncTimerDuration(hours, minutes) {
            cancelTimerCompletionAnimation();
            timerSelectedHours = clampTimerInput(hours, 0, 23);
            timerSelectedMinutes = clampTimerInput(minutes, 0, 59);
            timerTotalSeconds = timerSelectedHours * 3600 + timerSelectedMinutes * 60;
            timerRemainingSeconds = 0;
            timerRunning = false;
            timerActive = false;
        }

        function toggleTimer(hours, minutes) {
            if (timerCompletionAnimating)
                cancelTimerCompletionAnimation();

            if (timerRunning) {
                timerRunning = false;
                return;
            }

            if (!timerActive || timerRemainingSeconds <= 0) {
                syncTimerDuration(hours, minutes);
                timerRemainingSeconds = timerTotalSeconds;
                timerActive = timerRemainingSeconds > 0;
            }

            if (timerRemainingSeconds > 0)
                timerRunning = true;
        }

        function resetTimer() {
            cancelTimerCompletionAnimation();
            timerRemainingSeconds = 0;
            timerRunning = false;
            timerActive = false;
        }

        function startTimerCompletionAnimation() {
            timerCompletionPulse = 0;
            timerCompletionFlash = 0;
            timerCompletionAnimating = true;
        }

        function cancelTimerCompletionAnimation() {
            timerCompletionAnimating = false;
            timerCompletionPulse = 0;
            timerCompletionFlash = 0;
        }

        function showExpandedTimerPage() {
            openTimerPageWhenExpanded = true;
            showExpandedPlayer(false);
            if (expandedPlayerLoader.item && expandedPlayerLoader.item.openTimerPage) {
                expandedPlayerLoader.item.openTimerPage();
                openTimerPageWhenExpanded = false;
            }
        }

        function showTransientCapsule(icon, progress, customText, rawPercent) {
            if (progress === undefined)    progress = -1.0;
            if (customText === undefined)  customText = "";
            // -1 = "no raw value"; the ring then derives its label from
            // progress, which is correct for everything that cannot exceed
            // 100%. See the transientRequested signal in IslandSystemState.
            if (rawPercent === undefined)  rawPercent = -1.0;

            // FORK SETTING, forkRingOsdEnabled. Hand GAUGE-shaped calls to
            // the standalone ring window instead of the island's split
            // capsule. See qml/osd/RingOsdWindow.qml.
            //
            // ---- THIS MUST COME BEFORE THE TWO GUARDS BELOW ----
            //
            // It did not, and the bug was reported as "in media mode the
            // volume/brightness ring does not appear". Both guards exist to
            // protect the ISLAND's split capsule:
            //
            //   autoHideSuppressesTransientReveal — do not un-hide a hidden
            //     island just because the volume moved.
            //   blocksTransientSplit (openPanelState || "notification") — do
            //     not let an OSD replace a panel the user deliberately
            //     opened.
            //
            // The ring is a different SURFACE. It cannot un-hide the island
            // because it is not the island, and it cannot overwrite an open
            // panel because it does not share the capsule with one. Sitting
            // behind those returns meant the ring was suppressed in exactly
            // the state where an on-screen volume readout is most wanted:
            // the expanded player is an openPanelState, so adjusting volume
            // while looking at what is playing showed nothing at all.
            //
            // The guards still run, unchanged, for the island path below.
            if (progress >= 0
                    && shellRootController
                    && shellRootController.forkSettings
                    && shellRootController.forkSettings.ringOsdEnabled) {
                shellRootController.showRingOsd(icon, progress, rawPercent);
                return;
            }

            if (root.autoHideSuppressesTransientReveal) return;
            if (blocksTransientSplit) return;
            //
            // `progress >= 0` is the whole test, and it is not a proxy for
            // "is this volume or brightness": this one function is also how
            // the mode indicator and every showText/showTextWithIcon IPC
            // reaches the island, and those pass -1. Routing on the caller's
            // identity would need a fifth argument threaded through six call
            // sites; routing on whether there is a VALUE TO PLOT is exactly
            // the question a ring answers, and the ones with no value have
            // nothing to draw in it.
            const nextProgress = progress >= 0 ? progress : -1.0;
            const animateProgress = islandState === "split" && osdProgress >= 0 && nextProgress >= 0;
            const animateFromSide = currentTransientOriginSide();

            abortSideTransientMode();
            splitIcon = icon;
            osdCustomText = customText;
            setOsdProgress(nextProgress, animateProgress);
            splitOriginSide = animateFromSide;
            islandState = "split";
            swipeTransitionProgress = 0;
            restartAutoHideTimer();
        }

        function showNotificationCapsule(appName, summary, body) {
            // openPanelState, not blocksTransientSplit: a notification may
            // replace a notification (that is how a burst reads), but may not
            // replace a panel someone opened. `theme-apply` fires one on every
            // theme change, which is how this was first seen landing on top of
            // an open chord HUD.
            if (root.overviewVisible || openPanelState) return;

            const cleanedAppName = cleanNotificationText(appName);
            const cleanedSummary = cleanNotificationText(summary);
            const cleanedBody = cleanNotificationText(body);
            const resolvedSummary = cleanedSummary !== ""
                ? cleanedSummary
                : (cleanedBody !== "" ? cleanedBody : "New notification");

            abortSideTransientMode();
            clearTransientCapsule();
            notificationAppName = cleanedAppName !== "" ? cleanedAppName : "Notification";
            notificationSummary = resolvedSummary;
            notificationBody = cleanedSummary !== "" ? cleanedBody : "";
            notificationExpanded = false;
            islandState = "notification";
            restartAutoHideTimer(notificationAutoHideInterval);
            // Store in notification history
                if (notificationHistoryModel) {
                    notificationHistoryModel.insert(0, {
                        appName: cleanedAppName !== "" ? cleanedAppName : "Notification",
                        summary: resolvedSummary,
                        body: cleanedSummary !== "" ? cleanedBody : "",
                        timestamp: new Date()
                    });
                    if (notificationHistoryModel.count > 50)
                        notificationHistoryModel.remove(50, notificationHistoryModel.count - 50);
                }

        }

        function toggleNotificationExpansionIfNeeded() {
            if (islandState !== "notification" || !notificationLoader.item || !notificationLoader.item.hasOverflowContent)
                return false;

            if (notificationExpanded) {
                smartRestoreState();
                return true;
            }

            notificationExpanded = true;
            stopAutoHideTimer();
            return true;
        }

        function suppressCapsuleClick(cancelPreparedOverview) {
            if (cancelPreparedOverview === undefined) cancelPreparedOverview = false;
            if (cancelPreparedOverview && capsuleMouseArea.preparedOverviewOnPress) {
                root.cancelPreparedOverviewEverywhere();
                capsuleMouseArea.preparedOverviewOnPress = false;
            }
            capsuleMouseArea.suppressNextClick = true;
            swipeSuppressReset.restart();
        }

        function restoreRestingCapsule(forceImmediate) {
            if (forceImmediate === undefined) forceImmediate = false;
            const normalizedRestingState = normalizeRestingState(restingState);
            const targetSide = restingStateSide(normalizedRestingState);
            const shouldAnimateToSide = targetSide !== "none"
                && ((islandState === "long_capsule" && workspaceOriginSide === targetSide)
                    || (islandState === "split" && splitOriginSide === targetSide));

            if (!forceImmediate && shouldAnimateToSide) {
                expandedByPlayerAutoOpen = false;
                prepareRestingCapsuleGeometry();
                swipeTransitionProgress = restingStateProgress(normalizedRestingState);
                stopAutoHideTimer();
                sideTransientRestoreTimer.restart();
                return;
            }

            abortSideTransientMode();
            prepareRestingCapsuleGeometry();
            islandState = normalizedRestingState;
            clearTransientCapsule();
            applyRestingVisuals();
            expandedByPlayerAutoOpen = false;
            stopAutoHideTimer();
        }

        function setRestingState(nextState) {
            restingState = normalizeRestingState(nextState);
        }

        function smartRestoreState() {
            // FORK: a mode indicator outlives the transients that interrupt
            // it. Pressing volume-up inside a submap should flash the volume
            // OSD and then go back to saying which submap you are in — not
            // silently drop you back to the clock while the chord is still
            // swallowing your keys. Every path back to rest funnels through
            // here, so re-asserting here covers all of them.
            // The key panel outranks the name indicator for the same reason
            // and by the same mechanism — it is the richer answer to the
            // same question, and while a submap is active it is what should
            // be on screen. Seen before this existed: entering `lang`, a
            // theme-apply notification arriving over it, and the island
            // then resting on the clock while the submap was still
            // swallowing every key.
            if (modeKeysName !== "") {
                showModeKeys(modeKeysName);
                return;
            }

            if (modeIndicatorActive) {
                assertModeIndicator();
                return;
            }

            restoreRestingCapsule();
        }

        function assertModeIndicator() {
            cancelSideSwipeSettle();
            abortSideTransientMode();
            splitIcon = modeIndicatorIcon;
            osdCustomText = modeIndicatorText;
            setOsdProgress(-1.0, false);
            splitOriginSide = "none";
            islandState = "split";
            swipeTransitionProgress = 0;
            mainCapsule.displayedWidth = mainCapsule.baseTargetWidth;
            // The whole point: no restartAutoHideTimer. This stays until
            // something clears it.
            stopAutoHideTimer();
        }

        function showModeIndicator(icon, text) {
            modeIndicatorIcon = icon === undefined || icon === null ? "" : String(icon);
            modeIndicatorText = text === undefined || text === null ? "" : String(text);

            if (modeIndicatorText === "") {
                clearModeIndicator();
                return;
            }

            modeIndicatorActive = true;
            assertModeIndicator();
        }

        function clearModeIndicator() {
            if (!modeIndicatorActive && modeIndicatorText === "")
                return;

            modeIndicatorActive = false;
            modeIndicatorText = "";
            modeIndicatorIcon = "";
            clearTransientCapsule();
            restoreRestingCapsule();
        }

        function showRestingCapsule(nextState) {
            setRestingState(nextState);
            restoreRestingCapsule();
            stopAutoHideTimer();
        }

        function showExpandedPlayer(autoOpened) {
            cancelSideSwipeSettle();
            abortSideTransientMode();
            clearTransientCapsule();
            islandState = "expanded";
            mainCapsule.displayedWidth = mainCapsule.baseTargetWidth;
            expandedByPlayerAutoOpen = autoOpened;
            if (autoOpened) restartAutoHideTimer();
            else stopAutoHideTimer();
        }

        function showBluetoothExpanded(device) {
            // Same correction as showWorkspaceCapsule: a device connecting is
            // a spontaneous event and must not take over an open panel.
            if (!device || root.overviewVisible || blocksTransientSplit)
                return;

            cancelSideSwipeSettle();
            abortSideTransientMode();
            clearTransientCapsule();
            bluetoothExpandedDevice = device;
            islandState = "bluetooth_expanded";
            mainCapsule.displayedWidth = mainCapsule.baseTargetWidth;
            expandedByPlayerAutoOpen = false;
            restartAutoHideTimer(bluetoothExpandedAutoHideInterval);
        }

        function showControlCenter() {
            cancelSideSwipeSettle();
            abortSideTransientMode();
            clearTransientCapsule();
            islandState = "control_center";
            mainCapsule.displayedWidth = mainCapsule.baseTargetWidth;
            stopAutoHideTimer();
        }

        function showNotificationCenter() {
            cancelSideSwipeSettle();
            abortSideTransientMode();
            clearTransientCapsule();
            islandState = "notification_center";
            mainCapsule.displayedWidth = mainCapsule.baseTargetWidth;
            stopAutoHideTimer();
        }


        function showWallpaperPicker() {
            cancelSideSwipeSettle();
            abortSideTransientMode();
            clearTransientCapsule();
            islandState = "wallpaper_picker";
            mainCapsule.displayedWidth = mainCapsule.baseTargetWidth;
            stopAutoHideTimer();
        }

        // FORK: the display panel — qtile's DisplayPopup (28 bindings),
        // the largest hole the migration left and the only one with no
        // fallback at all, since neither nwg-displays nor wdisplays is
        // installed. See qml/display/DisplayPanel.qml.
        function showDisplayPanel() {
            cancelSideSwipeSettle();
            abortSideTransientMode();
            clearTransientCapsule();
            islandState = "display_panel";
            mainCapsule.displayedWidth = mainCapsule.baseTargetWidth;
            stopAutoHideTimer();
        }

        // FORK: the audio panel — qtile's AudioPopup (25 bindings). The
        // control centre owns a Sound slider on the default sink; this owns
        // everything else that popup did. See qml/audio/AudioPanel.qml.
        function showAudioPanel() {
            cancelSideSwipeSettle();
            abortSideTransientMode();
            clearTransientCapsule();
            islandState = "audio_panel";
            mainCapsule.displayedWidth = mainCapsule.baseTargetWidth;
            stopAutoHideTimer();
        }

        // FORK: the Wi-Fi QR, so a phone joins by camera instead of by
        // reading the PSK off the screen. See qml/wifi/WifiQrLayer.qml.
        function showWifiQr() {
            cancelSideSwipeSettle();
            abortSideTransientMode();
            clearTransientCapsule();
            islandState = "wifi_qr";
            mainCapsule.displayedWidth = mainCapsule.baseTargetWidth;
            stopAutoHideTimer();
        }

        // FORK: the calendar — DESIGN-SPEC.md's state list, with no qtile
        // ancestor at all. See qml/island/CalendarLayer.qml.
        function showCalendar() {
            cancelSideSwipeSettle();
            abortSideTransientMode();
            clearTransientCapsule();
            islandState = "calendar";
            mainCapsule.displayedWidth = mainCapsule.baseTargetWidth;
            stopAutoHideTimer();
        }

        // FORK: the power menu — the island's replacement for `dm-logout -r`
        // (rofi). See qml/island/PowerMenuLayer.qml.
        function showPowerMenu() {
            cancelSideSwipeSettle();
            abortSideTransientMode();
            clearTransientCapsule();
            islandState = "power_menu";
            mainCapsule.displayedWidth = mainCapsule.baseTargetWidth;
            stopAutoHideTimer();
        }

        // FORK: the settings surface. The packaged tide-island-config-app is
        // a compiled binary that `yay -Syu` overwrites, so this is a state
        // rather than a patch. See qml/island/SettingsLayer.qml.
        function showSettings() {
            cancelSideSwipeSettle();
            abortSideTransientMode();
            clearTransientCapsule();
            islandState = "settings";
            mainCapsule.displayedWidth = mainCapsule.baseTargetWidth;
            stopAutoHideTimer();
        }

        // FORK: the generic list picker. `name` is one word — windows,
        // processes, workspaces — which is what makes it safe across an IPC
        // that splits arguments on whitespace (ModeKeysLayer.qml has the
        // full account of what happens when an argument is not).
        //
        // pickerMenu is assigned BEFORE islandState, so the PanelLoader
        // builds a PickerLayer that already knows its menu and fetches it
        // once. The other order works too and costs one wasted `--list` of
        // the previous menu, plus a frame of the wrong title in the header.
        //
        // clearPicker exists as the counterpart to showPicker for the same
        // reason clearModeKeys does — something outside the shell may need
        // to take the panel down without knowing whether it is up — but
        // unlike the chord HUD nothing drives it yet: the picker is closed
        // by its own Esc, or by running a row. It is here so that a caller
        // that needs it does not have to reach for smartRestoreState.
        function showPicker(name) {
            cancelSideSwipeSettle();
            abortSideTransientMode();
            clearTransientCapsule();
            pickerMenu = name;
            islandState = "picker";
            mainCapsule.displayedWidth = mainCapsule.baseTargetWidth;
            stopAutoHideTimer();
        }

        function clearPicker() {
            if (islandState === "picker")
                smartRestoreState();
        }

        // FORK: the polkit password prompt. See qml/island/PolkitPromptLayer.qml
        // — and read the safety note there before enabling it, because a
        // wrong polkit agent means NO password prompts anywhere on the
        // system and fails silently until you need one.
        function showPolkitPrompt() {
            cancelSideSwipeSettle();
            abortSideTransientMode();
            clearTransientCapsule();
            islandState = "polkit_prompt";
            mainCapsule.displayedWidth = mainCapsule.baseTargetWidth;
            stopAutoHideTimer();
        }

        // FORK: the chord heads-up display. Entering a submap calls this;
        // leaving one calls clearModeKeys. Both come from
        // hypr/scripts/submap-indicator.sh, which is watching Hyprland's
        // event socket.
        //
        // stopAutoHideTimer, like every other panel: a chord lasts as long
        // as you are in it, and an auto-hide would take the hints away
        // while the mode was still swallowing keys — which is exactly the
        // never-expiring-indicator problem the shell script already had to
        // solve from the other direction.
        function showModeKeys(name) {
            // FORK SETTING, forkModeKeysEnabled. Off falls back to the mode
            // NAME alone in the transient capsule — which is precisely what
            // submap-indicator.sh did before ModeKeysLayer existed, and what
            // the settings row for this switch has always promised it would
            // do. Until now the switch was read by nothing and both
            // positions drew the full key grid.
            if (shellRootController && shellRootController.forkSettings
                    && !shellRootController.forkSettings.modeKeysEnabled) {
                showTransientCapsule("", -1, String(name).toUpperCase());
                return;
            }

            cancelSideSwipeSettle();
            abortSideTransientMode();
            clearTransientCapsule();
            modeKeysName = name;
            islandState = "mode_keys";
            mainCapsule.displayedWidth = mainCapsule.baseTargetWidth;
            stopAutoHideTimer();
        }

        function clearModeKeys() {
            modeKeysName = "";
            if (islandState === "mode_keys")
                smartRestoreState();
        }

        // FORK: the cheatsheets. stopAutoHideTimer for the same reason
        // every other panel does it — this one is READ, and a sheet that
        // withdrew itself after a few seconds would be useless at exactly
        // the moment you were still looking for the key.
        function showCheatsheet(which) {
            cancelSideSwipeSettle();
            abortSideTransientMode();
            clearTransientCapsule();
            // Set BEFORE the state, so the layer the Loader is about to
            // build already has the right sheet and fetches it once
            // instead of loading `hypr` and then switching.
            cheatsheetWhich = which;
            islandState = "cheatsheet";
            mainCapsule.displayedWidth = mainCapsule.baseTargetWidth;
            stopAutoHideTimer();
        }

        // FORK: the theme switcher, which DESIGN-SPEC.md lists as one of
        // the island's states and which upstream does not have.
        function showThemePicker() {
            cancelSideSwipeSettle();
            abortSideTransientMode();
            clearTransientCapsule();
            islandState = "theme_picker";
            mainCapsule.displayedWidth = mainCapsule.baseTargetWidth;
            stopAutoHideTimer();
        }

        function showApplicationLauncher() {
            cancelSideSwipeSettle();
            abortSideTransientMode();
            clearTransientCapsule();
            islandState = "application_launcher";
            mainCapsule.displayedWidth = mainCapsule.baseTargetWidth;
            stopAutoHideTimer();
        }

        function showCustomCapsule() {
            if (!hasCustomLeftItems) {
                showTimeCapsule();
                return;
            }

            systemState.refreshMissingValues();
            showRestingCapsule("custom");
        }

        function showLyricsCapsule() {
            showRestingCapsule("lyrics");
        }

        function showTimeCapsule() {
            showRestingCapsule("normal");
        }

        function showWorkspaceCapsule(wsId) {
            // currentWs is updated even when the capsule is suppressed: it is
            // the resting capsule's own workspace readout, not the OSD.
            currentWs = wsId;
            if (root.autoHideSuppressesTransientReveal) return;
            // Was a hand-written two-item list; see blocksTransientSplit for
            // what that cost. A workspace switch is a transient exactly like
            // a volume OSD and is now gated by the same list.
            if (blocksTransientSplit) return;
            const animateFromSide = currentTransientOriginSide();
            clearTransientCapsule();
            sideTransientRestoreTimer.stop();
            workspaceOriginSide = animateFromSide;
            splitOriginSide = "none";
            islandState = "long_capsule";
            swipeTransitionProgress = 0;
            restartAutoHideTimer();
        }

        Timer { id: autoHideTimer; interval: islandContainer.defaultAutoHideInterval; onTriggered: islandContainer.smartRestoreState() }
        Timer {
            id: islandTimerTick
            interval: 1000
            repeat: true
            running: islandContainer.timerRunning
            onTriggered: {
                const nextRemainingSeconds = Math.max(0, islandContainer.timerRemainingSeconds - 1);
                if (nextRemainingSeconds <= 0) {
                    islandContainer.startTimerCompletionAnimation();
                    islandContainer.timerRemainingSeconds = 0;
                    islandContainer.timerRunning = false;
                    islandContainer.timerActive = false;
                } else {
                    islandContainer.timerRemainingSeconds = nextRemainingSeconds;
                }
            }
        }
        Timer {
            id: osdProgressAnimationReset
            interval: 0
            onTriggered: islandContainer.osdProgressAnimationEnabled = true
        }
        Timer {
            id: sideTransientRestoreTimer
            interval: islandContainer.swipeAnimationDuration
            onTriggered: {
                islandContainer.workspaceOriginSide = "none";
                islandContainer.splitOriginSide = "none";
                islandContainer.prepareRestingCapsuleGeometry();
                islandContainer.islandState = islandContainer.normalizeRestingState(islandContainer.restingState);
                islandContainer.clearTransientCapsule();
                islandContainer.applyRestingVisuals();
                islandContainer.expandedByPlayerAutoOpen = false;
            }
        }
        Timer {
            id: sideSwipeSettleReset
            interval: mainCapsule.morphDuration
            onTriggered: islandContainer.finishSideSwipeSettle()
        }
        Timer {
            id: hoverExpandDelayTimer
            interval: 350
            repeat: false
            onTriggered: {
                if (!capsuleMouseArea.containsMouse) return;
                if (!root.hoverExpandEnabled) return;

                const current = islandContainer.islandState;
                const target = root.configuredHoverExpandAction === 2 ? "control_center" : "expanded";
                if (current === target) return;
                if (current !== "normal" && current !== "custom" && current !== "lyrics")
                    return;

                islandContainer.hoverExpandedActive = true;
                if (root.configuredHoverExpandAction === 2)
                    islandContainer.showControlCenter();
                else
                    islandContainer.showExpandedPlayer(false);
            }
        }
        Timer {
            id: hoverCollapseDelayTimer
            interval: 250
            repeat: false
            onTriggered: {
                if (capsuleMouseArea.containsMouse) return;
                if (!islandContainer.hoverExpandedActive) return;
                islandContainer.hoverExpandedActive = false;
                islandContainer.smartRestoreState();
            }
        }

        function syncCustomCapsuleWidth() {
            const view = customSwipeLoader.item;
            if (!view) return;
            customCapsuleWidth = Math.max(220, Math.min(root.width - 48, view.preferredWidth));
        }

        function syncLyricsCapsuleWidth() {
            const view = lyricsSwipeLoader.item;
            if (!view) return;
            lyricsCapsuleWidth = Math.max(220, Math.min(root.width - 48, view.preferredWidth));
        }

        onCurrentTrackChanged: {
            if (userConfig.disableAutoExpandOnTrackChange) return;
            if (currentTrack !== ""
                    && islandState !== "control_center"
                    && islandState !== "notification"
                    && islandState !== "bluetooth_expanded") {
                if (root.autoHideSuppressesTransientReveal) return;
                if (islandState === "expanded" && !expandedByPlayerAutoOpen) return;
                showExpandedPlayer(true);
            }
        }

        // FORK: the notch skirt — the overshoot band and the two concave
        // flares, drawn as ONE path so that nothing ever appears or
        // disappears; every vertex is a continuous function of
        // root.notchProgress. At notchProgress 0 the path collapses to a
        // zero-area sliver on the capsule's own top edge and the floating
        // pill is exactly what upstream drew.
        //
        // Why this is a sibling of mainCapsule and not part of it: a
        // Rectangle cannot be concave, and mainCapsule has clip:true plus
        // ~40 anchored children. Painting the flares inside it would clip
        // them away; changing its bounds to make room would move all of
        // them. The skirt owns no content, so it can be any shape it likes.
        //
        // Both are opaque #000 and share exact edges, so the join is
        // invisible — there is no alpha blending at a hard vertical edge
        // between two identical opaque fills. It sits BELOW the capsule
        // (z 4 vs 5) so the capsule's own border, when it has one, still
        // draws on top.
        Shape {
            id: notchSkirt
            z: 4
            visible: root.notchProgress > 0.001 && root.autoHideProgress > 0.001
            opacity: root.autoHideProgress
            preferredRendererType: Shape.CurveRenderer

            // Live, animated values. F and O are what the two phases drive:
            // O (overshoot) rides phase 1 alongside the un-rounding, so the
            // shape is already sealed against the top edge before the flares
            // start growing; F rides phase 2.
            readonly property real f: root.notchFlareSize * root.notchFlareProgress
            readonly property real o: root.notchOvershoot * root.notchUnround
            // Quarter-circle-to-cubic constant. 4/3*(sqrt(2)-1); a cubic
            // with its controls this far along the tangents is within 0.03%
            // of a true quarter arc, and unlike PathArc it leaves no room
            // for a sweep-direction mistake that silently draws the arc the
            // long way round.
            readonly property real kappa: 0.5522847498

            x: mainCapsule.x - f
            y: mainCapsule.y - o
            width: mainCapsule.width + f * 2
            height: o + f

            ShapePath {
                fillColor: mainCapsule.color
                strokeWidth: -1

                // Clockwise from the top-left of the bounding box. The band
                // above local y = o is the overshoot: it is off-screen and
                // exists only because the drop shadow's padding otherwise
                // leaves a 1-2 px line of desktop above the notch.
                startX: 0
                startY: 0
                PathLine { x: notchSkirt.width; y: 0 }
                PathLine { x: notchSkirt.width; y: notchSkirt.o }

                // Right flare. A fillet between the screen's top edge and
                // the capsule's right side: full flared width at the top,
                // tapering to the capsule's own width one flare-height down.
                // Concave because the fill lies OUTSIDE the circle, which is
                // what makes it read as the shape blooming into the bezel
                // rather than as a chamfer stuck on the side.
                PathCubic {
                    control1X: notchSkirt.width - notchSkirt.kappa * notchSkirt.f
                    control1Y: notchSkirt.o
                    control2X: notchSkirt.width - notchSkirt.f
                    control2Y: notchSkirt.o + notchSkirt.f - notchSkirt.kappa * notchSkirt.f
                    x: notchSkirt.width - notchSkirt.f
                    y: notchSkirt.o + notchSkirt.f
                }

                PathLine { x: notchSkirt.f; y: notchSkirt.o + notchSkirt.f }

                // Left flare, mirrored.
                PathCubic {
                    control1X: notchSkirt.f
                    control1Y: notchSkirt.o + notchSkirt.f - notchSkirt.kappa * notchSkirt.f
                    control2X: notchSkirt.kappa * notchSkirt.f
                    control2Y: notchSkirt.o
                    x: 0
                    y: notchSkirt.o
                }

                PathLine { x: 0; y: 0 }
            }
        }

        // ------------------------------------------------------------
        //  FORK: the island's flanks.
        // ------------------------------------------------------------
        //  A workspace chip and one ring per open window, living in the
        //  empty bar either side of the notch. SIBLINGS of mainCapsule and
        //  never children: every one of the ~20 islandState cases in
        //  baseTargetWidth is arithmetic against islandWidth, and a second
        //  permanent occupant of the capsule means revisiting all of them.
        //  Out here the pill's geometry is untouched.
        //
        //  z:4 keeps them UNDER mainCapsule (z:5), so a panel that morphs
        //  out to 980 px simply covers them rather than having to fight
        //  them for the same pixels.
        //
        //  Positioned against the RESTING band, not against mainCapsule's
        //  animating y/height. Anchoring to a rectangle that springs and
        //  overshoots would make the flanks bounce in sympathy with every
        //  panel that opens, and they are not part of that motion.
        //
        //  They are drawn but not clickable: the window's input Region is
        //  built from mainCapsule's rectangle alone. That is deliberate —
        //  see the mask near the top of this file.
        Item {
            id: islandFlanks
            // 4 -> 6, ABOVE mainCapsule's z 5.
            //
            // The workspace ring now sits inside the capsule, and z is
            // resolved among SIBLINGS: raising the chip inside this Item
            // reorders it against the other flank children and does nothing
            // against the capsule, which is a sibling of this whole Item.
            // The chip was drawn, composited under an opaque rounded
            // rectangle, and completely invisible — with no warning, because
            // nothing was wrong.
            //
            // Safe for the rest of the flanks: the icons sit outside the pill
            // where there is nothing to be above, and the whole strip is
            // hidden unless restingNow.
            z: 6

            // ---- CENTRED ON THE CAPSULE, NOT ON THE SURFACE ----
            //
            // Was `islandTopMargin + islandHeight / 2`, which looks like the
            // island's centre line and is not. `islandHeight` is the LAYER
            // SURFACE's height — 58 px here — while the resting pill is only
            // about 33 px of that, hung from the top. So this centred the
            // flanks on the whole surface and everything else (the clock, and
            // the timer ring beside it) centred on the pill.
            //
            // Measured on screen rather than reasoned: the timer ring's
            // centre sits at y 16.5, the app icons' at y 30.5. Exactly the
            // 14 px this expression is off by, and the reason the icons kept
            // reading as sitting in the wrong place no matter what was done
            // to the ring itself.
            //
            // mainCapsule's own centre cannot drift from the pill, because it
            // IS the pill. Only read while restingNow is true, so the
            // capsule's height here is always the resting height.
            readonly property real restingCenterY:
                mainCapsule.y + mainCapsule.height / 2
            readonly property real pillLeft: mainCapsule.x
            readonly property real pillRight: mainCapsule.x + mainCapsule.width
            readonly property real gap: Metrics.px(14)

            // Shown only while the capsule is at its RESTING size. Tested on
            // targetHeight rather than on the state NAME: targetHeight jumps
            // the instant a state changes, so the flanks start fading as the
            // panel starts growing, and the test cannot rot when a new
            // islandState is added and nobody updates a list of names here.
            readonly property bool restingNow:
                !root.overviewVisible
                && mainCapsule.targetHeight <= userConfig.islandHeight + 1

            // ToplevelManager, not `hyprctl clients`: the foreign-toplevel
            // protocol is live, so this updates on open/close with no poll.
            readonly property var openWindows: {
                const out = [];
                const manager = ToplevelManager;
                if (!manager || !manager.toplevels)
                    return out;
                const values = manager.toplevels.values;
                const focused = manager.activeToplevel;

                // ---- FILTERED TO THE CURRENT WORKSPACE ----
                //
                // ToplevelManager is the foreign-toplevel protocol, which is
                // live and carries appId and title but knows nothing about
                // workspaces — Wayland has no such concept. Hyprland does, so
                // the workspace comes from Quickshell.Hyprland, which keeps a
                // HyprlandToplevel per surface with a `wayland` back-pointer
                // to exactly these objects. Matching on that pointer rather
                // than on title or appId matters: two kitty windows share
                // both, and a match by either would put them on the wrong
                // workspace half the time.
                //
                // GUARDED, AND DELIBERATELY FAILING OPEN. If the Hyprland
                // list is empty — which is what a throwaway instance reports,
                // the same way ToplevelManager does before the shell owns a
                // surface — every window is shown rather than none. A strip
                // that silently empties itself is indistinguishable from a
                // broken strip; showing too much is at least legible.
                const hlValues = (typeof Hyprland !== "undefined" && Hyprland
                                  && Hyprland.toplevels)
                    ? Hyprland.toplevels.values : [];
                const currentWs = Hyprland && Hyprland.focusedWorkspace
                    ? Hyprland.focusedWorkspace.id : -1;
                const wsFor = new Map();
                for (let h = 0; h < hlValues.length; h++) {
                    const ht = hlValues[h];
                    if (ht && ht.wayland && ht.workspace)
                        wsFor.set(ht.wayland, ht.workspace.id);
                }
                const canFilter = wsFor.size > 0 && currentWs > 0;

                for (let index = 0; index < values.length; index++) {
                    const entry = values[index];
                    if (!entry)
                        continue;
                    if (canFilter && wsFor.get(entry) !== currentWs)
                        continue;
                    out.push({
                        appId: entry.appId,
                        title: entry.title,
                        active: entry === focused
                    });
                }
                if (root.flankDebug)
                    console.log("FLANK| hl=" + hlValues.length + " ws=" + currentWs
                                + " canFilter=" + canFilter
                                + " in=" + values.length + " out=" + out.length);
                return out;
            }

            WorkspaceChip {
                id: workspaceChip
                // ---- INSIDE THE CAPSULE, NOT BESIDE IT ----
                //
                // Was `pillLeft - gap - width`, i.e. out on the wallpaper to
                // the left of the pill. WorkspaceChip's own header explains
                // why it started there: putting it in the capsule means the
                // capsule has to grow, and ~20 islandState cases in
                // baseTargetWidth do arithmetic against that width.
                //
                // Asked for anyway, and the objection is answered rather than
                // ignored: only the RESTING width grows, through
                // restingWorkspaceAllowance, exactly as musicPlaying already
                // grows it for the EQ bars. Every other islandState case is
                // untouched, because every other state replaces the resting
                // content wholesale rather than adding to it.
                //
                // Hung off the capsule's own left edge with the same inner
                // padding the clock uses, and centred on the capsule rather
                // than on the layer surface — see restingCenterY.
                // Above mainCapsule, which sits at z 5. The flanks are a
                // sibling of the capsule and default to z 0, so the moment
                // this moved from beside the pill to inside it the chip went
                // BEHIND the pill and vanished — drawn, composited under an
                // opaque rounded rectangle, and completely invisible.
                z: 6
                x: mainCapsule.x + Metrics.pad(10)
                y: islandFlanks.restingCenterY - height / 2
                workspaceId: islandContainer.currentWs
                textFontFamily: root.textFontFamily
                accentColor: islandTheme.accent
                fillColor: islandTheme.shellFill
                showCondition: islandFlanks.restingNow
                revealProgress: root.autoHideProgress
            }

            WindowRingStrip {
                id: leftRings
                side: "left"
                x: islandFlanks.pillLeft - islandFlanks.gap - width
                y: islandFlanks.restingCenterY - height / 2
                windows: islandFlanks.openWindows
                textFontFamily: root.textFontFamily
                accentColor: islandTheme.accent
                plateColor: islandTheme.shellFill
                showCondition: islandFlanks.restingNow
                revealProgress: root.autoHideProgress
            }

            WindowRingStrip {
                id: rightRings
                side: "right"
                x: islandFlanks.pillRight + islandFlanks.gap
                y: islandFlanks.restingCenterY - height / 2
                windows: islandFlanks.openWindows
                textFontFamily: root.textFontFamily
                accentColor: islandTheme.accent
                plateColor: islandTheme.shellFill
                showCondition: islandFlanks.restingNow
                revealProgress: root.autoHideProgress
            }
        }

        // --- UI 渲染：灵动岛主干 ---
        Rectangle {
            id: mainCapsule
            z: 5
            // FORK: was a bare `property int morphDuration: 400`. Same 400,
            // but sourced from Motion.js so the whole shell's speed is one
            // number (Motion.SCALE) rather than 92 literals. A Timer and
            // ExpandedPlayerLayer's sliderIntroDelay both synchronise
            // against this, which is why the duration is kept at the spec
            // value and the SHAPE of the curve does the speeding up.
            // Nothing assigns to it, so readonly is safe.
            readonly property int morphDuration: Motion.morphDuration()

            // ---- DISTANCE-AWARE MORPH ----
            //
            // See Motion.js, "ONE DURATION FOR A 40 px MOVE AND A 1000 px
            // ONE WAS THE BUG". The 980 px resting -> control-centre morph
            // and the 40 px EQ allowance both ran at 400 ms; this latches
            // how far the shape is about to travel so the duration can
            // scale with it.
            //
            // LATCHED IN A ScriptAction, not bound. The obvious spelling,
            //     duration: Motion.morphDurationFor(baseTargetWidth - displayedWidth)
            // reads the property the Behavior is animating, so as
            // displayedWidth closes on its target the distance falls to
            // zero and the duration is rewritten UNDER the running
            // animation — Qt applies a mid-flight setDuration, and the
            // morph snaps. A ScriptAction at the head of the Behavior runs
            // once, before the first frame, while displayedWidth is still
            // the OLD value and baseTargetWidth is already the new one.
            property int pendingMorphPx: 0
            readonly property int distanceMorphDuration: Motion.morphDurationFor(pendingMorphPx)
            readonly property bool notificationHistorySurface: islandContainer.islandState === "notification_center"
            property real outlineWidth: root.overviewContentVisible || notificationHistorySurface ? 1 : 0
            property color outlineColor: root.overviewContentVisible
                ? root.overviewCapsuleBorderColor
                : (notificationHistorySurface ? "#1affffff" : StyleTokens.clearBlack)
            property real displayedWidth: baseTargetWidth
            readonly property real baseTargetWidth: {
                if (root.overviewVisible) return root.overviewCapsuleWidth;
                if (sideTransientRestoreTimer.running) {
                    if (islandContainer.restingState === "lyrics"
                            && ((islandContainer.islandState === "split" && islandContainer.splitOriginSide === "right")
                                || (islandContainer.islandState === "long_capsule" && islandContainer.workspaceOriginSide === "right"))) {
                        return islandContainer.lyricsCapsuleWidth;
                    }

                    if (islandContainer.restingState === "custom"
                            && ((islandContainer.islandState === "split" && islandContainer.splitOriginSide === "left")
                                || (islandContainer.islandState === "long_capsule" && islandContainer.workspaceOriginSide === "left"))) {
                        return islandContainer.customCapsuleWidth;
                    }
                }

                switch (islandContainer.islandState) {
                case "split":
                    return islandContainer.splitCapsuleWidth;
                case "long_capsule":
                    return Metrics.px(220);
                case "custom":
                    return islandContainer.customCapsuleWidth;
                case "lyrics":
                    return islandContainer.lyricsCapsuleWidth;
                case "control_center":
                    return Metrics.px(420);
                case "notification_center":
                    return Metrics.px(410);
                case "wallpaper_picker":
                case "application_launcher":
                    return Metrics.px(1100);
                case "display_panel":
                    // Wider than the theme picker because the layout is a
                    // list AND a details column side by side: an output row
                    // is "eDP-1 (laptop) 1366x768" and the details are
                    // "position", "scale", "rotation", "mirror" with values.
                    // Neither elides well, and eliding the one field that
                    // says what a change did is the worst place to save
                    // width.
                    return Math.min(Metrics.px(900), root.width - Metrics.px(48));
                case "audio_panel":
                    // The same list-plus-details shape as the display panel,
                    // and a touch wider: a device row carries a name, a level
                    // bar and a readout side by side, and the details column
                    // holds free text (a bluez profile description, a media
                    // title) that elides badly.
                    return Math.min(Metrics.px(940), root.width - Metrics.px(48));
                case "wifi_qr":
                    // Square-ish and narrow, because the content is one
                    // square symbol. Anything wider is white card the phone
                    // does not need and the eye has to cross.
                    return Metrics.px(360);
                case "calendar":
                    // Narrow on purpose, and the narrowest panel in the
                    // shell after the QR. The content is seven columns of
                    // two-digit numbers; every pixel past what those need is
                    // black the eye has to cross to get from Monday to
                    // Sunday. Seven cells at Metrics.px(34) = 31 is 217,
                    // plus 2 x Metrics.pad(18) = 36 of padding, = 253. 276
                    // leaves the grid a little air on each side without the
                    // columns drifting apart.
                    return Metrics.px(300);
                case "power_menu":
                    // Six actions in one column, each a label plus a short
                    // explanation of what it actually runs ("systemctl
                    // poweroff", "loginctl terminate-session"). The
                    // explanation is the reason for the width: a power menu
                    // where you cannot see which of reboot and shutdown you
                    // are about to press is the one panel where a misread is
                    // expensive.
                    return Metrics.px(400);
                case "settings":
                    // The list-plus-details shape the display and audio
                    // panels use, and sized between them: rows are
                    // "Notch mode          on", and the details column
                    // carries a paragraph saying what the key does and
                    // whether the packaged config app knows about it.
                    return Math.min(Metrics.px(860), root.width - Metrics.px(48));
                case "picker":
                    // The same list-plus-details shape as settings, and the
                    // same width, because the content is the same size:
                    // a row is one elided line and the column beside it
                    // carries the thing that disambiguates it. Measured on
                    // the `windows` menu, whose worst row on this session is
                    // "Reacher (2022) — Watch on Cineby - Brave" against a
                    // detail of "brave-browser · workspace 5" — narrower
                    // than 860 and the title elides while its own
                    // disambiguator is still on screen, which is the one
                    // thing this panel must not do.
                    return Math.min(Metrics.px(860), root.width - Metrics.px(48));
                case "polkit_prompt":
                    // Deliberately modest. This is a password field and one
                    // line of "<app> is asking to <do thing>"; a wide panel
                    // makes the field wide, and a wide field invites reading
                    // the dots as progress.
                    return Metrics.px(430);
                case "mode_keys":
                    // Wide, because the rows are "KEY  action" in up to
                    // three columns and a chord's whole value is being
                    // readable at a glance. Clamped to the screen.
                    return Math.min(Metrics.px(820), root.width - Metrics.px(48));
                case "cheatsheet":
                    // Wider than any other panel and clamped only by the
                    // screen. The WM sheet's rows are a key chip plus a
                    // command, some of which are full paths, and the
                    // alternative to width is eliding the half of the row
                    // that says what the key does.
                    return Math.min(Metrics.px(1100), root.width - Metrics.px(40));
                case "theme_picker":
                    // 22 tiles in a 4-column grid. Narrower than the
                    // wallpaper picker's 1100 because a theme tile is a
                    // word and three chips, not a thumbnail; at 1100 the
                    // tiles were mostly empty background. Clamped to the
                    // screen so it still fits this 1366 panel with the
                    // island's own margins.
                    return Math.min(Metrics.px(760), root.width - Metrics.px(48));
                case "expanded":
                case "bluetooth_expanded":
                    return Metrics.px(410);
                case "notification":
                    if (!notificationLoader.item) return Metrics.px(272);
                    return Math.max(
                        notificationLoader.item.minimumWidth,
                        Math.min(root.width - Metrics.px(48), notificationLoader.item.maximumWidth, notificationLoader.item.preferredWidth)
                    );
                default:
                    // FORK: the collapsed width grows to fit the resting EQ
                    // rather than clipping it. islandWidth is sized for the
                    // clock alone (96 on this panel), and the bars are
                    // additional ink, not ink that fits in the padding.
                    // It rides mainCapsule's own spring for free, because
                    // Behavior on displayedWidth already covers it — which
                    // is why the bars fade in over 180ms while the capsule
                    // takes 400: the shape arrives first and the content
                    // lands inside it.
                    return userConfig.islandWidth
                        + (islandContainer.musicPlaying ? root.restingEqAllowance : 0)
                        + root.restingWorkspaceAllowance;
                }
            }
            readonly property real targetHeight: {
                if (root.overviewVisible) return root.overviewCapsuleHeight;

                switch (islandContainer.islandState) {
                case "control_center":
                    return Metrics.px(320) + (controlCenterLoader.item ? controlCenterLoader.item.controlCenterExtraHeight : Metrics.px(32));
                case "notification_center":
                    return notificationCenterLoader.item ? notificationCenterLoader.item.contentHeight : Metrics.px(200);
                case "wallpaper_picker":
                case "application_launcher":
                    return Metrics.px(260);
                case "display_panel":
                    // Content-sized, like mode_keys and for the same reason:
                    // the flat Metrics.px(300) was drawn for a multi-monitor
                    // worst case, and on a one-output laptop it left ~45% of
                    // the panel as empty black with the key hints stranded on
                    // the far side of it. Clamped to the screen because a
                    // 30-entry mode list would otherwise size past it.
                    return displayPanelLoader.item
                        ? Math.min(displayPanelLoader.item.preferredHeight,
                                   root.screen.height - Metrics.px(60))
                        : Metrics.px(300);
                case "audio_panel":
                    // Content-sized, like the display panel. The comment this
                    // replaces argued for a tall FIXED panel because "outputs
                    // + microphones + every playing stream is routinely six or
                    // eight rows" — true of the busiest tab on a busy machine,
                    // and true of no tab most of the time. Screenshotted at
                    // Metrics.px(360) with one output: ~55% of the surface was
                    // empty black. It can still reach that height; it now has
                    // to earn it a row at a time. The argument the old comment
                    // was actually right about survives as `rowsVisible: 6`,
                    // which is where it stops growing and starts scrolling.
                    return audioPanelLoader.item
                        ? Math.min(audioPanelLoader.item.preferredHeight,
                                   root.screen.height - Metrics.px(60))
                        : Metrics.px(360);
                case "wifi_qr":
                    // Room for the symbol at the size wifi-qr.py picked
                    // (Metrics.px(300) of box) plus its white card, the SSID
                    // above and the password below.
                    return Metrics.px(430);
                // All four content-sized, for the reason the display, audio
                // and theme panels were changed to be: a flat number is a
                // number drawn for the worst case, and the worst case is not
                // what is on screen most of the time. The calendar is the
                // clearest example — February in four rows and August in six
                // differ by two whole rows of black.
                case "calendar":
                    return calendarLoader.item
                        ? Math.min(calendarLoader.item.preferredHeight,
                                   root.screen.height - Metrics.px(60))
                        : Metrics.px(290);
                case "power_menu":
                    return powerMenuLoader.item
                        ? Math.min(powerMenuLoader.item.preferredHeight,
                                   root.screen.height - Metrics.px(60))
                        : Metrics.px(300);
                case "settings":
                    return settingsLoader.item
                        ? Math.min(settingsLoader.item.preferredHeight,
                                   root.screen.height - Metrics.px(60))
                        : Metrics.px(340);
                case "picker":
                    // Content-sized like the rest, and the layer is the only
                    // thing that can compute it: it knows the row count and
                    // the 11-row cap it applies to it. Deliberately NOT
                    // sized to the FILTERED count — see the long note on
                    // PickerLayer's preferredHeight; a panel that changed
                    // height on every keystroke would walk the search field
                    // out from under the eye that is using it.
                    return pickerLoader.item
                        ? Math.min(pickerLoader.item.preferredHeight,
                                   root.screen.height - Metrics.px(60))
                        : Metrics.px(340);
                case "polkit_prompt":
                    return polkitPromptLoader.item
                        ? Math.min(polkitPromptLoader.item.preferredHeight,
                                   root.screen.height - Metrics.px(60))
                        : Metrics.px(180);
                case "mode_keys":
                    // The layer knows its own row count; nothing else does.
                    return modeKeysLoader.item
                        ? modeKeysLoader.item.preferredHeight
                        : Metrics.px(90);
                case "cheatsheet":
                    // FIXED, unlike mode_keys, and that is the difference
                    // between a panel that lists a chord and a panel that
                    // lists 192 rows: sizing to content here would mean a
                    // panel the height of the screen, and one whose height
                    // jumped on every keystroke as the filter narrowed.
                    // A fixed frame that scrolls is what a search field
                    // needs to sit still in.
                    //
                    // Clamped against root.screen.height and NOT against
                    // root.height: this window's height is DERIVED from
                    // this switch (capsuleWindowHeight -> implicitHeight),
                    // so reading root.height here would be a binding loop
                    // — the panel sizing itself from a number it is in the
                    // middle of producing. The screen is the fixed thing.
                    return Math.min(Metrics.px(460),
                                    root.screen.height - Metrics.px(60));
                case "theme_picker":
                    // Content-sized. The flat Metrics.px(290) showed 3.8 of
                    // the 6 rows a 22-theme library needs, so SIX THEMES were
                    // below the fold on every open with nothing on screen
                    // saying so. See ThemePickerLayer's preferredHeight.
                    return themePickerLoader.item
                        ? Math.min(themePickerLoader.item.preferredHeight,
                                   root.screen.height - Metrics.px(60))
                        : Metrics.px(290);
                case "expanded":
                    // Deliberately NOT the scaled 165 that bluetooth_expanded
                    // keeps. The media card's content — art, two lines of
                    // text, a scrubber and a transport row — has a floor set
                    // by glyph height, and glyph height does not scale all the
                    // way down with the shape. At the scaled 122 the transport
                    // row was cut off by the card's own bottom edge.
                    //
                    // Now content-sized, like every other panel here. The
                    // literal 190 was the LAST thing pinning the album art
                    // below spec: DESIGN-SPEC.md calls for 88 px of art, the
                    // card computes chrome + 88 as its preferredHeight, and
                    // 190 left only 67 px for it — so the art clamped itself
                    // down to fit a shape that was never asked to grow. The
                    // clamp stays in ExpandedPlayerLayer as the floor for the
                    // frame before the loader exists; this is what lets it
                    // reach its full size instead of living at the floor.
                    return expandedPlayerLoader.item
                        ? expandedPlayerLoader.item.preferredHeight
                        : Metrics.px(190);
                case "bluetooth_expanded":
                    return Metrics.px(165);
                case "notification":
                    return notificationLoader.item
                        ? Math.max(Metrics.px(56), notificationLoader.item.preferredHeight)
                        : Metrics.px(56);
                default:
                    return userConfig.islandHeight;
                }
            }
            readonly property real targetRadius: {
                if (root.overviewVisible) return root.overviewCapsuleRadius;

                switch (islandContainer.islandState) {
                case "control_center":
                    return Metrics.px(34);
                case "notification_center":
                    return mainCapsule.targetHeight * 40 / 165;
                case "wallpaper_picker":
                case "application_launcher":
                case "display_panel":
                case "audio_panel":
                case "wifi_qr":
                case "theme_picker":
                case "mode_keys":
                case "cheatsheet":
                case "calendar":
                case "power_menu":
                case "settings":
                case "picker":
                case "polkit_prompt":
                    return Metrics.px(34);
                case "expanded":
                case "bluetooth_expanded":
                    return Metrics.px(40);
                case "notification":
                    return islandContainer.notificationExpanded ? Metrics.px(28) : mainCapsule.targetHeight / 2;
                default:
                    return userConfig.islandHeight / 2;
                }
            }
            function sideSwipeWidthForProgress(progressValue) {
                if (progressValue < 0)
                    return userConfig.islandWidth + (islandContainer.customCapsuleWidth - userConfig.islandWidth)
                        * islandContainer.clamp01(-progressValue);
                if (progressValue > 0)
                    return userConfig.islandWidth + (islandContainer.lyricsCapsuleWidth - userConfig.islandWidth)
                        * islandContainer.clamp01(progressValue);
                return userConfig.islandWidth;
            }
            readonly property real sideSwipePreviewWidth: mainCapsule.sideSwipeWidthForProgress(
                islandContainer.swipeTransitionProgress
            )
            // FORK: the shell fill FOLLOWS THE THEME.
            //
            // This reverses DESIGN-SPEC.md, deliberately and on the user's
            // call — the spec says the notch must be hardcoded #000000
            // because it is imitating bezel, and "tint it and it stops being
            // a notch and becomes a colored blob". REQUIREMENTS.md item 1
            // recorded that as a conflict to decide and it is now decided the
            // other way. Both documents say so; this note is here so the spec
            // is not read alone and the decision quietly reverted.
            //
            // The spec's actual CONCERN is still answered, which is why this
            // is a blend rather than a swap: islandTheme.shellFill is the
            // palette's background slot dragged 45% toward black with 8% of
            // the accent mixed in, so the hue is identifiable beside the
            // wallpaper while the surface stays dark enough to read as bezel.
            // See qml/common/IslandTheme.qml.
            //
            // This comment said "72% toward black" long after that value was
            // changed to 0.35, and then to the present 0.45 + accent. The
            // number lives in IslandTheme.qml; repeating it here is what let
            // it go stale, so it is repeated once more only because the
            // reasoning above is meaningless without knowing it is a BLEND.
            //
            // islandBackgroundOpacity still governs the alpha, so a user who
            // wants the old translucent pill keeps that control.
            color: root.overviewContentVisible
                ? root.overviewCapsuleColor
                : (notificationHistorySurface
                    ? Qt.darker(islandTheme.shellFill, 1.6)
                    : Qt.rgba(islandTheme.shellFill.r,
                              islandTheme.shellFill.g,
                              islandTheme.shellFill.b,
                              userConfig.islandBackgroundOpacity / 100.0))

            // No `Behavior on color` here: mainCapsule already has one
            // further down, on Motion.fade(), and a second interceptor on the
            // same property is refused with
            //   WARN: Attempting to set another interceptor on
            //         QQuickRectangle property color - unsupported
            // — which is a warning, not an error, so the shell runs and one
            // of the two animations simply never happens. The existing one
            // already cross-dissolves a theme change for free.
            // FORK: the resting offset is now interpolated between the two
            // forms rather than fixed at islandTopMargin. Phase 1 of the
            // morph carries it from the floating gap to flush with the top
            // edge.
            //
            // The overshoot is deliberately NOT folded in here. Pushing this
            // rectangle to a negative y would drag ~40 anchored children up
            // with it, and growing its height to compensate would recentre
            // every one of them by half the overshoot — a 2 px drift across
            // every panel the capsule hosts, to fix a seam nobody can see.
            // The overshoot band is painted by notchSkirt instead, which is
            // a sibling and owns no content.
            readonly property real restingTopOffset:
                userConfig.islandTopMargin * (1 - root.notchUnround)

            y: restingTopOffset
                - (1 - root.autoHideProgress) * (targetHeight + userConfig.islandTopMargin + 8)
            x: parent ? parent.width * userConfig.islandPositionX / 100 - width / 2 : 0
            clip: true
            width: displayedWidth
            height: targetHeight
            radius: targetRadius
            // FORK: the un-rounding half of the morph. `radius` still drives
            // the bottom corners — the notch keeps those, it is only the top
            // pair that squares off against the screen edge. Per-corner radii
            // are Qt 6.7+; this runs on 6.11.
            topLeftRadius: targetRadius * (1 - root.notchUnround)
            topRightRadius: targetRadius * (1 - root.notchUnround)
            opacity: root.autoHideProgress
            scale: 0.96 + root.autoHideProgress * 0.04
            transformOrigin: Item.Top

            onBaseTargetWidthChanged: {
                if (!capsuleMouseArea.sideSwipeInteractive && !islandContainer.sideSwipeSettling)
                    displayedWidth = baseTargetWidth;
            }

            // FORK: geometry moves on the spring, everything colour-ish
            // moves on the critically damped fade. See Motion.js.
            //
            // Upstream ran the three geometry Behaviors on Easing.OutQuint
            // and the three colour ones on InOutQuad. OutQuint is the reason
            // the island "felt slow": it is monotone with a very long tail,
            // so it covers 97% of the distance in the first ~150ms and then
            // spends 250ms crawling the last 3%. The spring covers the
            // distance in ~105ms, overshoots 1.5%, and settles — same 400ms
            // budget, completely different perceived speed.
            Behavior on displayedWidth  {
                SequentialAnimation {
                    ScriptAction {
                        script: mainCapsule.pendingMorphPx =
                            Math.abs(mainCapsule.baseTargetWidth - mainCapsule.displayedWidth)
                    }
                    NumberAnimation {
                        duration: capsuleMouseArea.sideSwipeInteractive
                            ? 0 : mainCapsule.distanceMorphDuration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Motion.spring()
                    }
                }
            }
            Behavior on height {
                enabled: !(controlCenterLoader.item && controlCenterLoader.item.batteryDrawerMoving)

                // Height rides the width's latched distance rather than
                // latching its own. The two change together — every state
                // that widens the capsule also makes it taller — and giving
                // them independent durations is what makes a morph look
                // like two animations rather than one shape moving.
                NumberAnimation {
                    duration: mainCapsule.distanceMorphDuration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Motion.spring()
                }
            }
            Behavior on radius {
                NumberAnimation {
                    duration: mainCapsule.morphDuration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Motion.spring()
                }
            }
            // Colour cannot overshoot for the same reason opacity cannot:
            // the channels are clamped, so an undershoot below 0 or an
            // overshoot past the target colour is silently flattened and
            // shows up as a hitch rather than as bounce.
            Behavior on color {
                ColorAnimation {
                    duration: Motion.fadeDuration()
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Motion.fade()
                }
            }
            Behavior on outlineWidth {
                NumberAnimation {
                    duration: Motion.fadeDuration()
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Motion.fade()
                }
            }
            Behavior on outlineColor {
                ColorAnimation {
                    duration: Motion.fadeDuration()
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Motion.fade()
                }
            }
            border.width: outlineWidth
            border.color: outlineColor

            Rectangle {
                anchors.fill: parent
                anchors.margins: 1
                radius: Math.max(parent.radius - 1, 0)
                color: StyleTokens.transparent
                border.width: 1
                border.color: StyleTokens.overviewInnerBorder
                opacity: root.overviewContentVisible ? 1 : 0

                Behavior on opacity {
                    NumberAnimation {
                        duration: root.overviewContentVisible ? 260 : 140
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Motion.fade()   // FORK: was Easing.InOutQuad
                    }
                }
            }


            MouseArea {
                id: capsuleMouseArea
                anchors.fill: parent
                z: -1
                enabled: !root.overviewVisible && twoFingerTouchArea.touchPoints.length < 2
                acceptedButtons: root.dynamicIslandAcceptedButtons
                preventStealing: true
                hoverEnabled: root.hoverExpandEnabled || root.autoHideEnabled
                property real swipeStartX: 0
                property real swipeStartY: 0
                property real swipeStartProgress: 0
                property real swipeLastX: 0
                readonly property real sideSwipeVerticalTolerance: 24
                property bool swipeArmed: false
                property bool swipeMoved: false
                property bool sideSwipeInteractive: false
                property bool suppressNextClick: false
                property bool preparedOverviewOnPress: false

                Timer {
                    id: swipeSuppressReset
                    interval: 180
                    repeat: false
                    onTriggered: capsuleMouseArea.suppressNextClick = false
                }

                onEntered: {
                    if (root.autoHideEnabled) {
                        root.autoHidePointerInside = true;
                        root.showAutoHiddenIsland();
                    }
                    if (root.hoverExpandEnabled) {
                        hoverCollapseDelayTimer.stop();
                        hoverExpandDelayTimer.restart();
                    }
                }

                onExited: {
                    if (root.autoHideEnabled) {
                        root.autoHidePointerInside = false;
                        root.scheduleAutoHide();
                    }
                    if (root.hoverExpandEnabled)
                        hoverCollapseDelayTimer.restart();
                }

                onPressed: (mouse) => {
                    const mappedPoint = capsuleMouseArea.mapToItem(islandContainer, mouse.x, mouse.y);
                    swipeStartX = mappedPoint.x;
                    swipeStartY = mappedPoint.y;
                    islandContainer.cancelSideSwipeSettle();
                    swipeArmed = mouse.button === Qt.LeftButton
                        && islandContainer.canShowSideSwipe;
                    swipeStartProgress = islandContainer.swipeTransitionProgress;
                    swipeLastX = mappedPoint.x;
                    swipeMoved = false;
                    sideSwipeInteractive = swipeArmed;
                    islandContainer.swipeTransitionProgress = swipeStartProgress;

                    let pressedAction = "";
                    if (mouse.button === userConfig.mouseButton(userConfig.dynamicIslandPrimaryButton)) {
                        pressedAction = userConfig.dynamicIslandPrimaryAction;
                    } else if (mouse.button === userConfig.mouseButton(userConfig.dynamicIslandSecondaryButton)) {
                        pressedAction = userConfig.dynamicIslandSecondaryAction;
                    }

                    preparedOverviewOnPress = pressedAction === "openOverview"
                        || (pressedAction === "toggleOverview" && root.overviewPhase === "closed");
                    if (preparedOverviewOnPress)
                        root.prepareOverviewEverywhere();
                }

                onPositionChanged: (mouse) => {
                    if (!pressed || !swipeArmed || suppressNextClick || twoFingerTouchArea.touchPoints.length >= 2) return;

                    const mappedPoint = capsuleMouseArea.mapToItem(islandContainer, mouse.x, mouse.y);
                    const deltaX = mappedPoint.x - swipeLastX;
                    const deltaY = Math.abs(mappedPoint.y - swipeStartY);
                    const adjustedDeltaX = deltaY < sideSwipeVerticalTolerance ? deltaX : 0;
                    const nextProgress = islandContainer.advanceSideSwipeProgress(
                        islandContainer.swipeTransitionProgress,
                        adjustedDeltaX
                    );

                    swipeMoved = swipeMoved || Math.abs(nextProgress - swipeStartProgress) > 0.03 || deltaY > 6;
                    swipeLastX = mappedPoint.x;
                    islandContainer.swipeTransitionProgress = nextProgress;
                    mainCapsule.displayedWidth = mainCapsule.sideSwipePreviewWidth;
                }

                onReleased: {
                    if (swipeMoved) {
                        if (preparedOverviewOnPress)
                            root.cancelPreparedOverviewEverywhere();
                        preparedOverviewOnPress = false;
                        suppressNextClick = true;
                        swipeSuppressReset.restart();
                    }
                    let settleResult = {
                        action: "",
                        progress: islandContainer.sideSwipeRestProgressForProgress(swipeStartProgress),
                        width: islandContainer.sideSwipeRestWidthForProgress(swipeStartProgress)
                    };

                    if (swipeArmed)
                        settleResult = islandContainer.resolveSideSwipeSettle(
                            swipeStartProgress,
                            islandContainer.swipeTransitionProgress
                        );

                    sideSwipeInteractive = false;

                    if (swipeArmed)
                        islandContainer.beginSideSwipeSettle(settleResult.width);
                    else
                        mainCapsule.displayedWidth = mainCapsule.baseTargetWidth;

                    if (swipeArmed) {
                        switch (settleResult.action) {
                        case "time":
                            islandContainer.showTimeCapsule();
                            break;
                        case "custom":
                            islandContainer.showCustomCapsule();
                            break;
                        case "lyrics":
                            islandContainer.showLyricsCapsule();
                            break;
                        default:
                            islandContainer.swipeTransitionProgress = settleResult.progress;
                        }
                    } else {
                        islandContainer.swipeTransitionProgress = settleResult.progress;
                    }
                    swipeArmed = false;
                    swipeMoved = false;
                }

                onCanceled: {
                    if (preparedOverviewOnPress)
                        root.cancelPreparedOverviewEverywhere();
                    swipeArmed = false;
                    swipeMoved = false;
                    sideSwipeInteractive = false;
                    suppressNextClick = false;
                    preparedOverviewOnPress = false;
                    swipeSuppressReset.stop();
                    mainCapsule.displayedWidth = mainCapsule.baseTargetWidth;
                    islandContainer.swipeTransitionProgress = islandContainer.swipeRestProgressForState();
                }

                onClicked: (mouse) => {
                    islandContainer.hoverExpandedActive = false;
                    hoverExpandDelayTimer.stop();
                    hoverCollapseDelayTimer.stop();

                    if (suppressNextClick) {
                        swipeSuppressReset.stop();
                        suppressNextClick = false;
                        preparedOverviewOnPress = false;
                        return;
                    }

                    if (mouse.button === userConfig.mouseButton(userConfig.dynamicIslandPrimaryButton)) {
                        if (islandContainer.toggleNotificationExpansionIfNeeded()) {
                            if (preparedOverviewOnPress)
                                root.cancelPreparedOverviewEverywhere();
                            preparedOverviewOnPress = false;
                            return;
                        }

                        preparedOverviewOnPress = false;
                        islandContainer.handleConfiguredClickAction(userConfig.dynamicIslandPrimaryAction);
                        return;
                    }

                    if (mouse.button === userConfig.mouseButton(userConfig.dynamicIslandSecondaryButton)) {
                        preparedOverviewOnPress = false;
                        islandContainer.handleConfiguredClickAction(userConfig.dynamicIslandSecondaryAction);
                    }
                }
            }

            MultiPointTouchArea {
                id: twoFingerTouchArea
                anchors.fill: parent
                z: 0
                enabled: !root.overviewVisible
                mouseEnabled: false
                minimumTouchPoints: 2
                maximumTouchPoints: 2

                property real swipeStartX: 0
                property real swipeStartProgress: 0
                property bool swipeMoved: false

                onPressed: (touchPoints) => {
                    const centerPoint = islandContainer.mapFromItem(twoFingerTouchArea, 
                        (touchPoints[0].x + touchPoints[1].x) / 2,
                        (touchPoints[0].y + touchPoints[1].y) / 2);
                    swipeStartX = centerPoint.x;
                    swipeStartProgress = islandContainer.swipeTransitionProgress;
                    swipeMoved = false;
                    islandContainer.cancelSideSwipeSettle();
                }

                onUpdated: (touchPoints) => {
                    const centerPoint = islandContainer.mapFromItem(twoFingerTouchArea, 
                        (touchPoints[0].x + touchPoints[1].x) / 2,
                        (touchPoints[0].y + touchPoints[1].y) / 2);
                    
                    const deltaX = centerPoint.x - swipeStartX;
                    const nextProgress = islandContainer.advanceSideSwipeProgress(
                        swipeStartProgress,
                        deltaX
                    );

                    if (Math.abs(nextProgress - swipeStartProgress) > 0.03) {
                        swipeMoved = true;
                    }

                    islandContainer.swipeTransitionProgress = nextProgress;
                    mainCapsule.displayedWidth = mainCapsule.sideSwipePreviewWidth;
                }

                onReleased: {
                    if (swipeMoved) {
                        const settleResult = islandContainer.resolveSideSwipeSettle(
                            swipeStartProgress,
                            islandContainer.swipeTransitionProgress
                        );

                        islandContainer.beginSideSwipeSettle(settleResult.width);

                        switch (settleResult.action) {
                        case "time":
                            islandContainer.showTimeCapsule();
                            break;
                        case "custom":
                            islandContainer.showCustomCapsule();
                            break;
                        case "lyrics":
                            islandContainer.showLyricsCapsule();
                            break;
                        default:
                            islandContainer.swipeTransitionProgress = settleResult.progress;
                        }
                    } else {
                        islandContainer.swipeTransitionProgress = islandContainer.sideSwipeRestProgressForProgress(swipeStartProgress);
                    }
                    swipeMoved = false;
                }
            }



            Loader {
                id: customSwipeLoader
                anchors.fill: parent
                active: islandContainer.customSwipeVisible
                asynchronous: false
                visible: active

                onLoaded: islandContainer.syncCustomCapsuleWidth()

                sourceComponent: Component {
                    SwipeCustomInfoLayer {
                        items: islandContainer.customLeftItems
                        cavaLevels: islandContainer.cavaLevels
                        timeText: timeObj.currentTime
                        iconFontFamily: root.iconFontFamily
                        textFontFamily: root.heroFontFamily
                        timeFontFamily: root.heroFontFamily
                        textPixelSize: root.bodyFontSize
                        iconPixelSize: root.iconFontSize
                        minimumWidth: 220
                        maximumWidth: Math.max(220, root.width - 48)
                        transitionProgress: islandContainer.swipeTransitionProgress
                        recordingActive: islandContainer.screenRecordingActive
                        showSecondaryText: islandContainer.workspaceOriginSide !== "left"
                            && islandContainer.splitOriginSide !== "left"
                        showCondition: true
                        onPreferredWidthChanged: islandContainer.syncCustomCapsuleWidth()
                    }
                }
            }

            Loader {
                id: lyricsSwipeLoader
                anchors.fill: parent
                active: islandContainer.lyricsSwipeVisible
                asynchronous: false
                visible: active

                onLoaded: islandContainer.syncLyricsCapsuleWidth()

                sourceComponent: Component {
                    SwipeLyricsLayer {
                        lyricText: islandContainer.lyricsDisplayText
                        currentArtUrl: islandContainer.currentArtUrl
                        cavaLevels: islandContainer.cavaLevels
                        timeText: timeObj.currentTime
                        textFontFamily: root.textFontFamily
                        timeFontFamily: root.timeFontFamily
                        textPixelSize: root.bodyFontSize
                        minimumWidth: 220
                        maximumWidth: Math.max(220, root.width - 48)
                        transitionProgress: islandContainer.rightSwipeProgress
                        recordingActive: islandContainer.screenRecordingActive
                        musicPlaying: islandContainer.musicPlaying
                        showSecondaryText: islandContainer.workspaceOriginSide !== "right"
                            && islandContainer.splitOriginSide !== "right"
                        showCondition: true
                        onPreferredWidthChanged: islandContainer.syncLyricsCapsuleWidth()
                    }
                }
            }

            Loader {
                id: splitIconLoader
                anchors.fill: parent
                active: !root.overviewVisible && islandContainer.splitShowsIconOnly
                asynchronous: false
                visible: active

                sourceComponent: Component {
                    SplitIconLayer {
                        iconText: islandContainer.splitIcon
                        iconFontFamily: root.iconFontFamily
                        transitionProgress: islandContainer.swipeTransitionProgress
                        slideDirection: islandContainer.splitOriginSide
                        showCondition: true
                    }
                }
            }

            Loader {
                id: osdLayerLoader
                anchors.fill: parent
                active: !root.overviewVisible && islandContainer.splitUsesExtendedLayout
                asynchronous: false
                visible: active

                sourceComponent: Component {
                    OsdLayer {
                        iconText: islandContainer.splitIcon
                        progress: islandContainer.osdProgress
                        customText: islandContainer.osdCustomText
                        iconFontFamily: root.iconFontFamily
                        textFontFamily: root.textFontFamily
                        heroFontFamily: root.heroFontFamily
                        transitionProgress: islandContainer.swipeTransitionProgress
                        slideDirection: islandContainer.splitOriginSide
                        showCondition: true
                    }
                }
            }

            Loader {
                id: workspaceLayerLoader
                anchors.fill: parent
                active: !root.overviewVisible
                    && islandContainer.islandState === "long_capsule"
                    && (islandContainer.workspaceOriginSide !== "none"
                        || Math.abs(islandContainer.swipeTransitionProgress) < 0.001)
                asynchronous: false
                visible: active

                sourceComponent: Component {
                    WorkspaceLayer {
                        workspaceId: islandContainer.currentWs
                        displayText: "Workspace " + islandContainer.currentWs
                        textFontFamily: root.textFontFamily
                        textPixelSize: root.bodyFontSize
                        animateVisibility: islandContainer.restingState === "normal"
                        transitionProgress: islandContainer.swipeTransitionProgress
                        showCondition: true
                        slideDirection: islandContainer.workspaceOriginSide
                    }
                }
            }

            PanelLoader {
                id: expandedPlayerLoader
                anchors.fill: parent
                live: islandContainer.expandedLayerVisible
                onLoaded: {
                    if (islandContainer.openTimerPageWhenExpanded
                            && item && item.openTimerPage) {
                        item.openTimerPage();
                        islandContainer.openTimerPageWhenExpanded = false;
                    }
                }

                sourceComponent: Component {
                    ExpandedPlayerLayer {
                        currentArtUrl: islandContainer.currentArtUrl
                        currentTrack: islandContainer.currentTrack
                        currentArtist: islandContainer.currentArtist
                        timePlayed: islandContainer.timePlayed
                        timeTotal: islandContainer.timeTotal
                        trackProgress: islandContainer.trackProgress
                        activePlayer: islandContainer.activePlayer
                        iconFontFamily: root.iconFontFamily
                        textFontFamily: root.textFontFamily
                        timerSelectedHours: islandContainer.timerSelectedHours
                        timerSelectedMinutes: islandContainer.timerSelectedMinutes
                        timerTotalSeconds: islandContainer.timerTotalSeconds
                        timerRemainingSeconds: islandContainer.timerRemainingSeconds
                        timerRunning: islandContainer.timerRunning
                        timerActive: islandContainer.timerActive
                        showCondition: islandContainer.expandedLayerVisible
                        onControlPressed: islandContainer.suppressCapsuleClick()
                        onBackgroundClicked: islandContainer.smartRestoreState()
                        onKeyboardFocusRequested: islandContainer.requestExpandedPlayerKeyboardFocus()
                        onKeyboardFocusReleased: islandContainer.releaseExpandedPlayerKeyboardFocus()
                        onPreviousRequested: mediaController.previous()
                        onTimerToggleRequested: function(hours, minutes) {
                            islandContainer.toggleTimer(hours, minutes);
                        }
                        onTimerResetRequested: islandContainer.resetTimer()
                        onTimerDurationRequested: function(hours, minutes) {
                            if (!islandContainer.timerActive)
                                islandContainer.syncTimerDuration(hours, minutes);
                        }
                    }
                }
            }

            PanelLoader {
                id: bluetoothExpandedLoader
                anchors.fill: parent
                live: islandContainer.bluetoothExpandedLayerVisible

                sourceComponent: Component {
                    BluetoothExpandedLayer {
                        device: islandContainer.bluetoothExpandedDevice
                        volumeLevel: islandContainer.currentVolume
                        iconText: ""
                        iconFontFamily: root.iconFontFamily
                        textFontFamily: root.textFontFamily
                        showCondition: islandContainer.bluetoothExpandedLayerVisible
                    }
                }
            }

            PanelLoader {
                id: notificationLoader
                anchors.fill: parent
                live: islandContainer.notificationLayerVisible

                sourceComponent: Component {
                    NotificationLayer {
                        appName: islandContainer.notificationAppName
                        summary: islandContainer.notificationSummary
                        body: islandContainer.notificationBody
                        expanded: islandContainer.notificationExpanded
                        toggleButton: userConfig.mouseButton(userConfig.dynamicIslandPrimaryButton)
                        iconText: root.notificationStatusIcon
                        iconFontFamily: root.iconFontFamily
                        textFontFamily: root.textFontFamily
                        heroFontFamily: root.heroFontFamily
                        showCondition: true
                        onExpansionToggleRequested: {
                            islandContainer.suppressCapsuleClick(true);
                            islandContainer.toggleNotificationExpansionIfNeeded();
                        }
                    }
                }
            }

            PanelLoader {
                id: controlCenterLoader
                anchors.fill: parent
                live: islandContainer.controlCenterLayerVisible || root.anyConnectivityDetailMounted

                sourceComponent: Component {
                    ControlCenterLayer {
                        iconFontFamily: root.iconFontFamily
                        textFontFamily: root.textFontFamily
                        heroFontFamily: root.heroFontFamily
                        // FORK: the filament faders' fill colour. See
                        // ControlSliderCard.qml — the accent is ours rather
                        // than ukishima's fixed vermillion because this
                        // shell follows theme-apply.
                        accentColor: islandTheme.accent
                        sliderIntroDelay: mainCapsule.morphDuration
                        currentTime: timeObj.currentTime
                        currentDateLabel: timeObj.currentDateLabel
                        batteryCapacity: islandContainer.batteryCapacity
                        isCharging: islandContainer.isCharging
                        volumeLevel: islandContainer.currentVolume
                        brightnessLevel: islandContainer.currentBrightness
                        currentWorkspace: islandContainer.currentWs
                        currentTrack: islandContainer.currentTrack
                        currentArtist: islandContainer.currentArtist
                        nightLightEnabled: root.shellRootController && root.shellRootController.nightLightEnabled !== undefined
                            ? root.shellRootController.nightLightEnabled
                            : false
                        showCondition: islandContainer.controlCenterLayerVisible
                        onFocusModeChanged: function(enabled) {
                            if (root.shellRootController && root.shellRootController.focusEnabled !== undefined)
                                root.shellRootController.focusEnabled = enabled;
                        }
                        onNightLightModeChanged: function(enabled) {
                            if (root.shellRootController && root.shellRootController.nightLightEnabled !== undefined)
                                root.shellRootController.nightLightEnabled = enabled;
                        }
                        onRequestNotification: function(appName, summary, body) {
                            islandContainer.showNotificationCapsule(appName, summary, body);
                        }
                        onConnectivityPanelRequested: function(kind, open) {
                            root.setConnectivityDetailVisible(kind, open);
                        }
                    }
                }
            }

            PanelLoader {
                id: notificationCenterLoader
                anchors.fill: parent
                live: islandContainer.notificationCenterLayerVisible

                sourceComponent: Component {
                    NotificationCenterLayer {
                        notificationModel: islandContainer.notificationHistoryModel
                        iconFontFamily: root.iconFontFamily
                        textFontFamily: root.textFontFamily
                        heroFontFamily: root.heroFontFamily

                        onClearAllRequested: {
                            islandContainer.notificationHistoryModel.clear();
                        }
                    }
                }
            }

            PanelLoader {
                id: wallpaperPickerLoader
                anchors.fill: parent
                live: islandContainer.wallpaperPickerLayerVisible
                onLoaded: root.focusWallpaperPicker()

                sourceComponent: Component {
                    WallpaperPickerLayer {
                        iconFontFamily: root.iconFontFamily
                        textFontFamily: root.textFontFamily
                        activeWallpaper: root.wallpaperPickerActiveWallpaper
                        showCondition: islandContainer.wallpaperPickerLayerVisible
                        onWallpaperApplied: filePath => root.wallpaperPickerActiveWallpaper = filePath
                        onWallpaperApplySucceeded: filePath => root.handleWallpaperApplySucceeded(filePath)
                        onCloseRequested: islandContainer.smartRestoreState()
                    }
                }
            }

            // FORK: the display panel. Ordered before the theme picker only
            // for readability; Loaders are mutually exclusive by island state.
            PanelLoader {
                id: displayPanelLoader
                anchors.fill: parent
                live: islandContainer.displayPanelLayerVisible

                sourceComponent: Component {
                    DisplayPanel {
                        textFontFamily: root.textFontFamily
                        heroFontFamily: root.heroFontFamily
                        showCondition: islandContainer.displayPanelLayerVisible
                        onCloseRequested: islandContainer.smartRestoreState()
                    }
                }
            }

            // FORK: the audio panel — qtile's AudioPopup.
            PanelLoader {
                id: audioPanelLoader
                anchors.fill: parent
                live: islandContainer.audioPanelLayerVisible

                sourceComponent: Component {
                    AudioPanel {
                        textFontFamily: root.textFontFamily
                        heroFontFamily: root.heroFontFamily
                        showCondition: islandContainer.audioPanelLayerVisible
                        onCloseRequested: islandContainer.smartRestoreState()
                    }
                }
            }

            // FORK: the Wi-Fi QR — qtile's WifiQR.
            PanelLoader {
                id: wifiQrLoader
                anchors.fill: parent
                live: islandContainer.wifiQrLayerVisible

                sourceComponent: Component {
                    WifiQrLayer {
                        textFontFamily: root.textFontFamily
                        heroFontFamily: root.heroFontFamily
                        showCondition: islandContainer.wifiQrLayerVisible
                        onCloseRequested: islandContainer.smartRestoreState()
                    }
                }
            }

            // FORK: the calendar — DESIGN-SPEC.md's state list, no ancestor.
            PanelLoader {
                id: calendarLoader
                anchors.fill: parent
                live: islandContainer.calendarLayerVisible

                sourceComponent: Component {
                    CalendarLayer {
                        textFontFamily: root.textFontFamily
                        heroFontFamily: root.heroFontFamily
                        showCondition: islandContainer.calendarLayerVisible
                        onCloseRequested: islandContainer.smartRestoreState()
                    }
                }
            }

            // FORK: the power menu — qtile's `dm-logout -r`, which was rofi.
            PanelLoader {
                id: powerMenuLoader
                anchors.fill: parent
                live: islandContainer.powerMenuLayerVisible

                sourceComponent: Component {
                    PowerMenuLayer {
                        textFontFamily: root.textFontFamily
                        heroFontFamily: root.heroFontFamily
                        showCondition: islandContainer.powerMenuLayerVisible
                        onCloseRequested: islandContainer.smartRestoreState()
                    }
                }
            }

            // FORK: settings, as a state of the island rather than a patch to
            // the packaged config app — which is a compiled binary from the
            // `tide-island` package and would be overwritten by the next
            // upgrade. See qml/island/SettingsLayer.qml.
            PanelLoader {
                id: settingsLoader
                anchors.fill: parent
                live: islandContainer.settingsLayerVisible

                sourceComponent: Component {
                    SettingsLayer {
                        textFontFamily: root.textFontFamily
                        heroFontFamily: root.heroFontFamily
                        showCondition: islandContainer.settingsLayerVisible
                        onCloseRequested: islandContainer.smartRestoreState()
                    }
                }
            }

            // FORK: the generic list picker — the shape three of the rofi
            // chord's menus share, as one panel. See qml/island/PickerLayer.qml.
            PanelLoader {
                id: pickerLoader
                anchors.fill: parent
                live: islandContainer.pickerLayerVisible
                // Same as the application launcher and the cheatsheet: the
                // search field is useless without the focus, and the focus
                // has to be taken AFTER the item exists — which is what this
                // signal is for and why the layer's own onShowConditionChanged
                // is not enough on the first open (showCondition is already
                // true by the time the item is constructed, so the handler
                // that would have grabbed the focus never runs).
                onLoaded: {
                    if (pickerLoader.item && pickerLoader.item.grabKeyboardFocus)
                        pickerLoader.item.grabKeyboardFocus();
                }

                sourceComponent: Component {
                    PickerLayer {
                        textFontFamily: root.textFontFamily
                        heroFontFamily: root.heroFontFamily
                        iconFontFamily: root.iconFontFamily
                        showCondition: islandContainer.pickerLayerVisible
                        menu: islandContainer.pickerMenu
                        onCloseRequested: islandContainer.smartRestoreState()
                    }
                }
            }

            PanelLoader {
                id: cheatsheetLoader
                anchors.fill: parent
                live: islandContainer.cheatsheetLayerVisible
                // Same as the application launcher: the search field is
                // useless without the focus, and the focus has to be taken
                // after the item exists.
                onLoaded: {
                    if (cheatsheetLoader.item && cheatsheetLoader.item.grabKeyboardFocus)
                        cheatsheetLoader.item.grabKeyboardFocus();
                }

                sourceComponent: Component {
                    CheatsheetLayer {
                        textFontFamily: root.textFontFamily
                        heroFontFamily: root.heroFontFamily
                        iconFontFamily: root.iconFontFamily
                        showCondition: islandContainer.cheatsheetLayerVisible
                        sheet: islandContainer.cheatsheetWhich
                        onCloseRequested: islandContainer.smartRestoreState()
                    }
                }
            }

            PanelLoader {
                id: modeKeysLoader
                anchors.fill: parent
                live: islandContainer.modeKeysLayerVisible

                sourceComponent: Component {
                    ModeKeysLayer {
                        textFontFamily: root.textFontFamily
                        heroFontFamily: root.heroFontFamily
                        showCondition: islandContainer.modeKeysLayerVisible
                        modeName: islandContainer.modeKeysName
                        // See ModeKeysLayer's `pendingHeight`: this is what
                        // turns the chord HUD's open from two height
                        // animations into one.
                        pendingHeight: islandContainer.modeKeysHeightFor(islandContainer.modeKeysName)
                        onMeasured: function (mode, height) {
                            islandContainer.rememberModeKeysHeight(mode, height);
                        }
                    }
                }
            }

            PanelLoader {
                id: themePickerLoader
                anchors.fill: parent
                live: islandContainer.themePickerLayerVisible

                sourceComponent: Component {
                    ThemePickerLayer {
                        textFontFamily: root.textFontFamily
                        heroFontFamily: root.heroFontFamily
                        showCondition: islandContainer.themePickerLayerVisible
                        // Guarded on the function existing rather than on the
                        // controller existing: an older shell.qml (or a
                        // /usr/share/tide-island left over after an upgrade
                        // wiped the fork) still has shellRootController, and
                        // calling a method it does not have would take the
                        // picker down with a TypeError on click.
                        useTransition: root.shellRootController
                            && typeof root.shellRootController.startThemeTransition === "function"
                        onThemeRequested: function(name) {
                            root.shellRootController.startThemeTransition(name);
                        }
                        onCloseRequested: islandContainer.smartRestoreState()
                    }
                }
            }

            PanelLoader {
                id: applicationLauncherLoader
                anchors.fill: parent
                live: islandContainer.applicationLauncherLayerVisible
                onLoaded: root.focusApplicationLauncher()

                sourceComponent: Component {
                    ApplicationLauncherLayer {
                        iconFontFamily: root.iconFontFamily
                        textFontFamily: root.textFontFamily
                        showCondition: islandContainer.applicationLauncherLayerVisible
                        onCloseRequested: islandContainer.smartRestoreState()
                    }
                }
            }

            Loader {
                id: overviewLoader

                anchors.fill: parent
                active: root.overviewLoaderActive
                asynchronous: false
                visible: root.overviewContentVisible

                onStatusChanged: {
                    if (status === Loader.Ready && root.overviewPreparing) {
                        root.beginOverviewOpening();
                    }
                }

                sourceComponent: Component {
                    WorkspaceOverviewScene {
                        screen: root.screen
                        showCondition: root.overviewVisible
                        previewsEnabled: root.overviewContentVisible
                        textFontFamily: root.textFontFamily
                        heroFontFamily: root.heroFontFamily
                        wallpaperPath: root.overviewWallpaperSource
                        windowCornerRadius: root.overviewWindowCornerRadius
                        onCloseRequested: root.closeOverviewEverywhere()
                    }
                }
            }

        }

        Item {
            id: timerBubble

            property bool mounted: islandContainer.timerBubbleWanted
            property real reveal: islandContainer.timerBubbleWanted ? 1 : 0
            readonly property int bubbleSize: 34
            readonly property real hiddenX: mainCapsule.x + mainCapsule.width - width * 0.62
            readonly property real shownX: mainCapsule.x + mainCapsule.width + 8
            readonly property real centerY: mainCapsule.y + mainCapsule.height / 2 - height / 2

            width: bubbleSize
            height: bubbleSize
            x: hiddenX + (shownX - hiddenX) * reveal
            y: centerY + (1 - reveal) * 10
            z: 6
            visible: mounted
            opacity: reveal * root.autoHideProgress
            scale: (0.55 + reveal * 0.45) * (0.96 + root.autoHideProgress * 0.04) * (1 + islandContainer.timerCompletionPulse * 0.12)
            transformOrigin: Item.Center

            Connections {
                target: islandContainer

                function onTimerBubbleWantedChanged() {
                    timerBubbleShowAnimation.stop();
                    timerBubbleHideAnimation.stop();

                    if (islandContainer.timerBubbleWanted) {
                        timerBubble.mounted = true;
                        timerBubbleShowAnimation.restart();
                    } else {
                        timerBubbleHideAnimation.restart();
                    }
                }

                function onTimerProgressChanged() {
                    timerBubbleRing.requestPaint();
                }

                function onTimerRemainingSecondsChanged() {
                    timerBubbleRing.requestPaint();
                }

                function onTimerTotalSecondsChanged() {
                    timerBubbleRing.requestPaint();
                }

                function onTimerCompletionAnimatingChanged() {
                    timerBubbleRing.requestPaint();
                }

                function onTimerCompletionFlashChanged() {
                    timerBubbleRing.requestPaint();
                }
            }

            NumberAnimation {
                id: timerBubbleShowAnimation

                target: timerBubble
                property: "reveal"
                from: timerBubble.reveal
                to: 1
                duration: 360
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Motion.spring()   // FORK: was Easing.OutCubic
            }

            NumberAnimation {
                id: timerBubbleHideAnimation

                target: timerBubble
                property: "reveal"
                from: timerBubble.reveal
                to: 0
                duration: 280
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Motion.fade()   // FORK: was Easing.InCubic — a
                // withdrawal, so it must not overshoot past zero and bounce back
                // into view on its way out.
                onStopped: {
                    if (!islandContainer.timerBubbleWanted && timerBubble.reveal <= 0.001)
                        timerBubble.mounted = false;
                }
            }

            SequentialAnimation {
                id: timerBubbleCompletionAnimation

                running: islandContainer.timerCompletionAnimating

                onStarted: {
                    timerBubbleShowAnimation.stop();
                    timerBubbleHideAnimation.stop();
                    timerBubble.mounted = true;
                    timerBubble.reveal = 1;
                }

                onStopped: {
                    if (islandContainer.timerCompletionAnimating)
                        islandContainer.timerCompletionAnimating = false;
                    islandContainer.timerCompletionPulse = 0;
                    islandContainer.timerCompletionFlash = 0;
                    timerBubbleRing.requestPaint();
                }

                ParallelAnimation {
                    NumberAnimation {
                        target: islandContainer
                        property: "timerCompletionPulse"
                        from: 0
                        to: 1
                        duration: 140
                        easing.type: Easing.OutCubic
                    }

                    NumberAnimation {
                        target: islandContainer
                        property: "timerCompletionFlash"
                        from: 0
                        to: 1
                        duration: 140
                        easing.type: Easing.OutCubic
                    }
                }

                ParallelAnimation {
                    NumberAnimation {
                        target: islandContainer
                        property: "timerCompletionPulse"
                        from: 1
                        to: 0
                        duration: 380
                        easing.type: Easing.OutCubic
                    }

                    NumberAnimation {
                        target: islandContainer
                        property: "timerCompletionFlash"
                        from: 1
                        to: 0
                        duration: 380
                        easing.type: Easing.InOutQuad
                    }
                }

                PauseAnimation {
                    duration: 380
                }
            }

            Rectangle {
                anchors.fill: parent
                anchors.margins: 2
                radius: width / 2
                color: StyleTokens.black
            }

            Canvas {
                id: timerBubbleRing

                anchors.fill: parent
                anchors.margins: 1

                Component.onCompleted: requestPaint()
                onVisibleChanged: requestPaint()
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()

                onPaint: {
                    const ctx = getContext("2d");
                    const centerX = width / 2;
                    const centerY = height / 2;
                    const completionActive = islandContainer.timerCompletionAnimating;
                    const flash = Math.max(0, Math.min(1, islandContainer.timerCompletionFlash));
                    const lineWidth = completionActive ? 3 + flash : 3;
                    const radius = Math.min(width, height) / 2 - lineWidth / 2;
                    const progress = Math.max(0, Math.min(1, islandContainer.timerProgress));
                    const startAngle = -Math.PI / 2;
                    const endAngle = startAngle - Math.PI * 2 * progress;

                    ctx.clearRect(0, 0, width, height);
                    ctx.lineCap = "round";
                    ctx.lineWidth = lineWidth;

                    ctx.beginPath();
                    ctx.strokeStyle = "#303036";
                    ctx.arc(centerX, centerY, radius, 0, Math.PI * 2);
                    ctx.stroke();

                    if (completionActive) {
                        if (flash > 0) {
                            ctx.beginPath();
                            ctx.lineWidth = lineWidth + 1.5;
                            ctx.strokeStyle = "rgba(255, 204, 0, " + (0.18 * flash) + ")";
                            ctx.arc(centerX, centerY, radius, 0, Math.PI * 2);
                            ctx.stroke();
                        }

                        ctx.beginPath();
                        ctx.lineWidth = lineWidth;
                        ctx.strokeStyle = "rgba(255, 204, 0, " + (0.72 + 0.28 * flash) + ")";
                        ctx.arc(centerX, centerY, radius, 0, Math.PI * 2);
                        ctx.stroke();
                    } else if (progress > 0) {
                        ctx.beginPath();
                        ctx.strokeStyle = "#ffcc00";
                        ctx.arc(centerX, centerY, radius, startAngle, endAngle, true);
                        ctx.stroke();
                    }
                }
            }

            Text {
                anchors.centerIn: parent
                anchors.horizontalCenterOffset: -1
                text: "󰔛"
                color: "white"
                font.pixelSize: root.iconFontSize - 1
                font.family: root.iconFontFamily
                font.weight: Font.DemiBold
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }

            MouseArea {
                anchors.fill: parent
                enabled: timerBubble.mounted && root.autoHideProgress > 0.5
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: {
                    if (root.autoHideEnabled) {
                        root.autoHidePointerInside = true;
                        root.showAutoHiddenIsland();
                    }
                }
                onExited: {
                    if (root.autoHideEnabled) {
                        root.autoHidePointerInside = false;
                        root.scheduleAutoHide();
                    }
                }
                onClicked: islandContainer.showExpandedTimerPage()
            }
        }

        ConnectivityDetailShell {
            id: wifiConnectivityDetailShell

            open: root.wifiConnectivityDetailOpen
            mounted: root.wifiConnectivityDetailMounted
            rightSide: false
            panelKind: "wifi"
            // Escape / q inside the panel. Routed through the same
            // setter the toggle uses, so the close animation and the
            // unmount timer behave identically however it was closed.
            onCloseRequested: root.setConnectivityDetailVisible("wifi", false)
            provider: controlCenterLoader.item
            mainCapsule: mainCapsule
            availableWidth: root.width
            detailWidth: root.connectivityDetailWidth
            detailHeight: root.connectivityDetailHeight
            detailGap: root.connectivityDetailGap
            iconFontFamily: root.iconFontFamily
            textFontFamily: root.textFontFamily
            heroFontFamily: root.heroFontFamily
            panelFill: islandTheme.shellFill
        }

        ConnectivityDetailShell {
            id: bluetoothConnectivityDetailShell

            open: root.bluetoothConnectivityDetailOpen
            mounted: root.bluetoothConnectivityDetailMounted
            rightSide: true
            panelKind: "bluetooth"
            // Escape / q inside the panel. Routed through the same
            // setter the toggle uses, so the close animation and the
            // unmount timer behave identically however it was closed.
            onCloseRequested: root.setConnectivityDetailVisible("bluetooth", false)
            provider: controlCenterLoader.item
            mainCapsule: mainCapsule
            availableWidth: root.width
            detailWidth: root.connectivityDetailWidth
            detailHeight: root.connectivityDetailHeight
            detailGap: root.connectivityDetailGap
            iconFontFamily: root.iconFontFamily
            textFontFamily: root.textFontFamily
            heroFontFamily: root.heroFontFamily
            panelFill: islandTheme.shellFill
        }
    }

    MouseArea {
        id: autoHideRevealArea

        x: root.autoHideRevealX
        y: 0
        z: 20
        width: root.autoHideRevealWidth
        height: root.autoHideRevealHeight
        enabled: root.autoHideEnabled
        hoverEnabled: true
        acceptedButtons: Qt.NoButton

        onEntered: {
            root.autoHidePointerInside = true;
            root.showAutoHiddenIsland("edge");
        }

        onExited: {
            root.autoHidePointerInside = false;
            root.scheduleAutoHide();
        }
    }

    IslandRootGestureArea {
        anchors.fill: parent
        enabled: root.topGestureInputActive
        islandController: islandContainer
        capsule: mainCapsule
    }
}

