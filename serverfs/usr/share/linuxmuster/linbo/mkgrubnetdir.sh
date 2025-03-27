#!/bin/sh
#
# creates directory structure for grub network boot
# thomas@linuxmuster.net
# 20250317
# GPL V3
#

# read linuxmuster environment
. /usr/share/linuxmuster/environment.sh || exit 1

# architectures
I386="i386-pc"
EFI64="x86_64-efi"

# dirs
SUBDIR="/boot/grub"
I386_DIR="/usr/lib/grub/$I386"
EFI64_DIR="/usr/lib/grub/$EFI64"

# grub modules
GRUBCOMMONMODS="all_video boot chain configfile cpuid echo net ext2 extcmd fat gettext gfxmenu \
  gfxterm gzio http ntfs linux linux16 loadenv minicmd net part_gpt part_msdos png progress read \
  reiserfs search sleep terminal test tftp"
# arch specific netboot modules
GRUBEFIMODS="$GRUBCOMMONMODS $(ls "$EFI64_DIR"/*efi*.mod | sed "s|$EFI64_DIR/||g" | sed 's|\.mod||g')"
GRUBI386MODS="$GRUBCOMMONMODS biosdisk gfxterm_background normal ntldr pxe"
GRUBISOMODS='iso9660 usb'
GRUBFONT='unicode'

# image files
CORE_I386="$LINBOGRUBDIR/$I386/core"
CORE_EFI64="$LINBOGRUBDIR/$EFI64/core"

# grub.cfg templates
GRUBCFG_TEMPLATE="$LINBOTPLDIR/grub.cfg.pxe"

# fonts
FONTS="unicode"

# make cd/usb boot images (efi only)
grub-mknetdir --modules="$GRUBEFIMODS $GRUBISOMODS" -d "$EFI64_DIR" --net-directory="$LINBODIR" --subdir="$SUBDIR"
mv "$CORE_EFI64.efi" "$CORE_EFI64.iso"

# make special purpose minimal netboot image for i386
grub-mknetdir --fonts="$GRUBFONT" -d "$I386_DIR" --net-directory="$LINBODIR" --subdir="$SUBDIR"
mv "$CORE_I386.0" "$CORE_I386.min"

# make standard netboot images
grub-mknetdir --fonts="$GRUBFONT" --modules="$GRUBI386MODS" -d "$I386_DIR" --net-directory="$LINBODIR" --subdir="$SUBDIR"
grub-mknetdir --fonts="$GRUBFONT" --modules="$GRUBEFIMODS" -d "$EFI64_DIR" --net-directory="$LINBODIR" --subdir="$SUBDIR"

# copy remaining files
rsync -a "$I386_DIR/" "$LINBOGRUBDIR/$I386/"
rsync -a "$EFI64_DIR/" "$LINBOGRUBDIR/$EFI64/"

# copy ipxe files
cp /boot/ipxe.lkrn "$LINBOGRUBDIR"
cp /boot/ipxe.efi "$LINBOGRUBDIR"
