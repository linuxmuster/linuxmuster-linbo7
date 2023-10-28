#!/bin/bash
#
# linbo ssh wrapper
#
# thomas@linuxmuster.net
# 20231014
# GPL V3
#

# read linuxmuster environment
source /usr/share/linuxmuster/defaults.sh || exit 1

SSH_CONFIG="$LINBOSYSDIR/ssh_config"

ssh -F $SSH_CONFIG $@ ; RC="$?"

exit "$RC"

