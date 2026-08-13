pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import IslandBackend

// FORK: the shared ring — qml/common/ProgressRing.qml. Three of them here.
import "../common"
// FORK: the shared scale factor — see qml/common/Metrics.js.
import "../common/Metrics.js" as Metrics
// FORK: the shared motion system — one spring for geometry, one critically
// damped curve for opacity. See qml/common/Motion.js.
import "../common/Motion.js" as Motion

//
// FORK — new file. The system monitor: CPU, memory and disk in one panel,
// on $mod+` .
//
// WHY IT EXISTS, AND WHY ON THAT KEY
// ----------------------------------
// hypr/binds.conf already carried the argument, in the comment above the
// binding it replaces. qtile's $mod+` was "toggle 2nd system widget box" —
// the key that meant *show me the system readout*. The migration had nothing
// to point it at, so it was aimed at the control centre as the nearest thing
// whose job is status rather than a task, and the comment said plainly what
// was wrong with that: "the control centre has Volume but no Disk and no
// Updates … disk usage has no home in the island yet. Both are content gaps
// in the panel, not reasons to leave the key dead."
//
// This is the content. The key goes back to meaning what it meant, and the
// control centre keeps $mod+SHIFT+A, which the same comment names as its
// primary binding — so nothing became unreachable.
//
// WHAT IT TOOK FROM ukishima's SysmonSurface, AND WHAT IT DID NOT
// --------------------------------------------------------------
// Taken: the shape of the thing. Dials for the headline percentages with the
// number in the hole and a label under it, a hairline, and a detail strip
// below reading the things a dial cannot say. The two-sample /proc/stat delta
// and the MemAvailable-based memory figure are the same arithmetic, because
// there is only one correct version of both.
//
// Not taken:
//
//   * The colour. ukishima ships one identity and hardcodes a vermillion
//     gradient (Theme.vermBurn -> Theme.vermLit) straight into the arc's
//     paint call. This shell follows theme_mode, so the arcs are
//     StyleTokens.accent and the surface is IslandTheme.shellFill, passed
//     down from DynamicIslandWindow — the capsule's own material. A panel
//     painted a fixed colour that ignores the theme is the repeat complaint
//     in this fork and it is not going to arrive through this file.
//
//   * The kanji. There was a 系 in ukishima's header; the fork's header
//     register is letterspaced uppercase plus a "· status" clause, and the
//     kanji were removed from this shell on request.
//
//   * Its own Canvas. ukishima draws a bespoke 270° arc inline. This shell
//     already has ONE ring — qml/common/ProgressRing.qml, extracted from
//     OsdLayer precisely so the countdown, the volume OSD and the window
//     strip could share it — and a fourth hand-rolled arc would be the thing
//     that extraction existed to prevent. So: a full 360° ring from twelve
//     o'clock, which is what the shared component draws.
//
//   * GPU, VRAM, network and swap dials. GPU is not what was asked for and
//     the detection is a page of shell; network belongs to a different
//     question than "how full is this machine". Swap survives as one line of
//     the memory detail, because it is the number that explains a memory
//     figure that looks wrong.
//
// DISK IS THE ADDITION
// --------------------
// ukishima reports disk as a single "Disk · %" cell for `/` and nothing else.
// On this machine that answers the least interesting third of the question:
// `/` is 32G at 81%, and /home is 202G at 91%. So the disk section is a ROW
// PER FILESYSTEM with its own fill bar, and the third ring follows whichever
// row the cursor is on. That is also the only reason this panel has a cursor
// at all — see the keymap note below.
//
// KEYMAP
// ------
//   j / k · ↓ / ↑   move between filesystems (the DISK ring follows)
//   g / G           first / last filesystem
//   r               re-poll now, without waiting for the timer
//   Escape / q      close
//
// There is deliberately no Return. Every other panel in this shell binds it
// to the thing the row DOES, and a filesystem does not do anything — mounting
// or unmounting one from a status readout would be a surprising amount of
// power on a key you press to dismiss a list. A binding that exists because
// the other panels have one, and then does nothing, is worse than its
// absence.
//
FocusScope {
    id: root

    signal closeRequested

    property bool showCondition: false
    property string textFontFamily: ""
    property string heroFontFamily: ""

    // ---- COLOUR FOLLOWS THE THEME ----
    //
    // Same contract as the Wi-Fi and Bluetooth panels: panelFill is
    // IslandTheme.shellFill handed down by DynamicIslandWindow, and
    // drawBackground is false inside the island because the capsule is
    // already painted in exactly that colour — a second rounded fill at a
    // smaller radius shows as four pale corner wedges. The fill stays so the
    // panel is instantiable on its own and so the colour it WOULD use is
    // written down rather than assumed.
    property color panelFill: IslandTheme.surface
    property color accentColor: IslandTheme.accent
    property bool drawBackground: false

    // --- live readings -----------------------------------------------------
    // Percentages are whole numbers 0..100. They are rendered from these and
    // ANIMATED through a separate 0..1 property per ring, so the arc eases
    // and the digits do not fractionally count up — a percentage read as
    // "57" and an arc that is still travelling toward it are both correct,
    // and a digit tweening through 53, 54, 55 is neither.
    property int cpuPercent: 0
    property int memPercent: 0
    property real memUsedGb: 0
    property real memTotalGb: 0
    property real swapUsedGb: 0
    property real swapTotalGb: 0
    property int coreCount: 0
    property string loadAverage: ""
    property int uptimeSeconds: 0

    // Each entry: { mount, sizeKb, usedKb, availKb, percent }
    property var filesystems: []
    property int selectedIndex: 0

    // /proc/stat is CUMULATIVE jiffies since boot, so a single read says what
    // the machine has done since it started and nothing at all about now. The
    // percentage is the delta between two reads. Which means the FIRST sample
    // after opening the panel can only prime these — there is no previous
    // sample to subtract — and the first number appears one interval later.
    // The header status clause says which of those two states we are in
    // rather than showing a confident 0%.
    property real previousCpuTotal: 0
    property real previousCpuIdle: 0
    readonly property bool sampling: root.previousCpuTotal > 0 && root.cpuSampleCount > 1
    property int cpuSampleCount: 0

    // --- geometry ----------------------------------------------------------
    // FORK: header height, content inset and the key-hint strip are
    // PanelChrome's now. See qml/common/PanelChrome.qml.
    readonly property real ringSize: Metrics.px(86)

    // How many columns the dial row divides into. See Dial.slot.
    readonly property int dialCount: 4

    // --- battery -----------------------------------------------------------
    //
    // Straight off SysBackend, which is where IslandSystemState reads it and
    // therefore the only figure in the shell that can agree with the island's
    // own battery capsule. Not a second /sys/class/power_supply reader: two
    // pollers on one file is how a panel ends up disagreeing with the bar
    // above it by one percent for a few seconds at a time.
    //
    // -1 is "no battery in this machine", and it hides the dial rather than
    // drawing a 0% ring. A desktop showing an empty battery is a fault
    // report, not a reading.
    readonly property int batteryPercent: SysBackend.batteryCapacity
    readonly property string batteryStatus: SysBackend.batteryStatus
    readonly property bool batteryPresent: root.batteryPercent >= 0
    readonly property bool batteryCharging:
        root.batteryStatus === "Charging" || root.batteryStatus === "Full"
    // ---- MEASURED OFF A DIAL, NOT ADDED UP ----
    //
    // This was `ringSize + pad(8) + font(10) + pad(4) + font(11) + pad(4)`,
    // and it was wrong twice over. It counted THREE stacked texts under the
    // ring when the dial draws FOUR (label, detail, sub-detail), and it used
    // the font's pixelSize as the line's height when a Text is taller than
    // its pixelSize by whatever the font's line spacing is — Inter is about
    // 1.2x. Screenshotted: the hairline was drawn straight through "4 cores"
    // and "swap 1.5 GB".
    //
    // Reading the height back off a real dial cannot be wrong in either way,
    // because it is the height the dial actually took. No loop: a Dial's
    // height is built from its ring and its own texts, and nothing in it
    // reads the row's height or the panel's.
    readonly property real ringBlockHeight: cpuDial.height
    readonly property real diskRowHeight: Metrics.px(24)
    readonly property real diskRowSpacing: 2

    // Floors the disk block at two rows so a single-filesystem machine still
    // gets a panel with a section in it rather than a strip with one line.
    readonly property real diskBlockHeight:
        Math.max(2, root.filesystems.length) * (root.diskRowHeight + root.diskRowSpacing) - root.diskRowSpacing

    // Metrics and not chrome.chromeHeight: this sizes the capsule the panel is
    // drawn inside, so reading it off a child of that panel is a loop waiting
    // for one more term.
    readonly property real preferredHeight:
        Metrics.chromeTotal()
        + root.ringBlockHeight
        + Metrics.pad(14) + 1 + Metrics.pad(10)      // hairline and its air
        + root.diskBlockHeight
        + Metrics.pad(2)

    // --- selection ---------------------------------------------------------
    // Re-anchored by MOUNT POINT, not by index, for the reason WifiPanel
    // re-anchors by SSID: `filesystems` is replaced wholesale on every disk
    // poll, and if a filesystem is mounted or unmounted while the panel is
    // open the row under an integer cursor changes identity without the
    // cursor moving. Five seconds is long enough for that to happen while
    // someone is looking at it.
    property string selectedMount: ""

    function selectedFilesystem() {
        if (root.selectedIndex >= 0 && root.selectedIndex < root.filesystems.length)
            return root.filesystems[root.selectedIndex];
        return null;
    }

    function reanchorSelection() {
        if (root.filesystems.length === 0) {
            root.selectedIndex = 0;
            return;
        }
        if (root.selectedMount !== "") {
            for (let i = 0; i < root.filesystems.length; i++) {
                if (root.filesystems[i].mount === root.selectedMount) {
                    root.selectedIndex = i;
                    return;
                }
            }
        }
        root.selectedIndex = Math.max(0, Math.min(root.selectedIndex, root.filesystems.length - 1));
        root.selectedMount = root.filesystems[root.selectedIndex].mount;
    }

    // FORK: the index and the MOUNT are one selection and were being written
    // as two, in three places. `selectedMount` is what reanchorSelection uses
    // to keep the cursor on the same filesystem across a refresh, so an index
    // moved without it silently re-anchors to the wrong row the next time the
    // poll lands. Adding the pointer as a fourth writer of that pair is what
    // made it worth having one.
    function selectAt(index) {
        const count = root.filesystems.length;
        if (count === 0 || index < 0 || index >= count)
            return;
        root.selectedIndex = index;
        root.selectedMount = root.filesystems[index].mount;
    }

    function move(step) {
        const count = root.filesystems.length;
        if (count === 0)
            return;
        // Wraps, for the reason DisplayPanel's does: this list is three rows
        // long on this machine, and `j` stopping dead on the third reads as
        // the key not working rather than as the end of a buffer.
        root.selectAt(((root.selectedIndex + step) % count + count) % count);
    }

    function jump(where) {
        const count = root.filesystems.length;
        if (count === 0)
            return;
        root.selectAt(where === "top" ? 0 : count - 1);
    }

    // --- formatting --------------------------------------------------------
    function formatUptime(seconds) {
        const d = Math.floor(seconds / 86400);
        const h = Math.floor((seconds % 86400) / 3600);
        const m = Math.floor((seconds % 3600) / 60);
        const hh = h < 10 ? "0" + h : String(h);
        const mm = m < 10 ? "0" + m : String(m);
        return "up " + d + "d " + hh + ":" + mm;
    }

    // df reports 1K blocks. Rendered in the unit df -h would have picked, but
    // computed here rather than parsed out of `df -h`, because -h's rounding
    // is lossy in exactly the range where the bar beside it is not.
    //
    // ---- WHY THIS DOES NOT AGREE WITH `df -h` TO THE DIGIT ----
    //
    // df -h rounds UP: this machine's root filesystem is 32716560 blocks =
    // 31.2 GiB and df -h prints "32G". Rounding to whole GB the same way I
    // first did printed "31 GB" beside df's "32G", which is the worst
    // possible outcome — a monitor that looks like it disagrees with the
    // tool everyone checks against, over nothing.
    //
    // The fix is not to copy df's rounding, it is to stop rounding into the
    // ambiguity: one decimal up to 100 GiB, so the panel says 31.2 and the
    // reader can see for themselves that 32G is the same number rounded the
    // other way. Above 100 GiB a tenth is noise and the whole number is back.
    function formatKb(kb) {
        if (kb >= 1048576)
            return (kb / 1048576).toFixed(kb >= 104857600 ? 0 : 1) + " GB";
        if (kb >= 1024)
            return (kb / 1024).toFixed(kb >= 102400 ? 0 : 1) + " MB";
        return kb + " KB";
    }

    // ---- WHY A PERCENTAGE IS FADED AND NOT SPRUNG ----
    //
    // Motion.js's header states the rule and this is the case it is about: a
    // percentage is clamped 0..1, and the spring (zeta 0.8) overshoots by
    // ~1.5% by design. On an arc that runs to 100% the overshoot is clipped
    // flat and the ring visibly throbs at the top of its travel. Geometry
    // only. Everything animated in this file is a value, so everything in it
    // uses fade().
    function ringColorFor(percent) {
        // Tokens, not literals — and the claim this comment used to make is
        // now true. It said StyleTokens.warning and .danger "are theme
        // colours"; they are not, they are C++ constants compiled into
        // libIslandBackendplugin.so, so the ring was as hardcoded as the
        // literal it was congratulating itself for avoiding. IslandTheme's
        // are the palette's own yellow and red, made legible against the
        // surface.
        //
        // Not one of the battery exceptions, despite the same shape: a load
        // ring is a MEASUREMENT that happens to be coloured, whereas the
        // battery bar is read by its colour alone. The ring always shows
        // its number.
        if (percent >= 90)
            return IslandTheme.danger;
        if (percent >= 75)
            return IslandTheme.warning;
        return root.accentColor;
    }

    // The battery's ring runs the other way, and it is the one dial here that
    // is not a load. 90% CPU is the alarming end; 90% battery is the good
    // one. Reusing ringColorFor would paint a full battery red and a nearly
    // dead one in the accent — the exact inversion of what the colour is for.
    //
    // Charging is accent at any level: a battery at 8% that is plugged in is
    // not a problem, and a red ring that stays red while the number climbs
    // trains you to ignore red.
    function batteryRingColor(percent, charging) {
        if (charging)
            return root.accentColor;
        if (percent <= 10)
            return IslandTheme.danger;
        if (percent <= 25)
            return IslandTheme.warning;
        return root.accentColor;
    }

    // --- lifecycle ---------------------------------------------------------
    focus: showCondition
    activeFocusOnTab: true
    anchors.fill: parent
    opacity: showCondition ? 1 : 0

    // FORK: one choreography for every layer in the shell — the same
    // delay-then-critically-damped-fade every other panel uses. See Motion.js.
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

    // ---- POLLING ONLY WHILE OPEN ----
    //
    // Both timers are gated on showCondition. A shell that reads /proc every
    // second for the whole session, to draw a panel nobody has open, is a
    // wakeup per second and a battery cost for a picture of nothing.
    //
    // The CPU delta state is thrown away on close and re-primed on open
    // rather than kept: a delta spanning the twenty minutes the panel was
    // shut is the machine's average over twenty minutes, which would be
    // rendered as though it were "now".
    onShowConditionChanged: {
        if (showCondition) {
            root.previousCpuTotal = 0;
            root.previousCpuIdle = 0;
            root.cpuSampleCount = 0;
            root.pollNow();
            forceActiveFocus();
        }
    }

    // PanelLoader creates this component only once its `live` is true, and
    // `live` and `showCondition` are bound to the SAME expression — so by the
    // time the panel exists, showCondition is already true and
    // onShowConditionChanged never fires for the opening. Without this, the
    // first poll would be the one-second timer's rather than immediate, and
    // the panel would show empty dials for a beat after it appeared.
    //
    // ---- A WRONG THEORY, KEPT ----
    //
    // This block was first written to fix keyboard focus, on the strength of
    // a throwaway logging activeFocus=false. That reading was real and the
    // conclusion drawn from it was wrong: activeFocus was false because the
    // throwaway's own FloatingWindow was not the focused toplevel, not
    // because this FocusScope had failed to take focus. Focusing the window
    // with `hyprctl dispatch focuswindow` flipped it to true with and without
    // this handler, and j/k/g/G/Escape/q were then all driven with wtype and
    // all answered.
    //
    // What actually grants focus is `focus: showCondition` on the FocusScope
    // — true from construction, propagating down the chain islandContainer
    // already holds — which is the same mechanism DisplayPanel and AudioPanel
    // rely on. The forceActiveFocus() below is kept as a belt to that braces,
    // because it costs one call and the failure it would guard is a panel
    // that draws perfectly and eats every key. But the priming poll is the
    // reason this handler earns its place, and the focus call is not.
    Component.onCompleted: {
        if (root.showCondition) {
            root.pollNow();
            root.forceActiveFocus();
        }
    }

    function pollNow() {
        if (!procProcess.running)
            procProcess.running = true;
        if (!diskProcess.running)
            diskProcess.running = true;
    }

    // ---- WHY SplitParser AND NOT StdioCollector ----
    //
    // A Process reused for a second run with a StdioCollector on it hands
    // back the PREVIOUS run's text — measured in this shell, and it is the
    // trap that matters most for a panel whose whole job is to re-run the
    // same command every second. The symptom would be a monitor that renders
    // beautifully and is one interval stale forever, which is the hardest
    // kind of wrong to see on a number that changes anyway.
    //
    // SplitParser is line-oriented and fires as each line arrives, so there
    // is no accumulated buffer to go stale. It is also already the fork's
    // proven idiom for a repeated poll: IslandSystemState's storagePollProcess
    // has been running `df` on a 10 s timer through one of these since before
    // this file existed.
    //
    // The cost is that a parser sees lines, not a run, so anything spanning
    // more than one line needs its own framing — hence DISKBEGIN/DISKEND
    // below.
    Process {
        id: procProcess
        running: false
        command: ["sh", "-c",
            // /proc/stat's first line is `cpu` then the per-mode jiffy
            // counters: user nice system idle iowait irq softirq steal.
            // Busy is total minus (idle + iowait) — iowait counts as idle
            // here because a core waiting on the disk is not computing, and
            // calling it busy is how a monitor reports 100% during a file
            // copy that is using no CPU at all.
            "read -r _ a b c d e f g h _ < /proc/stat; echo \"CPU $((a+b+c+d+e+f+g+h)) $((d+e))\"; "
            // MemAvailable, not MemFree. MemFree on this machine reads 415 MB
            // against 3.3 GB actually available, because the difference is
            // reclaimable page cache — a memory gauge built on MemFree reads
            // 95% on an idle laptop and is the single most common way to get
            // this number wrong.
            + "awk '/^MemTotal:/{mt=$2}/^MemAvailable:/{ma=$2}/^SwapTotal:/{st=$2}/^SwapFree:/{sf=$2}END{print \"MEM\",mt,ma,st,sf}' /proc/meminfo; "
            + "awk '{print \"UP\",int($1)}' /proc/uptime; "
            + "awk '{print \"LOAD\",$1,$2,$3}' /proc/loadavg; "
            + "echo \"CORES $(nproc)\""]

        stdout: SplitParser {
            onRead: function(line) {
                const parts = String(line).trim().split(/\s+/);
                if (parts.length === 0)
                    return;
                if (parts[0] === "CPU") {
                    const total = parseFloat(parts[1]);
                    const idle = parseFloat(parts[2]);
                    if (root.previousCpuTotal > 0) {
                        const deltaTotal = total - root.previousCpuTotal;
                        const deltaIdle = idle - root.previousCpuIdle;
                        // A zero or negative delta means two reads landed in
                        // the same jiffy, or the counters wrapped. Holding the
                        // previous value is right: there is no measurement,
                        // and rendering 0% would be a claim rather than a gap.
                        if (deltaTotal > 0)
                            root.cpuPercent = Math.max(0, Math.min(100,
                                Math.round(100 * (deltaTotal - deltaIdle) / deltaTotal)));
                    }
                    root.previousCpuTotal = total;
                    root.previousCpuIdle = idle;
                    root.cpuSampleCount += 1;
                } else if (parts[0] === "MEM") {
                    const memTotal = parseFloat(parts[1]);
                    const memAvailable = parseFloat(parts[2]);
                    const swapTotal = parseFloat(parts[3]);
                    const swapFree = parseFloat(parts[4]);
                    root.memTotalGb = memTotal / 1048576;
                    root.memUsedGb = (memTotal - memAvailable) / 1048576;
                    root.memPercent = memTotal > 0
                        ? Math.round(100 * (memTotal - memAvailable) / memTotal)
                        : 0;
                    root.swapTotalGb = swapTotal / 1048576;
                    root.swapUsedGb = (swapTotal - swapFree) / 1048576;
                } else if (parts[0] === "UP") {
                    root.uptimeSeconds = parseInt(parts[1], 10) || 0;
                } else if (parts[0] === "LOAD") {
                    root.loadAverage = parts[1] + " " + parts[2] + " " + parts[3];
                } else if (parts[0] === "CORES") {
                    root.coreCount = parseInt(parts[1], 10) || 0;
                }
            }
        }
    }

    // The disk poll is framed by sentinels because it is the one reading
    // that spans an unknown number of lines. Rows accumulate into a scratch
    // array from DISKBEGIN and are published in ONE assignment at DISKEND —
    // never appended to `filesystems` directly.
    //
    // That is not tidiness. `filesystems` feeds a Repeater, a binding
    // re-evaluates whenever anything it reads changes, and rebuilding a model
    // destroys every delegate: publishing per line would tear down and
    // rebuild the whole disk section three times per poll, which in this
    // shell has already produced one visible flicker on a different list.
    // One assignment per poll is one rebuild per poll.
    property var pendingFilesystems: []

    Process {
        id: diskProcess
        running: false
        command: ["sh", "-c",
            "echo DISKBEGIN; "
            // -P is the POSIX single-line-per-filesystem format: a long
            // device name wraps onto two lines in the default output and
            // every field then lands one column off.
            //
            // The -x list drops the pseudo filesystems. Without it this panel
            // reports /run, /dev/shm, /tmp and half a dozen per-user
            // /run/user/1000 mounts as "disks", which is both untrue and
            // eight rows of noise ahead of the three that are real.
            + "df -P -x tmpfs -x devtmpfs -x efivarfs -x squashfs -x overlay -x ramfs -x fuse.portal 2>/dev/null "
            + "| awk 'NR>1{gsub(\"%\",\"\",$5); print \"DISK\",$6,$2,$3,$4,$5}'; "
            + "echo DISKEND"]

        stdout: SplitParser {
            onRead: function(line) {
                const trimmed = String(line).trim();
                if (trimmed === "DISKBEGIN") {
                    root.pendingFilesystems = [];
                    return;
                }
                if (trimmed === "DISKEND") {
                    root.filesystems = root.pendingFilesystems;
                    root.reanchorSelection();
                    return;
                }
                const parts = trimmed.split(/\s+/);
                if (parts[0] !== "DISK" || parts.length < 6)
                    return;
                const next = root.pendingFilesystems.slice();
                next.push({
                    mount: parts[1],
                    sizeKb: parseFloat(parts[2]) || 0,
                    usedKb: parseFloat(parts[3]) || 0,
                    availKb: parseFloat(parts[4]) || 0,
                    percent: parseInt(parts[5], 10) || 0
                });
                root.pendingFilesystems = next;
            }
        }
    }

    // One second for CPU and memory: the CPU figure IS the interval, since it
    // is the delta across it, and a shorter window turns a scheduler hiccup
    // into a spike while a longer one smooths away the thing you opened the
    // panel to see.
    Timer {
        interval: 1000
        repeat: true
        running: root.showCondition
        onTriggered: if (!procProcess.running) procProcess.running = true
    }

    // Five for disk, on its own timer rather than folded into the fast one.
    // `df` stats every mounted filesystem and can block on a slow or
    // unresponsive one; behind the same timer as /proc it would stall the CPU
    // arc, and the whole point of splitting the cadences is that a slow
    // source never freezes a fast dial. Disk also does not move in a second.
    Timer {
        interval: 5000
        repeat: true
        running: root.showCondition
        onTriggered: if (!diskProcess.running) diskProcess.running = true
    }

    // --- keys --------------------------------------------------------------
    // The same convention as AudioPanel and DisplayPanel, key for key as far
    // as this panel has meanings for them. No second convention.
    Keys.onPressed: function(event) {
        const shift = (event.modifiers & Qt.ShiftModifier) !== 0;

        switch (event.key) {
        case Qt.Key_Escape:
        case Qt.Key_Q:
            root.closeRequested();
            break;
        case Qt.Key_J:
        case Qt.Key_Down:
            root.move(1);
            break;
        case Qt.Key_K:
        case Qt.Key_Up:
            root.move(-1);
            break;
        case Qt.Key_G:
            root.jump(shift ? "bottom" : "top");
            break;
        case Qt.Key_R:
            root.pollNow();
            break;
        default:
            return;
        }
        event.accepted = true;
    }

    // The standalone-render capsule is PanelChrome's now.

    // --- chrome ------------------------------------------------------------
    //
    // ---- THE HEADER REGISTER ----
    //
    // Letterspaced uppercase well below title size, then a "· status" clause
    // that carries the accent only when something is live. It reads as a
    // label on an instrument rather than as a window title. No kanji — there
    // was a 系 in the surface this is adapted from and it does not come with
    // ---- CHROME, SHARED ---- see qml/common/PanelChrome.qml.
    PanelChrome {
        id: chrome
        textFontFamily: root.textFontFamily
        drawBackground: root.drawBackground
        panelFill: root.panelFill

        title: "system"

        // "live" here has a precise meaning and it is not decorative: until
        // two /proc/stat samples have landed there is no CPU measurement at
        // all, only a primed counter. The clause says which of those two the
        // dials are showing, and takes the accent only in the second.
        statusClause: root.sampling ? "· sampling" : "· priming"
        statusClauseLive: root.sampling

        // The right-hand slot, where the audio, display and connectivity
        // panels put what the panel is doing. This panel is never doing
        // anything — it only reads — so the slot carries the one fact that
        // contextualises every number under it: how long the machine has been
        // accumulating them.
        status: root.uptimeSeconds > 0 ? root.formatUptime(root.uptimeSeconds) : ""
        statusLevel: "idle"

        hints: [
            { key: "j/k", label: "filesystem" },
            { key: "g/G", label: "first-last" },
            { key: "r", label: "refresh" },
            { key: "q", label: "close" }
        ]
    }

    // --- the three dials ---------------------------------------------------
    //
    // A component rather than three copies, because the only differences are
    // the number, two strings and the colour rule — and three copies of a
    // ring is how a shell ends up with three rings that disagree about their
    // stroke width.
    component Dial: Item {
        id: dial

        property int percent: 0
        property string label: ""
        property string detail: ""
        property string subDetail: ""

        // Overridable so the battery can invert the ramp. Defaults to the
        // load ramp, which is what the other three want.
        property color ringColor: root.ringColorFor(dial.percent)

        // 0-based slot in the dial row. The row divides its width into
        // `dialCount` equal columns and centres each dial in its own — which
        // is not what this row did when it had three. It pinned them to
        // x=0 / centre / right edge, so the OUTER two hung their detail text
        // off the ends of the content box and the gaps between them were
        // whatever was left. That works for exactly three and for no other
        // number, and a fourth dial made it obvious. Equal columns instead:
        // every dial gets the same width, the text centres under its own ring
        // rather than over its neighbour, and adding a fifth is one constant.
        property int slot: 0
        x: dialRow.width * (dial.slot + 0.5) / root.dialCount - dial.width / 2

        // The animated 0..1 the ring actually draws, kept separate from
        // `percent` so the arc eases while the digits step. Faded, never
        // sprung — see ringColorFor's note; this is the clamped value the
        // Motion.js header is about.
        property real shown: 0
        onPercentChanged: dial.shown = dial.percent / 100
        Component.onCompleted: dial.shown = dial.percent / 100
        Behavior on shown {
            NumberAnimation {
                duration: Motion.fadeDuration()
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Motion.fade()
            }
        }

        width: root.ringSize
        // Sized from its own last line, so the block below the dials can be
        // placed against something real. See ringBlockHeight.
        height: subDetailText.y + subDetailText.height

        ProgressRing {
            id: ring
            anchors.horizontalCenter: parent.horizontalCenter
            y: 0
            width: root.ringSize
            height: root.ringSize
            // Off: the OSD's ring floats over the desktop and needs a dark
            // disc to sit on. This one is already over the capsule's own
            // material, and the disc would only fight the number in the hole.
            showCore: false
            lineWidth: Metrics.px(6)
            progress: dial.shown
            // Through `dial.ringColor` rather than calling ringColorFor here,
            // so the battery dial can supply its own inverted ramp. The
            // default IS ringColorFor, so the three load dials are unchanged.
            fillColor: dial.ringColor
            // The arc's own colour at low alpha, not a grey: a track in a
            // fixed grey drifts away from the arc as the theme moves, and on
            // a light accent it reads as a second, darker ring.
            trackColor: Qt.rgba(dial.ringColor.r, dial.ringColor.g,
                                dial.ringColor.b, 0.18)

            Row {
                anchors.centerIn: parent
                spacing: 1

                Text {
                    id: percentText
                    text: String(dial.percent)
                    color: IslandTheme.textPrimary
                    font.family: root.heroFontFamily
                    font.pixelSize: Metrics.font(19)
                    font.weight: Font.DemiBold
                    // Tabular figures: without them the ring's centre shifts
                    // sideways every time the value crosses a digit whose
                    // advance width differs, which on a number updating once
                    // a second reads as a wobble.
                    font.features: ({ "tnum": 1 })
                }
                Text {
                    anchors.baseline: percentText.baseline
                    text: "%"
                    color: IslandTheme.textMuted
                    font.family: root.textFontFamily
                    font.pixelSize: Metrics.font(10)
                    font.weight: Font.DemiBold
                }
            }
        }

        Text {
            id: dialLabel
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: ring.bottom
            anchors.topMargin: Metrics.pad(8)
            text: dial.label
            color: IslandTheme.textMuted
            font.family: root.textFontFamily
            font.pixelSize: Metrics.font(10)
            font.weight: Font.DemiBold
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 1.2
        }

        Text {
            id: dialDetail
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: dialLabel.bottom
            anchors.topMargin: Metrics.pad(4)
            text: dial.detail
            color: IslandTheme.textSecondary
            font.family: root.textFontFamily
            font.pixelSize: Metrics.font(11)
            font.features: ({ "tnum": 1 })
        }

        Text {
            id: subDetailText
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: dialDetail.bottom
            anchors.topMargin: Metrics.pad(2)
            // `visible`, not a zero height: the memory dial's swap line comes
            // and goes with whether any swap is in use, and a dial that
            // changed height when swap crossed 0.05 GB would shove the
            // hairline and the whole disk section up and down under it.
            visible: dial.subDetail !== ""
            text: dial.subDetail
            color: IslandTheme.textMuted
            font.family: root.textFontFamily
            font.pixelSize: Metrics.font(10)
            font.features: ({ "tnum": 1 })
        }
    }

    Item {
        id: dialRow
        x: chrome.contentX
        y: chrome.contentY
        width: chrome.contentWidth
        height: root.ringBlockHeight

        Dial {
            id: cpuDial
            slot: 0
            percent: root.cpuPercent
            label: "CPU"
            detail: root.loadAverage === "" ? "" : root.loadAverage.split(" ")[0] + " load"
            subDetail: root.coreCount > 0 ? root.coreCount + " cores" : ""
        }

        Dial {
            id: memDial
            slot: 1
            percent: root.memPercent
            label: "Memory"
            detail: root.memTotalGb > 0
                ? root.memUsedGb.toFixed(1) + " / " + root.memTotalGb.toFixed(1) + " GB"
                : ""
            // Swap is shown only when some is in use. A permanent "0.0 GB
            // swap" line is a row of chrome that never says anything; the
            // moment it is non-zero it is the line that explains a memory
            // figure which otherwise looks impossible.
            subDetail: root.swapUsedGb >= 0.05
                ? "swap " + root.swapUsedGb.toFixed(1) + " GB"
                : ""
        }

        Dial {
            id: diskDial
            slot: 2
            percent: {
                const fs = root.selectedFilesystem();
                return fs ? fs.percent : 0;
            }
            label: "Disk"
            detail: {
                const fs = root.selectedFilesystem();
                return fs ? root.formatKb(fs.usedKb) + " / " + root.formatKb(fs.sizeKb) : "";
            }
            // "on /", not a bare "/". Screenshotted as the bare mount and it
            // read as a stray slash under a size rather than as the subject
            // of the dial — at Metrics.font(10) a one-character path is
            // indistinguishable from a rendering fault. The preposition costs
            // three characters and makes the line a sentence.
            subDetail: {
                const fs = root.selectedFilesystem();
                return fs ? "on " + fs.mount : "";
            }
        }

        Dial {
            id: batteryDial
            slot: 3
            // Hidden, not zeroed, on a machine with no battery. See
            // root.batteryPresent.
            visible: root.batteryPresent
            percent: Math.max(0, Math.min(100, root.batteryPercent))
            label: "Battery"
            ringColor: root.batteryRingColor(batteryDial.percent,
                                             root.batteryCharging)
            // The status word, lowercased, because the label above it is
            // already shouting in caps and two levels of emphasis on a
            // four-word column is one too many. SysBackend hands these
            // through from /sys as "Discharging", "Charging", "Full",
            // "Not charging" -- passed through rather than mapped, so an
            // unexpected state shows up as itself instead of as "unknown".
            detail: root.batteryStatus === ""
                ? "" : root.batteryStatus.toLowerCase()
            // Deliberately empty. The other three dials use the third line
            // for a second measurement (cores, swap, mount); the battery's
            // second measurement is time-to-empty, which SysBackend does not
            // expose, and inventing it from a percentage delta is how you get
            // a "3 h left" that changes to "40 min" when a build starts.
            subDetail: ""
        }
    }

    Rectangle {
        id: hairline
        x: chrome.contentX
        y: dialRow.y + dialRow.height + Metrics.pad(14)
        width: chrome.contentWidth
        height: 1
        // This was an explicit Qt.rgba(1, 1, 1, 0.08), carrying a note that
        // StyleTokens.hairline does not exist and that an unknown property
        // on a QML singleton is not an error — it resolves to `undefined`,
        // which a `color` silently accepts as transparent, so the separator
        // would have been absent with nothing in the log to say so.
        //
        // The trap is real and still worth knowing; it no longer applies.
        // IslandTheme.hairline exists, and being a token it also inverts on
        // a light palette, which a literal white at 0.08 cannot. 0.13 rather
        // than 0.08 because one hairline for the shell is the point, and
        // this was the fainter of the two values that were in use.
        color: IslandTheme.hairline
    }

    // --- the disk section --------------------------------------------------
    Column {
        id: diskColumn
        x: chrome.contentX
        y: hairline.y + 1 + Metrics.pad(10)
        width: chrome.contentWidth
        spacing: root.diskRowSpacing

        Repeater {
            model: root.filesystems

            delegate: PanelRow {
                id: diskRow
                required property int index
                required property var modelData

                width: diskColumn.width
                height: root.diskRowHeight

                // `active` is never set on this list: a filesystem is not in a
                // state the way a connected network or a default sink is —
                // they are all equally mounted — so the only mark here is the
                // cursor. That also moves this row off `IslandTheme.selectionFill`,
                // which was the accent wash, i.e. the shell's "this is a state"
                // colour used for the one thing on this panel that is not one.
                //
                // FORK: P1-3 — HOVER MOVES THE CURSOR, one indicator driven by
                // both input devices. This panel had no MouseArea at all, so
                // the ring and the detail readout could only be pointed at a
                // different filesystem with j/k.
                //
                // `activated` is deliberately NOT connected: the selection IS
                // the whole interaction here, and there is nothing a click
                // could commit that the hover has not already done.
                selected: diskRow.index === root.selectedIndex
                onCursorRequested: root.selectAt(diskRow.index)

                Text {
                    id: mountText
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: Metrics.px(90)
                    elide: Text.ElideMiddle
                    text: diskRow.modelData.mount
                    color: diskRow.index === root.selectedIndex
                        ? IslandTheme.textPrimary
                        : IslandTheme.textSecondary
                    font.family: root.textFontFamily
                    font.pixelSize: Metrics.font(11)
                }

                // The bar and the ring are the same reading twice, and that
                // is the point: the ring answers "how full is the one I am
                // looking at", the bars answer "which of these is the
                // problem" without moving the cursor onto each in turn.
                Rectangle {
                    id: barTrack
                    anchors.left: mountText.right
                    anchors.leftMargin: Metrics.pad(10)
                    anchors.verticalCenter: parent.verticalCenter
                    width: Metrics.px(150)
                    height: Metrics.px(5)
                    radius: height / 2
                    color: IslandTheme.trackSubtle

                    Rectangle {
                        height: parent.height
                        radius: parent.radius
                        width: parent.width * Math.max(0, Math.min(1, diskRow.modelData.percent / 100))
                        color: root.ringColorFor(diskRow.modelData.percent)
                        // Faded, not sprung: a fill width driven by a
                        // percentage is the same clamped value the dials are,
                        // and a bar that overshoots its own track paints
                        // outside it.
                        Behavior on width {
                            NumberAnimation {
                                duration: Motion.fadeDuration()
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Motion.fade()
                            }
                        }
                    }
                }

                Text {
                    id: barPercent
                    anchors.left: barTrack.right
                    anchors.leftMargin: Metrics.pad(10)
                    anchors.verticalCenter: parent.verticalCenter
                    width: Metrics.px(34)
                    horizontalAlignment: Text.AlignRight
                    text: diskRow.modelData.percent + "%"
                    color: root.ringColorFor(diskRow.modelData.percent)
                    font.family: root.textFontFamily
                    font.pixelSize: Metrics.font(11)
                    font.weight: Font.DemiBold
                    font.features: ({ "tnum": 1 })
                }

                // Free, not used. `used` is already the bar and the percent;
                // the number a person opens a disk readout to find is how
                // much room is left.
                Text {
                    anchors.left: barPercent.right
                    anchors.leftMargin: Metrics.pad(14)
                    anchors.right: parent.right
                    anchors.rightMargin: Metrics.pad(10)
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideRight
                    text: root.formatKb(diskRow.modelData.availKb) + " free"
                    color: IslandTheme.textMuted
                    font.family: root.textFontFamily
                    font.pixelSize: Metrics.font(11)
                    font.features: ({ "tnum": 1 })
                }
            }
        }
    }

    // The key-hint Text that used to close this file is `chrome.hints` now.
}
