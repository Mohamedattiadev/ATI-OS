# Prompt — rewrite the manual

Paste this into a fresh session. Read `docs/PLAN.md` first; it is the
argument and the measurements, this is the brief.

---

Rewrite the ATI-OS manual in `~/.dotfiles/docs/`. The owner's words:
*"the whole documention need rewrite from scratch ezier and simpler and
matches the new things"*.

**Read before writing anything:**

* `docs/PLAN.md` — why, what must not be lost, and the order of work
* `ARCHITECTURE.md` — the plugin contract; §3's six surfaces are the thing
  the manual most needs to explain and currently explains only once
* `.config/hypr/PROMPT-NEXT.md`'s status banner — what is actually built.
  **Do not describe a feature from that file's body without checking the
  code**: eleven of its seventeen items were already built while it still
  described them as open.
* `installScripts/validate.sh` — it polices claims the docs make. Whatever
  you write has to keep passing it, and the rewrite should let it check
  MORE, not less.

**Ground rules, all of them learned the hard way in this repo:**

1. **Never write a number you did not compute.** `validate.sh` exists
   because prose counts drift. Today `install-git.html` says "22 colour
   schemes" and `themes.html` says 23 — both arguably right, together
   confusing. Generate them.
2. **Keep the voice.** It is written for someone who does not know the
   jargon: "Press Super+P, let go, then press c." Do not make it
   engineer-facing. Do not add words like "leverage" or "seamless".
3. **No build toolchain.** Plain HTML off GitHub Pages, one small committed
   generator, the same convention `build-index.py` already uses. No
   node_modules for twelve pages.
4. **Prove the generator before trusting it.** Port `start.html` first and
   diff the rendered output against the current file. A generator that
   quietly drops a section is worse than the copy-paste it replaced.
5. **Regenerate and COMMIT `assets/search-index.js`.** It is committed
   output; its own header says so.
6. **Shell examples are fish.** `cd (ati-plugin dir)`, not `$(...)`.

**Cover the things the current manual barely mentions**, all shipped
recently and all documented only by hand-patching a page:

* the plugin system — `plugins/`, the six surfaces, `ati-plugin
  list|sync|doctor|dir`, and that shipped plugins live in the repo while
  yours live in `~/.config/ati-plugins`
* the skills library — `ati-docs skills`, one markdown file per skill
* calendar reminders — click a day, `09:30 dentist`, real notifications
* AltGr — tap to repeat the last action, hold still types AltGr
* `system/` — the files this repo owns outside `$HOME`

**Verify, do not assume.** Open the rendered pages. Every command you print
should be one you ran. Three times in the session that produced this file,
something was "done" in a commit and broken in practice — `ati-plugin` was
never on `PATH`, `ati-plugin dir` printed a directory that did not exist,
and three features had no user-facing docs at all. Each was found by using
the thing, not by reading the diff.

**Scope.** The prose rewrite and the generator are separable; either is
worth landing alone. Do not start both and finish neither.
