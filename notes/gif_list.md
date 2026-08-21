# GIF recording plan

Every user-visible feature in this repo that is worth a recording, what a
finished clip has to show, and the literal keys that produce it.

**All 16 GIFs currently in `IMGS/` are being replaced.** Nothing in that
directory is being kept as-is. Rows marked *re-shoot* name the old file only so
it is clear what is being superseded — assume the old framing, size and pacing
were wrong and shoot from the spec in column 2, not from the old clip.

## Status — 2026-08-06

**Every P1 that can be captured is shot, published, and on doomone.** The one
P1 outstanding is `ati-os-install.gif`, which is a QEMU capture through
`installScripts/iso/film-iso.sh` and does not use the nest at all.

The harness is no longer something each session rebuilds: it is committed at
[`video/capture/`](../video/capture/), and its README carries the containment
rules from this file plus the four more that building it turned up. A clip is
one file in `video/capture/clips/` that sets its region and timings and
defines `choreograph()`, with an optional `prepare()` for setup that must not
be in frame. `groups`, `layouts`, `veil`, `qupdate` and `audio-popup` are
there as worked examples.

**Two copies of every clip exist** — `IMGS/` is where they are recorded to,
`docs/assets/img/` is what GitHub Pages serves, and nothing syncs them. Five
re-shot clips sat in `IMGS/` for two days while the site kept serving the
superseded ones. `validate.sh` now fails if a basename present in both
differs, and warns about any doc asset no page references. Copy to both.

**Not every gap wants a clip.** `install-usb.html` and `install-git.html` had
no images at all between them — the two pages where somebody decides whether
to install this. Both are fixed with stills, not motion: the installer's
first screen (22 KB) and the wizard's module list (50 KB). A still is the
right answer when the subject does not move and the information is dense.
Neither needed the 3.1 MB a trimmed `ati-os-install` GIF costs.

**The nest can change this machine's audio, and now undoes it.** Read the
pipewire bullet under *Containment* before recording anything — it is no
longer only the audio clip's problem.

Still open: the P2 and P3 rows, and everything in *Cannot be captured safely*
that has not been given a per-clip go-ahead.

## Conventions

- `Mod` = Super / Windows (`mod4`). `Alt` = `mod1` (`mod2` in `config.py`).
- Chords are written the way `ati-qtile-keys` prints them: `Super+P , C` means
  press `Super+P`, release, then press `c`.
- Screen is **1366×768**. The top bar is `size=28` with a `5/10/5/10` margin,
  so the whole bar strip is **1366×38 at +0+0** and the chips sit inside
  y≈5–33.
- **"bar right cluster"** below means roughly **640×38 at +726+0** — that is
  where `chord_chip`, `homerow_mode_chip`, the widget boxes, battery, lang,
  clock and the tray live. It is an estimate from widget order, *not* a
  measured value: before recording, get the real x of `chord_chip` from the
  running nested qtile (`qtile cmd-obj -o bar top -f info`) and crop to it.
  Do not ship a crop that clips a chip.
- Every region is at **native resolution**. No upscaling, no `-s` on the
  ffmpeg output, ever. See *Capture method*.

## Priorities

- **P1** — goes in `README.md` or a `docs/*.html` page. Must exist.
- **P2** — worth having, second pass.
- **P3** — completeness; record if the session has time left.

---

## The clips

| filename | what it must SHOW | exact trigger | region | duration | priority | re-shoot or new |
|---|---|---|---|---|---|---|
| `overview.gif` | A continuous desktop tour: bar visible throughout, group switch with the GroupBox icon lighting up, a layout change, the logo menu opening and closing, one mode chip appearing and clearing. No dead frames, no cursor parked mid-screen. | scripted sequence — see the rows below for the individual keys | full screen 1366×768+0+0 | 25–35 s | P1 | re-shoot (`overview.gif`, cut from `~/Videos/qtile-overview.mp4` — this one is re-shot in Xephyr instead) |
| `groups.gif` | The GroupBox in the bar: the active group's **icon glyph** (not a digit) recolours to the accent as the number changes, the TaskList to its left empties and refills with that group's windows. Show at least 4 groups, including one with windows and one empty. **There is no pill** — `highlight_method="text"`, so only the glyph recolours. `hide_unused=True` means windows must be seeded across several groups or there is nothing to see move. | `Super+1`, `Super+2`, `Super+4`, `Super+8` | top bar strip 1366×38+0+0 | 7 s | P1 | **done** — doomone, published |
| `layouts.gif` | The layout chip's **text changes** `monadtall → max → treetab` and the tiling behind it rearranges in the same frame — two dummy terminals side by side, then one full-width, then a TreeTab side panel. | `Super+Tab` three times (also: right-click the layout chip) | full screen | 8 s | P1 | **done** — doomone, published |
| `modes-chip.gif` | One clip, the `chord_chip` only: it is empty, then fills and its RectDecoration turns that mode's accent colour, `Esc` clears it, and so on through six modes. Each legible for ≥0.8 s; the chip returns to empty/default colour between every one. **The chip does not display the internal mode name** — it shows a hint string listing the keys the mode accepts: `󰍉 ROFI : i , o , p , w , z , b , e , r , t , y , f , s , n , h`, `󰏫 DRAW : w , c , z , r , v`, and so on. `CHORD_CHIP_COLORS`' keys are internal names, not display text. Note Draw-Mode and CheatSheet-Mode are **both** `colors[3]`, so two of the six beats share a colour — config, not capture. This is the clip that replaces the five "too bad" chip GIFs. | `Super+P` `Esc`, `Super+Space` `Esc`, `Super+R` `Esc`, `Super+Shift+W` `Esc`, `Super+Shift+K` `q`, `Super+slash` `Esc` | bar right cluster ~640×38+726+0 | 12 s | P1 | re-shoot (replaces `rofi.gif`, `lang.gif`, `resize.gif`, `draw.gif`, `cheatsheet.gif` — all five) |
| `mode-rofi.gif` | `Rofi-Mode` alone in the chip, accent colour, plus the fact that digits still switch groups while the chord is held (`group_keys()` is spliced into this chord). | `Super+P`, then `2`, then `Esc` | bar right cluster | 5 s | P2 | re-shoot (`rofi.gif`) |
| `mode-lang.gif` | `Lang-Switch` in the chip **and** the `w_lang` chip changing `🇺🇸 EN → 🇸🇦 AR → 🇹🇷 TR → 🇩🇪 DE`. Both chips must be in frame — the old clip showed only the chord chip, which is the half that says nothing. | `Super+Space`, then `a`, `t`, `d`, `e`, then `Esc` | bar right cluster | 7 s | P2 | re-shoot (`lang.gif`) |
| `mode-resize.gif` | `Resize-Mode` in the chip **and a window actually resizing** — the monadtall main pane shrinking and growing behind it. Chip-only is what made the old one useless. | `Super+R`, then `Shift+h` ×4, `Shift+l` ×4, `Shift+n`, `Esc` | full screen | 8 s | P2 | re-shoot (`resize.gif`) |
| `mode-draw.gif` | `Draw-Mode` in the chip **and gromit-mpx actually drawing** — a freehand stroke over a window, `z` undoing it, `c` clearing. | `Super+Shift+W`, then `w`, draw with the mouse, `z`, `c`, `Esc` | full screen | 8 s | P2 | re-shoot (`draw.gif`) |
| `mode-media.gif` | `Media-Mode` in the chip and the `w_volume` chip's percentage stepping up/down as keys are pressed. | `Super+slash`, then `Shift+k` ×3, `Shift+j` ×3, `Shift+m`, `Esc` | bar right cluster | 6 s | P2 | new |
| `mode-passthrough.gif` | `PASSTHROUGH` in the chip; a key that normally does something in qtile (e.g. `Super+Tab`) reaching the focused app instead; `Super+F12` taking the bindings back and the chip clearing. Needs a focused app that visibly reacts. | `Super+F12`, then `Super+Tab` (goes to the app), then `Super+F12` | full screen | 7 s | P3 | new |
| `cheatsheet-qtile.gif` | The qtile cheatsheet popup: cards, key hard against each card's right edge, `j`/`k` scrolling a few rows with the header's **% counter moving**, `Tab` jumping a screenful, symbol legend (`⇧ ⌃ ⏎ ␣`) visible in the header. `CheatSheet-Mode` chip in the bar throughout. | `Super+Shift+K , K` (`Super+Shift+K` alone only enters the chord), then `j` ×3, `Tab`, `Shift+Tab`, `Esc` | full screen | 12 s | P1 | **done** — doomone, published |
| `cheatsheet-vim.gif` | `v` **replacing** the qtile sheet with the vim sheet in place — the old sheet closes and the vim one opens, only ever one on screen. | `Super+Shift+K , V`, then `j` ×2, `q` | full screen | 7 s | P2 | new (the old `cheatsheet-popup.gif` had a `v` beat inside it) |
| `cheatsheet-fish.gif` | The fish + kitty sheet, same treatment. | `Super+Shift+K , F`, then `j` ×2, `q` | full screen | 6 s | P3 | new |
| `docs-menu.gif` | The logo menu: left-click the Arch chip, all **seven** sections listed (Keybindings, Cheatsheets, Documentation, Espanso, Appearance, System, Maintenance), enter Appearance, then **`Esc` walking back up to the parent instead of closing** — that return is the point of the clip. Every frame the rofi window must be the same 614×432 shape. | left-click `main_icon_chip` (leftmost Arch glyph in the top bar); equivalently run `rofi_docs` | full screen | 10 s | P1 | **done** — doomone, published |
| `keybindings.gif` | The searchable binding list — 85 bindings parsed out of `config.py` by AST — with **chord prefixes intact**: `Super+P , C`, `Super+Shift+K , V`, `Super+Shift+F , Shift+V`. Then typing filters the list live down to a couple of rows. | `rofi_docs keys` (or the logo menu → Keybindings) | full screen | 10 s | P1 | **done** — doomone, published |
| `docs-maintenance.gif` | The Maintenance section with a **live count on each entry** (pacnew merges, orphans, boot errors, cache), and one entry opening its *list* rather than a bare confirm. | `rofi_docs` → Maintenance | full screen | 8 s | P2 | new |
| `docs-troubleshooting.gif` | The troubleshooting index showing each entry's **`Symptom:` line instead of its heading**, then selecting one and landing on that line in `nvim -R`. | `rofi_docs` → Documentation → Troubleshooting | full screen | 9 s | P2 | new |
| `docs-espanso.gif` | The Espanso section listing which of the 26 snippet variables are **set** vs **missing**. Only safe if the nested session runs with a scrubbed `/etc/environment` view — otherwise it prints the owner's real name/email values. See *Cannot be captured safely*. | `rofi_docs` → Espanso | full screen | 6 s | P3 | new |
| `docs-system.gif` | The System section — about, package audit, failed services, display + GPU — all run live at open time. Under Xephyr the display line will read `default` / 0.00 Hz; crop it out or drop the row. | `rofi_docs` → System | full screen | 6 s | P3 | new |
| `qupdate.gif` | The update manager: tab one lists pending pacman + AUR packages with **checkboxes toggling**, tab two searches repos + AUR and shows results arriving. Opened from the bar chip, so the click and the window appearing are in the same clip. | click the `w_updates` chip inside the 2nd widget box (open it with `Super+grave` first), or `python3 ~/.config/qtile/scripts/qupdate.py --toggle` | full screen | 12 s | P1 | **done** — doomone, published; checkbox toggling + repo/AUR search |
| `qdrop.gif` | The drop shelf: `Alt+Shift+D` slides it in, a file is **dragged into it and a tile appears**, then that tile is **dragged back out** into another window. Both directions, or the clip does not make its point. | `Alt+Shift+D` (`mod2+shift+d` → `qdrop.py --toggle`), then mouse drags | full screen | 10 s | P1 | re-shoot (`qdrop.gif`) |
| `qdrop-shake.gif` | Dragging a file, **shaking the mouse mid-drag**, and the shelf appearing on its own — no keys pressed. This is a mouse gesture handled by `scripts/qdrop_watch.py`, **not a keybinding**; it needs `qdrop_watch.py` running in the nested session. | drag a file with Button1 and reverse direction ≥2 times inside the time window | full screen | 7 s | P2 | new |
| `veil.gif` | The restart veil: desktop frosts over, **one card per open window** appears, a real progress indicator advances (driven by the incoming qtile, not a fake timer), then the veil lifts onto a restored desktop with the same windows in the same groups. | `Super+Shift+R` | full screen | 8 s | P1 | **done** — doomone, published; full arc, real progress states |
| `widgetbox-system.gif` | The `system_widgetbox` chip expanding **in place** — the `󰖯` glyph becomes `󰖰` and CPU + Memory chips slide out beside it, pushing the rest of the cluster along; then collapsing back. | `Alt+grave` | bar right cluster | 5 s | P2 | re-shoot (`widgetbox.gif` — split into three) |
| `widgetbox-2nd.gif` | The 2nd widget box expanding to Updates + Disk + Volume, then collapsing. | `Super+grave` | bar right cluster | 5 s | P2 | re-shoot (`widgetbox.gif`) |
| `widgetbox-systray.gif` | The tray box: the `△` opening into the actual systray icons plus the night-light and wifi-QR chips, then closing. **Only safe if the nested session's tray is empty or seeded with throwaway apps** — the real tray shows the owner's running apps. | `Alt+Tab` (`mod2+tab` → `systray_widgetbox.toggle()`) | bar right cluster | 5 s | P3 | re-shoot (`widgetbox.gif`) |
| `bar-tooltips.gif` | Hovering across the bar: a tooltip appears under each chip in turn — "Current mode", "Layout · R-click to cycle", "CPU + Memory", "Pending updates · click → update manager". Cursor must be visible. | mouse hover only, no keys | top bar strip 1366×38+0+0, grown to ~1366×90+0+0 so the tooltip below the bar is in frame | 8 s | P2 | new |
| `bar-chip-flash.gif` | A clickable chip **flashing brighter on click** (`_ChipFlashMixin` brightens the RectDecoration by 0.55 and decays) — the feedback that says a bar click registered. | left-click any chip with a `mouse_callbacks` entry, e.g. the layout chip | 300×38 crop around one chip | 3 s | P3 | new |
| `bar-toggle.gif` | The top chip bar and the bottom "normal user" bar swapping: the transparent 28px top bar disappears and the 40px solid bottom bar with its LaunchBar icons appears, and back. | `Super+Shift+Z` | full screen | 6 s | P2 | new |
| `mpris.gif` | The Mpris2 chip: track title scrolling within its 220px width, `⏸`/`▶` glyph flipping on click. Needs a player in the nested session playing a file with **non-personal** metadata. | left-click `w_mpris`, or start a player and let it scroll | 300×38 crop around the chip | 6 s | P3 | new |
| `lang-chip.gif` | Left-click on the `w_lang` chip cycling the layout forward and right-click cycling it back — the flag + code changing without entering any mode. | left-click / right-click `w_lang` | 200×38 crop | 4 s | P3 | new |
| `onboarding.gif` | The eww onboarding tour: clicking the 💡 chip opens `onboarding-welcome`, then the steps → workspaces → keybindings → finish windows. | left-click `tooltip_widgetbox` (the 💡 chip); equivalently `eww open onboarding-welcome` | full screen | 10 s | P2 | new |
| `theme-picker.gif` | The theme picker rofi listing all 22 modes with the current one marked `●`, scrolling through them, then `Esc` **without selecting**. Do not press Enter — see *Cannot be captured safely*. | `Super+P , C` (or `theme-toggle`) | full screen | 9 s | P1 | re-shoot (`theme-picker.gif`) |
| `themes.png` | Still: 10+ of the 22 palettes side by side, same window content in each. | — (composited still, not a capture) | — | — | P1 | re-shoot (`themes.png`) |
| `theme-apply.gif` | **One supervised take on the real desktop**: a single `theme-apply gruvbox` retinting the bar, terminal, rofi, GTK, Qt and nvim at once. Must be followed by `theme-apply mono-dark`. See *Cannot be captured safely* — do not record without an explicit go-ahead. | `theme-apply gruvbox` in a terminal | full screen, real display | 10 s | P2 | new |
| `wallpaper-picker.gif` | The wallpaper picker popup itself — the grid, `h`/`j`/`k`/`l` moving the selection, `r` jumping to a random entry, `/` opening the fuzzy rofi search — then `Esc`. **Never press Enter**: applying rewrites `~/.cache/wall` and can re-derive the whole `wal` palette. | `Super+P , W`, then `l`, `j`, `r`, `slash`, `Esc`, `Esc` | full screen | 9 s | P2 | re-shoot (`wallpaper.gif`, which showed only the chip and weighed 1.2 MB) |
| `audio-popup.gif` | The audio picker: Outputs view with per-sink volume / gain / balance / port / profile detail, `Tab` to Inputs (mics), `o`/`i`/`a` switching views, `j`/`k` moving the cursor, `m` muting a sink and the row visibly changing state. | `Alt+3`, then `Tab`, `j`, `m`, `o`, `Escape` | full screen | 10 s | P1 | **done** — doomone, published. **THE WARNING STILL STANDS FOR ANY RE-SHOOT: `m` mutes the owner's REAL sink.** pipewire lives in the shared `XDG_RUNTIME_DIR` and cannot be contained by the `$HOME` overlay. What worked: read `pactl get-sink-mute`/`get-sink-volume` first, and note that this machine sits **muted at 150%** — so the honest choreography is `m` to UNMUTE (same visible state change, opposite direction) then `m` to restore, which is the ordering that leaves the machine correct even if the take dies halfway. No volume keys anywhere. Restore with `pactl set-sink-mute 1` + `set-sink-volume 150%` unconditionally after the shoot, whatever its exit code, and re-read both to confirm. Verified identical before and after: `Mute: yes`, `98304 / 150% / 10.57 dB` |
| `launcher.gif` | `rofi -show drun -show-icons` opening, typing filtering to one app, Enter launching it. | `Super+Shift+Return` | full screen | 6 s | P2 | new |
| `scratchpads.gif` | A dropdown scratchpad sliding in over the current group and toggling away again without disturbing the layout underneath — the terminal one is the safe choice. | `Alt+1` (term1), `Alt+1` again; `Alt+5` (calc), `Alt+5` | full screen | 7 s | P2 | new |
| `float-fullscreen.gif` | One window going floating (`Super+t`), then fullscreen (`Super+f`), then max/min toggle (`Super+x`), with the border and margins visibly changing each time. | `Super+t`, `Super+f`, `Super+f`, `Super+x`, `Super+x` | full screen | 8 s | P2 | new |
| `window-move.gif` | Windows being shuffled inside a layout — `Super+Shift+h/j/l` swapping panes — and `Super+Shift+Space` toggling split/unsplit. | `Super+Shift+l`, `Super+Shift+h`, `Super+Shift+j`, `Super+Shift+Space` | full screen | 7 s | P3 | new |
| `mouse-drag.gif` | `Super`+left-drag moving a floating window and `Super`+right-drag resizing it, without touching a titlebar. | hold `Super`, drag Button1; hold `Super`, drag Button3 | full screen | 6 s | P3 | new |
| `ati-kill.gif` | The process killer: list of processes, typing filters, selection kills it and the window disappears. Use a throwaway process. | `Super+P , K` | full screen | 6 s | P3 | new |
| `rofi-light.gif` | The brightness picker changing screen backlight. Under Xephyr there is no backlight device — likely shows an error. Verify before shooting; if it errors, drop the row. | `Super+P , L` | full screen | 5 s | P3 | new |
| `screenshot-chip.gif` | Clicking the camera chip on the bottom bar (or `Print`) putting a selection rectangle on screen and the region landing in the clipboard. Needs neutral on-screen content to select. | `Print`, or click `screenshot_chip_nu` on the bottom bar (`Super+Shift+Z` to reach it) | full screen | 6 s | P3 | new |
| `logout-menu.gif` | The `dm-logout -r` rofi list — lock / logout / reboot / poweroff — opening and being dismissed with `Esc`. **Never press Enter.** | `Super+Shift+Q` (or `Super+P , Q`) | full screen | 4 s | P3 | new |
| `homerow-hint.gif` | Hint mode: `Super+Shift+F` puts `Hint-Mode` in the chip, `h` overlays AT-SPI hint labels on the real UI elements of a focused app, typing a hint's letters clicks it. Needs an AT-SPI-exposing app (a throwaway GTK window) in the nested session — nothing in a bare qtile exposes one. | `Super+Shift+F , H`, then type a hint | full screen | 9 s | P2 | new |
| `homerow-scroll.gif` | Scroll mode: `s` picks a scrollable region and vim keys drive it; also the bare `Alt+j` shortcut that skips the chord. | `Super+Shift+F , S`, then `j`/`k`; and `Alt+j` | full screen | 7 s | P3 | new |
| `clock-tooltip.gif` | Hovering the clock chip: the tooltip opens with the **next prayer and a live countdown** on top, and **USD/EUR quoted in two currencies** on the lines under it, the prayer line centred over the FX lines. Two live scripts behind one chip. | mouse hover over `w_clock`, no keys | top bar strip grown to ~1366×110+0+0 so the tooltip below the bar is in frame | 6 s | P1 | **done** — doomone, published; neutral prayer/FX values, frames checked |
| `screenshot-satty.gif` | `ati-satty` taking a region screenshot and **opening it in the annotation editor** — draw an arrow or a box on it, then save/copy. The editing step is the point; a bare region grab is already `screenshot-chip.gif`. | `Super+P , I` | full screen | 9 s | P2 | new |
| `screen-record.gif` | The `ati-record` menu listing its capture modes (video, audio, webcam, GIF), picking one, the region select, and the **recording indicator appearing**. Stop it before it writes anything large. | `Super+P , R` | full screen | 9 s | P2 | new |
| `spellcheck.gif` | `dm-spellcheck` checking a word and a whole sentence, with the **corrections listed in a rofi table** and one being chosen. Use throwaway text with a deliberate typo — never the owner's real selection. | `Super+P , S` | full screen | 8 s | P2 | new |
| `safe-update.gif` | The guarded upgrade: its pre-flight checks running and reporting before any package is touched. **Must not actually upgrade** — stop at the confirm. | `rofi_docs` → Maintenance → safe-update | full screen | 8 s | P2 | new |
| `mpv-pip.gif` | An mpv window dropping into picture-in-picture — shrinking to a corner, staying on top, while another window is focused underneath. Needs a throwaway video with non-personal content. | `Super+slash , Shift+P` | full screen | 6 s | P3 | new |
| `nightlight.gif` | The night-light chip: left-click warming the whole screen and the chip's glyph changing, right-click turning it off. The colour shift must be visible in the frame, not just the chip. | left-click / right-click `w_nightlight` in the tray box | full screen | 5 s | P3 | new |
| `ati-adhkar.gif` | The periodic remembrance popup appearing on its own and dismissing. Runs from `autostart.sh`. **Content is religious and personal — the owner must look at the frames and approve before this ships.** | runs on a timer; force one from the nest | full screen | 5 s | P3 | new |
| `boot-splash.gif` | The boot screen: solid `ATI` block art centred on 38 % of screen height, the small Arch mark under it at 80 % opacity, and three dots at 81 % whose liveness wave travels through them while the progress fill creeps left to right. | `boot-splash preview` (no `--real`) — composites stills from the installed theme assets to a GIF, never touches the display | 1366×768, composited | 60 frames | P2 | **done** — recorded and verified this session |
| `ati-os-install.gif` | The ISO install: boot, **the plymouth splash actually caught** (sample at 1 s during boot), the wizard's three modes, and a desktop segment **with the qtile bar visible** — that segment must come from the real machine, since QEMU has no GPU, picom cannot composite and the `#11111b00` top bar renders as nothing. ~0.25 s/frame, not 0.9. | `installScripts/iso/film-iso.sh` | QEMU window, native | 30–45 s | P1 | **still outstanding as a clip.** The existing `~/ati-os-install.gif` (outside the repo) is unusable as shipped: 9.6 MB, 0.9 s/frame, and its desktop tail has no bar plus a "no battery found" error, exactly as this row says. Trimming it to the install portion (frames 8–113) and re-encoding gets it to 3.1 MB as GIF or 1.6 MB as h264 — the palette makes no difference because the source is already flat terminal text, so the only lever is frame count or dimensions, and neither may be scaled. **What shipped instead:** a single 22 KB still of the installer's first screen, on `install-usb.html` §4, which had no image at all. That is the higher-value half — it is the screen you actually decide from. The motion clip needs a fresh QEMU run, and per this row the desktop segment has to come from real hardware anyway |

**58 rows. 15 are P1** (`overview`, `groups`, `layouts`, `modes-chip`,
`cheatsheet-qtile`, `docs-menu`, `keybindings`, `qupdate`, `qdrop`, `veil`,
`theme-picker`, `themes.png`, `audio-popup`, `ati-os-install`) — plus
`clock-tooltip`, added later and P1 too, which makes 16.

**P1 status: 15 of 16 shot and published.** The exception is
`ati-os-install`, which needs QEMU rather than the nest.

On palettes: `overview`, `modes-chip` and `theme-picker` were checked
frame-by-frame and are already doomone, so they were left alone — the theme
picker even shows DoomOne as the active row. `qdrop` was checked too and is
inconclusive rather than wrong: its bar sits over a pale wallpaper for most
of the clip, so there is not enough chrome in frame to call the palette
either way. Not worth a re-shoot on that evidence; worth re-checking if it
is ever re-shot for another reason. Everything else was re-shot onto
doomone.

---

## Cannot be captured safely

Nothing in this section gets recorded without the owner saying so, in the
session, for that specific clip.

| feature | trigger | why not |
|---|---|---|
| clock popup — today & week plans/todos | `Alt+P` (`clock_popup`) | Renders **`~/ATITODOS/TODOS.md`** — the owner's real todos — on screen. It also draws through `notify-send`, which is D-Bus, so it reaches the *real* dunst and pops on the owner's screen even when launched on `:9`. Would need a fake `$HOME` with a synthetic todo file **and** a private dunst on the nested display before it could be shot at all. |
| wifi picker | `Super+P , N` | Lists the owner's saved SSIDs and every neighbouring network by name. Cannot be de-identified by cropping — the SSIDs *are* the content. |
| wifi QR chip | click `w_wifi_qr` in the tray box | Encodes the owner's current network **and its passphrase** into a scannable image. Never record. |
| bluetooth picker | `Super+P , B` | Shows the owner's paired devices by name (phone, headphones, watch). |
| password picker | `Super+P , P` | Vaultwarden / `rbw` vault entries. Never record, cropped or otherwise. |
| clipboard picker | `Alt+V` (`ati-copyq-rofi`) | Real clipboard history with thumbnails. CopyQ is a session-wide server, so a nested instance still reads the **owner's** history. |
| todo manager | `Super+P , T` (`rofi_todo`) | The owner's todos. |
| notes | `Super+P , O` (`dm-note -r`) | The owner's notes. |
| documents / manpage / config pickers | `Super+P , D` / `Super+P , M` / `Super+P , F` | `dm-documents` and `dm-confedit` list real paths under `$HOME`; the file names are personal data. Safe only from a scrubbed fake `$HOME`. |
| espanso variable list | `rofi_docs` → Espanso | Shows which of the 26 variables are set, and the fix flow opens `/etc/environment` with `sudoedit`. The *names* are fine; the values (real name, email, addresses) are not, and one careless frame of the editor leaks them. Listed as P3 above **only** on the condition that the values are never shown. |
| display picker | `Alt+4` | Renders correctly, but inside Xephyr `xrandr` reports a single output called **`default` at 0.00 Hz**, so the picker reads as broken rather than working. It needs a take on real hardware where it shows `eDP-1` with a real refresh rate. Do not ship the Xephyr version. |
| theme switch, whole desktop (`theme-apply.gif` above) | `theme-apply gruvbox` | `theme-apply` **restarts qtile and rewrites global state** — `~/.cache/wal`, the rofi `current-palette.rasi`, GTK/Qt settings, the browser theme extension. It cannot be contained in the nested display; it would recolour and restart the **owner's live session**. If it is ever recorded, it is one supervised take on the real desktop, and the session **must** be restored immediately afterwards with `theme-apply mono-dark` (the current mode, per `~/.cache/qtile/theme_mode`). |
| wallpaper *apply* (as opposed to browsing) | `Super+P , W` then `Enter` | Selecting rewrites `~/.cache/wall` and can re-derive the whole `wal` palette. The `wallpaper-picker.gif` row above navigates only and exits with `Esc`; do not press Enter. |
| voice dictation | `F8` (live) / `F9` (batch) | Needs the microphone and the owner's voice; the transcript is whatever was said. |
| phone mirror | `Super+Shift+F6` (`phone_screen`) | Mirrors the owner's Android phone — home screen, notifications, messages. |
| anki | `Super+P , A` (`rofi_anki`) | The owner's decks and cards. |
| translator | `Super+P , E` | Needs `GEMINI_API_KEY` from `~/.config/secrets.env`, and the input is whatever text is selected. README already marks it ~70 %. |
| shared link preview / youtube menu | `Super+P , Z` / `Super+P , Y` | Reads the owner's clipboard and browsing history. |
| tray contents | `Alt+Tab` | The systray shows the owner's running apps. The `widgetbox-systray.gif` row is conditional on the nested tray being empty or seeded with throwaway apps only. |
| clock tooltip — prayer + FX values | hover `w_clock` | The *feature* is fine to record and is P1 above; the **values** are not. `prayer_next.sh` defaults to `PRAYER_CITY`/`PRAYER_COUNTRY` (Cairo / Egypt) and `fx_rates.sh` quotes USD/EUR in TRY and EGP — together those disclose where the owner lives and which currencies they care about. Shoot `clock-tooltip.gif` with **neutral values overridden in the nest's environment**, so the behaviour is honest and the setup is not. Do not crop the values out and call it done: a tooltip with its content removed shows nothing. |
| ui-scale | `ui-scale-toggle` (no keybinding — command only) | Changes the live session's scale and restarts qtile. The effect is a before/after pair of stills, not a clip. |

---

## Scripts with no trigger — resolved

All four of the genuinely unreachable scripts have been dealt with. Kept
here because the audit that found them was wrong twice, and the corrections
are worth more than the list was.

| script | outcome |
|---|---|
| `rofi_ilovepdf` | **Wired** to `Super+P , V`, then rebuilt into a 23-action offline PDF toolkit. Four of its original twelve actions did not work. |
| `ati-keymaps` | **Wired** into the docs menu, Cheatsheets → "Your own shortcuts". Worth having beside the three hand-written sheets because it is parsed live: `FishCheatsheet.py` never reads `config.fish`, so the 79 functions and aliases actually defined there appeared on no sheet at all. Also lists 91 qtile bindings. |
| `collector_app.py` | **Deleted.** It could not run: imported nowhere, the `it.mijorus.collector` flatpak is not installed, and the `_collector` group it parks its window in is not defined in `config.py`. In git history if it is ever wanted. |

Two earlier claims in this file were wrong, and are corrected above and in
the git log: `ati-reset-pc` (`Mod+Shift+F5`) and `sum_app.py` (`Mod+Shift+S`)
were never orphans — both are invoked through a path or a helper rather
than by bare name, which is what a search for the bare name misses.

## Capture method

This is the agreed technique. It is not a suggestion — a recording agent should
not improvise around it.

**Nothing may ever appear on the owner's real screen.**

1. **Nested X server.** Start `Xephyr :9 -screen 1366x768 -ac -br -noreset` and
   immediately move the Xephyr window itself to a hidden qtile group on the real
   display. Xephyr keeps a shadow framebuffer, so `x11grab` captures a full,
   correctly-themed desktop even while its window is not visible anywhere.
2. **A second qtile, from a copy.** Copy `~/.config/qtile` to a scratch
   directory and **disable the `autostart.sh` hook** in the copy. Run
   `DISPLAY=:9 qtile start -c <copy>/config.py`. The autostart hook is what
   would otherwise launch a second picom, dunst, copyq, eww and tray applet
   against the owner's live session.
3. **Capture.** `ffmpeg -f x11grab -framerate 24 -video_size <W>x<H>
   -i :9.0+<X>,<Y> -codec:v ffvhuff <clip>.mkv`, then convert. 20–24 fps in,
   never more.
4. **Native resolution.** Capture the region at its real pixel size and never
   scale it up. Evidence: re-shooting the mode chips at native size took them
   from **1.0–2.5 MB down to 17–37 KB with identical content** — a 30–60×
   saving purely from not upscaling a 640×38 strip.
5. **Two-pass palette.** `palettegen` then `paletteuse`
   (`stats_mode=diff` for mostly-static clips), with
   `split[a][b];[a]palettegen[p];[b][p]paletteuse`. Drop to 12–14 fps on output
   where motion allows.
6. **Size cap ~1 MB per clip**, unless the content genuinely needs more (a
   full-screen 30 s tour does; a bar strip never does). A bar-only clip over
   100 KB means something is wrong with the pipeline, not with the content.
7. **Trim dead air at both ends.** The first frame should already be the
   subject; the last frame should be the result, not an idle desktop.
8. **Inspect every clip's frames before keeping it.** Extract frames
   (`ffmpeg -i clip.gif -vsync 0 /tmp/f%03d.png`) and *look at them*. This
   project has already shipped a screenshot that was actually QEMU's "display
   not initialized" placeholder. A clip that "recorded successfully" is not a
   clip that shows the feature.

### Containment, learned the hard way

Measured in the session that recorded these clips. All of it cost real incidents.

- **`dbus-run-session`'s bus address is not on its own process.** Reading
  `DBUS_SESSION_BUS_ADDRESS` from `/proc/<dbus-run-session pid>/environ` gives you
  the **parent's** bus — the owner's. The inner shell must publish its own. Getting
  this wrong sends a notification to the owner's real screen.
- **Never `pkill -f` a script name.** `pkill -f qupdate.py` matches the owner's
  daemon. Match on processes whose environment contains `DISPLAY=:9`.
- **`qupdate.py` and `qdrop.py` key their sockets by `$UID`, not by display**
  (`/tmp/qupdate-$UID.sock`). A nested `--toggle` therefore drives the *owner's*
  daemon and pops the window on the owner's screen. Patch the nest copy to key by
  `$DISPLAY`. This is also a real bug in the shipped scripts: two sessions for one
  user fight over a single daemon.
- **pipewire cannot be contained** by a `$HOME` overlay — it lives in the shared
  `XDG_RUNTIME_DIR`. Anything that mutes or changes volume hits the real sink.
  **This is not confined to the audio clip.** The nest runs the same qtile
  config, so the same `volume_control.py` and the same bar widgets are live in
  it, and a session of ordinary capture work — a wizard screenshot, no audio
  row anywhere near it — left the machine unmuted after it started muted, with
  no volume key pressed by anyone. It surfaced only because the sink happened
  to be checked on the way out, which is not a control. `nest.sh` now
  snapshots mute and volume on `up` and restores them on `down`, reporting any
  change. Treat that as a backstop: a clip that touches audio still restores
  its own state inline, because a take that dies halfway should not leave the
  speakers wrong until teardown.
- **Rofi and GTK popups do not follow `theme_mode`.** Set
  `rofi/themes/current-palette.rasi` and generate `current_palette.json`
  separately, or the popups clash with the bar.
- **Do not use `theme-apply` to theme the nest.** It writes GTK/Qt/browser state
  through paths that are symlinks to the owner's real config. Drive the three
  files directly: `theme_mode`, `current-palette.rasi`, `alacritty/themes/current.toml`.

### Two consequences of the nested display, known in advance

- **Anything that goes through D-Bus leaves `:9`.** `notify-send`, `dunstctl`,
  MPRIS and the tray applets all talk to the session bus, so they reach the
  *real* daemons and appear on the owner's screen. That is what rules out the
  clock popup, and what makes any notification-based clip unsafe without a
  private bus.
- **`xrandr` inside Xephyr reports one output named `default` at 0.00 Hz.**
  That is why the display picker cannot be shot there, and why the docs System
  section's display line must be cropped out of `docs-system.gif`.
