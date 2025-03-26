#!/bin/bash
#
# harvest an app from server os for use in linbofs
#
# thomas@linuxmuster.net
# 20250326
#

# get linbo env
source /usr/share/linuxmuster/helperfunctions.sh

# give full path to app
APP="$1"

[ -s "$APP" ] || exit 1

# linbofs paths
LINBOFSROOT="$LINBOCACHEDIR/linbofs64"
LINBOFSLIBDIR="$LINBOFSROOT/lib"
LINBOAPPDIR="$LINBOCACHEDIR/apps"

# app paths
APPNAME="$(basename $APP)"
APPDIR="$LINBOAPPDIR/$APPNAME"
APPARCHIVE="$LINBOAPPDIR/${APPNAME}.tar.xz"
IGNORELIST="linux-vdso.so libc.so.6 ld-linux-x86-64.so"

# skip libraries which are already in linbofs
is_ignored(){
    local item
    local res
    for item in $IGNORELIST; do
        stringinstring "$item" "$1" && return 0
    done
    res="$(find $LINBOFSLIB -name $1)"
    [ -n "$res" ] && return 0
    return 1
}

# provide necessary directories
rm -rf "$APPDIR"
mkdir -p "$APPDIR/$(dirname $APP)"
mkdir -p "$APPDIR/lib"

# copy app binary
cp -L $APP "$APPDIR/$APP"

# get dependend libraries and copy them
ldd "$APP" | while read line; do
    lib="$(echo $line | awk '{print $1}')"
    is_ignored "$lib" && continue
    slink="$(echo $line | awk '{print $3}')"
    [ -e "$slink" ] || continue
    cp -L "$slink" "$APPDIR/lib"
done

# pack files into xz archive and delete temp dir
cd "$APPDIR"
if [ -z "$(ls -A ./lib)" ]; then
    rm -rf lib
else
    chmod 755 lib/*
fi
tar --xz -cf "$APPARCHIVE" *
cd
rm -rf "$APPDIR"