#!/bin/bash
#
# Filename     : buildpackage.sh
# Description  : build the debian package
# Signed-off by: thomas@linuxmuster.net
# Assisted by  : Claude
# Date         : 20261003
#

set -o pipefail

MY_DIR="$(dirname $0)"
cd "$MY_DIR"

rm -f debian/files

dpkg-buildpackage \
    -tc -sn -us -uc \
    -I".claude" \
    -I".git" \
    -I".github" \
    -I".gitignore" \
    -I".directory" \
    -I"*.debhelper*" \
    -Icache \
    -Ikernel \
    -Isrc \
    -Ibuild.log \
    -Itmp 2>&1 | tee ../build.log

exit $?
