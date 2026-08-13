pragma ComponentBehavior: Bound

import QtCore
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import "../common/ApplicationSearch.js" as ApplicationSearch

// FORK: one shared scale factor for every island surface.
import "../common/Metrics.js" as Metrics
// FORK: the shared motion system — one spring for geometry, one
// critically damped curve for opacity. See qml/common/Motion.js.
import "../common/Motion.js" as Motion
import "../common"

FocusScope {
    id: root

    signal closeRequested

    property bool showCondition: false
    property string iconFontFamily: ""
    property string textFontFamily: ""
    property string query: ""
    property var filteredApplications: []
    property var favoriteIds: []
    property var sortFavoriteIds: []
    property bool favoritesHydrated: false
    property int selectedIndex: -1
    property bool favoriteDragActive: false
    property string favoriteDragSourceId: ""
    property int favoriteDragSourceIndex: -1
    property int favoriteDragTargetIndex: -1
    property real favoriteDragStartContentX: 0
    property real favoriteDragTranslationX: 0
    property real favoriteDragPointerX: 0
    property string suppressedLaunchId: ""

    readonly property int visibleApplicationCount: filteredApplications.length

    focus: showCondition
    activeFocusOnTab: true
    anchors.fill: parent
    opacity: showCondition ? 1 : 0

    // FORK: one choreography for every layer in the shell.
    // Was `root.showCondition ? 220 : 120` on Easing.InOutQuad — one of
    // eight hand-picked in-durations and six out-durations that agreed
    // with neither each other nor the 400 ms the shape takes. See
    // Motion.js, "CONTENT CHOREOGRAPHY", for the measurement.
    Behavior on opacity {
        SequentialAnimation {
            // The delay is what keeps the content from being painted
            // inside a capsule that is still the wrong size for it.
            PauseAnimation { duration: root.showCondition ? Motion.contentDelay() : 0 }
            NumberAnimation {
                duration: root.showCondition ? Motion.fadeInDuration() : Motion.fadeOutDuration()
                // Critically damped: opacity is clamped 0-1 and an
                // overshooting fade reads as a cut. Motion.js says why.
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Motion.fade()
            }
        }
    }

    function isFavorite(entry) {
        return !!entry && root.favoriteIds.indexOf(String(entry.id)) >= 0;
    }

    function isSortFavorite(entry) {
        return !!entry && root.sortFavoriteIds.indexOf(String(entry.id)) >= 0;
    }

    function favoriteSortIndex(entry) {
        if (!entry)
            return -1;
        return root.sortFavoriteIds.indexOf(String(entry.id));
    }

    function visibleSortableFavoriteIds() {
        const visibleIds = [];
        for (let index = 0; index < root.filteredApplications.length; ++index) {
            const entry = root.filteredApplications[index];
            if (root.isFavorite(entry) && root.isSortFavorite(entry))
                visibleIds.push(String(entry.id));
        }
        return visibleIds;
    }

    function canDragFavorite(entry, index) {
        if (root.query !== "" || !root.isFavorite(entry) || !root.isSortFavorite(entry))
            return false;

        const visibleIds = root.visibleSortableFavoriteIds();
        return index >= 0 && index < visibleIds.length
            && visibleIds[index] === String(entry.id);
    }

    function beginFavoriteDrag(entry, index) {
        if (!root.canDragFavorite(entry, index))
            return;

        root.favoriteDragActive = true;
        root.favoriteDragSourceId = String(entry.id);
        root.favoriteDragSourceIndex = index;
        root.favoriteDragTargetIndex = index;
        root.favoriteDragStartContentX = appGrid.contentX;
        root.favoriteDragTranslationX = 0;
        root.favoriteDragPointerX = 0;
        root.suppressedLaunchId = root.favoriteDragSourceId;
    }

    function updateFavoriteDrag(translationX, pointerX) {
        if (!root.favoriteDragActive)
            return;

        root.favoriteDragTranslationX = translationX;
        root.favoriteDragPointerX = pointerX;
        root.refreshFavoriteDragTarget();
    }

    function refreshFavoriteDragTarget() {
        if (!root.favoriteDragActive)
            return;

        const favoriteCount = root.visibleSortableFavoriteIds().length;
        if (favoriteCount <= 0)
            return;

        const contentDelta = appGrid.contentX - root.favoriteDragStartContentX;
        const columnDelta = Math.round(
            (root.favoriteDragTranslationX + contentDelta) / appGrid.cellWidth);
        root.favoriteDragTargetIndex = Math.max(0, Math.min(
            favoriteCount - 1, root.favoriteDragSourceIndex + columnDelta));
    }

    function favoriteShiftForIndex(index) {
        if (!root.favoriteDragActive || index === root.favoriteDragSourceIndex)
            return 0;

        if (root.favoriteDragSourceIndex < root.favoriteDragTargetIndex
                && index > root.favoriteDragSourceIndex
                && index <= root.favoriteDragTargetIndex)
            return -appGrid.cellWidth;

        if (root.favoriteDragSourceIndex > root.favoriteDragTargetIndex
                && index >= root.favoriteDragTargetIndex
                && index < root.favoriteDragSourceIndex)
            return appGrid.cellWidth;

        return 0;
    }

    function favoriteDragVisualOffset() {
        if (!root.favoriteDragActive)
            return 0;
        return root.favoriteDragTranslationX
            + appGrid.contentX - root.favoriteDragStartContentX;
    }

    function finishFavoriteDrag() {
        if (!root.favoriteDragActive)
            return;

        const sourceId = root.favoriteDragSourceId;
        const sourceIndex = root.favoriteDragSourceIndex;
        const targetIndex = root.favoriteDragTargetIndex;
        const targetEntry = targetIndex >= 0 && targetIndex < root.filteredApplications.length
            ? root.filteredApplications[targetIndex] : null;
        const targetId = targetEntry ? String(targetEntry.id) : "";

        root.favoriteDragActive = false;
        root.favoriteDragSourceId = "";
        root.favoriteDragSourceIndex = -1;
        root.favoriteDragTargetIndex = -1;

        if (sourceId !== "" && targetId !== "" && sourceIndex !== targetIndex) {
            const nextFavorites = root.favoriteIds.slice();
            const storedSourceIndex = nextFavorites.indexOf(sourceId);
            if (storedSourceIndex >= 0)
                nextFavorites.splice(storedSourceIndex, 1);

            let storedTargetIndex = nextFavorites.indexOf(targetId);
            if (storedSourceIndex >= 0 && storedTargetIndex >= 0) {
                if (targetIndex > sourceIndex)
                    ++storedTargetIndex;
                nextFavorites.splice(storedTargetIndex, 0, sourceId);

                root.favoriteIds = nextFavorites;
                root.sortFavoriteIds = nextFavorites.slice();
                favoriteStore.favoriteIds = nextFavorites;
                favoritesFile.writeAdapter();
                root.rebuildApplications();
            }
        }

        suppressLaunchReset.restart();
    }

    function favoriteShortcutNumber(entry) {
        if (!entry)
            return 0;

        const entryId = String(entry.id);
        let shortcutNumber = 0;
        for (let index = 0; index < root.filteredApplications.length; ++index) {
            const candidate = root.filteredApplications[index];
            if (!root.isFavorite(candidate))
                continue;

            ++shortcutNumber;
            if (String(candidate.id) === entryId)
                return shortcutNumber;
        }
        return 0;
    }

    function shortcutNumberForKeyEvent(event) {
        const blockedModifiers = Qt.ControlModifier | Qt.AltModifier
            | Qt.MetaModifier | Qt.ShiftModifier;
        if (event.isAutoRepeat || (event.modifiers & blockedModifiers) !== 0)
            return 0;
        if (event.key < Qt.Key_1 || event.key > Qt.Key_9)
            return 0;
        return event.key - Qt.Key_0;
    }

    function launchFavoriteShortcut(event) {
        if (root.query !== "")
            return false;

        const requestedNumber = root.shortcutNumberForKeyEvent(event);
        if (requestedNumber === 0)
            return false;

        let shortcutNumber = 0;
        for (let index = 0; index < root.filteredApplications.length; ++index) {
            const entry = root.filteredApplications[index];
            if (!root.isFavorite(entry))
                continue;

            ++shortcutNumber;
            if (shortcutNumber === requestedNumber) {
                root.launchApplication(entry);
                return true;
            }
        }
        return false;
    }

    function applyFavorites(stored, adoptSortOrder) {
        const nextFavorites = [];
        const seen = ({});

        if (Array.isArray(stored)) {
            for (let index = 0; index < stored.length; ++index) {
                const entryId = String(stored[index] || "").trim();
                if (entryId === "" || seen[entryId])
                    continue;
                seen[entryId] = true;
                nextFavorites.push(entryId);
            }
        }

        root.favoriteIds = nextFavorites;
        if (adoptSortOrder && !root.favoritesHydrated)
            root.sortFavoriteIds = nextFavorites.slice();
        root.favoritesHydrated = true;
        root.rebuildApplications();
    }

    function loadFavoritesFromDisk(adoptSortOrder) {
        let stored = [];
        try {
            const contents = favoritesFile.text();
            if (contents.trim() !== "") {
                const parsed = JSON.parse(contents);
                stored = parsed && Array.isArray(parsed.favoriteIds) ? parsed.favoriteIds : [];
            }
        } catch (error) {
            stored = [];
        }
        root.applyFavorites(stored, adoptSortOrder);
    }

    function toggleFavorite(entry) {
        if (!entry)
            return;

        if (!root.favoritesHydrated) {
            favoritesFile.waitForJob();
            root.loadFavoritesFromDisk(true);
        }

        const entryId = String(entry.id);
        const nextFavorites = root.favoriteIds.slice();
        const existingIndex = nextFavorites.indexOf(entryId);
        if (existingIndex >= 0)
            nextFavorites.splice(existingIndex, 1);
        else
            nextFavorites.push(entryId);

        root.favoriteIds = nextFavorites;
        favoriteStore.favoriteIds = nextFavorites;
        favoritesFile.writeAdapter();
    }

    function rebuildApplications() {
        const hasQuery = ApplicationSearch.normalize(root.query) !== "";
        const available = DesktopEntries.applications.values;
        const rankedApplications = [];

        for (let index = 0; index < available.length; ++index) {
            const entry = available[index];
            if (!entry || entry.noDisplay || String(entry.name).trim() === "")
                continue;

            const score = hasQuery ? ApplicationSearch.applicationScore(entry, root.query) : 0;
            if (score < 0)
                continue;
            rankedApplications.push({
                entry: entry,
                score: score + (hasQuery && root.isFavorite(entry) ? 45 : 0)
            });
        }

        rankedApplications.sort((left, right) => {
            if (hasQuery && left.score !== right.score)
                return right.score - left.score;

            const leftFavorite = root.isSortFavorite(left.entry);
            const rightFavorite = root.isSortFavorite(right.entry);
            if (!hasQuery && leftFavorite !== rightFavorite)
                return leftFavorite ? -1 : 1;
            if (!hasQuery && leftFavorite && rightFavorite) {
                const favoriteOrder = root.favoriteSortIndex(left.entry)
                    - root.favoriteSortIndex(right.entry);
                if (favoriteOrder !== 0)
                    return favoriteOrder;
            }

            const nameOrder = String(left.entry.name).localeCompare(String(right.entry.name));
            if (nameOrder !== 0)
                return nameOrder;
            return String(left.entry.id).localeCompare(String(right.entry.id));
        });
        const nextApplications = rankedApplications.map(candidate => candidate.entry);
        root.filteredApplications = nextApplications;
        root.selectedIndex = nextApplications.length > 0 ? 0 : -1;
        if (!appGrid)
            return;
        appGrid.currentIndex = root.selectedIndex;
        if (root.selectedIndex >= 0)
            appGrid.positionViewAtIndex(root.selectedIndex, GridView.Beginning);
    }

    function grabKeyboardFocus() {
        root.forceActiveFocus();
        searchInput.forceActiveFocus();
    }

    function moveSelection(offset) {
        const count = root.visibleApplicationCount;
        if (count <= 0)
            return;

        root.selectedIndex = (root.selectedIndex + offset + count) % count;
        appGrid.currentIndex = root.selectedIndex;
        appGrid.positionViewAtIndex(root.selectedIndex, GridView.Contain);
    }

    function launchApplication(entry) {
        if (!entry)
            return;

        const desktopCommand = [];
        for (let index = 0; index < entry.command.length; ++index)
            desktopCommand.push(String(entry.command[index]));

        if (desktopCommand.length === 0) {
            entry.execute();
        } else {
            const scopedCommand = [
                "systemd-run",
                "--user",
                "--scope",
                "--quiet",
                "--collect",
                "--slice=app.slice",
                "--expand-environment=no"
            ];
            const workingDirectory = String(entry.workingDirectory || "");
            if (workingDirectory !== "")
                scopedCommand.push("--working-directory=" + workingDirectory);
            scopedCommand.push("--");
            for (let index = 0; index < desktopCommand.length; ++index)
                scopedCommand.push(desktopCommand[index]);

            // Keep launched applications outside tide-island.service so a
            // service restart cannot kill their child process trees.
            Quickshell.execDetached(scopedCommand);
        }
        root.closeRequested();
    }

    function launchSelected() {
        if (root.selectedIndex < 0 || root.selectedIndex >= root.visibleApplicationCount)
            return;
        root.launchApplication(root.filteredApplications[root.selectedIndex]);
    }

    onShowConditionChanged: {
        if (showCondition) {
            sortFavoriteIds = favoriteIds.slice();
            searchInput.text = "";
            query = "";
            rebuildApplications();
            focusTimer.restart();
        }
    }

    Component.onCompleted: rebuildApplications()

    Connections {
        target: DesktopEntries

        function onApplicationsChanged() {
            root.rebuildApplications();
        }
    }

    FileView {
        id: favoritesFile
        path: StandardPaths.writableLocation(StandardPaths.GenericConfigLocation)
            + "/tide-island/application-launcher.json"
        preload: true
        watchChanges: true
        atomicWrites: true
        printErrors: false

        JsonAdapter {
            id: favoriteStore
            property var favoriteIds: []
        }

        onLoaded: root.loadFavoritesFromDisk(true)
    }

    Timer {
        id: focusTimer
        interval: 0
        repeat: false
        onTriggered: root.grabKeyboardFocus()
    }

    Timer {
        id: suppressLaunchReset
        interval: 0
        repeat: false
        onTriggered: root.suppressedLaunchId = ""
    }

    Timer {
        interval: 16
        repeat: true
        running: root.favoriteDragActive

        onTriggered: {
            const edgeSize = 48;
            const minimumContentX = appGrid.originX;
            const maximumContentX = minimumContentX
                + Math.max(0, appGrid.contentWidth - appGrid.width);
            let nextContentX = appGrid.contentX;

            if (root.favoriteDragPointerX < edgeSize)
                nextContentX = Math.max(minimumContentX, nextContentX - 10);
            else if (root.favoriteDragPointerX > appGrid.width - edgeSize)
                nextContentX = Math.min(maximumContentX, nextContentX + 10);

            if (nextContentX !== appGrid.contentX) {
                appGrid.contentX = nextContentX;
                root.refreshFavoriteDragTarget();
            }
        }
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) {
            root.closeRequested();
            event.accepted = true;
        } else if (root.launchFavoriteShortcut(event)) {
            event.accepted = true;
        }
    }

    Column {
        anchors.fill: parent
        anchors.topMargin: Metrics.pad(15)
        anchors.bottomMargin: Metrics.pad(12)
        anchors.leftMargin: Metrics.pad(22)
        anchors.rightMargin: Metrics.pad(22)
        spacing: Metrics.px(10)

        Item {
            width: parent.width
            height: Metrics.px(46)

            Rectangle {
                id: searchField
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(650, parent.width - 120)
                height: parent.height
                radius: Metrics.px(17)
                color: searchInput.activeFocus ? IslandTheme.inputFillFocused : IslandTheme.inputFill
                border.width: 1
                border.color: searchInput.activeFocus ? IslandTheme.inputBorderFocused : IslandTheme.inputBorder

                Behavior on color { ColorAnimation { duration: 140 } }
                Behavior on border.color { ColorAnimation { duration: 140 } }

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: Metrics.pad(16)
                    anchors.verticalCenter: parent.verticalCenter
                    text: "\uf002"
                    color: searchInput.activeFocus ? IslandTheme.textSecondary : IslandTheme.textMuted
                    font.family: root.iconFontFamily
                    font.pixelSize: Metrics.font(15)
                }

                TextInput {
                    id: searchInput
                    anchors.left: parent.left
                    anchors.leftMargin: Metrics.pad(45)
                    anchors.right: parent.right
                    anchors.rightMargin: root.query === "" ? 16 : 42
                    anchors.verticalCenter: parent.verticalCenter
                    color: IslandTheme.textPrimary
                    selectionColor: IslandTheme.accent
                    selectedTextColor: IslandTheme.accentInk
                    font.family: root.textFontFamily
                    font.pixelSize: Metrics.font(15)
                    clip: true
                    selectByMouse: true
                    text: ""

                    onTextChanged: {
                        if (root.query !== text)
                            root.query = text;
                        root.rebuildApplications();
                    }

                    // ---- FORK: VIM MOTIONS, AND WHY THEY CARRY CTRL ----
                    //
                    // Reported as "I cannot use vim motions there", and the
                    // reason is the field: this TextInput holds the keyboard
                    // for the whole life of the panel, so a bare `j` is a
                    // letter and always was. Measured before changing
                    // anything — `wtype j` with the launcher open put a `j`
                    // in the box and filtered the row down to five apps.
                    //
                    // PickerLayer solves the same conflict by letting bare
                    // j/k move WHILE THE QUERY IS EMPTY, and that rule is
                    // deliberately NOT copied here. Its own comment says why,
                    // about this very panel: "the application launcher can
                    // spend Left/Right on it because its own field takes the
                    // letters." The launcher opens with the field cleared
                    // every single time (onShowConditionChanged), so "empty"
                    // is not a state you pass through — it is the state every
                    // search starts in. Spending bare h/j/k/l there would
                    // mean the first keystroke after opening is never a
                    // letter, and gimp, htop, kitty and libreoffice all start
                    // with one of the four.
                    //
                    // So the motions carry Ctrl and are therefore unambiguous
                    // in BOTH states — they keep working after you have typed
                    // half a name, which is the state this panel spends most
                    // of its time in and the state PickerLayer's rule gives
                    // up on.
                    //
                    //   Ctrl+l / Ctrl+j / Ctrl+n   next
                    //   Ctrl+h / Ctrl+k / Ctrl+p   previous
                    //
                    // h/l and j/k both appear because the row is horizontal
                    // and the shell is not: h/l is the axis actually on
                    // screen (the same pairing WallpaperPickerLayer and
                    // ThemePickerLayer use for their horizontal moves), while
                    // j/k is what every list in this shell answers to and
                    // what the existing Down/Up already do here. Ctrl+n/p are
                    // PickerLayer's readline pair, kept identical so one hand
                    // position works on both panels.
                    //
                    // The cost, stated because it is invisible: Qt's X11 key
                    // bindings give a text field Ctrl+H as Backspace and
                    // Ctrl+K as delete-to-end-of-line, and a Keys.onPressed
                    // handler runs BEFORE the item, so accepting these takes
                    // both away inside this field. PickerLayer already spends
                    // Ctrl+H the same way (it pops a page), so this panel is
                    // following the shell rather than setting a precedent.
                    Keys.onPressed: event => {
                        const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;

                        if (event.key === Qt.Key_Escape) {
                            root.closeRequested();
                            event.accepted = true;
                        } else if (root.launchFavoriteShortcut(event)) {
                            event.accepted = true;
                        } else if (ctrl && (event.key === Qt.Key_L
                                || event.key === Qt.Key_J
                                || event.key === Qt.Key_N)) {
                            root.moveSelection(1);
                            event.accepted = true;
                        } else if (ctrl && (event.key === Qt.Key_H
                                || event.key === Qt.Key_K
                                || event.key === Qt.Key_P)) {
                            root.moveSelection(-1);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Right && text === "") {
                            root.moveSelection(1);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab) {
                            root.moveSelection(1);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Left && text === "") {
                            root.moveSelection(-1);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Up || event.key === Qt.Key_Backtab) {
                            root.moveSelection(-1);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            root.launchSelected();
                            event.accepted = true;
                        }
                    }

                    // FORK: the panel had no placeholder of any kind, so an
                    // empty field said nothing about what the keys are —
                    // which is most of why the motions read as missing rather
                    // than as unbound. Same sentence shape as PickerLayer's
                    // and CheatsheetLayer's, so the three search fields in
                    // this shell introduce themselves the same way.
                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        visible: parent.text === ""
                        text: "type to search — Ctrl+h/j/k/l move, Enter launches, Esc closes"
                        color: IslandTheme.textDisabled
                        font.family: root.textFontFamily
                        font.pixelSize: Metrics.font(13)
                    }
                }

                Rectangle {
                    anchors.right: parent.right
                    anchors.rightMargin: Metrics.pad(11)
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.query !== ""
                    width: Metrics.px(24)
                    height: Metrics.px(24)
                    radius: Metrics.px(12)
                    color: clearSearchArea.containsMouse ? IslandTheme.surfaceRaisedHover : IslandTheme.surfaceRaised

                    Text {
                        anchors.centerIn: parent
                        text: "\uf00d"
                        color: IslandTheme.textSecondary
                        font.family: root.iconFontFamily
                        font.pixelSize: Metrics.font(10)
                    }

                    MouseArea {
                        id: clearSearchArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            searchInput.text = "";
                            searchInput.forceActiveFocus();
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    z: -1
                    onClicked: searchInput.forceActiveFocus()
                }
            }

        }

        GridView {
            id: appGrid
            width: parent.width
            height: parent.height - y
            model: root.filteredApplications
            cellWidth: Metrics.px(126)
            cellHeight: height
            flow: GridView.FlowTopToBottom
            clip: true

            // FORK: P1-3. HORIZONTAL, not vertical — this grid flows
            // TopToBottom with cellHeight bound to its own height, so it is
            // one tall row that scrolls sideways, and a vertical bar here
            // would be an indicator for an axis that never moves.
            ScrollBar.horizontal: IslandScrollBar { view: appGrid }

            interactive: !root.favoriteDragActive
            boundsBehavior: Flickable.StopAtBounds
            flickDeceleration: 1800
            keyNavigationEnabled: false

            delegate: Item {
                id: appDelegate
                required property var modelData
                required property int index

                readonly property var entry: modelData
                readonly property bool selected: index === root.selectedIndex
                readonly property bool favorite: root.isFavorite(entry)
                readonly property int favoriteNumber: root.favoriteShortcutNumber(entry)
                readonly property bool favoriteDraggable: root.canDragFavorite(entry, index)

                width: appGrid.cellWidth
                height: appGrid.cellHeight
                z: root.favoriteDragActive
                    && root.favoriteDragSourceId === String(entry.id) ? 10 : 0

                Item {
                    id: appCard

                    z: 2
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: 8
                    width: parent.width - 10
                    height: Metrics.px(124)
                    scale: favoriteDrag.active ? 1.07
                        : appArea.pressed ? 0.95
                        : (appDelegate.selected || appArea.containsMouse ? 1.035 : 1)

                    Behavior on scale {
                        NumberAnimation {
                            duration: 150
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Motion.spring()   // FORK: was Easing.OutCubic
                        }
                    }

                    transform: [
                        Translate {
                            x: root.favoriteDragActive
                                && root.favoriteDragSourceId === String(appDelegate.entry.id)
                                ? root.favoriteDragVisualOffset() : 0
                        },
                        Translate {
                            x: root.favoriteShiftForIndex(appDelegate.index)

                            Behavior on x {
                                NumberAnimation {
                                    duration: 150
                                    easing.type: Easing.BezierSpline
                                    easing.bezierCurve: Motion.spring()   // FORK: was Easing.OutCubic
                                }
                            }
                        }
                    ]

                    Item {
                        id: iconArea
                        anchors.top: parent.top
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Metrics.px(76)
                        height: Metrics.px(76)

                        IconImage {
                            id: appIcon
                            anchors.centerIn: parent
                            width: Metrics.px(64)
                            height: Metrics.px(64)
                            source: Quickshell.iconPath(appDelegate.entry.icon, true)
                            asynchronous: true
                            mipmap: true
                        }

                        Text {
                            anchors.centerIn: parent
                            z: 100
                            visible: appIcon.source.toString() === ""
                            text: String(appDelegate.entry.name).charAt(0).toLocaleUpperCase()
                            color: IslandTheme.textPrimary
                            font.family: root.textFontFamily
                            font.pixelSize: Metrics.font(24)
                            font.weight: Font.DemiBold
                        }

                        Text {
                            anchors.top: parent.top
                            anchors.topMargin: Metrics.pad(-2)
                            anchors.left: parent.left
                            anchors.leftMargin: Metrics.pad(-2)
                            visible: appDelegate.favoriteNumber > 0
                            text: appDelegate.favoriteNumber
                            color: IslandTheme.textSecondary
                            font.family: root.textFontFamily
                            font.pixelSize: Metrics.font(12)
                            font.weight: Font.DemiBold
                        }
                    }

                    Text {
                        anchors.top: iconArea.bottom
                        anchors.topMargin: Metrics.pad(10)
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width - 8
                        text: appDelegate.entry.name
                        color: appDelegate.selected ? IslandTheme.textPrimary : IslandTheme.textSecondary
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        font.family: root.textFontFamily
                        font.pixelSize: Metrics.font(12)
                        font.weight: appDelegate.selected ? Font.Medium : Font.Normal
                    }

                    FavoriteStar {
                        anchors.top: iconArea.top
                        anchors.topMargin: Metrics.pad(-2)
                        anchors.right: iconArea.right
                        anchors.rightMargin: Metrics.pad(-4)
                        active: appDelegate.favorite
                        hovered: delegateHover.hovered
                        onToggleRequested: root.toggleFavorite(appDelegate.entry)
                    }
                }

                MouseArea {
                    id: appArea
                    z: 1
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    hoverEnabled: true
                    cursorShape: favoriteDrag.active ? Qt.ClosedHandCursor
                        : appDelegate.favoriteDraggable ? Qt.OpenHandCursor
                        : Qt.PointingHandCursor
                    onEntered: {
                        root.selectedIndex = appDelegate.index;
                        appGrid.currentIndex = appDelegate.index;
                    }
                    onClicked: mouse => {
                        if (root.suppressedLaunchId === String(appDelegate.entry.id))
                            return;
                        if (mouse.button === Qt.RightButton)
                            root.toggleFavorite(appDelegate.entry);
                        else
                            root.launchApplication(appDelegate.entry);
                    }
                }

                HoverHandler {
                    id: delegateHover
                }

                DragHandler {
                    id: favoriteDrag

                    enabled: appDelegate.favoriteDraggable
                    target: null
                    acceptedButtons: Qt.LeftButton
                    xAxis.enabled: true
                    yAxis.enabled: false

                    onActiveChanged: {
                        if (active) {
                            root.beginFavoriteDrag(appDelegate.entry, appDelegate.index);
                            const point = appDelegate.mapToItem(
                                appGrid, centroid.position.x, centroid.position.y);
                            root.updateFavoriteDrag(activeTranslation.x, point.x);
                        } else if (root.favoriteDragSourceId === String(appDelegate.entry.id)) {
                            root.finishFavoriteDrag();
                        }
                    }
                    onActiveTranslationChanged: {
                        if (!active)
                            return;
                        const point = appDelegate.mapToItem(
                            appGrid, centroid.position.x, centroid.position.y);
                        root.updateFavoriteDrag(activeTranslation.x, point.x);
                    }
                }
            }

            Text {
                anchors.centerIn: parent
                visible: root.visibleApplicationCount === 0
                text: root.query === "" ? "No launchable applications" : "No match for \u201c" + root.query + "\u201d"
                color: IslandTheme.textDisabled
                font.family: root.textFontFamily
                font.pixelSize: Metrics.font(13)
            }
        }
    }
}
