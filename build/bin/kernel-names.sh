#
# Filename     : kernel-names.sh
# Description  : provide kernel name, paths and prebuilt state based on version
# Signed-off by: thomas@linuxmuster.net
# Assisted by  : Claude
# Date         : 20261003
#

# get kernel name
case "$kvers" in
    "$STABLE".*) kname="stable"; kmajor="$STABLE" ;;
    "$LONGTERM".*) kname="longterm"; kmajor="$LONGTERM" ;;
    "$LEGACY".*) kname="legacy"; kmajor="$LEGACY" ;;
    *) exit 1 ;;
esac

# kernel paths
kcfg="$BUILDCONFIG/kernel-$kname"
kdir="linux-$kvers"
kroot="$SRC/$kname"
ksrc="$kroot/$kdir"
kmodarc="$kroot/modules.tar.xz"
klib="$kroot/lib"
kmoddir="$klib/modules/$kvers"
kextmod="$kroot/extmod"
karc="$CACHE/$kdir.tar.xz"
kimg="$ksrc/arch/x86/boot/bzImage"
klinbo="$kroot/linbo64"
kinst="$PKGVARDIR/$kname"

# prebuilt kernel & modules store
kstore="$KERNELDIR/$kname/$kvers"
kstoreconfig="$kstore/config"
kstorecpio="$kstore/gen_init_cpio.c"

# A stored kernel is only used if it is complete and was built with the
# current kernel config, otherwise it is rebuilt.
kprebuilt=""
if [ -s "$kstore/linbo64" -a -s "$kstore/modules.tar.xz" -a -s "$kstorecpio" ] \
    && cmp -s "$kcfg" "$kstoreconfig"; then
    kprebuilt="yes"
fi
