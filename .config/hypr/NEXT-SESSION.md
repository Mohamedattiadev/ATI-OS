# Prompt — next session

Continue the Hyprland / Tide-Island work in `~/.dotfiles`, branch `test`.

`~/.config/hypr` and `~/.config/quickshell` are stow symlinks INTO this
checkout, so editing here edits the running desktop. Quickshell hot-reloads
on save.

**Read before touching anything:** the RULES section at the bottom, then the
audits at the end of `.config/hypr/upgread_UI_UX.md` (newest last — they are
the measured state; the P0-1…P3-10 plan above them is mostly closed or
stale, and where they disagree the audit measured it).

**The user's original eight asks are all closed or resolved.** What follows
is a new list, given by the user directly. Several items already have a
ROOT CAUSE FOUND AND VERIFIED below — do not re-derive them.

Commit as you go, one concern per commit, reasoning in the message the way
the existing history does. **No Co-Authored-By trailer.**

---

# 1. WALLPAPERS — real per-theme sets, from a real source

The user's verdict on the generated ones: **"the wallpaper u found not even
good"**. They are gradient-mapped recolours of the existing library
(`AtiScriptsV1/theme-wallpaper-gen`), and they were only ever a fallback for
the measured fact that the 362-image library cannot serve nine themes.

The user found <https://github.com/FrenzyExists/wallpapers> and wants real
photographs that suit each theme.

### What they asked for, exactly

  * Clone that repo, take the wallpapers, put them in **their own wallpaper
    repo**, and **commit and push there**.
  * **More than 5 wallpapers per theme.** Get them all.
  * On every theme change, **pick ONE AT RANDOM** from that theme's set —
    "for gruvbox for example if i have 10 wal i want in every change of
    theme to have one randomly selected wal from these 10".

### Facts you need, already measured

**`~/Pictures/Wallpapers` IS A GIT REPO. This matters.**

    origin    https://github.com/Mohamedattiadev/wallpapers   (the user's)
    upstream  https://github.com/w3dg/wallpapers.git
    branch    main
    HEAD      3de9e7f "Rewrite README with attribution chain"

It currently has **one untracked entry: `themed/`** — the 21 generated
images from the last session. Decide deliberately whether those stay as a
fallback (recommended: keep — they are the only thing covering themes no
photo repo has) and whether they are committed or gitignored. Do not leave
the repo dirty either way.

**FrenzyExists/wallpapers does NOT cover most of the 21 themes.** Its 22
top-level directories are:

    Anime, Aquarium, Blobs And Waves, Brown, Cherry Blossoms, Crimson,
    Dracula, Flowers, Green, Gruv, Keyboards, Lantern, Linkin Park,
    Monochrome, Nord, Other, Pixelart, Shitpost, Solarized,
    Tea And Coffee, Universal

By NAME that is **Dracula, Gruv(box), Nord, Monochrome, Solarized** — and
`solarized` is not even one of this machine's 21 themes. Missing: doomone,
tokyonight, catppuccin, monokai, everforest, rose-pine, kanagawa, oxocarbon,
cyberpunk-neon, synthwave, matrix, mono-light, nightowl, onedark, palenight,
github-dark, ayu-mirage.

**So one repo will not satisfy "more than 5 per theme" for 21 themes.** Tell
the user that rather than quietly delivering four good themes and seventeen
weak ones. Recommended plan:

  1. Take everything usable from FrenzyExists for the themes it names.
  2. Add the other per-theme repos — `catppuccin/wallpapers`,
     `rose-pine/wallpapers`, `p4rfait/rose-pine-wallpapers`,
     `Apeiros-46B/everforest-walls`, `AngelJumbo/gruvbox-wallpapers`,
     `linuxdotexe/nordic-wallpapers`, and `yukazakiri/themed-wallpapers`
     (1100+ images across 22 palettes, generated with gowall — covers
     catppuccin, everforest, tokyo-*, onedark, night-owl, synthwave-84,
     cyberpunk).
  3. For any theme still short of 5, fall back to the generated `themed/`
     set — and consider generating MORE per theme by feeding
     `theme-wallpaper-gen` several base images instead of one. It already
     ranks all 362 in CIELAB and currently keeps only the best.
  4. **Score every candidate before keeping it.** `theme-wallpaper-gen`
     already contains the scorer (`score()`, CIELAB, weighted
     `1.00*d_bg + 0.60*d_accent + 0.25*d_fg`). A file in a folder called
     "Nord" is not automatically a nord wallpaper. Reject on ΔE and report
     the final count per theme.
  5. Check licensing/attribution before pushing into the user's repo — it
     already carries an attribution chain in its README (`3de9e7f`).
     Extend it rather than overwriting it.

### The code that has to change

`AtiScriptsV1/theme-wallpaper` resolves a theme to ONE path today:

    override map   ~/.cache/qtile/theme-walls.json   (a manual pick)
    default        ~/Pictures/Wallpapers/themed/<theme>.jpg
    nothing        leave the wallpaper alone

Random-per-theme means resolving to a SET and picking from it. Keep these
two behaviours, which the user chose explicitly and has not retracted:

  * a manual pick still REBINDS that theme (picking under synthwave makes
    synthwave mean that image), and a bound override must BEAT the random
    set — otherwise the pick does not stick, which was the whole point;
  * `theme-wallpaper forget <theme>` returns the theme to its set.

Suggested layout: `~/Pictures/Wallpapers/themed/<theme>/*.jpg` as the set,
with the single-file form still honoured. Avoid repeating the previous pick
when a set has more than one image, or "random" will visibly repeat.

---

# 2. THEME AND WALLPAPER MUST CHANGE TOGETHER, AS ONE ANIMATION

User: **"i want also the theme and the wallpaper change in the same time no
glitch at all one animation"**.

Today they are deliberately SEQUENTIAL, and you need to know why before
changing it. `theme-apply` calls `theme-wallpaper apply` **after** it prints
`THEME_APPLY_VISIBLE_DONE`. The island freezes the screen until it sees that
marker, and awww's wave takes about a second — putting the wallpaper ahead
of the marker adds all of it to a freeze that is already a known problem.
Measured to-marker after the dunst fix: median 1.04 s, min 0.91 s, n=6.

So the seam is a real design conflict, not an oversight. Resolving it
properly probably means driving BOTH from one place —
`qml/theme/ThemeTransitionWindow.qml` already exists and already covers the
screen for the theme change — so the wallpaper swap happens underneath the
same cover and the cover lifts once. Read:

    hypr/scripts/theme-list.sh           the palette source
    AtiScriptsV1/theme-apply             THEME_APPLY_VISIBLE_DONE, ~line 1489
    AtiScriptsV1/theme-wallpaper         apply / poke_daemon
    hypr/scripts/wallpaper-sync.sh       the awww wave parameters
    qml/theme/ThemeTransitionWindow.qml  the existing cover

**Measure the freeze before and after** with the to-marker method already
used here, and do not let it grow. Verify on screen — `wf-recorder` is
installed and working now, so the transition can be recorded and stepped
through rather than described.

---

# 3. `$mod SHIFT O` / `$alt SHIFT A` — THE S WORKSPACE. ROOT CAUSE FOUND.

User: **"the win+shift+o for S it do not take me to S workspace it still
writes 4 or whatever the workspace i am in and show all the icons of all
apps in the island"** — same for anki.

**Do not start by suspecting `toggle-app.sh`.** It was walked and all three
branches passed: not running → switches to S and spawns; open elsewhere →
switches and focuses; standing on it → bounces back. The compositor really
does move to S; `hyprctl activeworkspace` confirms it.

**The island is what is wrong, and the line is:**

    qml/island/HyprlandWorkspaceTracker.qml:32
        if (monitorWorkspaceId < 1)
            return;

`S` is a NAMED workspace and Hyprland gives named workspaces NEGATIVE ids —
`hyprctl workspaces` shows `S` as **id -1337**. So `syncWorkspaceState()`
returns early, `currentWorkspaceId` is never updated, and the island keeps
rendering the workspace you were on before. That is exactly "it still writes
4", and because the workspace never syncs the window strip keeps showing the
previous workspace's clients — "all the icons of all apps".

`normalizeWorkspaceId()` (line 26) also returns `-1` for anything
unparseable, which collides with the same guard.

Fix it properly: the island must represent a named workspace by NAME, not by
integer id. The id is threaded through as `int`, so check every consumer —
`HyprlandWorkspaceTracker.qml`, `CompositorWorkspaceTracker.qml`,
`WorkspaceLayer.qml`, `WindowRingStrip.qml`, `qml/workspace/*`, and
`showWorkspaceCapsule(workspaceId)` in `DynamicIslandWindow.qml`.
**When you widen that type, grep every consumer that assumed a positive
int** — that is the empty-picker bug from an earlier session, waiting in a
new place.

Also confirm special workspaces (`special:term1` etc, also negative) do not
regress. They are a separate case and the island currently ignores them,
which may well be correct.

**Test every case** ("i want u to test all possible cases in this thing to
fix all possible issues"): S empty / obsidian only / anki only / both;
toggling from each numbered workspace; app already open on S; app dead;
both open and toggling between them. In each, check the island's workspace
chip AND its window strip. anki and obsidian share home S but keep separate
go-back memory in `$XDG_RUNTIME_DIR/hypr-toggle/` — verify one cannot
clobber the other.

---

# 4. NIGHT LIGHT — ROOT CAUSE FOUND, AND THE LAST FIX CANNOT WORK

User: **"the nightmode not working i think there is a thing needed to be
downloaded do it"**. They are right, and the previous fix rested on a wrong
premise.

An earlier commit made **gammastep** the fallback because `hyprsunset` was
not installed. Measured now:

    $ gammastep -P -O 4500
    Warning: Zero outputs support gamma adjustment.
    Warning: 1/1 output(s) do not support gamma adjustment.

**Hyprland 0.56.2 does not expose `wlr-gamma-control`.** gammastep starts,
exits 0, and changes nothing — the fallback is inert, and it fails silently,
which is why it looked finished.

The fix is the package the user suspected:

    extra/hyprsunset 0.4.0-3        <- a REPO package, not AUR

Do:

  1. `sudo pacman -S hyprsunset` — but ASK FIRST. The last package install
     was approved before it happened and that is the pattern here.
  2. Declare it in `.config/arch-config/modules/wm.yaml` beside the other
     Hyprland pieces, with a comment recording WHY gammastep cannot serve
     (this exact measurement).
  3. `docs/under-the-hood.html` carries a declared-package count that
     `validate.sh` asserts — **the commit that adds a package is the commit
     that moves the number**, or the pre-commit hook refuses. It is 295 now.
  4. Rewrite the control-centre branch in
     `qml/controlcenter/ControlCenterLayer.qml` (~line 536, the `nightLight*`
     properties start ~line 201) to drive `hyprsunset`, and delete or demote
     the gammastep path with a comment saying it cannot work here.
  5. **A screenshot cannot see a gamma change** — `grim` samples the
     composited buffer and the LUT is applied at scanout. This needs the
     user's eyes, or `hyprctl hyprsunset` state as a proxy. Say which.

---

# 5. AN ONBOARDING FLOW FOR HYPRLAND, LIKE EWW'S

User: **"i want something like the onboarding of eww but for this hypr i
think we can do it also with quickshell i am counting on u"**.

The model to read first, in full:

    .config/eww/onboarding/welcome.yuck      steps.yuck
    .config/eww/onboarding/keybindings.yuck  workspaces.yuck
    .config/eww/onboarding/bar_tooltip.yuck  finish.yuck
    .config/eww/onboarding/onboarding.scss

qtile drives it from `config.py:2689 toggle_onboarding()` via
`eww open onboarding-welcome`, with a bar tooltip
(`"tooltip_widgetbox": "Tips (💡) · click → toggle onboarding"`). Also read
`AtiScriptsV1/onboarding-first-run` and `AtiScriptsV1/onboarding-cheatsheet`
— the first-run one likely already has the "has this user seen it" state
logic worth reusing rather than reinventing.

Build the Hyprland one in Quickshell, in the fork tree, as its own layer.
**Reuse the four shared components** — `qml/common/PanelChrome.qml`,
`PanelRow.qml`, `PanelTabs.qml`, `KeyHint.qml` — rather than inventing a
fifth style; consolidating onto them was an entire audit.

Hold yourself to: it must be reachable again after first run (an onboarding
you can only see once is untestable), it must not hold the keyboard in a way
that breaks the desktop behind it, and it must be drivable over IPC — **a
control with no way in from a script is a control whose bugs only the user
finds.**

---

# 6. NEW KEYBIND: `$mod SHIFT /` — THE DOCS / KEYMAP OVERLAY

User: **"a new keymap which is win+shift+/ which like i am clicking on
win+? so this will behave like the 'window chip' in qtile — will show all
the documentation keymaps troubleshooting etc but for hyprland, check the
qtile related part"**.

The qtile side to read:

    .config/qtile/popups/QtileCheatsheet.py      the sheet
    .config/qtile/popups/_cheatsheet_grid.py     its layout
    .config/qtile/popups/VimCheatsheet.py        FishCheatsheet.py
    .config/qtile/config.py:2838 open_cheatsheet(which="qtile")
    /usr/local/bin/rofi_docs                     the IPC entry point
    .config/qtile/config.py:306-338              the mode-chip label table

**The Hyprland side ALREADY HAS a cheatsheet — do not build a second one
blind:**

    binds.conf:465     bind = $mod SHIFT, K,  submap, cheatsheet
    hypr/scripts/cheatsheet.py
    qml/cheatsheet/CheatsheetLayer.qml

So the job is most likely to EXTEND that into a full docs surface — keymaps,
documentation, troubleshooting, tabbed — and bind `$mod SHIFT, slash` to it.
**Check for a collision first:** `binds.conf:459` already uses `$mod, slash`
for the media submap. Decide with the user whether `$mod SHIFT K` stays as
an alias or is replaced.

Generate the keymap content FROM `binds.conf` where possible rather than
hand-copying it. A keymap sheet that drifts from the real bindings is worse
than none, and this repo has already paid for that lesson —
`submap-indicator.sh`'s `hint_for()` had silently drifted by a third of its
map.

---

# 7. DOCUMENTATION PASS

User: **"update the readme and troubleshooting for hypr and also
arch-config etc"**.

    .config/hypr/README.md            (check it exists; create if not)
    .config/hypr/MIGRATION.md         1200+ lines, the qtile→hypr record
    .config/hypr/REQUIREMENTS.md
    .config/hypr/upgread_UI_UX.md     the audit trail — APPEND, do not rewrite
    .config/arch-config/README.md     and its modules/*.yaml comments
    docs/under-the-hood.html          asserted counts live here
    installScripts/validate.sh        gates every commit

Fold in what the last sessions established, and make the troubleshooting
sections genuinely diagnostic. The failures on this machine have been
overwhelmingly SILENT ones — a font that falls back, a daemon that is not
running, a socket listener that exited, a config key nothing reads, a
Gray-colorspace palette. Each deserves "symptom → the command that proves
it".

---

# 8. STILL OPEN FROM BEFORE

  * **The ~800 ms panel settle.** Oldest unsolved thing here. Two
    hypotheses disproven and NOT to be retried: `morphDurationFor` (760 vs
    520 measured identical) and the slider intro gate. Re-measure first.
  * **The theme change's remaining ~1.0 s.** The dunst 0.24 s is taken; the
    rest has never been profiled block by block. Instrument between start
    and `THEME_APPLY_VISIBLE_DONE` before changing anything.
  * **12 picker menus unchecked** against their rofi originals: documents,
    man, notes, clipboard, confedit, spellcheck, translate, pass, todo,
    shared, youtube, hub. **Do the record menu first** — its six rows were
    written against a `wf-recorder` that did not exist and now does.
  * **Live preview in the settings app** for the cheap numeric keys (sizes,
    opacity, position). The one Phase 8 item unbuilt.
  * **`islandShowWorkspaceOnAutoHide` is an inert row** — a row in both
    clients, no reader anywhere (packaged backend is 1.0.34, the key is
    upstream's from 1.0.35). Goes live on a package upgrade. Do NOT "fix" it
    via ForkConfig; see the audit for the collision that causes.
  * **Scratchpads on a second monitor** — never tested. The
    monitor-relative x/y logic is verified-by-history only.
  * **Keybind latency** — every island binding spawns a fresh `qs ipc call`,
    ~50 ms before any animation starts.
  * **`layout-cycle.sh` makes 7 `hyprctl` invocations per switch.**
  * **What killed the two socket listeners** was never recovered. They
    reconnect on a dropped read now, but a `kill` still ends them and
    nothing notices.

---

# RULES — every one of these was paid for, several twice

### Verification

- **A config that reloads cleanly is not a config that works.** Read
  `$XDG_RUNTIME_DIR/quickshell/by-id/<id>/log.log`.
- **Compare the log's last "Configuration Loaded" against the file's mtime.**
  A shell.qml edit once landed 6 s AFTER the reload its own earlier edit had
  triggered, and a measurement "proving the change did nothing" was reading
  the old shell. `touch` the file if in doubt.
- **A verification step that cannot fail loudly is not one.** A check that
  "passed" the picker ran `qs ipc call` through a shell VARIABLE holding the
  whole command line with stderr to `/dev/null`; the call never ran and a
  blank screen was read as a resting island.
- **`qs ipc call` prints "Function not found" and still EXITS 0.**
- **Toggle IPCs go out of phase. Prefer explicit show/hide when scripting.**
  This has now bitten twice — once on `qs ipc`, once on
  `togglespecialworkspace` in `scratchpad.sh`, where the spawn path already
  knew the state it wanted.
- **A control with no way in from a script is a control whose bugs can only
  be found by the user.** If a feature cannot be driven over IPC, ADD THE
  IPC — that is a fix, not scaffolding.
- **`wtype` is installed** and can drive panels. A synthesised capital
  arrives with `text` "G" and NO ShiftModifier — check the character.
- **If a metric is applied to two things, first run it on two things KNOWN
  to be equal.** `magick X -colorspace Gray -format %[fx:mean]` reads ~30
  points HIGH on a colour image (Gray is linear in memory, gamma-encoded on
  disk). That artifact looked exactly like a 70%→40% darkening, a plausible
  cause was found for it, and a working implementation was replaced on the
  strength of it.
- **A test that fails correct code is a bug in the test.** An assertion that
  a search "spans more than one section" failed a correct search, because
  all seven matches legitimately lived in one section.

### Reading the UI

- **Before filing "X is missing": GREP for X and MEASURE the claim.** Four
  deliberate design decisions were filed as defects in a single session.
- **Look at the image, not only the number.** Every luminance check passed
  while mono-light had lavender trees. Only a contact sheet showed it.
- **Private-use characters do not survive into what the model reads back.**
  A grep for a Nerd Font glyph returns an empty-looking string. Dump bytes.
- **A screenshot cannot see a gamma change.** Night light needs eyes.
- **Magnify before believing a glyph is absent.**

### Editing

- **When you widen an enum or a type, grep every consumer that named its
  values as literals.** This is the empty-picker bug, and item 3 above is
  the same shape waiting to happen with workspace ids.
- **One layout, one arithmetic.** Two descriptions of one layout put the
  notification centre's footer on the desktop.
- **A layer that fills its parent is NOT filling the capsule.**
- **`.pragma library` JS is cached.** Editing `Metrics.js` or `Motion.js`
  and reloading does nothing. **Restart the island.**
- **A file that has never been instantiated is not being watched.**
- **A background listener that connects to a socket ONCE will die silently
  and stay dead.** Distinguish "the read ended" (reconnect) from "the socket
  FILE is gone" (compositor left).
- **A "restart" that starts unconditionally is not a restart.** `pkill -x`
  exits 0 only if it signalled something, so it is both the kill and the
  test for whether there was anything to restart.
- **A verify-then-retry loop cannot catch a change that happens after its
  last read.** It succeeds, breaks, and the app moves the window afterwards.

### Safety

- **Never synthesise keystrokes into a settings panel.** Every press writes
  real config. Drive the logic directly instead.
- **Close a panel that commits on click before leaving it on screen.**
- **`pkill -f <pattern>` matches its own command line.** Use `pkill -x`.
  This defeats `pgrep -f` CHECKS too — even the `[s]` bracket trick, when
  the surrounding command line contains the literal string. Use
  `ps -eo args | awk '/pat/ && !/awk/'`, or test the lock file.
- **hyprlock is tested in a NESTED Hyprland, never by locking the session.**
- **Back up `~/.config/tide-island/userconfig.json` before any test that
  writes, and diff it after.** Byte-identical at the end of every session so
  far (`dff1139b…`). Keep that true. Note `--selftest-write` restores the
  VALUE, not the ABSENCE, so it is not byte-exact on its own.
- **`~/Pictures/Wallpapers` is a git repo with a remote.** Anything written
  there is a change to the user's published repository. Do not push without
  saying what is being pushed.
- **The user changes the theme while you work.** `theme_mode` read
  `synthwave`, then `mono-dark`, then `nightowl` across one session with no
  picker opened. Re-read it before a test that depends on it, and restore
  what you found rather than what you assumed.
- **The capture region must contain nothing but the thing under test.**
  `hyprctl workspaces -j` will tell you which workspaces are free.
- **Difference two frames; do not just count changed pixels.**
