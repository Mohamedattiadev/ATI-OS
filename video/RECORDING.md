# How the usage clip was recorded

`usage.mp4` is 28 seconds of ordinary work, in one take, recorded inside a
nested X server so nothing ever reached the real display.

    Xephyr :9 -screen 1366x768        second qtile, from a copy of the config
                                      with the autostart hook disabled
    ffmpeg -f x11grab -i :9.0         24 fps, lossless, then transcoded

Everything on screen runs against a scrubbed `$HOME` at `/tmp/atios-usage/home`:
four throwaway folders, three throwaway files, and Brave on a throwaway profile
pointed at this project's own docs. `usage-take.sh` is the choreography.

## Two things deliberately not in the clip

**No live theme switch.** The nest's home symlinks `gtk-3.0`, `gtk-4.0`,
`dunst`, `eww` and Brave's profile back to the real `~/.config`, so running
`theme-apply` inside the nest would retint the live session. The picker is
opened and Escaped instead.

**No drag into the drop shelf.** The shelf hides on focus loss, and summoning
it mid-drag does not help: pcmanfm answers the XDND handshake before qdrop
does, so every synthetic drop lands in the file manager as a "Copy here / Move
here" menu. The drag works by hand. It does not drive from `xdotool`.

## Rebuilding

    ./make-assets.sh          # transcodes IMGS/ and the take into public/
    npm run dev               # studio on :3021
