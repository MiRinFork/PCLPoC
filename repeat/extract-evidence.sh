#!/usr/bin/env bash
# Copy the demo evidence out of the FAT toolkit image. Run only after shutdown.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VM_DIR="${VM_DIR:-$HOME/.HHD/PCLPoC-VM}"
OUT="${1:-$ROOT/evidence}"

if pgrep -f "qemu-system.*PCLPoC-2.99.0.1" >/dev/null 2>&1; then
    echo "VM is still running; shut it down before extracting evidence" >&2
    exit 1
fi
if [[ ! -f "$VM_DIR/toolkit.img" ]]; then
    echo "missing: $VM_DIR/toolkit.img" >&2
    exit 1
fi
if ! mdir -i "$VM_DIR/toolkit.img@@1M" ::/pcl-test/evidence >/dev/null 2>&1; then
    echo "no evidence directory in the toolkit image" >&2
    exit 1
fi

mkdir -p "$OUT"
mcopy -s -i "$VM_DIR/toolkit.img@@1M" "::/pcl-test/evidence/*" "$OUT/"
find "$OUT" -maxdepth 2 -type f -printf '%p %s bytes\n' | sort
