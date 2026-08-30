# The Hyprland topbar — what it has to be

**BUILT.** `../quickshell/topbar`, launched by `scripts/topbar.sh`, and
`bar-switch native` no longer refuses on Hyprland. This file stays as the
record of what it was built AGAINST — the inventory below was extracted from
`qtile/config.py`'s AST and is what fidelity is measured by.

What is live: the logo and layout chips, the TaskList, the GroupBox with
qtile's own group ICONS, all four WidgetBoxes with qtile's toggle glyphs,
MPRIS, CPU, memory, disk, volume, battery, the keyboard layout with its flag,
the clock, the tray, and TOOLTIP_BY_NAME's tooltips on hover.

Its chips run qtile's commands — **rofi**, not the island's IPC. That is not
only fidelity: the island is stopped while this bar runs, so an IPC call
would find no instance and do nothing, silently.

`chord_chip` is live too, with qtile's own `CHORD_CHIP_LABELS` in it — the
key list, not the mode's name. It used to be listed below as deliberately
absent on the grounds that the island already draws the submap; that
reasoning was wrong in the one way that matters, since the island is STOPPED
while this bar runs, so there was never a second copy to avoid.

What is not here, and why:

* **`hintium_mode_chip`** — Hintium is X11-native and `binds.conf` records it
  as BLOCKED rather than unported, so there is no mode for the chip to show.
  On both bars, for the same reason.
* **`CheckUpdates`** — the count comes from `qupdate.py`'s daemon, which this
  bar does not own. It reads that daemon's cache instead of asking pacman a
  second time, so the number cannot disagree with the manager the chip opens.
* qtile's **`float_extra_qutebrowsers`** — floats the 2nd+ qutebrowser at
  900x600. A rule about how many instances exist, which Hyprland's rule
  language cannot ask; noted in `rules.conf`.

## What the bar does NOT draw, and where it went instead

Three of qtile's chips are buttons onto a POPUP rather than readouts, and the
popups are Quickshell now — `../quickshell/tide-island-fork/qml/popups/`,
served by a resident `popups.qml` that `topbar.sh` starts beside this bar:

| chip / key | qtile | here |
|---|---|---|
| the ✖ chip | `toggle_wallpaper_picker` | `WallpaperPopup.qml` |
| `$mod P` then `n` | Wifi-Mode | `NetworkPopup.qml` |
| `$alt 3` | Audio-Mode | `VolumePopup.qml` |

They share `PopupChrome.qml`, which is `WallpaperPopup.py`'s own frame — its
vertical rhythm, its card tones, its keycap bar and its JetBrainsMono. Each
popup's keys are its own file's chord from `config.py`.

Two more things belong to the SESSION rather than to either bar, and are
hosted by whichever shell is up:

* the **TreeTab sidebar** — `treetab.qml`, because treetab and max are the
  same arrangement without it;
* the **theme sweep** — the circular reveal, driven by
  `AtiScriptsV1/theme/theme-animate`, which hands a theme change to the island, or
  to the popups shell, or to plain `theme-apply` if neither is up.

## Both of qtile's bars

qtile builds **two** and shows one, swapped by `$mod SHIFT Z`. So does this:

| | top | bottom |
|---|---|---|
| height | `_s(28)` | `_s(40)` |
| background | `#11111b00` — transparent | `colors[2]` — opaque |
| widgets | chips, each with its own plate | bare widgets, `\|` separators |
| extra | TaskList | five launcher icons |

They are different bars, not one re-anchored — `config.py` builds two widget
lists for the same reason. `$mod SHIFT Z` drives the `topbar` IPC target;
position persists in `~/.cache/topbar-position`, deliberately NOT in
`~/.cache/bar-mode`, which answers the different question of island-vs-topbar.

## The Row-height trap, three times now

A `Row` derives its height FROM its children, so `height: parent.height` on a
child inside one is circular and Qt resolves it to **zero** — silently, with
the data correct. It has cost three debugging rounds here: the workspaces and
tray, the widget-box contents, and the bottom bar's launchers and readouts.
Give the Row an explicit height and take the child's from the component root.

It is a **reimplementation**, and that is not a shortcut — qtile's bar is part
of qtile and cannot run under another compositor. The target is
pixel-faithful: same layout, colours, decorations, glyphs and tooltips.

Built in **Quickshell**, decided against eww and waybar because it is already
this desktop's shell: layer-shell, the tray, MPRIS, Pipewire, Hyprland
workspace and toplevel feeds, and `IslandTheme`'s palette all come for free,
and the island already proves the stack on both display servers.

## The inventory

Extracted from `qtile/config.py` by walking its AST, not by reading it, so
this list is what the bar actually builds rather than what its comments say.

`bar.Bar(size=_s(28), margin=[5,10,5,10], background="#11111b00")` — the
background is fully transparent; **every visible pixel is a chip**.

### Left

| Widget | name | padding | fg |
|---|---|---|---|
| `TextBox` (Arch logo) | `main_icon_chip` | 11 | `colors[7]` |
| `SteadyCurrentLayout` | `w_layout` | 18 | `colors[3]` |
| `TaskList` | — | — | `colors[1]` |

Logo chip mouse map: **L** docs menu, **M** terminal, **R** launcher.
Layout chip: **R** cycles layout.

### Centre

`GroupBox`, `fontsize=_s(10)`. Not centred by spacers — `_center_top_groupbox()`
recomputes a fixed left spacer every layout change and pins the TaskList to a
computed width, because two STRETCH spacers only split the *leftover* space and
the GroupBox slid right as windows opened.

### Right, in order

`chord_chip`, `hintium_mode_chip`, `tooltip_widgetbox` (the 💡 lamp — toggles
onboarding), `w_mpris`, `system_widgetbox`, `wallpaper_toggle`,
`2nd_system_widgetbox`, `w_lang`, `w_clock`, `systray_widgetbox`, `w_cpu`,
`w_mem`, `w_updates`, `w_disk`, `w_volume`, `w_battery`, `Systray`,
`w_nightlight`, `w_wifi_qr`.

Several are `SmartWidgetBox`es that expand in place, so the right-hand side has
two widths and the centring arithmetic has to survive both.

### A tooltip can be DATA, and `w_clock`'s is

`TOOLTIP_BY_NAME` was reproduced as a table of strings, and that is right for
seventeen of the eighteen chips. It is wrong for the clock, whose entry —
"Next prayer · USD/EUR rates" — is a FALLBACK in qtile, not the tooltip:
`install_bar_tooltips()` replaces it with the dynamic `_clock_tooltip_text`
provider, which runs `qtile/scripts/prayer_next.sh` and `fx_rates.sh` and
joins their output. Reproducing the table and not the provider left a promise
of two numbers with neither number in it, and was reported as such.

Same class of miss as the TaskList's markup: reading the config rather than
what the widget does with it.

Ported with the provider's own rule intact — the two halves are independent,
so whichever script comes back empty drops its own block instead of blanking
the tooltip, and the static string is the floor. **Fetched on hover, not
polled**: the prayer block counts down in minutes, so a poll would run two
subprocesses a minute to keep a string nobody is looking at correct.
`Chip.tooltipRequested` fires on pointer-enter and the tooltip is drawn
450 ms later; both scripts read caches and answer in ~40 ms.

That is also why the hover sink keeps the CHIP rather than a snapshot of its
text — it latched the string at `enter()`, which is fine for a label and
wrong for data that arrives inside the delay.

## The font, which is two things and not one

`widget_defaults` is `font="Ubuntu Bold", fontsize=_s(10)`, and that string is
a pango font DESCRIPTION — family plus style. Qt parses a FAMILY, so
`font.family: "Ubuntu Bold"` finds nothing and falls back silently:

    fc-match "Ubuntu Bold"   ->  Noto Sans CJK KR, Regular
    fc-match "Ubuntu:bold"   ->  Ubuntu-B.ttf, Ubuntu Bold

Split into `Metrics.textFamily` and a bold flag. The flag is NOT applied to a
named icon face — Qt synthesises a bold cut for a family that has none, which
draws a heavier glyph than qtile's.

`fontsize` is PIXELS. It reaches pango through `set_absolute_size()`, which
takes device units — checked in the installed libqtile — so it maps onto
`font.pixelSize` with no point conversion.

**A pango markup `size=` is not that.** It is in points, so the tray
triangle's `size="15500"` is not comparable to the widget's `fontsize=_s(11)`
beside it. Measured rather than converted, by rendering config.py's span
through `pango-view` and trimming to the ink: 12x9, which is Adwaita Mono Bold
at **20 px** here and not 11.

## The chip

Every element carries its own rounded background — there are **no separators**
on this bar, deliberately (the one surviving pipe read as a stray mark). One
`RectDecoration` per widget:

```
colour     DEFAULT_CHIP_COLOR = [_plate, _plate]
radius     (_s(28) - 2*2) / 2      <- half the PLATE height, not the bar's
filled     true
padding_x  3
padding_y  2
```

The radius is derived, not hardcoded, and the reason is recorded in
`config.py`: a flat `11` against a 24 px plate leaves a 2 px straight segment
on each short side, which is the difference between "circle" and "squircle" and
was visible on the logo chip. **Keep the 28 in step with the bar's `size`.**

## Colours

`colors[N]` comes from `qtile/colors.py`, which reads `~/.cache/qtile/theme_mode`
and the pywal output. The island reads the same pipeline through `IslandTheme`,
so the topbar must take its palette from `IslandTheme` too — one theme change,
both bars, no third source of truth.

## Three things the build turned up

**Supplementary-plane glyphs DO render — the variable is the FACE.**
`NEXT-SESSION.md` says they paint nothing and concludes everything drawn in
this shell should stay in the BMP private-use block. Too broad: a probe
drawing twelve codepoints side by side in a panel showed U+F0570, U+F0336,
U+F0335, U+F05AF, U+F0902, U+F0042 and U+F035C all rendering correctly, in the
same run as the BMP ones, in **`Symbols Nerd Font`**. That is why the topbar
uses qtile's exact codepoints instead of lookalikes — and it is worth trying
on the island's own missing glyphs. Use `String.fromCodePoint`, never
`fromCharCode`, which takes a UTF-16 code unit and truncates above U+FFFF.

**A `Row` child must not take its height from its parent.** A Row derives its
height FROM its children, so `height: parent.height` on a delegate is circular
and Qt resolves it to zero. It cost three silent failures here — the
workspaces, the tray and the widget-box contents all rendered nothing while
their data was demonstrably correct. Take the height from the component root.

**Do not gate a clipper's `visible` on its own width.** `visible: width > 0`
where the width comes from a Row's `implicitWidth` deadlocks at zero: the Row
counts only visible children, and a child of an invisible parent is not
visible. Nothing in the cycle can ever become non-zero. The widget boxes
toggled their glyph and revealed nothing until that line came out.

## Order it was built in

1. The frame: `PanelWindow`, 28 px, 5/10 margins, transparent, plus the chip
   component (rounded plate, padding, the derived radius).
2. Cheap and self-contained: logo, layout, clock, CPU, memory, battery,
   keyboard layout.
3. Workspaces (`GroupBox`) off `Quickshell.Hyprland`, and the TaskList off
   `ToplevelManager`.
4. The centring arithmetic — port `_center_top_groupbox()`'s *rule*, not its
   code: fixed left spacer = bar centre − everything left of it, TaskList
   capped by what is left once the right-hand side is paid for.
5. Tray, MPRIS, the WidgetBoxes, tooltips.
6. Only then flip `hypr_native_available()` in `AtiScriptsV1/bar/bar-switch` to
   true, and add the `$mod SHIFT Z` top/bottom swap that binds.conf reserves.

## Two things not to rediscover

* **The bar's own background is transparent.** A bar that maps with unpainted
  widgets is indistinguishable from no bar — that is exactly how the qtile side
  of `bar-switch` failed, and it took a rebuild to fix.
* **`_s()` is a UI scale factor.** Every size above is scaled; none of these
  numbers are literals to copy.
