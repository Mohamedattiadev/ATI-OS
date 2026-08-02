#!/usr/bin/env bash
# service_trim.sh — interactive audit of enabled services. Suggests disable
# for heavy services you may not need on every boot.
#
# Per service: prompts y/n. Y = disable + stop (revert: systemctl enable --now X).
set -Eeuo pipefail

# No RED: this script reports (ok/warn/skip) and never hard-fails.
GREEN="\033[1;32m"; YELLOW="\033[1;33m"; BLUE="\033[1;34m"; RESET="\033[0m"
info() { echo -e "${BLUE}==>${RESET} $*"; }
ok()   { echo -e "${GREEN}✔${RESET} $*"; }
warn() { echo -e "${YELLOW}⚠${RESET} $*"; }

[[ $EUID -ne 0 ]] || { echo "Run as your user (uses sudo)."; exit 1; }
command -v systemctl >/dev/null 2>&1 || { echo "systemd not present — nothing to trim."; exit 0; }
command -v sudo >/dev/null 2>&1 || { echo "sudo is required but not installed."; exit 1; }

# Every prompt below defaults to "keep". Without a tty `read` returns 1 at EOF,
# which under `set -e` would abort the script mid-list instead — so the loop
# tolerates the failure and falls through to the safe default.
ask() {
  local prompt="$1" reply=""
  read -rp "$prompt" reply || reply=""
  [[ "$reply" == "y" || "$reply" == "Y" ]]
}

sudo -v

# Heavy services often not needed every boot
CANDIDATES=(
  "docker.service|Docker (3-4s boot cost). Start on-demand: 'sudo systemctl start docker'"
  "containerd.service|Docker's runtime, disable together with docker"
  "postgresql.service|Postgres DB (500ms). Start on-demand for dev"
  "tailscaled.service|Tailscale VPN (600ms). Enable when needed"
  "NetworkManager-wait-online.service|Blocks boot until online; usually not needed"
  "sshd.service|SSH daemon; disable if you never ssh IN to this laptop"
  "bluetooth.service|Bluetooth stack; disable if never used — this is what the Mod+P b picker talks to, it goes dead without it"
  "nvidia-hibernate.service|NVIDIA hibernate hook; disable on Intel-only"
  "nvidia-resume.service|NVIDIA resume hook; disable on Intel-only"
  "nvidia-suspend.service|NVIDIA suspend hook; disable on Intel-only"
)

echo
info "Interactive service disable — press y to disable+stop, anything else to keep."
echo

# The nvidia-* hooks are listed as "disable on Intel-only" — which is exactly
# what this repo's author's laptop is. On a machine that DOES have an NVIDIA
# card, answering y to that prompt breaks suspend/resume, so never offer it.
HAS_NVIDIA=false
if command -v lspci >/dev/null 2>&1 && lspci | grep -qi nvidia; then
  HAS_NVIDIA=true
fi

for entry in "${CANDIDATES[@]}"; do
  svc="${entry%%|*}"
  desc="${entry#*|}"

  if $HAS_NVIDIA && [[ "$svc" == nvidia-* ]]; then
    echo "  ○ $svc (NVIDIA GPU present) — skip"
    continue
  fi

  if ! systemctl is-enabled "$svc" &>/dev/null; then
    echo "  ○ $svc (not enabled) — skip"
    continue
  fi

  echo -e "  ${YELLOW}$svc${RESET}  — $desc"
  if ask "    disable? [y/N] "; then
    # `pipefail` is on, so a failing systemctl would take the whole script down
    # here — and the old code printed "disabled" from the sed's exit status
    # regardless, claiming success for a unit that is still enabled.
    if sudo systemctl disable --now "$svc" 2>&1 | sed 's/^/      /'; then
      ok "    disabled $svc"
    else
      warn "    could not disable $svc — left as-is"
    fi
  else
    echo "    kept."
  fi
  echo
done

# NetworkManager vs iwd conflict
if systemctl is-enabled NetworkManager.service &>/dev/null && systemctl is-enabled iwd.service &>/dev/null; then
  warn "Both NetworkManager AND iwd are enabled."
  echo "  NetworkManager uses iwd as backend when configured; running iwd separately = duplicate."
  if ask "  Disable standalone iwd.service (NM will still use iwd backend)? [y/N] "; then
    if sudo systemctl disable --now iwd.service; then
      ok "iwd standalone disabled"
    else
      warn "could not disable iwd.service — left as-is"
    fi
  fi
fi

echo
ok "DONE. New boot time after next reboot:"
echo "  systemd-analyze"
echo "  systemd-analyze blame | head"
