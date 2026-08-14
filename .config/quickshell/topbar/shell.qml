import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.UPower
import Quickshell.Services.SystemTray
import Quickshell.Services.Mpris

//
// ============================================================
//  The Hyprland topbar — qtile's bar, reimplemented
// ============================================================
//
// The `native` half of AtiScriptsV1/bar-switch on Hyprland. The island is the
// other half; this is what you get when you ask for the session's own bar.
//
// It is a REIMPLEMENTATION and could never be anything else: qtile's bar is
// part of qtile, and qtile is an X11 window manager. What is reproduced is
// the layout, the order, the chip decoration, the palette and the formats —
// all of it extracted from config.py's AST rather than read off its comments.
// The inventory and the build order are in ../../hypr/TOPBAR-SPEC.md.
//
// WHAT IS DELIBERATELY ABSENT
// ---------------------------
//   hintium_mode_chip   Hintium is X11-native; binds.conf records it as
//                       BLOCKED rather than unported, so there is no mode
//                       for this chip to display.
//   chord_chip          Hyprland has submaps, not qtile KeyChords, and the
//                       island already renders the submap name — that is
//                       what submap-indicator.sh is for. Duplicating it here
//                       would put the same string on screen twice whenever
//                       both bars' features overlap.
//
// Everything else on the right-hand side is here, in config.py's order.
ShellRoot {
    id: shellRoot

    // ---- THE SINGLETON TOUCH ----
    //
    // A QML singleton is constructed on FIRST ACCESS. If the first access is a
    // paint binding, the palette's FileView has not run yet and the bar draws
    // one frame of fallback DoomOne before repainting. IslandTheme's header
    // records the same trap and the same fix.
    Component.onCompleted: {
        BarTheme.themeName;
        Metrics.scale;
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: bar
            required property var modelData
            screen: modelData

            anchors { top: true; left: true; right: true }
            implicitHeight: Metrics.barHeight + Metrics.marginV * 2
            margins { top: 0 }

            // bar.Bar(background="#11111b00") — FULLY TRANSPARENT. Every
            // visible pixel on this bar is a chip, and that is load-bearing
            // rather than cosmetic: a bar that maps with unpainted widgets is
            // indistinguishable from no bar at all, which is exactly how the
            // qtile side of bar-switch failed and why it needs a rebuild
            // rather than an un-hide. If this bar ever looks absent, check
            // that the chips are painting before checking that it is mapped.
            color: "transparent"

            // The bar reserves its own strip, as qtile's does.
            exclusiveZone: Metrics.barHeight + Metrics.marginV * 2

            // ---- THE TASKLIST CAP ----
            //
            // _center_top_groupbox()'s arithmetic, as one expression, and it is the
            // reason this bar does not use two stretch spacers. Two STRETCH spacers
            // split only the LEFTOVER space evenly, so the GroupBox slid right as the
            // TaskList grew with each opened window — at 605 px it was already past
            // the bar's centre, and no spacer value can undo that.
            //
            // Two caps, and the SECOND one is the one that was learned the hard way
            // there. Reaching the centre group is the obvious limit. The other is
            // what is genuinely left once the RIGHT-hand side has been paid for: the
            // right side is the only thing that can grow without warning (a widget
            // box opening, an MPRIS title arriving), and once it exceeded the
            // spacer's slack the surplus ran off the end of the bar and the tray,
            // being last, was what disappeared.
            //
            // Floored at zero. A negative width is not a narrow list, it is a
            // backwards one.
            readonly property real taskListWidth: {
                const gap = Metrics.s(6);
                const toCentre = centreGroup.x - leftFixed.width - gap;
                const fits = content.width - leftFixed.width - centreGroup.width
                    - rightGroup.width - gap * 2;
                return Math.max(0, Math.min(toCentre, fits));
            }

            Item {
                id: content
                anchors.fill: parent
                anchors.topMargin: Metrics.marginV
                anchors.bottomMargin: Metrics.marginV
                anchors.leftMargin: Metrics.marginH
                anchors.rightMargin: Metrics.marginH

                // ================= LEFT =================
                Row {
                    id: leftFixed
                    anchors.left: parent.left
                    height: parent.height
                    spacing: 0

                    // config.py's ARCH_ICON_MAIN, U+F0570 — the four-square
                    // grid, and its EXACT codepoint rather than a lookalike.
                    //
                    // It is supplementary-plane, which NEXT-SESSION.md says
                    // renders as nothing in this shell. That note is too
                    // broad: probed by drawing twelve codepoints side by side
                    // in a panel and looking at them, U+F0570 and six other
                    // supplementary glyphs rendered correctly in the SAME run
                    // as the BMP ones. The variable is the FACE — they render
                    // in "Symbols Nerd Font". See WidgetBox.qml.
                    //
                    // fromCodePoint, never fromCharCode: the latter takes a
                    // UTF-16 code unit and silently truncates above U+FFFF.
                    Chip {
                        text: String.fromCodePoint(0xF0570)
                        foreground: BarTheme.purple      // colors[7]
                        padding: 11
                        fontPixelSize: Metrics.s(15)
                        fontFamily: "Symbols Nerd Font"
                        clickable: true
                        height: parent.height
                        // config.py's map, kept: L docs, M terminal, R launcher.
                        // Terminal is on MIDDLE rather than dropped because
                        // muscle memory is real, and $mod Return still does it.
                        onClicked: (b) => {
                            if (b === Qt.LeftButton)
                                Quickshell.execDetached(["qs", "-p", shellRoot.islandPath,
                                                         "ipc", "call", "tide",
                                                         "showCheatsheet", "docs"]);
                            else if (b === Qt.MiddleButton)
                                Quickshell.execDetached(["kitty"]);
                            else
                                Quickshell.execDetached(["qs", "-p", shellRoot.islandPath,
                                                         "ipc", "call", "tide",
                                                         "toggleApplicationLauncher"]);
                        }
                    }

                    // The layout name, in text as qtile shows it. Right-click
                    // cycles, which is config.py's Button3 on this chip.
                    Chip {
                        text: shellRoot.layoutName
                        foreground: BarTheme.red         // colors[3]
                        padding: 18
                        clickable: true
                        height: parent.height
                        onClicked: (b) => {
                            if (b === Qt.RightButton)
                                Quickshell.execDetached([
                                    Quickshell.env("HOME")
                                        + "/.config/hypr/scripts/layout-cycle.sh", "next"]);
                        }
                    }

                }

                // The task list. A SIBLING of leftFixed, not a child, and
                // that is required rather than tidy: its width is derived
                // from leftFixed.width, so nesting it inside would make that
                // Row's width depend on its own child's width — a binding
                // loop, and QML resolves those by silently dropping one side.
                TaskList {
                    id: taskList
                    anchors.left: leftFixed.right
                    height: parent.height
                    width: bar.taskListWidth
                    clip: true
                }

                // ================= CENTRE =================
                //
                // ---- WHY THIS IS NOT TWO STRETCH SPACERS ----
                //
                // config.py's _center_top_groupbox() exists because two
                // STRETCH spacers only split the LEFTOVER space evenly, so the
                // GroupBox slid right as the TaskList grew with each opened
                // window — at 605 px it was already past the bar's centre, and
                // no spacer value can undo that.
                //
                // The RULE is ported, not the code: the group is pinned to the
                // true centre of the bar, and the TaskList is capped by what
                // is actually left once the right-hand side has been paid for.
                // Centring yields to fitting, exactly as it does there — the
                // workspaces drift off-centre only when there is no
                // alternative, rather than the right-hand end running off the
                // bar.
                Workspaces {
                    id: centreGroup
                    anchors.horizontalCenter: parent.horizontalCenter
                    height: parent.height
                }

                // ================= RIGHT =================
                //
                // config.py's order, exactly: tooltip, mpris, system box,
                // wallpaper toggle, 2nd system box, battery, language, clock,
                // systray box. Four of these are WidgetBoxes — collapsed to a
                // toggle glyph until clicked — and that is why this side of
                // the bar has two widths and why the tasklist cap above has to
                // survive both.
                Row {
                    id: rightGroup
                    anchors.right: parent.right
                    height: parent.height
                    spacing: 0

                    // tooltip_widgetbox — the lamp. config.py's tooltip text is
                    // "Tips (lamp) · click → toggle onboarding", so the toggle
                    // opens the tour rather than a widget group. The island
                    // owns the onboarding and has an IPC for it.
                    Chip {
                        text: String.fromCodePoint(0xF0336)
                        foreground: BarTheme.fg          // colors[1]
                        padding: 11
                        fontPixelSize: Metrics.s(12)
                        fontFamily: "Symbols Nerd Font"
                        clickable: true
                        height: parent.height
                        onClicked: Quickshell.execDetached(
                            ["qs", "-p", shellRoot.islandPath, "ipc", "call",
                             "tide", "showOnboarding", "0"])
                    }

                    // MPRIS. Empty with no player, and Chip takes no width at
                    // all then rather than leaving a bare plate on the bar.
                    Chip {
                        text: shellRoot.mprisText
                        foreground: BarTheme.green       // colors[4]
                        padding: 10
                        fontPixelSize: Metrics.s(15)
                        height: parent.height
                    }

                    // system_widgetbox — CPU and memory.
                    WidgetBox {
                        codepointClosed: 0xF05AF
                        codepointOpen: 0xF05B0
                        foreground: BarTheme.purple      // colors[7]
                        fontPixelSize: Metrics.s(15)
                        padding: 10
                        height: parent.height

                        Chip {
                            text: shellRoot.cpuText
                            foreground: BarTheme.purple
                            padding: 11
                            fontPixelSize: Metrics.s(10)
                            height: parent.height
                        }
                        Chip {
                            text: shellRoot.memText
                            foreground: BarTheme.cyan
                            padding: 11
                            fontPixelSize: Metrics.s(10)
                            height: parent.height
                        }
                    }

                    // wallpaper_toggle. U+2716 is a plain heavy multiplication
                    // X, not a Nerd Font icon — qtile's choice, kept.
                    WidgetBox {
                        codepointClosed: 0x2716
                        codepointOpen: 0xF035C
                        foreground: BarTheme.cyan        // colors[8]
                        fontPixelSize: Metrics.s(13)
                        padding: 11
                        height: parent.height

                        Chip {
                            text: "wallpaper"
                            foreground: BarTheme.cyan
                            padding: 11
                            fontPixelSize: Metrics.s(10)
                            clickable: true
                            height: parent.height
                            onClicked: Quickshell.execDetached(
                                ["qs", "-p", shellRoot.islandPath, "ipc", "call",
                                 "tide", "toggleWallpaperPicker"])
                        }
                    }

                    // 2nd_system_widgetbox — disk and volume. config.py also
                    // carries CheckUpdates here; that is qupdate.py's, and it
                    // is left out rather than reimplemented badly, because the
                    // count it shows comes from a daemon this bar does not own.
                    WidgetBox {
                        codepointClosed: 0xF0902
                        codepointOpen: 0xF0042
                        foreground: BarTheme.yellow      // colors[5]
                        fontPixelSize: Metrics.s(14)
                        padding: 10
                        height: parent.height

                        Chip {
                            text: shellRoot.diskText
                            foreground: BarTheme.fg
                            padding: 11
                            fontPixelSize: Metrics.s(10)
                            height: parent.height
                        }
                        Chip {
                            text: shellRoot.volumeText
                            foreground: BarTheme.purple
                            padding: 11
                            fontPixelSize: Metrics.s(10)
                            clickable: true
                            height: parent.height
                            onClicked: Quickshell.execDetached(
                                ["qs", "-p", shellRoot.islandPath, "ipc", "call",
                                 "tide", "toggleAudioPanel"])
                        }
                    }

                    // Battery, only on a machine that has one — config.py
                    // splats it in conditionally for the same reason.
                    Chip {
                        active: UPower.displayDevice
                            && UPower.displayDevice.isLaptopBattery
                        text: shellRoot.batteryText
                        // colors[6], falling to colors[3] under 20%, which is
                        // config.py's low_foreground / low_percentage pair.
                        foreground: shellRoot.batteryLow ? BarTheme.red : BarTheme.blue
                        padding: 12
                        fontPixelSize: Metrics.s(10)
                        height: parent.height
                    }

                    Chip {
                        text: shellRoot.keyboardLayout
                        foreground: BarTheme.green       // colors[4]
                        padding: 11
                        height: parent.height
                    }

                    // format=" %a, %b %d - %H:%M", verbatim.
                    Chip {
                        text: shellRoot.clockText
                        foreground: BarTheme.cyan        // colors[8]
                        padding: 11
                        clickable: true
                        height: parent.height
                        onClicked: Quickshell.execDetached(
                            ["qs", "-p", shellRoot.islandPath, "ipc", "call",
                             "tide", "toggleCalendar"])
                    }

                    // systray_widgetbox. U+25B3 is a plain geometric triangle
                    // rather than a Nerd Font icon, and config.py is emphatic
                    // about it: "chosen for its silhouette rather than for
                    // consistency with the others. Do not correct it to a
                    // chevron again." The OPEN state is a chevron (U+F053),
                    // which is the correction it is warning about — the two
                    // states are deliberately different kinds of mark.
                    WidgetBox {
                        codepointClosed: 0x25B3
                        codepointOpen: 0xF053
                        foreground: BarTheme.green       // colors[4]
                        fontPixelSize: Metrics.s(11)
                        padding: 11
                        height: parent.height

                        Tray {
                            height: parent.height
                        }
                    }
                }
            }
        }
    }

    // ---------------------------------------------------------------
    //  State the chips read
    // ---------------------------------------------------------------

    readonly property string islandPath:
        Quickshell.env("HOME") + "/.config/quickshell/tide-island-fork"

    // ---- CLOCK ----
    //
    // A one-second tick, not a one-minute one: a clock that updates on the
    // minute drifts up to 59 s from the system time on any resume, and the
    // cost of the extra ticks is one Date and one string.
    property string clockText: ""
    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            const d = new Date();
            const days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
            const months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                            "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
            const p = (n) => (n < 10 ? "0" + n : String(n));
            // " %a, %b %d - %H:%M". The leading space is config.py's and is
            // kept: it is what stops the text touching the plate's left round.
            shellRoot.clockText = " " + days[d.getDay()] + ", " + months[d.getMonth()]
                + " " + p(d.getDate()) + " - " + p(d.getHours()) + ":" + p(d.getMinutes());
        }
    }

    // ---- CPU / MEMORY, FROM /proc ----
    //
    // Read directly rather than shelled out to. config.py's widgets use
    // psutil; a Process per tick per widget would be four processes a second
    // for two numbers, which is the cost this repo already criticises
    // HyprlandData for.
    property string cpuText: ""
    property string memText: ""
    property real _lastIdle: 0
    property real _lastTotal: 0

    FileView {
        id: statFile
        path: "/proc/stat"
        printErrors: false
    }
    FileView {
        id: memFile
        path: "/proc/meminfo"
        printErrors: false
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            statFile.reload();
            memFile.reload();
        }
    }

    Connections {
        target: statFile
        function onLoaded() {
            const line = statFile.text().split("\n")[0];      // "cpu  u n s i ..."
            const f = line.trim().split(/\s+/).slice(1).map(Number);
            if (f.length < 4) return;
            const idle = f[3] + (f[4] || 0);
            const total = f.reduce((a, b) => a + b, 0);
            const dT = total - shellRoot._lastTotal;
            const dI = idle - shellRoot._lastIdle;
            shellRoot._lastTotal = total;
            shellRoot._lastIdle = idle;
            // The first tick has no previous sample to difference against, so
            // it reports nothing rather than 100%.
            if (dT > 0 && shellRoot.cpuText !== "" || dT > 0 && dI >= 0) {
                const pct = Math.max(0, Math.min(100, Math.round(100 * (1 - dI / dT))));
                // format="  {load_percent}%" — the microchip glyph, BMP.
                shellRoot.cpuText = String.fromCharCode(0xF2DB) + "  " + pct + "%";
            }
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
            const usedMb = Math.round((total - avail) / 1024);
            // format="{MemUsed: .0f}{mm}", fmt="🖥  {} ". The emoji is BMP.
            // fmt="🖥  {} " in config.py. That emoji is U+1F5A5 —
            // SUPPLEMENTARY plane, which renders as nothing in this shell
            // (NEXT-SESSION.md: U+F022C and neighbours paint blank while BMP
            // ones render in the same face). U+F108 is the BMP Nerd Font
            // desktop and says the same thing.
            shellRoot.memText = String.fromCharCode(0xF108) + "  " + usedMb + "M ";
        }
    }

    // ---- DISK ----
    property string diskText: ""
    Process {
        id: diskProc
        command: ["sh", "-c", "df -h --output=pcent / | tail -1 | tr -d ' %'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const pct = parseInt(text.trim(), 10);
                if (isFinite(pct))
                    shellRoot.diskText = String.fromCharCode(0xF0A0) + "  " + pct + "%";
            }
        }
    }
    Timer {
        interval: 60000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: diskProc.running = true
    }

    // ---- VOLUME ----
    property string volumeText: ""
    Process {
        id: volProc
        command: ["sh", "-c", "wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null || pactl get-sink-volume @DEFAULT_SINK@"]
        stdout: StdioCollector {
            onStreamFinished: {
                const t = text.trim();
                if (t.indexOf("MUTED") >= 0) {
                    shellRoot.volumeText = String.fromCharCode(0xF026) + "  muted";
                    return;
                }
                const m = t.match(/([0-9]*\.?[0-9]+)/);
                if (m) {
                    const v = Math.round(parseFloat(m[1]) * 100);
                    shellRoot.volumeText = String.fromCharCode(0xF028) + "  " + v + "%";
                }
            }
        }
    }
    Timer {
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: volProc.running = true
    }

    // ---- BATTERY ----
    readonly property var battery: UPower.displayDevice
    readonly property bool batteryLow:
        battery && battery.isLaptopBattery && battery.percentage <= 0.2
    readonly property string batteryText: {
        if (!battery || !battery.isLaptopBattery) return "";
        const pct = Math.round(battery.percentage * 100);
        // charge_char=" ↑ ", discharge_char=" ↓ ", full_char="✔ " — config.py's
        // exact strings, and format="  {char}{percent:2.0%}".
        let ch = " ↓ ";
        if (battery.state === UPowerDeviceState.Charging) ch = " ↑ ";
        else if (battery.state === UPowerDeviceState.FullyCharged) ch = "✔ ";
        return String.fromCharCode(0xF240) + " " + ch + pct + "%";
    }

    // ---- KEYBOARD LAYOUT ----
    property string keyboardLayout: "us"
    Process {
        id: kbProc
        command: ["sh", "-c",
            "hyprctl -j devices | python3 -c \"import json,sys;d=json.load(sys.stdin);ks=[k for k in d.get('keyboards',[]) if k.get('main')];print((ks[0]['active_keymap'] if ks else 'us')[:2].lower())\""]
        stdout: StdioCollector {
            onStreamFinished: {
                const t = text.trim();
                if (t) shellRoot.keyboardLayout = t.toUpperCase();
            }
        }
    }
    Timer {
        interval: 3000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: kbProc.running = true
    }

    // ---- LAYOUT NAME ----
    //
    // The same state file layout-cycle.sh writes and the island's
    // LayoutState reads, so the two bars cannot disagree about which layout
    // the workspace is in.
    property string layoutName: "monadtall"
    FileView {
        path: Quickshell.env("HOME") + "/.cache/hypr/workspace-layouts"
        watchChanges: true
        preload: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const ws = Hyprland.focusedWorkspace;
                const map = JSON.parse(text());
                if (ws && map[String(ws.id)])
                    shellRoot.layoutName = String(map[String(ws.id)]);
            } catch (e) {
                // Keep the last known name. A layout label that briefly lags
                // is better than one that blanks on a torn read.
            }
        }
    }

    // ---- MPRIS ----
    readonly property var player: Mpris.players.values.length > 0
        ? Mpris.players.values[0] : null
    readonly property string mprisText: {
        if (!player || !player.trackTitle) return "";
        // format="{xesam:title} — {xesam:artist}"
        const a = player.trackArtist ? " — " + player.trackArtist : "";
        return player.trackTitle + a;
    }
}
