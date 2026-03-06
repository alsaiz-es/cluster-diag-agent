#!/usr/bin/env bash
set -euo pipefail
START="${1:?ISO-8601 UTC e.g. 2025-08-19T06:00:00Z}"; END="${2:?ISO-8601 UTC}"
LOG="${LOG_FILE:-/var/log/css_diag_agent/diagnet.log}"
awk -v S="$START" -v E="$END" 'function iso(s){gsub(/Z/,"",s);return s} BEGIN{s=iso(S);e=iso(E)} $1~/^[0-9-]+T/{t=$1;gsub(/Z/,"",t); if(t>=s && t<=e) print $0}' "$LOG" | tee /tmp/diagnet_window.log >/dev/null
echo "---- SUMMARY ----"
echo "PING_FAIL:" $(grep -c "PING_FAIL" /tmp/diagnet_window.log || true)
echo "PING_SLOW:" $(grep -c "PING_SLOW_TRIGGER" /tmp/diagnet_window.log || true)
echo "TCP_FAIL:"  $(grep -c "TCP_FAIL"  /tmp/diagnet_window.log || true)
echo "TCP_SLOW:"  $(grep -c "TCP_SLOW_TRIGGER" /tmp/diagnet_window.log || true)
echo "ECHO_FAIL:" $(grep -c "ECHO_FAIL" /tmp/diagnet_window.log || true)
echo "ECHO_SLOW:" $(grep -c "ECHO_SLOW_TRIGGER" /tmp/diagnet_window.log || true)
