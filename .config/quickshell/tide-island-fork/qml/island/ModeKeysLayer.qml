pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "../common/Metrics.js" as Metrics
// FORK: the shared motion system — one spring for geometry, one
// critically damped curve for opacity. See qml/common/Motion.js.
import "../common/Motion.js" as Motion
import "../common"

//
// FORK — new file. The chord/submap heads-up display.
//
// WHAT WAS WRONG WITH THE OLD ONE
// -------------------------------
// `submap-indicator.sh` put the mode's NAME in the capsule — "ROFI-MODE" —
// and that was the whole of it. It answered "am I in a mode", which is the
// question qtile's bar answered, and it is genuinely the important half:
// without it the compositor silently swallows keys and there is no way to
// tell. But it does not answer the question you actually have while
// standing in a 26-key chord, which is "and what are the keys".
//
// qtile got away with the name alone because its chords were one-shot and
// its cheatsheet was one keystroke away. Hyprland submaps are sticky, so
// you sit in them, and the cheatsheet is itself behind a chord.
//
// THIS LAYER TAKES NO KEYBOARD FOCUS, AND THAT IS THE WHOLE DESIGN
// ----------------------------------------------------------------
// Every other panel in this shell (theme picker, display, audio) takes an
// EXCLUSIVE keyboard grab, because each reads its own keys. This one must
// do the exact opposite: the keys belong to the compositor's submap, and a
// grab here would swallow the very keys it is drawn to advertise — the
// panel would appear and the mode would stop working.
//
// So it is not in `WlrLayershell.keyboardFocus`, not in the `focus:` list
// on islandContainer, and not raised to the Overlay layer. It is a
// picture. The only reason it is in `blocksTransientSplit` is so a volume
// OSD does not replace it mid-chord.
//
// That list was necessary and NOT sufficient, which cost a measurement to
// find: `showTransientCapsule` (volume, brightness, text OSDs) consulted
// it, but `showWorkspaceCapsule`, `showNotificationCapsule` and
// `showBluetoothExpanded` each carried their own hand-written
// `control_center || notification` guard predating every panel here. So a
// volume OSD was blocked and a workspace switch was not — and the chords
// bind `1-9 workspace`, so the one interrupt that got through was the one
// fired most. Measured with the HUD up: `hyprctl dispatch workspace 7`
// replaced it with the "Workspace 7" capsule before, survives it after.
// See `openPanelState` in DynamicIslandWindow.qml.
//
// The rows come from `hyprctl binds` at the moment the submap is entered,
// by way of `cheatsheet.py --submap-json`, for the same reason the printed
// cheatsheet does: a hand-written list of a mode's keys is only ever as
// true as the last person to edit it, and a wrong hint still renders.
//
Item {
    id: root

    property bool showCondition: false
    property string textFontFamily: ""
    property string heroFontFamily: ""

    // [{ key: "SHIFT K", action: "volume up" }, ...]
    property var keys: []
    property string modeName: ""

    // ---- WHY THE ROWS ARE FETCHED HERE AND NOT PASSED IN ----
    //
    // The first version had the shell script send the rows as an IPC
    // argument. They never arrived, and the reason is worth keeping:
    // **Quickshell's IPC splits arguments on whitespace, and shell quoting
    // does not survive it.** A one-parameter call gets the remainder joined
    // back together, which is why `tide showText "hello world"` works and
    // hides the problem entirely; a two-parameter call does not, so the
    // rofi chord's rows — actions reading "wifi panel", "theme picker" —
    // arrived as 27 arguments instead of 2 and were rejected outright.
    // Percent-encoding got past the argument count and still produced empty
    // rows, at which point the transport had cost more than it was worth.
    //
    // So the IPC carries only the mode NAME, which is one word and cannot
    // have this problem, and the panel runs the backend itself. That is
    // also the pattern every other panel in this shell already uses —
    // ThemePickerLayer runs theme-list.sh, DisplayPanel runs display-ctl.py
    // — so it is one less thing that is special.
    readonly property string ctl: Quickshell.env("HOME") + "/.config/hypr/scripts/cheatsheet.py"

    // ---- WHY EACH FETCH GETS A BRAND-NEW Process ----
    //
    // Going from one submap straight into another drew the NEW mode's name
    // over the OLD mode's keys — the panel rendered exactly ONE MODE
    // BEHIND. Measured, each step given two seconds to settle, so nothing
    // here is a race with a slow `hyprctl binds`:
    //
    //     lang  (from idle) -> its own 4 rows, correct
    //     rofi  (while up)  -> lang's 4 rows
    //     media (while up)  -> rofi's 26 rows
    //
    // TWO explanations were tried on it and BOTH were wrong, which is the
    // reason this comment is long: the fix that finally worked is not the
    // one the symptom suggests.
    //
    //   1. "`running = true` on an already-running Process is a no-op, so
    //      the second fetch never happened." No: two seconds is far longer
    //      than the fetch takes, and adding `running = false` first moved
    //      the numbers not at all.
    //
    //   2. "`command` was bound to modeName, and QML runs a change handler
    //      before re-evaluating the bindings that depend on the same
    //      property, so the process started against the previous name."
    //      Plausible, and also no: assigning command imperatively an
    //      instant before `running = true` produced the identical
    //      one-behind sequence.
    //
    // What both share is a REUSED Process and, with it, a reused
    // StdioCollector — and a collector that has already finished one
    // stream is what hands back the previous run's text. Creating the pair
    // fresh per fetch removes the reuse instead of trying to sequence
    // around it, and it is why `command` can go back to being an ordinary
    // binding: it is evaluated at construction, when modeName is by
    // definition already the new one.
    //
    // Toggling the Loader off and on is what destroys the old pair. The
    // `active = false` is not redundant with the reassignment below — a
    // Loader that is already active does not rebuild for a source that has
    // not changed, which would silently reinstate the reuse this exists to
    // end.
    //
    // Clearing `keys` in the same breath means the worst case while a
    // fetch is in flight is an empty grid for one frame, rather than a
    // confidently wrong one.
    onModeNameChanged: {
        root.keys = [];
        fetchLoader.active = false;
        if (root.modeName !== "")
            fetchLoader.active = true;
    }

    Loader {
        id: fetchLoader
        active: false

        sourceComponent: Component {
            Process {
                command: ["python3", root.ctl, "--submap-json", root.modeName]
                running: true
                stdout: StdioCollector {
                    onStreamFinished: {
                        try {
                            const parsed = JSON.parse(text);
                            root.keys = parsed.keys || [];
                        } catch (error) {
                            // A mode with no readable hints is still worth
                            // announcing — knowing you are in a chord at
                            // all is the half that matters most, and it is
                            // the half the old name-only indicator got
                            // right.
                            root.keys = [];
                        }
                    }
                }
            }
        }
    }

    // Three columns for a long chord, two for a short one, one for a tiny
    // one. Chosen by row count rather than fixed, because `rofi` has 26
    // rows and `lang` has 4, and four rows in three columns is one row of
    // three plus a widow.
    readonly property int columns: root.keys.length > 12 ? 3
                                 : (root.keys.length > 5 ? 2 : 1)
    readonly property int rows: Math.ceil(root.keys.length / Math.max(1, root.columns))

    // FORK: 21 -> 25 and 26 -> 32. Screenshotted beside the printed
    // cheatsheet, the HUD's rows were 19 px apart carrying 10 px type in
    // 14 px chips — denser than any other surface in the shell, on the
    // one panel you read while your hand is frozen mid-chord. Density is
    // the wrong currency here: this panel is never longer than 26 rows,
    // it has a whole screen under it, and nothing else competes for the
    // space. The header gets its 32 so the mode name is not sitting on
    // the first row of keys.
    readonly property real rowHeight: Metrics.px(25)
    readonly property real headerHeight: Metrics.px(32)

    // What DynamicIslandWindow asks for when sizing the capsule. Computed
    // here because only this file knows how many rows there are.
    //
    // ---- WHY THERE IS A FALLBACK AND NOT JUST THE ROW COUNT ----
    //
    // MEASURED opening the `rofi` chord, grim frames timed from the IPC
    // call: at t=+70 ms the capsule is at FULL WIDTH and 35 px tall — the
    // header, and nothing else — and at t=+204 ms it is 145 px tall and
    // still growing. Two separate height animations for one open.
    //
    // The cause is structural rather than a mistuned duration. `keys` is
    // cleared the instant modeName changes (see onModeNameChanged, and the
    // good reason it does), the rows come back from `cheatsheet.py` about
    // 130 ms later, and the capsule sizes itself from the row count in
    // between. So the shape animates to "zero rows", then animates again to
    // the real height. Nothing about that reads as one gesture.
    //
    // `pendingHeight` is the height the window remembers for THIS mode from
    // the last time it was opened, handed back in. While the fetch is in
    // flight the panel claims that height instead of its empty one, so the
    // capsule makes a single move to very nearly the right place and the
    // rows land inside it. A first-ever open of a given chord still has
    // nothing to remember and falls back to the row count — one open per
    // mode per session, rather than every open.
    readonly property bool hasKeys: root.keys.length > 0
    property real pendingHeight: 0
    readonly property real measuredHeight: root.headerHeight + root.rows * root.rowHeight
                                           + Metrics.pad(16)
    readonly property real preferredHeight: (!root.hasKeys && root.pendingHeight > 0)
        ? root.pendingHeight
        : root.measuredHeight

    // Emitted once the real rows are in, so the window can remember this
    // mode's height for next time.
    signal measured(string mode, real height)
    onHasKeysChanged: {
        if (root.hasKeys)
            root.measured(root.modeName, root.measuredHeight);
    }

    anchors.fill: parent
    opacity: showCondition ? 1 : 0
    visible: opacity > 0.01

    // FORK: one choreography for every layer in the shell.
    // Was `root.showCondition ? 160 : 100` on Easing.InOutQuad — one of
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

    Text {
        id: title
        x: Metrics.pad(18)
        y: Metrics.pad(10)
        text: root.modeName.toUpperCase()
        color: IslandTheme.textPrimary
        font.family: root.heroFontFamily
        font.pixelSize: Metrics.font(15)
        font.weight: Font.DemiBold
        font.letterSpacing: 0.6
    }

    Text {
        anchors.right: parent.right
        anchors.rightMargin: Metrics.pad(18)
        y: title.y + Metrics.px(3)
        // Every submap here exits on Escape; most also exit on q, and each
        // one's own entry combination toggles it. Escape is the one that is
        // true of all of them, so it is the one worth the pixels.
        text: "Esc"
        color: IslandTheme.textSecondary
        font.family: root.textFontFamily
        font.pixelSize: Metrics.font(11)
    }

    Grid {
        id: grid
        x: Metrics.pad(18)
        y: root.headerHeight
        width: parent.width - Metrics.pad(36)
        columns: root.columns
        rowSpacing: 0
        // FORK: 10 -> 20. Three columns of "CHIP action" with 9 px between
        // them read as one ragged column; the eye needs more gap BETWEEN
        // columns than between a chip and its own label, or the label
        // groups with the wrong chip.
        columnSpacing: Metrics.pad(20)

        Repeater {
            model: root.keys

            Item {
                id: cell
                required property var modelData
                width: (grid.width - grid.columnSpacing * (root.columns - 1)) / root.columns
                height: root.rowHeight

                Rectangle {
                    id: chip
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(Metrics.px(24), label.implicitWidth + Metrics.pad(12))
                    height: Metrics.px(19)
                    radius: Metrics.px(6)
                    color: IslandTheme.surfaceRaisedActive

                    Text {
                        id: label
                        anchors.centerIn: parent
                        text: cell.modelData.key
                        color: IslandTheme.textPrimary
                        font.family: root.textFontFamily
                        font.pixelSize: Metrics.font(11)
                        font.weight: Font.Medium
                    }
                }

                Text {
                    anchors.left: chip.right
                    anchors.leftMargin: Metrics.pad(9)
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: cell.modelData.action
                    color: IslandTheme.textSecondary
                    font.family: root.textFontFamily
                    font.pixelSize: Metrics.font(11)
                    elide: Text.ElideRight
                }
            }
        }
    }
}
