#!/usr/bin/env bash
# Build the FAT32 USB toolkit image for the PCL PoC VM.
# Requires: sfdisk, mkfs.vfat (dosfstools), mtools, truncate, dd.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PCL_ZIP="${PCL_ZIP:-}"

if [[ -z "$PCL_ZIP" ]]; then
    PCL_ZIP="$(find "$ROOT/.." -maxdepth 1 -type f -name 'PCL 正式版 2.99.0.1.zip' -print -quit)"
fi
if [[ -z "$PCL_ZIP" ]]; then
    PCL_ZIP="$(find "$ROOT/.." -maxdepth 1 -type f -name 'PCL*.zip' -print -quit)"
fi
if [[ -z "$PCL_ZIP" || ! -f "$PCL_ZIP" ]]; then
    echo "PCL 2.99.0.1 zip not found. Set PCL_ZIP=/path/to/PCL 正式版 2.99.0.1.zip" >&2
    exit 1
fi

HASH="$(sha256sum "$PCL_ZIP" | awk '{print $1}')"
EXPECTED="4d239a62ed66fb9ebcf4633fd881eb098e9a7e4f296f0e414b58aa2f1f7f7830"
if [[ "$HASH" != "$EXPECTED" ]]; then
    echo "PCL zip hash mismatch" >&2
    echo "  got:      $HASH" >&2
    echo "  expected: $EXPECTED" >&2
    exit 1
fi

for tool in sfdisk mkfs.vfat mcopy mmd mdir truncate dd; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "missing tool: $tool" >&2
        exit 1
    fi
done

cp -f "$PCL_ZIP" "$ROOT/toolkit/pcl-test/PCL-2.99.0.1.zip"
rm -f "$ROOT/toolkit.img" "$ROOT/part.img"

truncate -s 512M "$ROOT/toolkit.img"
printf 'label: dos\nstart=2048, size=1046528, type=c\n' | sfdisk -q "$ROOT/toolkit.img"

# FAT32 filesystem for the 511 MiB partition starting at 1 MiB.
mkfs.vfat -C -F 32 -n PCLTOOL "$ROOT/part.img" 523264 >/dev/null
dd if="$ROOT/part.img" of="$ROOT/toolkit.img" bs=1M seek=1 conv=notrunc status=none
rm -f "$ROOT/part.img"

mcopy -i "$ROOT/toolkit.img@@1M" -s "$ROOT/toolkit/autounattend.xml" "$ROOT/toolkit/pcl-test" ::

echo "built: $ROOT/toolkit.img"
mdir -i "$ROOT/toolkit.img@@1M" ::/
