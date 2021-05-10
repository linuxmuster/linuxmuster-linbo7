# busybox ash profile
#
# thomas@schmitt.tk
# 20210507

# prompt
export PS1='\h: \w # '

# path
export PATH='/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'

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
cat /etc/linbo-version | sed -e 's|LINBO |v|'
echo
