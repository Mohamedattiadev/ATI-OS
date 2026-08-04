# Prompt: find where qtile's restart time actually goes

Paste everything below as the opening message of a new session.

---

Task: profile my qtile startup and tell me, with numbers, exactly what
makes `Super+Shift+R` slow. Then fix the top offenders.

## Hard constraint (non-negotiable — learned the hard way)

**Never iterate by restarting my live qtile.** An earlier attempt froze
the desktop and crashed X. All work happens in an isolated Xephyr
sandbox. The sandbox recipe and its many gotchas are in
`~/.dotfiles/qtile-veil-HANDOFF.md` — **read that file first**, especially
the "Sandbox gotchas" section. I press `Super+Shift+R` myself; you never
trigger it on my real session.

## What is already known — do NOT re-derive these

- A "veil" process already covers the ugly part of the restart. It is
  done and working. This task is about *duration*, not appearance.
  Do not restyle it.
- The config **module executes in 0.13s**, and **no widget's `_configure`
  exceeds 20ms**. So "config.py is 4,500 lines" is a red herring — file
  size is not the cost.
- An `xmodmap` stall used to add ~15s. Fixed. Not the problem any more.
- Sandbox measured ~10s unattributed, but the sandbox is a nested X
  server with software compositing and no GPU. My own commit
  (`0b1d54e`) records that **the sandbox understates the real machine
  ~2.5x**, so sandbox numbers are not my numbers.
- The veil now renders an elapsed-time chip (e.g. `3.5s`) during every
  restart. That is the ground truth for my real hardware — use it.

## What I want

1. **Measure first, change nothing.** Attribute the wall time between
   `qtile.restart()` and `startup_complete` into named phases. Candidate
   tools: `python -X importtime`, `cProfile` around config import,
   timestamps written to an append-only file (qtile truncates stdout
   across execv — see the handoff), and finer-grained `_veil_stage()`
   calls to bisect the startup path.
2. **Report a breakdown**, largest first, in milliseconds. If a phase is
   inside libqtile rather than my config, say so plainly.
3. **Then fix the top offenders**, cheapest-first, and re-measure to show
   the before/after. Typical suspects: module-level `subprocess` calls,
   file or network I/O at import, widgets that probe hardware when
   constructed, expensive imports that could be deferred.

## Rules

- **Do not "split config.py to make it faster."** Splitting does not
  reduce import time — Python runs the same code either way. Propose it
  only as a maintainability change, clearly labelled as such.
- Do not guess or quote a speed number you have not measured on my
  machine. If you only have sandbox numbers, say so.
- Do not change how my bar looks or which widgets I have without asking.
  If a widget is expensive, tell me the cost and let me decide.
- Every claim gets a measurement behind it.

## Files

- `~/.config/qtile/config.py` — symlinked into `~/.dotfiles`
- `~/.config/qtile/scripts/qtile-restart-veil.py` — the veil; `_veil_stage`
  in config.py feeds its progress
- `~/.dotfiles/qtile-veil-HANDOFF.md` — sandbox recipe + gotchas
- `~/.dotfiles/qtile-veil-FINDINGS.md` — prior measurements

Start by reading the handoff, then tell me your measurement plan before
you change anything.
