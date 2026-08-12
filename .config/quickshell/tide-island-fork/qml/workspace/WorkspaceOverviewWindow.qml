pragma ComponentBehavior: Bound

import QtQuick
import IslandBackend
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
// FORK: the shared motion system — one generated spring for geometry,
// one critically damped curve for opacity. See qml/common/Motion.js.
import "../common/Motion.js" as Motion
import "../common/Metrics.js" as Metrics

Item {
    id: root

    property var toplevel: null
    property var windowData: null
    property var monitorData: null
    property var widgetMonitor: null
    property real scale: 0.18
    property real xOffset: 0
    property real yOffset: 0
    property bool centerIcons: true
    property bool previewEnabled: true
    property bool hovered: false
    property bool pressed: false
    property bool draggingActive: false
    property bool forcePreviewActive: false
    property var positionOverride: null
    property real visibilityOpacity: 1
    property string labelFontFamily: ""
    property real topLeftRadius: 18
    property real topRightRadius: 18
    property real bottomLeftRadius: 18
    property real bottomRightRadius: 18

    readonly property real widthRatio: {
        if (!widgetMonitor || !monitorData)
            return 1;

        const widgetWidth = widgetMonitor.transform & 1 ? widgetMonitor.height : widgetMonitor.width;
        const monitorWidth = monitorData.transform & 1 ? monitorData.height : monitorData.width;
        return monitorWidth > 0 ? (widgetWidth * monitorData.scale) / (monitorWidth * widgetMonitor.scale) : 1;
    }
    readonly property real heightRatio: {
        if (!widgetMonitor || !monitorData)
            return 1;

        const widgetHeight = widgetMonitor.transform & 1 ? widgetMonitor.width : widgetMonitor.height;
        const monitorHeight = monitorData.transform & 1 ? monitorData.width : monitorData.height;
        return monitorHeight > 0 ? (widgetHeight * monitorData.scale) / (monitorHeight * widgetMonitor.scale) : 1;
    }
    readonly property real targetWindowWidth: Math.max(52, (windowData && windowData.size ? windowData.size[0] : 240) * scale * widthRatio)
    readonly property real targetWindowHeight: Math.max(38, (windowData && windowData.size ? windowData.size[1] : 140) * scale * heightRatio)
    readonly property real initX: {
        if (!windowData || !monitorData)
            return xOffset;

        const reserved = monitorData.reserved ? monitorData.reserved : [0, 0, 0, 0];
        const position = positionOverride
            ? [positionOverride.x, positionOverride.y]
            : (windowData.at ? windowData.at : [monitorData.x, monitorData.y]);
        return Math.max((position[0] - monitorData.x - reserved[0]) * widthRatio * scale, 0) + xOffset;
    }
    readonly property real initY: {
        if (!windowData || !monitorData)
            return yOffset;

        const reserved = monitorData.reserved ? monitorData.reserved : [0, 0, 0, 0];
        const position = positionOverride
            ? [positionOverride.x, positionOverride.y]
            : (windowData.at ? windowData.at : [monitorData.x, monitorData.y]);
        return Math.max((position[1] - monitorData.y - reserved[1]) * heightRatio * scale, 0) + yOffset;
    }
    // ---- WHY THIS DELIBERATELY DOES NOT READ `title` ----
    //
    // It used to fall through to initialTitle and then title, and that is a
    // live hazard here: a QML binding re-evaluates whenever anything it READS
    // changes, and a kitty window retitles on every prompt. Feeding a volatile
    // string into the identity of a tile means the tile's icon and label churn
    // while the user types into a terminal in another workspace. The class is
    // set once at map time and never moves, which is exactly what identity
    // wants. A window with no class at all gets the empty string and falls
    // through to the "?" plate below, which is honest.
    readonly property string iconLookupName: {
        if (!windowData)
            return "";

        return windowData.class || windowData.initialClass || windowData.app_id || "";
    }
    readonly property bool compactMode: Math.min(targetWindowWidth, targetWindowHeight) < 120
    readonly property string iconPath: compactMode ? resolveIconSource(iconLookupName) : ""
    readonly property string displayName: resolveDisplayName(iconLookupName)
    readonly property real baseOpacity: !windowData ? 0 : (widgetMonitor && windowData.monitor === widgetMonitor.id ? 1 : 0.46)
    readonly property bool previewActive: previewEnabled && !!toplevel && (forcePreviewActive || (visible && opacity > 0))

    // ---- THE ALIAS MAP, LIFTED FROM WindowRingStrip.qml ----
    //
    // Not re-derived: qml/island/WindowRingStrip.qml carries the full
    // measurement of why the five-link chain below has five links, and the
    // three entries here are the same three windows for the same reason —
    // they are kitty instances launched with `--class` so hyprctl can address
    // them as scratchpads, verified there by reading `comm` off each pid.
    // There is no icon and no desktop entry named `sum-md` on this system and
    // there never will be, because the name is this user's own.
    //
    // The NAME half is new, and it is the half that fixes the actual
    // complaint. `scratch-term1` is a dispatcher handle, not a label: it is
    // the string the keybind types, and printing it in an overview is showing
    // the user their own plumbing. The names below say what the window is.
    readonly property var appIdAliases: ({
        "scratch-term1": "kitty",
        "scratch-term2": "kitty",
        "sum-md": "kitty"
    })
    readonly property var appNameAliases: ({
        "scratch-term1": "Scratch 1",
        "scratch-term2": "Scratch 2",
        "sum-md": "sum.md",
        "tide-island-config-app": "Island Config"
    })

    // Five links, in the order established by WindowRingStrip.iconFor: alias,
    // exact, lowercased, trailing dotted segment (the reverse-DNS case), then
    // the desktop entry's own Icon= key (brave-browser's icon is called
    // `brave-desktop`, which no amount of string munging would ever find).
    // `true` is the `check` argument — a miss returns "" rather than a broken
    // image, which is what lets the chain fall through instead of stopping at
    // the first hit that happens to be a placeholder.
    function resolveIconSource(rawName) {
        const raw = String(rawName === undefined || rawName === null ? "" : rawName).trim();
        if (raw === "")
            return "";

        const aliased = root.appIdAliases[raw] || root.appIdAliases[raw.toLowerCase()] || raw;

        const direct = Quickshell.iconPath(aliased, true);
        if (direct)
            return direct;

        const lowered = Quickshell.iconPath(aliased.toLowerCase(), true);
        if (lowered)
            return lowered;

        const segments = aliased.split(".");
        if (segments.length > 1) {
            const tail = Quickshell.iconPath(segments[segments.length - 1].toLowerCase(), true);
            if (tail)
                return tail;
        }

        const viaEntry = desktopEntryField(aliased, "icon");
        if (viaEntry) {
            const resolved = Quickshell.iconPath(viaEntry, true);
            if (resolved)
                return resolved;
        }

        return Quickshell.iconPath("application-x-executable", true);
    }

    // The name chain is the same shape but one link shorter, because there is
    // no "lowercased" step for a human-readable string.
    //
    // The desktop entry is preferred over any prettifying of the class, and
    // that ordering was checked against every entry this machine actually
    // has rather than assumed: kitty -> "kitty", brave-browser -> "Brave",
    // org.qutebrowser.qutebrowser -> "qutebrowser", pcmanfm-qt -> "PCManFM-Qt
    // File Manager", anki -> "Anki". Prettifying the class instead would
    // print "Pcmanfm Qt" and "Brave Browser" — plausible-looking strings that
    // are simply not what those programs are called. The entry is the app's
    // own answer; the prettifier is a guess, and so it goes last.
    function resolveDisplayName(rawName) {
        const raw = String(rawName === undefined || rawName === null ? "" : rawName).trim();
        if (raw === "")
            return "";

        const alias = root.appNameAliases[raw] || root.appNameAliases[raw.toLowerCase()];
        if (alias)
            return alias;

        const entryName = desktopEntryField(raw, "name");
        if (entryName)
            return entryName;

        // Last resort: strip a reverse-DNS prefix, turn separators into
        // spaces, and capitalise. Wrong-looking for some apps, but a
        // wrong-looking name still identifies the window, and a blank plate
        // does not.
        const segments = raw.split(".");
        const tail = segments.length > 1 ? segments[segments.length - 1] : raw;
        return tail.replace(/[-_]+/g, " ").replace(/\b\w/g, function (c) {
            return c.toUpperCase();
        });
    }

    // Scanning .applications.values rather than calling heuristicLookup, for
    // the reason recorded in WindowRingStrip.qml: in a throwaway probe
    // instance heuristicLookup returned null for EVERY id including kitty's
    // and the entry list read as length 0, so a null could not be told apart
    // from an unpopulated singleton. The launcher reads this list and
    // demonstrably works, so this reads the same thing.
    function desktopEntryField(name, field) {
        const entries = (DesktopEntries && DesktopEntries.applications)
            ? DesktopEntries.applications.values : [];
        const wanted = String(name || "").toLowerCase();
        for (let index = 0; index < entries.length; index++) {
            const entry = entries[index];
            if (!entry || !entry[field])
                continue;
            const entryId = String(entry.id || "").toLowerCase().replace(/\.desktop$/, "");
            if (entryId === wanted)
                return String(entry[field]);
        }
        return "";
    }
    x: initX
    y: initY
    width: targetWindowWidth
    height: targetWindowHeight
    opacity: baseOpacity * visibilityOpacity

    Behavior on x {
        enabled: !root.draggingActive

        NumberAnimation {
            duration: 160
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Motion.spring()   // FORK: was Easing.OutCubic
        }
    }

    Behavior on y {
        enabled: !root.draggingActive

        NumberAnimation {
            duration: 160
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Motion.spring()   // FORK: was Easing.OutCubic
        }
    }

    Behavior on width {
        NumberAnimation {
            duration: 160
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Motion.spring()   // FORK: was Easing.OutCubic
        }
    }

    Behavior on height {
        NumberAnimation {
            duration: 160
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Motion.spring()   // FORK: was Easing.OutCubic
        }
    }

    ClippingRectangle {
        anchors.fill: parent
        color: "transparent"
        contentUnderBorder: true
        antialiasing: true
        topLeftRadius: root.topLeftRadius
        topRightRadius: root.topRightRadius
        bottomLeftRadius: root.bottomLeftRadius
        bottomRightRadius: root.bottomRightRadius
        border.width: 1
        border.color: root.hovered ? "#77ffffff" : "#33ffffff"

        ScreencopyView {
            anchors.fill: parent
            captureSource: root.previewActive ? root.toplevel : null
            constraintSize: Qt.size(Math.max(1, Math.round(root.width)), Math.max(1, Math.round(root.height)))
            live: root.previewActive
        }

        Rectangle {
            anchors.fill: parent
            color: root.draggingActive
                ? "#14ffffff"
                : (root.pressed
                    ? "#26000000"
                    : (root.hovered ? "#10ffffff" : "transparent"))
        }

        Image {
            id: appIcon

            readonly property real iconSize: Math.max(18, Math.min(root.width, root.height) * (root.compactMode ? 0.52 : 0.32))
            property bool iconLoadFailed: false

            anchors.centerIn: parent
            // Lifted by half the plate when a plate is there, so the icon
            // stays optically centred in the space it actually has rather
            // than in the space it would have had.
            anchors.verticalCenterOffset: namePlate.visible ? -namePlate.height / 2 : 0
            visible: root.compactMode && source !== ""
            source: root.compactMode && !iconLoadFailed ? root.iconPath : ""
            width: iconSize
            height: iconSize
            sourceSize: Qt.size(width, height)
            mipmap: true
            smooth: true
            opacity: 0.96

            onStatusChanged: {
                if (status === Image.Error)
                    iconLoadFailed = true;
            }

            Connections {
                target: root

                function onIconPathChanged() {
                    appIcon.iconLoadFailed = false;
                }
            }
        }

        // ---- THE NAME PLATE, AND WHY THE OVERVIEW HAD NO NAMES AT ALL ----
        //
        // The report was "the names of the apps not visible enough". Measured
        // before changing anything, and the answer was not contrast, not size
        // and not truncation: `grep -c 'Text\|Label' qml/workspace/` returned
        // ZERO. This overview never drew a name. The only identifying mark a
        // tile carried was the icon below, and that icon is gated behind
        // `compactMode`, which on this machine almost never fires:
        //
        //   monitor 1366x768, reserved [0,33,0,0], scale 0.18
        //   workspace cell            = 1366*0.18 x 735*0.18 = 246 x 132
        //   maximised window tile     = 246 x 132  -> min 132, NOT compact
        //   half-screen (2 columns)   = 123 x 132  -> min 123, NOT compact
        //   third-screen (3 columns)  =  82 x 132  -> min  82, compact
        //
        // Measured against the real screenshot: the cell borders sit at
        // x = 59, 300, 312, 552, 564, 804 — 241 to 245 px apart, which is the
        // 246 the formula predicts. So you need THREE tiled columns before an
        // icon appears, and one or two windows on a workspace — the normal
        // case — gives a bare 246x132 live preview of the window at 18% and
        // nothing else. A terminal at 18% is a grey texture. That is the bug.
        //
        // WHY A PLATE AND NOT JUST A COLOUR
        // ---------------------------------
        // The label sits on a LIVE PREVIEW, so there is no background colour
        // to pick a text colour against — the background is whatever the user
        // happens to have on screen, and it changes while they look at it. No
        // choice of text colour survives both a white page and a black
        // terminal. An opaque-ish plate is the only fix that is not a bet on
        // the wallpaper.
        //
        // Contrast, computed rather than eyeballed, worst case first. Plate is
        // StyleTokens.module (#1c1c1e) at 0.88 alpha; text is
        // StyleTokens.textPrimary (#f5f5f7, relative luminance 0.913).
        //
        //   over pure WHITE: composite = 0.88*0.1098 + 0.12*1.0 = 0.2166
        //                    -> luminance 0.0384 -> contrast 10.9:1
        //   over pure BLACK: composite = 0.0966 -> luminance 0.0095
        //                    -> contrast 16.2:1
        //
        // So the label never drops below 10.9:1 no matter what is behind it,
        // against WCAG AA's 4.5:1 for body text. 0.88 rather than 1.0 because
        // a fully opaque plate reads as a separate object stuck onto the tile;
        // at 0.88 the preview ghosts through just enough to read as part of
        // the same surface, and the arithmetic above says it costs nothing.
        //
        // Colour comes from StyleTokens with an explicit alpha rather than a
        // literal rgba: a hardcoded hex that ignores theme_mode has been a
        // repeat complaint in this shell, and Qt.rgba(0,0,0,0.88) would be
        // exactly that wearing a different syntax.
        Rectangle {
            id: namePlate

            readonly property real hPad: Metrics.pad(7)
            readonly property real maxWidth: Math.max(0, parent.width - Metrics.pad(12) * 2)

            // Below these the plate would be wider than the tile or would
            // collide with the icon, and a clipped half-word is worse than
            // the icon alone. 80x58 is roughly a quarter-screen tile.
            visible: root.displayName !== ""
                && root.targetWindowWidth >= Metrics.px(80)
                && root.targetWindowHeight >= Metrics.px(58)

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Metrics.pad(6)
            width: Math.min(nameLabel.implicitWidth + hPad * 2, maxWidth)
            height: Metrics.px(19)
            radius: height / 2
            color: Qt.rgba(StyleTokens.module.r, StyleTokens.module.g,
                           StyleTokens.module.b, 0.88)
            border.width: 1
            border.color: Qt.rgba(StyleTokens.white.r, StyleTokens.white.g,
                                  StyleTokens.white.b, 0.14)

            Text {
                id: nameLabel

                anchors.centerIn: parent
                width: Math.min(implicitWidth, namePlate.maxWidth - namePlate.hPad * 2)
                text: root.displayName
                color: StyleTokens.textPrimary
                font.family: root.labelFontFamily
                font.pixelSize: Metrics.font(11)
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignHCenter
                maximumLineCount: 1
            }
        }
    }
}
