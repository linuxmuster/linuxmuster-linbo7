#!/bin/sh
#
# get deb from iggy, needs ubuntu 22.04
# thomas@linuxmuster.net
# 20230316
#

# get dependencies
sudo apt-get update
sudo apt-get -y install dpkg-sig gpg rsync || exit 1

version="$(head -1 debian/changelog | awk -F\( '{print $2}' | awk -F\) '{print $1}')"
lname="linuxmuster-linbo7"
lpkg="${lname}_${version}_all.deb"
fporig="CF1D06F83EE8518CBA80E88F26CB514FFD0B44B2"

# download debian package files
mkdir package
rsync iggy.linuxmuster.net::linbo/linuxmuster-linbo7_${version}\* package/
[ -s "package/$lpkg" ] || exit 1
