# Silence libvips warnings (noisy on thumbnail generation, e.g. the
# wallpaper picker's PIL/vips path).
#
# This lives here, not in ~/.profile. `set -x VIPS_WARNING 0` is fish
# syntax; fish never reads ~/.profile, and a POSIX shell sourcing that
# file reads `set -x` as "enable xtrace" and starts echoing every command
# instead of setting anything. So the variable was never actually set.
set -gx VIPS_WARNING 0
