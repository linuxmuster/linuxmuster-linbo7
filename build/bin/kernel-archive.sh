#
# Filename     : kernel-archive.sh
# Description  : function to move replaced prebuilt kernels to the kernel archive
# Signed-off by: thomas@linuxmuster.net
# Assisted by  : Claude
# Date         : 20261003
#
# Needs KERNELDIR, KERNELARCHIVE and KERNELARCHIVE_KEEP from build/conf.d/0_general.
#

# archiveKernels <kname> [keepversion]
# Moves all versions of kernel branch <kname> in KERNELDIR except <keepversion>
# to KERNELARCHIVE and keeps only the last KERNELARCHIVE_KEEP versions there.
# Leftovers of interrupted builds (*.tmp) are deleted, not archived.
archiveKernels() {
    local kname="$1"
    local keep="$2"
    local item
    mkdir -p "$KERNELARCHIVE/$kname" || return 1
    for item in "$KERNELDIR/$kname"/*; do
        [ -e "$item" ] || continue
        [ "$(basename "$item")" = "$keep" ] && continue
        case "$item" in
            *.tmp) rm -rf "$item"; continue ;;
        esac
        echo "Archiving old prebuilt kernel $item ..."
        rm -rf "$KERNELARCHIVE/$kname/$(basename "$item")"
        mv "$item" "$KERNELARCHIVE/$kname/" || return 1
    done
    ls -1 "$KERNELARCHIVE/$kname" | sort -V | head -n -"$KERNELARCHIVE_KEEP" | while read -r item; do
        echo "Removing archived kernel $KERNELARCHIVE/$kname/$item ..."
        rm -rf "$KERNELARCHIVE/$kname/$item"
    done
}
