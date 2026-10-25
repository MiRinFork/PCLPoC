#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VM_DIR="${VM_DIR:-$HOME/.HHD/PCLPoC-VM}"
ISO="${ISO:-$HOME/.HHD/en-us_windows_10_enterprise_ltsc_2021_x64_dvd_d289cf96.iso}"
PHASE="${1:-install}"
RUN="$ROOT/run"

mkdir -p "$RUN"

for f in "$VM_DIR/disk.qcow2" "$VM_DIR/toolkit.img"; do
    if [[ ! -f "$f" ]]; then
        echo "missing: $f" >&2
        exit 1
    fi
done
if [[ "$PHASE" == "install" && ! -f "$ISO" ]]; then
    echo "missing ISO: $ISO" >&2
    exit 1
fi
if pgrep -f "qemu-system.*PCLPoC-2.99.0.1" >/dev/null 2>&1; then
    echo "PCLPoC VM is already running" >&2
    exit 1
fi

rm -f "$RUN/qmp.sock" "$RUN/qemu.pid"

args=(
    -name PCLPoC-2.99.0.1
    -machine q35,accel=kvm
    -cpu host
    -smp 4,sockets=1,cores=4,threads=1
    -m 4096
    -rtc base=localtime,driftfix=slew
    -vga std
    -vnc 127.0.0.1:2
    -qmp "unix:$RUN/qmp.sock,server=on,wait=off"
    -pidfile "$RUN/qemu.pid"
    -drive "file=$VM_DIR/disk.qcow2,if=none,id=disk0,format=qcow2,cache=writeback,discard=unmap"
    -device ahci,id=ahci0
    -device "ide-hd,drive=disk0,bus=ahci0.0,bootindex=2"
    -drive "file=$VM_DIR/toolkit.img,if=none,id=usb0,format=raw,cache=writeback"
    -device qemu-xhci,id=xhci
    -device "usb-storage,drive=usb0,bus=xhci.0,removable=on,serial=PCLTOOL"
)

if [[ "$PHASE" == "install" ]]; then
    args+=(
        -boot order=d,menu=off
        -drive "file=$ISO,if=none,id=cd0,format=raw,media=cdrom,readonly=on"
        -device "ide-cd,drive=cd0,bus=ahci0.1,bootindex=1"
    )
else
    args+=(-boot order=c,menu=off)
fi

qemu-system-x86_64 "${args[@]}" -daemonize

echo "VM started: phase=$PHASE"
echo "pid: $(cat "$RUN/qemu.pid" 2>/dev/null || echo unknown)"
echo "QMP: $RUN/qmp.sock"
echo "VNC: 127.0.0.1:5902 (localhost only)"
