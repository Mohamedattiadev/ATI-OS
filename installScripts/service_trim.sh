#!/usr/bin/env bash
# service_trim.sh — interactive audit of enabled services. Suggests disable
# for heavy services you may not need on every boot.
#
# Per service: prompts y/n. Y = disable + stop (revert: systemctl enable --now X).
set -Eeuo pipefail

RED="\033[1;31m"; GREEN="\033[1;32m"; YELLOW="\033[1;33m"; BLUE="\033[1;34m"; RESET="\033[0m"
info() { echo -e "${BLUE}==>${RESET} $*"; }
ok()   { echo -e "${GREEN}✔${RESET} $*"; }
warn() { echo -e "${YELLOW}⚠${RESET} $*"; }

sudo -v

# Heavy services often not needed every boot
CANDIDATES=(
  "docker.service|Docker (3-4s boot cost). Start on-demand: 'sudo systemctl start docker'"
  "containerd.service|Docker's runtime, disable together with docker"
  "postgresql.service|Postgres DB (500ms). Start on-demand for dev"
  "tailscaled.service|Tailscale VPN (600ms). Enable when needed"
  "NetworkManager-wait-online.service|Blocks boot until online; usually not needed"
  "sshd.service|SSH daemon; disable if you never ssh IN to this laptop"
  "bluetooth.service|Bluetooth stack; disable if never used"
  "nvidia-hibernate.service|NVIDIA hibernate hook; disable on Intel-only"
  "nvidia-resume.service|NVIDIA resume hook; disable on Intel-only"
  "nvidia-suspend.service|NVIDIA suspend hook; disable on Intel-only"
)

echo
info "Interactive service disable — press y to disable+stop, anything else to keep."
echo

for entry in "${CANDIDATES[@]}"; do
  svc="${entry%%|*}"
  desc="${entry#*|}"

  if ! systemctl is-enabled "$svc" &>/dev/null; then
    echo "  ○ $svc (not enabled) — skip"
    continue
  fi

  echo -e "  ${YELLOW}$svc${RESET}  — $desc"
  read -rp "    disable? [y/N] " ans
  if [[ "$ans" == "y" || "$ans" == "Y" ]]; then
    sudo systemctl disable --now "$svc" 2>&1 | sed 's/^/      /'
    ok "    disabled $svc"
  else
    echo "    kept."
  fi
  echo
done

# NetworkManager vs iwd conflict
if systemctl is-enabled NetworkManager.service &>/dev/null && systemctl is-enabled iwd.service &>/dev/null; then
  warn "Both NetworkManager AND iwd are enabled."
  echo "  NetworkManager uses iwd as backend when configured; running iwd separately = duplicate."
  read -rp "  Disable standalone iwd.service (NM will still use iwd backend)? [y/N] " ans
  if [[ "$ans" == "y" || "$ans" == "Y" ]]; then
    sudo systemctl disable --now iwd.service
    ok "iwd standalone disabled"
  fi
fi

echo
ok "DONE. New boot time after next reboot:"
echo "  systemd-analyze"
echo "  systemd-analyze blame | head"
