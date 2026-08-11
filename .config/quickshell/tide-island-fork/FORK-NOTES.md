# Tide Island — fork notes

Vendored from **`tide-island 1.0.34-1`** (`/usr/share/tide-island`), Arch AUR.
Upstream: <https://github.com/enhaoswen/Tide-island>.

Launched by `../../hypr/scripts/island.sh`, which `autostart.conf` runs in
place of the packaged `tide-island` binary.

## What is in here, and what is not

| | |
|---|---|
| Vendored | `shell.qml`, `DynamicIslandWindow.qml`, the whole `qml/` tree |
| **Not** vendored | `bin/lyricsmpris` — a 356K ELF; the packaged copy is used via `QUICKSHELL_LYRICS_BACKEND` |
| **Not** vendored | `IslandBackend` — a compiled C++/Qt QML module, kept from the package |

The last line is the one that makes this fork cheap, and it was verified
before anything else was written: a QML tree at an arbitrary path still
resolves `import IslandBackend`, because `/usr/lib/qt6/qml` is one of Qt's
default import paths and the package installs the module there. Test used:

```
cp -r /usr/share/tide-island /tmp/vendortest
timeout 8 quickshell -p /tmp/vendortest
# → "Configuration Loaded", no "module IslandBackend is not installed"
```

Had that failed, the fallback was building the AUR tree at
`~/.config/quickshell/tide-island` with patches applied. It did not fail.

## Upgrading tide-island

`pacman -Syu` updates `/usr/share/tide-island` and leaves this tree alone,
so the fork silently goes stale — it keeps working, it just stops gaining
upstream fixes. After an upgrade:

```
diff -ru /usr/share/tide-island/qml  ~/.config/quickshell/tide-island-fork/qml
diff -u  /usr/share/tide-island/DynamicIslandWindow.qml \
         ~/.config/quickshell/tide-island-fork/DynamicIslandWindow.qml
```

Everything that shows up as ours is listed below; re-apply it on top of the
new upstream files.

Also re-check the backend ABI: `IslandBackend` is compiled against a
specific upstream QML API. If an upgrade renames a backend property, the
vendored QML breaks with a `ReferenceError` at runtime and **not** at load
time — Quickshell will still say "Configuration Loaded".

## Patches applied to upstream

Nothing yet beyond the vendoring itself. Each entry below is added by the
commit that makes the change, with the file, the upstream behaviour, and
why the spec wanted something else.

<!-- PATCH LIST -->

### `qml/common/Motion.js` (new file) + `DynamicIslandWindow.qml` — the spring

Upstream animates the capsule on `Easing.OutQuint` (geometry) and
`Easing.InOutQuad` (colour), at a hardcoded `morphDuration: 400`.
DESIGN-SPEC.md wants a generated damped-harmonic spring instead: 400 ms,
damping ratio 0.8, with **fades on a separate critically-damped curve**
because opacity is clamped 0-1 and an overshooting fade gets clipped.

`Motion.js` solves the oscillator analytically and emits it as an
`Easing.BezierSpline`. Nine `Behavior`s in `DynamicIslandWindow.qml` now
call `Motion.spring()` (geometry) or `Motion.fade()` (opacity/colour).

**The trap, which cost a crashed shell:** Qt's `BezierSpline` supports at
most **10 cubic segments**. An eleventh does not warn or fall back — it
writes past the end of a preallocated `QList` in `BezierEase::init()` and
the process takes SIGSEGV on the first animated frame. The first attempt
used 24 and killed Quickshell every launch, with the misleading trailing
message `QEventLoop: Cannot be used without QCoreApplication` (that is the
crash handler, not the cause). Bisected in an offscreen `qml6` harness:
8 and 10 fine, 11 and up SIGSEGV. See the long comment in `Motion.js`.

To keep fidelity inside 10 segments the knots are warped `t^1.8` so they
cluster on the rise and the overshoot peak rather than on the flat tail —
max deviation from the true response 4.0e-4 versus 2.9e-3 for even
spacing.

### `DynamicIslandWindow.qml` — the notch form

Upstream has one resting shape: a pill floating `islandTopMargin` below the
top edge with all four corners rounded. DESIGN-SPEC.md has two forms of the
**same** shape, and the flush one is what makes it read as a notch rather
than as a widget. `notchModeEnabled` defaults true, so the notch is now the
everyday resting appearance.

Driven by a single `notchProgress` 0..1, because the spec is explicit that
this must be "one shape morphing and not two shapes swapping. A single path
interpolated by one value" — the author's first attempt flipped two shapes
with `visible` and it "looked cheap instantly". Interpolated in two phases,
because an outline cannot be round-topped and flared at once:

| phase | range | what moves |
|---|---|---|
| 1 | 0 → 0.5 | top corner radii → 0, capsule slides flush, overshoot grows |
| 2 | 0.5 → 1 | the concave flares grow |

`notchSkirt` is a new `Shape` sibling of `mainCapsule` carrying the
overshoot band and both flares as one `ShapePath`. It is a sibling rather
than a child because `mainCapsule` is a `Rectangle` (cannot be concave)
with `clip: true` and ~40 anchored children — painting the flares inside
would clip them, and resizing it to make room would shift every child.
Quarter arcs are cubics at kappa = 0.5523 rather than `PathArc`, which
removes any chance of a sweep-direction mistake drawing the arc the long
way round.

The top corners use Qt 6.7+ `topLeftRadius` / `topRightRadius`; `radius`
still drives the bottom pair, which the notch keeps.

Scaling, per REQUIREMENTS.md's proportion rule: the flare is 14 px in the
spec's 2560-wide measurements and is scaled by the island's own factor
(96/150) to **9 px**. The 4 px overshoot is deliberately **not** scaled —
it exists to cover the drop shadow's padding, which is an absolute pixel
count, so shrinking it would reintroduce the desktop-coloured hairline it
exists to hide.

## Pre-existing upstream warning, not ours

```
WARN scene: @qml/island/BluetoothConnectionTracker.qml[153:-1]:
  ReferenceError: root is not defined
```

Present when running `/usr/share/tide-island` unmodified. Left alone so the
diff against upstream stays honest.
