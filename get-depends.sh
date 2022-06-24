#!/bin/sh
#
# thomas@linuxmuster.net
# 20210511
#

set -e

SUDO="$(which sudo)"
if [ -z "$SUDO" ]; then
  echo "Please install sudo!"
  exit 1
fi

PKGNAME="linuxmuster-linbo7"
CONTROL_URL="https://raw.githubusercontent.com/linuxmuster/$PKGNAME/main/debian/control"

echo "###############################################"
echo "# Installing $PKGNAME build depends #"
echo "###############################################"
echo

if [ ! -e debian/control ]; then
 echo "debian/control not found!"
 exit
fi

if ! grep -q "Source: $PKGNAME" debian/control; then
 echo "This is no $PKGNAME source tree!"
 exit
fi

# install prerequisites
$SUDO apt-get update && $SUDO apt-get -y dist-upgrade
$SUDO apt-get -y install bash bash-completion ccache curl dpkg-dev || exit 1

# install build depends
BUILDDEPENDS="$(curl -s $CONTROL_URL | sed -n '/Build-Depends:/,/Package:/p' | grep -v ^Package | sed -e 's|^Build-Depends: ||' | sed -e 's|,||g')"
$SUDO apt-get -y install $BUILDDEPENDS || exit 1
