# Why four windows are split into base + backend wrapper

*FORK. Nothing upstream looks like this — upstream is Wayland-only.*

The island runs under Hyprland **and**, since this change, under qtile on X11,
where it is the bar you get when `bar-switch` puts the qtile session into
island mode. One arrangement serves both, and this file is why it is shaped
the way it is, so the next person does not undo it.

## The failure it fixes

Under X11 the island rendered **nothing**. The whole screen measured
`mean=0`. The log said `Configuration Loaded` — no error, no failed reload,
nothing naming the island.

The cause, in the log four lines above:

```
WARN: qs:@/qs/DynamicIslandWindow.qml:295:5: Could not create attached
      properties object 'qs::wayland::layershell::WlrLayershell'
WARN: QQmlComponent: Component is not ready
```

`WlrLayershell.layer` is an **attached property**, and an attached object that
cannot be created fails **the entire component**, not the one line. So four
declarations — three of them constants — took four whole windows down with
them, including the 5,800-line one that is the island.

This is the same class of failure as `Property value set multiple times`,
which the RULES in `hypr/NEXT-SESSION.md` already record: a per-line mistake
that presents as a whole-file outage.

## Why not a runtime check instead

There is no conditional form of an attached property declaration. `Binding`'s
`property:` string does not reach attached properties, and there is no
`WlrLayershell.get(window)` accessor on this Quickshell (0.3.0 — checked in
`quickshell-wayland.qmltypes`). The declaration is compile-time or it is
nothing.

## The arrangement

Each affected window is now:

| | |
|---|---|
| **base** | the original file, minus the `WlrLayershell.*` lines. All the content. Loads on both backends. |

**Only the declarations move. The import may stay.** This is narrower than it
first looks, and getting it wrong cost a reload: `import Quickshell.Wayland`
is *harmless* under X11 — the module resolves, and only the types inside it
become unusable. What is fatal is *declaring an attached property* from it.
So `DynamicIslandWindow.qml` still imports the module, because it also uses
`ToplevelManager` and `Toplevel`; dropping the import there produced

```
WARN scene: @DynamicIslandWindow.qml[3428]: ReferenceError:
            ToplevelManager is not defined
```

on the very next hot reload. The other four bases genuinely use nothing else
from the module — grepped for `ToplevelManager`, `Toplevel`, `ScreencopyView`
and `WlSessionLock*`, not just for `Wlr` — so their imports are gone and that
is a tidy-up, not a requirement.

| **`…Wayland.qml`** | ~10 lines. `Base { WlrLayershell.layer: …; … }` |
| **`…X11.qml`** | ~10 lines. `Base { aboveWindows: …; focusable: … }` |

| Base | Wayland | X11 |
|---|---|---|
| `DynamicIslandWindow.qml` | `IslandWindowWayland.qml` | `IslandWindowX11.qml` |
| `qml/osd/RingOsdWindow.qml` | `RingOsdWindowWayland.qml` | `RingOsdWindowX11.qml` |
| `qml/theme/ThemeTransitionWindow.qml` | `…Wayland.qml` | `…X11.qml` |
| `qml/treetab/TreeTabSidebar.qml` | `TreeTabSidebarWayland.qml` | *(none — deliberate)* |

TreeTab has no X11 wrapper because qtile has the real `layout.TreeTab`.
Drawing a replica of qtile's TreeTab inside qtile would be the wrong panel.

**The base keeps the original filename.** That is the point of doing it this
way round rather than renaming the big file to `IslandSurface.qml` and making
`DynamicIslandWindow.qml` the wrapper: `FORK-NOTES.md` tells you to merge
upstream with

```
diff -u /usr/share/tide-island/DynamicIslandWindow.qml <fork>/DynamicIslandWindow.qml
```

and that diff still works. It shows the removed layershell block and nothing
else. A rename would have made every upgrade start with a rename to undo.

## The two rules that fall out of it

1. **Backend properties live in exactly one wrapper, never also in the base.**
   On Wayland `focusable` and `WlrLayershell.keyboardFocus` drive the same
   layer-shell field; setting one in the base and the other in the wrapper
   leaves which wins to evaluation order. One owner per backend.

2. **A wrapper cannot see the base's ids.** Ids are file-scoped, so
   `islandContainer` is invisible from `IslandWindowWayland.qml`. Anything a
   wrapper has to branch on must be a **property on the base's root**. That is
   why the island's ninety-line focus decision stays in the base and only its
   spelling moves out: the base publishes `islandKeyboardFocus` as a string
   (`"exclusive"` / `"ondemand"` / `"none"`) and each wrapper maps it.

   A string, not an enum, for the reason the island already runs off one
   string: it survives into a log line and into a grep.

## What X11 does not have

Recorded here so it is not re-diagnosed as a bug:

* **Two stacking layers, not four.** `aboveWindows` is the whole vocabulary.
  Top→`false` and Overlay→`true` reproduce both ends of the island's actual
  rule; Bottom and Background are unused by it anyway.
* **No exclusive keyboard grab.** `focusable` is a bool. The arrow-key and
  search-field panels still receive keys, because taking focus is what
  delivers them — but the *guarantee* is gone, and qtile's
  `follow_mouse_focus = True` can hand focus away mid-panel.
* **No layer-surface namespace**, so no `layerrule` equivalent. qtile matches
  on `WM_CLASS`.
* **Hyprland-only features are simply absent**: workspaces, the overview,
  the window ring, submap/mode keys, TreeTab. `Quickshell.Hyprland` is still
  *imported* under X11 and that is harmless — measured, the module loads, the
  singleton has no socket, and the only output is one warning about
  `hyprland-toplevel-mapping-v1`. It is *using* a Hyprland object that fails,
  and every such use is behind a Loader gated on the compositor.
