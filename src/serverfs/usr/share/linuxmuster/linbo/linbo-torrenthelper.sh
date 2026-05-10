#!/bin/bash
#
# thomas@linuxmuster.net
# GPL v3
# 20220317
#
# linbo ctorrent helper script, started in a screen session by init script
#

torrent="$1"
[ -s "$torrent" ] || exit 1

# get ctorrent options from file
[ -e /etc/default/linbo-torrent ] && source /etc/default/linbo-torrent

[ -n "$SEEDHOURS" ] &&  OPTIONS="$OPTIONS -e $SEEDHOURS"
[ -n "$MAXPEERS" ] &&  OPTIONS="$OPTIONS -M $MAXPEERS"
[ -n "$MINPEERS" ] &&  OPTIONS="$OPTIONS -m $MINPEERS"
[ -n "$SLICESIZE" ] &&  OPTIONS="$OPTIONS -z $SLICESIZE"
[ -n "$MAXDOWN" ] &&  OPTIONS="$OPTIONS -D $MAXDOWN"
[ -n "$MAXUP" ] &&  OPTIONS="$OPTIONS -U $MAXUP"
OPTIONS="$OPTIONS $torrent"

[ -n "$CTUSER" ] && SUDO="/usr/bin/sudo -u $CTUSER"

while true; do
 $SUDO /usr/bin/ctorrent $OPTIONS || exit 1
 # hash check only on initial start, add -f parameter
 echo "$OPTIONS" | grep -q ^"-f " || OPTIONS="-f $OPTIONS"
done
