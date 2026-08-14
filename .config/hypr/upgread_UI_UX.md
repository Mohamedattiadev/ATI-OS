# UI/UX upgrade plan — the next level

The popups are done. `REQUIREMENTS.md` items 1–5 are closed except the polkit
prompt, and every qtile popup that could be ported has been. This document is
about the *other* axis: not "does the feature exist" but **"does this read as
one designed system"** — and the honest answer today is no, for reasons that
are structural rather than cosmetic.

> **Correction, added by a later audit.** "Closed except the polkit prompt"
> understates it in one place and overstates it in another, and both are
> the same kind of error this document is about.
>
> The polkit prompt is not a gap. `tide showPolkitPrompt` is **registered
> on the live IPC**, and the layer it opens does not exist:
> `polkitPromptLoader` is referenced at `DynamicIslandWindow.qml:3307` and
> declared nowhere. Driving it puts the island into Overlay drawing
> nothing and logs `ReferenceError: polkitPromptLoader is not defined`. An
> absent feature is inert; a half-shipped one is not.
>
> And there is a second dead control of exactly this document's P0-2 kind,
> which it missed because it swept the fork's own files: the control
> centre's Focus/DND row shells out to `swaync-client`, which is **not
> installed** — `dunst` is the daemon here. Read, write and poll all fail,
> and the write failure silently flips the row to off.
>
> Both are written up in `REQUIREMENTS.md`. They belong to Phase 6 and
> Phase 2 respectively.
>
> **Both are now closed.** The polkit prompt was *removed* rather than
> finished — the right call, since nothing registered an agent, so there
> was no half-feature left to trip over; `showPolkitPrompt` is gone from
> `ipc show`. The Focus/DND row was rewritten onto `dunstctl`, and the
> rewrite went further than swapping the binary: state is no longer
> inferred from an exit code anywhere in that row, because "the command
> failed" and "the answer is false" are the same value and that is what
> made the original invisible. Polarity was measured from the daemon side
> rather than taken from the brief, which had it backwards. Unavailable is
> now drawn as well as refused.

Everything below was **measured against the running shell** (quickshell PID
1156732, Hyprland 0.56.2, eDP-1 1366×768) or counted out of the tree at
`.config/quickshell/tide-island-fork/` — 61 QML/JS files, 28,100 lines.
Nothing here is inferred from the design spec alone; where a value could not
be extracted, it says so rather than guessing.

---

## The verdict, in one paragraph

The shell has **three parallel colour systems, and the only live one is the
smallest**. It has no type ramp, no spacing grid and no radius scale — it has
inventories of 11, 15 and 16 unrelated values. It has **two disjoint
interaction models** (upstream panels are mouse-only with zero key handling;
every fork panel is keyboard-only with zero hover states) and no panel
supports both. And the most-seen surface in the entire desktop — the
notification — **is drawn twice, by two different programs, in two different
design languages, at the same moment.** None of that is a missing feature.
All of it is why a shell with 26 working states still does not look
deliberate.

---

# Part 1 — findings, ranked

## P0-1. Every notification is drawn twice

**Proven, with a screenshot and a bus query.** `dunst` (PID 1248363) owns
`org.freedesktop.Notifications`. The island's notification stack —
`NotificationLayer.qml`, `NotificationHistory.qml`,
`NotificationCenterLayer.qml`, the `notification` island state, and the whole
`blocksTransientSplit` arbitration built around it — is fed by
`SystemServices.notificationReceived`, which observes the bus rather than
serving it. So both render:

| drawn by | where | shape |
|---|---|---|
| the island | top centre, expanded capsule, layer level 3 | shell fill, Inter, notch geometry |
| dunst | top right, 327×84 @ 1029,83 | 2 px accent border, its own radius, its own type |

`notify-send "UX audit probe" …` produced both simultaneously; the capture is
in the scratchpad and the layer list showed `quickshell 1366x91 @ 0,0` and
`notifications 327x84 @ 1029,83` on the same frame.

This is worse than a duplicate. It means **the island's notification design
has never actually been in service** — no one has been reading it, because
dunst's card is the one with the icon, the app name and the border, and it is
the one the eye goes to. Every hour spent on `NotificationHistory.qml` is
currently invisible.

**Second-order problem:** `notificationReceived(appName, summary, body)` is
three strings. No `id`, no `replaces_id`, no urgency, no actions, no image
hints, no close signal. So even after dunst is retired, the island cannot
implement *dismiss*, *urgency styling*, *action buttons* or *replace-in-place*
— which is most of what a notification system is. Owning the bus properly
requires `Quickshell.Services.Notifications` (a real server), not the
backend's spy signal.

## P0-2. Three colour systems; theme-apply reaches almost none of the shell

| system | size | live? | usages |
|---|---|---|---|
| raw hex literals in QML | **115 distinct values across 33 of 61 files** | no | **288** |
| `StyleTokens` (compiled, `IslandBackend`) | 47 colours, 4 radii, 4 durations | **no — see below** | 112 (37 distinct) |
| `IslandTheme` (the fork's live palette) | 4 tokens + `shellFill` | **yes** | **18** |

`REQUIREMENTS.md` item 4 says theming is "DONE and verified live", and for
what it covers that is true — the shell *fill* and the window borders follow
`theme-apply`. But it covers 18 sites out of ~400. Every panel's text
colours, dividers, card surfaces, list selection, disabled states and status
colours are either a hex literal or a frozen token.

**The frozen part is not a matter of effort — it is compiled in.** Read out
of `/usr/lib/qt6/qml/IslandBackend/IslandBackend.qmltypes`: all **55**
`StyleTokens` properties are `isReadonly: true` **and**
`isPropertyConstant: true`. They are C++ constants in a package binary. No
amount of QML work makes `StyleTokens.accent` follow gruvbox. (Their actual
values could not be extracted — they are not stored as strings in
`libIslandBackendplugin.so`, and a `qml6` harness produced no console output
in this environment. The *structure* is what matters and that is read
directly from the type registry.)

So there are, on screen right now, at least two different "accents" — the
palette's, and the binary's — and a dozen greys that answer to nobody.

## P0-3. The panels are keyboard-only; the upstream ones are mouse-only

Counted per file. `MouseArea` / hover-state / `Keys.` handlers:

| fork panels | MouseArea | hover | Keys |
|---|---|---|---|
| `DisplayPanel` | **0** | 0 | yes |
| `SystemMonitorPanel` | **0** | 0 | yes |
| `AudioPanel`, `WifiPanel`, `BluetoothPanel`, `ThemePicker`, `PowerMenu`, `Settings`, `Cheatsheet`, `Calendar`, `WallpaperPicker` | 1 (a close-catcher) | **0** | yes |

| upstream panels | MouseArea | hover | Keys |
|---|---|---|---|
| `ControlCenterLayer` | 6 | 7 | **0** |
| `WorkspaceOverviewLayer` | 2 | 11 | **0** |
| `NotificationCenterLayer` | 1 | 3 | **0** |

Two paradigms, cleanly split by who wrote the file, and **not one panel
supports both**. The display panel and the system monitor cannot be operated
with a mouse at all. The control centre cannot be operated from the keyboard
at all. A user does not know which kind of panel they just opened until they
try the wrong input and nothing happens.

There is also **no hover feedback anywhere in the fork's panels** — zero
`hovered`/`containsMouse` bindings across nine of them — and only 2
`ScrollBar`s in the whole tree, so a list that overflows gives no sign that it
does.

## P1-4. Five layers still have dead fade-outs — and they are the five you see most

`PanelLoader.qml` was written to fix exactly this: `Loader { active: <bool> }`
destroys the item in the same event-loop turn that queues its fade, so the
`Behavior on opacity` never runs. It was applied at **46** sites. **Six raw
`Loader`s remain in `DynamicIslandWindow.qml`**, five of which wrap a layer
that fades:

| layer | line | its own fade | reached by |
|---|---|---|---|
| `WorkspaceLayer` | 3991 | `opacity: showCondition ? … : 0` + Behavior | **every workspace switch** |
| `SwipeCustomInfoLayer` | 3871 | same | `showText` / the mode indicator |
| `SwipeLyricsLayer` | 3902 | same | media playback |
| `SplitIconLayer` | 3951 | same | app-icon split state |
| `OsdLayer` | 3969 | same | `showText` **with a value**, and volume only when the ring is off |

Each is instantiated as `<Layer> { showCondition: true }` — a literal
constant — inside `Loader { active: … }`. The property that drives the fade
can never go false, so the fade-out is unreachable code, exactly as the
thirteen panels were before `PanelLoader` existed. The write-up in
`MIGRATION.md` ("Cause 1 — the out-fade had never once executed") is still
true of these five.

> **Two corrections, from trying to fix this.** The heading said "the five
> you see most" and the `OsdLayer` row said "every volume / brightness
> key". **Both were wrong**, and the reason is one branch this document
> did not follow:
>
> `userconfig.json` has `forkRingOsdEnabled: true`, and
> `showTransientSplit` returns early into `shellRootController.showRingOsd`
> whenever `progress >= 0`. So volume and brightness never reach
> `OsdLayer` at all — they reach `RingOsdWindow`, which is **not** behind a
> Loader and holds itself up correctly with
> `visible: root.shown || fade.opacity > 0.01`. The most-pressed keys in
> the shell already fade properly. `OsdLayer` gets only the `progress < 0`
> traffic, plus volume on a machine with the ring switched off.
>
> **And the fix is not the mechanical sweep Phase 5 called it.** All five
> of these are swipe layers: their opacity is already
> `showCondition ? revealProgress : 0`, where `revealProgress` is driven by
> `transitionProgress` — so several of them *are* animated out today, by
> the slide rather than by the fade. Binding `showCondition` to `live`
> would add a cross-fade on top of a slide that is already running, and on
> a swipe that means the outgoing layer lingering over the incoming one.
> `WorkspaceLayer` is the clearest genuine win (it carries
> `animateVisibility` and is a plain cut when resting); the swipe pair
> needs a decision about which animation owns the exit, per layer, not one
> substitution applied five times.

## P1-5. No type ramp, no spacing grid, no radius scale

Inventories, not systems:

| dimension | distinct values in use | what a system would have |
|---|---|---|
| type size (`Metrics.font`) | **11** — 9,10,11,12,13,15,17,18,19,24,29 | 5–6 named roles |
| spacing (`Metrics.px`/`pad`) | **15** — 1,2,3,4,5,6,8,10,12,13,14,16,18,20,50 | a 4-px grid: 4,8,12,16,24,32 |
| corner radius | **16** — 2…30 | the 4 `StyleTokens` radii, which exist and are ignored |

`Metrics.js` is a real achievement and its reasoning is sound — one scale, one
place, `font()` at 1.0 because legibility is absolute. But it scales numbers;
it does not name them. `Metrics.font(10)` and `Metrics.font(11)` are used 39
and 41 times respectively and nothing in the tree says what the difference
means, so the next person picks whichever the neighbouring line used.

`DisplayPanel.qml` also carries **8 raw `pixelSize:` literals** that bypass
`Metrics.font` entirely, plus a raw `hintHeight: 24  // 10px type + …`. It is
the one panel that does not scale with the rest.

## P1-6. Screen corners are specified and do not exist

`DESIGN-SPEC.md` lists them as their own item — 69 lines, overlay layer,
rendering **above fullscreen windows**, with an explicitly empty input region
("if you build anything full screen and decorative, that's a trap"). `grep -i
corner` across the fork returns only `windowCornerRadius` inside the workspace
overview. Nothing draws display corners.

This matters more here than it would elsewhere, because **the notch's entire
argument is that it is bezel.** Bezel that stops at the top edge and leaves
four hard 90° screen corners is bezel with a seam in it. The corners are what
make the notch read as part of the machine rather than as a widget parked at
the top.

The empty-input-region technique is already proven in this tree —
`RingOsdWindow` uses `mask: Region {}` for exactly this reason — so the risky
part is already solved and copyable.

## P2-7. `DynamicIslandWindow.qml` is 4,897 lines and owns 26 states

17% of the whole shell in one file, holding every one of:

`application_launcher · audio_panel · bluetooth_expanded · bluetooth_panel ·
calendar · cheatsheet · control_center · custom · display_panel · expanded ·
long_capsule · lyrics · mode_keys · normal · notification ·
notification_center · picker · polkit_prompt · power_menu · settings · split ·
sysmon_panel · theme_picker · wallpaper_picker · wifi_panel · wifi_qr`

This is not a style complaint. It is why P1-4 happened: the six raw `Loader`s
survived a 46-site sweep because nobody can hold 4,897 lines in view at once.
It is also why every panel re-implements its own header, its own selected-row
treatment and its own footer instead of sharing one — the shared-component
directory holds only `ProgressRing`, `MatteSurface`, `ControlSliderCard`,
`PanelLoader` and three non-visual helpers.

Evidence of the cost: the key-hint footer exists on **9 panels** under **two
different property names** (`hintHeight` on four, `footerHeight` on five) at
**four different heights** (`pad(26)`, `px(20)`, `px(22)`, raw `24`).

## P2-8. No search in any list, and lists are the main idiom

`Key_Slash` appears **nowhere** in the tree. The panels that have a search
field have it because they were built around one (application launcher,
cheatsheet); every other list is arrow-keys-only:

| list | items |
|---|---|
| theme picker | **22** |
| wallpaper picker | **362** |
| Wi-Fi networks | however many are in range |
| audio: outputs, mics, playback streams, recording, card profiles, ports | 6 tabs of lists |
| Bluetooth devices | paired + discovered |

`MIGRATION.md` already argued this case once and won it — the cheatsheet came
off rofi specifically because *"what rofi actually contributed was the typing,
not the window"*, and four of qtile's sixteen cheatsheet bindings existed only
to move a viewport. The same argument applies unchanged to 362 wallpapers and
22 themes, and it has not been applied.

## P2-9. The icon layer is thin and mixed

`iconFontFamily` (JetBrainsMono Nerd Font) is bound in **21** places against
**148** bindings of `textFontFamily`. The actual glyph inventory:

- 11 Nerd Font private-use glyphs, used 14 times total
- `⏮` `⏭` — Unicode media symbols, in the text font
- `●` `•` `›` `↔` `↑` `↓` `⇧` — assorted symbols in the text font
- `─` × 379 — box drawing, almost certainly comment rules rather than UI

So most of what reads as an "icon" in the panels is either a text character in
a text font or nothing at all. There is no icon set. There is also leftover
upstream Chinese in some strings (`动`, `灵`, `岛`, `没有找到` …) that will
render in Noto Sans CJK the moment it is reached.

## P3-10. Smaller, verified, cheap

- **`IslandTheme.qml`'s comment contradicts `MIGRATION.md`.** It says
  *"theme-apply renames the file into place atomically"*; `MIGRATION.md` item
  4 records that the rename was **removed** because `FileView` watches the
  inode and an atomic rename kills the watch forever. One of them will mislead
  someone. (The code is right; the comment is stale.)
- **`MIGRATION.md`'s headline table is stale** — it still reads 123/291
  bindings, 42.3%. `hyprctl binds` reports **244** live. Anyone reading the
  percentage as status gets a wrong picture of the whole port.
- **Lock screen** is close to spec (desktop capture, 3-pass blur, brightness
  0.8, `fade_on_empty` ≈ the spec's "hidden until you type") but has no
  user avatar, no username, and no top gradient behind the clock.
- **Resting state has drifted from the spec and that is fine** — it is clock +
  workspace digit + flanking app-icon pucks (`WindowRingStrip`), not clock +
  4-bar EQ. Deliberate, user-requested, and it should stay. Worth one look:
  in the captured frame the left puck sits directly against the notch's left
  flare, which weakens the "one shape" reading the flare exists to create.

---

# Part 2 — the plan

Ordered by *what unblocks what*, not by size. Phases 1 and 2 are prerequisites
for judging anything visual, because until the tokens are live and the
duplicate notification is gone, every "does this look right" question has two
answers.

## Phase 1 — one colour system (P0-2) — **DONE**

> **Closed.** `IslandTheme.qml` is a `pragma Singleton` publishing ~45
> derived roles; all 291 hex literals and all 121 `StyleTokens` reads are
> gone except **twelve**, and those twelve are exactly the four documented
> exceptions, each now carrying its reason at the site rather than only in
> this file. `StyleTokens` is not "demoted to a fallback" — it is gone
> from the tree entirely, along with the `IslandBackend` import in the
> eight files that only held it for that.
>
> **Four corrections to what this section assumed.**
>
> 1. **`StyleTokens`'s values CAN be extracted**, and P0-2's parenthetical
>    says they cannot. `quickshell -p` on a four-line config that imports
>    `IslandBackend` and logs each property prints all 55 exactly. The
>    earlier attempt used a bare `qml6` harness, which produces no console
>    output in this environment — the tool was the obstacle, not the
>    binary. Every derived role therefore starts from the value it
>    replaces instead of from taste. (The *structural* claim stands: all
>    55 really are `isReadonly` **and** `isPropertyConstant`.)
>
> 2. **"Mirror every `StyleTokens` role that is actually used — 37" was
>    the wrong instruction.** Mirroring 37 names would have carried the
>    inventory across intact, which is the disease rather than the cure:
>    eight of them were text greys with nothing anywhere saying what
>    distinguished any two. They collapse onto **four** text roles, and
>    each collapse is a decision recorded at its call site.
>
> 3. **Deriving is not enough on its own — legibility has to be
>    computed.** `textPrimary = fg` is correct on 20 palettes and
>    unreadable on `mono-light`, whose fill lands at #81818b (22%
>    luminance) with a BLACK `fg`. Text is now solved by walking the
>    palette colour toward whichever extreme the surface is not until WCAG
>    contrast clears the target. Modelled across all 21 named palettes
>    before any QML was written: 5.45:1 worst case.
>
> 4. **The verification step is not a formality, and it is where the real
>    bugs were.** Cycling five palettes found four faults that had
>    produced no log line of any kind:
>    `mix()`/`alpha()` receiving strings and returning `Qt.rgba(NaN…)`,
>    i.e. transparent black, which shipped **six roles invisible**;
>    three roles named `onAccent` / `onInverseSurface` / `onOverviewPlate`
>    whose bindings silently never ran because a QML property beginning
>    with `on` collides with signal-handler syntax; a name plate that
>    needed its ink solved against itself rather than against the panel;
>    and two `Canvas` rings that never repainted on a theme change because
>    a Canvas is not a binding. **Do not name a token `onAnything`.**

The goal is a single token layer that every surface reads and `theme-apply`
drives, with `StyleTokens` demoted to a fallback rather than a source.

1. **Grow `IslandTheme.qml` into a real token set.** It currently publishes 4
   colours. It needs roles, not slots: `surface`, `surfaceRaised`,
   `surfaceSunken`, `hairline`, `textPrimary`, `textSecondary`, `textMuted`,
   `textDisabled`, `accent`, `accentPressed`, `success`, `warning`, `danger`,
   `selectionFill`, `selectionBorder`, `trackEmpty`, `trackFill`. Derive what
   can be derived from the nine palette slots `theme-apply` already emits
   (mixes and alpha over `shellFill`) so `gen_island_colors()` does not have to
   grow 17 new arguments.
2. **Mirror every `StyleTokens` role that is actually used** — 37 distinct ones
   — so the migration is mechanical: `StyleTokens.textMuted` →
   `Tokens.textMuted`.
3. **Replace the 288 hex literals**, file by file, biggest first
   (`ExpandedPlayerLayer` 23, `CheatsheetLayer` 21, `PickerLayer` 20,
   `SettingsLayer` 19, `WifiPanel`/`AudioPanel` 17 each). Any literal that
   cannot be expressed as a role is a *finding* — it means a role is missing —
   not a licence to keep the hex.
4. **Keep the fallbacks.** `IslandTheme` already falls back to doomone rather
   than to grey, for the stated reason that a fresh machine should look
   themed rather than broken. That property must survive.

**Guard rail:** the four exceptions that must stay hardcoded are the Wi-Fi QR
card (black on white, always — a themed QR is a QR phones refuse), the battery
bar's success/warning/danger (where the colour *is* the information), the
theme picker's 22 tiles (each painted in the palette it applies), and the
theme-transition overlay.

**Verified by:** cycling ≥4 palettes with `theme-apply` against the live shell
and sampling the framebuffer at named points in each panel — the same method
that caught the `#282828` zero-channel-spread bug. A token that does not move
across four palettes is not wired up.

## Phase 2 — own the notification (P0-1) — **DONE**

> **Closed.** The island serves `org.freedesktop.Notifications` through
> `Quickshell.Services.Notifications`; dunst is out of `autostart.conf`
> and still installed. `busctl --user` reports quickshell as the owner,
> `hyprctl layers` shows one surface with a notification up, dismiss /
> urgency / actions / replace-in-place all round-trip on the bus.
>
> **The stated hazard does not exist on this machine**, and that is the
> finding, not a caveat. "If the island takes the bus name and its server
> has a bug, notifications stop system-wide and fail silently" assumed
> nothing else could answer. dunst ships
> `/usr/share/dbus-1/services/org.knopwob.dunst.service` — it is D-Bus
> **activatable**, so with the island killed the name reports as
> `(activatable)` and `notify-send` still succeeds, because the bus starts
> dunst on demand. Measured by killing the island and sending one.
>
> The real hazard is the opposite one and nobody had named it: an
> activated dunst HOLDS the name, and a later island start then runs,
> draws, answers IPC and never receives a notification. `island.sh` clears
> dunst before launching for that reason.
>
> **Two things this phase broke and had to fix in the same pass**, both of
> which were consequences rather than bugs: the control centre's
> Silent/DND row was on `dunstctl` and now reads the island's own
> `focusEnabled`; and the control centre's internal toasts had to stop
> going through the same path as bus notifications, or shell chrome would
> land in the user's notification history.
>
> **One design decision was reversed by the user mid-build.** Urgency was
> drawn as a coloured edge down the left of the capsule; it was rejected
> on sight, correctly — it adds a second element to a shape whose whole
> argument is that it is one shape. Urgency colours the existing icon
> instead, which costs no geometry, and the content is centred.

## Phase 2 — the original plan, for the record

1. **Decide the owner.** Recommended: the island serves the bus, dunst is
   removed from `autostart.conf`. The alternative — keep dunst and delete the
   island's notification UI — is cheaper and throws away three finished
   layers, the `notification` state and the arbitration logic.
2. **Serve it properly.** `SystemServices.notificationReceived` is three
   strings and cannot express dismiss, replace, urgency or actions. Use
   Quickshell's own notification server so the island gets ids, hints, urgency
   and action lists.
3. **Then build the three things a notification system needs and this one has
   never had**: dismiss (click, and a key), urgency styling (low/normal/
   critical must look different — critical must not auto-expire), and action
   buttons.
4. **Keep dunst installed but not autostarted** as the documented fallback for
   the window between login and the island loading — which is the role
   `submap-indicator.sh` already assigns it.

**The hazard, stated plainly:** if the island takes the bus name and its
server has a bug, notifications stop system-wide and fail silently — the same
shape of hazard as the polkit agent. Test with the island running *and* with
it killed, before dunst comes out of `autostart.conf`.

**Verified by:** `busctl --user` showing the island as the name owner;
`notify-send` at each urgency; a `notify-send -r` replace; an action button
round-trip; and one capture proving exactly **one** card on screen.

## Phase 3 — one interaction model (P0-3)

Every panel gets both inputs. The rule to adopt, because it is the only one
that survives contact with a keyboard-grabbing layer surface:

> **Keyboard is primary and complete. Mouse is complete for anything with a
> visible target. Hover always gives feedback. Focus and hover are two
> different states and both are drawn.**

1. **Hover states on the nine fork panels** — every selectable row, every tab,
   every button. Currently zero.
2. **Click-to-select and click-to-commit** on those same rows, mapping to the
   existing Enter path so there is one action and two ways in — the pattern
   `ConnectivityPanelLayer` already established for the Wi-Fi list.
3. **Wheel scrolling and a scroll indicator** on every `ListView`. There are 2
   `ScrollBar`s in 28,100 lines; a list that overflows must say so.
4. **Keyboard on the upstream panels** — the control centre (6 MouseAreas, 0
   keys) and the workspace overview (11 hover states, 0 keys). The control
   centre is on `$mod SHIFT A`, a *keyboard* binding, and then cannot be
   driven from the keyboard.
5. **`DisplayPanel` and `SystemMonitorPanel` first**, since they are at zero.

**Verified by:** driving each panel end to end with `wtype` — which is known
to work on these panels (they are ordinary Wayland clients with focus; only
the compositor bind that *opens* them cannot be synthesised) — and by clicking
through each with the pointer.

## Phase 4 — the design system (P1-5, P2-7, P2-9)

1. **Name the type ramp.** Five or six roles — `display`, `title`, `body`,
   `label`, `caption`, `mono` — mapped onto the sizes already in use, and
   `Metrics.font()` kept as the transform underneath. Then collapse 11 sizes
   onto the ramp; each collapse is a decision someone can review, where
   "`font(10)` because the line above said `font(10)`" is not.
2. **Snap spacing to a 4-px grid.** 15 values → 4/8/12/16/24/32. The odd
   numbers (1,3,5,13,18,50) are each either a deliberate optical correction —
   which should say so at the site — or an accident.
3. **Four radii, not sixteen**, matching the roles `StyleTokens` already
   names: panel, module, prompt, button.
4. **Fix `DisplayPanel`'s 8 raw `pixelSize` literals and its raw `24`.**
5. **Extract the shared components** that nine panels have each rebuilt:
   `PanelChrome` (header + body + hint footer, one name, one height),
   `PanelRow` (icon slot, label, detail, selected + hover states),
   `PanelTabs`, `KeyHint`. This is what shrinks `DynamicIslandWindow.qml`,
   and shrinking it is what stops P1-4 recurring.
6. **Pick one icon set** and use it for every icon. Nerd Font is already
   configured and already a hard dependency; the work is inventory and
   replacement, not a new package. Sweep the leftover upstream Chinese strings
   in the same pass.

## Phase 5 — the bezel (P1-6) and motion (P1-4)

1. **Screen corners.** Overlay layer, above fullscreen, `mask: Region {}` for
   input, one `PanelWindow` per screen through `Variants` — the shape
   `ThemeTransitionWindow` and `RingOsdWindow` already use. Radius should match
   the notch's own so the two read as one piece of bezel.
2. **Give the five swipe layers a real exit — one decision per layer, not one
   substitution five times.** See the correction under P1-4: these are not
   panels, they are swipe layers whose opacity is already driven by
   `transitionProgress`, so `PanelLoader` alone would cross-fade on top of a
   slide that is already running. Start with `WorkspaceLayer`, which is a
   plain cut when resting and is hit on every workspace switch; then decide,
   for each of the swipe pair, whether the slide or the fade owns the exit.
   The sixth raw `Loader` (`hyprlandIntegrationLoader`, line 86) is not a
   visual layer and is correctly a plain `Loader` — leave it.
3. **Re-audit the 17 deliberate raw easings** listed at the bottom of
   `Motion.js` — they were justified once and the list should be confirmed
   still true rather than inherited.

## Phase 6 — the two things left on the old list

1. **The polkit prompt** (`REQUIREMENTS.md` item 1's last row). Same hazard
   shape as Phase 2: a wrong agent means no password prompt anywhere on the
   system, failing silently until you need one. It must run alongside
   polkit-kde-agent and be proven before replacing it.
2. **Lock screen**: user avatar and name, and the soft top gradient behind the
   clock. Small, and it is the one surface a stranger sees.

## Phase 7 — search, once the system holds still (P2-8)

`/` opens a filter on any list panel; typing filters; Escape clears the filter
before it closes the panel. Wallpaper picker (362) and theme picker (22)
first. Deliberately last: a search field is a component, and it should be
built out of Phase 4's shared parts rather than being a tenth hand-rolled
input.

---

# Part 3 — what not to touch

Every one of these was measured, argued and paid for. They look like
inconsistencies and are not.

| decision | why it stays |
|---|---|
| `islandHeight` 28, not the spec's 38 | qtile's bar was the known-good daily driver for years; 38 was measured off a stranger's 2560×1440 screen |
| `SCALE = 0.92`, `FONT_SCALE = 1.0` | the panel scale and the notch scale are genuinely separate; type legibility is an absolute, not a ratio |
| the island fill follows the theme | direct user override of `DESIGN-SPEC.md`, with `darkenTowardBlack` 0.45 + `accentMix` 0.08 measured across four palettes |
| resting = clock + workspace + app pucks | user-requested divergence from the spec's clock + EQ |
| rofi keeps the `dm-*` launchers | `REQUIREMENTS.md` item 3: launchers are a list-and-pick problem rofi already solves |
| pixel geometry in `scratchpad.sh` / `sum-toggle.sh` | percentage rules are inert in static windowrules and on special workspaces |
| `r` in the wallpaper picker jumps but does not apply | navigation has no side effects; Enter is the only key that writes |
| the mode-keys panel takes no keyboard grab | the keys belong to the submap; a grab would swallow what the panel advertises |

---

# Part 4 — how each phase gets proved

This repo's standing rule, learned the hard way and worth restating at the top
of a UI plan: **a config that reloads cleanly is not a config that works.**
The failures in this codebase have almost all been silent — inert percentage
rules, a `ForkConfig` that was never instantiated, a `FileView` on a bare
`QtObject`, an unexpanded `$qsi`, five of twelve settings rows doing nothing.
Visual work fails the same way, because a wrong colour still renders.

So, per phase:

| phase | the measurement that decides it |
|---|---|
| 1 tokens | cycle ≥4 palettes, sample the framebuffer at named points; a token that does not move is not wired |
| 2 notifications | `busctl --user` name ownership; one capture proving exactly one card |
| 3 interaction | `wtype` through every panel; pointer through every panel |
| 4 system | grep counts go 11→6 sizes, 15→6 spacings, 16→4 radii, and `DynamicIslandWindow.qml` shrinks |
| 5 bezel/motion | corners visible over a real fullscreen window; `hyprctl activewindow` unchanged with the pointer over a corner; timed `grim` frames showing the OSD fading rather than cutting |
| 6 polkit | a real `pkexec` with the island's agent AND with it killed |
| 7 search | filter a 362-item list and commit from the filtered set |

Five environment facts that will otherwise cost a wrong conclusion. The last
three were each paid for during the Silent-row work, in one sitting.

- **`.pragma library` JS is cached by the running shell.** Editing
  `Metrics.js` or `Motion.js` and reloading changes nothing; the panel
  measuring the same as before is the only symptom. Restart the island.
- **A failed reload is survivable and therefore invisible.** A broken edit
  logs `Failed to load configuration` and the *previous* config keeps running,
  so "it still works" is not evidence that the edit loaded.
- **Read the log before believing a screenshot.** The fact above is not
  theoretical: a `readonly property` with a `Behavior` on it failed *every*
  reload for eight minutes while the desktop looked entirely normal, because
  the last good config was still running. Two screenshots were taken and
  reasoned about in that window and both were of stale pixels. The log is at
  `$XDG_RUNTIME_DIR/quickshell/by-id/<id>/log.log`, and the id is reachable
  through `by-pid/$(pgrep quickshell)`.
- **`sed -i` does not trigger a reload.** It writes a temp file and renames it
  into place, and quickshell's watcher — a `QFileSystemWatcher`, so an *inode*
  watch — is left pointing at the unlinked original. The edit is in the file
  and the shell never sees it, which reads exactly like "the change had no
  effect". This is the same inode trap `MIGRATION.md` records for
  `theme-apply`'s `mv`, arriving from the other direction. The Edit tool
  writes in place and is fine; after any `sed -i`, `touch shell.qml`.
- **A `Behavior` writes the property it animates**, so it cannot be attached
  to a `readonly property`. QML reports this as `Invalid property assignment`
  and fails the whole config load — not just that component — because the
  error propagates up through every enclosing type to `shell.qml`.

---

# Part 5 — decisions needed before Phase 2 starts

1. **Notifications: island or dunst?** Recommended: the island serves the bus
   and dunst comes out of `autostart.conf` but stays installed. The cheap
   alternative is to keep dunst and delete three finished island layers. This
   is the only choice in the plan that throws work away either way.
2. **Screen corners: yes?** They are in the spec and they are what completes
   the bezel argument, but they are also permanent furniture over every
   fullscreen video. The spec's author animates them away in "game mode";
   that would be a second feature.
3. **How far does theming go?** Phase 1 as written makes text, hairlines and
   selection follow the palette. The alternative reading of
   `DESIGN-SPEC.md` — theme the *contents*, keep the chrome neutral — is
   defensible and is half the work. The island fill decision already went the
   full-theming way, so this is a consistency question, not a fresh one.

---

## Sizing, honestly

Phase 1 is the largest single piece of mechanical work in the plan (288
replacements plus a token layer) and it is the one that makes every later
visual judgement meaningful. Phase 2 is the largest *risk* and the largest
visible win. Phase 5's second item — six `Loader`s — is an afternoon and
improves the two transitions you see hundreds of times a day. Phase 4 is
where the shell stops needing this document.

---

# Audit — 2026-08-13

Measured against the running shell, not inferred. What this session changed,
and what each phase actually stands at now.

## Phase 3 — one interaction model — **PARTIALLY DONE**

The control centre is done and was the worst offender: it is opened by
`$mod SHIFT A`, a keyboard binding, and had 6 MouseAreas and 0 Keys
handlers. It now has hover on every button, a keyboard cursor drawn
separately from hover, arrows **and hjkl**, Space/Enter to toggle, Right to
open a list, and Escape unwinding cursor -> drawer -> panel.

The cause of "the panels have Keys handlers that never fire" is found and
worth recording, because it is one mechanism and it defeated three panels:

> `islandContainer` is a **FocusScope**, and `keyPanelFocusTimer` calls
> `forceActiveFocus()` on it. A FocusScope hands active focus to ITS focus
> child and recurses. **14 of 20 PanelLoaders had no focus claim at all**, so
> the chain stopped at the scope and the layer one level below could never
> be reached. Fixed on the control centre, expanded player and notification
> centre, each bound to its own panel's visibility rather than a bare
> `true` — they are siblings in one scope and two are retained, so
> unconditional claims would leave the focus child decided by declaration
> order.

Escape/q now works on all three. The remaining 12 loaders are listed in the
commit; **`modeKeysLoader` must not get one** — Part 3 of this document
lists "the mode-keys panel takes no keyboard grab" under what not to touch.

Still open: hover states and click-to-commit on the nine fork panels, and
wheel scrolling with a visible indicator (still 2 ScrollBars in the tree).

## Phase 4 — the design system — **P2-9 CLOSED**

The upstream Chinese is gone. It was not only cosmetic: `lyricBaselineGuide`
is an `opacity: 0` Text reading `"Ag国"`, and Qt must SHAPE a glyph to
measure it — so three invisible characters mapped **NotoSansCJK at 27.6 MB**
into a shell that renders no CJK. Dropping the kanji is also more correct,
since the guide exists to stabilise the baseline of the Inter text actually
drawn there. Verified zero baseline shift by diffing the clock's ink rows.

The launcher's empty state genuinely read `没有找到` in daily use.

Type ramp, spacing grid and radius scale are untouched.

## Phase 5 — motion — **NOT STARTED**; the five dead fade-outs remain

## Phase 7 — search — **NOT STARTED**

## Corrections to this document's own method

Two findings this session were **wrong in a way worth naming**, both from
the same mistake — believing a capture over a measurement.

1. "The window border does not follow the theme" was reported from a
   framebuffer sample taken **inside the window** rather than on the 2 px
   border. The border had always followed. What was genuinely wrong is that
   it followed the CYAN slot while the island's layout glyph and workspace
   digit follow `accent` — so the two never agreed on any palette. Now the
   identical byte by construction, verified on five palettes.

2. "The settings panel receives no keyboard input" was filed as a task
   after three runs. The panel works. Every capture had been **cropped at
   ~420 px**, below which the selection had scrolled.

That second one has a cost attached and a rule that follows from it:

> **Do not test a settings panel by synthesising keystrokes into it.** Every
> press that lands is a write to the user's configuration; the ones that do
> not land make the result unreadable; and from a screenshot the two are
> indistinguishable. `wtype` drops events on rapid successive invocations,
> which is what made it look intermittent. Stray presses wrote
> `islandPositionX` 50 -> 70 — reported by the user as "the island is not in
> center" — and `clockFormat` 24 -> 12. Both reverted; the whole config was
> then audited against its session-start values. Test the schema over its
> CLI, which is fully covered, and let a human press the keys.

## Performance, measured — and the number not to act on

    CPU  0.8% of one core at rest
    RSS  482 MB      <- misleading
    PSS  162 MB
    Anon  87 MB      <- the real private cost

The largest mapping is Inter.ttc at 144.7 MB, a file-backed **shared**
mapping counted in full against every process that maps it. libLLVM and
libgallium are Mesa's. 87 MB private is unremarkable for a shell with this
many layers, and "reduce the RAM" against the RSS figure would have been
chasing a number that is not real.

**Layout switching, measured: 0.30-0.39 s**, and the cost is process
spawns, not the compositor — `layout-cycle.sh` makes **7 `hyprctl`
invocations per switch**, of which three are separate `hyprctl clients -j`
queries. Caching that query once and batching the dispatches through
`hyprctl --batch` is the fix; not attempted here rather than half-done.

The TreeTab sidebar **is live** — `quickshell-treetab`, 180x768, exclusive
zone working, confirmed in `hyprctl layers`.

---

# Audit — 2026-08-13, second session

## Swipe left — **FIXED**, and it was not a dead loader

The two IPC wrappers were each other's mirror: `swipeLeftWindow` called
`showLyricsCapsule` and `swipeRightWindow` called `showCustomCapsule`.
Three things in the tree already agreed on the direction and all three
disagreed with the wrappers — `advanceSideSwipeProgress` walks toward
custom on NEGATIVE deltaX, `sideSwipeDragDistanceForDirection` maps
`"left"`->custom, and SwipeCustomInfoLayer draws its items travelling
leftward into place. The config key is `dynamicIslandLeftSwipeItems` and
it feeds custom.

The inversion was invisible with a player running, because then both
layers have content and a mirrored pair is still a working pair. With no
player, `hasMediaSurface` is false, `normalizeRestingState` refuses
`"lyrics"`, and the left swipe resolved to the state the island was
already in. **No error, no log line, no movement.** The gesture path had
been guarded against exactly this at `resolveSideSwipeSettle`; the IPC
path is the same decision one level up and never was.

Replaced with one step along the custom(-1) - clock(0) - lyrics(+1) axis
that skips an empty layer. Measured over the full axis with a real MPRIS
player: 11096 px / 0 px (exact return) / 1011 px / 6 px (end-stop).

## Notification centre — **FIXED**, and the brief's guess was wrong

The cards did NOT carry raw pixelSize; they were already going through
`Metrics.font()`. Three real defects:

1. **Nothing in the file read `userConfig`**, so this was the one surface
   in the shell that ignored `bodyFontSize` — turning the shell's type
   down left this panel where it was. And the hardcoded sizes had no
   hierarchy: panel heading and card TITLE were both `font(15)` Bold.
   Now 15 heading / 12 title DemiBold / 11 body, from config.
2. **The 18/16 px line boxes are Latin measurements.** Reproduced with a
   real `notify-send` of al-Fatiha: the Arabic title rode over the card's
   top border and the body was cut off by its bottom one, because harakat
   sit above the ascender and below the baseline. Texts now take their
   natural `implicitHeight`; `cardHeight` derives from the type at 1.75x.
   Derived arithmetically, not probed — a hidden Text would SHAPE Arabic
   and map an Arabic face permanently, which is the `"Ag国"` mistake.
3. **The body was anchored to the card's bottom edge**, stranding the
   title against the ceiling on any notification with no distinct body.
   A vertically centred Column fixes it.

## The CJK unmapping — **REFUTED at cold start**

P2-9 claimed dropping the kanji would unmap NotoSansCJK. The island has
now cold-started and it is **still mapped**: 18 MB of address space,
**8.4 MB resident**, with zero CJK rendered anywhere — every remaining
CJK codepoint in the tree is inside a comment, and comments are never
shaped. So the mapping does not come from a shaped glyph and removing the
glyph did not remove it. Dropping the kanji was still right for the
reason that actually holds — measuring an Inter baseline with a CJK glyph
is measuring the wrong face — but the memory saving did not materialise
and the 27.6 MB figure should not be quoted again.

## Motion — **~800 ms, cause NOT found. Two hypotheses disproven.**

Measured with a 50 fps grim burst (20 ms/frame, PPM so the PNG encode
stays out of the sample rate). Control centre open, warm loader:

    settle 767-807 ms, reproducible across cold, second and third opens

Two candidate causes were tested and **both came back negative**, which is
the useful part of this entry:

| tried | result |
|---|---|
| `LARGE_MORPH_MS` 760 -> 520 (island restarted, it is `.pragma library`) | 787 ms -> 801 ms. Within noise, wrong direction. Reverted. |
| `sliderIntroDelay` gate closing on data instead of a 400 ms clock | 806 ms -> 804 ms. Kept anyway — it is a real correctness fix — but it is not the cure. |
| loader building cold | second and third opens measure the same |

What is actually still moving came out of **differencing two frames either
side of the tail** rather than measuring the tail's magnitude: between
+560 ms and +1080 ms the **entire content block below the clock shifts
~17 px vertically**, on every open. The clock and battery row do not move;
everything below them does. That shift owns the number and is unexplained.
`controlCenterMaximumExtraHeight` is composed of constants and its
null-loader fallback of 120 only applies before the item exists, so it is
not that either.

### A method failure worth more than the result

The first three runs measured a ~790 ms settle that was **the terminal
behind the island still repainting** from the `echo` that announced the
test. The capture region included it. Differencing two frames showed the
transcript text doubled and offset by one line, which is what exposed it.

> A capture region must contain nothing but the thing under test, and the
> console must be quiet before sampling starts. "Measure, don't
> screenshot-and-infer" is not enough on its own — a *measurement* of the
> wrong region is just as confidently wrong as a screenshot, and it comes
> with a number attached, which makes it more persuasive and therefore
> worse.

And the positive lesson: **difference two frames, do not just count
changed pixels.** Every one of the three real findings in this section —
the terminal contamination, the slider still travelling, the 17 px block
shift — was invisible in the magnitude curve and obvious in the diff.

## Keybind latency

Every island binding spawns a fresh `qs ... ipc call` process: **~50 ms
round trip**, measured five times. That is before any animation starts and
is paid on every panel open from the keyboard.

## Still not started

Second monitor; the remaining four fade-outs (P1-4); full settings
coverage for the island; Phase 3 leftovers (hover and click-to-commit on
the nine fork panels, wheel scrolling); Phase 4 (type ramp, 4 px spacing
grid, radius scale); the theme-change transition, which is serial —
capture, then `theme-apply` at ~622 ms, then a 620 ms wipe — and so
cannot be under ~1.2 s as currently sequenced.

## Second monitor — **VERIFIED, no defects**

Tested live with `hyprctl output create headless` (1920x1080 beside the
1366x768 panel), then removed.

All four surfaces are per-output by construction — `Variants { model:
Quickshell.screens }` for `panelVariants`, `ringOsdVariants`,
`treeTabVariants` and `themeTransitionVariants`, each passing `screen:
modelData` and an `outputName` down.

Measured rather than assumed:

    resting              eDP-1 1366x58   HEADLESS-1 1920x58
    control centre open  eDP-1 1366x463  HEADLESS-1 1920x58
    closed               eDP-1 1366x58   HEADLESS-1 1920x58

So the island exists on both outputs and sizes itself to each, and
`monitorFocused` correctly confines an opened panel to the focused screen
rather than opening it twice.

TreeTabSidebar gates on `layoutIsTreeTab && monitorFocused && rowCount > 0`
and its exclusive zone is `panelWidth * revealProgress` per instance, so
the 180 px reservation is per-output and animated rather than a constant
claimed on every screen.

## P1-4 — **CLOSED. The layers decided it, not a sweep.**

The remaining four were `customSwipeLoader`, `lyricsSwipeLoader`,
`splitIconLoader` and `osdLayerLoader`. The per-layer decision P1-4 asked
for turns out to be written inside the layers themselves:

    opacity: showCondition ? revealProgress : 0
    revealProgress: slideDirection === "none" ? 1 : (1 - clampedProgress)
    Behavior on opacity { enabled: slideDirection === "none" }

**The Behavior is enabled only when there is no slide.** So the question
is not per file, it is per case, and both cases are already separated:

- `slideDirection` "left"/"right" — the layer arrived on a swipe,
  `revealProgress` IS the slide, the Behavior is disabled. The slide owns
  the exit. Adding a cross-fade here is precisely what P1-4 warns against.
- `slideDirection` "none" — `revealProgress` is the constant 1, opacity is
  purely `showCondition`, the Behavior is enabled. The fade owns the exit
  — and could never run, because `showCondition` was the literal `true`.

So `splitIconLoader` and `osdLayerLoader` are the WorkspaceLayer bug again,
confined to the no-slide case, and the swipe case is protected by the
layer's own guard rather than by us remembering to be careful. Both are now
`PanelLoader` with `showCondition: <loader>.live`.

**`customSwipeLoader` and `lyricsSwipeLoader` need no change at all**, and
this is the finding worth keeping: their `active` predicates are on
`swipeTransitionProgress` — the *animated* property — so they already
outlive their own slide by construction. `lyricsSwipeVisible` is `>= 0`
rather than `> 0` because that layer also draws the resting clock, so it
is mounted at rest and never has an exit to run.

Measured, `showText` then `clearText`, 50 fps burst on the island strip:

    changed px/frame: 152 153 134 111 77 42 0   over ~170 ms

A cut is one frame with a large delta and then zero. A monotonically
decaying ramp over six frames is a fade. It runs.

## Theme change — **MEASURED. 1.77 s of dead screen, and the 622 ms in this document is stale.**

Measured end to end through the real path (`tide applyThemeAnimated`), 50 fps
burst, re-applying the theme ALREADY active so nothing about the user's
palette changed — `~/.cache/tide-island/colors.json` reported
`"theme": "catppuccin"` before and after:

       0 -  239 ms   nothing (IPC spawn, then grim's capture)
     239 -  408 ms   the frozen frame goes up
     408 - 2180 ms   ZERO CHANGE. 1.77 s, pixel-diff exactly 0.
    2180 - 2320 ms   the wipe crosses this region
    2373 ms          settled

**This document's "622 ms, measured by running theme-apply bare" is wrong
now.** Timed directly, three runs: **3385 ms, 3232 ms, 7461 ms.** The
variance is as important as the size — a theme change is not a fixed cost.

The island's gating is **already correct** and should not be touched:
`ThemeTransitionWindow` watches stdout for `THEME_APPLY_VISIBLE_DONE`
rather than waiting for the process to exit, which is what keeps the freeze
at 1.77 s instead of 3.2-7.5 s. theme-apply's own header block explains
why, and predicted this exact failure mode — "the user spent the difference
looking at a screenshot with a pixel-diff of exactly 0.00 between
consecutive frames". The marker fixed two thirds of it. The remaining
1.77 s is the same complaint, smaller.

Where the remaining time goes, from theme-apply's own breakdown of what is
BEHIND the marker:

    kitty set-colors + SIGUSR1  0.86 s
    dunstrc + dunst restart     1.10 s
    GTK overlay css             1.14 s
    qutebrowser :config-source  1.27 s   (detached)

**`dunst` is the interesting line.** The island serves
`org.freedesktop.Notifications` itself and `island.sh` does `pkill -x dunst`
before starting, so under Hyprland dunst is NOT RUNNING — the wipe is
waiting ~0.24 s on a restart of a daemon this session deliberately killed.
That is free to reclaim, but the fix is in `theme-apply`, which lives in
`/usr/local/bin` from AtiScriptsV1 and is SHARED WITH THE QTILE SESSION,
where dunst is real. So it needs a session test, not an unconditional cut,
and it is not a change to make from this repo without one.

The other direction, and the one that is in this repo: 1.77 s of a frozen
screenshot with no feedback of any kind reads as a hang. Whatever the
script costs, the overlay should not be blank while it runs.

---

# Phase 8 — a full settings APP (requested 2026-08-13)

> "a full detailed customizable app for settings for the island … like the
> app tide island settings but more professional and more detailed"

## Why this is not just a bigger SettingsLayer

The in-island panel cannot grow into this, and the reason is structural
rather than effort. `island-settings.py` records it already: there is no
`string` type because **SettingsLayer has no keyboard-entry field**, and it
cannot have one, because the panel lives under a Hyprland keyboard grab —
a text field there would swallow the next character you type into your
window. That single constraint is why the four font families, both
wallpaper paths, the custom wallpaper command and the nine wallpaper
transition parameters have no rows.

So the app is not a duplicate of the panel. **It is the client that can
cover the keys the panel structurally cannot**: 43 keys are read by the
QML, 25 have rows, and most of the missing 18 are missing for exactly this
reason.

## The architecture that keeps one source of truth

`island-settings.py` stays the only thing that writes config. It already
has the whole contract:

    --list    JSON: descriptors + current values + warnings
    --set     one key, atomically, typed and validated
    --check   validate the schema itself

The app is a **GUI client of that CLI**, exactly as SettingsLayer is. No
second writer, no second copy of the defaults, no drift. Anything the app
needs that the schema cannot express is a schema change first.

## The schema work that comes first

1. **A `panel` field on every row** — whether the in-island panel can render
   it. This is what makes the next item safe: adding a `string` row today
   would put an inert row in SettingsLayer, which is the exact failure the
   whole schema exists to prevent. With the flag, SettingsLayer filters and
   the app does not.
2. **New types**: `string`, `path`, `font`.
3. **`font` must validate with fc-match.** A bad family name does NOT fail
   — it falls back silently, and on this machine it falls back to Noto Sans
   CJK KR, confirmed against a deliberately bogus name. So the check is
   that the REQUESTED family appears in what `fc-match` returns, not that
   fc-match succeeded, because it always succeeds.
4. **`tlpSudoPassword` still gets no row**, in the app either.

## What the app should have that the panel does not

Search across key, label and detail; grouped categories rather than one
flat list of 40+; the `detail` prose shown as help rather than hidden;
live preview where it is cheap (sizes, opacity, position); reset-to-default
per row; and a visible diff of what differs from the packaged defaults.

## Toolkit

Recommend **GTK4 + PyGObject**, not QML. The app's whole reason to exist is
the capabilities the layer-shell panel lacks — real text entry, real
window management, real scrolling, a file chooser for the wallpaper paths,
a font chooser for the four families — and those are free in GTK and hand-
built in QML. It also keeps it in the same language as the schema it
drives, so the descriptor types are defined once in Python.

## P1-5 / Phase 4 — **the premise was mostly wrong, measured**

This document calls the type and radius numbers "inventories, not systems"
and sets 11 -> 6 sizes, 16 -> 4 radii. Counted across the tree before
changing anything:

    font sizes   151 uses, 10 distinct     143 already go through font()
    radii         64 uses, 18 distinct      55 already go through px()

**The funnel already exists.** What is missing is names for the steps. And
the steps are already there: 145 of the 151 type uses fall in 9..15 — six
values — with the other six being 18/19/24/29, which are display sizes and
legitimately off the body ramp.

Two things that look like the bug this phase describes and are not:

1. **All 8 raw `font.pixelSize: N` literals are in DisplayPanel.qml**, which
   does not import Metrics at all and says so: it sizes everything with
   literals, and mixing one scaled dimension into an unscaled panel would
   put that element out of step with the header around it. Internally
   consistent, not a miss. Captured beside AudioPanel — which uses Metrics
   35 times — the two are indistinguishable in type size.

2. **`FONT_SCALE` is 1.0, so `font(n)` is the identity above 9.** Every
   `Metrics.font(11)` evaluates to exactly 11, the same number DisplayPanel
   writes directly. The type system has no mechanical effect today. It is a
   naming convention and one place to change later — worth having, not worth
   pretending is more.

   That is also why point 1 is invisible: there is nothing to see, because
   the two paths compute the same number.

The remaining raw radii are `0` and `1`; `px(0)` is 0 and `px(1)` is floored
at 1, so routing them through `px()` is churn that provably cannot move a
pixel.

**What was done:** `TYPE`, `DISPLAY` and `RADIUS` are now named in
Metrics.js, set to the values already in use, so adopting one is a no-op by
construction. **Not applied over the 198 existing call sites** — that is a
large diff whose only verification is "every panel still looks right", which
is the class of change that produced two wrong conclusions earlier in this
same session.

**What is left, and it is a decision rather than work:** whether
DisplayPanel should join the scale. Converting it means every literal in the
file, not the 8 type ones — `horizontalPadding` 18, `headerHeight` 34, the
ring at 26 — and at SCALE 0.92 that shrinks the panel ~8%. It is a visible
change to one panel that currently looks correct, so it wants an explicit
yes rather than being swept in.

## P1-3 interaction — **CLOSED**, and the grep that suggested it was open was misleading

Audited all nine fork panels. `containsMouse` appears **zero** times across
every one of them, which reads like nine panels with no hover states. It is
not, and the reason is the model this shell settled on:

> **Hover moves the CURSOR.** One selection indicator, driven by both the
> keyboard and the pointer, rather than a hover highlight sitting beside a
> separate selection. So `onEntered: setCursor(index)` is the hover state,
> and `containsMouse` is absent because nothing needs a second visual.

WifiPanel, BluetoothPanel, AudioPanel, PickerLayer, ThemePickerLayer and
SettingsLayer already did this. Two did not, and they were the two with
**zero MouseAreas** — pointer could not reach them at all:

  DisplayPanel   now hovers to move the cursor and clicks to activate. The
                 two destructive views, a mode change and a layout restore,
                 are the same call `Enter` already made and both already run
                 behind the revert countdown `revertRing` draws, so a click
                 cannot commit anything the panel does not offer to undo.

  SystemMonitorPanel  hovers to move the cursor. NO click handler: the
                 selection is the whole interaction, and a click that did
                 what the hover already did would imply an action that does
                 not exist.

CheatsheetLayer keeps none — it has a delegate but no `selectedIndex`, so
there is nothing to select; it is reference text.

Found while wiring sysmon: `selectedIndex` and `selectedMount` are one
selection written as two, in three places. `reanchorSelection` uses the
MOUNT to keep the cursor on the same filesystem across a poll, so an index
moved without it re-anchors to the wrong row on the next refresh. Adding the
pointer as a fourth writer is what made one `selectAt()` worth having.

## Phase 3.4 — the workspace overview — **CLOSED, and every one of its keys had been inert**

P0-3 counts `WorkspaceOverviewLayer.qml` at 11 hover states and **0 Keys
handlers**. The symptom was real and the location was wrong: a handler
existed, in `DynamicIslandWindow.qml`, covering h/j/k/l and Tab/Shift-Tab.
It had never worked.

**One cause for all six.** They dispatched a workspace change while the
overview was still on screen, and the compositor accepts that silently.
Measured with the control that settles it:

    overview OPEN    hyprctl dispatch workspace 5  ->  "ok", stays on 4
    overview CLOSED  hyprctl dispatch workspace 5  ->  moves 4 -> 5 -> 4

So it is not the island's dispatcher — an external `hyprctl` is blocked
too. `dispatchExpression` compounded it by returning `true` for "we sent
it" rather than "it happened", so nothing anywhere reported a failure.

`closeAndFocusWorkspace` is the path that always worked and is what
**clicking a tile has always used**: set the pending id, close, let
`deferredWorkspaceFocusTimer` focus once the surface is down. All six keys
route through it now, which is Phase 3's "one action, two ways in" exactly.

An arrow therefore COMMITS rather than browses. Not a compromise — the
compositor will not let the workspace change underneath this surface, so
there is no browse state available to offer.

**A wrong instinct, twice in one fix, worth recording.** The first pass
kept Tab/Shift-Tab in place on the assumption that `r+1`/`r-1` were
RELATIVE dispatches and so exempt from the block. They are not: Tab left
the workspace on 4 with the overview still up. The block is on the switch,
not on how the target is spelled.

`focusAdjacentWorkspace` was **deleted**, not kept. A correct-looking
helper that silently does nothing is the exact failure this tree keeps
paying for.

Escape and `q` are new — the old handler had neither, so the only way out
was the pointer or pressing the opening chord again. Measured, all six:

    Right 4->5   Left 5->4   Down 4->9   Up 9->4   Tab 4->5   S-Tab 5->4
    Escape/q     close, workspace unchanged

Also fixed on the way: the focus chain. The window already took an
Exclusive grab for the overview (it always did), but `focus:` only
NOMINATES a focus child — something must walk the chain, and
`keyPanelFocusTimer` is restarted for three panels and not for this one.
The scene claims focus from its own `onShowConditionChanged`, which is
what NotificationCenterLayer settled on, because the item exists by
definition at the moment its own handler runs.

## Phase 7 — search — **STARTED. Wallpaper picker done; it is type-to-jump, not a filter.**

`Key_Slash` appeared nowhere in the tree. The wallpaper picker (362 items)
and the theme picker (22) were the two the plan named, and both genuinely
had no search — PickerLayer, the launcher and the cheatsheet already have
fields, so those were never the gap.

**The plan specifies a filter and a filter is the wrong mechanism in this
panel**, for a reason specific to it rather than a preference:
`allWallpapers` is a ListModel carrying per-item thumbnail state
(`thumbnailReady`, `thumbnailSource`, `cacheRevision`) and
`wallpaperIndexByPath` maps a path to its INDEX in that model. Rebuilding
it to show a subset invalidates every index and discards the
generated-thumbnail bookkeeping — a filter would cost a re-scan per
keystroke.

Type-to-jump moves the cursor and touches nothing. It is also the right
idiom for a PathView: a filtered carousel is a different component, not a
smaller one. And it preserves this panel's standing rule, already in Part 3
— navigation has no side effects, Enter is the only key that writes.

`/` opens it, letters narrow, Backspace widens, Up/Down walk between
matches, Escape unwinds query-then-panel, Enter commits and exits. The
query and the MATCH COUNT are both drawn, and both are load-bearing: a
type-to-jump search with nothing on screen is indistinguishable from a
stuck keyboard, and the count is what separates "no such wallpaper" from
"you typo'd".

Search mode is a separate branch ahead of the switch rather than extra
cases in it, because **every navigation key in this panel is a letter** —
`h`, `l`, `r`, `q` are all things you type into a filename, so typing
"roses" would otherwise re-roll on the `r` and walk the carousel on the
`s`.

Measured, with the wallpaper config value checked before and after to
prove nothing was written:

    /0234   ->  · 234 / 362   "1 match"    carousel on 0234.jpg
    /zzzz   ->  · 1 / 362     "0 matches"  in red, cursor held
    backspace x4 then /0099 -> · 99 / 362  "1 match"

362 items reached in five keystrokes instead of 233 presses of `l`.

**Still open in Phase 7:** the theme picker (22 items, a GridView rather
than a carousel, so a real filter IS appropriate there), and the font
picker the settings app needs.

---

# Audit — 2026-08-14, the restyle session

Job B, done as P2-7 rather than beside it. What follows is measured, not
inferred, and is written so none of it is re-derived.

## The four components — and the count that justified them

`PanelChrome`, `PanelRow`, `PanelTabs`, `KeyHint` in `qml/common/`. Counted
before choosing anything:

    the key-hint footer   9 panels, TWO property names (hintHeight x5,
                          footerHeight x4), FOUR heights, TWO colours,
                          THREE bottom margins
    the header height     pad(34) x6, pad(36) x2, pad(38) x1, raw 34 x1
    the content inset     pad(18) x9, raw 18 x1

All of that is now `Metrics.chromeTotal()` and friends. **Ten surfaces
converted**: control centre, Wi-Fi, Bluetooth, audio, system monitor, display,
settings, power, calendar, picker, theme picker.

## The header register — one of two, and the reason is not taste

The tree had two, cleanly split:

  A. hero        heroFontFamily, font(15), DemiBold, `color: "white"`
                 — Audio, Settings, Calendar, Power, Display
  B. instrument  textFontFamily, font(10), DemiBold, AllUppercase,
                 letterSpacing 1.6, textMuted, plus an accent-when-live
                 status clause — Wi-Fi, Bluetooth, System monitor

**B wins because A cannot compose with a panel whose header is its own
content** — the control centre's header is a hero battery number and register
A puts a window title exactly where that number goes — and because A's colour
is the literal `"white"`, which on `mono-light` is the wrong ink.

## One vocabulary for position, and it came out of WifiPanel

    accent EDGE  = "you are here"       PanelRow's leading bar, PanelTabs'
                                        sliding underline
    accent WASH  = "this is true of     the connected network, the default
                    the system"          sink, the arrange pick
    danger fill  = "the next keystroke   PanelMenu's armed row
                    does something you
                    cannot undo"

That is WifiPanel's own rule promoted: *"if the cursor used the accent too,
moving it would look like connecting."* Four panels were violating it by using
`IslandTheme.selectionFill` — the accent wash — for a plain cursor.

## `color: "white"` — 29 of them, and it was a real defect

Across 19 files. On `mono-light`, the one palette of 21 whose surface lands on
the light side of IslandTheme's 0.18 threshold, white is the wrong ink, and
the island's fill FOLLOWS THE THEME by the user's explicit override of
DESIGN-SPEC.md. All 29 are roles now.

**Four files referenced `IslandTheme` without importing `"../common"`** —
ClockLayer, WorkspaceLayer, SplitIconLayer, SwipeDatePreviewLayer, i.e. the
resting clock, the workspace digit and the layout glyph. Caught by grepping
every file that mentions the singleton for the import *before* restarting.

## RADIUS was already concentric and nobody had noticed

    panel shell   px(28)  = 26
    minus padX    pad(18) = 18
    ------------------------------
    inner card              8      == RADIUS.card, exactly
    minus a chip's pad(4) = 4
    ------------------------------
    chip                    4      == RADIUS.tight, exactly

The table is not a proposal laid over the tree; it is what concentricity
derives from padding nine panels already agreed on.

## Bugs found that the code could not show

1. **`Repeater.itemAt()` is not bindable.** PanelTabs' indicator read its
   geometry through it and drew NOTHING — no error, no warning. The binding
   evaluated once at construction against a Repeater with no delegates and
   never re-ran. Same shape as the Keys handlers that never fired: right about
   what it wants, wrong about when it runs. The delegate pushes now.
2. **A rule drawn through a caption.** The control centre added px(8) of
   header air to its own Column's `y`, so the chrome centred its header rule
   in a gap it could not see and put it inside "THU, AUG 13". That air is
   `PanelChrome.bodyOffset` now.
3. **Two undefined bindings with no visible symptom.** AudioPanel never
   rendered standalone and declares neither `drawBackground` nor `panelFill`;
   binding them assigned undefined to a colour and a bool. Log only.

## Phase 7 — CLOSED. The theme picker got a real filter.

And the reason it is a filter here and type-to-jump in the wallpaper picker is
specific rather than a preference: `themes` is a plain array with no per-item
cache state and nothing keyed by index, it is a GridView (a grid of 3 is just
a smaller grid; a carousel of 3 is a different component), and it is 22 items.

The panel does NOT shrink while you type — sized from the unfiltered count, so
the query line stays under your eyes. Measured: `/mono` -> 3 of 22 accented,
`/zzz` -> 0 of 22 in red with the frame unmoved, Escape -> all 22 back.

## P1-6 screen corners — CLOSED, and the hide cost nothing

User's call: build them, hidden over fullscreen. **No fullscreen-state
tracking was needed.** Hyprland draws a fullscreen window above Top and below
Overlay, which is already the mechanism behind the island's own
`islandRestingSurface` rule. The corners are on Top and the compositor hides
them — so the bezel appears and disappears as ONE piece.

Two things measured:

    surface came up 1366x735 at y=33   the island's exclusive zone; fixed with
                                       exclusionMode: Ignore. Writing
                                       `exclusiveZone: 0` alongside it SILENTLY
                                       UNDID the fix — assigning exclusiveZone
                                       at all forces Normal mode
    corner pixel, normal    (15,25,32) the shell fill
    corner pixel, fullscreen (20,20,19) the window underneath
    corner pixel, restored  (15,25,32) byte-identical

Input mask proven through the compositor: with focus_follows_mouse, the
pointer at (6,6) — inside a painted corner — still activates the window
underneath.

## Motion.js — re-audited, and three claims were wrong

  * **The count was 17 and is 16.** The seventeenth entry was SwipeCavaBars,
    which the list itself describes as converted TO the spring.
  * **FavoriteStar's reason was wrong**, its conclusion right. "The overshoot
    is already authored into the keyframes" — there is no overshoot; the legs
    are 1->0.9, 0.9->1, 0.5->1, 1->0.5, 0->1, 1->0. The real reason is that
    they are scripted legs of a SequentialAnimation, which is the rule that
    actually separates the 16 from the 49 that were converted.
  * **osdProgress's easing.type is dead code.** SmoothedAnimation solves its
    own velocity-limited trajectory. Measured: two SmoothedAnimations
    differing only in easing type produce byte-identical trajectories, and the
    same harness on a plain NumberAnimation reports them different — which is
    the control that makes the first result mean anything.

## Lock screen (Phase 6.2) — avatar, username, top gradient

**The nested-compositor rule earned itself.** Four failures in a row, three of
them config errors invisible to `hyprctl configerrors`, and one that was not a
config error at all:

    shape { color = <gradient> }  shape takes a FLAT colour
    image { size = W, H }         size is ONE int
    image { size = 100% }         rejected
    `size` IS THE WIDTH           an 8x1024 source at size 2400 asked for a
                                  2400x307200 texture, the framebuffer failed,
                                  and HYPRLOCK EXITED — on a real session, a
                                  lock screen that dies at the instant you lock

Also: `-font "Inter-SemiBold"` resolves to Inter **Regular** and fc-match
reports success. Settled by ink coverage, not by fc-match.

**Not verified, and stated as such:** the gradient's on-screen HEIGHT. Every
nested lock screenshots a different desktop, so an A/B against a no-gradient
run showed darkening even where the image is fully transparent. 420 px is
arithmetic from a measured aspect ratio, not a measured distance.

## Still open

  * **The ~800 ms panel settle.** Untouched by this session and NOT to be
    assumed fixed by it: the control centre's layout changed, so the ~17 px
    content shift needs re-measuring before anything is concluded.
  * **The theme change's 1.77 s freeze**, unchanged — the remaining win is in
    `theme-apply`, shared with the qtile session.
  * **Font rows in the in-island panel.** The GTK app already has them
    (`Gtk.FontDialog`, four families, marked app-only). The island panel does
    not, because `PANEL_TYPES` derives `panel` from the type and `font` is
    excluded — the panel has no text entry under a keyboard grab. The theme
    picker's filter now makes a text-entry-free font picker POSSIBLE, which
    would mean adding `font` to `PANEL_TYPES`. That is an architectural
    decision, not a task.

## A method note that cost a theme

The theme picker was left open on the live screen between commands and the
desktop theme changed twice while it was up. Verified NOT to be the code —
with the panel open and no input the theme is stable for 15 s. It was pointer
clicks on a panel this session had opened. Restored to oxocarbon.

> **Close a panel that commits on click before leaving it on screen.** The
> existing rule covers synthesised keystrokes into a settings panel; this is
> the same hazard reached with the mouse and nobody had written it down.

And twice, `pkill -f <pattern>` matched its own command line and killed the
shell running it — once taking the island down for ~90 s because the restart
line never ran. `pkill -x` on the process name, or the pattern in brackets.

---

# Audit — 2026-08-14, the reference repo

## Ask #6's reference repo is this fork's own upstream

`enhaoswen/Dynamic-island-on-hyprland` is not a second, more polished island
to catch up to. It is **the former name of `enhaoswen/Tide-island`** — the
repo this fork is vendored from. Cloning the URL in the ask lands on a README
titled "Tide Island" whose own badges and release links point at
`enhaoswen/Tide-island`.

So the ask as written — "get the UI/UX up to the reference repo's polish" —
has no gap to close in the direction it assumes. Measured:

    vendored / installed   tide-island 1.0.34-1   (/usr/share/tide-island)
    reference clone HEAD   1.0.35                 (PKGBUILD pkgver)

One patch release apart. And the fork is the larger tree:

    qml files, reference   57
    qml files, fork        67
    fork-only              29 files
    reference-only          3 files (qml/connectivity/{BluetoothDeviceRow,
                             ConnectivityDetailPanel,ConnectivityDetailShell})

The three reference-only files are not missing features — the fork deleted
them when it wrote its own `connectivity/WifiPanel.qml` and
`connectivity/BluetoothPanel.qml`.

## What 1.0.34 → 1.0.35 actually contains

Diffed the *vendored baseline* against the reference clone rather than the
fork against the reference, because that isolates upstream's changes from
three sessions of deliberate divergence. Exactly two files differ:

**1. `DynamicIslandWindow.qml`, two hunks.**

  * `islandShowWorkspaceOnAutoHide` — a new config flag that reveals an
    auto-hidden island on workspace change. **The sentence that was here was
    wrong** and is corrected below under "the inert row"; the fork's schema
    DOES carry this key, with a row in both clients. What it lacks is a
    reader, because the property is compiled into upstream's backend and the
    installed package is a release behind.
  * the notification-centre corner radius, `targetHeight * 40 / 165` →
    `targetHeight * 36 / 165`. **Do not take this.** `faa424f` removed the
    proportionality entirely, because a radius derived from panel height grows
    with the notification count until the footer sits beside bare desktop.
    Upstream adjusted the constant and kept the bug. This is the clearest
    evidence in the diff that the fork is ahead, not behind.

**2. `WallpaperPickerLayer.qml` — a search filter.**

Upstream added `/`-to-search with a collapsible search bar. Phase 7 in this
document gave the wallpaper picker type-to-jump instead, and rejected a
filter for a specific measured reason: `allWallpapers` carries per-item
thumbnail state and `wallpaperIndexByPath` maps path → index into it, so
rebuilding the model for a subset invalidates the thumbnail bookkeeping.

**Upstream's implementation is the receipt for that prediction.** To make the
filter work it had to add a second `ListModel` (`filteredWallpapers`), a
second index map (`filteredIndexByPath`), a `syncFilteredEntry()` that
re-mirrors an item on every scan callback, a manual index-shift loop on
removal, and a duplicate four-property write into the filtered model inside
the thumbnail-finished handler:

    filteredWallpapers.setProperty(filteredIdx, "thumbnailReady", true);
    filteredWallpapers.setProperty(filteredIdx, "thumbnailRequested", true);
    filteredWallpapers.setProperty(filteredIdx, "thumbnailSource", ...);
    filteredWallpapers.setProperty(filteredIdx, "cacheRevision", revision);

That is two descriptions of one list, which is the same failure shape as the
"one layout, one arithmetic" rule. Not ported. Phase 7's remaining item is
the theme picker, and that one is a GridView where a filter is correct.

## What this means for ask #6

There is no upstream polish to import. If the island is to look better than
it does, the standard is the user's eye and this document's own audits, not a
reference tree — the reference tree is 57 files of what this fork already
vendored, one release stale, carrying a radius bug the fork has fixed.

The one thing worth taking from 1.0.35 is `islandShowWorkspaceOnAutoHide`,
and only if auto-hide is a mode the user actually runs.

---

# Audit — 2026-08-14, per-theme wallpapers and the freeze

## Ask #5 — the library could not have supplied these, and that is measured

`wal-precompile` had already written bg / bg_alt / fg / six accents for each
of the 362 wallpapers into `~/.cache/qtile/palettes/NNNN.json`. Scoring
every image against every theme in CIELAB — weighted `1.00*d_bg +
0.60*d_accent + 0.25*d_fg`, background dominant because it is most of the
screen — gives the best the library can do per theme:

    good (<=20)   oxocarbon 6.6, github-dark 6.8, ayu-mirage 11.4,
                  doomone 13.0, monokai 13.9, gruvbox 15.3,
                  tokyonight 16.3, onedark 17.0, kanagawa 17.6,
                  synthwave 17.8, nightowl 18.1, dracula 19.6
    weak (20-30)  cyberpunk-neon 20.5, nord 24.4, catppuccin 25.6,
                  mono-dark 25.6, rose-pine 26.1, palenight 26.1,
                  everforest 29.3
    impossible    matrix 38.8, mono-light 137.9

mono-light's 137.9 is 90.7 of BACKGROUND distance alone. The library is 362
dark wallpapers; mono-light's background is `#ffffff`. There is no ranking
of a set with no light images that produces a light image. matrix fails the
same way on foreground (108.3): nothing in the library is `#00ff41`.

So nine of twenty-one cannot be served by selection at any quality. Downloads
were checked and rejected too — the best collection found
(`yukazakiri/themed-wallpapers`, 1100+ images, ~1 GB, itself generated with
`gowall`) covers 22 palettes but only 12 of these 21 by name.

The generator is `AtiScriptsV1/theme-wallpaper-gen`; the runtime half is
`AtiScriptsV1/theme-wallpaper`, called by theme-apply after the visible-done
marker and by wallpaper-set.sh on a manual pick. Full reasoning lives in
those two headers and is not repeated here.

## Three things only the contact sheet could show

Every intermediate version passed its numeric checks. All three defects were
found by tiling the 21 outputs with labels and looking at them.

  * **the ramp must be uniform in LIGHTNESS**, not along the neutral chain.
    gruvbox's bg and bg_alt are five points apart with fg 76 above, so
    by-segment spacing starves the range the theme actually uses.
  * **accent knots must be damped** toward the grey of their own lightness.
    At full strength dracula's mountains grew a purple halo and
    cyberpunk-neon's clouds went solid cyan.
  * **damping must be toward the SAME-LIGHTNESS grey**, not the ramp's ends.
    Mixing navy to white in Lab passes through purple, which gave mono-light
    lavender trees — an off-palette colour in a themed wallpaper, which is
    the single defect the whole feature exists to prevent.

## A measurement artifact that replaced a working implementation

Recorded because it is the most expensive mistake of the session and it
would have been invisible in the result.

`-remap` appeared to darken every image: 0316.jpg read 70% mean luminance in
and 40% out. A cause was found and it was a good one — nearest-colour
matching against a neutral palette minimises RGB distance, and the grey
nearest a pixel is its channel AVERAGE, not its luma, so green foliage lands
too dark. Sound reasoning. Not what was happening.

    magick colour.jpg -colorspace Gray -format %[fx:mean] info:  -> 0.70
    magick colour.jpg -colorspace Gray  grey.png
    magick grey.png                -format %[fx:mean] info:      -> 0.40

The same conversion read two ways: Gray is linear in memory and gamma-encoded
on disk, so a colour input measured through that pipeline reads ~30 points
above a grey one. Re-measured with Rec709 luma over encoded sRGB channel
means, applied identically to both: base 40.2, old remap 40.3, gradient map
34.5. **The remap had never darkened anything.**

The gradient map was kept, because the reasons that survive measurement are
enough on their own — continuous tone instead of 14 flat colours, no dither
noise, and the accent landing at its own lightness by construction.

> If a metric is applied to two things, first run it on two things KNOWN to
> be equal.

## The theme-change freeze — 0.24 s of it was a daemon that does not run

`theme-apply` killed dunst, slept 0.2 s and started it, unconditionally, on
every theme change. That is a restart on qtile. On Hyprland it is not: dunst
has not run there since the island took over notifications, and `busctl
--user list` shows quickshell's pid against `org.freedesktop.Notifications`.
So the block was spending 0.24 s of the FROZEN window launching a daemon
that either failed silently or would have taken notifications away from the
island.

`pkill -x` exits 0 only if it signalled something, so it is both the kill and
the test for whether there is anything to restart — session-agnostic rather
than session-detecting. Measured to `THEME_APPLY_VISIBLE_DONE`:

    before   1.17, 1.22             (n=2)
    after    median 1.04, min 0.91  (n=6, range 0.91-1.07)

The 1.77 s in the older audit above was not re-measured, so these numbers
stand on their own rather than against it. **~1.0 s remains and has never
been profiled block by block** — that is the next move on ask #4, and it
should be instrumented before anything is changed.

## Two socket listeners had been dead for hours

Reported as "the mode popups do not appear at all, but the mode itself
works". Both halves true, one cause: Hyprland handles submap keys itself, so
the chord kept working while the only thing that ANNOUNCES it was gone.

`submap-indicator.sh` was not running, its lock was free, and
`workspace-layout.sh` — the other socket2 listener from the same
autostart.conf — was also dead. The survivors in that file are exactly the
two entries with a `sleep 40; pgrep -x ... ||` re-check behind them.

Both now distinguish "the read ended" (reconnect, with backoff) from "the
socket FILE is gone" (Hyprland left, exit). Verified by killing the python
reader out from under a running indicator: it survived, spawned a new
reader, and the RESIZE panel still drew.

**What killed them was not recovered.** Nothing in the repo kills either
script. They survive a dropped read now; they still do not survive a `kill`,
and nothing notices if they stop.

---

# Audit — 2026-08-14, the settings app (ask #2)

## What was actually wrong with it

The app was not unbuilt. It was libadwaita, grouped, searching, and already
a correct client of `island-settings.py --set`. Phase 8's schema work was
done too: 31 rows, the `panel` flag, the `font`/`path`/`list` types.

The defect was one property. `set_subtitle_lines(0)` — unlimited — so all 31
rows printed their entire `detail` paragraph. Measured on screen: the page
ran about nine screens, the controls sat stranded at the right margin, and
the group headings were never visible at the same time as a group boundary.
Grouping was true in the markup and false on screen.

That is the whole of "terrible looking, not easy". The prose the app exists
to show was the thing making it unusable.

## The three changes, and what each answers

| the user's words | the change |
|---|---|
| "not easy" | subtitles capped at 2 lines; full prose one click away on ⓘ |
| "not customisable" | sections became a sidebar with counts — a table of contents for what is changeable at all |
| "more detailed" | the ⓘ popover carries key, type, range/choices, default AND current |

Shape and Typography now fit an 980x720 window with no scrolling.

The ⓘ popover is where "more detailed" actually landed. It shows the KEY,
which nothing in either client had ever displayed — `subtitle_for`'s
docstring claimed the key was in the subtitle and it never was. The key is
what you need to script `--set`, to read userconfig.json, or to grep this
repo for why a row exists.

A "Changed" pseudo-section lists only rows differing from the packaged
defaults. Phase 8 asked for "a visible diff"; the per-row reset arrow was
only ever the local half of that.

## Verified without clicking, and that is a rule not a convenience

Every control in this window writes on change, so a synthesised click two
pixels off a list row lands on a switch and edits real config. The
`--selftest` navigation block drives `apply_filter()` directly instead: all
9 sections show exactly their own rows, and a query issued from "System"
returns 7 rows entirely outside it.

**The first version of that test was wrong and failed correct code.** It
asserted "a search spans more than one section", and all seven matches for
"font" are legitimately in Typography. The property that matters is that
results ESCAPE the selected section, not that they span several. Fixed, and
given a second query that does span five.

> A test that fails correct code is a bug in the test. Check what the
> assertion actually implies before believing the FAIL.

`--section Changed` was added beside the existing `--filter`, for the reason
`--filter`'s own comment gives: it is the only way to get a section into a
screenshot without synthesising input.

## The inert row

`islandShowWorkspaceOnAutoHide` has a row in both clients and no reader
anywhere on this machine:

    IslandBackend.qmltypes / libIslandBackendplugin.so
        islandShowWorkspaceOnAutoHide   0 hits, both files
        islandAutoHideEnabled           present, both files
    grep -r  ~/.config/quickshell/tide-island-fork
        nothing

`scope` says "packaged"; the packaged backend is 1.0.34 and the key is
upstream's, added in 1.0.35. UserConfigBackend is compiled and blind to any
key it has no property for, so the toggle writes something nothing reads.

Its `detail` had made this worse than a silent bug — it said the row "is
inert until [auto-hide] is switched, and that is a property of the feature
rather than a fault in the row". Confident, specific, and wrong, which tells
anyone who notices the row does nothing to stop looking.

Left in place: it goes live on the next package upgrade. NOT served through
ForkConfig, because every fork key is `fork`-prefixed precisely so a future
upstream key cannot collide, and adopting an upstream NAME into the fork's
reader creates exactly that collision — two readers for one key the day
1.0.35 lands.

## Still open here

  * The row list is one flat page per section; live preview for the cheap
    numeric keys (sizes, opacity, position) is still unimplemented, and
    Phase 8 asked for it.
  * `exercise_writes` restores the VALUE, not the ABSENCE — see its
    docstring. Byte-exact restore needs an unset in `island-settings.py`.

---

# Audit — 2026-08-14, scratchpads and the S session (ask #8)

## The ask was verification, and the doc's "NOT STARTED" was wrong

`scratchpad.sh`, `toggle-app.sh` and `sum-toggle.sh` all existed, bound and
commented. `rofi_ilovepdf` is on PATH and bound at `$mod P` → `V`, kept as
rofi deliberately — it is a file manager with multi-select and the picker's
protocol carries one id per page. So the migration table's row for it was as
stale as the handoff warned.

What was outstanding was walking the cases. Two defects came out.

## Defect 1 — the spawn path asked for a toggle

Pressing a pad's key while a DIFFERENT pad was open sometimes left the other
pad on screen and the new one hidden: the key looks dead, a second press
fixes it. Seen on `calc` with `term2` open, not reproducible on the next
attempt, and never reproducible with kitty.

Hyprland was cleared first — `togglespecialworkspace B` while A is open
switches to B, dispatched directly. The script ended in an unconditional
toggle even on the path that had just created the window, and that path
knows the state it wants.

This is the existing rule — *toggle IPCs go out of phase; prefer explicit
show/hide when scripting* — surfacing in a subsystem nobody had checked for
it. The rule was written about `qs ipc call`. It is about toggles.

## Defect 2 — 44 px, and three fixes that did not work

`calc` sat at @273,33 where every other pad gets @273,77. Sampled every
150 ms from spawn:

    t=0.90s   820x461 @273,77     our rules, exactly right
    t=1.35s   820x550 @273,33     qalculate-gtk resizes ITSELF
    t=3.90s   820x550 @273,33     and stays

The exec rules were never wrong. The app requests a taller window half a
second after mapping, and a floating window grown about its own centre
drifts up by half the overshoot — precisely 44 px. Invisible on kitty and
the browser pads because they accept the height, so the recentring is zero.

Rejected, each measured:

  * move after the batch rather than inside it — no effect
  * move, verify, re-move up to four times — no effect, and the reason is
    the lesson: **it succeeds.** It reads back @273,77 and breaks, and the
    app resizes after its last read. A verify loop cannot catch a change
    that happens after it stops looking.
  * wait for the size to settle before moving at all — works, and charges
    every pad ~1 s of first-launch latency for one app's habit.

Shipped: the correction is backgrounded. The pad appears immediately and a
watcher re-asserts position once the size has held for three reads. kitty
first launch stays 0.39 s; calc reaches @273,77 within ~2 s.

## The matrix that passed — do not re-walk it

    re-toggle show/hide/show      1 client throughout, no duplicate spawn
    app dead, pad was open        Hyprland auto-hides the emptied special,
                                  so the spawn path lands visible
    app dead, pad was closed      respawns and shows
    first launch, never run       term2, correct geometry, 0.39 s
    geometry vs the qtile source  820x461 @273,77 = 60/60 @ 20/10 of 1366x768
    browser pad hand-off          chatgpt with brave ALREADY RUNNING (12
                                  procs): 956x614 @205,77, floating, shown

The last one matters most: `brave --app` hands the URL to the running brave
and exits, so the window belongs to a process Hyprland never spawned. That
is the case the script's address-polling exists for, and it is the one the
header says used to fail outright. It now works with brave already up.

`toggle-app.sh` with Obsidian, all three branches: not running → switches to
S and spawns, window lands on S; open elsewhere → switches and focuses;
standing on it → bounces back to 4. anki and obsidian share home S but keep
separate go-back memory (`anki` vs `obsidian_md__Obsidian`), so neither can
clobber the other. `sum-toggle.sh` shows and hides as documented.

## Not tested

A second monitor. The x/y monitor-relative logic in `scratchpad.sh` was
measured against a headless output in an earlier session and its reasoning
is in the header; this pass did not re-create that output, so multi-monitor
remains verified-by-history rather than verified-today.
