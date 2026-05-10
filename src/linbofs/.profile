# busybox ash profile
#
# thomas@schmitt.tk
# 20260510

# environment
source /.env

# load keyboard layout
/usr/bin/busybox loadkmap < /etc/console.kmap

[ -n "$IP" ] && myip="| IP: $IP"
[ -n "$MACADDR" ] && mymac="| MAC: $MACADDR"

# logo
echo
echo ' Welcome to'
echo '  _      _____ _   _ ____   ____'
echo ' | |    |_   _| \ | |  _ \ / __ \'
echo ' | |      | | |  \| | |_) | |  | |'
echo ' | |      | | | . ` |  _ <| |  | |'
echo ' | |____ _| |_| |\  | |_) | |__| |'
echo ' |______|_____|_| \_|____/ \____/'
echo
echo " $LINBOFULLVER $myip $mymac $myname"
echo
echo -n " " ; uname -a | sed -e "s| $HOSTNAME||"
echo
