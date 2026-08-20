import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
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
//
// `chord_chip` USED to be listed here, on the grounds that the island already
// renders the submap name. It is built, and the reasoning was wrong in the
// one way that matters: the island is STOPPED while this bar runs, so there
// was never a second copy to avoid — only the absence of the first.
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
        // One run so the FIRST hover of the clock has data rather than the
        // fallback label. Everything after that is hover-driven; see
        // refreshClockTooltip(). Folded in here rather than given its own
        // Component.onCompleted, which is "Property value set multiple
        // times" on one object and fails the whole shell.
        shellRoot.refreshClockTooltip();
    }

    // ---- WHICH OF THE TWO BARS ----
    //
    // qtile builds TWO and shows one: a top bar of chips and a bottom "normal
    // user" bar of bare widgets, swapped by $mod SHIFT Z. apply_bar_mode()
    // there hides one and shows the other, and BAR_MODE is the single owner.
    //
    // Same arrangement, same single owner, persisted so it survives a restart
    // the way BAR_MODE does through config reloads. NOT in ~/.cache/bar-mode —
    // that file answers a different question (island vs this bar) and
    // overloading it would make two unrelated toggles fight.
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
                shellRoot.position = v;
        }
    }

    function setPosition(p) {
        if (p !== "top" && p !== "bottom")
            return;
        shellRoot.position = p;
        positionFile.setText(p + "\n");
    }

    // ---- THE WIDGET BOXES, WHICH ARE KEYS AS WELL AS CHIPS ----
    //
    // qtile's SmartWidgetBoxes are bound to keys as well as to their own
    // glyphs — binds.conf's dead-bind section records all three:
    //
    //     $alt `     system_widgetbox        CPU + memory
    //     $mod `     2nd_system_widgetbox    updates · disk · volume
    //     $alt Tab   systray_widgetbox       the tray
    //
    // and they were left dead there on the grounds that there was no bar to
    // toggle. There is now, so the state lives HERE rather than inside a chip:
    // `Variants` builds one bar per screen, so per-chip state would have each
    // monitor disagreeing about which boxes are open, and a flag inside a
    // delegate cannot be reached from a keybinding at all.
    property bool systemBoxOpen: false
    property bool secondBoxOpen: false
    property bool trayBoxOpen: false
    property bool wallpaperBoxOpen: false

    // Driveable from a script, which is what the keybinding uses. A control
    // with no way in from a script is a control whose bugs only the user finds.
    IpcHandler {
        target: "topbar"
        function top(): void { shellRoot.setPosition("top"); }
        function bottom(): void { shellRoot.setPosition("bottom"); }
        function toggle(): void {
            shellRoot.setPosition(shellRoot.position === "top" ? "bottom" : "top");
        }
        function status(): string { return shellRoot.position; }

        // One function per box rather than one taking a name, because
        // Quickshell's IPC splits arguments on whitespace and a typo'd name
        // would be indistinguishable from a box that refused to open — where
        // a missing FUNCTION at least prints "Function not found".
        function toggleSystemBox(): void {
            shellRoot.systemBoxOpen = !shellRoot.systemBoxOpen;
        }
        function toggleSecondBox(): void {
            shellRoot.secondBoxOpen = !shellRoot.secondBoxOpen;
        }
        function toggleTrayBox(): void {
            shellRoot.trayBoxOpen = !shellRoot.trayBoxOpen;
        }
        // Explicit setters beside the toggles, because a toggle driven by a
        // script goes out of phase with the screen the first time a click and
        // a keypress disagree — the RULES in NEXT-SESSION.md say to prefer
        // show/hide when scripting, and a test cannot do that without them.
        function showTrayBox(): void { shellRoot.trayBoxOpen = true; }
        function hideTrayBox(): void { shellRoot.trayBoxOpen = false; }
        function showSystemBox(): void { shellRoot.systemBoxOpen = true; }
        function hideSystemBox(): void { shellRoot.systemBoxOpen = false; }
        function showSecondBox(): void { shellRoot.secondBoxOpen = true; }
        function hideSecondBox(): void { shellRoot.secondBoxOpen = false; }
        function boxes(): string {
            return "system=" + shellRoot.systemBoxOpen
                + " second=" + shellRoot.secondBoxOpen
                + " tray=" + shellRoot.trayBoxOpen;
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: bar
            // One bar at a time, as qtile shows one at a time.
            visible: shellRoot.position === "top"
            required property var modelData
            screen: modelData

            // ---- ALWAYS Top, NOW — the promotion moved to its own window ----
            //
            // This used to be `shellRoot.submap !== "" ? Overlay : Top`, on the
            // same reasoning as the island's islandRestingSurface: Hyprland
            // draws a fullscreen window ABOVE Top and BELOW Overlay, so a
            // fullscreen video hid this bar's chord_chip along with everything
            // else on it — reported as "in fullscreen I open $mod P and cannot
            // see the mode".
            //
            // The fix was right and its blast radius was wrong. Promoting THIS
            // window to Overlay does not put only the chord chip over the
            // video — every chip on the bar comes with it, arch icon through
            // tray, because they are all one PanelWindow. Asked for directly
            // afterwards: qtile's own mode_overlay.py shows a SEPARATE small
            // floating label at top-centre while a mode covers the bar, never
            // the bar itself — "it appears in mid of screen without the bar,
            // just it". That is `ModeChip` below: its own tiny Overlay-layer
            // window, visible only while `shellRoot.submap !== ""` AND
            // `shellRoot.focusedFullscreen`, holding nothing but the label.
            //
            // So this bar goes back to being simply Top, always — hidden
            // behind fullscreen exactly like any other dock, which is correct
            // for every chip on it including the embedded chord chip further
            // down (rightGroup's Chip): that one keeps showing the mode
            // normally whenever the bar itself is visible, and ModeChip is the
            // ONLY thing that shows it when the bar is not, so the two never
            // draw the same label at once.
            WlrLayershell.layer: WlrLayer.Top

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

                // The CHIP is kept, not a snapshot of its text. It used to
                // latch the string at enter(), which is right for the
                // seventeen chips whose tooltip is a LABEL and wrong for the
                // one whose tooltip is DATA: the clock fetches its next
                // prayer and its FX rates when hovered, and a snapshot taken
                // 450 ms before the answer arrives would show the stale line
                // for as long as the pointer stayed. See Tooltip's `text`.
                //
                // `text` is still accepted and ignored so an out-of-date
                // caller cannot fail — Chip passes it.
                function enter(chip, text) {
                    hoverSink.current = chip;
                    tooltipDelay.restart();
                }
                function exit(chip) {
                    if (hoverSink.current !== chip)
                        return;
                    tooltipDelay.stop();
                    hoverSink.current = null;
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
                text: hoverSink.current ? hoverSink.current.tooltip : ""
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
                        // TRUTHFUL, AND THEREFORE NOT qtile's STRING.
                        //
                        // TOOLTIP_BY_NAME["main_icon_chip"] is "Arch menu \u00b7
                        // L-click \u2192 terminal \u00b7 R-click \u2192 launcher" and this
                        // bar reproduced it verbatim \u2014 but that tooltip
                        // disagrees with its own widget: config.py binds
                        // Button1 to open_docs, not to a terminal. qtile has
                        // shipped a chip that mis-describes itself, and
                        // copying the text faithfully copied the lie.
                        //
                        // Fidelity to a tooltip is worth less than a tooltip
                        // that is true, and this one is the only place a user
                        // finds out what the three buttons do.
                        tooltip: "Arch menu \u00b7 L \u2192 docs \u00b7 M \u2192 launcher \u00b7 R \u2192 terminal"
                        hoverSink: hoverSink
                        foreground: BarTheme.purple      // colors[7]
                        padding: 11
                        fontPixelSize: Metrics.s(15)
                        fontFamily: "Symbols Nerd Font"
                        clickable: true
                        height: parent.height
                        // ---- ONE ASKED-FOR DIVERGENCE: R IS THE TERMINAL ----
                        //
                        // config.py's top-bar map is L docs, M terminal, R
                        // launcher, and that is what this was. Asked for
                        // directly: "the right click on the window chip should
                        // open terminal".
                        //
                        // It is not an arbitrary swap. main_icon_chip_nu — the
                        // BOTTOM bar's copy of this chip, in the same config —
                        // is L launcher, R TERMINAL, so right-click-for-a-
                        // terminal is already this desktop's habit on the
                        // other bar, and the two bars disagreeing on the most
                        // used button is the thing being reported. The
                        // launcher moves to MIDDLE rather than being dropped,
                        // so all three actions stay reachable from the chip.
                        //
                        // Recorded as a divergence rather than folded in
                        // quietly, because everything else on this bar is
                        // measured against config.py.
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
                                Quickshell.execDetached(
                                    ["rofi", "-show", "drun", "-show-icons"]);
                            else
                                Quickshell.execDetached(["kitty"]);
                        }
                    }

                    // The layout name, in text as qtile shows it. Right-click
                    // cycles, which is config.py's Button3 on this chip.
                    Chip {
                        text: shellRoot.layoutName
                        // SteadyCurrentLayout's reserved width, ported as its
                        // rule rather than its code: the widest of the three
                        // layout names layout-cycle.sh can write. Without it
                        // this chip shrinks by six characters on the way from
                        // monadtall to max and shoves the centred workspace
                        // group sideways for a frame \u2014 which is the entire
                        // reason that subclass exists in config.py.
                        widestText: "monadtall"
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
                    height: parent.height

                    // ---- CENTRING YIELDS TO FITTING ----
                    //
                    // It was anchored to horizontalCenter, which is right
                    // until the right-hand side grows past the middle of the
                    // bar. With three widget boxes open the expansion area
                    // reaches x=520 on a 1366 px bar, and the group was drawn
                    // UNDERNEATH it — present, centred, and invisible.
                    //
                    // config.py resolves this the same way and says so: the
                    // GroupBox "drifts off-centre only once there is no
                    // alternative", because the alternative is content running
                    // off the end of the bar. So the true centre is the
                    // preference and the right-hand edge is the constraint.
                    //
                    // Floored at leftFixed's edge: pushed far enough, the
                    // group stops rather than sliding under the layout chip.
                    x: Math.max(leftFixed.width + Metrics.s(6),
                                Math.min((parent.width - width) / 2,
                                         rightGroup.x - width - Metrics.s(6)))
                }

                // ================= RIGHT =================
                //
                // config.py's order, complete: chord, the shared expansion
                // area, lamp, mpris, system box, wallpaper toggle, 2nd system
                // box, battery, language, clock, systray box.
                //
                // ---- WHERE EACH BOX OPENS, AND WHY THEY DIFFER ----
                //
                // Two of the three boxes open in a SHARED area left of the
                // lamp, and the tray opens beside its own triangle. That is
                // not an inconsistency — it is config.py's, read off the
                // arguments rather than off the layout:
                //
                //     system_widgetbox        insert_before_name="tooltip_widgetbox"
                //     2nd_system_widgetbox    insert_before_name="tooltip_widgetbox"
                //     systray_widgetbox       (no insert_before_name)
                //
                // SmartWidgetBox's insert_before_name is what moves a box's
                // contents somewhere other than its own slot, and the tray does
                // not set it — so in qtile the icons appear at the triangle,
                // between the clock and the chevron, and only the two system
                // boxes collect in front of the lamp. Reported as "the triangle
                // chip should show the icons near to it", which is the same
                // observation from the other side.
                //
                // See BoxContent.qml for why the shared area is one Item per
                // box rather than one shared list.
                Row {
                    id: rightGroup
                    anchors.right: parent.right
                    height: parent.height
                    spacing: 0

                    // chord_chip. qtile shows the active KeyChord; Hyprland's
                    // equivalent is the SUBMAP, and the island normally draws
                    // it — but the island is stopped while this bar runs, so
                    // without this the submap would be invisible in exactly
                    // the session that has this bar. fmt=" {} " and
                    // foreground=colors[0], with the plate colour carrying the
                    // identity, which is CHORD_CHIP_COLORS' whole idea.
                    Chip {
                        // fmt=" {} " is already applied by submapLabel /
                        // submapIcon — see the table for why the leading space
                        // rides on whichever of the two comes first.
                        icon: shellRoot.submapIcon
                        text: shellRoot.submapLabel
                        foreground: BarTheme.bg          // colors[0]
                        plate: shellRoot.submapColour
                        padding: 11
                        tooltip: "Current mode"
                        hoverSink: hoverSink
                        height: parent.height
                    }

                    // ---- THE SHARED EXPANSION AREA ----
                    Row {
                        height: parent.height
                        spacing: 0

                        // system_widgetbox: CPU and memory.
                        BoxContent {
                            open: shellRoot.systemBoxOpen
                            Chip {
                                text: shellRoot.cpuText
                                tooltip: "CPU load \u00b7 click \u2192 mission-center"
                                hoverSink: hoverSink
                                foreground: BarTheme.purple
                                padding: 11
                                fontPixelSize: Metrics.s(10)
                                clickable: true
                                height: parent.height
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
                                onClicked: Quickshell.execDetached(
                                    ["kitty", "--start-as=fullscreen", "-e", "btop"])
                            }
                        }

                        // 2nd_system_widgetbox: updates, disk, volume — which
                        // is exactly what its tooltip in config.py promises.
                        BoxContent {
                            open: shellRoot.secondBoxOpen
                            Chip {
                                text: shellRoot.updatesText
                                tooltip: "Pending updates \u00b7 click \u2192 update manager"
                                hoverSink: hoverSink
                                foreground: BarTheme.yellow
                                padding: 11
                                fontPixelSize: Metrics.s(10)
                                clickable: true
                                height: parent.height
                                onClicked: Quickshell.execDetached(
                                    ["python3", Quickshell.env("HOME")
                                        + "/.config/qtile/scripts/qupdate.py", "--toggle"])
                            }
                            Chip {
                                text: shellRoot.diskText
                                tooltip: "Disk free (/ + /home) \u00b7 click \u2192 notify"
                                hoverSink: hoverSink
                                foreground: BarTheme.fg
                                padding: 11
                                fontPixelSize: Metrics.s(10)
                                clickable: true
                                height: parent.height
                                onClicked: Quickshell.execDetached(["disk_notify"])
                            }
                            // ---- w_volume IS NOT INERT ----
                            //
                            // It was drawn as a readout, on the grounds that
                            // config.py sets no mouse_callbacks on it. That is
                            // true and it does not mean what the comment here
                            // said. Asked of the installed libqtile rather than
                            // of the config:
                            //
                            //     Volume.__init__ -> add_callbacks({
                            //       "Button1": mute, "Button3": run_app,
                            //       "Button4": increase_vol,
                            //       "Button5": decrease_vol })
                            //
                            // The widget ships its own, so an empty
                            // mouse_callbacks keeps the defaults. Its own
                            // tooltip in TOOLTIP_BY_NAME said so all along —
                            // "Volume · scroll to change" — and this chip did
                            // not do it.
                            //
                            // wpctl, not pactl: the topbar's readout above and
                            // the media keys both use it, and two tools for one
                            // number is how they come to disagree. -l 1.5 is
                            // the same 150% ceiling submaps.conf's media mode
                            // uses, itself qtile's min(150, ...).
                            Chip {
                                text: shellRoot.volumeText
                                tooltip: "Volume \u00b7 scroll to change"
                                hoverSink: hoverSink
                                foreground: BarTheme.purple
                                padding: 11
                                fontPixelSize: Metrics.s(10)
                                clickable: true
                                scrollable: true
                                height: parent.height
                                // Every branch that CHANGES the volume asks for
                                // a re-read; see shellRoot.volumeSoon(). The
                                // readout is on a 2 s poll, which is fine for
                                // a volume something else changed and is the
                                // same staleness the language chip was
                                // reported for when it is YOUR scroll that
                                // changed it. pavucontrol does not, because
                                // opening a window changes nothing.
                                onClicked: (b) => {
                                    if (b === Qt.RightButton) {
                                        Quickshell.execDetached(["pavucontrol"]);
                                    } else if (b === Qt.LeftButton) {
                                        Quickshell.execDetached(["wpctl", "set-mute",
                                            "@DEFAULT_AUDIO_SINK@", "toggle"]);
                                        shellRoot.volumeSoon();
                                    }
                                }
                                onScrolled: (d) => {
                                    Quickshell.execDetached(
                                        ["wpctl", "set-volume", "-l", "1.5",
                                         "@DEFAULT_AUDIO_SINK@",
                                         d > 0 ? "5%+" : "5%-"]);
                                    shellRoot.volumeSoon();
                                }
                            }
                        }
                    }

                    // tooltip_widgetbox — the lamp.
                    Chip {
                        text: String.fromCodePoint(0xF0336)
                        tooltip: "Tips (\ud83d\udca1) \u00b7 click \u2192 toggle onboarding"
                        hoverSink: hoverSink
                        foreground: BarTheme.fg          // colors[1]
                        padding: 11
                        fontPixelSize: Metrics.s(12)
                        fontFamily: "Symbols Nerd Font"
                        clickable: true
                        height: parent.height
                        onClicked: Quickshell.execDetached(
                            ["sh", "-c",
                             "eww close onboarding-welcome 2>/dev/null "
                             + "|| eww open onboarding-welcome"])
                    }

                    // w_mpris. FIVE buttons in config.py, not two, and one of
                    // them was backwards here: Button3 is `playerctl previous`
                    // and this chip ran `next` on it. TOOLTIP_BY_NAME spells
                    // the whole map out and is copied verbatim, which is how
                    // the mismatch showed.
                    //
                    // Button2 is `toggle_player` — Mpris2's own method for
                    // cycling between players, which has no playerctl
                    // equivalent; the tooltip calls it "album art" because
                    // that is what the widget does with a second press there.
                    // `playerctl -a` shifting to the next player is the
                    // nearest honest thing, and it is what the island's own
                    // media controls use.
                    Chip {
                        text: shellRoot.mprisText
                        tooltip: "L: play/pause \u00b7 M: album art \u00b7 R: prev \u00b7 scroll: next/prev"
                        hoverSink: hoverSink
                        foreground: BarTheme.green       // colors[4]
                        padding: 10
                        fontPixelSize: Metrics.s(15)
                        clickable: true
                        scrollable: true
                        height: parent.height
                        onClicked: (b) => {
                            if (b === Qt.RightButton)
                                Quickshell.execDetached(["playerctl", "previous"]);
                            else if (b === Qt.MiddleButton)
                                Quickshell.execDetached(["playerctl", "shift"]);
                            else
                                Quickshell.execDetached(["playerctl", "play-pause"]);
                        }
                        // Button4 next, Button5 previous — config.py's, and
                        // note they are NOT symmetrical with the click map.
                        onScrolled: (d) => Quickshell.execDetached(
                            ["playerctl", d > 0 ? "next" : "previous"])
                    }

                    WidgetBox {
                        id: systemBox
                        open: shellRoot.systemBoxOpen
                        onToggle: shellRoot.systemBoxOpen = !shellRoot.systemBoxOpen
                        codepointClosed: 0xF05AF
                        codepointOpen: 0xF05B0
                        tooltip: "CPU + Memory"
                        hoverSink: hoverSink
                        foreground: BarTheme.purple      // colors[7]
                        fontPixelSize: Metrics.s(15)
                        padding: 10
                        height: parent.height
                    }

                    // ---- wallpaper_toggle: A BUTTON, NOT A BOX ----
                    //
                    // It is a SmartWidgetBox in config.py and it holds
                    // `widgets=[]` — nothing. What it actually does is its
                    // Button1: `toggle_wallpaper_picker`, i.e. the popup in
                    // popups/WallpaperPopup.py. This bar had it opening a box
                    // with one chip in it that ran `dm-setbg`, a rofi menu,
                    // which is a different thing wearing the same key.
                    //
                    // Reported directly: "the ✖ chip should show the wal
                    // picker that was written as a qtile popup". It does now —
                    // ../tide-island-fork/qml/popups/WallpaperPopup.qml, in
                    // this shell's own toolkit rather than in rofi.
                    //
                    // Still a WidgetBox and not a plain Chip, because the
                    // OPEN/CLOSED glyph pair is qtile's: ✖ closed, U+F035C
                    // open, and the picker being open is what "open" means.
                    //
                    // U+2716 is a plain heavy multiplication X, not a Nerd
                    // Font icon — qtile's choice, kept.
                    WidgetBox {
                        id: wallpaperBox
                        open: shellRoot.wallpaperBoxOpen
                        onToggle: {
                            shellRoot.wallpaperBoxOpen = !shellRoot.wallpaperBoxOpen;
                            Quickshell.execDetached([
                                "qs", "-p",
                                Quickshell.env("HOME")
                                    + "/.config/quickshell/tide-island-fork/popups.qml",
                                "ipc", "call", "popups", "wallpaper"]);
                        }
                        codepointClosed: 0x2716
                        codepointOpen: 0xF035C
                        tooltip: "Wallpaper picker"
                        hoverSink: hoverSink
                        foreground: BarTheme.cyan        // colors[8]
                        fontPixelSize: Metrics.s(13)
                        padding: 11
                        height: parent.height
                    }

                    WidgetBox {
                        id: secondBox
                        open: shellRoot.secondBoxOpen
                        onToggle: shellRoot.secondBoxOpen = !shellRoot.secondBoxOpen
                        codepointClosed: 0xF0902
                        codepointOpen: 0xF0042
                        tooltip: "Updates \u00b7 Disk \u00b7 Volume"
                        hoverSink: hoverSink
                        foreground: BarTheme.yellow      // colors[5]
                        fontPixelSize: Metrics.s(14)
                        padding: 10
                        height: parent.height
                    }

                    // Battery, only on a machine that has one — config.py
                    // splats it in conditionally for the same reason.
                    Chip {
                        active: UPower.displayDevice
                            && UPower.displayDevice.isLaptopBattery
                        text: shellRoot.batteryText
                        tooltip: "Battery \u00b7 click \u2192 status"
                        hoverSink: hoverSink
                        foreground: shellRoot.batteryLow ? BarTheme.red : BarTheme.blue
                        padding: 12
                        fontPixelSize: Metrics.s(10)
                        clickable: true
                        height: parent.height
                        onClicked: Quickshell.execDetached(["battery_notify"])
                    }

                    Chip {
                        emoji: shellRoot.layoutFlag
                        text: shellRoot.layoutCode
                        tooltip: "Keyboard layout"
                        hoverSink: hoverSink
                        foreground: BarTheme.green       // colors[4]
                        padding: 11
                        clickable: true
                        height: parent.height
                        onClicked: (b) => Quickshell.execDetached(
                            ["hyprctl", "switchxkblayout", "all",
                             b === Qt.RightButton ? "prev" : "next"])
                    }

                    Chip {
                        text: shellRoot.clockText
                        // THE DATA, not the label that described it.
                        //
                        // Reported: "the clockchip when i hover i should see
                        // the prayer time and eur dolar in the tooltip". It
                        // said "Next prayer \u00b7 USD/EUR rates" \u2014 a promise of
                        // two numbers with neither number in it.
                        //
                        // qtile does not have this bug and never did: its
                        // TOOLTIP_BY_NAME string is a FALLBACK, and
                        // install_bar_tooltips() replaces w_clock's with the
                        // dynamic `_clock_tooltip_text` provider. This bar
                        // reproduced the table and not the provider, which is
                        // the same class of miss as the TaskList's markup \u2014
                        // reading the config and not what the widget does
                        // with it.
                        tooltip: shellRoot.clockTooltip
                        hoverSink: hoverSink
                        onTooltipRequested: shellRoot.refreshClockTooltip()
                        foreground: BarTheme.cyan        // colors[8]
                        padding: 11
                        clickable: true
                        height: parent.height
                        onClicked: Quickshell.execDetached(["clock_popup"])
                    }

                    // systray_widgetbox: the tray, then nightlight, then
                    // the Wi-Fi QR — config.py's order inside the box.
                    BoxContent {
                        open: shellRoot.trayBoxOpen
                        Tray {
                            height: parent.height
                        }
                        Chip {
                            // U+F1A4C, config.py's _nightlight_text glyph.
                            text: String.fromCodePoint(0xF1A4C)
                            tooltip: "Nightlight \u00b7 L: on \u00b7 R: off"
                            hoverSink: hoverSink
                            foreground: BarTheme.blue      // colors[6]
                            padding: 11
                            fontPixelSize: Metrics.s(11)
                            fontFamily: "Symbols Nerd Font"
                            clickable: true
                            height: parent.height
                            // hyprsunset, not gammastep/redshift: those are
                            // config.py's X11 answer and do nothing under a
                            // Wayland compositor. `identity` clears the
                            // temperature without killing the daemon, which
                            // is what the island's own night light does.
                            onClicked: (b) => Quickshell.execDetached(
                                ["sh", "-c", b === Qt.RightButton
                                    ? "hyprctl hyprsunset identity"
                                    : "pgrep -x hyprsunset >/dev/null 2>&1 || "
                                      + "setsid hyprsunset >/dev/null 2>&1 & "
                                      + "sleep 0.2; hyprctl hyprsunset temperature 4000"])
                        }
                        Chip {
                            // U+F029, config.py's w_wifi_qr text.
                            text: String.fromCodePoint(0xF029)
                            tooltip: "Wi-Fi QR"
                            hoverSink: hoverSink
                            foreground: BarTheme.purple    // colors[5]
                            padding: 11
                            fontPixelSize: Metrics.s(11)
                            fontFamily: "Symbols Nerd Font"
                            clickable: true
                            height: parent.height
                            // Was the SCRIPT, directly — and that is the whole
                            // of why this chip was reported as dead. wifi-qr.py
                            // is a data producer: it writes the PNG and prints
                            // its path, and the island renders it in its
                            // wifi_qr state. Run bare from here it did its job
                            // perfectly and drew nothing, every press.
                            //
                            // The popups shell now holds the viewer, addressed
                            // the same way the wallpaper chip above addresses
                            // its own — by ENTRY FILE, because popups.qml is a
                            // second entry point into the island's config
                            // directory and `qs -p` keys an instance on the
                            // path it was given.
                            onClicked: Quickshell.execDetached([
                                "qs", "-p",
                                Quickshell.env("HOME")
                                    + "/.config/quickshell/tide-island-fork/popups.qml",
                                "ipc", "call", "popups", "wifiqr"])
                        }
                    }

                    // systray_widgetbox. U+25B3 is a plain geometric triangle
                    // rather than a Nerd Font icon, and config.py is emphatic:
                    // "chosen for its silhouette rather than for consistency
                    // with the others. Do not correct it to a chevron again."
                    // The OPEN state IS a chevron (U+F053) — the two states are
                    // deliberately different kinds of mark.
                    WidgetBox {
                        id: systrayBox
                        open: shellRoot.trayBoxOpen
                        onToggle: shellRoot.trayBoxOpen = !shellRoot.trayBoxOpen
                        codepointClosed: 0x25B3
                        codepointOpen: 0xF053
                        tooltip: "System tray"
                        hoverSink: hoverSink
                        foreground: BarTheme.green       // colors[4]
                        // TWO SIZES, and they are qtile's two. See
                        // WidgetBox.qml for the measurement; the short of it
                        // is that the widget's fontsize=_s(11) governs the
                        // CHEVRON, while the triangle carries its own
                        // size="15500" in text_closed's markup — which lands
                        // on 20 px here, not 11, because a pango markup size
                        // is in points and a qtile fontsize reaches pango as
                        // absolute pixels.
                        fontPixelSize: systrayBox.open
                            ? Metrics.s(11) : Metrics.s(20)
                        // weight="bold" in that same span, and Adwaita Mono
                        // has a real bold cut, so this is not synthesised.
                        fontBold: !systrayBox.open
                        padding: 11
                        height: parent.height
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

            // Anchored to whichever edge the live bar is on, and holding that
            // bar's height. Both bars are ExclusionMode.Ignore, so this one
            // surface is the entire reservation either way.
            anchors {
                top: shellRoot.position === "top"
                bottom: shellRoot.position === "bottom"
                left: true
                right: true
            }
            implicitHeight: 1
            exclusiveZone: (shellRoot.position === "top"
                ? Metrics.barHeight : Metrics.bottomBarHeight) + Metrics.marginV * 2
            color: "transparent"
            // No input at all. Without this the strip eats clicks along the
            // very top edge of the screen — the same trap RingOsdWindow
            // documents, in one pixel instead of a full screen.
            mask: Region {}
        }
    }

    // ---- THE BOTTOM BAR ----
    //
    // Its own window rather than the top bar re-anchored, because it is a
    // DIFFERENT BAR: 40 px instead of 28, an opaque colors[2] background
    // instead of a transparent one, and bare widgets with pipe separators
    // instead of chips. config.py builds two lists for the same reason.
    Variants {
        model: Quickshell.screens

        PanelWindow {
            required property var modelData
            screen: modelData
            visible: shellRoot.position === "bottom"

            // Same rule as the top bar above, and the same fix: always Top.
            // The standalone `ModeChip` window covers the fullscreen+mode
            // case for both bar positions at once, so this bar does not need
            // its own promotion any more than the top one does.
            WlrLayershell.layer: WlrLayer.Top

            anchors { bottom: true; left: true; right: true }
            implicitHeight: Metrics.bottomBarHeight + Metrics.marginV * 2
            // Same reasoning as the top bar: Ignore keeps the TreeTab
            // sidebar's zone from narrowing and shoving it, and the shared
            // reserver above holds the space.
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"

            Rectangle {
                anchors.fill: parent
                anchors.topMargin: Metrics.marginV
                anchors.bottomMargin: Metrics.marginV
                anchors.leftMargin: Metrics.marginH
                anchors.rightMargin: Metrics.marginH
                // background=colors[2] — OPAQUE, unlike the top bar's
                // "#11111b00". This bar has a surface of its own.
                color: BarTheme.bgAlt
                radius: Metrics.s(6)

                BottomBar {
                    id: bottomContent
                    anchors.fill: parent
                    shell: shellRoot
                    sink: bottomSink
                }

                // The bottom bar's own hover sink and tooltip. Its own rather
                // than the top bar's, because a Tooltip anchors to the window
                // its target lives in and these are two different windows —
                // sharing one would place the popup against the wrong surface.
                QtObject {
                    id: bottomSink
                    property var current: null
                    property string currentText: ""
                    function enter(item, text) {
                        bottomSink.current = item;
                        bottomSink.currentText = text;
                        bottomTipDelay.restart();
                    }
                    function exit(item) {
                        if (bottomSink.current !== item) return;
                        bottomTipDelay.stop();
                        bottomSink.current = null;
                        bottomSink.currentText = "";
                    }
                }
                Timer { id: bottomTipDelay; interval: 450; repeat: false }
            }
        }
    }

    // ---------------------------------------------------------------
    //  THE STANDALONE MODE CHIP — qtile's mode_overlay.py, ported
    // ---------------------------------------------------------------
    //
    // The two PanelWindows above are back to being plain Top-layer bars,
    // which means a fullscreen window hides them completely, chord chip
    // included — matching qtile, where the whole bar (and everything on it)
    // disappears under a fullscreen client too. qtile's answer to "then how
    // do I see what mode I am in" is `mode_overlay.py`: a SEPARATE tiny
    // floating chip at top-centre, shown only while BOTH a mode is open AND
    // the real bar is covered, holding nothing but the label. This is that
    // chip, one per screen like the bars above.
    //
    // A third PanelWindow rather than reusing either bar's own surface,
    // because the two conditions that gate it — `submap !== ""` and
    // `focusedFullscreen` — have nothing to do with `shellRoot.position`,
    // and folding it into one of the two bar windows would mean promoting
    // that whole window's layer again, which is the exact bug this replaces.
    Variants {
        model: Quickshell.screens

        PanelWindow {
            required property var modelData
            screen: modelData

            visible: shellRoot.submap !== "" && shellRoot.focusedFullscreen

            // Always Overlay: unlike the bars, this window has nothing to
            // hide behind fullscreen for — it only exists to be seen over it.
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "quickshell-mode-chip"

            // Reserves nothing — a transient chip must not shove tiled
            // windows around for however long a mode stays open.
            exclusionMode: ExclusionMode.Ignore
            anchors { top: true; left: true; right: true }
            // From Metrics directly, not from `chip.height`/`chip.anchors.
            // topMargin`: those read back a child's own laid-out geometry to
            // size the window it is laid out INSIDE, which is exactly the
            // shape of a binding loop, and qmllint's engine called it one on
            // first try. Same two numbers either way — `chip.height` below
            // is `Metrics.barHeight` verbatim — but sourced from the
            // constants directly breaks the cycle instead of tiptoeing
            // around it.
            implicitHeight: Metrics.barHeight + Metrics.marginV
            color: "transparent"

            // Input is the chip's own rectangle alone, same reasoning as the
            // island's mask (DynamicIslandWindow.qml): a full-width surface
            // must not eat clicks meant for the fullscreen window under it.
            mask: Region {
                x: Math.floor(chip.x)
                y: Math.floor(chip.y)
                width: Math.ceil(chip.width)
                height: Math.ceil(chip.height)
            }

            Chip {
                id: chip
                anchors.top: parent.top
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.topMargin: Metrics.marginV
                height: Metrics.barHeight
                icon: shellRoot.submapIcon
                text: shellRoot.submapLabel
                foreground: BarTheme.bg
                plate: shellRoot.submapColour
                padding: 11
            }
        }
    }

    // ---------------------------------------------------------------
    //  State the chips read
    // ---------------------------------------------------------------


    // ---- THE SUBMAP, WHICH IS qtile's CHORD ----
    //
    // config.py's chord_chip names the active KeyChord and colours its PLATE
    // per chord (CHORD_CHIP_COLORS) rather than its text — the identity is the
    // colour, which is why the foreground is colors[0] against it.
    //
    // The seven Hyprland submaps map one-to-one onto the chord names, so the
    // chip says the same words in either session.
    //
    // ---- IT SAYS THE KEYS, NOT THE MODE'S NAME ----
    //
    // It drew "Media-Mode", which is the chord's NAME and not what qtile puts
    // on that chip. config.py passes `name_transform=chord_chip_label`, and
    // chord_chip_label is a lookup into CHORD_CHIP_LABELS — so the real bar
    // shows "󰕾   MEDIA : J , K , M , H , L , P". The name alone answers "am I
    // in a mode"; the list answers the question you actually have while
    // standing inside a fourteen-key chord, which is what the keys are.
    // Reported as the chip not behaving like the real one, with the Rofi row
    // quoted.
    //
    // Both halves are config.py's verbatim: the text from CHORD_CHIP_LABELS,
    // the plate colour from CHORD_CHIP_COLORS (colors[5] orange for resize,
    // [6] blue for rofi, [8] cyan for media, [1] fg for lang, [3] red for
    // draw and cheatsheet, [8] cyan for passthrough). The text is colors[0],
    // the background, so it stays legible on whichever accent the plate is —
    // that is CHORD_CHIP_COLORS' whole idea.
    //
    // The GLYPH is separated from the words, and has to be: qtile's strings
    // mix a supplementary-plane Nerd Font icon with plain text in ONE string,
    // which pango renders by falling back per run and Qt does not. See
    // Chip.qml's `icon`.
    //
    // Two entries carry NO glyph, and that is not an omission here: lang and
    // passthrough begin with three plain spaces in config.py — checked at the
    // byte level, not by eye — so the real bar has no icon on them either.
    // Their glyphs were private-use characters and did not survive some edit
    // of that file, which is precisely the trap the RULES record. Reproduced
    // as it renders rather than as it was presumably meant to.
    //
    // A submap with no entry falls back to its own name and the accent, which
    // is better than a blank chip for a mode that IS swallowing your keys.
    readonly property var submapMap: ({
        "resize":      { icon: 0xF0A68, text: "   RESIZE : H, J, N",
                         colour: BarTheme.yellow },
        "rofi":        { icon: 0xF0349,
                         text: "   ROFI : i , o , p , w , z , b , e , r , t , y , f , s , n , h ",
                         colour: BarTheme.blue },
        "media":       { icon: 0xF057E, text: "   MEDIA : J , K , M , H , L , P ",
                         colour: BarTheme.cyan },
        "lang":        { icon: 0, text: "   LANG : a , e , t , d ",
                         colour: BarTheme.fg },
        "draw":        { icon: 0xF03EB, text: "   DRAW : w , c , z , r , v ",
                         colour: BarTheme.red },
        "cheatsheet":  { icon: 0xF018D,
                         text: "   CHEATSHEET : k , v , f , j/k scroll , TAB , ESC ",
                         colour: BarTheme.red },
        "passthrough": { icon: 0, text: "   PASSTHROUGH : ESC",
                         colour: BarTheme.cyan },
        // CHORD_CHIP_LABELS' PASSTHROUGH-CONFIRM, and CHORD_CHIP_COLORS gives
        // it colors[1] — commented there as "urgent/warm — it is asking to
        // quit". colors[1] is the FOREGROUND colour, so the plate goes bright
        // and the text on it goes to the background: the one chord whose chip
        // inverts the bar, which is what makes a question look like a
        // question. Reproduced rather than promoted to red, which is what it
        // looks like it should be and is not what qtile draws.
        //
        // No glyph, for the same byte-level reason lang and passthrough have
        // none: the entry begins with three plain spaces in config.py.
        "passthrough-confirm": { icon: 0,
                         text: "   EXIT PASSTHROUGH ? y , n , ESC",
                         colour: BarTheme.fg }
    })
    property string submap: ""
    // Fed by the same `onRawEvent` below (Hyprland's `fullscreen>>1` /
    // `fullscreen>>0`), and read by ModeChip's `visible` further down: the
    // standalone chip must show only while the bar itself is actually
    // covered, or it would draw the mode label a second time right next to
    // the bar's own embedded chord chip whenever nothing is fullscreen.
    property bool focusedFullscreen: false
    readonly property var submapEntry: submapMap[shellRoot.submap] || null

    // fmt=" {} " — one space each side of whatever the transform returned.
    // The leading one rides on the icon when there is an icon, so the two
    // Texts stay flush against each other.
    readonly property string submapIcon:
        (submapEntry && submapEntry.icon)
            ? " " + String.fromCodePoint(submapEntry.icon) : ""
    readonly property string submapLabel: {
        if (shellRoot.submap === "")
            return "";
        if (!submapEntry)
            return " " + shellRoot.submap.toUpperCase() + " ";
        return (submapEntry.icon ? "" : " ") + submapEntry.text + " ";
    }
    readonly property color submapColour:
        submapEntry ? submapEntry.colour : BarTheme.accent

    Connections {
        target: Hyprland
        // Hyprland emits `submap>>name`, and an EMPTY name on reset. There is
        // no polling here on purpose: a submap is entered and left by a
        // keypress, so the event is exact and a timer would only add latency
        // to the one widget whose whole job is to be immediate.
        //
        // `fullscreen>>1` / `fullscreen>>0` rides the same socket and the same
        // Connections block on purpose — it is what ModeChip below needs to
        // know whether the bar underneath it is actually hidden, and adding a
        // second listener for one more event name is cheaper than a second
        // Connections object watching the same target.
        function onRawEvent(event) {
            const name = String(event.name);
            if (name === "submap")
                shellRoot.submap = String(event.data || "").trim();
            else if (name === "fullscreen")
                shellRoot.focusedFullscreen = String(event.data || "").trim() === "1";
        }
    }

    // ---- PENDING UPDATES ----
    //
    // qtile uses widget.CheckUpdates, which shells out to checkupdates itself.
    // This reads qupdate.py's CACHE instead — ~/.cache/qupdate.json, the list
    // it already maintains as a daemon in both sessions. Same number, no
    // second process asking pacman the same question, and it cannot disagree
    // with the update manager the chip's click opens.
    property int updateCount: 0
    readonly property string updatesText:
        updateCount > 0 ? "Updates: " + updateCount : ""

    FileView {
        path: Quickshell.env("HOME") + "/.cache/qupdate.json"
        watchChanges: true
        preload: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const list = JSON.parse(text());
                shellRoot.updateCount = Array.isArray(list) ? list.length : 0;
            } catch (e) {
                // Leave the last count. A torn read must not flash "no
                // updates" at somebody who has some.
            }
        }
    }

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

    // ---- THE CLOCK'S TOOLTIP IS TWO SCRIPTS, NOT A SENTENCE ----
    //
    // qtile's `_clock_tooltip_text`, ported: `scripts/prayer_next.sh` for the
    // next prayer and its countdown, `scripts/fx_rates.sh` for USD and EUR in
    // TL and EGP, joined by a blank line.
    //
    // Both halves are INDEPENDENT, which is that function's rule and is worth
    // keeping: whichever one comes back empty — dead network, cold cache —
    // drops its own block instead of blanking the tooltip. And the fallback
    // is qtile's old static string rather than nothing, so a machine where
    // neither script can run still says what the chip is for.
    //
    // FETCHED ON HOVER, not polled. The prayer block counts down in minutes,
    // so a poll would have to run two subprocesses a minute forever to keep a
    // string nobody is looking at correct. Chip.tooltipRequested fires on
    // pointer-enter and the tooltip is drawn 450 ms later, which is ample:
    // both scripts read a cache — prayer_next.sh refreshes once a day,
    // fx_rates.sh every six hours — and answer in ~40 ms warm. Measured here
    // at 44 ms and 38 ms.
    //
    // The two runs are SERIAL through one Process rather than two, because
    // that is the whole of what `sh -c 'a; echo; b'` buys and it keeps the
    // blank-line join in one place. A failed script contributes nothing and
    // is not an error: both `exit 0` with no output when they have nothing.
    readonly property string clockTooltipFallback: "Next prayer · USD/EUR rates"
    property string clockTooltip: shellRoot.clockTooltipFallback
    // Enough that moving along the bar and back does not re-run them, far
    // less than the minute the countdown changes in.
    property double clockTooltipFetchedAt: 0

    function refreshClockTooltip() {
        const now = Date.now();
        if (clockTooltipProcess.running || now - shellRoot.clockTooltipFetchedAt < 5000)
            return;
        shellRoot.clockTooltipFetchedAt = now;
        clockTooltipProcess.running = true;
    }

    Process {
        id: clockTooltipProcess
        command: ["sh", "-c",
            "p=\"$($HOME/.config/qtile/scripts/prayer_next.sh 2>/dev/null)\"; " +
            "f=\"$($HOME/.config/qtile/scripts/fx_rates.sh 2>/dev/null)\"; " +
            // printf and not echo: the blank line between the blocks only
            // belongs there when BOTH blocks exist.
            "if [ -n \"$p\" ] && [ -n \"$f\" ]; then printf '%s\\n\\n%s' \"$p\" \"$f\"; " +
            "else printf '%s%s' \"$p\" \"$f\"; fi"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = text.trim();
                shellRoot.clockTooltip = out !== ""
                    ? out : shellRoot.clockTooltipFallback;
            }
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

    // ---- A CHIP THAT CHANGES SOMETHING RE-READS IT ----
    //
    // Audited alongside the language chip, because the report was that the
    // others "feel the same". Every timer on this bar was checked:
    //
    //     TaskList / Workspaces  90 ms   debounce ON AN EVENT — fine
    //     clock                   1 s    a clock
    //     cpu / memory            2 s    /proc readouts nobody drives
    //     disk                   60 s    a readout nobody drives
    //     keyboard layout         3 s -> event driven, see the kb section
    //     VOLUME                  2 s    driven by THIS BAR's own scroll
    //
    // Only the volume chip had the language chip's actual shape: a control
    // whose own action changes the number it displays, with the display on a
    // poll. Scrolling it moved the volume immediately and the readout caught
    // up whenever the 2 s tick came round.
    //
    // Debounced rather than a poll per scroll event: a wheel sends a burst,
    // and one `wpctl get-volume` per notch is a process per notch. 80 ms is
    // after the wpctl that caused it has been applied and short enough that
    // the readout moves while the wheel is still turning. The 2 s poll stays
    // for volume changed anywhere else.
    Timer {
        id: volSoon
        interval: 80
        repeat: false
        onTriggered: volProc.running = true
    }
    function volumeSoon() {
        volSoon.restart();
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
        // TWO spaces after the glyph, which is config.py's format string
        // exactly: "\uf240  {char}{percent:2.0%}". One space sat the readout
        // a couple of pixels left of qtile's — the sort of thing that only
        // shows up with the two bars stacked on top of each other.
        return String.fromCharCode(0xF240) + "  " + ch + pct + "%";
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
            // The CONFIGURED LIST on a second line, so the event path can
            // resolve a display name against the layouts this machine
            // actually declares instead of against a table baked in here.
            "print(k.get('layout') or 'us')\n" +
            "\""]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.split("\n");
                // Kept as the raw key ("us", "ara"), because layoutMap is
                // keyed on it. Upper-casing here was why the map never hit.
                const t = (lines[0] || "").trim();
                if (t) shellRoot.keyboardLayout = t;
                const list = (lines[1] || "").trim();
                if (list !== "") {
                    const keys = list.split(",").map((x) => x.trim())
                        .filter((x) => x !== "");
                    if (keys.length > 0)
                        shellRoot.layoutKeys = keys;
                }
            }
        }
    }
    // ---- THE POLL IS A FALLBACK NOW, NOT THE MECHANISM ----
    //
    // Reported: clicking through us -> ara -> tr "visibly trails the
    // keypress". Measured before changing anything, and the handoff's two
    // candidates split cleanly:
    //
    //     the poll command itself   32-41 ms over five runs
    //     the poll INTERVAL         3000 ms
    //
    // so process-spawn latency is not what anyone was seeing. The glyph was
    // simply up to three seconds stale, and the layout had changed instantly
    // the whole time.
    //
    // Hyprland announces it. Confirmed on the live event socket by switching
    // layouts while listening:
    //
    //     activelayout>>at-translated-set-2-keyboard,Arabic
    //     activelayout>>keyd-virtual-keyboard,Turkish
    //     activelayout>>video-bus,English (US)
    //
    // one line PER KEYBOARD DEVICE — eight on this machine — carrying the
    // same display name the poll was already matching on. So the chip is
    // event-driven, and the timer drops from 3 s to a 30 s safety net that
    // exists only to re-sync if an event is ever missed. In the steady state
    // this is one python spawn every 30 s instead of twenty.
    Timer {
        interval: 30000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: kbProc.running = true
    }

    // The configured list, "us,ara,tr,de" — qtile's `configured_keyboards`.
    // Learned from the same devices query rather than hardcoded, so a machine
    // with different layouts still resolves.
    property var layoutKeys: ["us", "ara", "tr", "de"]

    // The substring each layout key is recognised BY, inside Hyprland's
    // display name. The poll's python one-liner carried this table; it is
    // here now because the event path needs the same answer and two copies of
    // a mapping is how they come to disagree.
    readonly property var layoutNameHints: ({
        "us": "english", "ara": "arabic", "tr": "turkish", "de": "german"
    })

    function layoutKeyForName(displayName) {
        const km = String(displayName).toLowerCase();
        for (const key of shellRoot.layoutKeys) {
            const hint = shellRoot.layoutNameHints[key] || key;
            if (km.indexOf(hint) >= 0)
                return key;
        }
        return "";
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (String(event.name) !== "activelayout")
                return;
            // "<device>,<Display Name>". The device may not contain a comma
            // but a display name can — "English (US, intl)" — so the split is
            // on the FIRST one only.
            const data = String(event.data || "");
            const at = data.indexOf(",");
            if (at < 0)
                return;
            const key = shellRoot.layoutKeyForName(data.substring(at + 1));
            if (key !== "")
                shellRoot.keyboardLayout = key;
        }
    }

    // ---- qtile's NON-ENGLISH WARNING ----
    //
    // config.py raises a sticky critical notification whenever the layout is
    // not `us` and takes it down when it returns, on a fixed replace id.
    // Nothing under Hyprland did either — neither the chip nor the language
    // submap — which is the second half of what was reported about this chip.
    //
    // Driven from the layout CHANGING rather than from the things that change
    // it, so the chip, the submap and anything else all get it for free. The
    // script is the shared copy; see its header for why the three notify-send
    // details are not adjustable.
    onKeyboardLayoutChanged: {
        // Not on the first assignment: the shell starts, reads "us" (or
        // whatever is current) and that is not a change the user made. Raising
        // a critical sticky warning because a bar restarted would be noise.
        if (!shellRoot.layoutWarningArmed) {
            shellRoot.layoutWarningArmed = true;
            return;
        }
        Quickshell.execDetached([Quickshell.env("HOME")
            + "/.config/hypr/scripts/layout-notify.sh", shellRoot.keyboardLayout]);
    }
    property bool layoutWarningArmed: false

    // ---- LAYOUT NAME ----
    //
    // The chip was stuck on "monadtall" through every $mod Tab and every
    // workspace switch, and the reason is that it was watching a file that
    // has never existed: ~/.cache/hypr/workspace-layouts, a JSON map of
    // workspace id to layout name. Nothing writes it. `ls ~/.cache/hypr`
    // holds a display-layouts directory and two wifi QR pngs.
    //
    // What layout-cycle.sh actually writes is
    // $XDG_RUNTIME_DIR/hypr-layouts/ — one file per workspace plus
    // `current`, holding the bare word monadtall | max | treetab. That is
    // where the island's LayoutState reads, so this now reads the same file
    // and the two bars cannot disagree.
    //
    // `current` and not the per-workspace file: workspace-layout.sh rewrites
    // it on every switch, so it already answers "what layout is the focused
    // workspace in" without this widget having to know which workspace that
    // is. It also means one watch instead of a watch that has to be moved.
    //
    // The /tmp fallback is layout-cycle.sh's own, so an unset XDG_RUNTIME_DIR
    // cannot point the writer and the reader at two different files.
    readonly property string runtimeDir: {
        const x = Quickshell.env("XDG_RUNTIME_DIR");
        return (x && String(x) !== "") ? String(x) : "/tmp";
    }

    // SteadyCurrentLayout renders qtile's layout NAME, and qtile's names are
    // lower case in `layouts` — the widget prints them as they are.
    property string layoutName: "monadtall"
    FileView {
        path: shellRoot.runtimeDir + "/hypr-layouts/current"
        watchChanges: true
        preload: true
        // Absent until layout-cycle.sh has run once, which on a fresh boot
        // may well be after this bar starts. An expected state, not an error.
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            // Trimmed because the writer uses `printf '%s'` and a future
            // `echo` would add a newline — a stray "\n" would widen the chip
            // and show as a layout name that does not match any of the three.
            const t = text().trim();
            if (t !== "")
                shellRoot.layoutName = t;
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
