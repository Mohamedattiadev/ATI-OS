# whisper.cpp local patches / build fixes

Both of these apply to the `whisper.cpp-git` AUR package's cached source
at `~/.cache/yay/whisper.cpp-git/src/whisper.cpp-git` and are re-applied
by hand after any `yay -S whisper.cpp-git` rebuild — neither is
upstreamed.

## 1. The AUR package is built completely unoptimized

`~/.cache/yay/whisper.cpp-git/PKGBUILD` builds with:

```
cmake -S "$srcdir/$pkgname" -B "$_BUILDDIR" -DCMAKE_INSTALL_PREFIX=/usr -W no-dev -D CMAKE_BUILD_TYPE=None
```

`CMAKE_BUILD_TYPE=None` means no optimization flags at all (effectively
`-O0`), and no `-march=native`. Measured on this machine: encoding 2s of
audio with `ggml-base.en.bin` took **28 seconds** with the pacman-built
`/usr/bin/whisper-cli` vs **2.1 seconds** with a `Release` build of the
exact same source/model — a ~13x slowdown, present in every binary the
package ships (`whisper-cli`, `whisper-server`, ...). This was silently
throttling `ati-voice-dictate`'s batch dictation (Super+Shift+B) the whole
time, not just anything new.

Fix: build Release binaries from the same cached source and shadow the
slow system ones via `/usr/local/bin` (already earlier in `$PATH` than
`/usr/bin`) and `/usr/local/lib/whisper-cpp` (registered via
`/etc/ld.so.conf.d/whisper-cpp.conf` + `ldconfig`, so the binaries keep
working even if the yay cache is ever cleared):

```bash
cd ~/.cache/yay/whisper.cpp-git/src/whisper.cpp-git
git apply /path/to/patches/whisper-stream-poll-ms.patch   # see below, needed for whisper-stream only
cmake -S . -B build-stream -DWHISPER_SDL2=ON -DCMAKE_BUILD_TYPE=Release
cmake --build build-stream --target whisper-cli whisper-stream -j$(nproc)

sudo mkdir -p /usr/local/lib/whisper-cpp
sudo cp build-stream/bin/lib*.so* /usr/local/lib/whisper-cpp/
echo "/usr/local/lib/whisper-cpp" | sudo tee /etc/ld.so.conf.d/whisper-cpp.conf
sudo ldconfig

sudo install -Dm755 build-stream/bin/whisper-cli    /usr/local/bin/whisper-cli
sudo install -Dm755 build-stream/bin/whisper-stream /usr/local/bin/whisper-stream
```

Verify it actually took: `whisper-cli ... 2>&1 | grep 'encode time'` should
land in the low seconds for a few seconds of audio, not tens of seconds.
`ldd $(which whisper-cli)` should resolve to `/usr/local/lib/whisper-cpp/*`.

## 2. whisper-stream-poll-ms.patch

Adds `--poll-ms`/`--vad-tail-ms` to `examples/stream/stream.cpp` (used by
`ati-voice-dictate-live`) -- see that patch file's own diff for detail.
Upstream hardcodes these at 2000ms/1000ms with no CLI flag, which meant
up to ~2s of dead air before a paused phrase even started transcribing.
