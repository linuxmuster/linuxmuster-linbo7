#!/bin/bash
#
# add an app from ubuntu for use in linbofs
#
# thomas@linuxmuster.net
# 20231207
#

# give full path to app
APP="$1"

[ -s "$APP" ] || exit 1

# read build environment
source build/conf.d/0_general || exit 1

# skip libraries which are already in linbofs
IGNORELIST="linux-vdso.so libc.so.6 ld-linux-x86-64.so"
is_ignored(){
    echo "$IGNORELIST" | grep -q "$1" && return 0
    grep -q "$1" "$BUILDINITD"/* && return 0
    return 1
}

# create initramfs config file for app
rm -f $BUILDINITD/*_$(basename $APP)
INITRAMFS_APP="$BUILDINITD/$(( $(ls -1 $BUILDINITD | tail -1 | awk -F_ '{print $1}') +1 ))_$(basename $APP)"
CHMOD="755 0 0"
echo "# $APP" > "$INITRAMFS_APP"
echo >> "$INITRAMFS_APP"
echo "file $APP $APP $CHMOD" >> "$INITRAMFS_APP"

# get dependend libraries and copy them
ldd "$APP" | while read line; do
    lib="$(echo $line | awk '{print $1}')"    
    is_ignored "$lib" && continue
    slink="$(echo $line | awk '{print $3}')"
    [ -e "$slink" ] || continue
    echo "file /lib/$lib $slink $CHMOD" >> "$INITRAMFS_APP"
done
