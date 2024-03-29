#!/bin/bash
#
# thomas@linuxmuster.net
# 20231201
#

set -o pipefail

MY_DIR="$(dirname $0)"
cd "$MY_DIR"

rm -f debian/files

dpkg-buildpackage \
    -tc -sn -us -uc \
    -I".git" \
    -I".github" \
    -I".gitignore" \
    -I".directory" \
    -I"*.debhelper*" \
    -Icache \
    -Isrc \
    -Ibuild.log \
    -Itmp 2>&1 | tee ../build.log

exit $?
