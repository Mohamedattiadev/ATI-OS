# The Hyprland topbar — what it has to be

The `native` half of `bar-switch` on Hyprland. Until it exists,
`bar-switch native` **refuses** in this session rather than taking the island
away and leaving no bar at all.

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

## Order to build it

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
