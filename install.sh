#!/usr/bin/env bash
set -euo pipefail

# Instalador unificado css_diag_agent
# Uso: ./install.sh [--all | --diagnet | --vmwatch | --alerts | --status | --uninstall]
#   Sin argumentos equivale a --all

BASE="/opt/css_diag_agent"
LOG_DIR="/var/log/css_diag_agent"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "$BASE" "$LOG_DIR"

# Instalar conf solo si no existe (no machacar configuración del usuario)
if [[ ! -f "$BASE/diagnet.conf" ]]; then
  install -m 0644 "${SCRIPT_DIR}/diagnet.conf" "$BASE/diagnet.conf"
  echo "Configuración instalada en $BASE/diagnet.conf — editar según entorno."
else
  echo "Configuración existente en $BASE/diagnet.conf — no se sobreescribe."
fi

install_diagnet() {
  local D="$BASE/diagnet"; mkdir -p "$D"
  install -m 0755 "${SCRIPT_DIR}/diagnet/diagnet.sh"       "$D/"
  install -m 0755 "${SCRIPT_DIR}/diagnet/echo_server.py"   "$D/"
  install -m 0755 "${SCRIPT_DIR}/diagnet/diagnet_report.sh" "$D/"
  install -m 0644 "${SCRIPT_DIR}/diagnet/echo_server.service" /etc/systemd/system/
  install -m 0644 "${SCRIPT_DIR}/diagnet/diagnet.service"     /etc/systemd/system/
  systemctl daemon-reload
  systemctl enable --now echo_server.service
  systemctl enable --now diagnet.service
  echo "DiagNet instalado. Echo en :$(grep -oP 'PEER_PORT=\K[0-9]+' "$BASE/diagnet.conf" 2>/dev/null || echo 9400) y sondas activas."
}

install_vmwatch() {
  local D="$BASE/vmwatch"; mkdir -p "$D"
  install -m 0755 "${SCRIPT_DIR}/vmwatch/vmwatch.sh"  "$D/"
  install -m 0755 "${SCRIPT_DIR}/vmwatch/snapshot.sh"  "$D/"
  install -m 0755 "${SCRIPT_DIR}/vmwatch/tcpdump.sh"   "$D/"
  install -m 0644 "${SCRIPT_DIR}/vmwatch/vmwatch.service" /etc/systemd/system/
  systemctl daemon-reload
  systemctl enable --now vmwatch.service
  echo "VMWatch instalado."
}

install_alerts() {
  local D="$BASE/alerts"; mkdir -p "$D"
  install -m 0755 "${SCRIPT_DIR}/alerts/diagnet_alert.sh"    "$D/"
  install -m 0644 "${SCRIPT_DIR}/alerts/diagnet-alert.service" /etc/systemd/system/
  install -m 0644 "${SCRIPT_DIR}/alerts/diagnet-alert.timer"   /etc/systemd/system/
  systemctl daemon-reload
  systemctl enable --now diagnet-alert.timer
  echo "Alertas instaladas (cada 5 min)."
}

SERVICES=(echo_server diagnet vmwatch diagnet-alert)

show_status() {
  echo "=== css_diag_agent — estado ==="
  echo "Conf: $BASE/diagnet.conf $([ -f "$BASE/diagnet.conf" ] && echo '[OK]' || echo '[NO EXISTE]')"
  echo "Logs: $LOG_DIR"
  echo
  for svc in "${SERVICES[@]}"; do
    local unit="${svc}.service"
    [[ "$svc" == "diagnet-alert" ]] && unit="diagnet-alert.timer"
    printf "  %-28s " "$unit"
    if systemctl is-enabled "$unit" 2>/dev/null | grep -q enabled; then
      systemctl is-active "$unit" 2>/dev/null || true
    else
      echo "no instalado"
    fi
  done
}

do_uninstall() {
  echo "Parando y deshabilitando servicios..."
  for svc in diagnet-alert.timer diagnet-alert.service echo_server.service diagnet.service vmwatch.service; do
    systemctl disable --now "$svc" 2>/dev/null || true
    rm -f "/etc/systemd/system/$svc"
  done
  systemctl daemon-reload
  echo "Servicios eliminados."
  echo "Binarios en $BASE y logs en $LOG_DIR NO se borran (por seguridad)."
  echo "Para eliminar completamente: rm -rf $BASE $LOG_DIR"
}

MODE="${1:---all}"
case "$MODE" in
  --all)       install_diagnet; install_vmwatch; install_alerts ;;
  --diagnet)   install_diagnet ;;
  --vmwatch)   install_vmwatch ;;
  --alerts)    install_alerts ;;
  --status)    show_status; exit 0 ;;
  --uninstall) do_uninstall; exit 0 ;;
  *)           echo "Uso: $0 [--all | --diagnet | --vmwatch | --alerts | --status | --uninstall]"; exit 1 ;;
esac

echo "Logs en: $LOG_DIR"
echo "Conf en: $BASE/diagnet.conf"
