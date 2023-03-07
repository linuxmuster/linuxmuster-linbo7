#!/bin/sh
#
# get deb from iggy
# thomas@linuxmuster.net
# 20230307
#

version="$(head -1 debian/changelog | awk -F\( '{print $2}' | awk -F\) '{print $1}')"
lname="linuxmuster-linbo7"
lpkg="${lname}_${version}_all.deb"

mkdir package
rsync iggy.linuxmuster.net::linbo/linuxmuster-linbo7_${version}\* package/

[ -s "package/$lpkg" ] || exit 1