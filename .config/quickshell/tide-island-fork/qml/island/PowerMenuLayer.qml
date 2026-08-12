pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

// FORK: the shared scale factor — see qml/common/Metrics.js.
import "../common/Metrics.js" as Metrics
// FORK: the shared motion system — one spring for geometry, one
// critically damped curve for opacity. See qml/common/Motion.js.
import "../common/Motion.js" as Motion
import "../common"

//
// FORK — new file. The POWER MENU, one of DESIGN-SPEC.md's states of the one
// shape, and unlike the calendar this one HAS an ancestor: qtile spawned
// `dm-logout -r`, bound at config.py ~6129 to mod+shift+q and again as `q`
// inside the Rofi chord. Both of those keys now point here instead.
//
// WHAT dm-logout ACTUALLY OFFERS
// ------------------------------
// /usr/local/bin/dm-logout is a dmscripts rofi menu. Its seven options, read
// out of the script rather than remembered:
//
//     Lock screen · Logout (terminate session) · Refresh the PC ·
//     Reboot · Shutdown · Suspend · Quit
//
// Six of them survive. "Quit" does not appear as a row here because it is
// not an action — in a rofi menu it is how you dismiss the menu, and this
// panel already dismisses on Escape and on q, which is the same gesture with
// no row spent on it.
//
// The commands live in hypr/scripts/power-ctl.sh, one to a line, and that
// file records the two options that could not port verbatim: `betterlockscreen`
// is X11-only so lock goes through `loginctl lock-session` like $mod SHIFT X,
// and `reset_PC` kills twenty applications and restarts qtile so "Refresh"
// becomes `hyprctl reload` like $mod SHIFT R. Both were read before being
// replaced.
//
// THE CONFIRMATION IS THE PORT'S MOST IMPORTANT HALF
// --------------------------------------------------
// dm-logout does not just list actions; it asks a second question. Five of
// its six run
//
//     [[ "$(echo -e "No\nYes" | ${MENU} "${choice}?")" == "Yes" ]]
//
// and only "Lock screen" fires immediately. That asymmetry is the whole
// safety model of the original and it is reproduced exactly, `confirm` flag
// for `confirm` flag, out of the same script's --list.
//
// It matters MORE here than it did in rofi, not less. In rofi you type to
// filter and press Return on a highlighted line; here j/k walks a list of
// six where "Reboot" and "Shut down" are adjacent, and this panel is on the
// same keyboard grab as every other one, so Return is the key the hand has
// already been trained to press. A one-keystroke path from "I opened the
// power menu" to "the machine is off" is the one interaction in this shell
// where being fast is the wrong goal.
//
// The confirm step is a SEPARATE key, not a second Return: y (or Return)
// confirms, n or Escape backs out. A double-Return would be exactly the
// accident the step exists to prevent.
//
FocusScope {
    id: root

    signal closeRequested

    property bool showCondition: false
    property string textFontFamily: ""
    property string heroFontFamily: ""

    // [{ id, label, detail, confirm }, ...] — from power-ctl.sh --list, so
    // the panel and the script cannot disagree about what the actions are.
    // Same contract ModeKeysLayer has with cheatsheet.py.
    property var actions: []
    property int selectedIndex: 0

    // "" when no confirmation is pending, otherwise the id awaiting y/n.
    property string pendingConfirm: ""
    property string errorText: ""

    readonly property string ctl: Quickshell.env("HOME") + "/.config/hypr/scripts/power-ctl.sh"

    readonly property real horizontalPadding: Metrics.pad(18)
    readonly property real headerHeight: Metrics.pad(36)
    readonly property real rowHeight: Metrics.px(38)
    readonly property real footerHeight: Metrics.px(22)

    readonly property real preferredHeight:
        root.headerHeight + root.actions.length * root.rowHeight
        + root.footerHeight + Metrics.pad(16)

    readonly property var selectedAction:
        (root.selectedIndex >= 0 && root.selectedIndex < root.actions.length)
            ? root.actions[root.selectedIndex] : null

    focus: showCondition
    activeFocusOnTab: true
    anchors.fill: parent
    opacity: showCondition ? 1 : 0

    // FORK: one choreography for every layer in the shell. See Motion.js,
    // "CONTENT CHOREOGRAPHY".
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
            root.pendingConfirm = "";
            root.errorText = "";
            // Always start on the FIRST row, which is Lock screen — the one
            // action in the list that costs nothing if it fires by mistake.
            // Restoring the last selection would mean the panel sometimes
            // opens with "Shut down" already under the cursor, which is a
            // property no power menu should have.
            root.selectedIndex = 0;
            listProcess.running = true;
            forceActiveFocus();
        } else {
            root.pendingConfirm = "";
        }
    }

    Process {
        id: listProcess
        command: [root.ctl, "--list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(text);
                    root.actions = parsed.actions || [];
                } catch (error) {
                    // Say so rather than presenting an empty panel, which
                    // reads as "this machine cannot be turned off".
                    root.actions = [];
                    root.errorText = "could not read power-ctl.sh --list";
                }
            }
        }
    }

    // ---- WHY THE RUNNER IS A FRESH Process AND NOT A REUSED ONE ----
    //
    // The trap written up at length in ModeKeysLayer.qml: a REUSED
    // Quickshell Process with a StdioCollector hands back the PREVIOUS run's
    // text on the second and later runs. This panel does not read stdout, so
    // it would not show a stale value — but it does read the EXIT CODE, and
    // the same reuse is why `running = true` on an already-running Process
    // is a no-op. The failure mode would be: press Suspend, nothing happens,
    // press it again, still nothing.
    //
    // Building the pair fresh per invocation removes the reuse rather than
    // sequencing around it, which is what actually worked there.
    property string runningAction: ""

    function invoke(id) {
        if (!id || root.runningAction !== "")
            return;
        root.errorText = "";
        root.runningAction = id;
        runLoader.active = false;
        runLoader.active = true;
    }

    Loader {
        id: runLoader
        active: false

        sourceComponent: Component {
            Process {
                command: [root.ctl, root.runningAction]
                running: true
                onExited: function(exitCode) {
                    const failedAction = root.runningAction;
                    root.runningAction = "";
                    if (exitCode !== 0) {
                        root.errorText = failedAction + " failed (exit " + exitCode + ")";
                        return;
                    }
                    // Close on success. `reboot`, `shutdown` and `logout`
                    // never get here — the session is gone before the exit
                    // code is read — but `lock`, `suspend` and `refresh` all
                    // return, and leaving the menu up behind a lock screen
                    // means it is still up when you come back.
                    root.closeRequested();
                }
            }
        }
    }

    function activate() {
        const action = root.selectedAction;
        if (!action)
            return;

        if (root.pendingConfirm === String(action.id)) {
            // Second step: already asked, answer is yes.
            root.pendingConfirm = "";
            root.invoke(String(action.id));
            return;
        }

        if (action.confirm === true) {
            root.pendingConfirm = String(action.id);
            return;
        }

        root.invoke(String(action.id));
    }

    function move(delta) {
        if (root.actions.length === 0)
            return;
        // Any movement cancels a pending confirmation. Without this, j then
        // Return would confirm the action you moved AWAY from — the cursor
        // would be on Suspend and the machine would shut down.
        root.pendingConfirm = "";
        let next = root.selectedIndex + delta;
        // Wraps, like the display and audio panels' move(): this is a
        // six-row list and j stopping dead at the bottom reads as a dead
        // key. See FORK-NOTES.md, "the cursors wrap".
        if (next < 0) next = root.actions.length - 1;
        if (next > root.actions.length - 1) next = 0;
        root.selectedIndex = next;
    }

    Keys.onPressed: function(event) {
        // The confirmation state owns the keyboard while it is up, and
        // deliberately answers to a SMALL set: y/Return confirm, n/Escape
        // cancel, everything else is swallowed. Falling through to the
        // movement keys here would let j quietly change what "yes" meant.
        if (root.pendingConfirm !== "") {
            switch (event.key) {
            case Qt.Key_Y:
            case Qt.Key_Return:
            case Qt.Key_Enter:
                root.activate();
                break;
            case Qt.Key_N:
            case Qt.Key_Escape:
            case Qt.Key_Q:
                root.pendingConfirm = "";
                break;
            default:
                break;
            }
            event.accepted = true;
            return;
        }

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
        case Qt.Key_G:
            root.pendingConfirm = "";
            root.selectedIndex = (event.modifiers & Qt.ShiftModifier) !== 0
                ? Math.max(0, root.actions.length - 1) : 0;
            event.accepted = true;
            break;
        case Qt.Key_Return:
        case Qt.Key_Enter:
            root.activate();
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
        text: root.errorText !== "" ? root.errorText : "Power"
        color: root.errorText !== "" ? IslandTheme.danger : IslandTheme.textPrimary
        font.pixelSize: Metrics.font(15)
        font.family: root.heroFontFamily
        font.weight: Font.DemiBold
        font.letterSpacing: -0.2
    }

    Text {
        anchors.right: parent.right
        anchors.rightMargin: root.horizontalPadding
        y: Metrics.pad(13)
        text: root.runningAction !== "" ? root.runningAction + "…" : ""
        color: IslandTheme.textSecondary
        font.pixelSize: Metrics.font(12)
        font.family: root.textFontFamily
    }

    Column {
        id: rows
        x: root.horizontalPadding
        y: root.headerHeight
        width: parent.width - root.horizontalPadding * 2

        Repeater {
            model: root.actions

            Item {
                id: rowItem
                required property int index
                required property var modelData

                readonly property bool isSelected: rowItem.index === root.selectedIndex
                readonly property bool isConfirming:
                    root.pendingConfirm === String(rowItem.modelData.id)

                width: rows.width
                height: root.rowHeight

                Rectangle {
                    anchors.fill: parent
                    anchors.topMargin: Metrics.px(2)
                    anchors.bottomMargin: Metrics.px(2)
                    radius: Metrics.px(8)
                    // The confirming row goes RED, not merely highlighted.
                    // The state it is announcing is "the next keystroke does
                    // this", and a selection colour is what the row already
                    // had — a second shade of the same thing would be a
                    // change you can miss.
                    color: rowItem.isConfirming ? IslandTheme.dangerFill
                         : (rowItem.isSelected ? IslandTheme.selectionFill : "transparent")

                    Behavior on color {
                        ColorAnimation {
                            duration: Motion.fadeInDuration()
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Motion.fade()
                        }
                    }

                    Text {
                        id: label
                        anchors.left: parent.left
                        anchors.leftMargin: Metrics.pad(12)
                        anchors.verticalCenter: parent.verticalCenter
                        text: rowItem.isConfirming
                            ? rowItem.modelData.label + "?   y / n"
                            : rowItem.modelData.label
                        color: rowItem.isConfirming ? IslandTheme.danger : IslandTheme.textPrimary
                        font.pixelSize: Metrics.font(13)
                        font.family: root.textFontFamily
                        font.weight: (rowItem.isSelected || rowItem.isConfirming)
                            ? Font.DemiBold : Font.Normal
                    }

                    // The command, on the row. This is the width the panel
                    // is 400 px wide FOR: "Reboot" and "Shut down" are one
                    // word apart in a list and `systemctl reboot` versus
                    // `systemctl poweroff` is not. It also means a keybinding
                    // that stops working can be diagnosed from the panel
                    // rather than from this file.
                    Text {
                        visible: !rowItem.isConfirming
                        anchors.right: parent.right
                        anchors.rightMargin: Metrics.pad(12)
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: label.right
                        anchors.leftMargin: Metrics.pad(12)
                        horizontalAlignment: Text.AlignRight
                        elide: Text.ElideRight
                        text: rowItem.modelData.detail
                        color: IslandTheme.textDisabled
                        font.pixelSize: Metrics.font(10)
                        font.family: root.textFontFamily
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: {
                            if (root.pendingConfirm === "")
                                root.selectedIndex = rowItem.index;
                        }
                        // Click goes through activate(), so it gets the same
                        // confirmation step the keyboard does. A mouse path
                        // that skipped it would be a one-click shutdown next
                        // to a two-key one.
                        onClicked: {
                            root.selectedIndex = rowItem.index;
                            root.activate();
                        }
                    }
                }
            }
        }
    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Metrics.pad(8)
        text: root.pendingConfirm !== ""
            ? "y confirm  ·  n cancel"
            : "j/k move  ·  Enter select  ·  q close"
        color: IslandTheme.textDisabled
        font.pixelSize: Metrics.font(10)
        font.family: root.textFontFamily
    }
}
