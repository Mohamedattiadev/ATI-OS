# Recording harness

Records the clips in [`notes/gif_list.md`](../../notes/gif_list.md) inside a
nested X server, so nothing ever appears on the owner's real screen.

The spec is in `gif_list.md` and this directory does not restate it. What is
here is the machinery, and the reasons behind the parts that are not obvious.

```sh
./nest.sh up          # Xephyr :9 + private bus + picom + a second qtile
./nest.sh seed        # windows across groups 1, 2 and 4 (8 stays empty)
./shoot.sh layouts    # record, encode, extract frames
./nest.sh down        # kill everything this started, and nothing else
```

`nest.sh status` lists what is running. `nest.sh exec <cmd>` runs something
inside the nest.

## Adding a clip

One file in `clips/`, named after the row in `gif_list.md`. It sets whatever
it needs to override and defines `choreograph()`:

```sh
REGION="1366x38+0+0"   # WxH+X+Y, at NATIVE size — never upscale
DURATION=7
FPS_IN=24              # 20–24 in, never more
FPS_OUT=12
STATS=diff             # `full` when most of the frame moves
SETTLE=1.2

k() { DISPLAY="$NEST_DISPLAY" xdotool key --clearmodifiers "$@"; }

choreograph() {
  k super+1; sleep 1.4
}
```

`shoot.sh` starts the capture, runs `choreograph` against it, encodes, and
extracts every frame to `<clip>.frames/`. **Look at them.** A clip that
recorded successfully is not a clip that shows the feature — this project has
already shipped a screenshot that was QEMU's "display not initialized"
placeholder. `gifenc.sh` fails outright if every frame is identical, but that
only catches the most obvious version of the problem.

## What the containment is actually protecting against

Every one of these cost a real incident, either in the session that wrote
`gif_list.md` or in the one that wrote this harness.

**Config directories are symlinks into `~/.dotfiles`.** A plain `cp -r` copies
the *symlink*, and every subsequent write lands on the owner's real,
git-tracked config. The first run of `nest.sh` tried to stub `autostart.sh`
and the write went at `../.dotfiles/.config/qtile`. It failed only because
stow's link is relative and did not resolve from the nest; an absolute link
would have silently overwritten the real file. Hence `rsync --copy-links`,
and hence `assert_contained`, which refuses to start if any link under the
nest home points outside it.

**`~/.config/qtile` contains 256 MB of the owner's Brave profile.** Cookies,
history, logins, sitting inside the directory being copied into a place we
are about to point a camera at. Excluded.

**Killing by name kills the owner's daemons.** `pkill -f qupdate.py` matches
theirs. Everything started here carries `ATIOS_NEST=1`, and teardown matches
on that, read out of `/proc/<pid>/environ`.

**D-Bus.** `dbus-run-session` does not put its address on its own process, so
reading `/proc/<pid>/environ` gives the *parent's* bus — the owner's — and a
notification then pops on their real screen. `nest.sh` starts its own daemon
and uses the address it prints. A side effect worth knowing: the private bus
activates its own `dunst`, `gvfsd` and `playerctld`, so notifications raised
inside the nest stay inside it.

**The top bar is `background="#11111b00"` — fully transparent.** With no
compositor on `:9` it does not render as transparent, it renders as garbage,
and every bar clip is worthless. picom runs with the xrender backend; glx
does not work under Xephyr.

**A scrubbed `$HOME` is a brand-new account.** zsh sees no rc file and opens
every terminal on `zsh-newuser-install`; the first `layouts` take recorded
four panes of it. An empty `.zshrc` settles that. The nest then runs fish,
which is what the desktop actually ships.

**Terminals inherit the working directory of whatever spawned them.** Running
`seed` from the repo gave every pane a fish prompt reading
`.dotfiles/video/capture on ⎇ test [!?]` — the owner's real path, branch and
dirty state, on camera. `seed` and `exec` `cd` to the nest home first.

**`config.fish` runs `colorscript random` on every interactive shell.** Real
part of the desktop, but it paints different ANSI artwork every time, so no
two takes match and it fills the pane the clip is meant to show. A no-op stub
shadows it from `$HOME/.local/bin`, which is ahead of everything on the nest's
`PATH`. Overriding there rather than editing the copied `config.fish`, because
it runs inline partway through — there is no "unset" to append afterwards.

**pipewire cannot be contained.** It lives in the shared `XDG_RUNTIME_DIR`, so
any clip that changes volume or mutes hits the owner's real sink. This harness
cannot fix that; see the `audio-popup.gif` row in `gif_list.md`.

**Never run `theme-apply` against the nest.** It restarts qtile and rewrites
global state through paths that are symlinks to the owner's config. `nest.sh`
writes `theme_mode`, `current-palette.rasi` and `alacritty/themes/current.toml`
directly instead. `NEST_THEME=<mode> ./nest.sh up` picks the theme.

## Known rough edge

`./nest.sh seed | <anything>` can block after the seeding itself has finished,
while background children are still attaching. Run it without a pipe.

## Not usable here

`xrandr` inside Xephyr reports one output named `default` at 0.00 Hz, so the
display picker reads as broken rather than working. Anything in the *Cannot be
captured safely* table in `gif_list.md` needs the owner's explicit go-ahead,
per clip, in the session — most of it because the content **is** personal data
and cropping cannot fix that.
