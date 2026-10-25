#!/usr/bin/env bash
# Record the QEMU console. Start it before run-vm.sh; it retries the QMP socket.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="${1:-$ROOT/frames/install}"

mkdir -p "$OUT"
exec python3 "$ROOT/record.py" \
    --qmp "$ROOT/run/qmp.sock" \
    --out "$OUT" \
    --interval 0.125 \
    --boot-keys
