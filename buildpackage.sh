#!/bin/bash
#
# thomas@linuxmuster.net
# 20210414
#

for i in conf debian files graphics linbofs; do
 find ${i}/ -type f -name \*~ -exec rm '{}' \;
done

rm -f debian/files
rm -rf kernel64/modules

fakeroot dpkg-buildpackage \
    -tc -sn -us -uc \
    -I".git" \
    -I".gitignore" \
    -I".directory" \
    -I".debhelper" \
    -Icache \
    -Isrc64 \
    -Ikernel64 \
    -Ibuild.log \
    -Imkpkg \
    -Itmp
