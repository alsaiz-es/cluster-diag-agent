#!/usr/bin/env bash
set -euo pipefail
BASE="/opt/css_diag_agent"
CONF="${DIAGNET_CONF:-${BASE}/diagnet.conf}"
[[ -f "$CONF" ]] && source "$CONF"
LOG_DIR="${LOG_DIR:-/var/log/css_diag_agent}"
WINDOW="${DIAGNOSTIC_WINDOW_MIN:-15}"
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
SINCE=$(date -u -d "-${WINDOW} min" +%Y-%m-%dT%H:%M:%SZ)
DLOG="${DIAGNET_LOG:-${LOG_DIR}/diagnet.log}"
VLOG="${VMWATCH_LOG:-${LOG_DIR}/vmwatch.log}"
OUT="${OUT_LOG:-${LOG_DIR}/alerts.log}"
mkdir -p "$(dirname "$OUT")"
filter_window(){ local file="$1"; awk -v S="$SINCE" -v E="$NOW" 'function iso(s){gsub(/Z/,"",s);return s} BEGIN{s=iso(S);e=iso(E)} $1~/^[0-9-]+T/{t=$1;gsub(/Z/,"",t); if(t>=s && t<=e) print $0}' "$file"; }
summarize(){ local label="$1"; local data="$2"; echo "### ${label}"; echo "$data" | grep -E "(_SLOW_TRIGGER|_FAIL|SCHED_JITTER|NET_FAIL)" || true; echo; echo "Resumen ${label}:"; echo "  PING_FAIL   : $(echo "$data" | grep -c 'PING_FAIL' || true)"; echo "  PING_SLOW   : $(echo "$data" | grep -c 'PING_SLOW_TRIGGER' || true)"; echo "  TCP_FAIL    : $(echo "$data" | grep -c 'TCP_FAIL' || true)"; echo "  TCP_SLOW    : $(echo "$data" | grep -c 'TCP_SLOW_TRIGGER' || true)"; echo "  ECHO_FAIL   : $(echo "$data" | grep -c 'ECHO_FAIL' || true)"; echo "  ECHO_SLOW   : $(echo "$data" | grep -c 'ECHO_SLOW_TRIGGER' || true)"; echo "  JITTER      : $(echo "$data" | grep -c 'SCHED_JITTER' || true)"; echo "  NET_FAIL    : $(echo "$data" | grep -c 'NET_FAIL' || true)"; echo "  DNS_FAIL    : $(echo "$data" | grep -c 'DNS_FAIL' || true)"; echo "  DNS_SLOW    : $(echo "$data" | grep -c 'DNS_SLOW_TRIGGER' || true)"; echo; }
diag=$( [[ -s "$DLOG" ]] && filter_window "$DLOG" || true )
vmw=$( [[ -s "$VLOG" ]] && filter_window "$VLOG" || true )
NEW_SNAP=$(find "$LOG_DIR" -maxdepth 1 -type f -name "snapshot_*.*.tgz" -newermt "$SINCE" ! -newermt "$NOW" 2>/dev/null | wc -l || echo 0)
NEW_PCAP=$(find "$LOG_DIR" -maxdepth 1 -type f -name "pcap_*.pcap"     -newermt "$SINCE" ! -newermt "$NOW" 2>/dev/null | wc -l || echo 0)
NEW_SAR=$(find "$LOG_DIR" -maxdepth 1 -type f -name "sar_1s_*.sadc" -newermt "$SINCE" ! -newermt "$NOW" 2>/dev/null | wc -l || echo 0)
{ echo "==== DiagNet/VmWatch ALERT resumen (UTC) ===="; echo "Ventana: $SINCE .. $NOW"; echo; [[ -n "$diag" ]] && summarize "DiagNet" "$diag" || { echo "Sin datos DiagNet en la ventana."; echo; }; [[ -n "$vmw" ]] && summarize "VmWatch" "$vmw" || { echo "Sin datos VmWatch en la ventana."; echo; }; echo "Artefactos nuevos: snapshots=$NEW_SNAP pcaps=$NEW_PCAP sar1s=$NEW_SAR"; echo "============================================="; echo; } | tee -a "$OUT"
INC=$(( $(echo "$diag$vmw" | grep -E "(_SLOW_TRIGGER|_FAIL|SCHED_JITTER|NET_FAIL|DNS_FAIL)" -c || true) ))
if command -v logger >/dev/null 2>&1; then
  if (( INC > 0 )); then logger -p user.warning "DiagNet/VmWatch: ${INC} incidencias en ${WINDOW} min (ver $OUT)"; else logger -p user.info "DiagNet/VmWatch: sin incidencias en ${WINDOW} min"; fi
fi
if (( INC > 0 )) && command -v mail >/dev/null 2>&1; then mail -s "ALERTA DiagNet/VmWatch (${INC} incidencias)" root@localhost < "$OUT" || true; fi
exit $(( INC > 0 ? 2 : 0 ))
