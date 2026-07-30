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
if python3 - <<'PY'
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
open("/tmp/.validate_pycount", "w").write(str(len(files)))
PY
then pass "$(cat /tmp/.validate_pycount 2>/dev/null || echo '?') python files parse"
else fail "python syntax errors above"
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
# - bookmarks/urls user data (a bookmark list), not config
# - the test scripts they contain "/home/ati" as the pattern they SEARCH
#   for; matching them here would mean the check can never pass
hits="$(git ls-files -z | xargs -0 grep -In "/home/ati" 2>/dev/null \
  | grep -vE '\.md:' \
  | grep -vE '^[^:]+:[0-9]+:\s*(#|//|--|\*)' \
  | grep -vE '^\.config/qutebrowser/bookmarks/urls:' \
  | grep -vE '^installScripts/(container-test|validate)\.sh:' || true)"
if [[ -n "$hits" ]]; then
  fail "hardcoded /home/ati in tracked files:"
  printf '%s\n' "$hits" | sed 's/^/      /' >&2
else
  pass "no hardcoded home paths (bookmarks + comments excluded)"
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

# ── result ───────────────────────────────────────────────────────────
echo
if (( FAIL )); then
  printf '%s✗ validate: failures above%s\n' "$r" "$o"
  exit 1
fi
printf '%s✓ validate: all checks passed%s\n' "$g" "$o"
printf '%snext layers: ./wizard.sh --audit · ./container-test.sh · ./vm-test.sh%s\n' "$d" "$o"
