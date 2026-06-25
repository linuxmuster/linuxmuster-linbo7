#!/bin/bash
#
# thomas@linuxmuster.net
# GPL v3
# 20260625
#
# linbo aria2c torrent helper script, started in a tmux session
#

torrent="$1"
[ -s "$torrent" ] || exit 1

source /etc/default/linbo-torrent || exit 1

SUDO="/usr/bin/sudo -u nobody"

while true; do
 $SUDO /usr/bin/aria2c $ARIA2C_GLOBAL_OPTS $ARIA2C_SEED_OPTS $torrent || exit 1
done
