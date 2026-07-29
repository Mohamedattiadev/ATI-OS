# plan_ui_ux_qtile.md

Living document. Add / prune as ideas ship or drop.

---

## Topbar

- [ ] Weather chip (async fetch wttr.in, 10-min cache, click → forecast popup)
- [ ] Now-playing chip (playerctl → mpv/spotify title, click → dm-music)
- [ ] Reduce bar `margin=[5,10,5,10]` → `[3,8,3,8]` (tighter)
- [ ] Systray hide behind WidgetBox by default (icons eat width)
- [ ] Bar dynamic opacity: `opacity=0.9` when workspace has focused window, `0.6` when empty
- [ ] Pill hover animation: 150ms color pulse via qtile_extras `BorderDecoration` on `mouse_over`
- [ ] TaskList: background span per markup state (readable on any bg)
- [ ] CurrentLayout: shrink icon `scale=0.5`, drop right-click popup

## Wallpaper / theming

- [ ] `pywal` — wallpaper drives palette. Regenerate qtile `colors.py`, kitty, rofi, dunst on `dm-setbg`
- [ ] Wallpaper transitions via `oguri` (fork) or picom animate
- [ ] Random wallpaper on session start (from `~/Pictures/Wallpapers`)

## Dunst

- [x] Better contrast + shadow + rounded corners
- [ ] Notification history rofi: `dunstctl history-pop` bound to `Win+n`
- [ ] Per-app icon override (Telegram avatar, Anki cards, Battery percent)
- [ ] Do-not-disturb keybind + status indicator in bar

## Rofi

- [ ] New base rasi: 3-column layout for launcher, icons on left
- [ ] `rofi-emoji` — `Win+.` emoji picker
- [ ] `rofi-copyq` — clipboard history
- [ ] `rofi-bluetooth` script — pair/unpair menu
- [ ] `rofi-wifi-menu` — nmcli wrapper
- [ ] Consistent theme across all rofi scripts (currently drift)

## Terminal / prompt

- [ ] Kitty `background_opacity 0.85`
- [ ] Kitty ligatures verified (fira code)
- [ ] Fish prompt: starship (already?) — add rust/node/python version chips
- [ ] `zoxide` verify + fish widget

## Explainers (moved from Q&A)

### Session state persistence
Save window→group mapping + focused window on logout, restore on login. qtile
has `qtile.core.State` internal API used by `restart` (that's why restart keeps
windows in place). For **cross-logout** persistence, add hook:
`hook.subscribe.shutdown` → dump JSON of every window's `wid`, `wm_class`,
`group.name` to `~/.cache/qtile/session.json`. On `startup_complete` read it
back and move new windows matching class into recorded group. Not perfect
(pids change) but recovers 80% of layout.

### User services (systemctl --user)
Replace `& disown` in autostart.sh with per-daemon systemd unit under
`~/.config/systemd/user/`. Benefits: auto-restart on crash (`Restart=on-failure`),
proper dependency order (`After=graphical-session.target`), one-shot restart via
`systemctl --user restart dunst`, journalctl integration. Ship units for:
`dunst`, `picom`, `eww`, `syncthing`, `copyq`, `warpd`. Currently everything is
background bash job — silent death, no restart.

### Voice command
Bound to `Win+Shift+V` → `voice_dictate` script. First press = start recording
(sox). Second press = stop + transcribe via whisper.cpp (small.en, ~460MB) +
type at cursor with xdotool. Requires model at `~/.local/share/whisper/ggml-small.en.bin`
(install.sh downloads on setup). Deps: `whisper.cpp-git` (AUR), `sox`, `xdotool` — all in dcli.

---

## Session flow

- [ ] Boot splash (`plymouth` — optional, dev only)
- [ ] Login greeter alt to TTY: `ly` (minimal, TUI)
- [ ] Lock screen art via `betterlockscreen` (installed) + blur wallpaper
- [ ] Session save on logout: qtile hooks + JSON of window→group

## Notifications for pillars

- [ ] Battery: notify at 20% + 10% + 5% (currently silent)
- [ ] Updates: notify count on chord open
- [ ] Volume/brightness: on-screen bar via `dunstify` progress hint

## Popups

- [ ] Unified popup style (borrow qtile_extras `PopupRelativeLayout`)
- [ ] Wallpaper picker + Bluetooth + Wifi + Audio popups share look
- [ ] Fade-in on open (picom `fading = true` already; extend to popup class)

## Cheatsheet

- [ ] Auto-generate from `keys.py` (after config split) — no more manual sync
- [ ] Categorize by mode chord
- [ ] Search filter (rofi-style)

## Fonts

- [ ] Verify `fc-match "Arabic"` → Amiri
- [ ] Verify `fc-match "CJK"` → Noto
- [ ] Add `noto-color-emoji` as fallback for pango

## Animation (blocked on picom fork)

- [ ] Install `picom-ftlabs-git` (needs meson fix first)
- [ ] Wire animation rules for: window open, close, workspace switch, floating drag
- [ ] Fade-in bar on qtile start

## Priorities

**Ship this cycle:**
1. TaskList background contrast fix
2. Dunst restyle
3. CurrentLayout shrink
4. Rofi rasi rewrite
5. `rofi-emoji`, `rofi-copyq` bind

**Next cycle:**
1. Weather + now-playing chips
2. pywal integration
3. Session save/restore
4. Auto-generated cheatsheet

**Blocked:**
1. Animations (picom fork build)
