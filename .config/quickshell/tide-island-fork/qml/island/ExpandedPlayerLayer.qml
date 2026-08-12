import QtQuick
import IslandBackend
import Quickshell.Services.Mpris
import "../controlcenter"

// FORK: one shared scale factor for every island surface.
import "../common/Metrics.js" as Metrics
// FORK: the shared motion system — one spring for geometry, one
// critically damped curve for opacity. See qml/common/Motion.js.
import "../common/Motion.js" as Motion

Item {
    id: root

    signal controlPressed()
    signal backgroundClicked()
    signal keyboardFocusRequested()
    signal keyboardFocusReleased()
    signal previousRequested()
    signal timerToggleRequested(int hours, int minutes)
    signal timerResetRequested()
    signal timerDurationRequested(int hours, int minutes)

    readonly property var userConfig: UserConfig

    property bool showCondition: false
    property string currentArtUrl: ""
    property string currentTrack: ""
    property string currentArtist: ""
    property string timePlayed: "0:00"
    property string timeTotal: "0:00"
    property real trackProgress: 0
    property var activePlayer: null
    property string iconFontFamily: userConfig.iconFontFamily
    property string textFontFamily: userConfig.textFontFamily
    property int timerSelectedHours: 0
    property int timerSelectedMinutes: 5
    property int timerTotalSeconds: 300
    property int timerRemainingSeconds: 0
    property bool timerRunning: false
    property bool timerActive: false
    property real visualizerPhase: 0
    property int currentPage: 0
    property int pendingPage: -1
    readonly property int pageCount: 2
    property real pageProgress: 0
    readonly property real clampedPageProgress: Math.max(0, Math.min(1, pageProgress))
    readonly property real pageSlideDistance: Math.max(1, viewport.width + 24)

    readonly property bool isPlaying: activePlayer && activePlayer.playbackState === MprisPlaybackState.Playing

    // FORK — the album line the spec asks for, taken straight off the player
    // rather than plumbed through DynamicIslandWindow: `activePlayer` is
    // already handed to this layer, and MprisPlayer publishes trackAlbum next
    // to the title and artist this card was already drawing.
    readonly property string currentAlbum: activePlayer && activePlayer.trackAlbum
        ? String(activePlayer.trackAlbum) : ""

    //
    // FORK — the media card's own measurements, and the one number it
    // publishes upwards.
    //
    // DESIGN-SPEC.md's media card is "88 px album art · bold two-line title ·
    // album and artist underneath · transport controls". The art was 60 in
    // source and Metrics.px(60) = 55 on screen — a third of the size the
    // design calls for, on the one element of the card that is a picture.
    //
    // artSize is a min() and not the flat Metrics.px(88) on purpose. The
    // capsule's height for `expanded` is a literal in DynamicIslandWindow.qml
    // (Metrics.px(190) = 175) and that file is not this pass's to edit, so a
    // flat 81 would draw a card 20 px taller than the shape holding it and
    // the capsule's own `clip: true` would eat the transport row — exactly
    // the failure the old comment on that literal records happening at 122.
    // Clamping instead means the card is right at whatever height it is
    // given: 67 px of art today, 81 the moment the capsule reads
    // preferredHeight below, and never a row cut off in between.
    //
    readonly property real cardMargin: Metrics.pad(18)
    readonly property real rowGap: Metrics.px(12)
    readonly property real scrubberHeight: Metrics.px(18)
    readonly property real transportHeight: Metrics.px(36)
    readonly property real chromeHeight: cardMargin * 2 + rowGap * 2
        + scrubberHeight + transportHeight
    readonly property real desiredArtSize: Metrics.px(88)
    readonly property real artSize: Math.max(Metrics.px(52),
        Math.min(desiredArtSize, height - chromeHeight))
    readonly property real preferredHeight: chromeHeight + desiredArtSize

    function visualizerLevel(index) {
        const phase = visualizerPhase + index * 0.78;
        const primary = (Math.sin(phase) + 1) * 0.5;
        const secondary = (Math.sin(phase * 2 + index * 0.95) + 1) * 0.5;
        return 0.22 + primary * 0.42 + secondary * 0.24;
    }

    function pausedVisualizerLevel(index) {
        const levels = [0.34, 0.58, 0.82, 0.58, 0.34];
        return levels[index] || 0.4;
    }

    function togglePlayback() {
        if (!activePlayer || !activePlayer.canControl) return;

        if (activePlayer.canTogglePlaying) {
            activePlayer.togglePlaying();
            return;
        }

        if (activePlayer.playbackState === MprisPlaybackState.Playing) {
            if (activePlayer.canPause) activePlayer.pause();
            return;
        }

        if (activePlayer.canPlay) activePlayer.play();
    }

    function showPage(page) {
        settlePage(page);
    }

    function settlePage(page) {
        const targetPage = Math.max(0, Math.min(pageCount - 1, page));
        pendingPage = -1;
        pageSettleAnimation.stop();
        pageStrip.interactive = false;
        pendingPage = targetPage;
        pageSettleAnimation.startProgress = clampedPageProgress;
        pageSettleAnimation.endProgress = targetPage;

        if (Math.abs(clampedPageProgress - targetPage) < 0.001) {
            pageProgress = targetPage;
            finishPageSettle();
            return;
        }

        pageSettleAnimation.restart();
    }

    function finishPageSettle() {
        if (pendingPage < 0)
            return;

        currentPage = pendingPage;
        pendingPage = -1;
        pageProgress = currentPage;
        updateKeyboardFocusForPage();
    }

    function updateKeyboardFocusForPage() {
        if (showCondition && currentPage === 1)
            keyboardFocusRequested();
        else
            keyboardFocusReleased();
    }

    function grabKeyboardFocus() {
        if (currentPage === 1 && timerPage.grabKeyboardFocus)
            timerPage.grabKeyboardFocus();
    }

    function openTimerPage() {
        showPage(1);
    }

    anchors.fill: parent
    opacity: showCondition ? 1 : 0

    onShowConditionChanged: {
        if (!showCondition) {
            pendingPage = -1;
            pageSettleAnimation.stop();
            currentPage = 0;
            pageProgress = 0;
        }
        updateKeyboardFocusForPage();
    }

    // FORK: one choreography for every layer in the shell.
    // Was `showCondition ? 300 : 100` on Easing.InOutQuad — one of
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

    SequentialAnimation {
        id: pageSettleAnimation

        property real startProgress: 0
        property real endProgress: 0

        NumberAnimation {
            target: root
            property: "pageProgress"
            from: pageSettleAnimation.startProgress
            to: pageSettleAnimation.endProgress
            duration: 220
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Motion.spring()   // FORK: was Easing.OutCubic
        }

        ScriptAction {
            script: root.finishPageSettle()
        }
    }

    Timer {
        interval: 64
        repeat: true
        running: showCondition && isPlaying && currentPage === 0
        onTriggered: {
            visualizerPhase += 0.18;
            if (visualizerPhase > Math.PI * 2) visualizerPhase -= Math.PI * 2;
        }
    }

    Item {
        id: viewport

        anchors.fill: parent
        clip: true

        MouseArea {
            id: pageSwipeArea

            anchors.fill: parent
            z: 0
            acceptedButtons: Qt.LeftButton
            preventStealing: false

            property real startX: 0
            property int startPage: 0
            property real startProgress: 0
            property bool moved: false

            onPressed: (mouse) => {
                root.pendingPage = -1;
                pageSettleAnimation.stop();
                startX = mouse.x;
                startPage = root.currentPage;
                startProgress = root.clampedPageProgress;
                moved = false;
                pageStrip.interactive = true;
                root.pageProgress = startProgress;
                mouse.accepted = true;
            }

            onPositionChanged: (mouse) => {
                if (!pressed || viewport.width <= 0)
                    return;

                const deltaX = mouse.x - startX;
                root.pageProgress = Math.max(0, Math.min(1, startProgress + deltaX / root.pageSlideDistance));
                moved = moved || Math.abs(deltaX) > 8;
            }

            onReleased: {
                if (!moved || viewport.width <= 0) {
                    root.settlePage(startPage);
                    return;
                }

                const progress = root.clampedPageProgress;
                let targetPage = startPage;

                if (startPage === 0 && progress > 0.22)
                    targetPage = 1;
                else if (startPage === 1 && progress < 0.78)
                    targetPage = 0;

                root.settlePage(targetPage);
            }

            onCanceled: root.settlePage(startPage)
            onClicked: if (!moved) root.backgroundClicked()
        }

        Item {
            id: pageStrip

            z: 1
            property bool interactive: false

            width: viewport.width
            height: viewport.height
            x: 0

            onWidthChanged: {
                if (!interactive && !pageSettleAnimation.running)
                    root.pageProgress = root.currentPage;
            }

            Item {
                id: musicPage

                width: viewport.width
                height: viewport.height
                x: root.clampedPageProgress * root.pageSlideDistance
                opacity: 1 - root.clampedPageProgress
                enabled: opacity > 0.001

                Column {
                    anchors.fill: parent
                    anchors.margins: root.cardMargin
                    spacing: root.rowGap

                    Item {
                        id: headerRow
                        width: parent.width
                        height: root.artSize

                        Row {
                            id: artRow
                            anchors.left: parent.left
                            anchors.right: eqBlock.left
                            anchors.rightMargin: Metrics.px(10)
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Metrics.px(14)

                            Rectangle {
                                width: root.artSize
                                height: root.artSize
                                // Radius tracks the art rather than sitting at
                                // a literal 14: the same corner on a 55 px
                                // square and an 81 px one are different shapes.
                                radius: Math.round(root.artSize * 0.22)
                                color: "#2c2c2e"
                                clip: true

                                Image {
                                    anchors.fill: parent
                                    source: currentArtUrl
                                    fillMode: Image.PreserveAspectCrop
                                    visible: source.toString() !== ""
                                    // Was a flat 120 — half the pixels the art
                                    // now asks for on a hidpi-ish redraw.
                                    sourceSize: Qt.size(root.artSize * 2, root.artSize * 2)
                                }
                            }

                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - root.artSize - artRow.spacing
                                spacing: Metrics.px(3)

                                // Two lines, per the spec, and wrapped rather
                                // than elided on the first: a single elided
                                // line of a long title is the half of the card
                                // that says what is playing.
                                Text {
                                    width: parent.width
                                    text: currentTrack
                                    color: "white"
                                    font.pixelSize: Metrics.font(userConfig.bodyFontSize + 2)
                                    font.family: textFontFamily
                                    font.weight: Font.DemiBold
                                    font.letterSpacing: -0.15
                                    wrapMode: Text.WordWrap
                                    maximumLineCount: 2
                                    elide: Text.ElideRight
                                    lineHeight: 1.15
                                }

                                Text {
                                    width: parent.width
                                    text: currentArtist
                                    color: "#8e8e93"
                                    font.pixelSize: Metrics.font(userConfig.bodyFontSize - 1)
                                    font.family: textFontFamily
                                    font.weight: Font.Medium
                                    elide: Text.ElideRight
                                }

                                Text {
                                    width: parent.width
                                    visible: root.currentAlbum !== ""
                                             && root.currentAlbum !== currentTrack
                                    text: root.currentAlbum
                                    color: "#6e6e73"
                                    font.pixelSize: Metrics.font(userConfig.bodyFontSize - 1)
                                    font.family: textFontFamily
                                    font.weight: Font.Normal
                                    elide: Text.ElideRight
                                }
                            }
                        }

                        Item {
                            id: eqBlock
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            width: Metrics.px(44)
                            height: Metrics.px(22)

                            Row {
                                anchors.centerIn: parent
                                height: parent.height
                                spacing: Metrics.px(4)

                                Repeater {
                                    model: 5

                                    delegate: Rectangle {
                                        width: Metrics.px(4)
                                        height: isPlaying
                                            ? 6 + (parent.height - 6) * visualizerLevel(index)
                                            : 6 + (parent.height - 6) * pausedVisualizerLevel(index)
                                        radius: Metrics.px(2)
                                        color: isPlaying ? "#b56cff" : "#5f4b72"
                                        anchors.verticalCenter: parent.verticalCenter

                                        Behavior on height {
                                            NumberAnimation {
                                                duration: isPlaying ? 120 : 260
                                                easing.type: Easing.BezierSpline
                                                easing.bezierCurve: Motion.spring()   // FORK: was Easing.InOutQuad
                                            }
                                        }

                                        Behavior on color {
                                            ColorAnimation {
                                                duration: isPlaying ? 140 : 280
                                                easing.type: Easing.BezierSpline
                                                easing.bezierCurve: Motion.fade()   // FORK: was Easing.InOutQuad
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Item {
                        width: parent.width
                        height: root.scrubberHeight

                        // FORK: was `bodyFontSize - Metrics.px(4)` = 8 px.
                        // These two labels bypassed Metrics.font(), so the 9 px
                        // floor never saw them and they rendered a full size
                        // below anything else on the card. 10 px, and through
                        // font() this time, so the floor applies.
                        Text {
                            id: timeL
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: timePlayed
                            color: "#8e8e93"
                            font.pixelSize: Metrics.font(userConfig.bodyFontSize - 2)
                            font.family: textFontFamily
                            font.weight: Font.Medium
                        }

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: timeL.right
                            anchors.right: timeR.left
                            anchors.margins: Metrics.pad(12)
                            height: Metrics.px(6)
                            radius: Metrics.px(3)
                            color: "#333333"

                            // FORK: the fill animates its PROGRESS, not its
                            // width, and it does so on the critically damped
                            // curve rather than the spring. Two separate bugs
                            // shared one Behavior.
                            //
                            // 1. The spring overshoots ~1.54% of the travel by
                            //    construction (Motion.overshoot()). This width
                            //    is `parent.width * trackProgress` with
                            //    trackProgress clamped 0..1, so it is the
                            //    slider case Motion.js's own header already
                            //    calls out: at the end of a track the fill is
                            //    drawn ~1.5% wider than the grey track behind
                            //    it, white spilling past a rounded end cap,
                            //    for the ~100 ms the peak lasts. The header
                            //    lists `animatedProgress` under fade for
                            //    exactly this reason; the timer ring 230 lines
                            //    down this same file already does it right.
                            //
                            // 2. Worse, and the reason this is a motion bug
                            //    and not a pedantry: `parent.width` is not
                            //    constant. The player lives inside mainCapsule
                            //    and the capsule morphs from 156 px to its
                            //    expanded width when the panel opens
                            //    (measured with grim). A Behavior on `width`
                            //    cannot distinguish "the song advanced one
                            //    second" from "the container just grew 400 px"
                            //    — so every open ran a 500 ms animation on the
                            //    fill that was chasing the capsule instead of
                            //    riding inside it. Same failure as the icon
                            //    strip's Behavior on x, which was removed for
                            //    it two commits ago.
                            //
                            // Moving the Behavior onto the 0..1 lets the
                            // parent.width term pass through untouched, so the
                            // fill scales with the capsule frame-for-frame and
                            // only genuine progress changes animate.
                            //
                            // 500 ms is kept. mpris position updates land
                            // roughly once a second, so the animation has to
                            // occupy a good fraction of the gap or the bar
                            // ticks; the timer ring uses 700 for the same
                            // reason and is fed at the same rate.
                            Rectangle {
                                id: trackFill

                                property real animatedTrackProgress: root.trackProgress

                                Behavior on animatedTrackProgress {
                                    NumberAnimation {
                                        duration: 500
                                        easing.type: Easing.BezierSpline
                                        easing.bezierCurve: Motion.fade()
                                    }
                                }

                                height: parent.height
                                radius: Metrics.px(3)
                                color: "white"
                                width: parent.width * trackFill.animatedTrackProgress
                            }
                        }

                        Text {
                            id: timeR
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: timeTotal
                            color: "#8e8e93"
                            font.pixelSize: Metrics.font(userConfig.bodyFontSize - 2)
                            font.family: textFontFamily
                            font.weight: Font.Medium
                        }
                    }

                    Item {
                        width: parent.width
                        height: root.transportHeight

                        Row {
                            anchors.centerIn: parent
                            spacing: Metrics.px(50)

                            Item {
                                width: Metrics.px(28)
                                height: Metrics.px(28)
                                scale: prevArea.pressed ? 0.8 : 1.0

                                Behavior on scale {
                                    NumberAnimation { duration: 100 }
                                }

                                Canvas {
                                    anchors.fill: parent
                                    property color fillColor: prevArea.pressed ? "#888" : "white"

                                    onFillColorChanged: requestPaint()
                                    onPaint: {
                                        var ctx = getContext("2d");
                                        ctx.clearRect(0, 0, width, height);
                                        ctx.fillStyle = fillColor;
                                        ctx.strokeStyle = fillColor;
                                        ctx.lineJoin = "round";
                                        ctx.lineWidth = 2;
                                        ctx.beginPath();
                                        ctx.rect(3, 5, 3, 18);
                                        ctx.moveTo(14, 5);
                                        ctx.lineTo(6, 14);
                                        ctx.lineTo(14, 23);
                                        ctx.closePath();
                                        ctx.moveTo(23, 5);
                                        ctx.lineTo(15, 14);
                                        ctx.lineTo(23, 23);
                                        ctx.closePath();
                                        ctx.fill();
                                        ctx.stroke();
                                    }
                                }

                                MouseArea {
                                    id: prevArea
                                    anchors.fill: parent
                                    anchors.margins: Metrics.pad(-15)
                                    preventStealing: true
                                    onPressed: (mouse) => {
                                        controlPressed();
                                        mouse.accepted = true;
                                    }
                                    onClicked: root.previousRequested()
                                }
                            }

                            Item {
                                width: Metrics.px(28)
                                height: Metrics.px(28)
                                scale: playArea.pressed ? 0.8 : 1.0

                                Behavior on scale {
                                    NumberAnimation { duration: 100 }
                                }

                                Row {
                                    anchors.centerIn: parent
                                    spacing: Metrics.px(6)
                                    visible: activePlayer && activePlayer.playbackState === MprisPlaybackState.Playing

                                    Rectangle { width: 6; height: 20; radius: 2; color: playArea.pressed ? "#888" : "white" }
                                    Rectangle { width: 6; height: 20; radius: 2; color: playArea.pressed ? "#888" : "white" }
                                }

                                Canvas {
                                    anchors.fill: parent
                                    visible: !activePlayer || activePlayer.playbackState !== MprisPlaybackState.Playing
                                    property color fillColor: playArea.pressed ? "#888" : "white"

                                    onFillColorChanged: requestPaint()
                                    onPaint: {
                                        var ctx = getContext("2d");
                                        ctx.clearRect(0, 0, width, height);
                                        ctx.fillStyle = fillColor;
                                        ctx.strokeStyle = fillColor;
                                        ctx.lineJoin = "round";
                                        ctx.lineWidth = 2;
                                        ctx.beginPath();
                                        ctx.moveTo(8, 4);
                                        ctx.lineTo(24, 14);
                                        ctx.lineTo(8, 24);
                                        ctx.closePath();
                                        ctx.fill();
                                        ctx.stroke();
                                    }
                                }

                                MouseArea {
                                    id: playArea
                                    anchors.fill: parent
                                    anchors.margins: Metrics.pad(-15)
                                    preventStealing: true
                                    onPressed: (mouse) => {
                                        controlPressed();
                                        mouse.accepted = true;
                                    }
                                    onClicked: togglePlayback()
                                }
                            }

                            Item {
                                width: Metrics.px(28)
                                height: Metrics.px(28)
                                scale: nextArea.pressed ? 0.8 : 1.0

                                Behavior on scale {
                                    NumberAnimation { duration: 100 }
                                }

                                Canvas {
                                    anchors.fill: parent
                                    property color fillColor: nextArea.pressed ? "#888" : "white"

                                    onFillColorChanged: requestPaint()
                                    onPaint: {
                                        var ctx = getContext("2d");
                                        ctx.clearRect(0, 0, width, height);
                                        ctx.fillStyle = fillColor;
                                        ctx.strokeStyle = fillColor;
                                        ctx.lineJoin = "round";
                                        ctx.lineWidth = 2;
                                        ctx.beginPath();
                                        ctx.moveTo(5, 5);
                                        ctx.lineTo(13, 14);
                                        ctx.lineTo(5, 23);
                                        ctx.closePath();
                                        ctx.moveTo(14, 5);
                                        ctx.lineTo(22, 14);
                                        ctx.lineTo(14, 23);
                                        ctx.closePath();
                                        ctx.rect(22, 5, 3, 18);
                                        ctx.fill();
                                        ctx.stroke();
                                    }
                                }

                                MouseArea {
                                    id: nextArea
                                    anchors.fill: parent
                                    anchors.margins: Metrics.pad(-15)
                                    preventStealing: true
                                    onPressed: (mouse) => {
                                        controlPressed();
                                        mouse.accepted = true;
                                    }
                                    onClicked: if (activePlayer) activePlayer.next()
                                }
                            }
                        }
                    }
                }
            }

            TimerPage {
                id: timerPage

                x: -(1 - root.clampedPageProgress) * root.pageSlideDistance
                width: viewport.width
                height: viewport.height
                opacity: root.clampedPageProgress
                enabled: opacity > 0.001
                textFontFamily: root.textFontFamily
                timerSelectedHours: root.timerSelectedHours
                timerSelectedMinutes: root.timerSelectedMinutes
                timerTotalSeconds: root.timerTotalSeconds
                timerRemainingSeconds: root.timerRemainingSeconds
                timerRunning: root.timerRunning
                timerActive: root.timerActive
                onControlPressed: root.controlPressed()
                onKeyboardFocusRequested: root.keyboardFocusRequested()
                onTimerToggleRequested: function(hours, minutes) {
                    root.timerToggleRequested(hours, minutes);
                }
                onTimerResetRequested: root.timerResetRequested()
                onTimerDurationRequested: function(hours, minutes) {
                    root.timerDurationRequested(hours, minutes);
                }
            }
        }
    }

    component TimerPage: Item {
        id: timerRoot

        signal controlPressed()
        signal keyboardFocusRequested()
        signal timerToggleRequested(int hours, int minutes)
        signal timerResetRequested()
        signal timerDurationRequested(int hours, int minutes)

        readonly property var userConfig: UserConfig

        property string textFontFamily: userConfig.textFontFamily
        property int timerSelectedHours: 0
        property int timerSelectedMinutes: 5
        property int timerTotalSeconds: 300
        property int timerRemainingSeconds: 0
        property bool timerRunning: false
        property bool timerActive: false
        property real animatedProgress: 0
        property string focusTarget: "hour"

        readonly property int displaySeconds: timerActive ? timerRemainingSeconds : 0
        readonly property real targetProgress: timerActive && timerTotalSeconds > 0 ? timerRemainingSeconds / timerTotalSeconds : 0
        readonly property bool canStart: inputTotalSeconds() > 0 && (!timerActive || timerRemainingSeconds > 0)
        readonly property string timeText: {
            const hours = Math.floor(displaySeconds / 3600);
            const minutes = Math.floor((displaySeconds % 3600) / 60);
            const seconds = displaySeconds % 60;
            const minuteText = minutes < 10 ? "0" + minutes : "" + minutes;
            const secondText = seconds < 10 ? "0" + seconds : "" + seconds;

            if (hours > 0)
                return hours + ":" + minuteText + ":" + secondText;
            return minuteText + ":" + secondText;
        }

        function clampInt(value, minValue, maxValue) {
            const parsed = parseInt(value, 10);
            if (isNaN(parsed)) return minValue;
            return Math.max(minValue, Math.min(maxValue, parsed));
        }

        function inputHours() {
            return clampInt(hourInput.text, 0, 23);
        }

        function inputMinutes() {
            return clampInt(minuteInput.text, 0, 59);
        }

        function inputTotalSeconds() {
            return inputHours() * 3600 + inputMinutes() * 60;
        }

        function syncDurationFromInputs() {
            timerDurationRequested(inputHours(), inputMinutes());
            progressRing.requestPaint();
        }

        function normalizeInputs() {
            hourInput.text = "" + timerSelectedHours;
            minuteInput.text = timerSelectedMinutes < 10 ? "0" + timerSelectedMinutes : "" + timerSelectedMinutes;
        }

        function resetTimer() {
            timerResetRequested();
            progressRing.requestPaint();
        }

        function toggleTimer() {
            timerToggleRequested(inputHours(), inputMinutes());
        }

        function grabKeyboardFocus() {
            if (focusTarget === "minute")
                minuteInput.grabKeyboardFocus();
            else
                hourInput.grabKeyboardFocus();
        }

        onTargetProgressChanged: animatedProgress = targetProgress
        onAnimatedProgressChanged: progressRing.requestPaint()
        onTimerSelectedHoursChanged: normalizeInputs()
        onTimerSelectedMinutesChanged: normalizeInputs()
        Component.onCompleted: normalizeInputs()

        Behavior on animatedProgress {
            NumberAnimation {
                duration: 700
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Motion.fade()   // FORK: was Easing.InOutCubic
            }
        }

        Row {
            anchors.fill: parent
            anchors.leftMargin: Metrics.pad(8)
            anchors.rightMargin: Metrics.pad(8)
            spacing: Metrics.px(18)

            Item {
                width: Metrics.px(116)
                height: parent.height

                Canvas {
                    id: progressRing

                    anchors.centerIn: parent
                    width: Metrics.px(104)
                    height: Metrics.px(104)

                    onPaint: {
                        const ctx = getContext("2d");
                        const centerX = width / 2;
                        const centerY = height / 2;
                        const lineWidth = 5;
                        const radius = Math.min(width, height) / 2 - lineWidth / 2;
                        const startAngle = -Math.PI / 2;
                        const progress = Math.max(0, Math.min(1, timerRoot.animatedProgress));
                        const endAngle = startAngle - Math.PI * 2 * progress;

                        ctx.clearRect(0, 0, width, height);
                        ctx.lineCap = "round";
                        ctx.lineWidth = lineWidth;

                        ctx.beginPath();
                        ctx.strokeStyle = "#2b2e35";
                        ctx.arc(centerX, centerY, radius, 0, Math.PI * 2);
                        ctx.stroke();

                        if (progress > 0) {
                            ctx.beginPath();
                            ctx.strokeStyle = "#ff9f0a";
                            ctx.arc(centerX, centerY, radius, startAngle, endAngle, true);
                            ctx.stroke();
                        }
                    }
                }

                Text {
                    anchors.centerIn: progressRing
                    text: timerRoot.timeText
                    color: "#ffffff"
                    font.pixelSize: timerRoot.displaySeconds >= 3600 ? timerRoot.userConfig.bodyFontSize + Metrics.px(2) : timerRoot.userConfig.bodyFontSize + Metrics.px(8)
                    font.family: timerRoot.textFontFamily
                    font.weight: Font.DemiBold
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }

            Column {
                width: parent.width - 173
                anchors.verticalCenter: parent.verticalCenter
                spacing: Metrics.px(10)

                Row {
                    width: parent.width
                    height: Metrics.px(42)
                    spacing: Metrics.px(8)

                    TimerInput {
                        id: hourInput

                        width: (parent.width - 8) / 2
                        height: parent.height
                        label: "时"
                        text: "0"
                        textFontFamily: timerRoot.textFontFamily
                        onKeyboardFocusRequested: {
                            timerRoot.focusTarget = "hour";
                            timerRoot.keyboardFocusRequested();
                        }
                        onEditingFinished: {
                            timerRoot.syncDurationFromInputs();
                            timerRoot.normalizeInputs();
                        }
                    }

                    TimerInput {
                        id: minuteInput

                        width: (parent.width - 8) / 2
                        height: parent.height
                        label: "分"
                        text: "05"
                        textFontFamily: timerRoot.textFontFamily
                        onKeyboardFocusRequested: {
                            timerRoot.focusTarget = "minute";
                            timerRoot.keyboardFocusRequested();
                        }
                        onEditingFinished: {
                            timerRoot.syncDurationFromInputs();
                            timerRoot.normalizeInputs();
                        }
                    }
                }

                Row {
                    width: parent.width
                    height: Metrics.px(34)
                    spacing: Metrics.px(8)

                    TimerButton {
                        width: (parent.width - 8) / 2
                        height: parent.height
                        label: timerRoot.timerRunning ? "Stop" : (timerRoot.timerActive && timerRoot.timerRemainingSeconds < timerRoot.timerTotalSeconds && timerRoot.timerRemainingSeconds > 0 ? "Continue" : "Start")
                        enabled: timerRoot.timerRunning || timerRoot.canStart
                        accent: true
                        textFontFamily: timerRoot.textFontFamily
                        onClicked: timerRoot.toggleTimer()
                        onPressed: timerRoot.controlPressed()
                    }

                    TimerButton {
                        width: (parent.width - 8) / 2
                        height: parent.height
                        label: "Reset"
                        textFontFamily: timerRoot.textFontFamily
                        onClicked: timerRoot.resetTimer()
                        onPressed: timerRoot.controlPressed()
                    }
                }
            }
        }
    }

    component TimerInput: Item {
        id: inputRoot

        signal editingFinished()
        signal keyboardFocusRequested()

        property alias text: input.text
        property string label: ""
        property string textFontFamily: ""
        property int focusAttempts: 0

        function grabKeyboardFocus() {
            inputRoot.keyboardFocusRequested();
            focusAttempts = 4;
            input.forceActiveFocus();
            input.selectAll();
            focusRetryTimer.restart();
        }

        Timer {
            id: focusRetryTimer

            interval: 16
            repeat: true
            onTriggered: {
                input.forceActiveFocus();
                input.selectAll();
                inputRoot.focusAttempts -= 1;
                if (inputRoot.focusAttempts <= 0)
                    stop();
            }
        }

        Item {
            anchors.fill: parent

            MatteSurface {
                anchors.fill: parent
                radius: Metrics.px(10)
                hovered: input.activeFocus || inputMouseArea.containsMouse
                pressed: inputMouseArea.pressed
            }

            Rectangle {
                anchors.fill: parent
                anchors.margins: 1
                radius: Metrics.px(9)
                color: StyleTokens.transparent
                border.width: 1
                border.color: input.activeFocus ? "#ff9f0a" : "#2b2e35"
            }

            MouseArea {
                id: inputMouseArea

                anchors.fill: parent
                z: 2
                acceptedButtons: Qt.LeftButton
                hoverEnabled: true
                preventStealing: true
                onPressed: (mouse) => {
                    inputRoot.grabKeyboardFocus();
                    mouse.accepted = true;
                }
                onClicked: (mouse) => {
                    mouse.accepted = true;
                }
            }

            Row {
                z: 1
                anchors.centerIn: parent
                spacing: Metrics.px(4)

                TextInput {
                    id: input

                    width: Metrics.px(42)
                    property bool sanitizing: false
                    color: "#f5f5f7"
                    selectionColor: "#ff9f0a"
                    selectedTextColor: "#111111"
                    font.pixelSize: UserConfig.bodyFontSize + Metrics.px(2)
                    font.family: inputRoot.textFontFamily
                    font.weight: Font.DemiBold
                    horizontalAlignment: TextInput.AlignRight
                    validator: IntValidator {
                        bottom: 0
                        top: 99
                    }
                    inputMethodHints: Qt.ImhDigitsOnly
                    cursorVisible: activeFocus
                    onActiveFocusChanged: if (activeFocus) inputRoot.keyboardFocusRequested()
                    onTextChanged: {
                        if (sanitizing)
                            return;

                        const digits = text.replace(/[^0-9]/g, "").slice(0, 2);
                        if (digits !== text) {
                            sanitizing = true;
                            text = digits;
                            sanitizing = false;
                        }
                    }
                    onEditingFinished: inputRoot.editingFinished()
                    Keys.onReturnPressed: inputRoot.editingFinished()
                    Keys.onEnterPressed: inputRoot.editingFinished()
                }

                Text {
                    text: inputRoot.label
                    color: "#9b9da4"
                    font.pixelSize: UserConfig.bodyFontSize - Metrics.px(3)
                    font.family: inputRoot.textFontFamily
                    font.weight: Font.Medium
                }
            }
        }
    }

    component TimerButton: Item {
        id: buttonRoot

        signal pressed()
        signal clicked()

        property string label: ""
        property bool accent: false
        property string textFontFamily: ""

        opacity: enabled ? 1.0 : 0.45
        scale: buttonArea.pressed ? 0.96 : 1.0

        Behavior on scale {
            NumberAnimation {
                duration: 90
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Motion.spring()   // FORK: was Easing.OutCubic
            }
        }

        Item {
            anchors.fill: parent

            MatteSurface {
                anchors.fill: parent
                radius: Metrics.px(10)
                hovered: buttonArea.containsMouse
                pressed: buttonArea.pressed
            }

            Rectangle {
                anchors.fill: parent
                anchors.margins: 1
                radius: Metrics.px(9)
                color: buttonRoot.accent
                    ? (buttonArea.pressed ? "#d98500" : "#ff9f0a")
                    : StyleTokens.transparent
                border.width: 1
                border.color: buttonRoot.accent ? "#ff9f0a" : "#2b2e35"
            }
        }

        Text {
            anchors.centerIn: parent
            text: buttonRoot.label
            color: buttonRoot.accent ? "#111111" : "#f5f5f7"
            font.pixelSize: UserConfig.bodyFontSize - Metrics.px(2)
            font.family: buttonRoot.textFontFamily
            font.weight: Font.DemiBold
        }

        MouseArea {
            id: buttonArea

            anchors.fill: parent
            enabled: buttonRoot.enabled
            hoverEnabled: true
            preventStealing: true
            onPressed: (mouse) => {
                buttonRoot.pressed();
                mouse.accepted = true;
            }
            onClicked: buttonRoot.clicked()
        }
    }
}
