# Rewriting the manual

> **Status: not started.** This is the plan, written 2026-08-30. The prompt
> that executes it is `PROMPT-REWRITE.md` next to this file.

## Why rewrite rather than keep patching

Asked for directly: *"the whole documention need rewrite from scratch ezier
and simpler and matches the new things"*.

The measurements behind that, taken today:

| | |
|---|---|
| pages | 12 |
| total | 5,489 lines of hand-written HTML |
| largest | `under-the-hood.html` 833 lines · `keybindings.html` 772 |
| nav sidebar | hand-copied into **11 of the 12 files** |
| hand-typed counts | in 4 files (`46 steps`, `23 colour schemes`, `21 packages`…) |

Three symptoms follow from that shape, and all three happened this week:

1. **Adding one feature costs four edits.** Documenting the Skills badges,
   the calendar reminders and the AltGr key meant touching three pages plus
   regenerating `assets/search-index.js` — and none of those edits are
   discoverable from the feature's own code.
2. **The numbers drift, and the drift is invisible.** `validate.sh` exists
   *because* of this: it compares the docs' step count against
   `wizard.sh`'s real one. It caught a `46 vs 47` mismatch this week. It
   does not check theme counts, so `install-git.html` says "22 colour
   schemes" while `themes.html` says 23 — both defensible, together
   confusing.
3. **The nav is 11 copies of one list.** A new page means editing every
   other page. That is why `plugins.html` needed a scripted insert rather
   than a hand edit.

## What must NOT be lost

The current manual is good in ways a rewrite could easily throw away:

* **It is written for a person, not a peer.** "Press Super+P, let go, then
  press c" — no jargon, no assumed vocabulary. Keep that voice exactly.
* **Every claim is sourced from the live system.** Counts are computed,
  screenshots are of the real thing, and `validate.sh` polices the claims
  that are typed by hand. A rewrite that reintroduces "about 20 themes"
  is worse than what it replaced.
* **The `.screen` and `.note` blocks** that say what you will actually see,
  and the "what this does not prove" honesty in the install pages.
* **It is plain HTML served straight off GitHub Pages, no build step** — one
  generated file (`search-index.js`, committed output). Do not introduce a
  static site generator, a toolchain or a `node_modules` for a 12-page
  manual.

## The shape to move to

**One layout, one nav, one place for numbers.**

* **`_layout` fragments + a tiny generator.** The nav, header and footer
  become one file each; a ~100-line `build.py` (beside the existing
  `build-index.py`, same "committed output" convention) renders each page.
  Adding a page edits one list. This is the single biggest win and it is
  cheap.
* **`facts.json`, generated from the repo.** Step count, theme count,
  package count, command count — computed by the same logic `validate.sh`
  already uses, written once, substituted into pages. Then `validate.sh`
  checks the *generator*, not twelve prose copies.
* **Fewer, shorter pages.** Merge `under-the-hood.html` (833 lines) into
  `reference.html` and cut what only the author needs; that page is the
  clearest case of writing for a peer rather than a user.
* **A page per surface, matching what exists now**, including the three
  things that only got documented today by hand: plugins, the skills
  library, reminders.

## Order of work

1. Inventory every claim in the current 12 pages; mark keep / cut / stale.
2. Build the layout fragments + `build.py`; port ONE page (`start.html`)
   and diff the rendered output against the current file to prove the
   generator is faithful before touching the rest.
3. Port the remaining pages one at a time, rewriting prose as you go.
4. Add `facts.json` and delete the hand-typed numbers.
5. Extend `validate.sh` to check the generator's inputs instead of the
   rendered prose.
6. Regenerate `search-index.js`; commit generated output as today.

Steps 2 and 3 are separable — the generator is worth doing even if the
prose rewrite stalls, and the prose rewrite is worth doing even if the
generator is rejected.

## What "easier and simpler" should mean in practice

* A reader should reach any answer in **two clicks from the index**.
* No page over ~300 lines. If it is longer, it is two pages.
* Every page opens with what the thing is FOR, in one sentence, before any
  key, path or command.
* Command blocks are copy-pasteable as-is, with the shell's own syntax —
  fish, since that is the shell here. `cd (ati-plugin dir)`, not
  `cd $(ati-plugin dir)`.
