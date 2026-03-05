# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Diagnostic toolkit for monitoring network and VM health across a cluster of Linux nodes. All scripts run as root via systemd services on each node.

## Architecture

Three subsystems installed under `/opt/css_diag_agent/` with unified logs in `/var/log/css_diag_agent/`. Configuration in `/opt/css_diag_agent/diagnet.conf`.

### diagnet (core synthetic probes) → `/opt/css_diag_agent/diagnet/`

- **echo_server.py** — TCP echo server on configurable port (default 9400). One per node.
- **diagnet.sh** — Continuous probe loop (default every 5s) testing each peer with ICMP ping, TCP connect, application-level echo RTT, and DNS resolution. Triggers snapshot + tcpdump + sar capture when thresholds are exceeded. Cooldown guard (default 300s) prevents trigger storms.
- **diagnet_report.sh** — One-shot log parser: extracts events in a time window and prints failure/slow counts.

### vmwatch (jitter and infrastructure health) → `/opt/css_diag_agent/vmwatch/`

- **vmwatch.sh** — Heartbeat loop (default 1s). Detects scheduling jitter, periodic TCP connect checks, periodic disk fsync latency checks. Triggers snapshot + tcpdump on jitter events.
- **snapshot.sh** — Comprehensive system snapshot (clocksource, time sync, CPU, memory, IRQ, disk I/O, network, kernel warnings, top processes). Saved as `.tgz`.
- **tcpdump.sh** — Short (65s) packet capture filtered to peer IPs/ports. Lock file with 5-min cooldown.

### alerts (periodic summary) → `/opt/css_diag_agent/alerts/`

- **diagnet_alert.sh** — Runs every 5 min (systemd timer). Reads last 15 min from both logs, counts incidents, logs to syslog, optionally emails root. Exit code 2 = incidents found.

## Installation

```bash
chmod +x install.sh && ./install.sh          # install all
./install.sh --diagnet                        # only probes + echo server
./install.sh --vmwatch                        # only jitter detector
./install.sh --alerts                         # only periodic summaries
```

Edit `diagnet.conf` before installing to set peer IPs, port, and thresholds. The installer copies it to `/opt/css_diag_agent/diagnet.conf` only if it doesn't already exist.

## Configuration (`diagnet.conf`)

All variables are centralized in `diagnet.conf`, sourced by every script at startup.

| Variable | Default | Used by |
|---|---|---|
| `PEER_IPS` | *(required)* | diagnet.sh, vmwatch.sh |
| `PEER_PORT` | 9400 | all (echo server, probes) |
| `PERIOD_SEC` | 5 | diagnet.sh |
| `PERIOD_MS` | 1000 | vmwatch.sh |
| `PING_THRESH_MS` | 50 | diagnet.sh |
| `TCP_THRESH_MS` | 300 | diagnet.sh |
| `ECHO_THRESH_MS` | 500 | diagnet.sh |
| `JITTER_THRESHOLD_MS` | 200 | vmwatch.sh |
| `TRIGGER_COOLDOWN_SEC` | 300 | diagnet.sh |
| `DNS_TARGETS` | *(empty = disabled)* | diagnet.sh |
| `DNS_THRESH_MS` | 200 | diagnet.sh |
| `DIAGNOSTIC_WINDOW_MIN` | 15 | diagnet_alert.sh |

## Log location (unified)

All logs and artifacts go to `/var/log/css_diag_agent/`:

- `diagnet.log` — probe results (auto-rotates at 50MB)
- `vmwatch.log` — heartbeats and events
- `alerts.log` — periodic summaries
- `snapshot_*.tgz` — system snapshots
- `pcap_*.pcap` — packet captures
- `sar_1s_*.sadc` — sar captures
- `tcpdump.log` — tcpdump capture log

## Conventions

- All scripts use `#!/usr/bin/env bash` with `set -euo pipefail`
- Log format: `ISO-8601-UTC [hostname] EVENT_TYPE key=value ...`
- Event types: `{PROBE}_{OK|FAIL|SLOW_TRIGGER}` (e.g., `PING_OK`, `TCP_SLOW_TRIGGER`, `DNS_FAIL`, `SCHED_JITTER`)
- Spanish used in user-facing messages and comments
