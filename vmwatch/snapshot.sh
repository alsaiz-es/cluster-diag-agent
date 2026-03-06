#!/usr/bin/env bash
set -uo pipefail
OUTDIR="${1:-/var/log/css_diag_agent}"; HOST="${2:-$(hostname -s || echo unknown)}"; ARG3="${3:-}"; ARG4="${4:-}"; REASON="${5:-manual}"
TS="$(date -u +%Y%m%dT%H%M%SZ)"; SNAPDIR="${OUTDIR}/snapshot_${HOST}_${TS}"; TXT="${SNAPDIR}/snapshot.txt"
mkdir -p "$SNAPDIR"; exec > >(tee -a "$TXT") 2>&1
hr(){ printf -- "------------------------------------------------------------\n"; }; sec(){ echo "== $* =="; }
safe_cat(){ local f="$1"; [[ -e "$f" ]] || return 0; if [[ -r "$f" ]]; then echo "$f: $(cat "$f")"; else echo "$f: (not readable / write-only)"; fi; }
run(){ local title="$1"; shift; sec "$title"; if command -v "$1" >/dev/null 2>&1; then "$@" || echo "[WARN] Failed: $*"; else echo "[INFO] '$1' not available"; fi; }
sec "meta"; date -u; uname -a; uptime; whoami; echo "snapshot_dir=$SNAPDIR"; echo "reason=$REASON arg3=$ARG3 arg4=$ARG4 host=$HOST"; hr
sec "clocksource"; for f in /sys/devices/system/clocksource/clocksource0/*; do safe_cat "$f"; done; (dmesg | egrep -i 'clocksource|tsc|kvm|hyperv|xen|vmware' | tail -n 200) || true; hr
sec "time sync"; (timedatectl 2>/dev/null || true); (chronyc tracking 2>/dev/null || ntpq -pn 2>/dev/null || echo "chrony/ntp not available") || true; hr
run "CPU (lscpu)" lscpu; run "Memory (free -m)" free -m
if command -v vmstat >/dev/null 2>&1; then vmstat 1 5 || true; else echo "vmstat not available (install: sysstat)"; fi
if command -v mpstat >/dev/null 2>&1; then mpstat -P ALL 1 3 || true; else echo "mpstat not available (install: sysstat)"; fi
if command -v pidstat >/dev/null 2>&1; then pidstat -rudwt 1 5 || true; else echo "pidstat not available (install: sysstat)"; fi
hr
sec "irq/affinity and scheduler"; (systemctl is-active irqbalance >/dev/null 2>&1 && systemctl status irqbalance --no-pager -n 0 || echo "irqbalance not active/not installed") || true
(egrep -h . /proc/interrupts 2>/dev/null | sed -n '1,50p') || true
(cat /sys/devices/system/cpu/smt/active 2>/dev/null && echo "SMT: (0=off,1=on)") || true
hr
run "iostat -xz 1 3" iostat -xz 1 3; run "lsblk (rotational/model)" lsblk -o NAME,ROTA,SIZE,MODEL
(dmesg | egrep -i 'blk|nvme|scsi|io error|reset|timeout' | tail -n 200) || true
hr
run "interfaces (ip a)" ip a; run "routes (ip r)" ip r; run "sockets (ss -s)" ss -s
for dev in $(ls /sys/class/net 2>/dev/null); do
  echo "-- ethtool stats/features for $dev --"
  (ethtool -S "$dev" 2>/dev/null || echo "ethtool -S not supported for $dev") || true
  (ethtool -k "$dev" 2>/dev/null || echo "ethtool -k not supported for $dev") || true
done
(dmesg | egrep -i 'NETDEV WATCHDOG|TX timeout|link is (down|up)|reset|fatal|nic' | tail -n 200) || true
(nstat 2>/dev/null || echo "nstat not available") || true
hr
sec "kernel warnings (recent)"; (dmesg -T | egrep -i 'rcu|soft lockup|hard LOCKUP|hung task|blocked for more than|BUG:|WARNING:' | tail -n 200) || true; hr
sec "top (CPU)"; (top -b -n1 -o %CPU | head -n 60) || true
sec "top (MEM)"; (top -b -n1 -o %MEM | head -n 60) || true
(ps -eo pid,comm,pcpu,pmem,psr,pri,ni,stat,etime,wchan,cmd --sort=-pcpu | head -n 50) || true
hr
sec "journalctl -k --since -15 min"; (journalctl -k --since "-15 min" --no-pager 2>/dev/null || echo "journalctl not available") || true; hr
tar -czf "${OUTDIR}/snapshot_${HOST}_${TS}.tgz" -C "$OUTDIR" "$(basename "$SNAPDIR")" || true
echo "Snapshot saved: ${OUTDIR}/snapshot_${HOST}_${TS}.tgz"
exit 0
