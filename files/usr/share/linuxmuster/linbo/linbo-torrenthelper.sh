#!/bin/sh
#
# thomas@linuxmuster.net
# GPL v3
# 20210423
#
# linbo bittorrent helper script, started in a screen session by init script
#

torrent="$1"
options="-e 100000 $torrent"

while true; do
 /usr/bin/ctorrent $options || exit 1
 # hash check only on initial start, add -f parameter
 echo "$options" | grep -q ^"-f " || options="-f $options"
done
