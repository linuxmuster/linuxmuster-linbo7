#!/bin/bash
#
# Post-Download script for rsync/LINBO
# thomas@linuxmuster.net
# 20231122
#

# read in paedml specific environment
source /usr/share/linuxmuster/linbo/helperfunctions.sh || exit 1

# Debug
LOGFILE="$LINBOLOGDIR/rsync-post-download.log"
exec >>$LOGFILE 2>&1
#echo "$0 $*, Variables:" ; set

echo "### rsync post download begin: $(date) ###"

# Needs Version 2.9 of rsync
[ -n "$RSYNC_PID" ] || exit 0

PIDFILE="/tmp/rsync.$RSYNC_PID"

# Check for pidfile, exit if nothing to do
[ -s "$PIDFILE" ] || exit 0

# read file created by pre-upload script
FILE="$(<$PIDFILE)"
BASENAME="$(basename "$FILE")"
EXT="${BASENAME##*.}"

# fetch host & domainname
do_rsync_hostname

echo "HOSTNAME: $RSYNC_HOST_NAME"
echo "IP: $RSYNC_HOST_ADDR"
echo "RSYNC_REQUEST: $RSYNC_REQUEST"
echo "FILE: $FILE"
echo "PIDFILE: $PIDFILE"
echo "EXT: $EXT"

# handle request for obsolete menu.lst
if stringinstring "menu.lst." "$FILE"; then
  CACHE="$(grep -i ^cache "$LINBODIR/start.conf.$EXT" | awk -F\= '{ print $2 }' | awk '{ print $1 }' | tail -1)"
  [ -n "$CACHE" ] && EXT="upgrade"
fi

# recognize download request of local grub.cfg
stringinstring ".grub.cfg" "$FILE" && EXT="grub-local"

case "$EXT" in

  # remove linbocmd file after download
  cmd)
    echo "Removing onboot linbocmd file $FILE."
    rm -f "$FILE"
  ;;

  # remove dummy logfile after download
  log)
    echo "Removing dummy logfile $FILE."
    rm -f "$FILE"
  ;;

  # machine password file
  mpw)
    if [ -e "$FILE" ]; then
      echo "Removing machine password file $FILE."
      rm -f "$FILE"
    fi
  ;;

  winkey)
    if [ -e "$FILE" ]; then
      echo "Removing windows product key file $FILE."
      rm -f "$FILE"
    fi
  ;;

  # handle server based grub reboot in case of remote cache
  reboot)
    # get reboot parameters from filename
    rebootstr="$(echo "$FILE" | sed -e "s|^$LINBODIR/||")"
    bootpart="$(echo "$rebootstr" | awk -F\# '{ print $1 }' )"
    kernel="$(echo "$rebootstr" | awk -F\# '{ print $2 }' )"
    initrd="$(echo "$rebootstr" | awk -F\# '{ print $3 }' )"
    append="$(echo "$rebootstr" | awk -F\# '{ print $4 }' )"
    # grubenv template
    grubenv_tpl="$LINBOTPLDIR/grubenv.reboot"
    # create fifo socket
    fifo="$LINBODIR/boot/grub/spool/${compname}.reboot"
    rm -f "$fifo"
    mkfifo "$fifo"
    # create screen session
    screen -dmS "${compname}.reboot" "$LINBOSHAREDIR/reboot_pipe.sh" "$bootpart" "$kernel" "$initrd" "$append" "$grubenv_tpl" "$fifo"
  ;;

  grub-local)
    if [ -e "$FILE" ]; then
      echo "Removing $FILE."
      rm -f "$FILE"
    fi
  ;;

  # handle lmn7* start.conf request
  start-conf)
    echo "Removing temporary $FILE."
    rm -f "$FILE"
  ;;

  *) ;;

esac

rm -f "$PIDFILE"
