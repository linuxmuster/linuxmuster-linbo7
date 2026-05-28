#!/bin/bash
# kernel-harvester.sh
# ------------------
# Copies kernel modules listed in build/config/modules.d/*
# from /lib/modules/<kernelversion> to src/kernel/lib/modules/<kernelversion>
# preserving directory structure.
#
# The kernel version is determined from the first directory found under
# /lib/modules/ (uname -r is unreliable in Docker environments).
# Optionally pass the kernel version as the first argument.
#
# thomas@linuxmuster.net
# 20260514
# ------------------

source build/config/build.env

# use kernel version from argument if provided
[[ -n "$1" ]] && KERNELVER="$1"

if [[ ! -d "$MODLISTDIR" || -z "$(ls -A "$MODLISTDIR")" ]]; then
    echo "Error: modules list directory not found or empty: $MODLISTDIR"
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

rm -rf "$CACHE/lib"
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
done < <(for f in "$MODLISTDIR"/*; do cat "$f"; echo; done)


echo "Copied $count module(s)."

VMLINUZ="/boot/vmlinuz-$KERNELVER"
DSTVMLINUZ="$CACHE/linbo64"
KPKG="linux-image-$KERNELVER"

echo "Copying kernel image"
echo "  Source:      $VMLINUZ"
echo "  Destination: $DSTVMLINUZ"

mkdir -p "$(dirname "$DSTVMLINUZ")"

sudo install -m 644 "$VMLINUZ" "$DSTVMLINUZ" \
    && sudo chown "$MYNAME:$MYGROUP" "$DSTVMLINUZ" \
    || { echo "Error copying kernel image"; (( errors++ )); }

sudo chown -R "$MYNAME:$MYGROUP" "$CACHE/lib" || { echo "Error setting ownership of modules"; (( errors++ )); }
depmod -a -w -b "$CACHE" "$KERNELVER" || { echo "Error running depmod"; (( errors++ )); }

echo "$KERNELVER" > "$CACHE/kversion"

# save kernel-configuration for later use
KCONFIG="/boot/config-$KERNELVER"
DSTKCONFIG="$CACHE/config-$KERNELVER"
rm -f "$CACHE/config-"*
cp -f "$KCONFIG" "$DSTKCONFIG" || { echo "Error copying kernel config"; (( errors++ )); }
ln -sf "$(basename "$DSTKCONFIG")" "$CACHE/kconfig"

# save modules.dep
MODDEP="/lib/modules/$KERNELVER/modules.dep"
DSTMODDEP="$CACHE/modules.dep-$KERNELVER"
rm -f "$CACHE/modules.dep-"*
cp -f "$MODDEP" "$DSTMODDEP" || { echo "Error copying modules.dep"; (( errors++ )); }
ln -sf "$(basename "$DSTMODDEP")" "$CACHE/modules.dep"

if [[ $errors -gt 0 ]]; then
    echo "Completed with $errors error(s)."
    exit 1
fi

echo "Done."
