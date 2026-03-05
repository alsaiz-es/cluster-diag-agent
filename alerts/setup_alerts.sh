#!/usr/bin/env bash
# Wrapper de compatibilidad — usa install.sh --alerts
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec "$SCRIPT_DIR/install.sh" --alerts
