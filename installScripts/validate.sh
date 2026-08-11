#!/usr/bin/env bash
# validate.sh — the fast test layer. Seconds, no container, no root.
#
# Testing this repo has four layers, cheapest first. Each catches a class
# the one below it cannot, and none of them replaces the next:
#
#   1. validate.sh      seconds   syntax + config load + portability greps
#   2. wizard --audit   seconds   declared packages vs installed
#   3. container-test   ~3 min    a real install as a user who is not you
#   4. vm-test.sh       ~40 min   X11, systemd, GPU, boot -- the real thing
#
# What THIS layer catches, and why each check exists rather than being a
# generic linter pass:
#
#   * a qtile config that does not load. qtile falls back to its default
#     config on a syntax error, so the desktop still starts and looks
#     completely wrong, with the reason only in a log nobody opens.
#   * a /home/ati that crept back into a tracked file
#   * a @HOME@ template with no renderer, or a renderer with no template
#   * a module yaml that stopped parsing
#   * a wizard module with no uninstaller (fails mid-uninstall otherwise)
#   * a cheatsheet entry drawn past the edge of its popup, clipped mid-key,
#     or using a glyph the font lacks. PopupText does not clip and pango
#     falls back silently, so all three are invisible -- no error anywhere.
#   * an nvim lua file that does not parse
#   * an nvim theme that will never install: a colorscheme named in
#     theme_sync's map with no plugin spec behind it, or a spec carrying a
#     live `enabled = false`. Neither errors at runtime -- nvim just falls
#     through to rendering that mode from the palette, so the theme still
#     "works" and the missing plugin goes unnoticed for months.
#
# Usage: ./validate.sh [--quiet]
#
# TESTING A CHECK IN HERE: use ./validate-selftest.sh, never the live repo.
# `~/.config` is stow-symlinked INTO this repository, so editing
# .config/kitty/kitty.conf to prove the font check works edits the running
# terminal's font. That happened -- the owner's terminal changed face
# mid-session and only reverted when the backup was restored minutes later.
# The self-test mutates a detached git worktree instead, which nothing in
# `~` points at.

set -Eeuo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QUIET=0
[[ "${1:-}" == "--quiet" ]] && QUIET=1

r=$'\033[31m'; g=$'\033[32m'; y=$'\033[33m'; d=$'\033[90m'; o=$'\033[0m'
FAIL=0
pass() { (( QUIET )) || printf '  %s✓%s %s\n' "$g" "$o" "$*"; }
fail() { printf '  %s✗%s %s\n' "$r" "$o" "$*" >&2; FAIL=1; }
warn() { printf '  %s!%s %s\n' "$y" "$o" "$*"; }
# Not a pass and not a failure: the check could not run here. Used for
# things that need a package the container image deliberately lacks --
# reporting them as passes would be a lie about what was verified.
skip() { (( QUIET )) || printf '  %s-%s %s (skipped)\n' "$d" "$o" "$*"; }
head_() { (( QUIET )) || printf '\n%s%s%s\n' "$d" "$*" "$o"; }

cd "$REPO"

# ── 1. shell ─────────────────────────────────────────────────────────
head_ "shell syntax"
shell_files=()
while IFS= read -r f; do shell_files+=("$f"); done < <(
  git ls-files -z 2>/dev/null | xargs -0 -r file --mime-type 2>/dev/null \
    | awk -F: '/x-shellscript/ {print $1}'
)
if (( ${#shell_files[@]} )); then
  bad=0
  for f in "${shell_files[@]}"; do
    bash -n "$f" 2>/dev/null || { fail "bash -n: $f"; bad=1; }
  done
  (( bad )) || pass "${#shell_files[@]} shell scripts parse"
else
  warn "no shell scripts found (is this a git repo?)"
fi

# ── 2. python ────────────────────────────────────────────────────────
head_ "python syntax"
# The count used to travel through a fixed /tmp/.validate_pycount. On a
# machine with a second account that file is owned by whoever ran the
# validator first, the write raises PermissionError, and the whole block
# exits non-zero -- reporting "python syntax errors" for code that parses
# fine. It rides back on stdout instead; nothing is written anywhere.
if _py_out="$(python3 - <<'PY'
import ast, subprocess, sys
files = subprocess.run(["git","ls-files","*.py"], capture_output=True, text=True).stdout.split()
bad = []
for f in files:
    try:
        ast.parse(open(f, encoding="utf-8").read())
    except SyntaxError as e:
        bad.append(f"{f}:{e.lineno}: {e.msg}")
if bad:
    print("\n".join(bad)); sys.exit(1)
print(len(files))
PY
)"; then pass "${_py_out:-?} python files parse"
else
  printf '%s\n' "$_py_out" | sed 's/^/      /' >&2
  fail "python syntax errors above"
fi

# ── 3. fish ──────────────────────────────────────────────────────────
head_ "fish syntax"
if command -v fish >/dev/null 2>&1; then
  bad=0
  while IFS= read -r f; do
    fish -n "$f" >/dev/null 2>&1 || { fail "fish -n: $f"; bad=1; }
  done < <(git ls-files '*.fish')
  (( bad )) || pass "fish config parses"
else
  warn "fish not installed — skipped"
fi

# ── 4. yaml ──────────────────────────────────────────────────────────
head_ "package modules"
if python3 -c "import yaml" 2>/dev/null; then
  if python3 - <<'PY'
import glob, sys, yaml
bad = []
for f in glob.glob(".config/arch-config/**/*.yaml", recursive=True):
    try:
        yaml.safe_load(open(f))
    except Exception as e:
        bad.append(f"{f}: {e}")
if bad:
    print("\n".join(bad)); sys.exit(1)
PY
  then pass "all module yaml parses"
  else fail "yaml parse errors above"
  fi
else
  warn "pyyaml not installed — skipped"
fi

# ── 5. qtile config actually loads ───────────────────────────────────
# The most valuable check here. qtile silently falls back to its stock
# config when this fails, so the failure mode is "my desktop looks like a
# stranger's" rather than an error anyone sees.
head_ "qtile config"
if python3 -c "import libqtile" 2>/dev/null; then
  if (cd .config/qtile && timeout 90 python3 -c "
from libqtile.confreader import Config
c = Config('config.py'); c.load(); c.validate()
assert c.screens, 'no screens defined'
assert c.screens[0].top.size > 0, 'top bar has zero height'
" 2>&1 | tail -3); then
    pass "config.py loads and validates"
  else
    fail "qtile config does not load — the desktop would fall back to stock qtile"
  fi
else
  warn "libqtile not importable — skipped"
fi

# ── 6. portability ───────────────────────────────────────────────────
head_ "portability"
# Exclusions, each for a reason rather than to make the check pass:
# - *.md          prose about the problem, not the problem
# - comment lines the explanation of why a path was de-hardcoded
# - the test scripts they contain "/home/ati" as the pattern they SEARCH
#   for; matching them here would mean the check can never pass
#
# The bookmarks/urls exclusion that used to sit here is gone: that file is
# personal browsing data and is no longer tracked at all, so the check now
# covers every tracked file without a data carve-out.
hits="$(git ls-files -z | xargs -0 grep -In "/home/ati" 2>/dev/null \
  | grep -vE '\.md:' \
  | grep -vE '^[^:]+:[0-9]+:\s*(#|//|--|\*)' \
  | grep -vE '^installScripts/(container-test|validate)\.sh:' || true)"
if [[ -n "$hits" ]]; then
  fail "hardcoded /home/ati in tracked files:"
  printf '%s\n' "$hits" | sed 's/^/      /' >&2
else
  pass "no hardcoded home paths (comments excluded)"
fi

# Every @HOME@ template needs something that renders it, or it ships a
# literal placeholder into a config file and the app silently misbehaves.
head_ "templates"
tmpl_bad=0
while IFS= read -r t; do
  base="$(basename "$t")"
  if ! grep -rqF "$base" installScripts/ .config/AtiScriptsV1/ 2>/dev/null; then
    fail "template with no renderer: $t"; tmpl_bad=1
  fi
done < <(git ls-files '*.tmpl')
(( tmpl_bad )) || pass "every .tmpl is referenced by a renderer"

# Python scripts under AtiScriptsV1 are launched detached (qtile.spawn, nvim's
# vim.system) with their output going to a log nobody reads. A syntax error in
# one is therefore completely invisible at runtime -- the feature just stops
# working. Compiling them here is the only place it surfaces.
head_ "AtiScriptsV1 python"
py_bad=0
while IFS= read -r f; do
  head -1 "$f" | grep -q 'python' || continue
  # ast.parse, not py_compile: py_compile drops a __pycache__/ directory
  # next to every file it touches, so the one script in this repo that is
  # supposed to read the working tree and change nothing was littering it.
  if ! python3 -c 'import ast,sys; ast.parse(open(sys.argv[1],encoding="utf-8").read())' "$f" 2>/dev/null; then
    fail "python syntax error: $f"; py_bad=1
  fi
done < <(git ls-files '.config/AtiScriptsV1/*')
(( py_bad )) || pass "every python script in AtiScriptsV1 compiles"

# ── 7. wizard invariants ─────────────────────────────────────────────
head_ "wizard"
if ./installScripts/wizard.sh --help >/dev/null 2>&1; then
  pass "wizard --help runs (module ids validate, uninstallers all present)"
else
  fail "wizard --help failed — usually a module with no UMOD_CMD entry"
fi
if ./installScripts/wizard.sh --yes --dry-run >/dev/null 2>&1; then
  pass "full dry-run completes"
else
  fail "full dry-run failed"
fi

# ── 8. boot splash: the name matrix ──────────────────────────────────
# The splash renders whatever the account is called, and three separate
# bugs lived in that path unnoticed: characters the block face lacks were
# silently dropped (josé -> "JOS"), long names were sized off the wrong row
# of the art, and multi-word names were run onto one illegible line.
# `boot-splash selftest` renders a matrix of awkward names and asserts each
# one fits. It needs no root and writes only to a tempdir.
#
# Skipped, not failed, when ImageMagick or the block font is absent: this
# has to pass in a container that has neither.
head_ "boot splash"
if [[ ! -x .config/AtiScriptsV1/boot-splash ]]; then
  skip "boot-splash not present"
elif ! command -v magick >/dev/null 2>&1; then
  skip "no imagemagick — cannot render the name matrix"
elif [[ ! -f /usr/share/fonts/TTF/FiraCodeNerdFontMono-Bold.ttf ]]; then
  skip "block-art font not installed — cannot render the name matrix"
elif .config/AtiScriptsV1/boot-splash selftest >/dev/null 2>&1; then
  pass "every name in the matrix renders and fits on screen"
else
  fail "boot-splash selftest failed — run: boot-splash selftest"
fi

# Every boot menu entry that overrides the kernel cmdline must name the root
# device this machine actually booted from. A hand-edited arch.conf on the
# author's machine carried a PARTUUID one character off the real one and sat
# there for months: systemd-boot boots the auto-discovered UKI by default,
# so the broken entry was only ever reached by someone picking it out of the
# menu -- which is exactly what you do when a boot has already gone wrong.
#
# Needs to read the ESP, which is root-only (dmask=0077), so this uses
# `sudo -n` and reports a skip rather than a pass when there is no cached
# credential. validate.sh does not prompt for a password.
boot_root_out=""
if [[ ! -x .config/AtiScriptsV1/boot-splash ]]; then
  :
elif ! command -v findmnt >/dev/null 2>&1; then
  skip "no findmnt — cannot resolve the running root device"
else
  boot_root_rc=0
  boot_root_out="$(.config/AtiScriptsV1/boot-splash verify-root 2>&1)" || boot_root_rc=$?
  case "$boot_root_rc" in
    0) pass "every boot entry's root= matches the running root device" ;;
    2) skip "ESP not readable without a password — boot entries unverified" ;;
    *) fail "a boot entry names the wrong root device:"
       printf '%s\n' "$boot_root_out" >&2 ;;
  esac
fi

# ── 9. cheatsheet popups: everything fits on screen ──────────────────
# PopupText does not clip to its height -- text longer than the box just
# keeps drawing downward until the popup window edge cuts it off. All three
# cheatsheets overflowed for a long time with nothing to show for it: the
# entries were simply not on screen, no error, no log line. The Qtile sheet
# was losing the last four entries of its biggest column, and four Vim
# sections lost their tails.
#
# The selftest asks pango for the real extents of every card at its real
# font size and asserts it fits, that no row is clipped mid-key, and that
# every glyph drawn exists in the font -- a missing one falls back to
# another family at another width and un-aligns the whole key column.
# Cheap, and the only thing standing between "added one entry" and
# "silently dropped a different one".
#
# QTILE_UI_SCALE_FORCE=1 pins the sheets to their reference size. They
# scale with UI_SCALE now, but the selftest measures against a fixed
# 1366x768 reference screen -- so on a HiDPI machine the popup would grow
# while that reference did not, and every sheet would report as
# overflowing. The reference design is what this check is for.
head_ "cheatsheet popups"
if ! python3 -c "import gi, cairo" 2>/dev/null; then
  skip "no pygobject/cairo — cannot measure text"
elif ! python3 -c "import qtile_extras" 2>/dev/null; then
  skip "qtile-extras not importable"
elif _cs_out="$(cd .config/qtile && QTILE_UI_SCALE_FORCE=1 python3 -m popups._cheatsheet_grid 2>&1)"; then
  pass "every cheatsheet card fits, nothing clipped, every glyph present"
else
  printf '%s\n' "$_cs_out" | sed 's/^/    /'
  fail "a cheatsheet card is off-screen, clipped, or missing a glyph"
fi

# ── 10. the UI's fonts are actually installed ────────────────────────
# fontconfig NEVER errors on a missing family. It substitutes, silently,
# and on this system `fc-match` answers Noto Sans CJK KR for anything it
# does not have -- a proportional face. Every padded column in this repo
# (the cheatsheet key columns, the wifi/bluetooth rows, rofi_docs) is
# aligned with spaces, and spaces only align in a monospace font, so a
# substituted family does not look like a missing font. It looks like the
# layout code is broken.
#
# ttf-jetbrains-mono-nerd was exactly this: installed on the author's
# machine, declared in no module, so a fresh install would have rendered
# the whole qtile UI in CJK with nothing to say why. These are the
# families the UI names as ITS font, so each must resolve to itself.
#
# NOT a list of every family mentioned anywhere: CSS stacks and
# qutebrowser's fallback lists name plenty of fonts on purpose that are
# not expected to be present.
head_ "UI fonts installed"

# The list used to be hand-written, and the note in
# notes/archive/plan_found-but-not-fixed.md called that out as the last open
# item here: "it does not derive itself. Any config that starts naming a new
# family will pass validation while rendering in a substituted face. That is
# the exact failure this repo has now hit three times."
#
# It was already incomplete when this replaced it. config.py asks for
# `Ubuntu Mono` in five widgets and the list only carried `Ubuntu`; pango
# parses "Bold" off "Ubuntu Bold" as a weight, but "Mono" is a different
# FAMILY, not a style. Nothing broke because ttf-ubuntu-font-family happens
# to ship both, which is luck, not coverage.
#
# So the families are derived from the configs that name them. What is
# maintained by hand now is the list of SOURCES -- which kinds of file name a
# font, and how -- and that changes far less often than the fonts do.
_font_family() {   # pango-ish string -> bare family
  local s="$1"
  s="${s%\"}"; s="${s#\"}"
  # Trim FIRST. kitty pads its values ("bold_font   FiraCode Nerd Font Bold"),
  # and with a trailing space the anchored style strip below never fires --
  # which is how "FiraCode Nerd Font Bold" reached fc-match and came back as
  # Noto Sans CJK KR, a missing-font failure that was really a parsing one.
  s="$(sed -E 's/^[[:space:]]+|[[:space:]]+$//g; s/,.*$//' <<<"$s")"
  s="$(sed -E 's/[[:space:]]+[0-9]+([.][0-9]+)?$//' <<<"$s")"          # trailing size
  # Loop: styles stack. kitty's bold_italic_font is "FiraCode Nerd Font Bold
  # Italic", and stripping one word left "...Bold", which fc-match answered
  # with Noto Sans CJK KR -- reported as a missing font when it was really
  # two style words and a single-shot regex.
  local prev=""
  while [[ "$s" != "$prev" ]]; do
    prev="$s"
    s="$(sed -E 's/[[:space:]]+(Bold|Italic|Oblique|Light|Medium|Regular|SemiBold|Semibold|Thin|Black|Heavy|Condensed|ExtraBold)$//I' <<<"$s")"
  done
  sed -E 's/^[[:space:]]+|[[:space:]]+$//g' <<<"$s"
}

# Generic aliases resolve by definition -- requiring them would be asserting
# that fontconfig works, not that a font is installed.
_font_generic() {
  grep -qiE '^(sans|serif|monospace|sans-serif|system-ui|cursive|fantasy|ui-monospace|emoji)$' <<<"$1"
}

_font_emit() {     # raw, source-file
  local fam; fam="$(_font_family "$1")"
  [[ -z "$fam" ]] && return 0
  _font_generic "$fam" && return 0
  printf '%s|%s\n' "$fam" "${2#./}"
}

# sed -n .../p, NOT a `.*re.*` wrapper: half these patterns are anchored and
# wrapping them in .* makes ^ unmatchable, which silently passes the whole
# line through as if it were a family name.
_font_scan() {     # file, ERE with one capture group
  local f="$1" re="$2" hit
  [[ -f "$f" ]] || return 0
  while IFS= read -r hit; do _font_emit "$hit" "$f"; done \
    < <(sed -nE "s/$re/\1/Ip" "$f" 2>/dev/null)
}

_font_sources() {
  local f k
  # qtile: widget font="X", and pango markup <span font_family="X">
  while IFS= read -r f; do
    _font_scan "$f" '.*font[[:space:]]*=[[:space:]]*"([^"]+)".*'
    _font_scan "$f" '.*font_family="([^"]+)".*'
  done < <(git ls-files '.config/qtile/*.py' '.config/qtile/**/*.py' 2>/dev/null)
  for k in font_family bold_font italic_font bold_italic_font; do
    _font_scan .config/kitty/kitty.conf "^${k}[[:space:]]+(.+)$"
  done
  while IFS= read -r f; do
    _font_scan "$f" '.*family[[:space:]]*=[[:space:]]*"([^"]+)".*'
  done < <(git ls-files '.config/alacritty/*.toml' 2>/dev/null)
  while IFS= read -r f; do
    _font_scan "$f" '.*font:[[:space:]]*"([^"]+)".*'
  done < <(git ls-files '.config/rofi/*.rasi' '.config/rofi/**/*.rasi' 2>/dev/null)
  for f in .config/gtk-3.0/settings.ini .config/gtk-4.0/settings.ini; do
    _font_scan "$f" '^gtk-font-name[[:space:]]*=[[:space:]]*(.+)$'
  done
  _font_scan .config/dunst/dunstrc '^[[:space:]]*font[[:space:]]*=[[:space:]]*(.+)$'
  # fontconfig: only what a generic is aliased TO. The <family> naming the
  # generic itself, and the MS-font names in the <match> blocks below it, are
  # deliberately not required to exist.
  if [[ -f .config/fontconfig/fonts.conf ]]; then
    while IFS= read -r f; do
      _font_emit "$f" .config/fontconfig/fonts.conf
    done < <(awk '/<prefer>/{p=1;next} /<\/prefer>/{p=0} p' .config/fontconfig/fonts.conf \
               | grep -oE '<family>[^<]+</family>' | sed -E 's|</?family>||g')
  fi
}

if ! command -v fc-match >/dev/null 2>&1; then
  skip "no fontconfig — cannot check families"
else
  _font_bad=0
  _font_n=0
  while IFS='|' read -r _fam _who; do
    [[ -z "$_fam" ]] && continue
    _font_n=$(( _font_n + 1 ))
    _got="$(fc-match -f '%{family}' "$_fam" 2>/dev/null)"
    # fc-match answers the whole family list ("FiraCode Nerd Font Mono,FiraCode NFM").
    if [[ "${_got,,}" != *"${_fam,,}"* ]]; then
      printf '    %s -> %s  (named by %s)\n' "$_fam" "${_got:-nothing}" "$_who"
      _font_bad=1
    fi
  done < <(_font_sources | sort -u -t'|' -k1,1)

  if (( _font_bad )); then
    fail "a font the UI names is missing — fontconfig is silently substituting it; install the fonts module"
  elif (( _font_n == 0 )); then
    fail "no font families found in any config — the extraction is broken, not the fonts"
  else
    pass "$_font_n families named by configs, every one resolves to itself"
  fi
fi

# ── 11. nvim: lua parses, and the theme map matches the plugin specs ──
head_ "nvim config"

if ! command -v luac >/dev/null 2>&1; then
  skip "lua syntax (luac not installed)"
else
  _lua_bad=0
  _lua_n=0
  while IFS= read -r f; do
    _lua_n=$((_lua_n + 1))
    luac -p "$f" 2>/dev/null || { fail "luac -p: $f"; _lua_bad=1; }
  done < <(git ls-files '.config/nvim/**/*.lua' '.config/nvim/*.lua' 2>/dev/null)
  if (( _lua_bad )); then
    :
  elif (( _lua_n )); then
    pass "$_lua_n nvim lua files parse"
  else
    skip "lua syntax (no tracked .lua files)"
  fi
fi

# theme_sync.scheme_of is the single source of truth for "desktop mode ->
# colorscheme", read by BOTH the startup colorscheme and the live watcher.
# A scheme listed there whose plugin is not actually declared in themes.lua
# does not error: nvim silently falls through to rendering from the palette,
# so the mode still *works* and nobody notices the plugin was never
# installed. That is exactly how tokyonight sat broken -- declared twice in
# themes.lua, once with a stray enabled=false. Catch the drift instead.
_ts=.config/nvim/lua/config/theme_sync.lua
_th=.config/nvim/lua/plugins/themes.lua
if [[ ! -f "$_ts" || ! -f "$_th" ]]; then
  skip "nvim theme map (theme_sync.lua or themes.lua missing)"
elif ! command -v lua >/dev/null 2>&1; then
  skip "nvim theme map (lua not installed)"
else
  # Plugin dirs the specs actually declare. lazy.nvim installs
  # "owner/repo" into a directory called `repo` unless the spec overrides
  # it with name = "...". Specs here span several lines, so collect both
  # forms from the whole file rather than trying to parse spec by spec.
  mapfile -t _declared < <(
    {
      grep -oE '"[A-Za-z0-9._-]+/[A-Za-z0-9._-]+"' "$_th" \
        | tr -d '"' | sed 's|.*/||'
      grep -oE 'name\s*=\s*"[^"]+"' "$_th" \
        | grep -oE '"[^"]+"' | tr -d '"'
    } | sort -u
  )
  # plugin dirs theme_sync.plugin_of promises to load
  mapfile -t _promised < <(
    lua -e '
      package.path = ".config/nvim/lua/?.lua;" .. package.path
      -- theme_sync only touches vim.fn at load time; stub enough for that.
      vim = { fn = { expand = function(s) return s end } }
      local ok, m = pcall(require, "config.theme_sync")
      if not ok then os.exit(0) end
      local seen = {}
      for mode, scheme in pairs(m.scheme_of) do
        local plug = m.plugin_of[scheme]
        if not plug then
          print("NOPLUGIN\t" .. mode .. "\t" .. scheme)
        elseif not seen[plug] then
          seen[plug] = true
          print("NEED\t" .. plug)
        end
      end
    ' 2>/dev/null
  )
  _map_bad=0
  for line in "${_promised[@]}"; do
    kind=${line%%$'\t'*}; rest=${line#*$'\t'}
    if [[ "$kind" == NOPLUGIN ]]; then
      fail "theme_sync: mode '${rest%%$'\t'*}' maps to scheme '${rest##*$'\t'}' with no entry in plugin_of"
      _map_bad=1
    elif [[ "$kind" == NEED ]]; then
      # NB: not `d` -- that is the dim-colour global at the top of this file.
      _hit=0
      for _decl in "${_declared[@]}"; do [[ "$_decl" == "$rest" ]] && _hit=1 && break; done
      (( _hit )) || { fail "theme_sync.plugin_of names '$rest', but themes.lua declares no such plugin"; _map_bad=1; }
    fi
  done
  # A live enabled=false in themes.lua means a theme that silently never
  # installs. Disabling belongs in disabled.lua, where it is deliberate.
  if grep -nE '^[^-]*enabled\s*=\s*false' "$_th" >/dev/null 2>&1; then
    fail "themes.lua has a live 'enabled = false' — a theme that will never install; put it in disabled.lua"
    _map_bad=1
  fi
  (( _map_bad )) || pass "theme_sync map, themes.lua specs and disabled.lua agree"
fi

# ── 12. the docs serve the same clips IMGS/ holds ────────────────────
head_ "doc assets"

# There are two copies of every clip: IMGS/ is where they are recorded to,
# docs/assets/img/ is what GitHub Pages actually serves. Nothing syncs them,
# and a re-shoot that updates only IMGS/ leaves the published manual showing
# the old clip with no error anywhere.
#
# That is not hypothetical. c206da5 re-shot five clips onto doomone so the
# manual would stop looking like a palette jumble, and added clock-tooltip
# -- all into IMGS/ only. The site kept serving the tokyonight/gruvbox/
# kanagawa/catppuccin/nord versions the commit existed to replace, and
# clock-tooltip was referenced by no page at all.
#
# Files that live on only ONE side are fine and deliberate: wordmark-*.png
# are README assets, film-poster.jpg and real-desktop.png are page
# furniture. Only a basename present in both has to match.
_img_bad=0
_img_n=0
if [[ ! -d IMGS || ! -d docs/assets/img ]]; then
  skip "clip sync (IMGS/ or docs/assets/img/ missing)"
else
  for _src in IMGS/*; do
    [[ -f "$_src" ]] || continue
    _b="${_src##*/}"
    _dst="docs/assets/img/$_b"
    [[ -f "$_dst" ]] || continue
    _img_n=$((_img_n + 1))
    if ! cmp -s "$_src" "$_dst"; then
      fail "docs/assets/img/$_b differs from IMGS/$_b — the site is serving the older clip"
      _img_bad=1
    fi
  done
  (( _img_bad )) || pass "$_img_n clips identical in IMGS/ and docs/assets/img/"
fi

# A clip nobody links to is a clip nobody sees. Catches the other half of
# the same failure: recorded, committed, and then never put on a page.
_orphan=0
if [[ -d docs/assets/img ]]; then
  for _src in docs/assets/img/*; do
    [[ -f "$_src" ]] || continue
    _b="${_src##*/}"
    grep -qF "assets/img/$_b" docs/*.html 2>/dev/null && continue
    warn "docs/assets/img/$_b is referenced by no page"
    _orphan=1
  done
  (( _orphan )) || pass "every file in docs/assets/img/ is used by a page"
fi

# ── 13. the docs' step count and list match MOD_ORDER ────────────────
head_ "wizard steps vs docs"

# A default run is MOD_ORDER minus OPTIN_MODS, and the number is NOT
# hardware-dependent -- PICKED_IDS is built by filtering opt-ins and nothing
# else, so it is the same on every machine. Five places in docs/ state it as
# a fixed number, and install-git.html lists every step by id and in order.
#
# Add a module and forget those, and the manual quietly describes a wizard
# that no longer exists. That is not hypothetical in the other direction:
# `hintium` was added on 2026-08-05 and took the count 46 -> 47, which is
# why screenshots and notes from 2026-08-03/04 legitimately say 46. Both
# were right when written. Only a check keeps them right.
_ws_src="$(sed -n '/^MOD_ORDER=(/,/^)/p' installScripts/wizard.sh)"
if [[ -z "$_ws_src" ]]; then
  skip "wizard step count (MOD_ORDER not found)"
else
  # shellcheck disable=SC1090,SC2154
  eval "$_ws_src"
  _optin_src="$(grep -E '^OPTIN_MODS=\(' installScripts/wizard.sh)"
  eval "$_optin_src"
  _code_ids=()
  for _id in "${MOD_ORDER[@]}"; do
    _skip=0
    for _o in "${OPTIN_MODS[@]}"; do [[ "$_id" == "$_o" ]] && _skip=1; done
    (( _skip )) || _code_ids+=("$_id")
  done
  _n="${#_code_ids[@]}"

  # Every "<n> steps" claim in the manual -- but only where it is a TOTAL.
  # "32 steps after the cause" and "25 steps later" are distances between
  # steps, not counts of them, and four such sentences exist in the
  # troubleshooting and internals pages. Matching them was the first version
  # of this check and it failed on correct prose.
  _ws_bad=0
  while IFS=: read -r _f _claim; do
    [[ -z "$_claim" ]] && continue
    if [[ "$_claim" != "$_n" ]]; then
      fail "$_f says $_claim steps; wizard.sh runs $_n by default"
      _ws_bad=1
    fi
  done < <(grep -roE '[0-9]+ steps( after| later)?' docs/*.html \
             | grep -vE ' (after|later)$' \
             | sed -E 's/:([0-9]+) steps.*/:\1/' | sort -u)

  # and the enumerated list, ids and order both
  if [[ -f docs/install-git.html ]]; then
    mapfile -t _doc_ids < <(
      sed -n '/Show all .* steps/,/<\/details>/p' docs/install-git.html \
        | grep -oE '<td><code>[a-z0-9-]+</code></td>' \
        | sed 's|<td><code>||; s|</code></td>||'
    )
    if (( ${#_doc_ids[@]} != _n )); then
      fail "install-git.html lists ${#_doc_ids[@]} steps; wizard.sh runs $_n"
      _ws_bad=1
    elif ! diff -q <(printf '%s\n' "${_code_ids[@]}") \
                   <(printf '%s\n' "${_doc_ids[@]}") >/dev/null; then
      fail "install-git.html's step list disagrees with MOD_ORDER (ids or order)"
      _ws_bad=1
    fi
  fi
  (( _ws_bad )) || pass "$_n default steps — every docs claim and the full ordered list agree"
fi

# ── 14. the docs' package count matches what is declared ─────────────
head_ "declared package count"

# Adding one package to one module yaml silently falsifies any prose that
# quotes the total. It did: declaring man-db took the count from 276 to 277
# and left under-the-hood.html saying 276 in the same commit.
#
# The number is MARKED in the HTML rather than matched in prose --
# <span data-count="declared-packages">277</span> -- because the same page
# also says "31 packages" about a rebuild cost and "21 packages" in an
# example prompt, and a `[0-9]+ packages` pattern would fail on both. That
# is the mistake the steps check made first; not repeating it.
if ! command -v pacman >/dev/null 2>&1; then
  skip "declared package count (not an Arch system)"
else
  # Captured whole, then matched in-shell rather than piped through
  # `head -1`. Under `set -Eeuo pipefail` that head closes the pipe as
  # soon as it has its line, wizard.sh takes SIGPIPE (141), pipefail
  # promotes it to the pipeline's status and set -e kills validate.sh
  # mid-run -- silently, since the section header has already printed.
  # It only began firing once --audit grew a section AFTER the
  # "declared:" line, leaving the writer still going when head exits.
  _pkg_audit="$(./installScripts/wizard.sh --audit 2>/dev/null || true)"
  _pkg_declared=""
  [[ "$_pkg_audit" =~ declared:\ ([0-9]+) ]] && _pkg_declared="${BASH_REMATCH[1]}"
  if [[ -z "$_pkg_declared" ]]; then
    skip "declared package count (audit produced no total)"
  else
    _pkg_bad=0
    _pkg_seen=0
    while IFS=: read -r _f _claim; do
      [[ -z "$_claim" ]] && continue
      _pkg_seen=$(( _pkg_seen + 1 ))
      if [[ "$_claim" != "$_pkg_declared" ]]; then
        fail "$_f says $_claim declared packages; the audit counts $_pkg_declared"
        _pkg_bad=1
      fi
    done < <(grep -roE 'data-count="declared-packages">[0-9]+' docs/*.html 2>/dev/null \
               | sed -E 's/:.*>([0-9]+)$/:\1/')
    if (( _pkg_bad )); then
      :
    elif (( _pkg_seen == 0 )); then
      pass "$_pkg_declared declared; no page quotes the total"
    else
      pass "$_pkg_declared declared, and all $_pkg_seen page(s) quoting it agree"
    fi
  fi
fi

# ── result ───────────────────────────────────────────────────────────
echo
if (( FAIL )); then
  printf '%s✗ validate: failures above%s\n' "$r" "$o"
  exit 1
fi
printf '%s✓ validate: all checks passed%s\n' "$g" "$o"
printf '%snext layers: ./wizard.sh --audit · ./container-test.sh · ./vm-test.sh%s\n' "$d" "$o"
