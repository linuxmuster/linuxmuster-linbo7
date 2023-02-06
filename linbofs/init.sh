#!/bin/sh
# init.sh - System setup and hardware detection
# This is a busybox 1.1.3 init script
# (C) Klaus Knopper 2007
# License: GPL V2
#
# thomas@linuxmuster.net
# 20230206
#

# If you don't have a "standalone shell" busybox, enable this:
# /bin/busybox --install

# Ignore signals
trap "" 1 2 11 15

# set terminal
export TERM=xterm

# Reset fb color mode
RESET="]R"
# ANSI COLORS
# Erase to end of line
CRE="
[K"
# Clear and reset Screen
CLEAR="c"
# Normal color
NORMAL="[0;39m"
# RED: Failure or error message
RED="[1;31m"
# GREEN: Success message
GREEN="[1;32m"
# YELLOW: Descriptions
YELLOW="[1;33m"
# BLUE: System mesages
BLUE="[1;34m"
# MAGENTA: Found devices or drivers
MAGENTA="[1;35m"
# CYAN: Questions
CYAN="[1;36m"
# BOLD WHITE: Hint
WHITE="[1;37m"


# Utilities

# test if variable is an integer
isinteger () {
  [ $# -eq 1 ] || return 1
  case $1 in
    *[!0-9]*|"") return 1 ;;
    *) return 0 ;;
  esac
}

# print status message
print_status(){
  if [ -n "$SPLASH" ]; then
    plymouth --update="$1"
  else
    echo "$1"
  fi
}

# create device nodes
udev_extra_nodes() {
  grep '^[^#]' /etc/udev/links.conf | \
  while read type name arg1; do
    [ "$type" -a "$name" -a ! -e "/dev/$name" -a ! -L "/dev/$name" ] ||continue
    case "$type" in
      L) ln -s $arg1 /dev/$name ;;
      D) mkdir -p /dev/$name ;;
      M) mknod -m 600 /dev/$name $arg1 ;;
      *) echo "links.conf: unparseable line ($type $name $arg1)" ;;
    esac
  done
}

# provide environment variables from kernel cmdline and dhcp.log
do_env(){
  local item
  local varname
  local upvarname
  # parse kernel cmdline
  for item in `cat /proc/cmdline` `grep ^[a-zB] /tmp/dhcp.log | sort -u`; do
    echo "$item" | grep -q "=" || item="${item}='yes'"
    varname="$(echo "$item" | awk -F\= '{print $1}')"
    upvarname="$(echo "$varname" | tr a-z A-Z)"
    case "$upvarname" in
      # set LINBOSERVER if server parameter is given
      SERVER) upvarname="LINBOSERVER" ;;
      # set HOSTGROUP from dhcp option nisdomain
      NISDOMAIN) upvarname="HOSTGROUP" ;;
      # set localmode if nonetwork parameter is given
      NONETWORK) upvarname="LOCALMODE" ;;
    esac
    echo "export ${item/${varname}/${upvarname}}" >> /.env
  done
  source /.env
  # add fqdn to environment
  echo "export FQDN='"${HOSTNAME}.${DOMAIN}"'" >> /.env
  export FQDN="${HOSTNAME}.${DOMAIN}"
  # add linboserver to environment if not set on kernel cl
  if [ -z "$LINBOSERVER" ]; then
    echo "export LINBOSERVER='"${SERVERID}"'" >> /.env
    export LINBOSERVER="${SERVERID}"
  fi
  # set hostname
  echo "$HOSTNAME" > /etc/hostname
  hostname "$HOSTNAME"
  # save mac address in enviroment
  export MACADDR="`ifconfig | grep -B1 "$IP" | grep HWaddr | awk '{ print $5 }' | tr A-Z a-z`"
  echo "export MACADDR='"$MACADDR"'" >> /.env
}

# initial setup
init_setup(){
  mount -t proc /proc /proc
  echo 0 >/proc/sys/kernel/printk
  mount -t sysfs /sys /sys
  mount -t devtmpfs devtmpfs /dev
  if [ -e /etc/udev/links.conf ]; then
    udev_extra_nodes
  fi

  loadkmap < /etc/german.kbd
  ifconfig lo 127.0.0.1 up
  hostname linbo
  klogd >/dev/null 2>&1
  syslogd -C 64k >/dev/null 2>&1

  # Enable CPU frequency scaling
  for i in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
    [ -f "$i" ] && echo "ondemand" > "$i" 2>/dev/null
  done

  # load modules given with loadmodules=module1,module2
  loadmodules="$(grep -v ^# /etc/modules),$loadmodules"
  if [ -n "$loadmodules" ]; then
    loadmodules="$(echo "$loadmodules" | sed -e 's|,| |g')"
    for i in $loadmodules; do
      echo "Loading module $i ..."
      modprobe "$i"
    done
  fi
}

# copyfromcache files - copies files from cache to current dir
copyfromcache(){
  linbo_mountcache || return 1
  local item
  local RC="0"
  for item in $@; do
    if cp -af "/cache/$item" .; then
      echo "Copied $item successfully to $(pwd)."
      # read env again to get cache from copied start.conf
      [ "$item" = "start.conf" ] && source /.env
    else
      echo "Failed to copy $item to $(pwd)."
      RC="1"
    fi
  done
  umount /cache
  return "$RC"
}

# copytocache - copies start.conf and hostname to local cache
copytocache(){
  linbo_mountcache || return 1
  local RC="0"
  if [ -s /start.conf ]; then
    if cp -a /start.conf /cache; then
      echo "Copied start.conf successfully to cache."
    else
      echo "Failed to copy start.conf to cache."
      RC="1"
    fi
  fi
  # save hostname for offline use
  if [ -n "$FQDN" ]; then
    if echo "$FQDN" > /cache/hostname; then
      echo "Successfully saved hostname $FQDN to cache."
    else
      echo "Failed to save hostname $FQDN to cache."
      RC="1"
    fi
  fi
  umount /cache
  return "$RC"
}

# Utilities

# save windows activation tokens
save_winact(){
  # rename obsolete activation status file
  [ -e /mnt/linuxmuster-win/activation_status ] && mv /mnt/linuxmuster-win/activation_status /mnt/linuxmuster-win/win_activation_status
  # get windows activation status
  if [ -e /mnt/linuxmuster-win/win_activation_status ]; then
    grep -i ^li[cz]en /mnt/linuxmuster-win/win_activation_status | grep -i status | grep -i li[cz]en[sz][ei][de] | grep -vqi not && local win_activated="yes"
  fi
  if [ -n "$win_activated" ]; then
    echo "Windows is activated."
  else
    echo "Windows is not activated."
  fi
  # get msoffice activation status
  if [ -e /mnt/linuxmuster-win/office_activation_status ]; then
    grep -i ^li[cz]en /mnt/linuxmuster-win/office_activation_status | grep -i status | grep -i li[cz]en[sz][ei][de] | grep -vqi not && office_activated="yes"
  fi
  if [ -n "$office_activated" ]; then
    echo "MSOffice is activated."
  else
    echo "MSOffice is not activated or not installed."
  fi
  # remove activation status files
  rm -f /mnt/linuxmuster-win/*activation_status
  # get activation token files
  if [ -n "$win_activated" ]; then
    local windir="$(ls -d /mnt/[Ww][Ii][Nn][Dd][Oo][Ww][Ss])"
    # find all windows tokens and key files in windir (version independent)
    local win_tokens="$(find "$windir" -iname tokens.dat)"
    [ "$win_tokens" = "" ] || win_tokens="$win_tokens $(find "$windir" -iname pkeyconfig.xrm-ms)"
    #local win_tokensdat="$(ls /mnt/[Ww][Ii][Nn][Dd][Oo][Ww][Ss]/[Ss][Ee][Rr][Vv][Ii][Cc][Ee][Pp][Rr][Oo][Ff][Ii][Ll][Ee][Ss]/[Nn][Ee][Tt][Ww][Oo][Rr][Kk][Ss][Ee][Rr][Vv][Ii][Cc][Ee]/[Aa][Pp][Pp][Dd][Aa][Tt][Aa]/[Rr][Oo][Aa][Mm][Ii][Nn][Gg]/[Mm][Ii][Cc][Rr][Oo][Ss][Oo][Ff][Tt]/[Ss][Oo][Ff][Tt][Ww][Aa][Rr][Ee][Pp][Rr][Oo][Tt][Ee][Cc][Tt][Ii][Oo][Nn][Pp][Ll][Aa][Tt][Ff][Oo][Rr][Mm]/[Tt][Oo][Kk][Ee][Nn][Ss].[Dd][Aa][Tt] 2> /dev/null)"
    #local win_pkeyconfig="$(ls /mnt/[Ww][Ii][Nn][Dd][Oo][Ww][Ss]/[Ss][Yy][Ss][Ww][Oo][Ww]64/[Ss][Pp][Pp]/[Tt][Oo][Kk][Ee][Nn][Ss]/[Pp][Kk][Ee][Yy][Cc][Oo][Nn][Ff][Ii][Gg]/[Pp][Kk][Ee][Yy][Cc][Oo][Nn][Ff][Ii][Gg].[Xx][Rr][Mm]-[Mm][Ss] 2> /dev/null)"
  fi
  [ -n "$office_activated" ] && local office_tokens="$(ls /mnt/[Pp][Rr][Oo][Gg][Rr][Aa][Mm][Dd][Aa][Tt][Aa]/[Mm][Ii][Cc][Rr][Oo][Ss][Oo][Ff][Tt]/[Oo][Ff][Ff][Ii][Cc][Ee][Ss][Oo][Ff][Tt][Ww][Aa][Rr][Ee][Pp][Rr][Oo][Tt][Ee][Cc][Tt][Ii][Oo][Nn][Pp][Ll][Aa][Tt][Ff][Oo][Rr][Mm]/[Tt][Oo][Kk][Ee][Nn][Ss].[Dd][Aa][Tt] 2> /dev/null)"
  # test if files exist
  if [ -n "$win_activated" -a -z "$win_tokens" ]; then
    echo "No windows activation tokens found."
    win_activated=""
  fi
  if [ -n "$office_activated" -a -z "$office_tokens" ]; then
    echo "No office activation tokens found."
    office_activated=""
  fi
  # if no activation return
  [ -z "$win_activated" -a -z "$office_activated" ] && return
  # get local mac address
  local mac="$(linbo_cmd mac | tr a-z A-Z)"
  # do not save if no mac address is available
  if [ -z "$mac" -o "$mac" = "OFFLINE" ]; then
    echo "Cannot determine mac address."
    return
  fi
  # get image name
  [ -s  /mnt/.linbo ] && local image="$(cat /mnt/.linbo)"
  # if an image is not yet created do nothing
  if [ -z "$image" ]; then
    echo "No image file found."
    return
  fi
  echo -e "Saving activation tokens ... "
  # archive name contains mac address and image name
  local archive="/cache/$mac.$image.winact.tar.gz"
  local tmparchive="/cache/tokens.tar.gz"
  # generate tar command
  local tarcmd="tar czf $tmparchive"
  [ -n "$win_tokens" ] && tarcmd="$tarcmd $win_tokens"
  [ -n "$office_tokens" ] && tarcmd="$tarcmd $office_tokens"
  # create temporary archive
  if ! $tarcmd &> /dev/null; then
    echo "Sorry. Error on creating $tmparchive."
    return 1
  else
    echo "OK."
  fi
  # merge old and new if archive already exists
  local RC=0
  if [ -s "$archive" ]; then
    echo -e "Updating $archive ... "
    local tmpdir="/cache/tmp"
    local curdir="$(pwd)"
    [ -e "$tmpdir" ] && rm -rf "$tmpdir"
    mkdir -p "$tmpdir"
    tar xf "$archive" -C "$tmpdir" || RC="1"
    tar xf "$tmparchive" -C "$tmpdir" || RC="1"
    rm -f "$archive"
    rm -f "$tmparchive"
    cd "$tmpdir"
    tar czf "$archive" * &> /dev/null || RC="1"
    cd "$curdir"
    rm -rf "$tmpdir"
  else # use temporary archive if it does not exist already
    echo -e "Creating $archive ... "
    rm -f "$archive"
    mv "$tmparchive" "$archive" || RC="1"
  fi
  # if error occured
  if [ "$RC" = "1" -o ! -s "$archive" ]; then
    echo "Failed. Sorry."
    return 1
  else
    echo "OK."
  fi
  # do not in offline mode
  [ -z "$LINBOSERVER" ] && return
  # trigger upload
  echo "Starting upload of windows activation tokens."
  rsync "$LINBOSERVER::linbo/winact/$(basename $archive).upload" /cache &> /dev/null || true
}

# save windows activation tokens
do_housekeeping(){
  local dev
  if ! linbo_mountcache; then
    echo "Housekeeping: Cannot mount cache partition."
    return 1
  fi
  [ -s /start.conf ] || return 1
  grep -iw ^root /start.conf | awk -F\= '{ print $2 }' | awk '{ print $1 }' | sort -u | while read device; do
    [ -b "$dev" ] || continue
    if linbo_mount "$dev" /mnt 2> /dev/null; then
      # save windows activation files
      ls /mnt/linuxmuster-win/*activation_status &> /dev/null && save_winact
      umount /mnt
    fi
  done
  grep -qw /cache /proc/mounts && umount /cache
}

# update linbo and install it locally
do_linbo_update(){
  local rebootflag="/tmp/.linbo.reboot"
  linbo_update 2>&1 | tee /cache/update.log
  # initiate warm start
  if [ -e "$rebootflag" ]; then
    echo "LINBO/GRUB configuration has been successfully updated."
    linbo_warmstart
  fi
}

# disable auto functions from cmdline
disable_auto(){
  sed -e 's|^[Aa][Uu][Tt][Oo][Pp][Aa][Rr][Tt][Ii][Tt][Ii][Oo][Nn].*|AutoPartition = no|g
         s|^[Aa][Uu][Tt][Oo][Ff][Oo][Rr][Mm][Aa][Tt].*|AutoFormat = no|g
  s|^[Aa][Uu][Tt][Oo][Ii][Nn][Ii][Tt][Cc][Aa][Cc][Hh][Ee].*|AutoInitCache = no|g' -i /start.conf
}

# handle autostart from cmdline
set_autostart() {
  # return if autostart shall be suppressed generally
  if [ "$autostart" = "0" ]; then
    echo "Deactivating autostart generally."
    # set all autostart parameters to no
    sed -e 's|^[Aa][Uu][Tt][Oo][Ss][Tt][Aa][Rr][Tt].*|Autostart = no|g' -i /start.conf
    return
  fi
  # count [OS] entries in start.conf if there are any
  [ -s /start.conf ] || return
  grep -qi ^"\[OS\]" /start.conf || return
  local counts="$(grep -ci ^"\[OS\]" /start.conf)"
  # autostart OS at start.conf position given by autostart parameter
  local c=0
  local found=0
  local line=""
  while read -r line; do
    if echo "$line" | grep -qi ^"\[OS\]"; then
      let c++
      [ "$autostart" = "$c" ] && found=1
    fi
    # suppress autostart for other OS entries
    echo "$line" | grep -qi ^autostart || echo "$line" >> /start.conf.new
    # write autostart line for specific OS
    if [ "$found" = "1" ]; then
      echo "Activating autostart for os no. $c."
      echo "Autostart = yes" >> /start.conf.new
      found=0
    fi
  done </start.conf
  mv /start.conf.new /start.conf
}

network(){
  echo
  rm -f /tmp/linbo-network.done
  # iterate over ethernet interfaces
  print_status "Requesting ip address per dhcp ..."
  # dhcp retries
  for i in $(cat /proc/cmdline); do case "$i" in dhcpretry=*) eval "$i" ;; esac; done
  [ -n "$dhcpretry" ] && dhcpretry="-t $dhcpretry"
  local RC="0"
  local dev
  local dhcpdev
  for dev in `grep ':' /proc/net/dev | awk -F\: '{ print $1 }' | awk '{ print $1}' | grep -v ^lo`; do
    print_status "Interface $dev ... "
    ifconfig "$dev" up &> /dev/null
    # activate wol
    ethtool -s "$dev" wol g &> /dev/null
    # check if using vlan
    if [ -n "$vlanid" ]; then
      print_status "Using vlan id $vlanid."
      vconfig add "$dev" "$vlanid" &> /dev/null
      dhcpdev="$dev.$vlanid"
      ip link set dev "$dhcpdev" up
    else
      dhcpdev="$dev"
    fi
    udhcpc -O nisdomain -n -i "$dhcpdev" $dhcpretry &> /dev/null ; RC="$?"
    if [ "$RC" = "0" ]; then
      # set mtu
      [ -n "$mtu" ] && ifconfig "$dev" mtu $mtu &> /dev/null
      break
    else
      dhcpdev=""
    fi
  done
  # create environment
  do_env
  # Move away standard start.conf and try to download the current one
  mv /start.conf /start.conf.dist
  if [ -n "$LINBOSERVER" -a -n "$HOSTGROUP" ]; then
    print_status "Downloading start.conf from $LINBOSERVER ..."
    rsync -vL "$LINBOSERVER::linbo/start.conf.$HOSTGROUP" "/start.conf" | tee /tmp/startconf.log
  fi
  # set flag for working network connection and do additional stuff which needs
  # connection to linbo server
  if [ -s /start.conf ]; then
    print_status "Network connection to $LINBOSERVER established successfully."
    print_status "IP: $IP * Hostname: $HOSTNAME * MAC: $MACADDR * Server: $LINBOSERVER"
    # first do linbo update (splits start.conf)
    do_linbo_update
    # time sync
    print_status "Starting time sync ..."
    # time sync with ntp server
    ntpd -q -p "$NTPSRV"
    # get onboot linbo-remote commands, if there are any
    local item
    for item in $HOSTNAME $IP; do
      rsync -L "$LINBOSERVER::linbo/linbocmd/$item.cmd" "/linbocmd" &> /dev/null
      [ -s /linbocmd ] && break
    done
    # save linbo-remote noauto and disablegui cmds to variables
    if [ -s /linbocmd ]; then
      for i in noauto disablegui; do
        if grep -q $i /linbocmd; then
          eval $i=yes
          sed -i "s|$i||" /linbocmd
        fi
      done
      # strip leading and trailing spaces and escapes and save remaining cmds to variable
      export linbocmd="$(awk '{$1=$1}1' /linbocmd | sed -e 's|\\||g')"
    fi
    # save start.conf and hostname to cache
    copytocache
  fi
  # if start.conf could not be downloaded or does not contain [os] section
  if [ ! -s /start.conf ] || ([ -s /start.conf ] && ! grep -qi ^'\[os\]' /start.conf); then
    # No new version / no network available, look for cached copies of start.conf.
    echo "Trying to copy start.conf from cache."
    copyfromcache start.conf
    # Still nothing new, revert to old version.
    [ -s /start.conf ] || mv -f /start.conf.dist /start.conf
    # set flag to split start.conf
    do_split="yes"
  fi
  # disable auto functions if noauto is given
  if [ -n "$noauto" ]; then
    echo "Disabling auto functions."
    autostart=0
    disable_auto
    # set flag to split start.conf
    do_split="yes"
  fi
  # start.conf: set autostart if given on cmdline
  isinteger "$autostart" && set_autostart
  # disable gui (splits start.conf)
  if [ -n "$disablegui" ]; then
    echo "Disabling linbo_gui."
    gui_ctl disable
  fi
  # split start.conf finally, if it has been changed in the meantime
  [ -n "$do_split" -a -z "$disablegui" ] && linbo_split_startconf
  # start ssh server only if network is avalilable
  if [ -n "$dhcpdev" ]; then
    print_status "Starting ssh service."
    /sbin/dropbear -s -g -E -p 2222 &> /dev/null
  fi
  # remove reboot flag, save windows activation
  do_housekeeping
  # done
  echo > /tmp/linbo-network.done
  print_status "Done."
}

# HW Detection
hwsetup(){
  rm -f /tmp/linbo-cache.done
  echo "## Hardware setup - begin ##" >> /tmp/linbo.log

  #
  # Udev starten
  echo > /sys/kernel/uevent_helper
  mkdir -p /run/udev
  udevd --daemon
  mkdir -p /dev/.udev/db/ /dev/.udev/queue/
  udevadm trigger --type=subsystems --action=add
  udevadm trigger --type=devices --action=add
  udevadm trigger
  mkdir -p /dev/pts
  mount /dev/pts
  udevadm settle || true

  # mount efivar fs
  [ -d /sys/firmware/efi ] && mount -t efivarfs efivarfs /sys/firmware/efi/efivars

  export TERM_TYPE=pts

  dmesg >> /tmp/linbo.log
  echo "## Hardware setup - end ##" >> /tmp/linbo.log

  sleep 2
  touch /tmp/linbo-cache.done
}


# Main

# print welcome message
clear
source /.profile

# initial setup
echo
echo "Initializing hardware ..."
echo
if [ -n "$quiet" ]; then
  init_setup &> /dev/null
  hwsetup &> /dev/null
else
  init_setup
  hwsetup
fi

# start plymouth boot splash daemon
if grep -qiw splash /proc/cmdline; then
  plymouthd --mode=boot --tty="/dev/tty2" --attach-to-session
  plymouth --show-splash
  SPLASH="yes"
fi

# do network setup
network

# execute linbo commands given on commandline
if [ -n "$linbocmd" ]; then
  OIFS="$IFS"
  IFS=","
  for cmd in $linbocmd; do
    # filter password
    if echo "$cmd" | grep -q ^linbo:; then
      msg="linbo_wrapper linbo:*****"
    else
      msg="linbo_wrapper $cmd"
    fi
    print_status "$msg"
    /usr/bin/linbo_wrapper "$cmd" | while read line; do
      line="${line/---/}"
      print_status "$line"
    done
  done
  IFS="$OIFS"
fi

exit 0
