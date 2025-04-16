#!/bin/sh
#
# get deb from martini.schmitt.red, needs ubuntu 22.04
# thomas@linuxmuster.net
# 20250416
#

# get dependencies
sudo apt-get update
sudo apt-get -y install debdelta gpg rsync || exit 1

version="$(head -1 debian/changelog | awk -F\( '{print $2}' | awk -F\) '{print $1}')"
lname="linuxmuster-linbo7"
lpkg="${lname}_${version}_all.deb"
fporig="CCA1DC5BE0F38B0FFCE5FCC68D158AA6CF53F928"

# download debian package files
mkdir package
rsync -L repo.schmitt.red::repo/linuxmuster-linbo7_${version}\* package/
[ -s "package/$lpkg" ] || exit 1
