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
