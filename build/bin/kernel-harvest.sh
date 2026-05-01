#!/bin/bash
# kernel-harvest.sh
# ------------------
# Copies kernel modules listed in build/config/modules.list
# from /lib/modules/<kernelversion> to src/kernel/lib/modules/<kernelversion>
# preserving directory structure.
#
# The kernel version is determined from the first directory found under
# /lib/modules/ (uname -r is unreliable in Docker environments).
# Optionally pass the kernel version as the first argument.
#
# thomas@linuxmuster.net
# 20260429
# ------------------

source build/conf.d/0_general

if [[ -n "$1" ]]; then
    KERNELVER="$1"
else
    KERNELVER="$(ls /lib/modules/ | head -1)"
fi

SRCMODDIR="/lib/modules/$KERNELVER"
DSTMODDIR="$KERNELDIR/lib/modules/$KERNELVER"

if [[ ! -f "$MODULESLIST" ]]; then
    echo "Error: modules list not found: $MODULESLIST"
    exit 1
fi

if [[ -z "$KERNELVER" ]]; then
    echo "Error: could not determine kernel version from /lib/modules/"
    exit 1
fi

if [[ ! -d "$SRCMODDIR" ]]; then
    echo "Error: kernel module directory not found: $SRCMODDIR"
    exit 1
fi

echo "Harvesting kernel modules for $KERNELVER"
echo "  Source:      $SRCMODDIR"
echo "  Destination: $DSTMODDIR"

rm -rf "$KERNELDIR/lib"
mkdir -p "$DSTMODDIR"

errors=0
count=0
while IFS= read -r line; do
    [[ -z "$line" || "$line" =~ ^# ]] && continue
    src="$SRCMODDIR/$line"
    dst="$DSTMODDIR/$line"
    if [[ ! -f "$src" ]]; then
        echo "Warning: not found: $src"
        continue
    fi
    install -D -m 644 "$src" "$dst" || { echo "Error copying: $src"; (( errors++ )); continue; }
    (( count++ ))
done < "$MODULESLIST"

echo "Copied $count module(s)."

VMLINUZ="/boot/vmlinuz-$KERNELVER"
DSTVMLINUZ="$KERNELDIR/linbo64"
KPKG="linux-image-$KERNELVER"

echo "Copying kernel image"
echo "  Source:      $VMLINUZ"
echo "  Destination: $DSTVMLINUZ"

mkdir -p "$(dirname "$DSTVMLINUZ")"

sudo install -m 644 "$VMLINUZ" "$DSTVMLINUZ" \
    && sudo chown build:build "$DSTVMLINUZ" \
    || { echo "Error copying kernel image"; (( errors++ )); }

echo "$KERNELVER" > "$KERNELDIR/version"

if [[ $errors -gt 0 ]]; then
    echo "Completed with $errors error(s)."
    exit 1
fi

echo "Done."
