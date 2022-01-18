#
# helperfunctions for linbo scripts
#
# thomas@linuxmuster.net
# 20220114
#

# get linuxmuster environment variables
source /usr/share/linuxmuster/defaults.sh || exit 1

# basic ldbsearch string
LDBSEARCH="$(which ldbsearch) -b OU=SCHOOLS,$basedn -H /var/lib/samba/private/sam.ldb"

# converting string to lower chars
tolower(){
  echo $1 | tr A-Z a-z
}

# converting string to upper chars
toupper(){
  echo $1 | tr a-z A-Z
}

# test if string is in string
stringinstring(){
  case "$2" in *$1*) return 0;; esac
  return 1
}

# test if variable is an integer
isinteger(){
  [ $# -eq 1 ] || return 1
  case $1 in
  *[!0-9]*|"") return 1;;
            *) return 0;;
  esac
} # isinteger

# check valid ip
validip(){
  (expr match "$1"  '\(\([1-9]\|[1-9][0-9]\|1[0-9]\{2\}\|2[0-4][0-9]\|25[0-4]\)\.\([0-9]\|[1-9][0-9]\|1[0-9]\{2\}\|2[0-4][0-9]\|25[0-4]\)\.\([0-9]\|[1-9][0-9]\|1[0-9]\{2\}\|2[0-4][0-9]\|25[0-4]\)\.\([1-9]\|[1-9][0-9]\|1[0-9]\{2\}\|2[0-4][0-9]\|25[0-4]\)$\)') &> /dev/null || return 1
}

# test valid mac address syntax
validmac(){
  [ `expr length $1` -ne "17" ] && return 1
  (expr match "$1" '\([a-fA-F0-9-][a-fA-F0-9-]\+\(\:[a-fA-F0-9-][a-fA-F0-9-]\+\)\+$\)') &> /dev/null || return 1
}

# test for valid hostname
validhostname(){
  (expr match "$(tolower $1)" '\([a-z0-9\-]\+$\)') &> /dev/null || return 1
}

# check valid domain name
validdomain(){
  (expr match "$(tolower $1)" '\([A-Za-z0-9\-]\+\(\.[A-Za-z0-9\-]\+\)\+$\)') &> /dev/null || return 1
}

# get hostname from AD
# get_hostname <ip|mac|hostname>
get_hostname(){
  local attr="sophomorixDnsNodename"
  if validip "$1"; then
    $LDBSEARCH "(sophomorixComputerIP=$1)" $attr | grep ^$attr | awk '{print $2}'
  elif validmac "$1"; then
    $LDBSEARCH "(sophomorixComputerMAC=$(toupper $1))" $attr | grep ^$attr | awk '{print $2}'
  elif validhostname "$1"; then
    $LDBSEARCH "($attr=$(tolower $1))" $attr | grep ^$attr | awk '{print $2}'
  else
    return 1
  fi
}

# get host's mac address from AD
# get_mac <ip|hostname|mac>
get_mac(){
  local attr="sophomorixComputerMAC"
  if validip "$1"; then
    $LDBSEARCH "(sophomorixComputerIP=$1)" $attr | grep ^$attr | awk '{print $2}'
  elif validhostname "$1"; then
    $LDBSEARCH "(sophomorixDnsNodename=$(tolower $1))" $attr | grep ^$attr | awk '{print $2}'
  elif validmac "$1"; then
    $LDBSEARCH "($attr=$(toupper $1))" $attr | grep ^$attr | awk '{print $2}'
  else
    return 1
  fi
}

# get host's ip address from AD
# get_ip <hostname|mac|ip>
get_ip(){
  local attr="sophomorixComputerIP"
  if validhostname "$1"; then
    $LDBSEARCH "(sophomorixDnsNodename=$(tolower $1))" $attr | grep ^$attr | awk '{print $2}'
  elif validmac "$1"; then
    $LDBSEARCH "(sophomorixComputerMAC=$(toupper $1))" $attr | grep ^$attr | awk '{print $2}'
  elif validip "$1"; then
    $LDBSEARCH "($attr=$1)" $attr | grep ^$attr | awk '{print $2}'
  else
    return 1
  fi
}

# get broadcast address for specified ip address
# get_bcaddress <ip>
get_bcaddress(){
python3 <<END
from functions import getIpBcAddress
try:
  ip="$1"
  print(getIpBcAddress(ip))
except:
  quit(1)
END
}

# return hostgroup of device from devices.csv
# get_hostgroup hostname
get_hostgroup(){
  $LDBSEARCH "(sophomorixDnsNodename="$(tolower $1)")" memberOf | grep ,OU=device-groups, | awk -F= '{print $2}' | awk -F, '{print $1}' | sed 's|^d_||'
}

# return mac address from dhcp leases
get_mac_dhcp(){
  validip "$1" || return
  LANG=C grep -A10 "$1" /var/lib/dhcp/dhcpd.leases | grep "hardware ethernet" | awk '{ print $3 }' | awk -F\; '{ print $1 }' | tr A-Z a-z
}

# return hostname by dhcp ip from devices.csv
get_hostname_dhcp_ip(){
  validip "$1" || return
  local macaddr="$(get_mac_dhcp "$1")"
  [ -z "$macaddr" ] && return
  get_hostname "$macaddr"
}

# do hostname handling for linbos rsync xfer scripts
do_rsync_hostname(){
  # handle unknown hostname in case of dynamic ip client
  if echo "$RSYNC_HOST_NAME" | grep -q UNKNOWN; then
    local compname_tmp="$(get_hostname_dhcp_ip "$RSYNC_HOST_ADDR")"
    [ -n "$compname_tmp" ] && RSYNC_HOST_NAME="$(echo "$RSYNC_HOST_NAME" | sed -e "s|UNKNOWN|$compname_tmp|")"
  fi
  compname="$(echo $RSYNC_HOST_NAME | awk -F\. '{ print $1 }' | tr A-Z a-z)"
  # get FQDN
  validdomain "$RSYNC_HOST_NAME" || RSYNC_HOST_NAME="${RSYNC_HOST_NAME}.$(hostname -d)"
  export compname
  export RSYNC_HOST_NAME
}
