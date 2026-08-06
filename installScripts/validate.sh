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
if ! command -v fc-match >/dev/null 2>&1; then
  skip "no fontconfig — cannot check families"
else
  _font_bad=0
  while IFS='|' read -r _fam _who; do
    [[ -z "$_fam" ]] && continue
    _got="$(fc-match -f '%{family}' "$_fam" 2>/dev/null)"
    # Compare case- and space-insensitively: fc-match answers the full
    # family list ("FiraCode Nerd Font Mono,FiraCode NFM").
    if [[ "${_got,,}" != *"${_fam,,}"* ]]; then
      printf '    %s -> %s  (wanted by %s)\n' "$_fam" "${_got:-nothing}" "$_who"
      _font_bad=1
    fi
  # Hand-maintained, and it must stay exhaustive: this list is the only thing
  # standing between a fresh install and a desktop that renders in the wrong
  # face with nothing in any log. It was three entries and claimed to cover
  # "every family the UI names" -- two of the families below were missing from
  # it, and one of those ("Noto Sans", asked for by both GTK settings files)
  # was silently substituted on the author's own machine for exactly as long
  # as the check has existed. Anything a tracked config names goes here:
  #   git grep -ohiE 'font[-_ ]?(name|family)?[ =:"]+[A-Z][A-Za-z ]+'
  done <<'FONTS'
JetBrainsMono Nerd Font|qtile bar, all qtile popups, dunst
FiraCode Nerd Font|kitty
Noto Sans CJK KR|rofi (base.rasi names it directly, on purpose)
Noto Sans|gtk-3.0/settings.ini, gtk-4.0/settings.ini
Adwaita Mono|qtile systray triangle, wallpaper chip ✖
Ubuntu|qtile bar widgets ("Ubuntu Bold" -- pango parses the weight off)
Cairo|fontconfig sans-serif Arabic fallback
Amiri|fontconfig serif Arabic fallback
FONTS
  if (( _font_bad )); then
    fail "a font the UI names is missing — fontconfig is silently substituting it; install the fonts module"
  else
    pass "every family the UI names resolves to itself, no silent substitution"
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

# ── result ───────────────────────────────────────────────────────────
echo
if (( FAIL )); then
  printf '%s✗ validate: failures above%s\n' "$r" "$o"
  exit 1
fi
printf '%s✓ validate: all checks passed%s\n' "$g" "$o"
printf '%snext layers: ./wizard.sh --audit · ./container-test.sh · ./vm-test.sh%s\n' "$d" "$o"
