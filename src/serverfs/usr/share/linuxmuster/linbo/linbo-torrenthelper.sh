#!/bin/bash
#
# thomas@linuxmuster.net
# GPL v3
# 20260518
#
# linbo aria2c torrent helper script, started in a tmux session
#

torrent="$1"
[ -s "$torrent" ] || exit 1

SUDO="/usr/bin/sudo -u nobody"

while true; do
 $SUDO /usr/bin/aria2c -V --seed-ratio=0.0 --enable-dht=false --disable-ipv6=true $torrent || exit 1
done
