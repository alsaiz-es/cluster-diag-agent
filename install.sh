#!/usr/bin/env bash
set -euo pipefail

# Unified installer for cluster_diag_agent
# Usage: ./install.sh [--all | --diagnet | --vmwatch | --alerts | --status | --uninstall]
#   No arguments defaults to --all
# Compatible with systemd and init.d (auto-detection)

BASE="/opt/cluster_diag_agent"
LOG_DIR="/var/log/cluster_diag_agent"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Detect init system
if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
  INIT_SYS="systemd"
else
  INIT_SYS="initd"
fi

mkdir -p "$BASE" "$LOG_DIR"

# Install conf only if it does not exist (do not overwrite user configuration)
if [[ ! -f "$BASE/diagnet.conf" ]]; then
  install -m 0644 "${SCRIPT_DIR}/diagnet.conf" "$BASE/diagnet.conf"
  echo "Configuration installed at $BASE/diagnet.conf — edit for your environment."
else
  echo "Existing configuration at $BASE/diagnet.conf — not overwritten."
fi

echo "Init system detected: $INIT_SYS"

# --- systemd functions ---

systemd_install_diagnet() {
  install -m 0644 "${SCRIPT_DIR}/diagnet/echo_server.service" /etc/systemd/system/
  install -m 0644 "${SCRIPT_DIR}/diagnet/diagnet.service"     /etc/systemd/system/
  systemctl daemon-reload
  systemctl enable --now echo_server.service
  systemctl enable --now diagnet.service
}

systemd_install_vmwatch() {
  install -m 0644 "${SCRIPT_DIR}/vmwatch/vmwatch.service" /etc/systemd/system/
  systemctl daemon-reload
  systemctl enable --now vmwatch.service
}

systemd_install_alerts() {
  install -m 0644 "${SCRIPT_DIR}/alerts/diagnet-alert.service" /etc/systemd/system/
  install -m 0644 "${SCRIPT_DIR}/alerts/diagnet-alert.timer"   /etc/systemd/system/
  systemctl daemon-reload
  systemctl enable --now diagnet-alert.timer
}

systemd_status() {
  local units=(echo_server.service diagnet.service vmwatch.service diagnet-alert.timer)
  for unit in "${units[@]}"; do
    printf "  %-28s " "$unit"
    if systemctl is-enabled "$unit" 2>/dev/null | grep -q enabled; then
      systemctl is-active "$unit" 2>/dev/null || true
    else
      echo "not installed"
    fi
  done
}

systemd_uninstall() {
  for svc in diagnet-alert.timer diagnet-alert.service echo_server.service diagnet.service vmwatch.service; do
    systemctl disable --now "$svc" 2>/dev/null || true
    rm -f "/etc/systemd/system/$svc"
  done
  systemctl daemon-reload
}

# --- init.d functions ---

initd_install_svc() {
  local src="$1" name="$2"
  install -m 0755 "$src" "/etc/init.d/${name}"
  if command -v update-rc.d >/dev/null 2>&1; then
    update-rc.d "$name" defaults
  elif command -v chkconfig >/dev/null 2>&1; then
    chkconfig --add "$name"
    chkconfig "$name" on
  fi
  "/etc/init.d/${name}" start
}

initd_install_diagnet() {
  initd_install_svc "${SCRIPT_DIR}/diagnet/echo_server.init" "cluster-echo-server"
  initd_install_svc "${SCRIPT_DIR}/diagnet/diagnet.init" "cluster-diagnet"
}

initd_install_vmwatch() {
  initd_install_svc "${SCRIPT_DIR}/vmwatch/vmwatch.init" "cluster-vmwatch"
}

initd_install_alerts() {
  install -m 0644 "${SCRIPT_DIR}/alerts/diagnet-alert.cron" /etc/cron.d/cluster-diagnet-alert
}

initd_status() {
  local svcs=(cluster-echo-server cluster-diagnet cluster-vmwatch)
  for svc in "${svcs[@]}"; do
    printf "  %-28s " "$svc"
    if [ -x "/etc/init.d/${svc}" ]; then
      "/etc/init.d/${svc}" status 2>/dev/null || true
    else
      echo "not installed"
    fi
  done
  printf "  %-28s " "cluster-diagnet-alert (cron)"
  if [ -f /etc/cron.d/cluster-diagnet-alert ]; then
    echo "installed"
  else
    echo "not installed"
  fi
}

initd_uninstall() {
  for svc in cluster-diagnet cluster-echo-server cluster-vmwatch; do
    if [ -x "/etc/init.d/${svc}" ]; then
      "/etc/init.d/${svc}" stop 2>/dev/null || true
      if command -v update-rc.d >/dev/null 2>&1; then
        update-rc.d -f "$svc" remove
      elif command -v chkconfig >/dev/null 2>&1; then
        chkconfig --del "$svc"
      fi
      rm -f "/etc/init.d/${svc}"
    fi
  done
  rm -f /etc/cron.d/cluster-diagnet-alert
}

# --- Common install functions ---

install_diagnet() {
  local D="$BASE/diagnet"; mkdir -p "$D"
  install -m 0755 "${SCRIPT_DIR}/diagnet/diagnet.sh"        "$D/"
  install -m 0755 "${SCRIPT_DIR}/diagnet/echo_server.py"    "$D/"
  install -m 0755 "${SCRIPT_DIR}/diagnet/diagnet_report.sh" "$D/"
  "${INIT_SYS}_install_diagnet"
  echo "DiagNet installed. Echo on :$(grep -oP 'PEER_PORT=\K[0-9]+' "$BASE/diagnet.conf" 2>/dev/null || echo 9400) and probes active."
}

install_vmwatch() {
  local D="$BASE/vmwatch"; mkdir -p "$D"
  install -m 0755 "${SCRIPT_DIR}/vmwatch/vmwatch.sh"  "$D/"
  install -m 0755 "${SCRIPT_DIR}/vmwatch/snapshot.sh"  "$D/"
  install -m 0755 "${SCRIPT_DIR}/vmwatch/tcpdump.sh"   "$D/"
  "${INIT_SYS}_install_vmwatch"
  echo "VMWatch installed."
}

install_alerts() {
  local D="$BASE/alerts"; mkdir -p "$D"
  install -m 0755 "${SCRIPT_DIR}/alerts/diagnet_alert.sh" "$D/"
  "${INIT_SYS}_install_alerts"
  echo "Alerts installed (every 5 min)."
}

show_status() {
  echo "=== cluster_diag_agent — status ($INIT_SYS) ==="
  echo "Conf: $BASE/diagnet.conf $([ -f "$BASE/diagnet.conf" ] && echo '[OK]' || echo '[MISSING]')"
  echo "Logs: $LOG_DIR"
  echo
  "${INIT_SYS}_status"
}

do_uninstall() {
  echo "Stopping and disabling services ($INIT_SYS)..."
  "${INIT_SYS}_uninstall"
  echo "Services removed."
  echo "Binaries in $BASE and logs in $LOG_DIR are NOT deleted (for safety)."
  echo "To remove completely: rm -rf $BASE $LOG_DIR"
}

MODE="${1:---all}"
case "$MODE" in
  --all)       install_diagnet; install_vmwatch; install_alerts ;;
  --diagnet)   install_diagnet ;;
  --vmwatch)   install_vmwatch ;;
  --alerts)    install_alerts ;;
  --status)    show_status; exit 0 ;;
  --uninstall) do_uninstall; exit 0 ;;
  *)           echo "Usage: $0 [--all | --diagnet | --vmwatch | --alerts | --status | --uninstall]"; exit 1 ;;
esac

echo "Logs at: $LOG_DIR"
echo "Conf at: $BASE/diagnet.conf"
