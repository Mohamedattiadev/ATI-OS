# The Hyprland topbar — what it has to be

**BUILT.** `../quickshell/topbar`, launched by `scripts/topbar.sh`, and
`bar-switch native` no longer refuses on Hyprland. This file stays as the
record of what it was built AGAINST — the inventory below was extracted from
`qtile/config.py`'s AST and is what fidelity is measured by.

What is live: the logo and layout chips, the TaskList, the GroupBox, all four
WidgetBoxes with qtile's own toggle glyphs, MPRIS, CPU, memory, disk, volume,
battery, keyboard layout, the clock, and the tray.

What is not, and why:

* **`hintium_mode_chip`** — Hintium is X11-native and `binds.conf` records it
  as BLOCKED rather than unported, so there is no mode for the chip to show.
* **`chord_chip`** — Hyprland has submaps, not qtile KeyChords, and
  `submap-indicator.sh` already puts the submap name in the island. Two
  copies of one string is worse than one.
* **`CheckUpdates`** — the count comes from `qupdate.py`'s daemon, which this
  bar does not own. Left out rather than reimplemented badly.

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
6. Only then flip `hypr_native_available()` in `AtiScriptsV1/bar-switch` to
   true, and add the `$mod SHIFT Z` top/bottom swap that binds.conf reserves.

## Two things not to rediscover

* **The bar's own background is transparent.** A bar that maps with unpainted
  widgets is indistinguishable from no bar — that is exactly how the qtile side
  of `bar-switch` failed, and it took a rebuild to fix.
* **`_s()` is a UI scale factor.** Every size above is scaled; none of these
  numbers are literals to copy.
