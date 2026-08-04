# Explainer video — concept and script

**Status: approved 2026-08-05 and built.** Spine "Nothing flashes", silent
captions, ~2:00, closing card stays. Rendered to `video/out/ati-os.mp4`.
The written agreement this document existed to obtain is the section at the
bottom, *Decisions taken*.

Remotion is at `~/Attia-Pro/Projects/Asec/asec-more` (reuse, do not reinstall).
`~/.dotfiles/video/` holds v1 — the rejected attempt — plus already-transcoded
h264 clips in `video/public/` that are reusable as source material.

---

## Why v1 read as "too AI generated"

I read the v1 source rather than guessing. Four concrete causes, all fixable:

1. **It is a feature list, not a film.** Ten scenes, near-equal durations
   (150/250/330/285/210/210/210/225/390/195 frames), each a card. Nothing is at
   stake in scene 2 that resolves in scene 8. That even-weight shape is the
   single strongest tell.
2. **The copy is product-marketing second person.** "Drop things here, use them
   later." "Updates and installs, without a terminal." Nobody in `README.md`
   talks like that. The README's voice is flat, specific and slightly
   adversarial — *"Verified end to end, not asserted"*, *"a second untested boot
   path is worse than no second path"*. The video threw that voice away and
   replaced it with the generic one.
3. **The software never gets the screen.** Every clip sits inside a
   kicker/title/body/keys frame, shrunk, with text competing for attention. The
   thing being demonstrated is the smallest element in frame.
4. **Everything dissolves into everything.** A global `shutter()` opacity ramp
   with a 14-frame overlap on every boundary. Uniform transitions read as
   template.

---

## Recommended concept — "Nothing flashes"

The through-line is not "here are the features." It is: **this config is a set
of answers to specific irritations, and it tells you what it hasn't tested.**

That gives the video a spine (irritation → answer, four times), an opening that
is not a logo, and an ending nobody else's project video has: the list of what
is *not* verified, on screen, in full.

### Rules of the edit

- **Cold open on the veil, no title for the first 10 seconds.** The most
  distinctive thing this repo does is the one thing you cannot screenshot.
- **Clips run full-frame at native size, unscaled.** No chrome, no card, no
  border. The native-resolution finding from the GIF work applies here too.
- **Captions only where the screen alone is ambiguous.** Never a caption that
  narrates what is plainly visible.
- **Cut on the action, not on a timer.** Scene lengths are whatever the clip's
  behaviour needs — deliberately uneven.
- **No second person, no imperatives, no benefit statements.** README voice:
  facts, numbers, and the occasional flat admission.
- **One accent, taken from `mono-dark`.** Transitions are hard cuts except two
  deliberate ones (into the title, into the receipts card).

### Script — target ~2:00 at 30 fps

Timings are intent, not gospel; they move to fit the real clip lengths.

| # | Time | Picture | On screen (text) | Source |
|---|------|---------|------------------|--------|
| 1 | 0:00–0:09 | Full frame, no text. Desktop frosts over, one card per open window, progress advances, veil lifts onto the same windows in the same groups. | *(nothing)* | `IMGS/veil.gif` |
| 2 | 0:09–0:14 | Held on the restored desktop. | `That was qtile restarting.`  ⏎  `Normally every window on every workspace flashes across the screen.` | same frame |
| 3 | 0:14–0:20 | Hard cut to black. Six-line block-letter ATI-OS artwork, accent, then one line under it. | `ATI-OS` artwork ⏎ `Arch + qtile, packaged` | `banner()` artwork, as in the docs header |
| 4 | 0:20–0:40 | Full-frame desktop tour: group switch, layout change, logo menu, a mode chip filling and clearing. | Three short lower-thirds timed to the action: `groups` / `layouts` / `every mode names the keys it takes` | `IMGS/overview.gif` |
| 5 | 0:40–0:55 | Update manager: pending pacman + AUR with checkboxes toggling, then the search tab. | `Updates are a chip in the bar.` ⏎ `pacman and the AUR, same list.` | `IMGS/qupdate.gif` |
| 6 | 0:55–1:08 | Drop shelf slides in, a file dragged in becomes a tile, tile dragged back out into another window. | `A file between two applications has to live somewhere.` | `IMGS/qdrop.gif` — **see note** |
| 7 | 1:08–1:25 | Theme picker listing 22 modes, then a cut to the palette grid. | `22 themes.` ⏎ `Every one retints every application at once.` | `IMGS/theme-picker.gif` → `IMGS/themes.png` |
| 8 | 1:25–1:35 | The searchable binding list, chord prefixes intact, filtering live as it types. | `85 keybindings, parsed out of the config by AST —` ⏎ `so the list cannot drift from the config.` | `IMGS/keybindings.gif` |
| 9 | 1:35–1:52 | The install, cut tight from the three QEMU runs. | `Seven questions.` ⏎ `~22 minutes, not two hours — the 31 AUR packages ship prebuilt.` ⏎ `QEMU: default 16/16 · encrypted 19/19 · alongside an existing OS 19/19` | `video/public/install-a,b,c.mp4` |
| 10 | 1:52–2:05 | Slow fade to a plain card. No motion. | `Not verified:` ⏎ `AMD · NVIDIA · a HiDPI panel · booting from a physical USB stick on real hardware.` ⏎ `Nobody has run it on those.` | — |
| 11 | 2:05–2:12 | Wordmark, small, with two links. | `github.com/Mohamedattiadev/ATI-OS` ⏎ `archive.org/details/ati-os-2026.08.04-x86_64` | — |

Scene 10 is the one that makes it not an ad. If it goes, the video is v1 again
with better pacing.

### Two alternatives, if the spine is wrong

- **"One command, one hour, one desktop"** — the whole video is a single install
  running its course. Cold open on a bare TTY, cut to what each phase produces,
  end on `letsgo` and the desktop. Through-line is time. Strongest if the ISO is
  the thing you want people to take away; weakest at showing daily use.
- **"Read the receipts"** — the honesty angle promoted from ending to premise.
  Every claim on screen arrives with its evidence next to it (46/46 modules,
  16/16, 19/19, and the untested list). Most distinctive, hardest to keep from
  turning dry.

---

## Decisions taken — 2026-08-05

| Question | Answer |
|---|---|
| Spine | "Nothing flashes" — the recommended one |
| Voice | Silent captions. No narration, plays muted in a README |
| Length | ~2:00 |
| Closing "Not verified" card | Stays |

### What changed between script and build

- **The composition is 1366×768, not 1080p.** That is the resolution the
  desktop was captured at, so every full-screen clip plays 1:1 and no
  resampling touches the terminal text. A 1920×1080 canvas would have had to
  scale all of them by 1.405× — non-integral, and it blurs. Clips smaller than
  the frame (`qdrop` 680×400, the QEMU window 900×562) are centred at native
  size and letterbox into `#11111b`, which is the config's own desktop colour,
  so the surround is invisible rather than a frame.
- **The accent is `#51afef`, not mono-dark.** `palette-mono-dark.rasi` is
  genuinely monochrome (`#000000`/`#e0e0e0`/greys) — an accent taken from it
  would be grey. The nested captures are themed with that cyan, so the
  typography now matches the footage on screen instead of fighting it.
- **`themes.png` is the one thing that gets scaled**, because it is a 1626×1911
  composited still, not footage. It is shown full-width and panned rather than
  shrunk to fit, which would make the palette labels unreadable.
- **Beat lengths are measured, not planned.** The three markers in the desktop
  tour are timed to frames read off `overview.mp4` — layouts at clip f125–360,
  a mode chip at f450–560, the logo menu at f770–875 — not to a grid.
- Final cut: 3,870 frames at 30 fps = **2:09**.

---

## Source-material note (found while surveying, not part of Job C)

Against `gif_list.md`'s P1 set, `IMGS/` is short three items:

- `qdrop.gif` is dated **2026-07-28** — it was not re-shot in the Job B pass,
  so scene 6 would use an old clip.
- `clock-tooltip.gif` (P1, new) does not exist.
- `ati-os-install.gif` (P1, re-shoot) does not exist — scene 9 falls back to the
  three QEMU `install-*.mp4` clips in `video/public/`, which is what the script
  above assumes.

Not blocking the concept. Worth knowing before the edit.
