# Design spec, extracted from the two video transcripts

I cannot watch video. What follows is transcribed from the creators' own
spoken descriptions (yt-dlp captions, overlap-trimmed) — 4,640 words for
the glass video, 5,436 for the notch video. Every number below is one they
said out loud. Where they didn't say something, it is marked UNKNOWN rather
than guessed.

---

# Video 1 — the notch

`nKomstQedmE` · "I Replaced My Whole Hyprland Bar With One Notch"

## Critical: this is not Tide-island, and there is no repo

> "This shell is about 7 and 1/2 thousand lines, I think, across 59 files,
> and I wrote every one of them by hand"

It is his own Quickshell shell, unreleased, taught only through his paid
program. **There is nothing to clone.** That is why you couldn't find it.

So the plan stands as you framed it: **use Tide-island as the base and
restyle it to this spec.** Tide-island is also Quickshell/QML, so the
concepts transfer directly even though the code does not.

## Geometry

| Property | Value |
|---|---|
| Collapsed size | **150 × 38 px** — "that's the whole thing" |
| Floating island | **11 px** below top edge, all four corners rounded |
| Notch mode | flush to top edge, **top corners square** |
| Notch flare | **14 px concave flare each side**, blooming where it meets the screen top |
| Top overshoot | **4 px** past screen top, clipped (see shadow trap) |

**There is no bar.** Not a thin bar — none.

> "There is no status bar in this setup... This black shape, pill-shaped
> thing is basically the entire top surface of my desktop."

## The morph — one shape, not two

> "This is one shape morphing and not two shapes swapping. A single path
> interpolated by one value."

He tried the obvious way first — a rounded rect and a teardrop, flipped with
`visible` — and it popped, because one shape vanished while the other
appeared mid-animation. "It looked cheap instantly."

The fix is **two-phase interpolation of a single outline**, because an
outline cannot be both round-topped and flared at once:

1. First half: un-round the top corners
2. Second half: grow the flares

## Colour — hardcoded black, deliberately

> "Actual triple zero black written into the code, immune to whatever the
> wallpaper does. And I didn't choose that, the notch chose it."

The reasoning: a notch is pretending to be **bezel**, and bezel is black.
Tint it with a theme accent and "the illusion basically dies instantly. It
stops being a notch and becomes a colored blob."

**This propagated:** because island and notch are the same shape, the
floating island had to go black too.

> **Conflict with your item 4.** You want theming to drive the whole system.
> This spec says the notch specifically must NOT follow the theme. My
> recommendation: theme everything *inside* the notch (text, cards, accents)
> and keep the shell shape `#000000`. Flag if you disagree — it's your call,
> but the illusion is the entire point of the design.

### RESOLVED — the user overruled this; the shape follows the theme

**"the color of the bg if the islend should also follow the colortheme".**
It was flagged as their call and they have made it. The section above is
kept as written because the *reasoning* is still worth understanding — the
rule is simply no longer what the shell does.

The implementation answers the spec's real concern rather than ignoring it.
The fill is the palette's **background** slot, never its accent, and all 22
palettes have a near-black there (doomone `#282c34`, gruvbox `#282828`,
nord `#2e3440`). That is then blended 35% toward black. The shape stays
unmistakably dark — bezel, not a coloured blob — while its hue is readable
beside the wallpaper:

| theme | palette bg | island fill |
|---|---|---|
| doomone | `#282c34` | `#1a1d22` |
| gruvbox | `#282828` | `#1a1a1a` |
| nord | `#2e3440` | `#1e222a` |

Sampled out of the framebuffer while cycling, not asserted. **The first
attempt darkened by 72% and was worthless**: every palette's background is
already near-black, so taking three quarters off put doomone at `#0b0c0f`
and gruvbox at `#0b0b0b` — four points apart on a single channel. The theme
was genuinely being followed and no eye could tell. If this ever looks
plain black again, that is the number to check.

Mechanism: `theme-apply`'s `gen_island_colors()` writes
`~/.cache/tide-island/colors.json` and
`tide-island-fork/qml/common/IslandTheme.qml` watches it. See
REQUIREMENTS.md item 4.

## The 4-pixel shadow trap

When first made flush, a 1–2 px line of desktop showed above it — surviving
theme changes, so not a colour bug. It was the **drop shadow's own padding**
insetting the painted shape inside its layer.

Fix: the shape deliberately overshoots the screen top by 4 px and lets the
excess clip. The overshoot **scales to zero** as it morphs back to the
floating island, because the island needs its 11 px gap back.

## Resting state — subtraction as a feature

Shows exactly two things: **the time**, and **a 4-bar EQ visualiser** that
animates only while music actually plays.

Deliberately deleted: workspaces, tray, **battery, Wi-Fi**.

> "I was checking my battery about once a day... and looking at that pill
> roughly 400 times a day. It earned permanent screen real estate by being
> occasionally relevant. That's a terrible trade."

## Expansion

- Expands **on hover**, or **on click to pin open**
- **Media and notifications do not expand it.** They arrive as separate
  states that swap the content while the shape stays put — "different
  mechanism entirely"
- The **clock slides**: starts centred in the collapsed notch, travels right
  as it opens. Took him three attempts

## States of the one shape

This is the list that matters for your item 1 — every one of these is a
state of the same island, not a separate window:

launcher · control center · calendar · power menu · Polkit password prompt ·
**wallpaper picker** · **theme switcher**

Your wallpaper and theme popups belong here, exactly as you asked.

## Media card

88 px album art · bold two-line title · album and artist underneath ·
transport controls (back, play/pause, forward) · date carousel top-right
(inspired by the Notcho Mac app)

## Motion — a real spring, not easing presets

> "None of this runs on easing presets. There's no ease out quad, no in out
> cubic. The shell generates a real spring at runtime."

A damped harmonic oscillator, step response converted to a curve Qt can run:

| Parameter | Value |
|---|---|
| Duration | **400 ms** |
| Damping ratio | **0.8** — under 1, so it overshoots slightly and settles |

> "That tiny overshoot is the whole difference between something that moves
> and something that feels like it has mass."

**Fades use a different, critically damped curve**, because opacity is
clamped 0–1: an overshooting fade tries to exceed fully opaque, gets
clipped, and reads as an abrupt cut. Same system, two curves — "position can
overshoot and opacity physically can't."

## Typography

- His: **SF Pro Text** (body), **SF Pro Display** (display)
- Stated substitutes: **Inter** (body) / **Inter Display** (display), with
  **Inter Medium** for body weight to match SF Pro
- Turn hinting down to avoid colour fringing

## Screen corners — 69 lines

Rounded display corners, on the **overlay layer**, rendering **above
fullscreen windows** ("a real bezel doesn't disappear because you open the
video").

Two traps he names explicitly:

1. **Input region must be explicitly empty**, or a transparent fullscreen
   surface swallows every desktop click. "If you build anything full screen
   and decorative, that's a trap and it will confuse you for an hour."
2. They animate away to nothing in **game mode** — which disables every
   effect, shell and windows, no shadows no blur

## Lock screen

Not a wallpaper — **your actual desktop at the instant of locking**:
captured, frozen, blurred, dimmed ~20%, soft gradient at top so the clock
stays readable. macOS layout: date/day top, clock, user + avatar, "press any
key", password box.

**The password field is hidden until you type.** "90% of the time you're
glancing at it to check the clock... why put an input box in front of
someone who isn't going to type into it?"

Five hard-won implementation details:

| Problem | Fix |
|---|---|
| Lock screen appeared before its own background — 850 ms gap | **JPEG quality 85, not PNG.** "Lossless is worthless when the very thing you do is destroy the detail on purpose" |
| Screenshot tool could hang | **700 ms safety timer** — lock engages anyway. Fails closed |
| Black flash in, lingering frame out | **Single boolean** drives both directions; locks the way it unlocks in reverse |
| Locking stuttered, unlocking was smooth | **90 ms delay** before animation, so the heavy first frame (decode + blur shader compile) finishes first |
| Qt skips work on fully transparent items | Hidden elements sit at **barely above zero** opacity so buffers get built — **except on unlock**, which goes to true zero so the final frame is pixel-identical |

### Security warning — read this one

> "I pointed it at one of these standard PAM configurations... Then I tested
> it properly and it accepted any password, any string at all, complete
> gibberish. Every one of them unlocked my machine instantly."

**If we build a lock screen, it gets tested with a deliberately wrong
password before it is ever trusted.** Non-negotiable.

---

# Video 2 — liquid glass

`2ZNGlPW6DM8` · "How to Get Liquid Glass on Hyprland"

Confirms the plugin identification: **hyprglass**, `github.com/hyprnux/hyprglass`.

## The mental model

The plugin treats a window as a **thick convex slab of glass**, not a surface.

| Region | Behaviour | Settings |
|---|---|---|
| Middle | flat — light passes nearly straight through | `blur_strength`, `lens_distortion` |
| Edges | curved — light bends outward, dragging in content from beyond the window | `refraction_strength` |
| Rim | R/G/B bend by different amounts, blue most → colour fringing | `chromatic_aberration` |
| Surface | glow where light catches the curve, top-biased highlight, bottom rim shadow | `fresnel_strength`, specular |

`edge_thickness` controls where middle becomes edge. "Middle equals blur,
edges equal glass."

## Install and the version trap

```
hyprpm add https://github.com/hyprnux/hyprglass
hyprpm enable hyprglass
```

Then **`hyprctl version`**. Current release targets **Hyprland 0.56**; on
0.55, either update or take the **v0.6.4** release which targets 0.55.4.

> "A mismatch is the number one reason people bounce off this plugin in the
> first 90 seconds."

## Two things it does automatically

1. **Auto-enables Hyprland shadows** — it hooks the shadow decoration to
   render. Your shadow values may all be zero; it just needs the decoration
   present.
2. **Sets `noblur` on every glass window**, because Hyprland's cached blur is
   captured before plugin decorations draw.

## Three bugs he names, so we skip them

**1. Glass vanishes when you release a dragged window.**
Not broken — `blur:new_optimizations` caching a frame without the glass. The
plugin handles it via automatic `noblur`. If managing blur rules yourself:
set `manage_window_blur = 0` and add your own noblur rule.

> **This applies to us.** `looks.conf` had `new_optimizations = true`. Fixed.

**2. The empty-whitelist trap — "the one that will waste your evening".**
Each `hg.layer(...)` call *whitelists* that namespace. If your only call is
an exclude, the whitelist stays empty — and an empty whitelist means
**every layer on your system gets glassed**.

> "I checked this in the source. Exclusions are evaluated first, then an
> empty filter returns true for everything."

**3. Mystery rectangles around widgets.**
The effect masks to visible content by alpha, and **shadows count as visible
content**. Default `mask_threshold` is 0.001 — basically anything — so a
widget with a drop shadow gets a glass rectangle around its shadow box.

Fix: raise `mask_threshold` above your shadow's alpha. Start at 0.05 and
raise until the rectangle dies. He tried 0.3, then 0.7, and for Quickshell
ended up excluding it entirely.

## The aesthetic argument: restraint

> "Apple's material is desaturated. It's low contrast and it has gentle
> refraction... Everyone's first instinct is to crank every slider and the
> result looks like a car windshield in the rain."

**The plugin defaults are already calibrated near Apple's look** — "most of
you are just one install and one line away from the thing in the title."

His own `glass` preset vs the `apple` preset, in his numbers:

| Setting | Apple | His glass |
|---|---|---|
| `chromatic_aberration` | 0.3 | 0.8 |
| `lens_distortion` | — | 0.9 ("almost maximum dome") |
| `contrast` | below 1.0 | 1.7 |
| `vibrancy` | 0.12 | 0.8 |

## Adaptive — what makes it work on any wallpaper

- `adaptive_dim` pulls down bright areas behind the glass, so **dark themes
  stay readable**
- `adaptive_boost` lifts dark areas, so **light themes don't go muddy**

The Apple preset carries **separate `dark` and `light` tables**.

## Config format

Lua is preferred (Hyprland 0.55+); the legacy `.conf` form is already marked
deprecated and he expects it removed within a release or two. He keeps
hyprglass settings in `modules/plugins.lua`, required from `hyprland.lua`.

Tint colour format: **`0xRRGGBBAA`** — last two digits are alpha.

> He notes his own tint is pulled from his colours file, so **the glass tint
> is derived from his wallpaper**. That is exactly what your `theme-apply`
> already generates — see REQUIREMENTS.md item 4.

## Per-window control

```
windowrule: match class = mpv       → tag +hyprglass_disabled
            fullscreen = true       → tag +hyprglass_disabled
            match class = firefox   → tag hyprglass_theme_light
            match class = kitty     → tag hyprglass_preset_high_contrast
```

Live testing without reload:
`hyprctl dispatch tagwindow +hyprglass_preset_subtle`

## His recommendation for most people

> "If you just want it to look good and work, just run the Apple preset. You
> can whitelist your bar, tag off MPV, and you're done. That's a complete,
> beautiful result, and there is zero shame in stopping there."

That is the configuration written into `hyprglass.lua`.
