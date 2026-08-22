import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.UPower

//
// DIRECTION E — real app icons, consolidated stats toggle, battery redone,
// chord pill restyled, lamp reordered
// ============================================================================
// Standalone preview: `qs -p redesign-e-final.qml`. Click the stats icon on
// the right (the one with "<" beside it) — it actually expands, this isn't
// just a picture of the idea.
//
// CHANGES FROM D
// --------------
// 1. Workspace icons are smaller (ActivatableIcon now takes a `size`).
// 2. Open windows are REAL app icons (Quickshell.iconPath, the same call
//    tide-island-fork/qml/island/WindowRingStrip.qml uses for its own
//    icon-strip), stacked like a shingled pile of cards — diagonal offset,
//    not the circular fan that read as "tribal" before. Kitty/code/firefox
//    icons confirmed resolving on this system before using them here.
// 3. GUESS, FLAGGED: "the layout icon should appear when I switch to a
//    workspace, like '</> | []'" — read as "pair the layout glyph with
//    the ACTIVE workspace icon" rather than "own persistent slot at the
//    end of the strip", since a layout is a per-workspace property. That's
//    what's built below; if that's not what was meant, easy to redo once
//    it's clear which reading is right.
// 4. The chord/submap pill is now the same rounded-rect plate as every
//    other Strip (radius 8, translucent bg, hairline border) instead of a
//    fully filled oval — the mode still reads via the text colour, not a
//    block of solid colour.
// 5. (Can't demo in a static mock: the SAME fix — Strip's exact styling —
//    applies to shell.qml's separate fullscreen ModeChip, which currently
//    uses its own plate math.)
// 6. Battery is a stack now: the percentage sits above the glyph, "[100]"
//    read literally as number-over-icon rather than icon-then-text.
// 7. CPU/mem + updates/disk/volume collapse into ONE glyph with one "<".
//    It is wired to a real MouseArea — click it and it actually expands
//    a small CPU/RAM/volume readout inline. mod+` already toggles the
//    second stats box in the real bar (binds.conf: `bind = $mod, grave,
//    exec, ati-bar-action bar secondBox`) — same box, same key, this is
//    just its new shape.
// 8. The lamp/tips glyph moved to be the last button in its cluster,
//    after wallpaper, instead of leading it.
ShellRoot {
    id: demo

    // ============================================================
    // REAL DATA — this file was a static mock through every earlier
    // round; "when I switch workspace it should behave dynamic like
    // the current bar" was a fair complaint. This section ports the
    // ACTUAL working data sources shell.qml/Workspaces.qml/
    // LayoutState.qml already use — same Process calls, same file
    // paths, same Hyprland event names — rather than inventing a new
    // mechanism. What's still NOT wired: the open-window app stack
    // (needs the toplevel/appId model tide-island-fork's
    // WindowRingStrip.qml uses, which is a bigger port on its own)
    // and CPU/RAM/volume/brightness (no existing live source was
    // read for these, so they stay mock values with real click
    // actions, as before).
    // ============================================================

    // ---- WORKSPACES — hyprctl -j workspaces / activeworkspace, exactly
    // as Workspaces.qml does it and for the same documented reason:
    // Hyprland.workspaces (the built-in model) doesn't populate reliably.
    property var wsList: []
    property int focusedWsId: -999

    // 6 and 7 deliberately have no entry: asked for directly ("6 and 7 no
    // icon pls") -- they show the plain workspace number instead. 7 having
    // no icon was also silently falling through iconForWs's old default to
    // 0xF0E7, workspace 1's OWN icon, i.e. workspace 7 rendered as a second
    // "1" -- the same "workspace 1 appeared twice" class of bug as the "S"
    // scratchpad fix above, just never reported because nothing occupies 7
    // often enough to notice.
    readonly property var wsIcons: ({
        "1": 0xF0E7, "2": 0xF03D, "3": 0xF07C, "4": 0xF121, "5": 0xF0AC,
        "8": 0xF02D, "9": 0xF2C6
    })
    function hasIconForWs(name) {
        return demo.wsIcons[String(name)] !== undefined;
    }
    function iconForWs(name) {
        const n = String(name);
        return demo.wsIcons[n] !== undefined ? demo.wsIcons[n] : 0xF0E7;
    }

    Process {
        id: wsProc
        command: ["hyprctl", "-j", "workspaces"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    // "S" (id -1337) is the scratchpad, not a real
                    // workspace — Workspaces.qml filters it by NAME for
                    // the same reason (id>0 alone can't tell a group from
                    // a scratchpad, since named workspaces are negative
                    // too). Missing this is exactly why "workspace 1
                    // appeared twice": with no entry in wsIcons, "S"
                    // fell through to the SAME default glyph as "1", and
                    // both were occupied at once — two different
                    // workspaces that happened to render identically,
                    // not a real duplicate.
                    const list = JSON.parse(text).filter(
                        (w) => String(w.name).indexOf("special:") !== 0
                            && String(w.name) !== "S");
                    list.sort((a, b) => a.id - b.id);
                    demo.wsList = list;
                } catch (e) { /* keep the last good list */ }
            }
        }
    }
    Process {
        id: activeWsProc
        command: ["hyprctl", "-j", "activeworkspace"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { demo.focusedWsId = JSON.parse(text).id; } catch (e) {}
            }
        }
    }
    // ---- WHAT'S OPEN, PER WORKSPACE — real now. Was a fixed mock list
    // (["kitty","firefox","code"]) since the very first pass; asked
    // directly, three times over, to make it the apps actually open on
    // the CURRENT workspace. `hyprctl -j clients` gives every window's
    // class and its workspace id together, so this is one Process rather
    // than tide-island-fork/qml/island/WindowRingStrip.qml's
    // Hyprland.toplevels model (that model lives in a different file this
    // one can't import — see TourPopup.qml's own header on why — and
    // hyprctl -j is the same real-data pattern demo.wsList/focusedWsId
    // already use here). `activewindow` in the same call is what makes
    // `wsActiveIndex` real instead of just "the last one".
    property var wsApps: []
    property int wsActiveIndex: -1
    // WindowRingStrip.qml's own alias table, ported: three of this
    // user's own scratchpad kitty windows (--class scratch-term1/2,
    // sum-md) have no desktop entry and no icon of that name — they ARE
    // kitty, verified by that file's own comment reading `comm` off each
    // window's pid.
    readonly property var appIdAliases: ({
        "scratch-term1": "kitty",
        "scratch-term2": "kitty",
        "sum-md": "kitty"
    })
    Process {
        id: wsAppsProc
        command: ["sh", "-c",
            "hyprctl -j clients; echo '::ACTIVE::'; hyprctl -j activewindow; "
            + "echo '::MON::'; hyprctl -j monitors"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parts = text.split("::ACTIVE::");
                    const clients = JSON.parse(parts[0]);
                    const rest = parts[1].split("::MON::");
                    const active = rest[0] && rest[0].trim() !== "" ? JSON.parse(rest[0]) : null;
                    const monitors = JSON.parse(rest[1]);
                    const mon = monitors.find((m) => m.focused) || monitors[0] || null;

                    // "why the file icon there i dont have anything just
                    // this terminal" — qdrop IS a real window (hyprctl
                    // confirmed it), but a floating scratchpad tool PARKED
                    // OFF-SCREEN waiting to be summoned (its own `at`:
                    // negative Y, well above the visible monitor). A
                    // window whose box doesn't overlap the monitor at all
                    // isn't something you can actually see, so it isn't
                    // "an open app" any more than an unmapped one is.
                    const onScreen = (c) => {
                        if (!mon || !c.at || !c.size) return true;
                        const [x, y] = c.at, [w, h] = c.size;
                        return x + w > 0 && y + h > 0 && x < mon.width && y < mon.height;
                    };

                    const onWs = clients.filter((c) =>
                        c.workspace && c.workspace.id === demo.focusedWsId && onScreen(c));
                    const alias = (cls) => demo.appIdAliases[cls] || demo.appIdAliases[String(cls).toLowerCase()] || cls;
                    const rawIds = onWs.map((c) => alias(c.class || c.initialClass || ""));

                    // "the opened icons in the bar if the same icon opens
                    // so put the icon once and write '+then the number'" —
                    // three kitty windows used to mean three identical
                    // kitty icons in a row. Grouped by appId instead,
                    // first-seen order, each group carrying its own count;
                    // AppFileStack draws the "+N" badge itself when
                    // count > 1.
                    const groups = [];
                    const groupIndexOf = {};
                    rawIds.forEach((id) => {
                        if (groupIndexOf[id] === undefined) {
                            groupIndexOf[id] = groups.length;
                            groups.push({ appId: id, count: 1 });
                        } else {
                            groups[groupIndexOf[id]].count += 1;
                        }
                    });
                    demo.wsApps = groups;

                    const activeRawIndex = active
                        ? onWs.findIndex((c) => c.address === active.address) : -1;
                    demo.wsActiveIndex = activeRawIndex >= 0
                        ? groupIndexOf[rawIds[activeRawIndex]] : -1;
                } catch (e) { /* keep the last good list */ }
            }
        }
    }
    function refreshWs() { wsProc.running = true; activeWsProc.running = true; wsAppsProc.running = true; }

    // ---- KEYBOARD LAYOUT — real readback, not a hardcoded "EN". Asked
    // for directly ("EN not switching to ar/en/tr"): submaps.conf's own
    // `lang` submap is how this setup actually changes layout (E/A/T/D
    // inside mod+space, not a next/prev cycle), so the click below opens
    // THAT submap rather than guessing at switchxkblayout's cycle order,
    // and this poll is what makes the label ever say anything but "EN".
    property string layoutCode: "EN"
    Process {
        id: kbProc
        command: ["hyprctl", "-j", "devices"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const kbs = JSON.parse(text).keyboards || [];
                    const main = kbs.find((k) => k.main) || kbs[0];
                    if (main && main.active_keymap)
                        demo.layoutCode = String(main.active_keymap).slice(0, 2).toUpperCase();
                } catch (e) {}
            }
        }
    }
    // 2000ms made a real switch look "too slow" — up to two full seconds
    // between the click and the label catching up, since a poll-only
    // readback has no idea a click just happened. The click handler below
    // now fires an immediate re-poll (kbPollSoon, a short one-shot) instead
    // of waiting for this to come back around; this interval is now only
    // the fallback for a layout change from OUTSIDE this bar (the `lang`
    // submap, another keyboard shortcut), so it can drop from "must feel
    // instant" to "just needs to eventually notice".
    Timer { interval: 800; running: true; repeat: true; onTriggered: kbProc.running = true }
    // hyprctl needs a beat after switchxkblayout actually lands before
    // `devices` reports the new active_keymap — polling with zero delay
    // read back the layout that was just replaced. 120ms is short enough
    // to read as instant and long enough that it wasn't caught stale in
    // repeated testing.
    Timer { id: kbPollSoon; interval: 120; repeat: false; onTriggered: kbProc.running = true }

    // ---- CPU / MEMORY / VOLUME / BRIGHTNESS — real now, the mock
    // "4.2G"/"12%"/"65%"/"80%" strings replaced with shell.qml's own
    // sources (CPU/mem straight off /proc, no shelling out — its own
    // comment audits every timer on that bar and this copies its numbers:
    // 2s for CPU/mem, 2s + an 80ms debounced re-check for volume). Only
    // brightness has no shell.qml equivalent to copy — that stat was
    // "invented for this mock's 4-stat layout" from the start — so it's
    // sourced fresh from `brightnessctl -m`, polled the same way.
    property string statMem: "--"
    property string statCpu: "--"
    property string statVolume: "--"
    property string statBrightness: "--"
    property real _cpuLastIdle: 0
    property real _cpuLastTotal: 0

    FileView { id: statFile; path: "/proc/stat"; printErrors: false }
    FileView { id: memFile; path: "/proc/meminfo"; printErrors: false }

    Timer {
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: { statFile.reload(); memFile.reload(); }
    }

    Connections {
        target: statFile
        function onLoaded() {
            const line = statFile.text().split("\n")[0];
            const f = line.trim().split(/\s+/).slice(1).map(Number);
            if (f.length < 4) return;
            const idle = f[3] + (f[4] || 0);
            const total = f.reduce((a, b) => a + b, 0);
            const dT = total - demo._cpuLastTotal;
            const dI = idle - demo._cpuLastIdle;
            demo._cpuLastTotal = total;
            demo._cpuLastIdle = idle;
            if (dT > 0 && dI >= 0)
                demo.statCpu = Math.max(0, Math.min(100, Math.round(100 * (1 - dI / dT)))) + "%";
        }
    }

    Connections {
        target: memFile
        function onLoaded() {
            const t = memFile.text();
            const grab = (k) => {
                const m = t.match(new RegExp("^" + k + ":\\s+(\\d+)", "m"));
                return m ? parseInt(m[1], 10) : 0;
            };
            const total = grab("MemTotal");
            const avail = grab("MemAvailable");
            if (!total) return;
            const usedGb = (total - avail) / 1024 / 1024;
            demo.statMem = usedGb.toFixed(1) + "G";
        }
    }

    Process {
        id: volProc
        command: ["sh", "-c",
            "wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null || pactl get-sink-volume @DEFAULT_SINK@"]
        stdout: StdioCollector {
            onStreamFinished: {
                const t = text.trim();
                if (t.indexOf("MUTED") >= 0) { demo.statVolume = "mute"; return; }
                const m = t.match(/([0-9]*\.?[0-9]+)/);
                if (m) demo.statVolume = Math.round(parseFloat(m[1]) * 100) + "%";
            }
        }
    }
    Timer { interval: 2000; running: true; repeat: true; triggeredOnStart: true; onTriggered: volProc.running = true }
    // Debounced re-check after THIS bar's own volume click, same shape as
    // shell.qml's volumeSoon()/volSoon — a chip whose own action changes
    // the number it displays gets an immediate re-read, not just the 2s
    // poll's eventual catch-up.
    Timer { id: volPollSoon; interval: 80; repeat: false; onTriggered: volProc.running = true }

    Process {
        id: brightnessProc
        command: ["sh", "-c", "brightnessctl -m 2>/dev/null | cut -d, -f4 | tr -d '%'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const pct = parseInt(text.trim(), 10);
                if (isFinite(pct)) demo.statBrightness = pct + "%";
            }
        }
    }
    Timer { interval: 2000; running: true; repeat: true; triggeredOnStart: true; onTriggered: brightnessProc.running = true }
    Timer { id: brightnessPollSoon; interval: 120; repeat: false; onTriggered: brightnessProc.running = true }

    // ---- POSITION — top/bottom, ported from shell.qml's own
    // shellRoot.position/setPosition. "i want to make the button bar same
    // style like the new bar and i can switch with win+shift+z like
    // before" — this is deliberately NOT shell.qml's separate bottom-bar
    // window (its own 40px/opaque/pipe-separator design, a different bar
    // entirely); it's the SAME bar this file already draws, just anchored
    // to the other edge, so "same style" is automatic rather than a
    // second design to maintain. Persisted the same way, and to the same
    // file, so a `topbar-position` written by either bar is honoured by
    // whichever one is actually running.
    property string position: "top"
    FileView {
        id: positionFile
        path: Quickshell.env("HOME") + "/.cache/topbar-position"
        watchChanges: true
        preload: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            const v = text().trim();
            if (v === "top" || v === "bottom")
                demo.position = v;
        }
    }
    function setPosition(p) {
        if (p !== "top" && p !== "bottom")
            return;
        demo.position = p;
        positionFile.setText(p + "\n");
        // Switching TO bottom while already faded (idle on top) must not
        // stay faded — the hide timers now refuse to fire in bottom mode,
        // but that only stops FUTURE fades, not one already in effect.
        if (p === "bottom")
            bar.wakeBoth();
    }

    // ---- CLOCK — real, ticking every second.
    property string clockText: Qt.formatDateTime(new Date(), "ddd, MMM d  HH:mm:ss")
    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: demo.clockText = Qt.formatDateTime(new Date(), "ddd, MMM d  HH:mm:ss")
    }
    Timer { id: wsDebounce; interval: 90; repeat: false; onTriggered: demo.refreshWs() }
    Component.onCompleted: {
        demo.refreshWs();
        recCheckProc.running = true;
    }

    // ---- RECORDING — "a red circle on/off till i finish the recording,
    // in the workspace part". ati-record (AtiScriptsV1/ati-record) writes
    // $XDG_RUNTIME_DIR/recordingpid when a recording starts and removes it
    // on stop (its own stop_recording(): `rm -f "$recording_pid_file"`) —
    // the same file its own `ps -p "$(cat pidfile)"` liveness check reads
    // elsewhere in that script, reused here rather than a second
    // mechanism. tide-island-fork's RecordingIndicator.qml already draws
    // exactly this pulsing dot for the island; that file lives outside
    // this standalone `qs -p`'s own directory and can't be imported here
    // (see TourPopup.qml's header on why), so the animation is the same
    // shape, ported by hand rather than shared.
    property bool recordingActive: false
    Process {
        id: recCheckProc
        command: ["sh", "-c",
            "f=\"${XDG_RUNTIME_DIR:-/tmp}/recordingpid\"; "
            + "[ -f \"$f\" ] && kill -0 \"$(cat \"$f\")\" 2>/dev/null && echo yes || echo no"]
        stdout: StdioCollector {
            onStreamFinished: demo.recordingActive = (text.trim() === "yes")
        }
    }
    Timer { interval: 1000; running: true; repeat: true; onTriggered: recCheckProc.running = true }

    // ---- NOTIFICATIONS — read-only, on purpose (see notifyFace's own
    // comment in the centre pill for why this is `busctl monitor | jq`
    // and not a NotificationServer). One clean JSON line per Notify call:
    // ["app","summary","body"] — verified live against a real notify-send
    // before wiring the QML side to it.
    property string notifyApp: ""
    property string notifySummary: ""
    property string notifyBody: ""
    property bool notifyActive: false
    // Roughly what still reads cleanly as one line in the pill before it
    // starts feeling like a dialog crammed into a badge.
    readonly property int notifyTakeoverMaxChars: 70
    // The notification CENTER's own backing list. A NotificationServer
    // would carry real history (persistenceSupported, trackedNotifications
    // — see NotificationService.qml's own header); reading passively
    // instead means this can only remember what has crossed the bus
    // since THIS bar started watching, not anything from before. Capped
    // so a busy session doesn't grow this forever.
    property var notifyHistory: []
    readonly property int notifyHistoryMax: 30

    // ---- NOTIFICATION CENTER — "i want dropdown card as this pill" — a
    // real dropdown (NotificationCenter.qml) hanging under the workspace
    // pill, own window, own selection/vim-motion state. This flag is the
    // only thing that file and this one share.
    property bool notifCenterOpen: false
    Process {
        id: notifyWatch
        running: true
        command: ["sh", "-c",
            "busctl --user monitor --json=short 2>/dev/null | "
            + "jq -c --unbuffered "
            + "'select(.member==\"Notify\" and .interface==\"org.freedesktop.Notifications\") "
            + "| .payload.data | [(.[0]|tostring), (.[3]|tostring), (.[4]|tostring)]'"]
        stdout: SplitParser {
            onRead: (line) => {
                try {
                    const arr = JSON.parse(line);
                    demo.notifyApp = String(arr[0] || "");
                    demo.notifySummary = String(arr[1] || "");
                    demo.notifyBody = String(arr[2] || "");
                    // "the too long messages make it appears with the
                    // dunst as it is and normal ones in the workspace chip
                    // as it is" — a long summary+body crammed into one
                    // bar-height text line either elides into nonsense or
                    // forces the pill absurdly wide. The island's own
                    // notification card (what dunst-style popups this
                    // session actually draws — see notifyFace's own note
                    // on why this file only WATCHES the bus rather than
                    // owning it) is already showing every notification
                    // regardless of what this takeover does; simply not
                    // triggering the takeover for a long one means it's
                    // shown ONLY there, while a normal-length one still
                    // gets both.
                    const combined = demo.notifySummary + demo.notifyBody;
                    if (combined.length <= demo.notifyTakeoverMaxChars) {
                        demo.notifyActive = true;
                        notifyRevert.restart();
                        // "not in both at the same time" — a short one used
                        // to take over the pill AND still sit there as a
                        // real dunst popup, since this watcher is passive
                        // (see the header note on why there's no
                        // NotificationServer of its own to actually own
                        // delivery). `dunstctl close` closes dunst's own
                        // most-recent popup — the one that was just this
                        // Notify call, since this handler fires on the
                        // exact same bus message dunst itself reacts to.
                        // Long ones never call this, so they still show in
                        // dunst uninterrupted, same as before.
                        Quickshell.execDetached(["dunstctl", "close"]);
                    }

                    const entry = { app: demo.notifyApp, summary: demo.notifySummary,
                                     body: demo.notifyBody,
                                     time: Qt.formatDateTime(new Date(), "HH:mm") };
                    const hist = demo.notifyHistory.concat([entry]);
                    while (hist.length > demo.notifyHistoryMax) hist.shift();
                    demo.notifyHistory = hist;
                } catch (e) {}
            }
        }
    }
    // How long the takeover holds the pill before handing it back —
    // long enough to actually read a summary, short enough that it
    // still reads as "transient" against the chord takeover's "as long
    // as you're in the mode".
    Timer { id: notifyRevert; interval: 4000; repeat: false; onTriggered: demo.notifyActive = false }

    // ---- VOICE DICTATION — "when i run it the workspace part change to
    // be this voice wave like thing". Voxtype (Omarchy's voice-to-text
    // daemon, Alt+F8) streams one JSON object per line on state changes:
    // `voxtype status --follow --extended --format json` — verified live
    // against this exact binary before wiring it up, same as the
    // recording-pidfile check above. `class`/`alt` carry the state word
    // ("idle" confirmed; "recording"/"transcribing" are the daemon's
    // documented other states).
    //
    // This is deliberately the SIMPLE half of the idea: a state-driven
    // wave, not a real microphone level meter — the full VoiceOverlay
    // treatment (omantra-style per-track RMS meter, keycaps, its own
    // overlay window) is a separate, much bigger UI already scoped for
    // the island itself. Duplicating that here, in a bar prototype whose
    // OWN stat badges are still being sized by hand, would be solving the
    // same problem twice in two different places.
    property string voiceState: "idle"
    readonly property bool voiceActive: demo.voiceState !== "" && demo.voiceState !== "idle"
    Process {
        id: voiceWatch
        running: true
        command: ["voxtype", "status", "--follow", "--extended", "--format", "json"]
        stdout: SplitParser {
            onRead: (line) => {
                try {
                    const d = JSON.parse(line);
                    demo.voiceState = String(d.class || d.alt || "idle");
                } catch (e) {}
            }
        }
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            const n = String(event.name);
            if (n.indexOf("workspace") >= 0 || n.indexOf("window") >= 0)
                wsDebounce.restart();
            // The chord/submap pill's real state — Hyprland's submap
            // change event, empty string on exit. Matches shell.qml's
            // own chord chip: present only while a mode is actually
            // active, invisible the rest of the time.
            if (n === "submap")
                demo.submapName = String(event.data || "").trim();
            // wayscriber ("draw" mode) is NOT a Hyprland submap — binds.conf's
            // own note explains why: gromit-mpx's submap got replaced by a
            // standalone daemon (`wayscriber --daemon-toggle`, $mod SHIFT W)
            // with its own layer-shell surface instead. No submap event ever
            // fires for it, so submapMap's stale "draw" entry (ported from
            // the gromit era, still holding the right letters — C/Z/R/V
            // verified live against wayscriber's own config.toml keybindings)
            // never actually showed. openlayer/closelayer on its real
            // namespace is the live signal instead, confirmed via
            // `hyprctl layers` while toggling: the "wayscriber" namespace
            // appears/disappears exactly on daemon-toggle.
            if (n === "openlayer" && String(event.data || "").trim() === "wayscriber")
                demo.drawActive = true;
            if (n === "closelayer" && String(event.data || "").trim() === "wayscriber")
                demo.drawActive = false;
        }
    }

    // ---- LAYOUT — same file LayoutState.qml (the island) and shell.qml
    // both read: layout-cycle.sh's own runtime file, one writer, two
    // readers, never a second copy that could drift.
    property string layoutName: "monadtall"
    readonly property string runtimeDir: {
        const x = Quickshell.env("XDG_RUNTIME_DIR");
        return (x && String(x) !== "") ? String(x) : "/tmp";
    }
    readonly property var layoutGlyphs: ({ "monadtall": 0xF0DB, "max": 0xF096, "treetab": 0xF00B })
    readonly property int layoutGlyph:
        demo.layoutGlyphs[demo.layoutName] !== undefined ? demo.layoutGlyphs[demo.layoutName] : 0xF0DB
    FileView {
        path: demo.runtimeDir + "/hypr-layouts/current"
        watchChanges: true
        preload: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            const t = text().trim();
            if (t !== "") demo.layoutName = t;
        }
    }

    // ---- CHORD/SUBMAP — real name via the Hyprland event above; empty
    // whenever no submap is active, same as shell.qml's chord chip.
    property string submapName: ""
    // wayscriber's own layer-surface presence — see the openlayer/
    // closelayer handler above for why this can't be a submap name.
    property bool drawActive: false
    // "check the current bar and check the letters of rofi... and all
    // other modes" — this used to be MY OWN derivation off submaps.conf's
    // raw bind lines, curated by hand and wrong in the specific way that
    // matters: it's not what the chip on the bar actually running right
    // now shows. shell.qml already carries the REAL, tested table —
    // config.py's CHORD_CHIP_LABELS/CHORD_CHIP_COLORS, ported there and
    // verified against this session's own qtile bar — so this is that
    // table, copied rather than re-derived a second time. Text and colour
    // both verbatim from shell.qml's `submapMap`; the icon codepoints are
    // left out (they're 5-hex Supplementary-PUA glyphs, the same kind that
    // turned out missing from this system's installed Nerd Font patches
    // for the nightlight/updates icons above — not reused here without
    // separately confirming each one actually renders).
    readonly property var submapMap: ({
        "resize":     { text: "RESIZE : H, J, N", colour: BarTheme.yellow },
        "rofi":       { text: "ROFI : i , o , p , w , z , b , e , r , t , y , f , s , n , h",
                        colour: BarTheme.blue },
        "media":      { text: "MEDIA : J , K , M , H , L , P", colour: BarTheme.cyan },
        "lang":       { text: "LANG : a , e , t , d", colour: BarTheme.fg },
        "draw":       { text: "DRAW : w , c , z , r , v", colour: BarTheme.red },
        "cheatsheet": { text: "CHEATSHEET : k , v , f , j/k scroll , TAB , ESC",
                        colour: BarTheme.red },
        "passthrough": { text: "PASSTHROUGH : ESC", colour: BarTheme.cyan },
        "passthrough-confirm": { text: "EXIT PASSTHROUGH ? y , n , ESC", colour: BarTheme.fg }
    })

    component Strip: Rectangle {
        id: strip
        default property alias content: row.children
        property int hgap: Metrics.s(11)
        height: parent ? parent.height : Metrics.barHeight
        width: row.implicitWidth + hgap * 2
        radius: Metrics.s(8)
        // BarTheme.plate, not raw BarTheme.bg: `plate` is the theme file's
        // OWN contrast-aware derivation (see BarTheme.qml) — it darkens a
        // light background and lightens a dark one specifically so a chip
        // stays legible on either kind of theme. Blending raw `bg` at low
        // alpha over an arbitrary wallpaper had no such guarantee — on a
        // pale wallpaper it went to a barely-there light wash, with
        // light-on-dark fg text still expecting a dark backdrop
        // underneath: "sometimes the wallpaper is white and the bar isn't
        // visible" is exactly that failure. Raised again — 0.55 was
        // STILL "not too visible enough" against a saturated orange/pink
        // wallpaper (tested against several, not just the one theme that
        // happened to be active): the plate itself has to win against
        // the wallpaper's own colour, not just against its brightness.
        // 0.78 keeps a hint of transparency; the theme's own tone still
        // reads through faintly, it just isn't fighting the wallpaper's
        // saturation for control of the pixel any more.
        // "the bottom bar make it a full bar bro not sep pills" — qtile's
        // own bottom bar is ONE opaque bar, not a row of chips (its own
        // note: "no chips, no plates... a solid background. Reproducing
        // it with chips would be reproducing the wrong bar"). `barFull`
        // below IS that one solid background for bottom mode; every
        // individual Strip going transparent/borderless here is what
        // stops each cluster ALSO drawing its own pill on top of it —
        // without this every group still looked like a separate floating
        // chip sitting on a bar, which is the opposite of "one bar".
        color: demo.position === "bottom" ? "transparent" : BarTheme.alpha(BarTheme.plate, 0.78)
        border.width: demo.position === "bottom" ? 0 : 1
        border.color: BarTheme.alpha(BarTheme.accent, 0.3)

        // Per-instance opt-out — asked for directly: "when I switch
        // workspace, should not have animation for the workspace part".
        // The width-Behavior and the Row's move-Transition below are both
        // real fixes for the stats/tray pill (see the comment on `move`),
        // but the SAME animation on the workspace pill meant every real
        // workspace switch — a pill appearing/disappearing as
        // hide_unused changes — visibly slid and resized. centerStrip
        // sets this false; the stats/tray pill leaves it true.
        property bool animated: true

        Behavior on width {
            enabled: strip.animated
            NumberAnimation { duration: 140; easing.type: Easing.OutQuad }
        }

        Row {
            id: row
            anchors.centerIn: parent
            spacing: Metrics.s(10)
            // THE FIX for "the animation while opening isn't stable":
            // toggling a child's `visible` makes Row snap every sibling
            // to its new x INSTANTLY, while the Strip's own width eases
            // over 140ms — icons were arriving at their new spot before
            // the pill had finished resizing around them, which is the
            // "wired"/unstable look. `move` animates the Row's own
            // repositioning on the same curve, so the icons and the
            // pill's edge now move together. Duration collapses to 0
            // when `animated` is false, so it's a true no-op there
            // rather than just a fast animation.
            move: Transition {
                NumberAnimation {
                    properties: "x,y"
                    duration: strip.animated ? 140 : 0
                    easing.type: Easing.OutQuad
                }
            }
        }
    }

    component Divider: Rectangle {
        // 0.12 read as basically invisible ("the '|' in between not even
        // visible") — more than tripled to actually register as a mark
        // rather than a rounding error in the plate's own colour.
        width: 1
        height: Metrics.s(14)
        color: BarTheme.alpha(BarTheme.fg, 0.4)
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
    }

    component Glyph: Text {
        property color fg: BarTheme.alpha(BarTheme.fg, 0.7)
        color: fg
        font.family: "Symbols Nerd Font"
        font.pixelSize: Metrics.s(12)
        renderType: Text.NativeRendering
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
    }

    component Label: Text {
        property color fg: BarTheme.fg
        color: fg
        font.family: Metrics.textFamily
        font.pixelSize: Metrics.textSize
        renderType: Text.NativeRendering
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
    }

    // SIXTH attempt. The fifth (icon sliced through its own midline, number
    // wedged in the gap) was confirmed against an ASCII preview before
    // building it, but the ASCII preview lied: it assumed a glyph's ink
    // fills its layout box edge to edge, the way a monospace LETTER does.
    // Screenshotted live (`qs ipc call debugview showAll` + grim, since
    // this bar auto-hides and there's no way to click it without
    // disturbing the real session) rather than guessed at again, and the
    // clip was cutting empty PADDING, not the icon: Nerd Font glyphs sit
    // centred in a box noticeably taller than their visible ink, so the
    // top half-height item showed nothing at all, and the bottom one
    // (shifted up by half, per the clip trick) actually exposed the
    // glyph's WHOLE visible ink, unclipped — which is exactly why it read
    // as "a real memory-stick / cpu-chip icon" in that screenshot instead
    // of a smudge. So this keeps that accidental result on purpose: one
    // full, uncut icon under the number. No box, no border, no nub, no
    // clipping — the icon's own silhouette, actually intact this time.
    component StatBadge: Item {
        id: badge
        property int icon: 0
        property string value: ""
        property color tint: BarTheme.fg
        // "they are out of frame" — the number+icon column was landing at
        // ~28px tall against a 28px-tall Strip, zero margin either side, so
        // the icon's own descender was crossing the plate's own rounded
        // edge. Shrunk further (not just "icon smaller" this time, the
        // whole column shorter) so there's real breathing room top and
        // bottom instead of the content exactly filling the plate.
        // Bumped 10% ("if 1 make it 1.1"), then asked for "a bit bigger"
        // again against a screenshot at that size — there was still slack
        // below barHeight (28px) even with the +10% pass (column came to
        // ~20px), so this grows again without touching the margin fix.
        readonly property int iconSize: Metrics.s(9)

        width: col.implicitWidth
        height: col.implicitHeight
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        // "the text is near to the top a lot make it a bit down" — the
        // Column is centred exactly (col.implicitHeight === badge.height,
        // so there was never any real slack for anchors to get wrong);
        // what reads as "too high" is the number's own glyph box, which
        // reserves descender space under the baseline that plain digits
        // never use. +2 OVER-corrected it: badge is ~22px in a 28px
        // Strip, only ~6px of real slack total, and +2 pushed the icon's
        // own descender right up against the plate's bottom edge ("too
        // near to the border of the frame"). Halved.
        anchors.verticalCenterOffset: Metrics.s(1)

        Column {
            id: col
            // Both children already carry anchors.horizontalCenter, and
            // this Column is centred in the badge's own Item below — "align
            // them in center" was already true structurally, so nothing
            // needed to move there.
            anchors.centerIn: parent
            // Negative on purpose — "near to the icon not touching each
            // other". At spacing 0 there was still a visible gap: Text's
            // own box reserves leading/descender space below the visible
            // ink that plain digits never fill, so two stacked Texts read
            // as further apart than their `spacing` value alone says.
            // Pulling the icon up compensates for that reserved space
            // instead of fighting it with font-size tricks.
            spacing: -Metrics.s(3)

            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: undefined
                text: badge.value
                fg: badge.tint
                font.pixelSize: Metrics.s(9)
                font.bold: true
            }

            Glyph {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: undefined
                text: String.fromCodePoint(badge.icon)
                fg: BarTheme.alpha(badge.tint, 0.9)
                font.pixelSize: badge.iconSize
            }
        }
    }

    // Real app icons in a shingled pile — "a bunch of files above each
    // other". Later entries sit up and to the right of earlier ones;
    // the focused one is drawn frontmost AND ringed, so which one is
    // open never needs a label.
    component AppFileStack: Item {
        id: stack
        property var appIds: []
        property int activeIndex: -1
        // Sized down again — "increase the space a bit and reduce the
        // icons size", against a screenshot showing the three overlapping
        // into what read as one blob rather than a legible pile.
        property int chip: Metrics.s(15)
        // Widened alongside the smaller chip so the actual gap between
        // icons grows rather than just each icon shrinking in place —
        // "increase the space" was about the room between them, not only
        // their own size.
        property int step: Metrics.s(13)
        implicitWidth: appIds.length > 0 ? chip + step * (appIds.length - 1) : 0
        // chip exactly, no headroom, used to be the container's height —
        // "the icon in top not fully visible" is the focused chip's own
        // 1.14 scale (below) pushing a sliver of itself past a box sized
        // for the UNSCALED chip. Padded out so the scaled chip has real
        // room on both edges instead of relying on sub-pixel luck.
        implicitHeight: Math.round(chip * 1.3)
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined

        Repeater {
            model: stack.appIds
            delegate: Rectangle {
                width: stack.chip
                height: stack.chip
                radius: Metrics.s(4)
                // Mirrored — asked for directly ("opposite direction").
                // Earlier entries now sit further RIGHT, so the pile
                // cascades leftward toward the focused one instead of
                // building away from it.
                x: (stack.appIds.length - 1 - index) * stack.step
                anchors.verticalCenter: parent.verticalCenter
                z: index === stack.activeIndex ? 100 : index
                // Fill, not a ring — "the [] square is bad, can't we do
                // another thing like fill colour of the icon". The
                // border stays a plain uniform 1px on every chip (just
                // enough to separate one icon from the next in the
                // pile); "focused" is a tinted background behind the
                // logo instead of a thick accent outline around it.
                // Also asked for: "the most top one should be more
                // visible" — a touch larger and a stronger fill, not a
                // ring, so it still doesn't reintroduce the "[]" look.
                scale: index === stack.activeIndex ? 1.14 : 1.0
                color: index === stack.activeIndex
                    ? BarTheme.alpha(BarTheme.accent, 0.45)
                    : BarTheme.alpha(BarTheme.bg, 0.95)
                border.width: 1
                border.color: index === stack.activeIndex
                    ? BarTheme.alpha(BarTheme.accent, 0.6)
                    : BarTheme.alpha(BarTheme.fg, 0.2)

                // "why there is an empty gap here" — a real class with no
                // resolvable icon (qdrop, this desktop's own drop-stash
                // tool: a plain python3 GUI, no .desktop entry, no icon
                // named "qdrop" anywhere), not a missing mock-alias entry.
                // Chasing every custom/internal tool by name one at a time
                // is a list that never finishes; a generic fallback glyph
                // is the general fix — an unresolved icon reads as "some
                // app" instead of a blank box.
                readonly property bool hasIcon: Quickshell.iconPath(modelData.appId, true) !== ""
                IconImage {
                    visible: parent.hasIcon
                    anchors.centerIn: parent
                    source: parent.hasIcon ? Quickshell.iconPath(modelData.appId, true) : ""
                    width: parent.width - Metrics.s(5)
                    height: width
                }
                Glyph {
                    visible: !parent.hasIcon
                    anchors.centerIn: parent
                    anchors.verticalCenter: undefined
                    text: String.fromCodePoint(0xF2D0)   // generic app window
                    font.pixelSize: parent.width * 0.55
                }

                // "if the same icon opens so put the icon once and write
                // '+then the number' ex +3" — three kitty windows on one
                // workspace used to be three identical kitty icons; now
                // one icon plus this badge, since demo.wsApps already
                // groups by appId (see its own Process) and hands each
                // chip a real count instead of a duplicate entry.
                Rectangle {
                    visible: modelData.count > 1
                    width: countLabel.implicitWidth + Metrics.s(4)
                    height: countLabel.implicitHeight + Metrics.s(1)
                    radius: height / 2
                    color: BarTheme.accent
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.rightMargin: -Metrics.s(2)
                    anchors.bottomMargin: -Metrics.s(2)
                    z: 200
                    Text {
                        id: countLabel
                        anchors.centerIn: parent
                        text: "+" + modelData.count
                        color: BarTheme.bg
                        font.family: Metrics.textFamily
                        font.pixelSize: Metrics.s(7)
                        font.bold: true
                        renderType: Text.NativeRendering
                    }
                }
            }
        }
    }

    // Recording dot — same pulse shape as tide-island-fork's
    // RecordingIndicator.qml (a slow dim-then-brighten loop, not a hard
    // blink), ported by hand since that file can't be imported from here.
    // `active` toggling off snaps `core.opacity` back to 1 only after the
    // outer fade-out finishes — that file's own fix for a bright flash
    // the instant a still-mid-dim recording stops, reproduced for the
    // same reason.
    component RecDot: Item {
        id: recDot
        property bool active: false
        readonly property int dotSize: Metrics.s(7)
        implicitWidth: active || opacity > 0.01 ? dotSize : 0
        implicitHeight: dotSize
        opacity: active ? 1 : 0
        visible: active || opacity > 0.01
        Behavior on opacity {
            NumberAnimation { duration: recDot.active ? 180 : 220; easing.type: Easing.InOutQuad }
        }
        onActiveChanged: if (!active) resetCore.restart()
        Timer { id: resetCore; interval: 220; onTriggered: core.opacity = 1.0 }

        Rectangle {
            id: core
            width: recDot.dotSize
            height: recDot.dotSize
            anchors.centerIn: parent
            radius: width / 2
            color: BarTheme.red
            opacity: 1.0
        }
        SequentialAnimation {
            running: recDot.active
            loops: Animation.Infinite
            PauseAnimation { duration: 110 }
            NumberAnimation { target: core; property: "opacity"; to: 0.35; duration: 980; easing.type: Easing.InOutSine }
            PauseAnimation { duration: 120 }
            NumberAnimation { target: core; property: "opacity"; to: 1.0; duration: 1040; easing.type: Easing.InOutSine }
        }
    }

    // One bar of the voice-dictation "wave" — a time-driven pulse, not a
    // real microphone level (see voiceFace's own note on why the full
    // meter treatment lives elsewhere). Five of these, staggered by index,
    // read as one wave rather than five bars blinking independently — the
    // same trick RecordingIndicator-style pulses use, just spread across
    // several elements instead of one.
    component VoiceBar: Rectangle {
        id: vbar
        required property int index
        readonly property int maxHeight: Metrics.s(11)
        property real level: 0.2
        width: Metrics.s(3)
        radius: width / 2
        color: BarTheme.accent
        anchors.bottom: parent.bottom
        // "not moving at all" — real bug, not a guess: `height` is a live
        // binding off `level`, and `level` is ALREADY being smoothly
        // animated below (InOutSine, 300ish ms). A Behavior on top of that
        // restarts its own 260ms tween every single frame `level` ticks
        // (~16ms apart), chasing a target that moves faster than it can
        // follow — the textbook trap of animating a property a Behavior
        // is also attached to. It never visibly gets anywhere. Removed;
        // the NumberAnimations on `level` are the only motion this needs.
        height: Math.max(Metrics.s(2), vbar.maxHeight * vbar.level)
        SequentialAnimation {
            running: demo.voiceState === "recording"
            loops: Animation.Infinite
            PauseAnimation { duration: vbar.index * 60 }
            NumberAnimation { target: vbar; property: "level"; to: 0.9; duration: 300 + vbar.index * 40; easing.type: Easing.InOutSine }
            NumberAnimation { target: vbar; property: "level"; to: 0.25; duration: 300 + vbar.index * 40; easing.type: Easing.InOutSine }
        }
    }

    PanelWindow {
        id: bar
        screen: Quickshell.screens[0]
        // top/bottom via demo.position (Win+Shift+Z, ported from
        // shell.qml — see demo.setPosition's own note). Both edges are
        // always anchored; only WHICH one carries the actual margin
        // switches, so the bar snaps to the opposite edge instead of
        // stretching across the whole screen height.
        anchors {
            top: demo.position === "top"
            bottom: demo.position === "bottom"
            left: true
            right: true
        }
        // shell.qml's own bar switches height by position too
        // (Metrics.barHeight top / Metrics.bottomBarHeight bottom) —
        // this used barHeight unconditionally, so the bottom bar sat at
        // 28px instead of the qtile bottom bar's real 40px.
        implicitHeight: (demo.position === "top"
            ? Metrics.barHeight : Metrics.bottomBarHeight) + Metrics.marginV * 2
        // Was offset by a whole bar-height-plus-gap so this could sit as
        // a SECOND row underneath the real shell.qml bar during
        // side-by-side preview. shell.qml's own `quickshell -p .../topbar`
        // process is stopped now ("disable this... enable this one") so
        // there's nothing left to sit below — this takes the primary
        // slot at the true top of the screen instead of leaving that gap
        // empty above it.
        margins.top: demo.position === "top" ? Metrics.marginV : 0
        margins.bottom: demo.position === "bottom" ? Metrics.marginV : 0
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Top
        exclusionMode: ExclusionMode.Ignore
        // This bar itself asks for no keyboard focus at all — the
        // notification centre is its own separate dropdown window now
        // (NotificationCenter.qml) and owns its own keyboard focus,
        // OnDemand rather than Exclusive for the exact reason recorded
        // in that file: Exclusive blocks Hyprland's global dispatch
        // (workspace switching included) while held, not just
        // keyboard-focused input.

        // ---- AUTO-HIDE: minimal-as-possible, workspace pill always stays ----
        //
        // Asked for directly: after idling, the left (brand) and right
        // (status) sides fade out and ONLY the centred workspace pill
        // remains; moving the mouse back into either side's zone brings
        // it back. Opacity only — nothing is set invisible or removed
        // from layout, so nothing reflows and no size/spacing changes,
        // which was the explicit caution given alongside this ask.
        //
        // 4s here so the effect is actually visible within this same
        // preview session; the real ask was "1 min" — bump autoHideMs to
        // 60000 for that.
        property int autoHideMs: 4000
        property real leftOpacity: 1
        property real rightOpacity: 1

        // "make the bottom bar not hide at all" — qtile's own bottom bar
        // never auto-hides (it's the "normal user" bar: "everything
        // reachable by pointer", not a minimal strip that gets out of the
        // way). Guarded here rather than on each opacity binding: every
        // cluster's opacity already just reads bar.leftOpacity/
        // rightOpacity, so refusing to let THOSE drop to 0 in bottom mode
        // covers all of them at once.
        Timer {
            id: leftHideTimer
            interval: bar.autoHideMs
            onTriggered: if (demo.position !== "bottom") bar.leftOpacity = 0
        }
        Timer {
            id: rightHideTimer
            interval: bar.autoHideMs
            onTriggered: if (demo.position !== "bottom") bar.rightOpacity = 0
        }
        Component.onCompleted: { leftHideTimer.start(); rightHideTimer.start(); }

        // "when the right part is hidden and i click win+` should appear
        // and show the opening and closing... and then when the req time
        // finished it disappear as it is" — the hover zone already does
        // this (leftOpacity/rightOpacity = 1 + stop the hide timer while
        // the pointer is there); the IPC-driven opens (Win+`/Alt+`,
        // ati-bar-action) bypassed hover entirely, so opening a box while
        // auto-hidden opened it invisibly. This is the same wake, called
        // from those IPC functions instead of a HoverHandler — `restart`,
        // not `stop`, so it fades back out on its own after the normal
        // autoHideMs, exactly like hovering-then-leaving does.
        function wakeRight() {
            bar.rightOpacity = 1;
            rightHideTimer.restart();
        }
        function wakeBoth() {
            bar.leftOpacity = 1;
            bar.rightOpacity = 1;
            leftHideTimer.restart();
            rightHideTimer.restart();
        }

        // THE ONE FULL BAR — bottom mode only. Was truly edge-to-edge
        // (anchors.fill, no margins) — WRONG against shell.qml's own
        // bottom bar, which insets its opaque background by
        // Metrics.marginH left/right (and marginV top/bottom) same as
        // the top bar's own `content` does; "should not be touching the
        // screen border from left and right like the qtile one" is
        // exactly that gap being missing here. Matched to those same
        // margins now instead of filling the raw window. Radius was
        // missing entirely (square corners) — shell.qml's own bottom
        // bar background Rectangle carries `radius: Metrics.s(6)`,
        // matched here too ("width and height and roundness... like
        // the bar of qtile bottom").
        Rectangle {
            anchors.fill: parent
            anchors.leftMargin: Metrics.marginH
            anchors.rightMargin: Metrics.marginH
            anchors.topMargin: Metrics.marginV
            anchors.bottomMargin: Metrics.marginV
            radius: Metrics.s(6)
            visible: demo.position === "bottom"
            color: BarTheme.bg
        }

        Item {
            id: content
            anchors.fill: parent
            anchors.topMargin: Metrics.marginV
            anchors.bottomMargin: Metrics.marginV
            anchors.leftMargin: Metrics.marginH
            anchors.rightMargin: Metrics.marginH

            // A wider-than-the-pill hover catcher, so the mouse doesn't
            // have to land exactly on the (now possibly invisible) Strip
            // to bring it back — "when I get with the mouse to the left
            // part they appear", not "onto the exact pixel".
            Item {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                // Bound to the real content instead of a guessed constant —
                // see the right zone's own note below for why a fixed
                // number drifts out of sync with what's actually on the bar.
                width: brandStrip.width + Metrics.s(40)
                height: parent.height
                HoverHandler {
                    // BUG FIXED HERE: this used to only ever RESTART the
                    // timer on hover-in and never touch it on hover-out,
                    // so lingering on the bar longer than autoHideMs made
                    // it vanish out from under the pointer mid-interaction
                    // — exactly what was reported ("if I am on it or
                    // clicking on something and still on it, do not
                    // hide"). Now the timer is fully STOPPED for the
                    // whole time the pointer is inside this zone, and
                    // only starts counting down again the moment it
                    // actually leaves.
                    onHoveredChanged: {
                        if (hovered) {
                            bar.leftOpacity = 1;
                            leftHideTimer.stop();
                        } else {
                            leftHideTimer.restart();
                        }
                    }
                }
            }
            Item {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                // Was a flat 480 — "when i am hovering on the left and
                // right part do not hide" was this going stale: rightRow
                // grows past 480px once stats/tray are both open plus
                // battery/EN/clock, so the pointer sitting on, say, the
                // clock was OUTSIDE this catcher's bounds entirely, never
                // set `hovered`, and the timer kept counting down under it.
                // Bound to the row's own real width so it always covers
                // whatever is actually rendered, expanded or not.
                width: rightRow.width + Metrics.s(40)
                height: parent.height
                HoverHandler {
                    onHoveredChanged: {
                        if (hovered) {
                            bar.rightOpacity = 1;
                            rightHideTimer.stop();
                        } else {
                            rightHideTimer.restart();
                        }
                    }
                }
            }

            // ---- THE ONE TOOLTIP, PORTED FROM shell.qml ----
            //
            // "why there is no tooltip add like the currnt running one" —
            // shell.qml has this exact pattern (one shared hoverSink + one
            // Tooltip instance, a chip reports hover into it rather than
            // owning a popup each) and this file had none of it. Same
            // shape here: every hoverable icon below calls
            // barTooltip.enter/exit on its own MouseArea instead of
            // growing seventeen separate popups.
            QtObject {
                id: barTooltip
                property var current: null
                property string currentText: ""
                function enter(item, text) {
                    barTooltip.current = item;
                    barTooltip.currentText = text;
                    tooltipDelay.restart();
                }
                function exit(item) {
                    if (barTooltip.current !== item)
                        return;
                    tooltipDelay.stop();
                    barTooltip.current = null;
                }
            }
            Timer { id: tooltipDelay; interval: 450; repeat: false }
            Tooltip {
                target: tooltipDelay.running ? null : barTooltip.current
                text: barTooltip.current ? barTooltip.currentText : ""
                belowTarget: demo.position === "top"
            }

            // ================= LEFT: the Arch logo =================
            Strip {
                id: brandStrip
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                opacity: bar.leftOpacity
                Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutQuad } }
                Glyph {
                    text: String.fromCodePoint(0xF303)   // linux-archlinux
                    // BarTheme.accent, not a hardcoded purple — asked
                    // for directly ("why not changing, fit the theme").
                    // accent is the one colour BarTheme derives FROM the
                    // active theme's palette (theme-apply writes it into
                    // colors.json), so this now actually retints when
                    // the theme does, the same as the clock already did.
                    fg: BarTheme.accent
                    // "make the bottom bar sizes... same size and space
                    // like the old qtile bar bottom one" — BottomBar.qml's
                    // own brand icon is pixelSize 19 (bigger than the top
                    // bar's 14, since main_icon_chip_nu is a bigger target
                    // on the "everything reachable by pointer" bar).
                    // "bottom bar's arch logo is too big make it a bit
                    // smaller" — BottomBar.qml's own 19 read as too large
                    // against this bar's actual proportions; dialled back
                    // rather than matched literally.
                    font.pixelSize: demo.position === "bottom" ? Metrics.s(16) : Metrics.s(14)
                    // L-click -> the actual menu bound to mod+shift+/
                    // (binds.conf: `ati-bar-action tide toggleMenu`,
                    // which opens the island's own MenuLayer.qml — the
                    // exact command the keybind runs, not a re-
                    // implementation of it). R-click -> terminal, same
                    // as shell.qml's own menu chip.
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -Metrics.s(5)
                        // THE REAL BUG behind "right click terminal" not
                        // working, and it was systemic: MouseArea only
                        // accepts the LEFT button by default. Every
                        // mouse.button===Qt.RightButton branch in this
                        // file was dead code until acceptedButtons named
                        // the right button too — fixed here and at every
                        // other site below that checks it.
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: (mouse) => {
                            if (mouse.button === Qt.RightButton)
                                Quickshell.execDetached(["kitty"]);
                            else
                                Quickshell.execDetached(["ati-bar-action", "tide", "toggleMenu"]);
                        }
                    }
                }
            }

            // ================= LEFT (bottom mode only): the launcher row
            // — qtile's "normal user" bottom bar's own concept
            // (BottomBar.qml: "a launcher row... five fixed application
            // icons, which is what makes it the normal user bar —
            // everything reachable by pointer"), restyled as Strip/Glyph
            // pills instead of that bar's bare pipe-separated text on an
            // opaque background. "i want the bottom bar same concept like
            // the qtile like one but with the new style" — the CONTENT is
            // qtile's, the CHROME is this bar's.
            Strip {
                id: launcherStrip
                visible: demo.position === "bottom"
                anchors.left: brandStrip.right
                // BottomBar.qml's brand-icon padding (16) plus its "|"
                // separator's (3) — the gap between the brand icon and
                // what follows it on that bar.
                anchors.leftMargin: Metrics.s(16)
                anchors.verticalCenter: parent.verticalCenter
                opacity: bar.leftOpacity
                Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutQuad } }

                Row {
                    // "same size and space like the old qtile bar bottom
                    // one" — BottomBar.qml gives each launcher icon
                    // padding 12 (per side), so ~2x12 between two of them;
                    // this Row's single `spacing` is the equivalent total
                    // gap, not a per-side inset, hence 20 rather than 12.
                    spacing: Metrics.s(20)
                    anchors.verticalCenter: parent ? parent.verticalCenter : undefined

                    Repeater {
                        // BottomBar.qml's `launchers`, verbatim codepoints
                        // and commands.
                        model: [
                            { cp: 0xF269,  cmd: "brave",       name: "Brave Browser" },
                            { cp: 0xF484,  cmd: "qutebrowser", name: "Qutebrowser" },
                            { cp: 0xEBC4,  cmd: "kitty",       name: "Kitty Terminal" },
                            { cp: 0xF07B,  cmd: "pcmanfm-qt",  name: "File Manager" },
                            { cp: 0xF0A1E, cmd: "code",        name: "VS Code" }
                        ]
                        delegate: Glyph {
                            required property var modelData
                            text: String.fromCodePoint(modelData.cp)
                            // BottomBar.qml's own launcher pixelSize.
                            font.pixelSize: Metrics.s(14)
                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -Metrics.s(5)
                                hoverEnabled: true
                                onClicked: Quickshell.execDetached([parent.modelData.cmd])
                                onEntered: barTooltip.enter(parent, parent.modelData.name)
                                onExited: barTooltip.exit(parent)
                            }
                        }
                    }

                    Divider {}

                    Glyph {
                        text: String.fromCodePoint(0xF0E51)   // screenshot_chip_nu
                        // BottomBar.qml's own screenshot-chip pixelSize.
                        font.pixelSize: Metrics.s(16)
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -Metrics.s(5)
                            hoverEnabled: true
                            onClicked: Quickshell.execDetached(["ati-satty"])
                            onEntered: barTooltip.enter(parent, "Screenshot area → clipboard")
                            onExited: barTooltip.exit(parent)
                        }
                    }
                }
            }

            // ================= CENTRE: where / what's open =================
            Strip {
                id: centerStrip
                // No animation on this pill at all — asked for directly
                // ("when I switch workspace, should not have animation
                // for the workspace part"). hide_unused means a real
                // workspace switch changes which pills exist, which
                // changes this Strip's width AND its collision-avoidance
                // x below; both used to ease, which is a workspace
                // switch visibly sliding the whole group. Now it snaps.
                animated: false
                // REAL FIX, not cosmetic: pure anchors.horizontalCenter
                // had no idea the right cluster could grow (opening the
                // cpu/tray readout widens it by ~150px) or that the right
                // Row is independently anchored to the window's right
                // edge — so on a narrow screen the two just drove
                // straight through each other the moment something
                // opened. shell.qml's own real bar hit this exact problem
                // and solved it with `taskListWidth`, a computed cap
                // rather than a fixed anchor; this is the same idea,
                // applied to a POSITION instead of a width: the pill sits
                // at true centre only when there's room, and slides left
                // to stay clear of the right cluster (with a matching
                // floor against the left/brand cluster) the instant
                // there isn't.
                x: Math.max(
                    // The launcher row (bottom mode only) extends the left
                    // cluster's real right edge past brandStrip's own —
                    // floor against whichever is actually further right,
                    // or centerStrip would sit UNDER the launcher icons the
                    // moment the bar drops to the bottom edge.
                    (launcherStrip.visible ? launcherStrip.x + launcherStrip.width
                                            : brandStrip.x + brandStrip.width) + Metrics.s(12),
                    Math.min(
                        (content.width - width) / 2,
                        rightRow.x - Metrics.s(12) - width
                    )
                )
                anchors.verticalCenter: parent.verticalCenter

                // ---- MODE TAKEOVER — new idea, asked for directly: "when
                // a chord mode opens make replace everything in the
                // workspace chip with the chord... and when done make the
                // workspace things come back... smooth". Previously the
                // submap only got its OWN separate pill (chordStrip, to
                // the right) while this one sat there unrelated and
                // unchanged — easy to miss since it wasn't where your eye
                // already was (the centre pill, mid-workspace-switch).
                // Now the centre pill itself becomes the announcement.
                //
                // Both faces are children of ONE Item so they occupy the
                // same spot and can be cross-faded rather than laid out
                // side by side; only their opacity moves, on a plain
                // Behavior, so entering and leaving a mode both animate
                // the same way with no separate enter/exit logic.
                //
                // Deliberately NOT wired through Strip's own `animated`
                // width-Behavior: that flag is what makes ordinary
                // workspace switching snap instead of slide (see the note
                // on `animated: false` above). A `Behavior on implicitWidth`
                // WAS here too, and it broke exactly that guarantee — it
                // animates every implicitWidth change, including
                // normalFace's own width changing on a plain hide_unused
                // workspace switch, which is what read as "moving/
                // unstable" ("when i move to another spaces... make it
                // stable"). Removed: `swap.implicitWidth` now jumps
                // instantly for BOTH cases, ordinary switching and the
                // chord takeover alike; the crossfade is carried entirely
                // by the two faces' opacity, which is animated smoothness
                // enough on its own.
                Item {
                    id: swap
                    // FOUR faces — the notification CENTER is no longer
                    // one of them. "i want dropdown card as this pill" —
                    // it's back to being a real dropdown that hangs UNDER
                    // this pill (see NotificationCenter.qml) rather than
                    // replacing the pill's own text, so the workspace
                    // icons stay visible and untouched while it's open.
                    // Priority for what's left: a fresh transient
                    // notification (a few seconds) first, then active
                    // dictation (you're mid-sentence), then a chord mode
                    // (a state you're deliberately sitting in), then the
                    // plain workspace view.
                    readonly property string activeFace:
                        demo.notifyActive ? "notify"
                        : demo.voiceActive ? "voice"
                        : (demo.submapName !== "" || demo.drawActive) ? "chord" : "normal"
                    implicitWidth: {
                        if (swap.activeFace === "notify") return notifyFace.implicitWidth;
                        if (swap.activeFace === "voice") return voiceFace.implicitWidth;
                        if (swap.activeFace === "chord") return chordFace.implicitWidth;
                        return normalFace.implicitWidth;
                    }
                    implicitHeight: Math.max(normalFace.implicitHeight, chordFace.implicitHeight,
                                              notifyFace.implicitHeight, voiceFace.implicitHeight)
                    // "the apps should [have a] gap between it and the
                    // bar[pill edge]" — real bug behind it, not a padding
                    // tweak: a plain Item's `width`/`height` do NOT track
                    // its own `implicitWidth`/`implicitHeight`
                    // automatically (Text/Image bind that internally;
                    // Item doesn't). So centerStrip's own outer sizing —
                    // `width: row.implicitWidth + hgap*2`, in Strip's
                    // definition — was computed off swap's actual `width`,
                    // which had been sitting at its default of 0 the whole
                    // time, while normalFace's children (centered ON that
                    // zero-width point) still rendered at their real,
                    // wider size — the overflow past what Strip thought
                    // the content needed is exactly the missing edge gap.
                    width: swap.implicitWidth
                    height: swap.implicitHeight

                    // "the animation of going to mode also not smooth...
                    // make both's open and close smooth" — the opacity
                    // crossfade below always animated; what didn't was
                    // THIS width, deliberately snapped (see the note just
                    // above) so an ordinary workspace switch wouldn't
                    // slide. That fix was too broad: it also killed the
                    // width motion for switching FACES, which is a
                    // different event and should animate.
                    //
                    // `settledFace` is what tells the two apart. It only
                    // catches up to `activeFace` after the transition
                    // finishes (settleTimer, below), so for the first
                    // ~230ms after activeFace actually changes the two
                    // differ and the Behavior is enabled; the rest of the
                    // time they match and every width change (hide_unused
                    // adding/removing a workspace pill while STAYING on
                    // normalFace) snaps exactly as before.
                    //
                    // 220ms/OutCubic, not the original 160ms/OutQuad —
                    // "should be smooth and not look cheap". Matched to
                    // this repo's own other fades (TourPopup's card,
                    // PopupChrome's) rather than picked arbitrarily, so
                    // every takeover — chord, notification, voice — now
                    // moves at the same weight as everything else instead
                    // of snapping noticeably faster.
                    property string settledFace: "normal"
                    onActiveFaceChanged: settleTimer.restart()
                    Timer {
                        id: settleTimer
                        interval: 230
                        onTriggered: swap.settledFace = swap.activeFace
                    }
                    Behavior on implicitWidth {
                        enabled: swap.activeFace !== swap.settledFace
                        NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                    }

                    // WHERE / WHAT'S OPEN — real now: model is demo.wsList
                    // (hyprctl -j workspaces, refreshed on Hyprland's own
                    // workspace/window events), active is a real id match
                    // against demo.focusedWsId, occupied is the real
                    // window count. Only a populated-or-focused workspace
                    // is shown, same hide_unused convention Workspaces.qml
                    // uses — an empty, unfocused workspace isn't drawn at
                    // all rather than sitting there dimmed.
                    Row {
                        id: normalFace
                        spacing: Metrics.s(6)
                        anchors.verticalCenter: parent.verticalCenter
                        opacity: swap.activeFace === "normal" ? 1 : 0
                        visible: opacity > 0.01
                        Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

                        Row {
                            spacing: Metrics.s(6)
                            anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                            Repeater {
                                model: demo.wsList
                                delegate: Rectangle {
                                    id: wsDelegate
                                    required property var modelData
                                    readonly property bool wsActive: modelData.id === demo.focusedWsId
                                    readonly property bool wsOccupied: (modelData.windows || 0) > 0
                                    // hide_unused — Workspaces.qml's own term for
                                    // exactly this rule.
                                    visible: wsOccupied || wsActive
                                    width: visible ? pairRow.implicitWidth + (wsActive ? Metrics.s(12) : Metrics.s(3)) : 0
                                    height: Metrics.s(21)
                                    radius: height / 3
                                    color: wsActive ? BarTheme.alpha(BarTheme.accent, 0.22) : "transparent"
                                    border.width: wsActive ? 1 : 0
                                    border.color: BarTheme.alpha(BarTheme.accent, 0.5)
                                    anchors.verticalCenter: parent ? parent.verticalCenter : undefined

                                    Row {
                                        id: pairRow
                                        spacing: Metrics.s(3)
                                        anchors.centerIn: parent
                                        Glyph {
                                            visible: demo.hasIconForWs(wsDelegate.modelData.name)
                                            text: visible ? String.fromCodePoint(demo.iconForWs(wsDelegate.modelData.name)) : ""
                                            // Three states, qtile-style: focused
                                            // (accent), occupied-but-elsewhere
                                            // (full-opacity fill so you can see
                                            // where your windows are from any
                                            // workspace) — the genuinely-empty
                                            // third state doesn't need a colour
                                            // now, since hide_unused means it's
                                            // simply not drawn at all.
                                            fg: wsDelegate.wsActive ? BarTheme.accent : BarTheme.alpha(BarTheme.fg, 0.9)
                                            font.pixelSize: Metrics.s(10)
                                            anchors.verticalCenter: undefined
                                        }
                                        // Plain number for workspaces with no icon (6, 7) --
                                        // "Symbols Nerd Font" (Glyph's font) carries icon
                                        // codepoints only, no digits, so this needs Label's
                                        // normal text font rather than just an un-mapped Glyph.
                                        Label {
                                            visible: !demo.hasIconForWs(wsDelegate.modelData.name)
                                            text: visible ? String(wsDelegate.modelData.name) : ""
                                            fg: wsDelegate.wsActive ? BarTheme.accent : BarTheme.alpha(BarTheme.fg, 0.9)
                                            font.pixelSize: Metrics.s(10)
                                            anchors.verticalCenter: undefined
                                        }
                                        // A real "|" between the workspace icon and
                                        // the layout glyph — only when there is a
                                        // layout worth naming, i.e. the active
                                        // workspace actually has windows on it.
                                        // Gated on wsActive alone, this drew a
                                        // dangling "|" with nothing after it on an
                                        // empty active workspace (no icon, no
                                        // apps) — reported directly.
                                        Divider {
                                            visible: wsDelegate.wsActive && wsDelegate.wsOccupied
                                            height: Metrics.s(11)
                                        }
                                        // The layout glyph — REAL now, from the
                                        // same runtime file LayoutState.qml reads,
                                        // not a hardcoded monadtall. Same gate as
                                        // the divider above: a layout glyph for a
                                        // workspace with nothing tiled on it is
                                        // exactly as meaningless as the "|" in
                                        // front of it.
                                        Glyph {
                                            visible: wsDelegate.wsActive && wsDelegate.wsOccupied
                                            text: String.fromCodePoint(demo.layoutGlyph)
                                            fg: BarTheme.accent
                                            font.pixelSize: Metrics.s(10)
                                            anchors.verticalCenter: undefined
                                        }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: Hyprland.dispatch("workspace " + wsDelegate.modelData.id)
                                    }
                                }
                            }
                        }

                        Divider {}

                        // WHAT'S OPEN — real now: demo.wsApps/wsActiveIndex,
                        // the actual windows on the FOCUSED workspace (see
                        // their own Process above), not the fixed
                        // ["kitty","firefox","code"] mock this carried
                        // through every earlier pass.
                        AppFileStack {
                            appIds: demo.wsApps
                            activeIndex: demo.wsActiveIndex
                        }

                        // "a red circle on off till i finish the
                        // recording, in the workcspcae part" — pulses for
                        // as long as demo.recordingActive (ati-record's
                        // pidfile) is true, takes zero width otherwise.
                        RecDot {
                            active: demo.recordingActive
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    // THE MODE FACE — shell.qml's real submapMap text,
                    // verbatim ("check the current bar and check the
                    // letters of rofi... and all other modes"), plate-
                    // less here since this pill already carries its own
                    // background — the PER-MODE colour is what carried the
                    // identity in config.py's original (CHORD_CHIP_COLORS),
                    // so it's on the text instead of a plate.
                    Label {
                        id: chordFace
                        // wayscriber wins ties over a real submap here on
                        // purpose — the two are mutually exclusive in
                        // practice (submaps grab the keyboard, wayscriber's
                        // own overlay does too), so this is just "which
                        // lookup", never a real conflict.
                        readonly property var entry: demo.drawActive
                            ? demo.submapMap["draw"]
                            : (demo.submapMap[demo.submapName] || null)
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: demo.drawActive
                            ? (chordFace.entry ? chordFace.entry.text : "DRAW")
                            : demo.submapName === "" ? ""
                                : (chordFace.entry ? chordFace.entry.text : demo.submapName.toUpperCase())
                        fg: chordFace.entry ? chordFace.entry.colour : BarTheme.accent
                        font.bold: true
                        opacity: swap.activeFace === "chord" ? 1 : 0
                        visible: opacity > 0.01
                        Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                    }

                    // THE NOTIFICATION FACE — "can we make workspace part
                    // also the notification part?" NotificationServer
                    // (Quickshell.Services.Notifications) is what
                    // tide-island-fork/qml/common/NotificationService.qml
                    // uses, and it is a ONE-OWNER job: whichever process
                    // instantiates it registers as THE org.freedesktop.
                    // Notifications bus name, and that file's own header
                    // spells out the hazard of two of those existing at
                    // once ("notifications stop system-wide"). The island
                    // is that owner on this session RIGHT NOW (checked:
                    // `pgrep -fa tide-island-fork` was running), so this
                    // reads the bus instead of owning it — `busctl --user
                    // monitor`, which is a passive eavesdropper and claims
                    // nothing, piped through `jq` for exactly the one
                    // event that matters (member Notify on that interface,
                    // [app, summary, body]). Safe with the island running
                    // AND with it stopped, unlike a second NotificationServer
                    // would have been.
                    Label {
                        id: notifyFace
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.horizontalCenter: parent.horizontalCenter
                        // Just the content — no "app : " prefix, asked
                        // directly to drop that.
                        text: demo.notifyApp !== ""
                            ? (demo.notifySummary
                               + (demo.notifyBody !== "" ? " — " + demo.notifyBody : ""))
                            : ""
                        fg: BarTheme.accent
                        font.bold: true
                        opacity: swap.activeFace === "notify" ? 1 : 0
                        visible: opacity > 0.01
                        Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                    }

                    // THE VOICE FACE — "when i run it the workspace part
                    // change to be this voice wave like thing". State word
                    // plus the five-bar wave (see VoiceBar above); the bars
                    // only run their pulse animation while
                    // demo.voiceState === "recording", and just sit at their
                    // resting height for transcribing/done/failed so the
                    // face still reads as "something is happening" without
                    // implying audio is still being captured.
                    Row {
                        id: voiceFace
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: Metrics.s(6)
                        opacity: swap.activeFace === "voice" ? 1 : 0
                        visible: opacity > 0.01
                        Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            text: demo.voiceState.toUpperCase()
                            fg: BarTheme.accent
                            font.bold: true
                        }
                        Item {
                            anchors.verticalCenter: parent.verticalCenter
                            width: barRow.implicitWidth
                            height: Metrics.s(11)
                            Row {
                                id: barRow
                                anchors.bottom: parent.bottom
                                spacing: Metrics.s(2)
                                Repeater {
                                    model: 5
                                    delegate: VoiceBar {}
                                }
                            }
                        }
                    }

                }
            }

            // Middle-click anywhere on the workspace pill opens the
            // notification centre — "create a notification center opening
            // from the workspace part". A SIBLING overlay rather than a
            // MouseArea declared inside centerStrip: Strip's `default
            // property alias content: row.children` (see its own
            // definition) captures any child declared inside a `Strip {}`
            // block straight into its inner Row's layout, which would
            // hand this MouseArea horizontal space next to the workspace
            // icons instead of just sitting over them. Tracking
            // centerStrip's own geometry by binding instead keeps it out
            // of that layout entirely. Middle-button only, so left-clicks
            // still reach the workspace pills' own MouseAreas underneath —
            // Qt Quick keeps probing past an item that doesn't accept the
            // pressed button, it doesn't just stop at the topmost one.
            MouseArea {
                x: centerStrip.x
                y: centerStrip.y
                width: centerStrip.width
                height: centerStrip.height
                acceptedButtons: Qt.MiddleButton
                onClicked: demo.notifCenterOpen = !demo.notifCenterOpen
            }

            // ================= RIGHT =================
            Row {
                id: rightRow
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                height: content.height
                spacing: Metrics.s(7)
                opacity: bar.rightOpacity
                Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutQuad } }

                // Chord/submap slot — REMOVED. "i dont want the one open
                // in the right handside remove it since the one in the
                // workspace is good" — the centre pill's own takeover
                // (swap/chordFace, above) is the only place the active
                // mode shows now; this used to be a second, redundant copy
                // of the same text sitting off to the side.

                // ONE chip now, not three — "the cpu and the [updates
                // chip] in the same chip". Lamp leads (asked for
                // directly, "most left"), then the cpu/stats toggle,
                // then the nightlight/QR/updates toggle. Each keeps its
                // own independent open state and MouseArea; they just
                // share one Strip/plate instead of each getting its own.
                Strip {
                    id: utilStrip
                    property bool statsOpen: false
                    property bool trayOpen: false

                    // Lamp/tips — leftmost, per direct ask. Used to shell
                    // out to `eww open/close onboarding-welcome`, a whole
                    // separate GTK app; ported to TourPopup.qml (QML, styled
                    // off PopupChrome/IslandTheme like the menu/wifi/display
                    // popups — see that file's own header for the full
                    // rationale and what changed in the content).
                    //
                    // The old flash-then-reset existed only because eww's
                    // `close || open` toggle never reported which way it
                    // landed — this side could never actually KNOW if the
                    // window was open, hence a press-flash instead of a
                    // real state. Now the popup's `visible` IS the state,
                    // owned here directly, so the glyph can just track it
                    // for real instead of faking an acknowledgement.
                    Glyph {
                        id: lampGlyph
                        text: String.fromCodePoint(0xF0336)
                        fg: tourPopup.visible ? BarTheme.accent : BarTheme.alpha(BarTheme.fg, 0.7)
                        Behavior on fg { ColorAnimation { duration: 200 } }
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -Metrics.s(5)
                            hoverEnabled: true
                            onClicked: tourPopup.visible = !tourPopup.visible
                            onEntered: barTooltip.enter(parent, "Tips (💡) · click → toggle onboarding")
                            onExited: barTooltip.exit(parent)
                        }
                    }

                    Divider {}

                    // CPU/mem + volume/brightness. Closed = just the
                    // cpu-icon; clicking it only opens the box — same
                    // split shell.qml has between "toggle the box" and
                    // "click the chip inside it". Each revealed value is
                    // its own StatBadge (icon+number in one enclosure,
                    // "like the battery" — asked for directly, replacing
                    // the icon-then-separate-label Row that ate too much
                    // width) and carries the REAL click action the
                    // equivalent chip has on the current bar: RAM ->
                    // btop, CPU -> missioncenter, volume L-click -> mute
                    // toggle / R-click -> pavucontrol. All four values are
                    // real now (demo.statMem/statCpu/statVolume/
                    // statBrightness — see their own sources further up),
                    // not the mock "4.2G/12%/65%/80%" strings this carried
                    // through every earlier round. Brightness still has no
                    // shell.qml equivalent to copy (it was invented for
                    // this mock's 4-stat layout from the start), so its
                    // real source is `brightnessctl -m` rather than a
                    // ported one.
                    Glyph {
                        visible: !utilStrip.statsOpen
                        text: String.fromCodePoint(0xF4BC)   // oct-cpu
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -Metrics.s(5)
                            hoverEnabled: true
                            onClicked: utilStrip.statsOpen = true
                            onEntered: barTooltip.enter(parent, "CPU + Memory + Volume + Brightness")
                            onExited: barTooltip.exit(parent)
                        }
                    }
                    Row {
                        visible: utilStrip.statsOpen
                        // "reduce the space between" the badges — was
                        // Metrics.s(5).
                        spacing: Metrics.s(3)
                        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                        StatBadge {
                            icon: 0xEFC5; value: demo.statMem; tint: BarTheme.cyan   // fa-memory
                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: Quickshell.execDetached(
                                    ["kitty", "--start-as=fullscreen", "-e", "btop"])
                                onEntered: barTooltip.enter(parent, "RAM used · click → btop")
                                onExited: barTooltip.exit(parent)
                            }
                        }
                        StatBadge {
                            icon: 0xF4BC; value: demo.statCpu; tint: BarTheme.purple  // oct-cpu
                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: Quickshell.execDetached(
                                    ["env", "GTK_THEME=Adwaita:dark", "missioncenter"])
                                onEntered: barTooltip.enter(parent, "CPU load · click → mission-center")
                                onExited: barTooltip.exit(parent)
                            }
                        }
                        Divider {}
                        StatBadge {
                            icon: 0xF028; value: demo.statVolume; tint: BarTheme.green   // fa-volume_up
                            MouseArea {
                                anchors.fill: parent
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                hoverEnabled: true
                                onClicked: (mouse) => {
                                    if (mouse.button === Qt.RightButton)
                                        Quickshell.execDetached(["pavucontrol"]);
                                    else
                                        Quickshell.execDetached(["wpctl", "set-mute",
                                            "@DEFAULT_AUDIO_SINK@", "toggle"]);
                                    volPollSoon.restart();
                                }
                                onEntered: barTooltip.enter(parent, "Volume · click: mute · right-click: mixer")
                                onExited: barTooltip.exit(parent)
                            }
                        }
                        StatBadge {
                            icon: 0xF0599; value: demo.statBrightness; tint: BarTheme.yellow // md-weather_sunny
                            MouseArea {
                                anchors.fill: parent
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                hoverEnabled: true
                                onClicked: (mouse) => {
                                    Quickshell.execDetached(
                                        ["brightnessctl", "set",
                                         mouse.button === Qt.RightButton ? "5%-" : "5%+"]);
                                    brightnessPollSoon.restart();
                                }
                                onEntered: barTooltip.enter(parent, "Brightness · click: +5% · right-click: -5%")
                                onExited: barTooltip.exit(parent)
                            }
                        }
                    }
                    Glyph {
                        visible: utilStrip.statsOpen
                        text: String.fromCodePoint(0xF105)
                        fg: BarTheme.accent
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -Metrics.s(5)
                            onClicked: utilStrip.statsOpen = false
                        }
                    }

                    Divider {}

                    // Nightlight / Wi-Fi-QR / updates — same expand
                    // pattern, independent open state, and the SAME real
                    // actions shell.qml's tray box wires up: nightlight
                    // L-click on / R-click off (hyprsunset), Wi-Fi QR
                    // opens the island's popups shell, updates toggles
                    // qupdate.py. The closed-state trigger just opens the
                    // box, matching the box/chip split above.
                    Glyph {
                        visible: !utilStrip.trayOpen
                        // Was 0xF06B0 (nf-md-update) — a 5-hex-digit
                        // Supplementary-PUA codepoint this system's
                        // installed Nerd Font patches (JetBrainsMono/
                        // FiraMono/FiraCode, per `pacman -Qs nerd` — there
                        // is no standalone "Symbols Nerd Font" here at
                        // all) don't carry, so it rendered as broken
                        // fallback glyph/hex text instead of an icon
                        // (screenshotted: "b0" next to a stray clock
                        // shape). fa-ellipsis-h (0xF141) is a plain
                        // 4-hex FontAwesome codepoint — the same block
                        // fa-memory/fa-volume_up/oct-cpu already render
                        // from correctly — and reads honestly as "more
                        // than one thing lives behind this icon".
                        text: String.fromCodePoint(0xF141)   // fa-ellipsis-h
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -Metrics.s(5)
                            hoverEnabled: true
                            onClicked: utilStrip.trayOpen = true
                            onEntered: barTooltip.enter(parent, "Nightlight · Wi-Fi QR · Updates")
                            onExited: barTooltip.exit(parent)
                        }
                    }
                    Row {
                        visible: utilStrip.trayOpen
                        spacing: Metrics.s(8)
                        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                        Glyph {
                            // Was 0xF1A4C — same broken-codepoint problem as
                            // the toggle icon above. fa-moon-o (0xF186) is
                            // the standard 4-hex nightlight/moon glyph.
                            text: String.fromCodePoint(0xF186)   // fa-moon-o
                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -Metrics.s(5)
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                hoverEnabled: true
                                onClicked: (mouse) => Quickshell.execDetached(
                                    ["sh", "-c", mouse.button === Qt.RightButton
                                        ? "hyprctl hyprsunset identity"
                                        : "pgrep -x hyprsunset >/dev/null 2>&1 || "
                                          + "setsid hyprsunset >/dev/null 2>&1 & "
                                          + "sleep 0.2; hyprctl hyprsunset temperature 4000"])
                                onEntered: barTooltip.enter(parent, "Nightlight · L: on · R: off")
                                onExited: barTooltip.exit(parent)
                            }
                        }
                        Glyph {
                            text: String.fromCodePoint(0xF029)    // Wi-Fi QR
                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -Metrics.s(5)
                                hoverEnabled: true
                                onClicked: Quickshell.execDetached([
                                    "qs", "-p",
                                    Quickshell.env("HOME")
                                        + "/.config/quickshell/tide-island-fork/popups.qml",
                                    "ipc", "call", "popups", "wifiqr"])
                                onEntered: barTooltip.enter(parent, "Wi-Fi QR")
                                onExited: barTooltip.exit(parent)
                            }
                        }
                        Glyph {
                            // Was 0xF06B0 too — see the toggle icon's note
                            // above. fa-refresh (0xF021) is the standard
                            // 4-hex "circular arrows" icon and reads as
                            // "updates" on its own, unlike the ellipsis
                            // used for the collapsed toggle.
                            text: String.fromCodePoint(0xF021)   // fa-refresh
                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -Metrics.s(5)
                                hoverEnabled: true
                                onClicked: Quickshell.execDetached(
                                    ["python3", Quickshell.env("HOME")
                                        + "/.config/qtile/scripts/qupdate.py", "--toggle"])
                                onEntered: barTooltip.enter(parent, "Pending updates · click → update manager")
                                onExited: barTooltip.exit(parent)
                            }
                        }
                    }
                    Glyph {
                        visible: utilStrip.trayOpen
                        text: String.fromCodePoint(0xF105)
                        fg: BarTheme.accent
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -Metrics.s(5)
                            onClicked: utilStrip.trayOpen = false
                        }
                    }
                }

                // Battery: THIRD attempt, and this time hand-drawn rather
                // than relying on a font glyph's internal geometry, which
                // is exactly what kept going wrong — first a portrait
                // phone-style cell (wrong shape), then a solid fill eating
                // the number's contrast, then a hollow glyph whose "centre"
                // still wasn't where the text actually needed to sit. Two
                // plain Rectangles (body + nub) means the text is
                // anchored to a box THIS code drew, not to a glyph's
                // undocumented padding — centring is exact by
                // construction, not by guessing at a font's metrics.
                // Battery click -> ati-battery-notify, EN click ->
                // switch keyboard layout, same as shell.qml's own
                // battery/language chips.
                Strip {
                    // Real now: hidden entirely on a desktop with no
                    // laptop battery, same condition shell.qml's own
                    // battery chip uses.
                    visible: UPower.displayDevice && UPower.displayDevice.isLaptopBattery
                    Item {
                        id: batteryIcon
                        width: Metrics.s(22)
                        height: Metrics.s(12)
                        anchors.verticalCenter: parent ? parent.verticalCenter : undefined

                        Rectangle {
                            id: battBody
                            width: parent.width - Metrics.s(3)
                            height: parent.height
                            radius: Metrics.s(2)
                            color: "transparent"
                            border.width: Metrics.s(1)
                            border.color: BarTheme.alpha(BarTheme.fg, 0.85)

                            Label {
                                anchors.centerIn: parent
                                anchors.verticalCenter: undefined
                                text: UPower.displayDevice
                                    ? String(Math.round(UPower.displayDevice.percentage * 100))
                                    : "--"
                                // shell.qml's own batteryLow/battery colour,
                                // verbatim: BarTheme.blue normally,
                                // BarTheme.red at/under 20%. Plain fg (the
                                // first pass here) read as uncoloured next
                                // to shell.qml's actual chip — "should be
                                // coloured" was exactly that gap.
                                fg: (UPower.displayDevice && UPower.displayDevice.isLaptopBattery
                                     && UPower.displayDevice.percentage <= 0.2)
                                    ? BarTheme.red : BarTheme.blue
                                font.pixelSize: Metrics.s(7)
                                font.bold: true
                            }
                        }
                        Rectangle {
                            x: battBody.width
                            width: Metrics.s(3)
                            height: parent.height * 0.5
                            anchors.verticalCenter: battBody.verticalCenter
                            radius: Metrics.s(1)
                            color: BarTheme.alpha(BarTheme.fg, 0.85)
                        }
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -Metrics.s(4)
                            hoverEnabled: true
                            onClicked: Quickshell.execDetached(["ati-battery-notify"])
                            onEntered: barTooltip.enter(parent, "Battery · click → status")
                            onExited: barTooltip.exit(parent)
                        }
                    }
                    Divider {}
                    // Real current layout (polled every 2s off `hyprctl -j
                    // devices`). REVERSED BACK per the follow-up: opening
                    // the `lang` submap was the wrong fix — what was
                    // actually asked for is a plain cycle, L-click forward
                    // (en -> ar -> tr -> ...), R-click backward, same
                    // direction convention as the layout chip's R-click in
                    // shell.qml. Bug behind it not moving before: this
                    // MouseArea never declared acceptedButtons, so the
                    // right-click branch was unreachable — same root
                    // cause as the Arch icon's terminal not opening.
                    Label {
                        text: demo.layoutCode
                        fg: BarTheme.fg
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -Metrics.s(4)
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            hoverEnabled: true
                            onClicked: (mouse) => {
                                Quickshell.execDetached(
                                    ["hyprctl", "switchxkblayout", "all",
                                     mouse.button === Qt.RightButton ? "prev" : "next"]);
                                kbPollSoon.restart();
                            }
                            onEntered: barTooltip.enter(parent, "Keyboard layout")
                            onExited: barTooltip.exit(parent)
                        }
                    }
                }

                // Clock click -> clock_popup, same as the current bar.
                // Text is REAL now (ticking Timer), not a fixed string.
                Strip {
                    Label {
                        text: demo.clockText
                        fg: BarTheme.accent
                        font.bold: true
                        font.pixelSize: Metrics.textSize + 1
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -Metrics.s(4)
                            hoverEnabled: true
                            onEntered: barTooltip.enter(parent, "Clock · click → clock_popup")
                            onExited: barTooltip.exit(parent)
                            onClicked: Quickshell.execDetached(["clock_popup"])
                        }
                    }
                }
            }
        }

    }

    // ---- THE RESERVER — ported straight from shell.qml ----
    //
    // "the gap still should be gap between bar and apps" — this bar has
    // always been ExclusionMode.Ignore (see `bar` above), which means
    // Hyprland reserves NOTHING for it: tiled windows render right up to
    // the true screen edge, and the bar just floats on top, overlapping
    // them. There was never a gap to fix in utilStrip's own padding
    // because the missing gap was never internal to a pill — it was this.
    //
    // shell.qml solves it with a SEPARATE invisible surface whose only
    // job is to hold the exclusive zone the visible bar gave up (its own
    // header: "An invisible, input-transparent strip whose ONLY job is to
    // hold the exclusive zone the bar above gave up") — kept separate so
    // the TreeTab sidebar's own zone isn't shoved around by the bar
    // itself needing Ignore for other reasons. Ported verbatim rather
    // than just flipping `bar`'s own exclusionMode, since that would
    // reintroduce whatever `bar` needs Ignore for.
    Variants {
        model: Quickshell.screens

        PanelWindow {
            required property var modelData
            screen: modelData
            // Same edge as `bar` itself (demo.position) — shell.qml's own
            // reserver does the identical thing: "Anchored to whichever
            // edge the live bar is on".
            anchors {
                top: demo.position === "top"
                bottom: demo.position === "bottom"
                left: true
                right: true
            }
            implicitHeight: 1
            exclusiveZone: (demo.position === "top"
                ? Metrics.barHeight : Metrics.bottomBarHeight) + Metrics.marginV * 2
            color: "transparent"
            // No input at all — otherwise this strip eats clicks along
            // the very top edge of the screen.
            mask: Region {}
        }
    }

    TourPopup {
        id: tourPopup
        visible: false
    }

    NotificationCenter {
        id: notificationCenter
        visible: demo.notifCenterOpen
        onRequestClose: demo.notifCenterOpen = false
        // Hangs under centerStrip on the top bar; same reasoning as
        // Tooltip's own belowTarget fix — hanging below unconditionally
        // would render off the bottom of the screen once the bar can
        // actually sit down there, so this hangs ABOVE `bar` instead in
        // that position.
        anchorX: Metrics.marginH + centerStrip.x + centerStrip.width / 2
        anchorTop: demo.position === "top"
            ? bar.margins.top + bar.implicitHeight + Metrics.s(4)
            : (bar.screen ? bar.screen.height : 768) - bar.margins.bottom
                - bar.implicitHeight - notificationCenter.popupHeight - Metrics.s(4)
    }

    // Driveable from a script — same reasoning shell.qml's own IpcHandler
    // gives: a control with no way in from a script is a control whose
    // bugs only the user finds. Added specifically so the stat badges can
    // be inspected by screenshot (`qs -p redesign-e-final.qml ipc call
    // statbadge show`) without a real click, since this is a standalone
    // preview with no compositor keybind wired to it.
    IpcHandler {
        target: "statbadge"
        // "open", not "show" — see notifcenter's own note on the
        // `qs ipc call <target> show` name collision.
        function open(): void { utilStrip.statsOpen = true; }
        function hide(): void { utilStrip.statsOpen = false; }
    }

    // "i want the notification center works with alt+`" — the direct IPC
    // surface (middle-click on the workspace pill calls the same
    // functions). shell.qml is no longer the active bar ("the qtile like
    // one will be disabled"), so Alt+`/Win+` are no longer live binds of
    // its — see the `target: "topbar"` handler below, which is what
    // ati-bar-action's `bar systemBox`/`bar secondBox` now actually call.
    IpcHandler {
        target: "notifcenter"
        function toggle(): void { demo.notifCenterOpen = !demo.notifCenterOpen; }
        // NOT "show" — `qs ipc call <target> show` misparses and prints
        // the target's function listing instead of calling it, the same
        // collision `statbadge show` hit earlier in this file (worked
        // around there by renaming to `showAll`). "show" apparently
        // collides with `qs ipc show`'s own subcommand name somewhere in
        // the CLI's argument parsing.
        function open(): void { demo.notifCenterOpen = true; }
        function hide(): void { demo.notifCenterOpen = false; }
    }

    // ati-bar-action's `bar` target ($alt ` / $mod ` / $alt Tab) calls
    // THIS — "target: topbar", matching the name it always called even
    // when that meant shell.qml. Realigned onto the same abstract slot the
    // ISLAND already uses these two keys for (its own systemBox opens
    // notifications, secondBox opens the system monitor) rather than kept
    // on shell.qml's literal CPU-box/updates-box split, which this bar
    // doesn't have as two separate boxes.
    IpcHandler {
        target: "topbar"
        function toggleNotifCenter(): void { demo.notifCenterOpen = !demo.notifCenterOpen; }
        function toggleStats(): void { utilStrip.statsOpen = !utilStrip.statsOpen; bar.wakeRight(); }
        function toggleTrayBox(): void { utilStrip.trayOpen = !utilStrip.trayOpen; bar.wakeRight(); }
        // Win+Shift+Z, ported from shell.qml's own `topbar toggle`/`status`.
        function toggle(): void { demo.setPosition(demo.position === "top" ? "bottom" : "top"); }
        function status(): string { return demo.position; }
    }

    // Debug-only, for screenshotting without a real mouse: forces both
    // auto-hidden clusters back to full opacity and freezes the timers
    // that would fade them again mid-screenshot.
    IpcHandler {
        target: "debugview"
        function showAll(): void {
            bar.leftOpacity = 1;
            bar.rightOpacity = 1;
            leftHideTimer.stop();
            rightHideTimer.stop();
            utilStrip.statsOpen = true;
        }
        function forceVoice(state: string): void { demo.voiceState = state; }
    }
}
