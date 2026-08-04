# GIF catalogue

Every feature in this repo that is worth a recording, what triggers it, and
whether a clip in `IMGS/` covers it.

`Mod` = Super/Windows (`mod4`). `Alt` = `mod1`. Screen is 1366×768, so every
capture region below is inside that.

Status values:

- **exists** — the clip in `IMGS/` shows the feature and is good enough to keep.
- **new** — recorded in this pass, nothing was there before.
- **redone** — a clip existed but was re-shot (see *Sizes*, below).
- **skipped** — deliberately not recorded; the reason is in the last table.

## How these were recorded

Not on the visible desktop. A nested X server (`Xephyr :9 -screen 1366x768`)
was started, its own window immediately moved to a hidden qtile group, and a
**second qtile** run inside it from a copy of `.config/qtile` with the
`autostart.sh` hook disabled — so no second picom, dunst, copyq, eww or tray
applet ever touched the live session. Xephyr keeps a shadow framebuffer, so
`ffmpeg -f x11grab -i :9.0` captures a full, correctly themed desktop while
nothing at all appears on the real screen. Capture at 20 fps, then a
two-pass `palettegen`/`paletteuse` down to 12–14 fps.

Two consequences worth knowing before re-shooting anything this way:

- Anything that goes through **D-Bus** leaves the nested display. `notify-send`
  reaches the *real* dunst and pops on the owner's screen — that is what rules
  out `clock_popup` below.
- `xrandr` inside Xephyr reports one output called `default` at 0.00 Hz, which
  is why the display picker cannot be shot there.

---

## Recorded in this pass

| name | what it shows | trigger | dur | prio | status |
|---|---|---|---|---|---|
| `docs-menu.gif` | Logo menu — the seven live-generated sections, then `Esc` walking **back up** from Appearance to the parent instead of closing | left-click the Arch logo in the bar, or `rofi_docs` | 10 s | high | new |
| `keybindings.gif` | The searchable binding list — 85 bindings parsed out of `config.py` by AST, chord prefixes intact (`Super+P , C` for the theme picker, `Super+Shift+K , V` for the vim sheet), filtered live by typing | `rofi_docs keys` | 11 s | high | new |
| `cheatsheet-popup.gif` | The cheatsheet popup itself — cards, key hard against the right edge, `j` scrolling with the header % counter moving 0 → 17 → 42 %, `Tab` by screenfuls, then `v` swapping the qtile sheet for the vim one. Mode chip visible in the bar throughout | `Mod+Shift+K`, then `k`/`j`/`Tab`, `v`, `q` | 12 s | high | new |
| `audio-popup.gif` | Audio picker — Outputs with volume/gain/balance/port/profile detail, `Tab` to Mics | `Alt+3`, then `Tab`, `Escape` | 7 s | high | new |
| `widgetbox.gif` | The bar's three collapsible widget boxes opening and closing — CPU + memory, then the systray | `Alt+grave`, `Mod+grave`, `Alt+Tab` | 11 s | med | new |
| `rofi.gif` | Rofi-mode chip | `Mod+P` | 5 s | med | redone |
| `lang.gif` | Lang-Switch chip (`a`/`e`/`t`/`d`) | `Mod+Space` | 5 s | med | redone |
| `resize.gif` | Resize-mode chip | `Mod+R` | 5 s | med | redone |
| `draw.gif` | Draw-mode chip (gromit-mpx: `w`/`c`/`z`/`r`/`v`) | `Mod+Shift+W` | 5 s | med | redone |
| `cheatsheet.gif` | Cheatsheet-mode chip | `Mod+Shift+K` | 5 s | med | redone |

### Sizes

The five chip clips were 638×40 strips of the bar weighing 1.0–2.5 MB each —
30–60× what those pixels need. Re-shot at native resolution with a tighter
palette they are 17–37 KB, with no loss of content:

| | before | after |
|---|---|---|
| `resize.gif` | 2.5 MB | 17 KB |
| `rofi.gif` | 1.4 MB | 18 KB |
| `lang.gif` | 1.3 MB | 17 KB |
| `draw.gif` | 1.3 MB | 21 KB |
| `cheatsheet.gif` | 1.0 MB | 37 KB |

Net: the five old chips cost 7.5 MB, the five new ones cost 110 KB, and the
five new feature clips add 3.8 MB — so `IMGS/` ends up smaller than it was.

## Already good — left alone

| name | what it shows | trigger | dur | prio | status |
|---|---|---|---|---|---|
| `overview.gif` | 33 s cut of the full desktop tour | — (edited from `~/Videos/qtile-overview.mp4`) | 33 s | high | exists |
| `theme-picker.gif` | Theme picker rofi, 22 modes, current one marked `●` | `Mod+P` then `c`, or `theme-toggle` | 11 s | high | exists |
| `qdrop.gif` | Drop shelf — drag files/text/URLs in, drag them back out | `Alt+Shift+D` | 9 s | high | exists |
| `qupdate.gif` | Updates + install GUI, pacman/AUR checkboxes and repo search | click the updates chip in the bar | 10 s | high | exists |
| `veil.gif` | Restart veil — frosted desktop, a card per window, real progress from the incoming qtile | `Mod+Shift+R` | 8 s | high | exists |
| `wallpaper.gif` | Wallpaper-picker chip | `Mod+P` then `w` | 4 s | low | exists (oversized at 1.2 MB — see the skip table) |
| `themes.png` | 10 of the 22 palettes side by side | — (still) | — | high | exists |

## Not recorded — and why

| name | what it would show | trigger | prio | why not |
|---|---|---|---|---|
| theme switch, whole desktop | one `theme-apply` retinting bar, terminal, rofi, GTK, Qt, nvim and browser at once | `theme-apply gruvbox` | high | Cannot be done in the nested display — `theme-apply` writes global state and restarts qtile, so it would recolour and restart the **owner's live session**. Approved in principle with a restore step; held back because the owner asked for this pass to stay invisible. Worth one supervised take: the current theme is `mono-dark` (`~/.cache/qtile/theme_mode`), so the restore is `theme-apply mono-dark` |
| `clock-popup.gif` | today & week plans/todos | `Alt+P` | high | Two blockers. It renders `~/ATITODOS/TODOS.md` — the owner's real todos — and it draws via `notify-send`, which is D-Bus, so it lands on the real dunst and pops on the owner's screen even when launched on `:9`. Would need a fake `$HOME` with a synthetic todo file and a private dunst |
| `display-popup.gif` | display picker over `xrandr` — outputs, presets, saved layouts | `Alt+4` | high | Renders correctly, but inside Xephyr the only output is called `default` at **0.00 Hz** — it reads as a broken picker rather than a working one. Needs a take on real hardware, where it shows `eDP-1` |
| boot splash | Arch mark in a progress ring, username in ANSI Shadow, comet sweep | `boot-splash preview` | high | Rendered fine (60 frames, 1366×768, 19 KB) and `boot-splash status` reports the theme installed, hooked and **up to date** — but what it draws is the name above a *small* Arch logo with a three-dot spinner. There is no progress ring, and the README describes a ring at 26 % of screen height with the logo inside it. Shipping it would document a feature that does not match the picture. **This is a finding, not just a skip** — either the installed assets predate the ring, or `generate` is not producing it on this machine |
| wallpaper picker (redo) | the picker popup itself, not just the chip | `Mod+P` then `w` | low | Selecting a wallpaper rewrites `~/.cache/wall` and can re-derive the whole `wal` palette — global state, from a nested display, for a low-priority clip. The existing chip clip is kept as-is |
| wifi picker | `nmcli` picker — connect, forget, toggle radio, QR to phone | `Mod+P` then `n` | high | Lists the owner's saved SSIDs and every neighbouring network. Cannot be de-identified by cropping |
| bluetooth picker | `bluetoothctl` picker — pair, connect, trust | `Mod+P` then `b` | med | Same: shows the owner's devices by name |
| password picker | Vaultwarden/rbw picker, `Alt+a` types without touching the clipboard | `Mod+P` then `p` | med | Vault entries. Never record |
| clipboard picker | CopyQ rofi picker with thumbnails | `Alt+V` | med | Real clipboard history — and copyq is a session-wide server, so it is the *owner's* history either way |
| todo manager | `rofi_todo` | `Mod+P` then `t` | low | The owner's todos |
| translator | rofi translator + Gemini synonyms | `Mod+P` then `e` | low | Needs an API key set; the README already marks it ~70 % |
| homerow hint mode | AT-SPI hints over real UI elements, then click / scroll / caret / search | `Mod+Shift+F`, then `h`/`s`/`f`/`c` | med | Needs an AT-SPI-exposing app in front, and nothing in the nested session exposes one. Worth a second pass with a throwaway browser window |
| voice dictation | live phrase-by-phrase typing from whisper.cpp | `F8` (live) / `F9` (batch) | med | Needs the mic and the owner's voice |
| phone mirror | scrcpy over mDNS | `Mod+Shift+F6` | low | Needs the owner's phone attached |
| passthrough mode | every binding released to the focused app, `Mod+F12` to take them back | `Mod+F12` | low | Nothing visible happens beyond the chip |
| layouts | monadtall ↔ max ↔ treetab | `Mod+Tab` | low | Needs throwaway windows to be legible, and any real terminal shows a prompt with the owner's paths |
| screenshot to clipboard | area select straight to the clipboard | `Print` | low | A selection rectangle over whatever is on screen — nothing to show without content |
| logout menu | `dm-logout -r` | `Mod+Shift+Q` | low | One rofi list, and misfiring it ends the session |
| ui-scale | bar/font/margin sizes re-derived from real DPI | `ui-scale-toggle` | low | Changes the live session's scale; the effect reads as a before/after still, not a clip |
