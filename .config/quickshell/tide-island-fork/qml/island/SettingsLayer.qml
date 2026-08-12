pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import IslandBackend

// FORK: the shared scale factor — see qml/common/Metrics.js.
import "../common/Metrics.js" as Metrics
// FORK: the shared motion system — one spring for geometry, one
// critically damped curve for opacity. See qml/common/Motion.js.
import "../common/Motion.js" as Motion

//
// FORK — new file. The SETTINGS surface.
//
// WHY THIS IS A PANEL AND NOT A PATCH
// -----------------------------------
// tide-island already has a settings application. It is
// /usr/bin/tide-island-config-app, and it is a COMPILED C++/Qt binary owned
// by the pacman package `tide-island 1.0.34-1`. Patching it means building it
// locally, and a local build of a packaged binary is overwritten without
// warning by the next `yay -Syu` — the same trap FORK-NOTES.md records for
// the vendored QML tree, except worse, because that one at least leaves a
// diff behind for `diff -ru` to find. A replaced binary leaves nothing.
//
// So this is a state of the island, like every other panel here.
//
// AND IT IS NOT A CLONE OF THAT APP
// ---------------------------------
// Reproducing all 39 backend properties would be a worse text editor than
// the file already is: userconfig.json is heavily annotated with `_key`
// comment entries explaining every divergence from upstream, and a panel
// cannot show those in the space a row has. Two tests decided each row, and
// they are written out in island-settings.py beside the table itself —
// roughly "changed more than once in practice", or "FORK-ONLY".
//
// The fork-only ones are the point. Notch mode, the chord HUD, the resting
// EQ, the theme reveal and the polkit prompt do not exist upstream, so
// UserConfigBackend has no property for them, so the packaged config app
// cannot show them and never will. Before this panel the only way to change
// one was to edit a QML literal. `scope` is on every row for exactly that
// reason: "fork" means the packaged app is blind to this key.
//
// WHERE THE WRITE HAPPENS, AND WHY NOT HERE
// -----------------------------------------
// hypr/scripts/island-settings.py, via os.replace. Not from QML, and the
// reason is the annotations: a writer has to read the whole object, change
// one key, and put the object back, or the twelve `_key` comments explaining
// a dozen decisions are gone in one save with nothing on screen to say so.
// That is a read-modify-write with an atomic rename, and doing it in QML
// would mean doing it without either.
//
// TWO CONSUMERS, TWO REFRESH PATHS
// --------------------------------
//   * `fork*` keys are read by qml/common/ForkConfig.qml, which WATCHES the
//     file. Those update themselves.
//   * packaged keys are read by the compiled UserConfigBackend, which is
//     re-read explicitly with UserConfig.reload() after a successful write.
//     Without that the file would be right and the island would not move,
//     which reads as the write having failed.
//
FocusScope {
    id: root

    signal closeRequested

    property bool showCondition: false
    property string textFontFamily: ""
    property string heroFontFamily: ""

    readonly property var userConfig: UserConfig
    readonly property string ctl: Quickshell.env("HOME") + "/.config/hypr/scripts/island-settings.py"

    // [{ key, label, type, value, scope, detail, ... }, ...]
    property var settings: []
    property int selectedIndex: 0
    property string statusText: ""
    property bool statusIsError: false
    property string configPath: ""

    // Problems in settings-extra.json, from --list. A row rejected for a typo
    // is SKIPPED rather than fatal (island-settings.py, load_extra), which is
    // the right call and is also completely invisible — the panel just has
    // one fewer row than the file asked for. This is the half that makes it
    // visible.
    property var warnings: []

    readonly property real horizontalPadding: Metrics.pad(18)
    readonly property real headerHeight: Metrics.pad(36)
    readonly property real rowHeight: Metrics.px(30)
    readonly property real baseFooterHeight: Metrics.px(22)
    readonly property int warningLines: Math.min(root.warnings.length, 3)
    readonly property real warningHeight:
        root.warningLines > 0
            ? root.warningLines * Metrics.px(14) + Metrics.pad(8) : 0
    readonly property real footerHeight: root.baseFooterHeight + root.warningHeight

    // The list is the tall half; the details column beside it is bounded by
    // the list, not the other way round. Same list-plus-details shape the
    // display and audio panels use.
    readonly property real preferredHeight:
        root.headerHeight + root.settings.length * root.rowHeight
        + root.footerHeight + Metrics.pad(16)

    readonly property real listWidth: Math.round(root.width * 0.52)

    readonly property var selected:
        (root.selectedIndex >= 0 && root.selectedIndex < root.settings.length)
            ? root.settings[root.selectedIndex] : null

    focus: showCondition
    activeFocusOnTab: true
    anchors.fill: parent
    opacity: showCondition ? 1 : 0

    // FORK: one choreography for every layer in the shell. See Motion.js.
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

    onShowConditionChanged: {
        if (showCondition) {
            // Re-read on every open. The file is also written by the packaged
            // config app and by hand, and a panel showing a cached value would
            // be the one place in this shell that disagreed with the config it
            // is editing.
            root.statusText = "";
            root.statusIsError = false;
            listProcess.running = true;
            forceActiveFocus();
        }
    }

    Process {
        id: listProcess
        command: ["python3", root.ctl, "--list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(text);
                    root.settings = parsed.settings || [];
                    root.configPath = String(parsed.path || "");
                    root.warnings = parsed.warnings || [];
                    // Clamp after a re-read: the list can get SHORTER than it
                    // was, because a --set re-reads settings-extra.json too
                    // and it may have been edited since the panel opened.
                    if (root.selectedIndex > root.settings.length - 1)
                        root.selectedIndex = Math.max(0, root.settings.length - 1);
                } catch (error) {
                    root.settings = [];
                    root.warnings = [];
                    root.statusText = "could not read island-settings.py --list";
                    root.statusIsError = true;
                }
            }
        }
    }

    // ---- THE WRITE, AND WHY THE Process IS BUILT FRESH ----
    //
    // The trap written up at length in ModeKeysLayer.qml: a REUSED Quickshell
    // Process with a StdioCollector hands back the PREVIOUS run's text on the
    // second and later runs. This panel reads the write's result, so on the
    // reused form the SECOND toggle would report the FIRST toggle's outcome —
    // and since the first one succeeds, a failing second write would show
    // "ok". Silently reporting success for a write that did not happen is the
    // worst available failure for a settings panel.
    //
    // Fresh pair per write, which is what actually fixed it there.
    property string pendingKey: ""
    property string pendingValue: ""

    function commit(key, value) {
        if (root.pendingKey !== "")
            return;
        root.pendingKey = String(key);
        root.pendingValue = String(value);
        root.statusText = "";
        root.statusIsError = false;
        writeLoader.active = false;
        writeLoader.active = true;
    }

    Loader {
        id: writeLoader
        active: false

        sourceComponent: Component {
            Process {
                command: ["python3", root.ctl, "--set", root.pendingKey, root.pendingValue]
                running: true
                stdout: StdioCollector {
                    onStreamFinished: {
                        let ok = false;
                        let message = "";
                        try {
                            const parsed = JSON.parse(text);
                            ok = parsed.ok === true;
                            message = String(parsed.error || "");
                        } catch (error) {
                            message = "island-settings.py produced no readable output";
                        }

                        root.pendingKey = "";
                        root.pendingValue = "";

                        if (!ok) {
                            root.statusText = message !== "" ? message : "write failed";
                            root.statusIsError = true;
                            // Re-read anyway, so the row snaps back to what is
                            // actually in the file rather than keeping the
                            // value the keypress implied.
                            listProcess.running = true;
                            return;
                        }

                        root.statusText = "saved";
                        root.statusIsError = false;

                        // The packaged backend does not watch the file, so
                        // without this the config is right and the island does
                        // not move — which is indistinguishable from the write
                        // having failed. ForkConfig.qml needs no equivalent:
                        // it has its own watcher.
                        root.userConfig.reload();
                        listProcess.running = true;
                    }
                }
            }
        }
    }

    // ---- CHANGING A VALUE ----
    //
    // One verb, three types. `delta` is +1 or -1: for a bool either sign
    // toggles (there are only two states and h/l meaning "the other one" is
    // what the hand expects), for an enum it steps the list, for an int it
    // adds a step. Enter is +1, which makes the common case — flipping a
    // switch — a single key.
    function change(delta) {
        const entry = root.selected;
        if (!entry || root.pendingKey !== "")
            return;

        if (entry.type === "bool") {
            root.commit(entry.key, entry.value === true ? "false" : "true");
            return;
        }

        if (entry.type === "enum") {
            const values = entry.values || [];
            if (values.length === 0)
                return;
            let index = values.indexOf(String(entry.value));
            if (index < 0) index = 0;
            index = (index + delta + values.length) % values.length;
            root.commit(entry.key, values[index]);
            return;
        }

        if (entry.type === "int") {
            const step = Number(entry.step || 1);
            let next = Number(entry.value) + delta * step;
            next = Math.max(Number(entry.min), Math.min(Number(entry.max), next));
            if (next === Number(entry.value))
                return;
            root.commit(entry.key, String(next));
            return;
        }
    }

    function move(delta) {
        if (root.settings.length === 0)
            return;
        let next = root.selectedIndex + delta;
        // Wraps, like every other list in this shell. See FORK-NOTES.md,
        // "the cursors wrap".
        if (next < 0) next = root.settings.length - 1;
        if (next > root.settings.length - 1) next = 0;
        root.selectedIndex = next;
        list.positionViewAtIndex(next, ListView.Contain);
    }

    Keys.onPressed: function(event) {
        switch (event.key) {
        case Qt.Key_Escape:
        case Qt.Key_Q:
            root.closeRequested();
            event.accepted = true;
            break;
        case Qt.Key_Down:
        case Qt.Key_J:
            root.move(1);
            event.accepted = true;
            break;
        case Qt.Key_Up:
        case Qt.Key_K:
            root.move(-1);
            event.accepted = true;
            break;
        case Qt.Key_Left:
        case Qt.Key_H:
            root.change(-1);
            event.accepted = true;
            break;
        case Qt.Key_Right:
        case Qt.Key_L:
        case Qt.Key_Return:
        case Qt.Key_Enter:
        case Qt.Key_Space:
            root.change(1);
            event.accepted = true;
            break;
        case Qt.Key_G:
            root.selectedIndex = (event.modifiers & Qt.ShiftModifier) !== 0
                ? Math.max(0, root.settings.length - 1) : 0;
            list.positionViewAtIndex(root.selectedIndex, ListView.Contain);
            event.accepted = true;
            break;
        default:
            break;
        }
    }

    Text {
        id: header
        x: root.horizontalPadding
        y: Metrics.pad(11)
        text: "Island settings"
        color: "white"
        font.pixelSize: Metrics.font(15)
        font.family: root.heroFontFamily
        font.weight: Font.DemiBold
        font.letterSpacing: -0.2
    }

    // The path, on the panel. This surface edits a file that is also edited
    // by hand and by the packaged app, so which file it is is not trivia —
    // it is the first thing you need when the panel and the shell disagree.
    Text {
        anchors.right: parent.right
        anchors.rightMargin: root.horizontalPadding
        y: Metrics.pad(13)
        width: Math.min(implicitWidth, root.width * 0.55)
        horizontalAlignment: Text.AlignRight
        elide: Text.ElideLeft
        text: root.statusText !== "" ? root.statusText : root.configPath
        color: root.statusIsError ? "#ff6b6b"
             : (root.statusText !== "" ? "#9ad18a" : "#6a6f78")
        font.pixelSize: Metrics.font(11)
        font.family: root.textFontFamily
    }

    ListView {
        id: list
        x: root.horizontalPadding
        y: root.headerHeight
        width: root.listWidth
        height: parent.height - root.headerHeight - root.footerHeight - Metrics.pad(8)
        clip: true
        model: root.settings
        currentIndex: root.selectedIndex
        boundsBehavior: Flickable.StopAtBounds

        delegate: Item {
            id: rowItem
            required property int index
            required property var modelData

            readonly property bool isSelected: rowItem.index === root.selectedIndex

            width: list.width
            height: root.rowHeight

            Rectangle {
                anchors.fill: parent
                anchors.topMargin: Metrics.px(2)
                anchors.bottomMargin: Metrics.px(2)
                radius: Metrics.px(7)
                color: rowItem.isSelected ? "#2c3038" : "transparent"

                Text {
                    id: rowLabel
                    anchors.left: parent.left
                    anchors.leftMargin: Metrics.pad(10)
                    anchors.verticalCenter: parent.verticalCenter
                    text: rowItem.modelData.label
                    color: "#f2f4f7"
                    font.pixelSize: Metrics.font(12)
                    font.family: root.textFontFamily
                    font.weight: rowItem.isSelected ? Font.DemiBold : Font.Normal
                }

                // The value, right-aligned. Booleans read "on"/"off" rather
                // than "true"/"false": the file is JSON and the panel is not,
                // and "off" is the word the eye is scanning a settings list
                // for.
                Text {
                    id: rowValue
                    anchors.right: parent.right
                    anchors.rightMargin: Metrics.pad(10)
                    anchors.verticalCenter: parent.verticalCenter
                    text: rowItem.modelData.type === "bool"
                        ? (rowItem.modelData.value === true ? "on" : "off")
                        : String(rowItem.modelData.value)
                    // The dangerous switch is coloured when it is ON, and
                    // only then. Every other value is neutral, so the one
                    // row that can take the system's password prompts away
                    // is the one row that is not.
                    color: (rowItem.modelData.key === "forkPolkitAgentEnabled"
                            && rowItem.modelData.value === true)
                        ? "#ff6b6b"
                        : (rowItem.modelData.value === true ? "#9ad18a" : "#8a8f98")
                    font.pixelSize: Metrics.font(12)
                    font.family: root.textFontFamily
                    font.weight: Font.DemiBold
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: root.selectedIndex = rowItem.index
                    onClicked: {
                        root.selectedIndex = rowItem.index;
                        root.change(1);
                    }
                }
            }
        }
    }

    // ---- DETAILS ----
    //
    // Every row's `detail` is the WHY, carried over from the `_key`
    // annotations in userconfig.json rather than newly written here: the file
    // is the record of these decisions and a second copy in a different place
    // would drift the first time one was revised. It is the reason the panel
    // is 860 px wide — a settings list of twelve switches with no explanation
    // of any of them is a list you change by trial and error.
    Column {
        id: details
        anchors.left: parent.left
        anchors.leftMargin: root.horizontalPadding + root.listWidth + Metrics.pad(16)
        anchors.right: parent.right
        anchors.rightMargin: root.horizontalPadding
        y: root.headerHeight + Metrics.px(2)
        spacing: Metrics.px(6)

        Row {
            spacing: Metrics.pad(8)

            Text {
                text: root.selected ? root.selected.label : ""
                color: "white"
                font.pixelSize: Metrics.font(13)
                font.family: root.heroFontFamily
                font.weight: Font.DemiBold
            }

            // The scope chip. "fork" is the load-bearing one: it says the
            // packaged config app has no row for this key and cannot get
            // one, which is the difference between "I could also change this
            // in the other app" and "this is the only place it exists".
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.selected !== null
                width: scopeLabel.implicitWidth + Metrics.pad(10)
                height: Metrics.px(16)
                radius: Metrics.px(5)
                color: (root.selected && root.selected.scope === "fork")
                    ? "#2f3f52" : "#2c3038"

                Text {
                    id: scopeLabel
                    anchors.centerIn: parent
                    text: root.selected
                        ? (root.selected.scope === "fork" ? "fork only" : "packaged")
                        : ""
                    color: (root.selected && root.selected.scope === "fork")
                        ? "#8fc0ef" : "#8a8f98"
                    font.pixelSize: Metrics.font(9)
                    font.family: root.textFontFamily
                    font.weight: Font.Medium
                }
            }

            // The provenance chip, beside the scope chip and only when there
            // is something to say. `scope` answers "can the packaged app
            // change this too"; this answers "where did this ROW come from",
            // and they are different questions the moment settings-extra.json
            // exists. It matters most for "edited": that row's detail may be
            // the user's own words, so the reasoning it shows is no longer
            // necessarily the reasoning this repo recorded.
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.selected !== null
                    && root.selected.source !== undefined
                    && root.selected.source !== "builtin"
                width: sourceLabel.implicitWidth + Metrics.pad(10)
                height: Metrics.px(16)
                radius: Metrics.px(5)
                color: "#3a3327"

                Text {
                    id: sourceLabel
                    anchors.centerIn: parent
                    text: (root.selected && root.selected.source === "user")
                        ? "yours" : "edited"
                    color: "#e0b072"
                    font.pixelSize: Metrics.font(9)
                    font.family: root.textFontFamily
                    font.weight: Font.Medium
                }
            }
        }

        Text {
            width: details.width
            wrapMode: Text.WordWrap
            text: root.selected ? String(root.selected.detail || "") : ""
            // The polkit row's explanation is a warning, so it is coloured
            // as one. It is the only row whose detail can cost you something.
            color: (root.selected && root.selected.key === "forkPolkitAgentEnabled")
                ? "#ffb3b8" : "#a8aeb8"
            font.pixelSize: Metrics.font(11)
            font.family: root.textFontFamily
            lineHeight: 1.25
        }

        // The key name, so the row can be found in the file it edits.
        Text {
            text: root.selected ? root.selected.key : ""
            color: "#5a5f68"
            font.pixelSize: Metrics.font(10)
            font.family: root.textFontFamily
        }
    }

    // ---- WARNINGS FROM settings-extra.json ----
    //
    // Amber, not red: nothing is broken. The built-in rows are all present
    // and working; some row the user's file asked for is not. Red here would
    // put the panel's most alarming colour on the least alarming failure,
    // next to a polkit row that earned it.
    //
    // Three lines and no more. The full list is `island-settings.py --check`,
    // which is where you would be anyway if you were fixing the file, and a
    // banner that can grow without limit eats the list it is reporting on.
    Text {
        id: warningBanner
        visible: root.warnings.length > 0
        // anchors.left AND anchors.right, not `x` plus anchors.right. With
        // only one horizontal anchor the Text keeps its implicitWidth, which
        // for one long line is far wider than the panel — wrapMode then has
        // nothing to wrap against and the string runs out past the rounded
        // left edge instead of onto a second line. This is what it did.
        anchors.left: parent.left
        anchors.leftMargin: root.horizontalPadding
        anchors.right: parent.right
        anchors.rightMargin: root.horizontalPadding
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.baseFooterHeight + Metrics.pad(4)
        wrapMode: Text.WordWrap
        maximumLineCount: root.warningLines
        elide: Text.ElideRight
        text: root.warnings.length > 0
            ? "settings-extra.json: " + root.warnings.join("  ·  ")
              + (root.warnings.length > 3 ? "   (--check for all)" : "")
            : ""
        color: "#e0b072"
        font.pixelSize: Metrics.font(10)
        font.family: root.textFontFamily
        lineHeight: 1.2
    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Metrics.pad(8)
        text: "j/k move  ·  h/l or Enter change  ·  q close"
        color: "#6a6a6a"
        font.pixelSize: Metrics.font(10)
        font.family: root.textFontFamily
    }
}
