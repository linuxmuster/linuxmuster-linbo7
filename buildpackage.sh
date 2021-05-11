#!/bin/bash
#
# thomas@linuxmuster.net
# 20210511
#

MY_DIR="$(dirname $0)"
cd "$MY_DIR"

rm -f debian/files
rm -rf tmp/*

dpkg-buildpackage \
    -tc -sn -us -uc \
    -I".git" \
    -I".gitignore" \
    -I".directory" \
    -I"*.debhelper*" \
    -Icache \
    -Isrc \
    -Ibuild.log \
    -Itmp 2>&1 | tee build.log
