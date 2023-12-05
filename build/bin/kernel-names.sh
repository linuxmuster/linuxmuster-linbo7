# provide kernelnames based on version
#
# thomas@linuxmuster.net
# 20231204
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
