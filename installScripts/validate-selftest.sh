#!/usr/bin/env bash
# validate-selftest.sh — prove validate.sh's checks actually fail when they
# should, without touching the running machine.
#
# WHY THIS EXISTS
#
# A check nobody has seen fail is a check nobody knows works. The honest way
# to test one is to reintroduce the bug and watch it get caught -- and doing
# that in the live repo is dangerous here, because `~/.config` is
# stow-symlinked INTO it. Editing .config/kitty/kitty.conf to prove the font
# check works edits the running terminal's configuration.
#
# That is not hypothetical. Verifying the derived font check did exactly
# that: kitty.conf and fontconfig/fonts.conf were mutated in place, the
# owner's terminal changed font mid-session, and it only went back when the
# backups were restored a few minutes later. The check was right; the way it
# was tested was not.
#
# So the mutations happen in a detached git worktree. A worktree is a real
# file tree that nothing in `~` points at, so a bogus font family in it
# reaches validate.sh and reaches nothing else.
#
# Usage:  ./validate-selftest.sh [name ...]     (default: all cases)
#         ./validate-selftest.sh --list
set -Eeuo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WT="${SELFTEST_WORKTREE:-${XDG_RUNTIME_DIR:-/tmp}/atios-validate-selftest}"

r=$'\033[31m'; g=$'\033[32m'; d=$'\033[90m'; o=$'\033[0m'
pass_n=0; fail_n=0

# Every case: name | file to edit | python mutation | substring validate must print
#
# Prefix the substring with `warn:` for a check that reports but does not
# fail the run. The orphaned-doc-asset check is one on purpose: a file no
# page references yet may be staged for a page being written, which is worth
# saying out loud and not worth blocking a commit over.
CASES=(
"font-kitty|.config/kitty/kitty.conf|s=s.replace('font_family        FiraCode Nerd Font','font_family        Nonexistent Mono',1)|Nonexistent Mono"
"font-fontconfig|.config/fontconfig/fonts.conf|s=s.replace('    <family>Cairo</family>','    <family>Cairo</family>\\n    <family>Ghost Naskh</family>',1)|Ghost Naskh"
"font-qtile|.config/qtile/config.py|s=s.replace('font=\"Ubuntu Mono\"','font=\"Totally Fake Sans\"',1)|Totally Fake Sans"
"docs-clip-drift|docs/assets/img/layouts.gif|BINARY_COPY:IMGS/overview.gif|differs from IMGS/layouts.gif"
"docs-orphan|docs/assets/img/zz-orphan.gif|BINARY_NEW:IMGS/groups.gif|warn:referenced by no page"
"wizard-count|installScripts/wizard.sh|s=s.replace('  whisper-fast mic-gain scrcpy','  whisper-fast mic-gain scrcpy newmodule',1)|wizard.sh runs 48"
"wizard-order|docs/install-git.html|s=s.replace('<tr><td>2</td><td><code>bootstrap</code></td>','<tr><td>2</td><td><code>zzz-wrong</code></td>',1)|disagrees with MOD_ORDER"
"nvim-disabled|.config/nvim/lua/plugins/themes.lua|s=s.replace('{ \"Mofiqul/dracula.nvim\", lazy = true }','{ \"Mofiqul/dracula.nvim\", lazy = true, enabled = false }',1)|enabled = false"
"pkg-count|docs/under-the-hood.html|s=s.replace('data-count=\"declared-packages\">277','data-count=\"declared-packages\">999',1)|says 999 declared packages"
"nvim-map|.config/nvim/lua/config/theme_sync.lua|s=s.replace('  oxocarbon = \"oxocarbon\",','  oxocarbon = \"oxocarbon\",\\n  bogus = \"bogus-scheme\",',1)|no entry in plugin_of"
)

if [[ "${1:-}" == "--list" ]]; then
  for c in "${CASES[@]}"; do printf '%s\n' "${c%%|*}"; done
  exit 0
fi

# ── the guard that makes this safe ───────────────────────────────────
# If the worktree ever resolved to the live checkout, every mutation below
# would land on the owner's real config. Refuse rather than trust the path.
setup() {
  git -C "$REPO" worktree remove --force "$WT" 2>/dev/null || true
  rm -rf "$WT"
  git -C "$REPO" worktree add --detach --quiet "$WT" HEAD
  local wt_real repo_real
  wt_real="$(cd "$WT" && pwd -P)"; repo_real="$(cd "$REPO" && pwd -P)"
  [[ "$wt_real" != "$repo_real" ]] || { printf '%s✗%s worktree resolved to the live repo — refusing\n' "$r" "$o" >&2; exit 2; }
  # and nothing in ~ may point into it
  local probe; probe="$(readlink -f "$HOME/.config/kitty" 2>/dev/null || true)"
  [[ "$probe" != "$wt_real"/* ]] || { printf '%s✗%s ~/.config points into the worktree — refusing\n' "$r" "$o" >&2; exit 2; }

  # Test what is about to be COMMITTED, not the last commit. A worktree is
  # created at HEAD, so a check still sitting uncommitted in the working
  # tree is simply absent from it -- and the case for that check then
  # "passes validate", which reads exactly like the check being broken. It
  # cost a debugging detour to notice the worktree was running an older
  # validate.sh than the one being tested.
  if ! git -C "$REPO" diff --quiet HEAD -- 2>/dev/null; then
    git -C "$REPO" diff HEAD -- | git -C "$WT" apply --allow-empty - \
      || { printf '%s✗%s could not carry uncommitted changes into the worktree\n' "$r" "$o" >&2; exit 2; }
    printf '%s   carried uncommitted changes into the worktree%s\n' "$d" "$o"
  fi

  # Freeze whatever the worktree now holds as ITS baseline. run_case reverts
  # with `git checkout -- .` between cases, which restores HEAD -- and HEAD
  # does not contain the carried changes, so the first revert would delete
  # the very check being tested and every later case would "pass validate".
  git -C "$WT" add -A
  git -C "$WT" -c user.name=selftest -c user.email=selftest@local \
      commit -q --allow-empty -m 'selftest baseline (throwaway worktree)'
}
teardown() { git -C "$REPO" worktree remove --force "$WT" 2>/dev/null || true; rm -rf "$WT"; }
trap teardown EXIT

run_case() {
  local name="$1" file="$2" mut="$3" want="$4"
  local target="$WT/$file"

  case "$mut" in
    BINARY_COPY:*) cp "$WT/${mut#BINARY_COPY:}" "$target" ;;
    BINARY_NEW:*)  cp "$WT/${mut#BINARY_NEW:}"  "$target" ;;
    *) MUT="$mut" TGT="$target" python3 -c '
import os, pathlib
p = pathlib.Path(os.environ["TGT"]); s = p.read_text()
exec(os.environ["MUT"])
p.write_text(s)' ;;
  esac

  local warn_only=0
  if [[ "$want" == warn:* ]]; then warn_only=1; want="${want#warn:}"; fi

  local out rc=0
  out="$(cd "$WT" && ./installScripts/validate.sh 2>&1)" || rc=$?

  if (( rc == 0 && warn_only == 0 )); then
    printf '  %s✗%s %-16s validate PASSED — the bug was not caught\n' "$r" "$o" "$name"; fail_n=$((fail_n+1))
  elif ! grep -qF -- "$want" <<<"$out"; then
    printf '  %s✗%s %-16s failed, but not for the right reason (wanted %q)\n' "$r" "$o" "$name" "$want"; fail_n=$((fail_n+1))
  else
    printf '  %s✓%s %-16s caught: %s\n' "$g" "$o" "$name" "$(grep -oF -m1 -- "$want" <<<"$out")"; pass_n=$((pass_n+1))
  fi

  git -C "$WT" checkout --quiet -- . 2>/dev/null || true
  git -C "$WT" clean -qfd 2>/dev/null || true
}

setup
printf '%sself-test: mutating %s, never the live repo%s\n\n' "$d" "$WT" "$o"

wanted=("$@")
for c in "${CASES[@]}"; do
  IFS='|' read -r name file mut want <<<"$c"
  if (( ${#wanted[@]} )); then
    hit=0; for w in "${wanted[@]}"; do [[ "$w" == "$name" ]] && hit=1; done
    (( hit )) || continue
  fi
  run_case "$name" "$file" "$mut" "$want"
done

echo
if (( fail_n )); then
  printf '%s✗ self-test: %d of %d checks did not catch their bug%s\n' "$r" "$fail_n" "$((pass_n+fail_n))" "$o"
  exit 1
fi
printf '%s✓ self-test: all %d checks caught their bug%s\n' "$g" "$pass_n" "$o"
