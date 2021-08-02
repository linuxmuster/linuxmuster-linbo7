# busybox ash profile
#
# thomas@schmitt.tk
# 20210802

# prompt
export PS1='\h: \w # '

# path
export PATH='/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'

# aliases
alias mount="mount -i"

ip="$(LANG=C ip route show | grep src | awk '{print $7}')"
[ -n "$ip" ] && ip="| IP: $ip"

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
echo "$(cat /etc/linbo-version | sed -e 's|LINBO |v|') $ip"
echo
uname -a | sed -e "s| $(hostname)||"
echo
