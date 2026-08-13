# Prompt — next session

Continue the Hyprland / Tide-Island work in `~/.dotfiles` (branch `test`).

**Read first:** `.config/hypr/upgread_UI_UX.md`. The two "Audit — 2026-08-13"
sections at the end are the measured state; the numbered findings above them
(P0-1 … P3-10) are the ORIGINAL plan and several are now stale — the audits
say which. Where the plan and an audit disagree, the audit measured it.

There are two jobs. **Job B is the one that matters most to me.**

---

# JOB A — finish the plan

In this order. Each is small enough to prove.

1. **Theme picker search.** Phase 7. The wallpaper picker got type-to-jump
   this session; the theme picker (22 items) still has none. It is a
   **GridView, not a PathView**, and its model is not carrying thumbnail
   cache state — so unlike the wallpaper picker a REAL FILTER is correct
   here. Do not copy the carousel's approach; the reason it was type-to-jump
   is written in `WallpaperPickerLayer.qml` and does not apply.

2. **`/` for the font picker in the settings app.** `island-settings.py`
   has `font` rows (textFontFamily, timeFontFamily, heroFontFamily,
   iconFontFamily) and 716 families are installed. The GTK app has a
   `Gtk.FontDialog` already; the ISLAND panel still cannot offer these at
   all (`panel: false`). If the in-island panel should ever have them, it
   needs the filtered-list component, which is the same component the theme
   picker wants.

3. **P2-7 — the shared components.** This is the prerequisite for Job B, so
   read Job B before starting it. Measured, still true:
   the key-hint footer exists on **9 panels** under **two** property names
   (`hintHeight` on 5, `footerHeight` on 4) at **four** heights
   (`Metrics.pad(26)`, `px(22)`, `px(20)`, raw `24`). Extract `PanelChrome`
   (header + body + footer), `PanelRow`, `PanelTabs`, `KeyHint`.

4. **Motion.js — re-audit the 17 "deliberate raw easings"** listed at the
   bottom of that file. They were justified once; confirm each is still
   true rather than inheriting the list.

5. **Lock screen** (Phase 6.2): user avatar, username, soft top gradient
   behind the clock. Small, and it is the one surface a stranger sees.

---

# JOB B — restyle every popup. This is the main request.

> "I want to upgrade the style and the UI/UX of all the island things — a
> really different upgrade style in all the popups, to be proper and good."

## Read this before writing any QML

**Do not restyle 20 panels one at a time.** The reason is measured, not
aesthetic: the 9 fork panels each rebuilt their own header, their own
selected-row treatment and their own footer, which is why one footer has
two names and four heights. Restyling them individually means making the
same decision 9 times and getting 9 answers — which is exactly how the
current inconsistency was created.

**So Job A item 3 and Job B are the same piece of work.** Extracting
`PanelChrome` / `PanelRow` / `PanelTabs` / `KeyHint` is the moment to change
the look, because after it the style lives in four files instead of twenty.
Do the extraction AS the restyle, not before it.

## What is already in place, so do not rebuild it

- **Colour is done.** `IslandTheme.qml` is a singleton publishing ~45 derived
  roles, all driven by `theme-apply`, with WCAG-solved text contrast
  (5.45:1 worst case across 21 palettes). Use the roles. Do not add hex.
- **`Metrics.js` now names the ramp** — `TYPE` (caption 9 / small 10 /
  body 11 / reading 12 / strong 13 / title 15), `DISPLAY` (18/24/29) and
  `RADIUS` (hairline 1 / tight 4 / card 8 / panel 16). They are set to the
  values already in use, so adopting one is a **no-op by construction**.
  **They are not applied anywhere yet — Job B is what applies them.**
- **`Motion.js`** is a generated spring (zeta 0.8 geometry, 1.0 opacity).
  Use `Motion.spring()` / `Motion.fade()`, never an easing preset.
- **The interaction model is settled**: *hover moves the cursor.* One
  selection indicator driven by both keyboard and pointer. Do not add a
  separate hover highlight beside a selection — that is why `containsMouse`
  appears zero times and it is deliberate.

## Two numbers that will save you a wrong assumption

- **`FONT_SCALE` is 1.0, so `Metrics.font(n)` is the identity above 9.**
  Changing type sizes means changing the SOURCE numbers or the `TYPE` table.
  Wrapping something in `font()` changes nothing.
- **18 distinct corner radii are in use** and `RADIUS` proposes 4. Radius is
  the single highest-leverage visual change in the shell — but nested shapes
  need concentric radii (outer = inner + padding), so this cannot be a
  find-and-replace.

## How to decide the style, rather than guessing at mine

I could not resolve "really different" from the request, and neither will
you. **Do not restyle everything and then ask.** Instead:

1. Pick **one** panel that exercises everything — the control centre (header,
   tabs, rows, sliders, toggles, footer) is the right one.
2. Build **two or three genuinely different directions** on it. Not three
   shades of the same thing — e.g. (a) denser and flatter with hairline
   dividers, (b) more spacious with raised cards and stronger radius, (c)
   high-contrast with heavier type and tighter chrome.
3. **Capture each** and show them side by side. Ask which, then roll the
   winner out through the shared components.

That costs one panel's work to avoid twenty panels' rework.

## Things the user has already said about style

From this session and the plan's Part 3 — these are settled, do not "fix" them:

- The island fill follows the theme (explicit override of `DESIGN-SPEC.md`).
- `islandHeight` 35, `islandWidth` 135 — user values, not the spec's.
- Resting state is clock + workspace digit + app pucks, not the spec's EQ.
- Notification urgency colours the ICON. A coloured edge down the capsule was
  built, shipped once, and **rejected on sight** — it adds a second element
  to a shape whose whole argument is that it is one shape.
- The notification centre's type ramp was just fixed to 15 heading / 12 title
  / 11 body, from config. Do not regress it to hardcoded sizes.

---

# THE RULES — every one of these was paid for

- **A config that reloads cleanly is not a config that works.** Read
  `$XDG_RUNTIME_DIR/quickshell/by-id/<id>/log.log`. A failed reload keeps the
  LAST GOOD config running, so a normal-looking desktop proves nothing.
- **`.pragma library` JS is cached.** Editing `Metrics.js` or `Motion.js` and
  reloading does nothing. **Restart the island.**
- **A file that has never been instantiated is not being watched.** Editing a
  panel you have not opened since the last restart will not trigger a reload,
  and you will test the old code. Open the panel, or restart.
- **Never synthesise keystrokes into a settings panel.** Every press that
  lands writes real config. Test schemas over `island-settings.py`. Other
  panels are fine — the wallpaper picker and the overview were driven with
  `wtype` this session, safely, because navigation there has no side effects.
- **Difference two frames; do not just count changed pixels.** Every real
  finding this session was invisible in a magnitude curve and obvious in a
  diff.
- **The capture region must contain nothing but the thing under test**, and
  the console must be quiet before sampling. A ~790 ms "settle" was measured
  three times before it turned out to be the terminal behind the island
  repainting. A measurement of the wrong region is as wrong as a screenshot
  and comes with a number attached, which makes it worse.
- **Back up `~/.config/tide-island/userconfig.json` before any test that
  writes, and diff it afterwards.** It has been byte-identical at the end of
  every session so far. Keep that true.

---

# OPEN, UNSOLVED — do not re-derive these

- **The ~800 ms panel settle.** Control centre open takes 767–807 ms to
  settle, cold or warm. **Not** `morphDurationFor` (760 vs 520 measured
  identical), **not** the slider intro gate, **not** a cold loader. The
  visible symptom: between +560 ms and +1080 ms the entire content block
  below the clock shifts **~17 px vertically**, every open; the clock and
  battery row do not move. Cause unknown. This is the best remaining lead on
  "the popups feel laggy".
- **The theme change's 1.77 s frozen screen.** The island is already correct
  (it gates on `THEME_APPLY_VISIBLE_DONE`, not on process exit). The
  remaining win is that `theme-apply` spends ~0.24 s restarting **dunst**,
  which is not running under Hyprland at all — the island serves the
  notification bus and `island.sh` pkills dunst. But `theme-apply` is
  `/usr/local/bin` from AtiScriptsV1 and is **shared with the qtile session**
  where dunst is real, so it needs a per-session guard proven on both.

---

# DECISIONS I NEED FROM YOU (ask, do not assume)

1. **Screen corners (P1-6)?** Specified in `DESIGN-SPEC.md`, would complete
   the bezel argument, and the risky part (empty input region) is already
   solved in `RingOsdWindow`. But they are permanent furniture over every
   fullscreen video.
2. **Should `DisplayPanel` join the `Metrics` scale?** It deliberately opts
   out and documents why, and it currently looks correct. Converting means
   every literal in the file, and at `SCALE 0.92` it shrinks the panel ~8%.
3. **Which style direction**, once the two or three mockups exist.
