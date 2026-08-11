# Requested scope — the full list, so nothing gets lost

Standing constraint, applies to everything below:
**do not touch the qtile config.** Both sessions run in parallel.

---

## 0. Install Hyprland

**Status: DONE.** Hyprland 0.56.2 installed and running; keyd is active,
enabled, and confirmed bound to `AT Translated Set 2 keyboard`. See the
"Runtime verification" section of MIGRATION.md for what first login
proved.

One package is still missing and matters for items 1 and 5:

```
sudo pacman -S inter-font
```

Without it every `Inter` / `Inter Display` family in `hyprlock.conf` —
and every one DESIGN-SPEC.md specifies for the notch — silently resolves
to Noto Sans CJK KR. `fc-match "Inter Medium"` confirms it.

Original install command, for reference:

```
sudo pacman -S hyprland xdg-desktop-portal-hyprland \
    hyprpaper hypridle hyprlock \
    grim slurp wl-clipboard jq \
    brightnessctl playerctl \
    polkit-kde-agent qt5-wayland qt6-wayland \
    keyd
```

`keyd` is in that list deliberately — see the Caps→Alt blocker in
`MIGRATION.md`. Configure it before first boot or ~40 bindings are dead.

---

## The two videos — RESOLVED

I still cannot see video frames. But you were right that the transcripts
were reachable: both were pulled with `yt-dlp` and de-duplicated (the
rolling auto-caption overlap needs word-level trimming, not cue-level).

**4,640 words for the glass video, 5,436 for the notch video, read in full.**
Both creators narrate their design decisions with specific numbers, so the
transcripts turned out to be a better spec than screenshots would have been.

Everything extracted is in **`DESIGN-SPEC.md`** — geometry, timings, damping
ratios, font choices, and the bugs each author hit.

| | Video | Identified as |
|---|---|---|
| 1 | `nKomstQedmE` | "I Replaced My Whole Hyprland Bar With One Notch" |
| 2 | `2ZNGlPW6DM8` | "How to Get Liquid Glass on Hyprland" |

### The finding that changes the plan

**The notch shell in video 1 is not Tide-island, and has no public repo.**

> "This shell is about 7 and 1/2 thousand lines, I think, across 59 files,
> and I wrote every one of them by hand"

It is unreleased, taught only through the author's paid course. That is
exactly why you couldn't find the config. Your instinct — take Tide-island
and restyle it — is therefore the only available route, and it is a sound
one: Tide-island is also Quickshell/QML, so the concepts port even though
the code does not.

What remains genuinely unknown without frames: exact colours inside the
expanded panels, icon set, and the precise flare curve. Everything
structural is now specified.

---

## 1. Notch bar + port my popups into it

**Status: NOT STARTED**

Base: [Tide-island](https://github.com/enhaoswen/Tide-island) — Quickshell
(QML/Qt6), targets Hyprland and niri. The video's shell is unavailable
(see above), so Tide-island is the base and gets restyled to the spec in
`DESIGN-SPEC.md`.

**The restyle target is now fully specified** — no longer blocked:

| | |
|---|---|
| Collapsed shape | 150 × 38 px pill — the entire top surface, no bar at all |
| Floating form | 11 px below top edge, all corners rounded |
| Notch form | flush, top corners square, 14 px concave flare per side |
| Morph | ONE path interpolated in two phases (un-round, then flare) — never two shapes swapping, that "looks cheap instantly" |
| Colour | hardcoded `#000000`, **not** theme-tinted |
| Overshoot | 4 px past screen top, clipped, scaling to 0 in floating form |
| Motion | real spring: 400 ms, damping 0.8 — fades on a separate critically-damped curve |
| Fonts | Inter / Inter Display (stated substitutes for SF Pro), Inter Medium body |
| Resting state | clock + 4-bar EQ only. No workspaces, tray, battery, Wi-Fi |
| Expansion | hover, or click to pin. Media/notifications swap content without expanding |

**Conflict to decide (item 4 vs item 1):** the spec says the notch shape must
stay pure black and ignore the theme, because it is imitating bezel — tint it
and "it stops being a notch and becomes a colored blob." My recommendation:
theme everything *inside* the notch, keep the shell shape black. Your call.

Work:
- Clone to `~/.config/quickshell/`, enable `qs -c tide-island` in
  `autostart.conf` (line is already there, commented)
- Restyle to the table above
- Rebuild the 13 qtile popups as QML pages inside the notch:

  | Popup | qtile bindings | Source |
  |---|---|---|
  | AudioPopup | 25 | `qtile/popups/AudioPopup.py` |
  | DisplayPopup | 28 | `qtile/popups/DisplayPopup.py` |
  | WifiPopup + WifiQR | 14 | `qtile/popups/WifiPopup.py`, `WifiQR.py` |
  | BluetoothPopup | 12 | `qtile/popups/BluetoothPopup.py` |
  | WallpaperPopup | 9 | `qtile/popups/WallpaperPopup.py` |
  | Cheatsheets (Qtile/Vim/Fish) | 16 | `qtile/popups/*Cheatsheet*.py` |
  | UpdatesPopup | — | `qtile/popups/UpdatesPopup.py` |

  Total: 104 bindings restored, plus Media-Mode's 17 = **121**.
- Keep the original keymaps exactly (chord entry keys are reserved and
  commented in `binds.conf`)

Effort: weeks. This is the long pole of the whole migration.

---

## 2. Liquid glass

**Status: CONFIG WRITTEN — `hyprglass.conf` + `hyprglass.lua`, awaiting install**

Written from the video's own settings and warnings. Already handled:

- **Apple preset** as the base, per the author's explicit recommendation
  ("just run the Apple preset, whitelist your bar, tag off MPV, and you're
  done"). The plugin defaults are already near Apple's look.
- **The `new_optimizations` bug is pre-fixed** — `looks.conf` had it `true`,
  which is the precise cause of "glass vanishes when you release a dragged
  window". Now `false`, with the reason in a comment.
- **The empty-whitelist trap** documented at the config site: an exclude-only
  config leaves the whitelist empty, and an empty whitelist glasses *every*
  layer on the system.
- **`mask_threshold` set to 0.05, not the 0.001 default**, so widget drop
  shadows don't grow glass rectangles around their shadow boxes.
- **`layers_enabled = false`** for now — the author tried 0.3 and 0.7 on his
  own Quickshell surfaces and ended up excluding them entirely.
- Per-window tags: glass off for mpv and fullscreen, light theme for
  browsers, high-contrast for kitty.

Still needs you: `hyprctl version` before install. Current release targets
**Hyprland 0.56**; on 0.55 take the **v0.6.4** release instead.

The mechanism behind video 2 is the **hyprglass** plugin
(<https://github.com/hyprnux/hyprglass>) — not a config setting. It models
windows as convex glass slabs: frosted multi-pass blur, edge refraction
via UV displacement, chromatic aberration, centre dome lens magnification,
Fresnel edge glow, specular highlights, adaptive tone mapping.

```
hyprpm add https://github.com/hyprnux/hyprglass
hyprpm enable hyprglass
```

Three things to know before committing:

1. **It cannot run alongside Hyprland's built-in blur on the same windows.**
   `looks.conf` currently enables `decoration:blur`. That has to come off
   for any window hyprglass handles.
2. **It is ABI-locked to your Hyprland version.** The plugin compares its
   build-time signature against the running compositor; a Hyprland update
   can break it until rebuilt. `hyprpm update` after every Hyprland upgrade.
3. **Layer-surface glass (bars, docks) hooks private Hyprland internals**
   and is off by default. Applying glass to the notch bar is exactly that
   case — expect it to be the fragile part.

Alternatives if the plugin proves too brittle: `hyprpm` fork
[liquid-glass-plugin-hyprpm](https://github.com/purple-lines/liquid-glass-plugin-hyprpm),
or approximating with native blur + opacity, which gets frosting but not
refraction or the lens effect.

---

## 3. All my scripts, same keymaps, same behaviour

**Status: PARTIALLY DONE**

Already ported (they never touched the WM): `brightness_control.py`,
`volume_control.py`, `mpv_manager.py`, `prayer_next.sh`, `fx_rates.sh`,
`sum_app.py`, `screenshot-area.sh` (→ grim+slurp), and the whole
Rofi-Mode launcher set — 20 dmscripts/rofi tools, transferred verbatim.

Still to do:
- **App togglers (7)** — `scripts/toggle_apps.py` imports `libqtile`
  directly. Rewrite as one generic script: `hyprctl clients -j` lookup,
  focus if present, spawn if not. Same shape as the `scratchpad.sh`
  already written.
- **`sum.md` toggle (1)** — same rewrite.
- **`qdrop.py` / `qdrop_watch.py`** — superseded by special workspaces.

On the popup-vs-menu question you raised: **rofi already works on Wayland**
under XWayland, and every one of your `dm-*` scripts runs unchanged. So
there is no forced rewrite. The Wayland-native equivalents are **wofi**
(closest to rofi) or **fuzzel** (faster, actively maintained) — worth
switching only if XWayland rofi misbehaves.

Preference: rebuild the *interactive* popups (audio, display, wifi,
bluetooth, wallpaper) as Quickshell pages per item 1, and leave the
*launcher* scripts on rofi. Launchers are a list-and-pick problem rofi
already solves well; the popups are stateful controls that genuinely
benefit from being in the notch.

---

## 4. System-wide theming

**Status: DONE and verified live.**

`gen_hypr_colors()` is in `theme-apply` (line ~398) and wired into
`gen_all_theme_css()`. Verified in a running session: `theme-apply
doomone` regenerated `~/.config/hypr/colors.conf` with the doomone
palette and the live border colour became `ff98be65` (doomone green)
without a restart. `hyprctl configerrors` stayed clean.

Both guards work as designed — it returns early if `~/.config/hypr` is
absent, and only shells out to `hyprctl reload` when
`HYPRLAND_INSTANCE_SIGNATURE` is set, so running it from the qtile/X11
session is unaffected.

Note: `~/.cache/qtile/theme_mode` said `doomone` while `colors.conf`
still held catppuccin values — the two had drifted. Re-applying doomone
reconciled them. The shared state file does keep both sessions in sync,
but only for themes applied *after* the Hyprland target existed.

Remaining under this item: a Quickshell/QML target, which cannot be
written until item 1 exists.

Original notes below.

**Was: NOT STARTED — but far cheaper than expected**

`~/.dotfiles/.config/AtiScriptsV1/theme-apply` is 1,660 lines and already
does the hard part: **20+ named themes** (doomone, dracula, gruvbox, nord,
tokyonight, catppuccin, monokai, everforest, rose-pine, kanagawa,
oxocarbon, cyberpunk-neon, synthwave, matrix, mono-dark, mono-light,
nightowl, onedark, palenight, github-dark) plus a `wal` mode driven by
pywal, fanned out to kitty, alacritty, rofi, dunst, eww, brave,
qutebrowser, btop, GTK, Qt, and glow.

**Almost all of it is WM-independent.** It is a bash script writing config
files. The only parts that need touching:

- Add a Hyprland target to `gen_all_theme_css()` that writes
  `~/.cache/wal/colors-hyprland.conf` (border colours, shadow tint) and
  calls `hyprctl reload`. `looks.conf` already has the `source =` line
  for it, commented.
- Add a Quickshell/QML target once the notch bar exists.
- Replace the `qtile cmd-obj` calls with `hyprctl` equivalents — guarded
  on which session is live, so the same script keeps serving qtile.
- `theme-toggle` is rofi-based and works as-is.

The `STATE_FILE` at `~/.cache/qtile/theme_mode` is shared, so both
sessions stay in sync on the current theme for free.

Effort: one day, not one week. This is the highest value-per-hour item
on the list.

---

## 5. Circular theme-change animation

**Status: NOT STARTED**

Source: [Aylur/dotfiles](https://github.com/Aylur/dotfiles) → the shell is
**[Marble Shell](https://github.com/Aylur/marble-shell)**, built on **AGS**
(Aylur's GTK Shell), GTK4 + layer shell, targeting Hyprland.

**Architectural conflict to be aware of:** Marble Shell is AGS/GTK4/TypeScript;
Tide-island is Quickshell/QML. There is no copy-paste path between them.
The animation has to be reimplemented, not ported.

That is fine, because the technique is standard: a full-screen layer-shell
overlay, screenshot of the pre-change desktop, then a circular mask
expanding from the centre to reveal the newly-themed desktop underneath.
In QML that is an `OpacityMask` with an animated radial gradient, or a
`ShaderEffect` — both well-trodden.

**The notch video hands us the implementation details for free** — its lock
screen does exactly this capture-freeze-blur trick, and the author names
every trap:

- **JPEG quality 85, never PNG.** PNG encoding at 2560×1440 plus a second
  monitor cost him ~850 ms. The image gets blurred four frames later, so
  every JPEG artifact is annihilated before your eye reaches it. "Lossless
  is worthless when the very thing you do is destroy the detail on purpose."
- **Safety timer.** If the screenshot tool hangs or is missing, proceed
  anyway after 700 ms. Fail closed, never wait on a screenshot.
- **One boolean drives both directions**, so the animation is symmetric —
  two code paths gave him a black flash in and a lingering frame out.
- **90 ms delay before animating**, so the heavy first frame (decode +
  blur shader compile) finishes before anything needs to move smoothly.
- **Hidden elements sit at barely-above-zero opacity, not zero**, because Qt
  skips buffer allocation on fully transparent items — then they warm up
  during that 90 ms. Exception: go to true zero on the way out, or you catch
  a blurred ghost frame.

Sequence:
1. `grim` captures the current screen (JPEG q85)
2. Overlay layer displays the capture, fullscreen, above everything
3. `theme-apply` runs underneath (item 4)
4. Circular mask animates outward from centre; the old screenshot is what
   gets erased, revealing the retheme
5. Overlay destroys itself

Depends on: item 1 (needs the Quickshell shell to live in) and item 4
(needs the retheme to trigger it around).

---

## Dependency order

```
0. Install + keyd          ← nothing works before this
      │
      ├── 4. Theming (Hyprland target)      ← cheapest, do early
      │
      └── 1. Tide-island notch
             ├── 1b. Popups as QML pages    ← the long pole, 121 bindings
             ├── 5. Theme animation          ← needs 1 and 4
             └── 2. hyprglass                ← independent, but conflicts
                                                with blur in looks.conf
3. Scripts — partly done, rest is independent of all the above
```

---

## Open questions I need you to answer

1. **Screenshots of both videos**, or a description of the notch's shape,
   what it shows idle vs expanded, and how it animates. I cannot see them.
2. Is video 1 actually Tide-island, or a different shell? If different and
   you can find the repo, that changes the base.
3. hyprglass on **windows only**, or on the notch bar too? Bar glass is the
   fragile path (private Hyprland internals).
4. Keep rofi for launchers, or go all-Quickshell? My recommendation is keep
   rofi — see item 3.
