# busybox ash profile
#
# thomas@schmitt.tk
# 20220615

# prompt
export PS1='\h: \w # '

# path
export PATH='/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'

# aliases
#alias mount="mount -i"

# environment
source /.env

[ -n "$IP" ] && myip="| IP: $IP"
[ -n "$MACADDR" ] && mymac="| MAC: $MACADDR"

# logo
echo
echo 'Welcome to'
echo ' _      _____ _   _ ____   ____'
echo '| |    |_   _| \ | |  _ \ / __ \'
echo '| |      | | |  \| | |_) | |  | |'
echo '| |      | | | . ` |  _ <| |  | |'
echo '| |____ _| |_| |\  | |_) | |__| |'
echo '|______|_____|_| \_|____/ \____/'
echo
echo "$LINBOFULLVER $myip $mymac $myname"
echo
uname -a | sed -e "s| $HOSTNAME||"
echo
