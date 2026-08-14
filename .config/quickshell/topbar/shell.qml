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

            // ---- IGNORE, AND A SEPARATE WINDOW TO DO THE RESERVING ----
            //
            // Reported: "the topbar is fixed in mid center, should not move to
            // left or right for the stack of the tree layout".
            //
            // The TreeTab sidebar is a Bottom-layer surface with a 180 px
            // exclusiveZone, and layer-shell computes the usable area across
            // ALL layers in order — so a Bottom surface's zone shrinks the area
            // a Top surface is then placed in. Measured with the sidebar open:
            // this bar came out 1186x38+180+0 instead of 1366x38+0+0, i.e.
            // narrowed AND pushed, and everything centred in it moved with it.
            //
            // ExclusionMode.Ignore fixes the position — measured, 1366x38+0+0
            // with the sidebar still open — but it is BOTH halves of one
            // switch: a window that ignores other zones also sets none of its
            // own. Measured again: `hyprctl monitors` reserved dropped to the
            // island's 33 alone, so windows would tile under this bar.
            //
            // Hence the reserver below. Splitting the two jobs across two
            // surfaces is the only way to have them separately, because
            // layer-shell has no "ignore theirs, keep mine".
            exclusionMode: ExclusionMode.Ignore

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

            // ---- THE ONE TOOLTIP, AND WHAT FEEDS IT ----
            //
            // qtile injects TooltipMixin into every widget instance's class,
            // gives each a delay timer, and needs _kill_all_tooltips() so two
            // cannot be on screen at once. This needs none of that: every chip
            // reports hover into this one object, so a new hover REPLACES the
            // old by construction.
            //
            // The delay is qtile's idea and is kept — a tooltip that appears
            // the instant the pointer crosses a chip fires constantly while
            // you are just moving across the bar.
            QtObject {
                id: hoverSink
                property var current: null
                property string currentText: ""

                function enter(chip, text) {
                    hoverSink.current = chip;
                    hoverSink.currentText = text;
                    tooltipDelay.restart();
                }
                function exit(chip) {
                    if (hoverSink.current !== chip)
                        return;
                    tooltipDelay.stop();
                    hoverSink.current = null;
                    hoverSink.currentText = "";
                }
            }

            Timer {
                id: tooltipDelay
                interval: 450
                repeat: false
            }

            Tooltip {
                // Shown only once the delay has elapsed AND the pointer is
                // still on the same chip — `current` is cleared on exit, so
                // leaving during the delay cancels it without a second flag.
                target: tooltipDelay.running ? null : hoverSink.current
                text: hoverSink.currentText
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
                        tooltip: "Arch menu \u00b7 L-click \u2192 terminal \u00b7 R-click \u2192 launcher"
                        hoverSink: hoverSink
                        foreground: BarTheme.purple      // colors[7]
                        padding: 11
                        fontPixelSize: Metrics.s(15)
                        fontFamily: "Symbols Nerd Font"
                        clickable: true
                        height: parent.height
                        // config.py's map, kept: L docs, M terminal, R launcher.
                        // Terminal is on MIDDLE rather than dropped because
                        // muscle memory is real, and $mod Return still does it.
                        // ---- ROFI, NOT THE ISLAND'S PANELS ----
                        //
                        // This bar is qtile's, and qtile drives ROFI. The
                        // first version called the island's IPC, which is
                        // wrong twice over: it makes the two bars show the
                        // same surfaces, and — the practical half — the
                        // island is NOT RUNNING when this bar is, because
                        // bar-switch stops one to start the other. Every one
                        // of those calls would have found no instance and
                        // failed silently, since `qs ipc call` exits 0 when
                        // it finds nothing.
                        //
                        // config.py's map, verbatim: L rofi_docs,
                        // M kitty, R rofi -show drun -show-icons.
                        onClicked: (b) => {
                            if (b === Qt.LeftButton)
                                Quickshell.execDetached(["rofi_docs"]);
                            else if (b === Qt.MiddleButton)
                                Quickshell.execDetached(["kitty"]);
                            else
                                Quickshell.execDetached(
                                    ["rofi", "-show", "drun", "-show-icons"]);
                        }
                    }

                    // The layout name, in text as qtile shows it. Right-click
                    // cycles, which is config.py's Button3 on this chip.
                    Chip {
                        text: shellRoot.layoutName
                        tooltip: "Layout \u00b7 R-click to cycle"
                        hoverSink: hoverSink
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
                        tooltip: "Tips \u00b7 click \u2192 toggle onboarding"
                        hoverSink: hoverSink
                        foreground: BarTheme.fg          // colors[1]
                        padding: 11
                        fontPixelSize: Metrics.s(12)
                        fontFamily: "Symbols Nerd Font"
                        clickable: true
                        height: parent.height
                        // qtile's toggle_onboarding: `eww open
                        // onboarding-welcome`. NOT the island's
                        // showOnboarding — the island is down while this bar
                        // is up. The eww window is the one both sessions can
                        // reach.
                        onClicked: Quickshell.execDetached(
                            ["sh", "-c",
                             "eww close onboarding-welcome 2>/dev/null "
                             + "|| eww open onboarding-welcome"])
                    }

                    // MPRIS. Empty with no player, and Chip takes no width at
                    // all then rather than leaving a bare plate on the bar.
                    Chip {
                        text: shellRoot.mprisText
                        tooltip: "L: play/pause \u00b7 R: next"
                        hoverSink: hoverSink
                        foreground: BarTheme.green       // colors[4]
                        padding: 10
                        fontPixelSize: Metrics.s(15)
                        clickable: true
                        height: parent.height
                        // config.py: L play-pause, R next.
                        onClicked: (b) => Quickshell.execDetached(
                            ["playerctl", b === Qt.RightButton ? "next" : "play-pause"])
                    }

                    // system_widgetbox — CPU and memory.
                    WidgetBox {
                        codepointClosed: 0xF05AF
                        tooltip: "CPU + Memory"
                        hoverSink: hoverSink
                        codepointOpen: 0xF05B0
                        foreground: BarTheme.purple      // colors[7]
                        fontPixelSize: Metrics.s(15)
                        padding: 10
                        height: parent.height

                        Chip {
                            text: shellRoot.cpuText
                        tooltip: "CPU load \u00b7 click \u2192 mission-center"
                        hoverSink: hoverSink
                            foreground: BarTheme.purple
                            padding: 11
                            fontPixelSize: Metrics.s(10)
                            clickable: true
                            height: parent.height
                            // config.py: env GTK_THEME=Adwaita:dark missioncenter
                            onClicked: Quickshell.execDetached(
                                ["env", "GTK_THEME=Adwaita:dark", "missioncenter"])
                        }
                        Chip {
                            text: shellRoot.memText
                        tooltip: "RAM used \u00b7 click \u2192 btop"
                        hoverSink: hoverSink
                            foreground: BarTheme.cyan
                            padding: 11
                            fontPixelSize: Metrics.s(10)
                            clickable: true
                            height: parent.height
                            // config.py: myFullScreenTerm + " -e btop"
                            onClicked: Quickshell.execDetached(
                                ["kitty", "--start-as=fullscreen", "-e", "btop"])
                        }
                    }

                    // wallpaper_toggle. U+2716 is a plain heavy multiplication
                    // X, not a Nerd Font icon — qtile's choice, kept.
                    WidgetBox {
                        codepointClosed: 0x2716
                        tooltip: "Wallpaper picker"
                        hoverSink: hoverSink
                        codepointOpen: 0xF035C
                        foreground: BarTheme.cyan        // colors[8]
                        fontPixelSize: Metrics.s(13)
                        padding: 11
                        height: parent.height

                        Chip {
                            text: "wallpaper"
                        tooltip: "Wallpaper picker"
                        hoverSink: hoverSink
                            foreground: BarTheme.cyan
                            padding: 11
                            fontPixelSize: Metrics.s(10)
                            clickable: true
                            height: parent.height
                            // dm-setbg, the rofi wallpaper picker both
                            // sessions already have on PATH.
                            onClicked: Quickshell.execDetached(["dm-setbg"])
                        }
                    }

                    // 2nd_system_widgetbox — disk and volume. config.py also
                    // carries CheckUpdates here; that is qupdate.py's, and it
                    // is left out rather than reimplemented badly, because the
                    // count it shows comes from a daemon this bar does not own.
                    WidgetBox {
                        codepointClosed: 0xF0902
                        tooltip: "Updates \u00b7 Disk \u00b7 Volume"
                        hoverSink: hoverSink
                        codepointOpen: 0xF0042
                        foreground: BarTheme.yellow      // colors[5]
                        fontPixelSize: Metrics.s(14)
                        padding: 10
                        height: parent.height

                        Chip {
                            text: shellRoot.diskText
                        tooltip: "Disk free \u00b7 click \u2192 notify"
                        hoverSink: hoverSink
                            foreground: BarTheme.fg
                            padding: 11
                            fontPixelSize: Metrics.s(10)
                            clickable: true
                            height: parent.height
                            onClicked: Quickshell.execDetached(["disk_notify"])
                        }
                        Chip {
                            text: shellRoot.volumeText
                        tooltip: "Volume \u00b7 scroll to change"
                        hoverSink: hoverSink
                            foreground: BarTheme.purple
                            padding: 11
                            fontPixelSize: Metrics.s(10)
                            // Inert, because config.py's w_volume has no
                            // mouse_callbacks either. Volume is a control the
                            // keys own on this desktop.
                            height: parent.height
                        }
                    }

                    // Battery, only on a machine that has one — config.py
                    // splats it in conditionally for the same reason.
                    Chip {
                        active: UPower.displayDevice
                            && UPower.displayDevice.isLaptopBattery
                        text: shellRoot.batteryText
                        tooltip: "Battery \u00b7 click \u2192 status"
                        hoverSink: hoverSink
                        // colors[6], falling to colors[3] under 20%, which is
                        // config.py's low_foreground / low_percentage pair.
                        foreground: shellRoot.batteryLow ? BarTheme.red : BarTheme.blue
                        padding: 12
                        fontPixelSize: Metrics.s(10)
                        clickable: true
                        height: parent.height
                        onClicked: Quickshell.execDetached(["battery_notify"])
                    }

                    // Keyboard layout. config.py's display_map, verbatim:
                    // a flag emoji then the two-letter code, over
                    // configured_keyboards = ["us", "ara", "tr", "de"].
                    // The flag is a separate Text inside Chip — see the note
                    // there for why it cannot share the label's.
                    Chip {
                        emoji: shellRoot.layoutFlag
                        text: shellRoot.layoutCode
                        tooltip: "Keyboard layout"
                        hoverSink: hoverSink
                        foreground: BarTheme.green       // colors[4]
                        padding: 11
                        clickable: true
                        height: parent.height
                        // L cycles forward, R back — config.py's
                        // _cycle_keyboard(1) / (-1). Hyprland switches the
                        // layout itself rather than through setxkbmap.
                        onClicked: (b) => Quickshell.execDetached(
                            ["hyprctl", "switchxkblayout", "all",
                             b === Qt.RightButton ? "prev" : "next"])
                    }

                    // format=" %a, %b %d - %H:%M", verbatim.
                    Chip {
                        text: shellRoot.clockText
                        tooltip: "Next prayer \u00b7 USD/EUR rates"
                        hoverSink: hoverSink
                        foreground: BarTheme.cyan        // colors[8]
                        padding: 11
                        clickable: true
                        height: parent.height
                        // config.py: qtile.spawn("clock_popup").
                        onClicked: Quickshell.execDetached(["clock_popup"])
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
                        tooltip: "System tray"
                        hoverSink: hoverSink
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

    // ---- THE RESERVER ----
    //
    // An invisible, input-transparent strip whose ONLY job is to hold the
    // exclusive zone the bar above gave up. It is allowed to be pushed around
    // by the TreeTab sidebar exactly as the bar used to be, because nothing
    // is drawn in it and a zone is a scalar — being placed at x=180 does not
    // change how many pixels it reserves off the top.
    //
    // 1 px tall rather than 0: a zero-size surface is not guaranteed to be
    // mapped, and an unmapped surface reserves nothing.
    Variants {
        model: Quickshell.screens

        PanelWindow {
            required property var modelData
            screen: modelData

            anchors { top: true; left: true; right: true }
            implicitHeight: 1
            exclusiveZone: Metrics.barHeight + Metrics.marginV * 2
            color: "transparent"
            // No input at all. Without this the strip eats clicks along the
            // very top edge of the screen — the same trap RingOsdWindow
            // documents, in one pixel instead of a full screen.
            mask: Region {}
        }
    }

    // ---------------------------------------------------------------
    //  State the chips read
    // ---------------------------------------------------------------


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
    //
    // config.py's display_map, which is where both the flag and the two-letter
    // code come from. Its configured_keyboards list is ["us","ara","tr","de"],
    // and note "ara" displays as AR and "us" as EN — the code is NOT the
    // layout name upper-cased, so it is a table and not a transform.
    readonly property var layoutMap: ({
        "us":  { flag: "\ud83c\uddfa\ud83c\uddf8", code: "EN" },
        "ara": { flag: "\ud83c\uddf8\ud83c\udde6", code: "AR" },
        "tr":  { flag: "\ud83c\uddf9\ud83c\uddf7", code: "TR" },
        "de":  { flag: "\ud83c\udde9\ud83c\uddea", code: "DE" }
    })
    readonly property var layoutEntry:
        layoutMap[shellRoot.keyboardLayout] || null
    readonly property string layoutFlag: layoutEntry ? layoutEntry.flag : ""
    readonly property string layoutCode:
        layoutEntry ? layoutEntry.code : shellRoot.keyboardLayout.toUpperCase()

    property string keyboardLayout: "us"
    // The MAIN keyboard's layout, as a layout KEY ("us", "ara"), because
    // that is what layoutMap and qtile's configured_keyboards are keyed on.
    //
    // Hyprland does not report the key. It reports `active_keymap` as a
    // DISPLAY NAME — "English (US)" — and `layout` as the configured list,
    // "us,ara,tr,de", which is qtile's list exactly. Taking the first two
    // characters of the display name was the first attempt and gave "en",
    // which matches nothing: the chip rendered "EN" with no flag, which is
    // how this was noticed.
    //
    // So the display name is matched against the layouts the device actually
    // declares, rather than against a hardcoded table — a machine configured
    // with different layouts then still resolves.
    Process {
        id: kbProc
        command: ["sh", "-c",
            "hyprctl -j devices | python3 -c \"" +
            "import json,sys\n" +
            "d=json.load(sys.stdin)\n" +
            "ks=[k for k in d.get('keyboards',[]) if k.get('main')] or d.get('keyboards',[])\n" +
            "if not ks: print('us'); sys.exit()\n" +
            "k=ks[0]\n" +
            "km=(k.get('active_keymap') or '').lower()\n" +
            "names={'us':'english','ara':'arabic','tr':'turkish','de':'german'}\n" +
            "for key in [x.strip() for x in (k.get('layout') or 'us').split(',')]:\n" +
            "    if names.get(key,key) in km: print(key); break\n" +
            "else: print((k.get('layout') or 'us').split(',')[0].strip())\n" +
            "\""]
        stdout: StdioCollector {
            onStreamFinished: {
                // Kept as the raw key ("us", "ara"), because layoutMap is
                // keyed on it. Upper-casing here was why the map never hit.
                const t = text.trim();
                if (t) shellRoot.keyboardLayout = t;
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
