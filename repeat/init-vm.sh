#!/usr/bin/env bash
# Create a fresh VM disk and copy the toolkit image into the VM directory.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VM_DIR="${VM_DIR:-$HOME/.HHD/PCLPoC-VM}"
FORCE=0

if [[ "${1:-}" == "--force" ]]; then
    FORCE=1
fi

if [[ ! -f "$ROOT/toolkit.img" ]]; then
    "$ROOT/build-toolkit.sh"
fi

if [[ -e "$VM_DIR/disk.qcow2" && "$FORCE" -ne 1 ]]; then
    echo "$VM_DIR/disk.qcow2 already exists; use --force to replace it" >&2
    exit 1
fi

mkdir -p "$VM_DIR"
if [[ "$FORCE" -eq 1 ]]; then
    rm -f "$VM_DIR/disk.qcow2"
fi
qemu-img create -f qcow2 "$VM_DIR/disk.qcow2" 60G
cp -f "$ROOT/toolkit.img" "$VM_DIR/toolkit.img"

echo "VM_DIR: $VM_DIR"
ls -lh "$VM_DIR"
