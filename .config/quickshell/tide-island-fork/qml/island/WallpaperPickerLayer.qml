import QtCore
import QtQuick
// MultiEffect, for the neighbour desaturation. See the delegate.
import QtQuick.Effects
import Quickshell.Io
import Quickshell.Widgets
import IslandBackend

// FORK: one shared scale factor for every island surface.
import "../common/Metrics.js" as Metrics
// FORK: the shared motion system — one spring for geometry, one
// critically damped curve for opacity. See qml/common/Motion.js.
import "../common/Motion.js" as Motion
import "../common"

FocusScope {
    id: root

    signal closeRequested
    signal wallpaperApplied(string filePath)
    signal wallpaperApplySucceeded(string filePath)

    property bool showCondition: false
    property string iconFontFamily: ""
    property string textFontFamily: ""
    readonly property var userConfig: UserConfig

    property bool pywalEnabled: userConfig.wallpaperPywalEnabled
    property bool customCommandEnabled: userConfig.wallpaperCustomCommandEnabled === true
    property string customCommand: userConfig.wallpaperCustomCommand === undefined || userConfig.wallpaperCustomCommand === null ? "" : String(userConfig.wallpaperCustomCommand)
    property int transitionFps: boundedInt(userConfig.wallpaperTransitionFps, 60, 1, 240)
    property int transitionStep: boundedInt(userConfig.wallpaperTransitionStep, 5, 1, 255)
    property real transitionDuration: boundedReal(userConfig.wallpaperTransitionDuration, 3.0, 0, 120)
    property int transitionAngle: boundedInt(userConfig.wallpaperTransitionAngle, 45, 0, 360)
    property string transitionPosition: nonEmptyString(userConfig.wallpaperTransitionPosition, "center")
    property string transitionBezier: nonEmptyString(userConfig.wallpaperTransitionBezier, ".54,0,.34,.99")
    property string transitionWave: nonEmptyString(userConfig.wallpaperTransitionWave, "20,20")
    property bool transitionInvertY: userConfig.wallpaperTransitionInvertY
    property string wallpaperDir: userConfig.wallpaperLibraryPath
    property string targetWallpaperPath: userConfig.wallpaperPath
    property int thumbnailWidth: 640
    property int thumbnailHeight: 360
    property int thumbnailQuality: 80

    property bool wallpapersLoaded: false
    property string activeWallpaper: ""
    property string latestAppliedWallpaper: ""
    property bool acceptingScanResults: false
    property bool closeAfterApply: false
    property bool releasingResources: false
    property var wallpaperIndexByPath: ({})
    property var pendingThumbnails: []
    property var pendingThumbnailKeys: ({})
    property bool thumbnailInFlight: false
    property string inFlightThumbnailSourcePath: ""
    property string inFlightThumbnailCachePath: ""

    readonly property string effectiveActiveWallpaper: latestAppliedWallpaper !== "" ? latestAppliedWallpaper : activeWallpaper
    readonly property string cacheRoot: localPath(StandardPaths.writableLocation(StandardPaths.GenericCacheLocation))
        + "/quickshell/dynamic_island/wallpaper-picker"
    readonly property string scanScript: "import hashlib,json,os,sys\n"
        + "cache_dir=sys.argv[1]\n"
        + "wallpaper_dir=os.path.expanduser(sys.argv[2])\n"
        + "tw,th,quality=sys.argv[3],sys.argv[4],sys.argv[5]\n"
        + "exts={'.jpg','.jpeg','.png','.webp','.gif','.avif','.tiff','.bmp'}\n"
        + "index_path=os.path.join(cache_dir,'wallpapers.json')\n"
        + "os.makedirs(cache_dir,exist_ok=True)\n"
        + "def thumb_path(path,st):\n"
        + "    key='{}|{}|{}|{}x{}|q{}'.format(path,st.st_mtime_ns,st.st_size,tw,th,quality)\n"
        + "    return os.path.join(cache_dir,'wallpaper-'+hashlib.sha1(key.encode('utf-8','surrogateescape')).hexdigest()[:24]+'.jpg')\n"
        + "def record(path):\n"
        + "    st=os.stat(path)\n"
        + "    cache_path=thumb_path(path,st)\n"
        + "    return {'filePath':path,'fileName':os.path.basename(path),'cachePath':cache_path,'cacheAvailable':os.path.isfile(cache_path),'mtime':st.st_mtime_ns,'size':st.st_size}\n"
        + "def emit(phase,records):\n"
        + "    for rec in records:\n"
        + "        rec=dict(rec)\n"
        + "        rec['phase']=phase\n"
        + "        print(json.dumps(rec,separators=(',',':')),flush=True)\n"
        + "def valid_path(path):\n"
        + "    return os.path.splitext(path)[1].lower() in exts and os.path.isfile(path)\n"
        + "cached=[]\n"
        + "try:\n"
        + "    with open(index_path,'r',encoding='utf-8') as f:\n"
        + "        for item in json.load(f):\n"
        + "            path=item.get('filePath','')\n"
        + "            if valid_path(path):\n"
        + "                cached.append(record(path))\n"
        + "except Exception:\n"
        + "    pass\n"
        + "emit('index',cached)\n"
        + "fresh=[]\n"
        + "if os.path.isdir(wallpaper_dir):\n"
        + "    for entry in sorted(os.scandir(wallpaper_dir),key=lambda e:e.name.lower()):\n"
        + "        if entry.is_file() and os.path.splitext(entry.name)[1].lower() in exts:\n"
        + "            try:\n"
        + "                fresh.append(record(entry.path))\n"
        + "            except OSError:\n"
        + "                pass\n"
        + "emit('scan',fresh)\n"
        + "try:\n"
        + "    tmp=index_path+'.tmp'\n"
        + "    with open(tmp,'w',encoding='utf-8') as f:\n"
        + "        json.dump(fresh,f,separators=(',',':'))\n"
        + "    os.replace(tmp,index_path)\n"
        + "except Exception:\n"
        + "    pass\n"
    readonly property string applyScript: "import os,shutil,subprocess,sys\n"
        + "source,target,transition,step,duration,fps,angle,pos,bezier,wave,invert_y,pywal_enabled=sys.argv[1:13]\n"
        + "if not source:\n"
        + "    sys.exit(2)\n"
        + "applied=source\n"
        + "if target:\n"
        + "    target=os.path.expanduser(target)\n"
        + "    if os.path.realpath(source) != os.path.realpath(target):\n"
        + "        os.makedirs(os.path.dirname(target) or '.',exist_ok=True)\n"
        + "        shutil.copy2(source,target)\n"
        + "    applied=target\n"
        // FORK: routed through wallpaper-set.sh, not run directly.
        //
        // Upstream runs `awww img <path> --transition-*` itself. This calls
        // hypr/scripts/wallpaper-set.sh instead, which records the choice in
        // ~/.cache/wall — the single source of truth theme-apply and the
        // still-running qtile session both read — and then hands off to
        // wallpaper-sync.sh. Going through the script is what keeps the two
        // sessions from disagreeing about the wallpaper; running awww here
        // would set it without recording it, and qtile would revert on its
        // next login.
        //
        // UPDATED: this comment used to read "hyprpaper, not swww", because
        // awww (which is what swww is called now — Arch ships extra/awww,
        // and searching for "swww" finds nothing) was not installed and
        // clicking a thumbnail did NOTHING while saying nothing: a missing
        // binary exits non-zero, the picker only checks `exitCode === 0`
        // before emitting "applied", so it just closed. awww is installed
        // now and wallpaper-sync.sh drives it with a wave transition, so the
        // transition-* settings in userconfig.json — which are awww's
        // parameter names and were configuring a program that was not there
        // — finally have something behind them. The hyprpaper-specific
        // trap that `preload` no longer exists in 0.8.4 is gone with it.
        + "cmd=[os.path.expanduser('~/.config/hypr/scripts/wallpaper-set.sh'),applied]\n"
        + "result=subprocess.run(cmd,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)\n"
        + "if result.returncode == 0 and pywal_enabled == 'true':\n"
        + "    if not shutil.which('wal'):\n"
        + "        print(\"Pywal is enabled, but the 'wal' command was not found in PATH.\",file=sys.stderr)\n"
        + "        sys.exit(127)\n"
        + "    result=subprocess.run(['wal','-n','-q','-i',source])\n"
        + "sys.exit(result.returncode)\n"

    readonly property var transitionTypes: ["none", "simple", "fade", "left", "right", "top", "bottom", "wipe", "wave", "grow", "center", "any", "outer", "random"]
    readonly property string configuredTransitionType: validTransitionType(userConfig.wallpaperTransitionType)

    focus: showCondition
    activeFocusOnTab: true
    anchors.fill: parent
    opacity: showCondition ? 1 : 0

    // FORK: one choreography for every layer in the shell.
    // Was `showCondition ? 240 : 120` on Easing.InOutQuad — one of
    // eight hand-picked in-durations and six out-durations that agreed
    // with neither each other nor the 400 ms the shape takes. See
    // Motion.js, "CONTENT CHOREOGRAPHY", for the measurement.
    Behavior on opacity {
        SequentialAnimation {
            // The delay is what keeps the content from being painted
            // inside a capsule that is still the wrong size for it.
            PauseAnimation { duration: showCondition ? Motion.contentDelay() : 0 }
            NumberAnimation {
                duration: showCondition ? Motion.fadeInDuration() : Motion.fadeOutDuration()
                // Critically damped: opacity is clamped 0-1 and an
                // overshooting fade reads as a cut. Motion.js says why.
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Motion.fade()
            }
        }
    }

    onShowConditionChanged: {
        if (showCondition) {
            if (!wallpapersLoaded)
                startScan();
            else
                syncCurrentIndex();
            root.grabKeyboardFocus();
        } else {
            releaseResources();
        }
    }

    Component.onDestruction: releaseResources()

    function startScan() {
        releasingResources = false;
        acceptingScanResults = true;
        wallpapersLoaded = false;
        wallpaperIndexByPath = ({});
        pendingThumbnails = [];
        pendingThumbnailKeys = ({});
        thumbnailInFlight = false;
        inFlightThumbnailSourcePath = "";
        inFlightThumbnailCachePath = "";
        allWallpapers.clear();
        if (scanProcess.running)
            scanProcess.running = false;
        scanProcess.running = true;
    }

    function releaseResources() {
        if (releasingResources)
            return;
        releasingResources = true;
        acceptingScanResults = false;
        closeAfterApply = false;
        if (scanProcess.running)
            scanProcess.running = false;
        if (applyProcess.running)
            applyProcess.running = false;
        if (customApplyProcess.running)
            customApplyProcess.running = false;
        pendingThumbnails = [];
        pendingThumbnailKeys = ({});
        thumbnailInFlight = false;
        inFlightThumbnailSourcePath = "";
        inFlightThumbnailCachePath = "";
        wallpapersLoaded = false;
        wallpaperIndexByPath = ({});
        allWallpapers.clear();
        releasingResources = false;
    }

    function localPath(value) {
        if (value === undefined || value === null)
            return "";
        if (value.toLocalFile)
            return value.toLocalFile();

        const text = String(value);
        return text.startsWith("file://") ? text.substring(7) : text;
    }

    function toFileUrl(localFile) {
        return localFile === "" ? "" : ("file://" + encodeURI(localFile));
    }

    function thumbnailUrl(cachePath, revision) {
        return cachePath === "" ? "" : (toFileUrl(cachePath) + "?v=" + revision);
    }

    function displayPath(path) {
        return path === "" ? "wallpaperLibraryPath" : path;
    }

    function boundedInt(value, fallback, minimumValue, maximumValue) {
        const number = Number(value);
        if (!isFinite(number))
            return fallback;
        return Math.max(minimumValue, Math.min(maximumValue, Math.round(number)));
    }

    function boundedReal(value, fallback, minimumValue, maximumValue) {
        const number = Number(value);
        if (!isFinite(number))
            return fallback;
        return Math.max(minimumValue, Math.min(maximumValue, number));
    }

    function nonEmptyString(value, fallback) {
        const text = String(value === undefined || value === null ? "" : value).trim();
        return text.length > 0 ? text : fallback;
    }

    function validTransitionType(value) {
        const text = nonEmptyString(value, "center");
        return transitionTypes.indexOf(text) >= 0 ? text : "center";
    }

    function enqueueThumbnail(sourcePath, cachePath) {
        if (!root.showCondition || sourcePath === "" || cachePath === "")
            return;
        if (cachePath === inFlightThumbnailCachePath)
            return;
        if (pendingThumbnailKeys[cachePath])
            return;
        pendingThumbnailKeys[cachePath] = true;
        pendingThumbnails.push({
            sourcePath: sourcePath,
            cachePath: cachePath
        });
        startNextThumbnail();
    }

    function startNextThumbnail() {
        if (!root.showCondition || thumbnailInFlight || pendingThumbnails.length === 0)
            return;

        const next = pendingThumbnails.shift();
        inFlightThumbnailSourcePath = next.sourcePath;
        inFlightThumbnailCachePath = next.cachePath;
        delete pendingThumbnailKeys[next.cachePath];
        thumbnailInFlight = true;
        SystemServices.generateWallpaperThumbnail(
            next.sourcePath,
            next.cachePath,
            root.cacheRoot,
            root.thumbnailWidth,
            root.thumbnailHeight,
            root.thumbnailQuality
        );
    }

    function upsertWallpaper(record) {
        if (!record || !record.filePath)
            return;

        const filePath = String(record.filePath);
        const cachePath = String(record.cachePath || "");
        const cacheRevision = Number(record.mtime || 0);
        const cacheAvailable = !!record.cacheAvailable;
        const existingIndex = wallpaperIndexByPath[filePath];
        const modelItem = {
            filePath: filePath,
            fileName: String(record.fileName || filePath),
            cachePath: cachePath,
            thumbnailSource: cacheAvailable ? thumbnailUrl(cachePath, cacheRevision) : "",
            thumbnailReady: cacheAvailable,
            thumbnailRequested: cacheAvailable,
            cacheRevision: cacheRevision
        };

        if (existingIndex === undefined) {
            wallpaperIndexByPath[filePath] = allWallpapers.count;
            allWallpapers.append(modelItem);
        } else {
            allWallpapers.set(existingIndex, modelItem);
        }

        if (!cacheAvailable)
            enqueueThumbnail(filePath, cachePath);
    }

    function syncCurrentIndex() {
        if (root.effectiveActiveWallpaper === "")
            return;
        for (let i = 0; i < allWallpapers.count; i++) {
            if (allWallpapers.get(i).filePath === root.effectiveActiveWallpaper) {
                pathView.currentIndex = i;
                return;
            }
        }
    }

    function grabKeyboardFocus() {
        root.focus = true;
        root.forceActiveFocus();
    }

    function moveNext() {
        pathView.incrementCurrentIndex();
    }

    function movePrevious() {
        pathView.decrementCurrentIndex();
    }

    // ---- TYPE-TO-JUMP, AND WHY IT IS NOT A FILTER ----
    //
    // FORK: P2-8. This file's own `r` comment makes the case better than the
    // plan does — "with 362 images in the library this is the only way to
    // actually use most of them: h/l walks the list one thumbnail at a time
    // and nobody walks 362". `r` answered that for browsing. It cannot
    // answer "I want the one with 'forest' in the name".
    //
    // Phase 7 specifies a FILTER, and a filter is the wrong mechanism here,
    // for a reason specific to this panel rather than a preference:
    // `allWallpapers` is a ListModel that carries per-item thumbnail state —
    // `thumbnailReady`, `thumbnailSource`, `cacheRevision` — and
    // `wallpaperIndexByPath` maps a path to its INDEX in that model.
    // Rebuilding the model to show a subset invalidates every one of those
    // indices and throws away the generated-thumbnail bookkeeping, so a
    // filter would cost a re-scan on every keystroke.
    //
    // Type-to-jump moves the cursor instead and touches nothing. It is also
    // the right idiom for a PathView, which is a carousel — a filtered
    // carousel is a different component, not a smaller one — and it keeps
    // this panel's standing rule that navigation has no side effects and
    // Enter is the only key that writes.
    property bool searching: false
    property string searchQuery: ""
    property int searchMatches: 0

    function matchesQuery(index, needle) {
        if (index < 0 || index >= allWallpapers.count)
            return false;
        const entry = allWallpapers.get(index);
        const name = String(entry.fileName !== undefined ? entry.fileName : entry.filePath);
        return name.toLowerCase().indexOf(needle) >= 0;
    }

    // Counts matches AND jumps to the first one at or after `from`, wrapping.
    // Wrapping rather than stopping, because a carousel has no ends — the
    // cursor is already free to run off either side, so a search that stopped
    // dead would be the only thing in the panel that did.
    function jumpToMatch(from, forward) {
        const needle = root.searchQuery.trim().toLowerCase();
        if (needle === "") {
            root.searchMatches = 0;
            return;
        }

        const count = allWallpapers.count;
        let found = 0;
        for (let i = 0; i < count; i++)
            if (root.matchesQuery(i, needle))
                found++;
        root.searchMatches = found;
        if (found === 0)
            return;

        const step = forward ? 1 : -1;
        for (let n = 1; n <= count; n++) {
            const candidate = ((from + step * n) % count + count) % count;
            if (root.matchesQuery(candidate, needle)) {
                pathView.currentIndex = candidate;
                return;
            }
        }
    }

    function endSearch() {
        root.searching = false;
        root.searchQuery = "";
        root.searchMatches = 0;
    }

    Keys.onPressed: event => {
        // SEARCH MODE FIRST, and it has to be a separate branch rather than
        // extra cases below, because every navigation key in this panel is a
        // LETTER. `h`, `l`, `r` and `q` are all things you type into a
        // filename, so while a query is being typed the single-key bindings
        // must be off entirely — otherwise typing "roses" jumps randomly on
        // the `r` and walks the carousel on the `s`.
        //
        // Escape unwinds one level at a time — query first, panel second —
        // which is the behaviour Phase 7 specifies and the same unwinding
        // the control centre does for cursor -> drawer -> panel.
        if (root.searching) {
            if (event.key === Qt.Key_Escape) {
                root.endSearch();
                event.accepted = true;
                return;
            }
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                // Commit what the search landed on, and leave search mode.
                // Enter is still the only key in this panel that writes.
                if (allWallpapers.count > 0)
                    root.applyWallpaper(allWallpapers.get(pathView.currentIndex).filePath);
                root.endSearch();
                event.accepted = true;
                return;
            }
            if (event.key === Qt.Key_Backspace) {
                root.searchQuery = root.searchQuery.slice(0, -1);
                root.jumpToMatch(pathView.currentIndex - 1, true);
                event.accepted = true;
                return;
            }
            // n / N walk between matches without changing the query, which
            // is what makes a query with 30 hits usable at all.
            if (event.key === Qt.Key_Down) {
                root.jumpToMatch(pathView.currentIndex, true);
                event.accepted = true;
                return;
            }
            if (event.key === Qt.Key_Up) {
                root.jumpToMatch(pathView.currentIndex, false);
                event.accepted = true;
                return;
            }
            if (event.text && event.text.length === 1 && event.text >= " ") {
                root.searchQuery += event.text;
                // Search from the index BEFORE the cursor so the current
                // item can itself be the first match — otherwise refining a
                // query jumps off the very entry you were narrowing onto.
                root.jumpToMatch(pathView.currentIndex - 1, true);
                event.accepted = true;
                return;
            }
            return;
        }

        switch (event.key) {
        case Qt.Key_Slash:
            root.searching = true;
            root.searchQuery = "";
            root.searchMatches = 0;
            event.accepted = true;
            break;
        case Qt.Key_Escape:
            root.closeRequested();
            event.accepted = true;
            break;
        case Qt.Key_Right:
        case Qt.Key_L:
        case Qt.Key_Tab:
            root.moveNext();
            event.accepted = true;
            break;
        case Qt.Key_Left:
        case Qt.Key_H:
        case Qt.Key_Backtab:
            root.movePrevious();
            event.accepted = true;
            break;
        case Qt.Key_Return:
        case Qt.Key_Enter:
            if (allWallpapers.count > 0)
                root.applyWallpaper(allWallpapers.get(pathView.currentIndex).filePath);
            event.accepted = true;
            break;
        // FORK — `r` for a random wallpaper. With 362 images in the library
        // this is the only way to actually use most of them: h/l walks the
        // list one thumbnail at a time and nobody walks 362.
        //
        // It MOVES the cursor only. It used to apply as well, and that was
        // wrong for the reason the user gave when they asked for it changed:
        // "it should switch and go to wallpaper randomly but not select it".
        //
        // A random JUMP and a random COMMIT are different tools. The jump is
        // navigation — it is `l` pressed 200 times, and navigation in this
        // picker has never had a side effect. The commit is Enter, and it is
        // the only key that writes anything. Folding the two together meant
        // there was no way to browse the library at random: every look cost
        // a wallpaper change (and, through theme-apply, a palette change),
        // and getting back to where you started meant remembering where that
        // was. Now `r` re-rolls as many times as you like, Enter takes the
        // one you stopped on, and Escape leaves the wallpaper untouched.
        //
        // Re-rolls if the draw lands on the current index, which with a
        // library this size is rare and with a library of two is not —
        // and matters more now than it did, because a self-draw used to
        // still apply something and now would look like a dead key.
        case Qt.Key_R:
            if (allWallpapers.count > 1) {
                let next = pathView.currentIndex;
                while (next === pathView.currentIndex)
                    next = Math.floor(Math.random() * allWallpapers.count);
                pathView.currentIndex = next;
            }
            event.accepted = true;
            break;
        }
    }

    ListModel {
        id: allWallpapers
    }

    function applyWallpaper(filePath) {
        const targetPath = root.targetWallpaperPath;
        const commandText = root.customCommand.trim();
        const useCustomCommand = root.customCommandEnabled && commandText.length > 0;
        if (filePath === "")
            return;
        latestAppliedWallpaper = filePath;
        wallpaperApplied(filePath);
        closeAfterApply = true;
        if (applyProcess.running)
            applyProcess.running = false;
        if (customApplyProcess.running)
            customApplyProcess.running = false;
        if (useCustomCommand) {
            customApplyProcess.wallpaperPath = filePath;
            customApplyProcess.targetPath = targetPath;
            customApplyProcess.commandText = root.customCommand;
            customApplyProcess.running = true;
            return;
        }
        applyProcess.wallpaperPath = filePath;
        applyProcess.targetPath = targetPath;
        applyProcess.transitionType = configuredTransitionType;
        applyProcess.running = true;
    }

    Process {
        id: scanProcess
        command: ["python3", "-c", root.scanScript, root.cacheRoot, root.wallpaperDir, String(root.thumbnailWidth), String(root.thumbnailHeight), String(root.thumbnailQuality)]
        stdout: SplitParser {
            onRead: data => {
                if (!root.acceptingScanResults)
                    return;
                try {
                    root.upsertWallpaper(JSON.parse(data));
                } catch (error) {
                }
            }
        }
        onExited: {
            if (!root.acceptingScanResults)
                return;
            root.acceptingScanResults = false;
            root.wallpapersLoaded = true;
            root.syncCurrentIndex();
            root.startNextThumbnail();
        }
    }

    Connections {
        target: SystemServices

        function onWallpaperThumbnailFinished(sourcePath, finishedCachePath, cacheAvailable, updated, errorString) {
            if (sourcePath !== root.inFlightThumbnailSourcePath || finishedCachePath !== root.inFlightThumbnailCachePath)
                return;

            root.thumbnailInFlight = false;
            root.inFlightThumbnailSourcePath = "";
            root.inFlightThumbnailCachePath = "";

            if (root.showCondition && cacheAvailable && errorString === "") {
                const modelIndex = root.wallpaperIndexByPath[sourcePath];
                if (modelIndex !== undefined && modelIndex >= 0 && modelIndex < allWallpapers.count) {
                    const revision = Date.now();
                    allWallpapers.setProperty(modelIndex, "thumbnailReady", true);
                    allWallpapers.setProperty(modelIndex, "thumbnailRequested", true);
                    allWallpapers.setProperty(modelIndex, "thumbnailSource", root.thumbnailUrl(finishedCachePath, revision));
                    allWallpapers.setProperty(modelIndex, "cacheRevision", revision);
                }
            }

            root.startNextThumbnail();
        }
    }

    Process {
        id: applyProcess
        property string wallpaperPath: ""
        property string targetPath: ""
        property string transitionType: "center"
        command: [
            "python3", "-c", root.applyScript,
            wallpaperPath,
            targetPath,
            transitionType,
            String(root.transitionStep),
            String(root.transitionDuration),
            String(root.transitionFps),
            String(root.transitionAngle),
            root.transitionPosition,
            root.transitionBezier,
            root.transitionWave,
            root.transitionInvertY ? "true" : "false",
            root.pywalEnabled ? "true" : "false"
        ]
        onExited: function(exitCode) {
            running = false;
            if (exitCode === 0)
                root.wallpaperApplySucceeded(wallpaperPath);
            if (root.closeAfterApply) {
                root.closeAfterApply = false;
                root.closeRequested();
            }
        }
    }

    Process {
        id: customApplyProcess
        property string wallpaperPath: ""
        property string targetPath: ""
        property string commandText: ""
        command: [
            "bash", "-c", commandText,
            "tide-island-wallpaper",
            wallpaperPath,
            targetPath
        ]
        onExited: function(exitCode) {
            running = false;
            if (exitCode === 0)
                root.wallpaperApplySucceeded(wallpaperPath);
            if (root.closeAfterApply) {
                root.closeAfterApply = false;
                root.closeRequested();
            }
        }
    }

    //
    // FORK — the carousel is sized from the HEIGHT it is given, not from a
    // fifth of its width.
    //
    // The old chain was slotW = (width - 24) / 5, cardW = slotW * 1.15,
    // cardH = cardW * 0.58. Every number in it is horizontal, so the panel's
    // height never entered the calculation at all: on this 1012 x 239 panel
    // it produced a 227 x 132 hero card inside 217 px of usable vertical
    // space, and screenshotted that way — 159 px of delegate in 217, with an
    // ~47 px band of empty black under the labels. A picker whose entire job
    // is showing you a photograph was showing it a third smaller than the
    // shape it sits in allows.
    //
    // Turned around: the card fills the height, then takes its width from the
    // 0.58 aspect the thumbnails are generated at (640x360). That alone would
    // give 322 px of width, so there is a second limit — the one that keeps
    // all five cards on the panel.
    //
    // Where the width limit comes from. PathView distributes items over
    // pathLength / pathItemCount, NOT / (count - 1) — which is why the
    // measured gap between card centres was 190 and not the 237 that
    // `slotW * 1.20` reads like. With pathLength = 4 * spacing the interval
    // between card centres is 0.8 * spacing.
    //
    // ---- THE CARDS WERE OVERLAPPING, and that is what "too big" was ----
    //
    // `spacing` was `cardW * sideScale`, which ties the gap between cards to
    // how small the side cards are drawn. Those are unrelated quantities and
    // tying them together is what broke it:
    //
    //     interval  = 0.8 * spacing = 0.8 * 0.78 * cardW = 0.624 * cardW
    //     side card = sideScale * cardW                  = 0.780 * cardW
    //
    // The interval is SMALLER than the card, so every neighbour overlapped
    // its neighbour by 0.156 * cardW — a measured 47 px at the 301 px card
    // this panel was computing, with the left pair visibly sitting on top of
    // one another and the outermost card running under the capsule's clip.
    // The previous pass fixed the card being too SMALL for its panel and in
    // doing so drove it past the point where five of them still fit.
    //
    // So spacing is now derived from what it actually has to clear: a side
    // card plus a visible gap. Solving 0.8 * spacingFactor = sideScale + gap
    // for the factor gives (0.78 + 0.06) / 0.8 = 1.05.
    //
    // The outermost card's outer edge then sits at
    //     2 * interval + sideScale * cardW / 2
    //   = 2 * 0.84 * cardW + 0.39 * cardW
    //   = 2.07 * cardW
    // from the centre. Holding that under half the panel minus hPad is what
    // keeps the fifth card off the clip — the failure the theme picker was
    // caught in — and on this 1012-wide panel it is now the binding limit:
    // 238 px card, against the 307 the height alone would have allowed.
    //
    readonly property real topPad: Metrics.pad(14)
    readonly property real botPad: Metrics.pad(10)
    readonly property real hPad: Metrics.pad(12)
    readonly property real labelH: Metrics.px(24)
    readonly property real labelGap: Metrics.px(6)

    readonly property real sideScale: 0.78
    readonly property real cardAspect: 0.58

    // The clear gap between adjacent side cards, as a fraction of cardW.
    readonly property real cardGap: 0.06
    // 0.8 is PathView's interval-per-spacing for pathItemCount 5.
    readonly property real spacingFactor: (sideScale + cardGap) / 0.8
    readonly property real outerReach: 2 * (0.8 * spacingFactor) + sideScale / 2

    // The header's height is subtracted here rather than being allowed to
    // push the strip down. This panel is a FIXED 260 px (see the
    // wallpaper_picker case in mainCapsule.targetHeight), and cardW/cardH
    // are both derived from cardAreaH — so leaving the header out of this
    // sum does not overflow visibly, it silently pushes the bottom row of
    // filenames past the panel edge where the clip eats them.
    readonly property real headerH: Metrics.px(20)
    readonly property real headerGap: Metrics.px(6)
    readonly property real cardAreaH: height - topPad - botPad - headerH - headerGap
    readonly property real heightLimitedW: (cardAreaH - labelGap - labelH) / cardAspect
    readonly property real widthLimitedW: (width / 2 - hPad) / outerReach
    readonly property real cardW: Math.max(Metrics.px(120),
        Math.round(Math.min(heightLimitedW, widthLimitedW)))
    readonly property real cardH: Math.round(cardW * cardAspect)
    readonly property real spacing: cardW * spacingFactor

    readonly property real cardPathY: cardAreaH / 2

    // ── UI ────────────────────────────────────────────────────────────────────
    Column {
        anchors.fill: parent
        anchors.topMargin: root.topPad
        anchors.leftMargin: root.hPad
        anchors.rightMargin: root.hPad
        anchors.bottomMargin: root.botPad
        spacing: root.headerGap

        // ── Header, in ukishima's register, minus the kanji ────────────────
        //  The surface name in letterspaced uppercase, then a "· n" clause.
        //
        //  There WAS a 壁 ("wall") glyph in front of the label, carried over
        //  from ukishima, where every surface header opens with a kanji.
        //  Removed on request — it is the one piece of their identity that
        //  is theirs rather than a technique worth adapting, and this shell
        //  reads in one language. The letterspaced uppercase label is the
        //  part of that header doing the actual work, and it stays.
        Item {
            width: parent.width
            height: root.headerH

            Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: Metrics.px(8)

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "WALLPAPER"
                    color: Qt.rgba(1, 1, 1, 0.55)
                    font.family: root.textFontFamily
                    font.pixelSize: Metrics.font(9.5)
                    font.weight: Font.DemiBold
                    font.capitalization: Font.AllUppercase
                    font.letterSpacing: 1.6
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.wallpapersLoaded && allWallpapers.count > 0
                    // The position in the strip, which the filmstrip itself
                    // cannot show: five cards are visible out of however many
                    // there are, so "12 / 87" is the only thing on screen that
                    // says how far in you are.
                    text: "· " + (pathView.currentIndex + 1) + " / " + allWallpapers.count
                    color: Qt.rgba(1, 1, 1, 0.34)
                    font.family: root.textFontFamily
                    font.pixelSize: Metrics.font(9.5)
                    font.weight: Font.Medium
                }

                // FORK: the query, and the match count beside it.
                //
                // Both are load-bearing rather than decorative. A
                // type-to-jump search with nothing on screen is
                // indistinguishable from a stuck keyboard — the carousel
                // moves and you cannot tell why — and the COUNT is what
                // separates "no such wallpaper" from "you typo'd", which are
                // the two states a search is most often in.
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.searching
                    text: "/" + root.searchQuery
                          + (root.searchQuery === ""
                             ? ""
                             : "  " + root.searchMatches
                               + (root.searchMatches === 1 ? " match" : " matches"))
                    // Red on zero, so a query that matches nothing says so in
                    // the one place the eye is already reading.
                    color: root.searchQuery !== "" && root.searchMatches === 0
                        ? IslandTheme.danger
                        : IslandTheme.accent
                    font.family: root.textFontFamily
                    font.pixelSize: Metrics.font(9.5)
                    font.weight: Font.DemiBold
                }
            }
        }

        // ── Carousel ───────────────────────────────────────────────────────
        Item {
            width: parent.width
            height: root.cardAreaH

            // Empty state
            Column {
                anchors.centerIn: parent
                spacing: Metrics.px(8)
                visible: !root.wallpapersLoaded || allWallpapers.count === 0

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: !root.wallpapersLoaded ? "Scanning…" : "\uf03e"
                    font.pixelSize: !root.wallpapersLoaded ? 12 : 26
                    font.family: !root.wallpapersLoaded ? root.textFontFamily : root.iconFontFamily
                    color: Qt.rgba(1, 1, 1, 0.22)
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: root.wallpapersLoaded && allWallpapers.count === 0
                    text: "No wallpapers found\nin " + root.displayPath(root.wallpaperDir)
                    horizontalAlignment: Text.AlignHCenter
                    color: Qt.rgba(1, 1, 1, 0.22)
                    font.pixelSize: Metrics.font(11)
                    font.family: root.textFontFamily
                    lineHeight: 1.5
                }
            }

            PathView {
                id: pathView
                anchors.fill: parent
                model: root.showCondition ? allWallpapers : null
                visible: allWallpapers.count > 0
                clip: false

                pathItemCount: Math.min(allWallpapers.count, 5)
                cacheItemCount: 4
                snapMode: PathView.SnapToItem
                preferredHighlightBegin: 0.5
                preferredHighlightEnd: 0.5
                highlightRangeMode: PathView.StrictlyEnforceRange
                highlightMoveDuration: 200

                path: Path {
                    startX: pathView.width / 2 - root.spacing * 2
                    startY: root.cardPathY
                    PathLine {
                        x: pathView.width / 2 + root.spacing * 2
                        y: root.cardPathY
                    }
                }

                delegate: Item {
                    id: del
                    readonly property bool isCurrent: PathView.isCurrentItem
                    readonly property bool onPath: PathView.onPath

                    width: root.cardW
                    height: root.cardH + root.labelGap + root.labelH
                    z: isCurrent ? 3 : 1

                    property real sc: isCurrent ? 1.0 : onPath ? root.sideScale : 0.0
                    Behavior on sc {
                        NumberAnimation {
                            duration: 200
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Motion.spring()   // FORK: was Easing.OutCubic
                        }
                    }

                    property real op: isCurrent ? 1.0 : onPath ? 0.65 : 0.0
                    Behavior on op {
                        NumberAnimation {
                            duration: 180
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Motion.fade()   // FORK: was Easing.OutCubic
                        }
                    }

                    Item {
                        id: inner
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: parent.top
                        width: root.cardW
                        height: root.cardH + root.labelGap + root.labelH
                        scale: del.sc
                        opacity: del.op
                        transformOrigin: Item.Center

                        // Clipped image
                        ClippingRectangle {
                            id: thumb
                            anchors.top: parent.top
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: root.cardW
                            height: root.cardH
                            radius: Metrics.px(14)
                            color: IslandTheme.surfaceSunken
                            antialiasing: false

                            // ---- THE NEIGHBOURS DESATURATE ----
                            //
                            // Scale and opacity alone were already here, and
                            // they were not enough: five photographs at 0.65
                            // opacity are still five photographs, all
                            // competing at full chroma, and the eye has to be
                            // told which one is selected instead of seeing
                            // it. ukishima's strip shrinks, dims AND
                            // desaturates the neighbours, which is what makes
                            // it read as depth rather than as a row.
                            //
                            // MultiEffect and not an overlaid grey veil: a
                            // veil lightens as well as greys and turns a dark
                            // wallpaper into a milky one, which is the
                            // opposite of receding.
                            layer.enabled: true
                            layer.effect: MultiEffect {
                                saturation: del.isCurrent ? 0.0 : -0.72
                                Behavior on saturation {
                                    NumberAnimation {
                                        duration: 200
                                        easing.type: Easing.BezierSpline
                                        easing.bezierCurve: Motion.fade()
                                    }
                                }
                            }

                            Image {
                                anchors.fill: parent
                                source: root.showCondition && model.thumbnailSource ? model.thumbnailSource : ""
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                cache: false
                                smooth: true
                                mipmap: false
                                sourceSize: Qt.size(root.cardW * 2, root.cardH * 2)

                                Rectangle {
                                    anchors.fill: parent
                                    color: IslandTheme.surfaceRaised
                                    opacity: parent.status === Image.Ready ? 0 : 1
                                    Behavior on opacity {
                                        NumberAnimation {
                                            duration: 200
                                        }
                                    }
                                }
                            }
                        }

                        // Border overlay
                        Rectangle {
                            anchors.top: parent.top
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: root.cardW
                            height: root.cardH
                            radius: Metrics.px(14)
                            color: "transparent"
                            border.width: (model.filePath === root.effectiveActiveWallpaper) ? 2.5 : 0
                            border.color: IslandTheme.accent
                            Behavior on border.width {
                                NumberAnimation {
                                    duration: 150
                                }
                            }

                        }

                        // Click area
                        MouseArea {
                            anchors.top: parent.top
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: root.cardW
                            height: root.cardH
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (del.isCurrent)
                                    root.applyWallpaper(model.filePath);
                                else
                                    pathView.currentIndex = index;
                            }
                        }

                        // Filename label
                        Text {
                            anchors.top: thumb.bottom
                            anchors.topMargin: root.labelGap
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: root.cardW - 4
                            text: model.fileName
                            color: del.isCurrent ? "white" : Qt.rgba(1, 1, 1, 0.50)
                            font.pixelSize: del.isCurrent ? 11 : 10
                            font.family: root.textFontFamily
                            font.weight: del.isCurrent ? Font.Medium : Font.Normal
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideMiddle
                            Behavior on color {
                                ColorAnimation {
                                    duration: 150
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
