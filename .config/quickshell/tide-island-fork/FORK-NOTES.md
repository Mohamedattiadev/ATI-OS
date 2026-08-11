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

## Pre-existing upstream warning, not ours

```
WARN scene: @qml/island/BluetoothConnectionTracker.qml[153:-1]:
  ReferenceError: root is not defined
```

Present when running `/usr/share/tide-island` unmodified. Left alone so the
diff against upstream stays honest.
