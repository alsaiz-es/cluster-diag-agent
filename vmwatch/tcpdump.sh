#!/usr/bin/env bash
set -euo pipefail
OUTDIR="${1:-/var/log/cluster_diag_agent}"; shift || true; PEERS="${*:-}"; mkdir -p "$OUTDIR"
LOCK="$OUTDIR/tcpdump.lock"; now=$(date +%s); if [[ -f "$LOCK" ]] && (( now - $(stat -c %Y "$LOCK" 2>/dev/null || echo 0) < 300 )); then exit 0; fi; echo $now > "$LOCK"
FILTER=""; for p in $PEERS; do ip="${p%%:*}"; port="${p##*:}"; [[ -n "$FILTER" ]] && FILTER="${FILTER} or "; FILTER="${FILTER}(host ${ip} and port ${port})"; done; [[ -z "$FILTER" ]] && FILTER="tcp"
TS="$(date -u +%Y%m%dT%H%M%SZ)"; PCAP="${OUTDIR}/pcap_${TS}.pcap"
if command -v tcpdump >/dev/null 2>&1; then timeout 65 tcpdump -s0 -i any -w "$PCAP" "$FILTER" >/dev/null 2>&1 || true; echo "PCAP_SAVED $PCAP filter=\"$FILTER\"" >> "$OUTDIR/tcpdump.log"; else echo "TCPDUMP_NOT_FOUND" >> "$OUTDIR/tcpdump.log"; fi
