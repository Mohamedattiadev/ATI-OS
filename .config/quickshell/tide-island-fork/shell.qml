import QtQuick
import Quickshell
import Quickshell.Io
import IslandBackend

// FORK: the circular theme-change reveal — REQUIREMENTS.md item 5.
import "qml/theme"

Scope {
    id: shellRoot

    readonly property bool screenRecordingActive: SystemServices.screenRecordingActive
    property bool focusEnabled: false
    property bool nightLightEnabled: false
    property bool shuttingDown: false
    property bool islandAutoHideRuntimeEnabled: true

    readonly property var userConfig: UserConfig

    function forEachWindow(callback) {
        const windows = panelVariants.instances ? panelVariants.instances : [];
        for (let index = 0; index < windows.length; index++) {
            const window = windows[index];
            if (window)
                callback(window);
        }
    }

    function showNotificationAll(appName, summary, body) {
        if (focusEnabled)
            return;

        shellRoot.forEachWindow((window) => {
            if (window && window.showNotification)
                window.showNotification(appName, summary, body);
        });
    }

    function anyOverviewOpen() {
        if (CompositorBackend.compositor === "niri")
            return false;

        const windows = panelVariants.instances ? panelVariants.instances : [];
        for (let index = 0; index < windows.length; index++) {
            const window = windows[index];
            if (window && window.overviewPhase !== "closed")
                return true;
        }

        return false;
    }

    function prepareOverviewAll() {
        if (CompositorBackend.compositor === "niri")
            return;

        shellRoot.forEachWindow((window) => window.prepareOverview());
    }

    function cancelPreparedOverviewAll() {
        if (CompositorBackend.compositor === "niri")
            return;

        shellRoot.forEachWindow((window) => window.cancelPreparedOverview());
    }

    function openOverviewAll() {
        if (CompositorBackend.compositor === "niri")
            return;

        shellRoot.forEachWindow((window) => window.openOverview());
    }

    function closeOverviewAll() {
        if (CompositorBackend.compositor === "niri")
            return;

        shellRoot.forEachWindow((window) => window.closeOverview());
    }

    function toggleOverviewAll() {
        if (CompositorBackend.compositor === "niri")
            return;

        if (shellRoot.anyOverviewOpen())
            shellRoot.closeOverviewAll();
        else
            shellRoot.openOverviewAll();
    }

    function anyIslandShown() {
        const windows = panelVariants.instances ? panelVariants.instances : [];
        for (let index = 0; index < windows.length; index++) {
            const window = windows[index];
            if (window && window.autoHideTargetVisible)
                return true;
        }

        return false;
    }

    function showIslandAll() {
        shellRoot.forEachWindow((window) => {
            if (window && window.showIslandWindow)
                window.showIslandWindow();
        });
    }

    function hideIslandAll() {
        shellRoot.forEachWindow((window) => {
            if (window && window.hideIslandWindow)
                window.hideIslandWindow();
        });
    }

    function toggleIslandAll() {
        if (shellRoot.anyIslandShown())
            shellRoot.hideIslandAll();
        else
            shellRoot.showIslandAll();
    }

    function refreshIslandAutoHideAll() {
        shellRoot.forEachWindow((window) => {
            if (window && window.refreshAutoHideWindow)
                window.refreshAutoHideWindow();
        });
    }

    function refreshOverviewWallpaperCaches(wallpaperPath) {
        shellRoot.forEachWindow((window) => {
            if (window
                    && wallpaperPath !== undefined
                    && wallpaperPath !== null
                    && String(wallpaperPath) !== "") {
                window.wallpaperPickerActiveWallpaper = String(wallpaperPath);
            }
            if (window && window.prewarmWallpaperCache)
                window.prewarmWallpaperCache();
        });
    }

    function forFocusedWindow(callback) {
        const windows = panelVariants.instances ? panelVariants.instances : [];
        let fallbackWindow = null;
        for (let index = 0; index < windows.length; index++) {
            const window = windows[index];
            if (window && !fallbackWindow)
                fallbackWindow = window;
            if (window && window.monitorFocused) {
                callback(window);
                return;
            }
        }

        if (fallbackWindow)
            callback(fallbackWindow);
    }

    // FORK: REQUIREMENTS.md item 5, the circular theme-change animation.
    //
    // It lives in shellRoot rather than inside the theme picker because the
    // picker is a Loader that UNLOADS when the island leaves the picker
    // state — and the very first thing a theme change does is close the
    // picker. An animation owned by the thing that triggers it would be
    // destroyed on frame one.
    function startThemeTransition(themeName) {
        if (!themeName)
            return;
        const windows = themeTransitionVariants.instances
            ? themeTransitionVariants.instances : [];
        if (windows.length === 0)
            return;
        for (let index = 0; index < windows.length; index++) {
            if (windows[index])
                windows[index].begin(String(themeName));
        }
    }

    Variants {
        id: themeTransitionVariants

        model: Quickshell.screens

        ThemeTransitionWindow {
            required property var modelData

            screen: modelData
            outputName: modelData && modelData.name !== undefined
                ? String(modelData.name) : ""
            themeApplyPath: Quickshell.env("HOME")
                + "/.dotfiles/.config/AtiScriptsV1/theme-apply"
            // Only the first screen's overlay runs theme-apply; see the note
            // in ThemeTransitionWindow.qml. Compared by identity against the
            // screen list rather than by an index property, because Variants
            // gives no index.
            ownsThemeApply: Quickshell.screens.length === 0
                || modelData === Quickshell.screens[0]
        }
    }

    IpcHandler {
        target: "overview"

        function toggle() {
            shellRoot.toggleOverviewAll();
        }

        function open() {
            shellRoot.openOverviewAll();
        }

        function close() {
            shellRoot.closeOverviewAll();
        }

        function refreshWallpaperCache() {
            shellRoot.refreshOverviewWallpaperCaches();
        }
    }

    IpcHandler {
        target: "island"

        function show() {
            shellRoot.showIslandAll();
        }

        function open() {
            shellRoot.showIslandAll();
        }

        function reveal() {
            shellRoot.showIslandAll();
        }

        function hide() {
            shellRoot.hideIslandAll();
        }

        function toggle() {
            shellRoot.toggleIslandAll();
        }

        function enableAutoHide() {
            shellRoot.islandAutoHideRuntimeEnabled = true;
            shellRoot.refreshIslandAutoHideAll();
        }

        function disableAutoHide() {
            shellRoot.islandAutoHideRuntimeEnabled = false;
            shellRoot.showIslandAll();
        }
    }

    IpcHandler {
        target: "tide"

        function showClock() {
            shellRoot.forFocusedWindow((window) => window.showClockWindow());
        }

        function showCustom() {
            shellRoot.forFocusedWindow((window) => window.showCustomInfoWindow());
        }

        function showLyrics() {
            shellRoot.forFocusedWindow((window) => window.showLyricsWindow());
        }

        function swipeRight() {
            shellRoot.forFocusedWindow((window) => window.swipeRightWindow());
        }

        function swipeLeft() {
            shellRoot.forFocusedWindow((window) => window.swipeLeftWindow());
        }

        function togglePlayer() {
            shellRoot.forFocusedWindow((window) => window.togglePlayerWindow());
        }

        function toggleControlCenter() {
            shellRoot.forFocusedWindow((window) => window.toggleControlCenterWindow());
        }

        function toggleNotificationCenter() {
            shellRoot.forFocusedWindow((window) => window.toggleNotificationCenterWindow());
        }

        function toggleWallpaperPicker() {
            shellRoot.forFocusedWindow((window) => window.toggleWallpaperPickerWindow());
        }

        function toggleApplicationLauncher() {
            shellRoot.forFocusedWindow((window) => window.toggleApplicationLauncherWindow());
        }

        // FORK: the theme switcher, one of the island states DESIGN-SPEC.md
        // lists and upstream does not have. Bound in hypr/binds.conf
        // alongside toggleWallpaperPicker.
        // FORK: qtile's DisplayPopup, ported. Bound to alt+4 in
        // hypr/binds.conf, which is the key it had in qtile.
        // FORK: qtile's WifiPopup and BluetoothPopup keys, landing straight
        // in the control centre's own lists. See openConnectivityPanelWindow.
        function toggleWifiPanel() {
            shellRoot.forFocusedWindow((window) => window.openConnectivityPanelWindow("wifi"));
        }

        function toggleBluetoothPanel() {
            shellRoot.forFocusedWindow((window) => window.openConnectivityPanelWindow("bluetooth"));
        }

        function toggleDisplayPanel() {
            shellRoot.forFocusedWindow((window) => window.toggleDisplayPanelWindow());
        }

        // FORK: qtile's AudioPopup, ported. Bound to alt+3 in hypr/binds.conf,
        // which is the key it had in qtile. Deliberately NOT folded into
        // toggleControlCenter: the control centre's Sound row is the volume of
        // the default sink, and this is everything else — which output is the
        // default, per-application volume and routing, card profiles, ports.
        function toggleAudioPanel() {
            shellRoot.forFocusedWindow((window) => window.toggleAudioPanelWindow());
        }

        function toggleThemePicker() {
            shellRoot.forFocusedWindow((window) => window.toggleThemePickerWindow());
        }

        // FORK: apply a theme THROUGH the circular reveal. This is what the
        // theme picker calls instead of running theme-apply itself, and it is
        // exposed on the IPC so `theme-toggle` (the rofi picker, which the
        // qtile session shares) can get the same animation later.
        function applyThemeAnimated(theme: string) {
            shellRoot.startThemeTransition(theme);
        }

        // FORK: arbitrary text in the island, which upstream has no way to
        // do — its `showCustom()` takes no arguments and renders the config's
        // own item list.
        //
        // The parameter MUST be declared with a type. Quickshell's IPC
        // marshals arguments by declared type and an untyped parameter is
        // simply not passed, so `function showText(text)` would accept the
        // call, arrive with undefined, and clear the indicator instead of
        // setting it — succeeding loudly at doing the opposite.
        //
        // Persistent on purpose: it stays until clearText, and survives any
        // transient OSD that interrupts it. hypr/scripts/submap-indicator.sh
        // is the first consumer.
        function showText(text: string) {
            shellRoot.forEachWindow((window) => {
                if (window && window.showModeIndicatorWindow)
                    window.showModeIndicatorWindow("", text);
            });
        }

        function showTextWithIcon(icon: string, text: string) {
            shellRoot.forEachWindow((window) => {
                if (window && window.showModeIndicatorWindow)
                    window.showModeIndicatorWindow(icon, text);
            });
        }

        function clearText() {
            shellRoot.forEachWindow((window) => {
                if (window && window.clearModeIndicatorWindow)
                    window.clearModeIndicatorWindow();
            });
        }
    }

    Connections {
        target: SystemServices

        function onNotificationReceived(appName, summary, body) {
            shellRoot.showNotificationAll(appName, summary, body);
        }
    }

    Component.onDestruction: {
        shuttingDown = true;
    }

    Component.onCompleted: {
        SystemServices.ensureUserConfigAvailable();
        SystemServices.requestScreenRecordingSnapshot();
    }

    Variants {
        id: panelVariants

        model: Quickshell.screens

        DynamicIslandWindow {
            required property var modelData

            screen: modelData
            shellRootController: shellRoot
        }
    }
}
