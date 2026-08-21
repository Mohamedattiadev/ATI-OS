pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

// FORK: the shared scale factor — see qml/common/Metrics.js.
import "../common/Metrics.js" as Metrics
// FORK: the shared motion system — one spring for geometry, one
// critically damped curve for opacity. See qml/common/Motion.js.
import "../common/Motion.js" as Motion
// FORK: one ranking for every search field in the shell.
import "../common/Match.js" as Match
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
// panel already dismisses on Escape, which is the same gesture with no row
// spent on it. (`q` dismissed it too until the search field arrived and the
// alphabet had to start typing; see the fallback key handler.) One of the
// six, "Refresh the PC", became TWO rows here rather than one — `refresh`
// and `hardreset`, below — so the panel has seven rows in total.
//
// The commands live in hypr/scripts/power-ctl.sh, one to a line, and that
// file records the two options that could not port verbatim: `betterlockscreen`
// is X11-only so lock goes through `loginctl lock-session` like $mod SHIFT X,
// and `ati-reset-pc` — which kills twenty applications and restarts qtile — is
// not what "Refresh" runs any more. It was ported to `refresh`/`hyprctl
// reload` first (like $mod SHIFT R) because ati-reset-pc verbatim would have
// done harm under Wayland; `hardreset` is ati-reset-pc's actual behaviour,
// ported properly afterwards as its own row, adapted app-kill-and-restart
// script under Hyprland (hypr/scripts/reset-pc.sh) and the genuine script
// unchanged under X11. Both were read before being replaced or added.
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
// It matters MORE here than it did in rofi, not less — and now that this
// panel HAS rofi's search field, it matters for rofi's own reason as well
// as for its own. You type to filter and press Return on a highlighted
// line, in a list of seven where "Reboot" and "Shut down" are adjacent and
// share four letters; and this panel is on the same keyboard grab as every
// other one, so Return is the key the hand has already been trained to
// press. A one-keystroke path from "I opened the power menu" to "the
// machine is off" is the one interaction in this shell where being fast is
// the wrong goal.
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
    property string iconFontFamily: ""

    // [{ id, label, detail, confirm }, ...] — from power-ctl.sh --list, so
    // the panel and the script cannot disagree about what the actions are.
    // Same contract ModeKeysLayer has with cheatsheet.py.
    property var actions: []
    property int selectedIndex: 0

    // ---- THE SEARCH FIELD ---- see qml/common/PanelSearchField.qml.
    //
    // Asked for directly: "the power popop theme popup and some other
    // popups need searchh bar like its rofi one". This panel had none at
    // all, and it is the one whose ancestor was literally rofi — dm-logout
    // is a rofi menu, and typing "sh" then Return is how it was used.
    //
    // It matches on the DETAIL as well as the label, so "poweroff" finds
    // Shut down. The detail column is already on screen for exactly that
    // reason (see the note on the row below), so making it searchable costs
    // nothing and closes the gap between what you can read and what you can
    // type.
    //
    // THE FIELD OWNS THE TEXT and this is a read-only view of it. The
    // obvious shape — `property string query` here, `query: root.query` on
    // the field, `onQueryChanged: root.query = query` back — is a two-way
    // binding, and QML does not have those: the first character typed makes
    // the field assign to root.query, which DESTROYS the `query: root.query`
    // binding that was feeding it. It half-works, which is the bad kind of
    // wrong — the first keystroke lands and the panel then filters against a
    // string that no longer tracks the box.
    readonly property string query: searchField.query

    // RANKED, not merely filtered — see qml/common/Match.js.
    //
    // This is the panel the ranking bug was reported against, and the data
    // is why it matters here more than anywhere else:
    //
    //     Lock screen    loginctl lock-session -> hyprlock   <- "log" is here
    //     Log out        loginctl terminate-session
    //
    // A flat "label or detail contains it" in list order leaves "Lock
    // screen" selected for the query "log", because it matches on
    // `loginctl` and comes first. Enter then locks the screen when you were
    // one keystroke into logging out. Matching on the detail is still
    // right — it is how "poweroff" finds Shut down — it just must not
    // outrank the row whose NAME you typed.
    //
    // The id goes into the detail half of the rank so `refresh` still finds
    // Reload config, without an id ever beating a label.
    readonly property var visibleActions: Match.filter(
        root.actions, root.query,
        function (a) { return a.label; },
        function (a) { return String(a.detail || "") + " " + String(a.id || ""); })

    // "" when no confirmation is pending, otherwise the id awaiting y/n.
    property string pendingConfirm: ""
    property string errorText: ""

    readonly property string ctl: Quickshell.env("HOME") + "/.config/hypr/scripts/power-ctl.sh"

    // FORK: header height, content inset and the key-hint strip are
    // PanelChrome's now. See qml/common/PanelChrome.qml.
    readonly property real rowHeight: Metrics.px(38)

    // Metrics and not chrome.chromeHeight: this sizes the capsule the panel is
    // drawn inside, so reading it off a child of that panel is a loop waiting
    // for one more term.
    //
    // It follows the FILTERED list, and here that is right where it would be
    // wrong in the cheatsheet. Two reasons, both about this panel's shape:
    // the field is above the rows and the island grows downward from the
    // notch, so only the bottom edge moves and nothing you are typing into
    // slides; and this is seven rows, so the step is one row rather than the
    // cheatsheet's 192-to-3. Shrinking as the list narrows is also what rofi
    // itself does, which is the thing being asked for.
    readonly property real preferredHeight:
        Metrics.chromeTotal() + root.searchStripHeight
        + root.visibleActions.length * root.rowHeight

    // The field plus the gap under it, in one place because both the height
    // above and the rows' y below have to agree about it.
    readonly property real searchStripHeight: Metrics.px(26) + Metrics.px(10)

    readonly property var selectedAction:
        (root.selectedIndex >= 0 && root.selectedIndex < root.visibleActions.length)
            ? root.visibleActions[root.selectedIndex] : null

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
            // A stale query would open the panel showing one row and no
            // obvious reason why. The field is cleared, not remembered.
            searchField.clear();
            // Always start on the FIRST row, which is Lock screen — the one
            // action in the list that costs nothing if it fires by mistake.
            // Restoring the last selection would mean the panel sometimes
            // opens with "Shut down" already under the cursor, which is a
            // property no power menu should have.
            root.selectedIndex = 0;
            listProcess.running = true;
            // The FIELD takes the focus, not the FocusScope. A rofi-style
            // search you have to click into first is not one, and this panel
            // opens on a keyboard grab with nothing else to focus.
            root.syncFocus();
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
        if (root.visibleActions.length === 0)
            return;
        // Any movement cancels a pending confirmation. Without this, Down then
        // Return would confirm the action you moved AWAY from — the cursor
        // would be on Suspend and the machine would shut down.
        root.pendingConfirm = "";
        let next = root.selectedIndex + delta;
        // Wraps, like the display and audio panels' move(): this is a
        // seven-row list and Down stopping dead at the bottom reads as a dead
        // key. See FORK-NOTES.md, "the cursors wrap".
        if (next < 0) next = root.visibleActions.length - 1;
        if (next > root.visibleActions.length - 1) next = 0;
        root.selectedIndex = next;
    }

    // The filter narrowing can strand the cursor past the end of the list —
    // and on THIS panel a stranded cursor is not a cosmetic bug: selectedAction
    // would go null and Return would silently do nothing, or worse, the index
    // would land on a different row than the one that was highlighted when the
    // list last redrew. Clamped on every change, and reset to the top whenever
    // the query itself changes, so what is highlighted is always the first
    // match rather than whatever survived from the previous search.
    onQueryChanged: {
        root.pendingConfirm = "";
        root.selectedIndex = 0;
    }
    onVisibleActionsChanged: {
        if (root.selectedIndex > root.visibleActions.length - 1)
            root.selectedIndex = Math.max(0, root.visibleActions.length - 1);
    }

    // ---- WHO HAS THE KEYBOARD ----
    //
    // The search field, always — a field you have to click into first is not
    // the rofi behaviour being asked for, and this panel opens on a keyboard
    // grab with nothing else to focus.
    //
    // The confirmation step does not take focus AWAY from it; it makes the
    // field read-only (`searchField.readOnly` below), which stops it
    // inserting text while leaving every key to bubble up to the branch in
    // Keys.onPressed. Moving focus was the first attempt and it silently did
    // nothing — see the note on PanelSearchField.readOnly for what that cost
    // and how it showed itself.
    function syncFocus() {
        if (root.showCondition)
            searchField.focusField();
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

        // Below here is the FALLBACK path only. With no confirmation
        // pending the search field holds focus and answers these itself —
        // this runs when focus has not landed there yet, or after a click
        // somewhere that is not the field.
        //
        // `q` is deliberately NOT a close key any more, and that is the one
        // thing this panel gave up for the search bar. It was faithful to
        // dm-logout, where `q` was a row you selected; here it has to type,
        // because a field that ignores one letter of the alphabet is worse
        // than one that has no shortcut. Escape closes, and the hint strip
        // says so.
        switch (event.key) {
        case Qt.Key_Escape:
            root.closeRequested();
            event.accepted = true;
            break;
        case Qt.Key_Down:
            root.move(1);
            event.accepted = true;
            break;
        case Qt.Key_Up:
            root.move(-1);
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

    // ---- CHROME, SHARED ---- see qml/common/PanelChrome.qml.
    //
    // The error text used to REPLACE the header — "Power" became the error
    // string in danger red. It goes in the status slot instead, which is where
    // every other panel puts what went wrong and which already colours by
    // level. A panel whose title changes to an error message is a panel you
    // cannot tell you are looking at.
    PanelChrome {
        id: chrome
        textFontFamily: root.textFontFamily

        title: "power"

        status: root.errorText !== "" ? root.errorText
              : (root.runningAction !== "" ? root.runningAction + "…" : "")
        statusLevel: root.errorText !== "" ? "error"
                   : (root.runningAction !== "" ? "busy" : "idle")

        hints: root.pendingConfirm !== ""
            ? [
                { key: "y", label: "confirm" },
                { key: "n", label: "cancel" }
              ]
            : [
                // Arrows, not j/k, and Esc, not q — the search field owns
                // the alphabet now. The hint strip is the only place that
                // said "q" out loud, so it is the only place that has to
                // stop saying it.
                { key: "↑↓", label: "move" },
                { key: "Enter", label: "select" },
                { key: "Esc", label: "close" }
              ]
    }

    PanelSearchField {
        id: searchField
        x: chrome.contentX
        y: chrome.contentY
        width: chrome.contentWidth

        textFontFamily: root.textFontFamily
        iconFontFamily: root.iconFontFamily
        // The confirmation owns the keyboard; see syncFocus() above.
        readOnly: root.pendingConfirm !== ""
        placeholder: "type to filter — Enter runs, Esc closes"
        countText: root.query === "" ? ""
                 : (root.visibleActions.length + " of " + root.actions.length)

        onSubmitted: root.activate()
        onCancelled: root.closeRequested()
        onMoved: function(delta) { root.move(delta); }
    }

    Column {
        id: rows
        x: chrome.contentX
        y: chrome.contentY + root.searchStripHeight
        width: chrome.contentWidth

        Repeater {
            model: root.visibleActions

            PanelRow {
                id: rowItem
                required property int index
                required property var modelData

                readonly property bool isSelected: rowItem.index === root.selectedIndex
                readonly property bool isConfirming:
                    root.pendingConfirm === String(rowItem.modelData.id)

                width: rows.width
                height: root.rowHeight

                // `armed` is PanelRow's third state and this panel is the
                // reason it exists — the note that used to be here is now in
                // that file: the confirming row goes RED, not merely
                // highlighted, because a selection colour is what the row
                // already had and a second shade of the same thing is a change
                // you can miss.
                armed: rowItem.isConfirming
                selected: rowItem.isSelected

                onCursorRequested: {
                    if (root.pendingConfirm === "")
                        root.selectedIndex = rowItem.index;
                }
                // Click goes through activate(), so it gets the same
                // confirmation step the keyboard does. A mouse path that
                // skipped it would be a one-click shutdown next to a two-key
                // one.
                onActivated: root.activate()

                Text {
                    id: label
                    anchors.left: parent.left
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

                // The MouseArea is PanelRow's; its signals are wired above.
            }
        }
    }

    // The key-hint Text that used to be here is `chrome.hints` now.
}
