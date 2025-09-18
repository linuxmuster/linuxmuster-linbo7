#!/bin/sh
# linbo.sh - Start Linbo GUI (with optional debug shell before)
# This is a busybox 1.1.3 script
# (C) Klaus Knopper 2007
# License: GPL V2
# thomas@linuxmuster.net
# 20250916
#

# Reset fb color mode
RESET="]R"
# Clear and reset Screen
CLEAR="c"

# get environment
source /usr/share/linbo/shell_functions

# plymouth
if [ -x "/sbin/plymouthd" -a -n "$SPLASH" ]; then
  if ! plymouth --ping &> /dev/null; then
    plymouthd --mode=boot --tty="/dev/tty2" --attach-to-session
    plymouth show-splash message --text="$LINBOFULLVER"
  fi
fi

# update & extract linbo_gui
linbo_update_gui &> /dev/null

# quit plymouth
plymouth quit

# DEBUG mode
if [ -n "$DEBUG" ]; then
  for item in /tmp/linbo_gui.*.log; do
    if [ -s "$item" ]; then
      echo "There is a logfile from a previous start of linbo_gui in $item:"
      cat "$item"
      echo -n "Press enter key to continue."
      read dummy
      rm -f "$item"
    fi
  done
  echo "Starting DEBUG shell, leave with 'exit'."
  sendlog
  ash >/dev/tty1 2>&1 < /dev/tty1

# Start LINBO GUI
elif [ -s /usr/bin/linbo_gui ]; then

  echo "### $timestamp linbo_gui ###"
  sendlog
  export XKB_DEFAULT_LAYOUT=de
  /usr/bin/linbo_gui -platform linuxfb

else # handle missing gui problem

  # autostart if requested in start.conf
  linbo_autostart
  clear
  export myname="| Name: $HOSTNAME"
  source /.profile
  # print console menu
  if [ -n "$NOMENU" ]; then
    echo "----------------------------------------------"
    echo " This LINBO client is in remote control mode."
    echo "----------------------------------------------"
    echo
    while true; do
      answer=$(stty -icanon -echo; dd ibs=1 count=1 2>/dev/null)
      echo -n "X"
    done
  else
    echo "----------------------------------------------"
    echo " Console boot menu of group $HOSTGROUP"
    echo "----------------------------------------------"
    count=0
    rm -f /tmp/menu
    # iterate start.conf os items
    for item in /conf/os.*; do
      [ -s "$item" ] || continue
      name=""
      source "$item"
      [ -z "$name" ] && continue
      osnr="${item#*.}"
      # create menu entry for start
      if [ "$startenabled" = "yes" -o -z "$startenabled" ]; then
        count=$(( count + 1 ))
        echo "$count start $osnr" >> /tmp/menu
        echo " $count Start $name"
      fi
      # create menu entry for sync & start
      if [ "$syncenabled" = "yes" -o -z "$syncenabled" ]; then
        count=$(( count + 1 ))
        echo "$count syncstart $osnr" >> /tmp/menu
        echo " $count Sync & start $name"
      fi
      # create menu entry for new & start
      if [ "$newenabled" = "yes" -o -z "$newenabled" ]; then
        count=$(( count + 1 ))
        echo "$count forcesyncstart $osnr" >> /tmp/menu
        echo " $count New & start $name"
      fi
    done
    echo "----------------------------------------------"
    echo " [C] Console"
    echo " [R] Reboot"
    echo " [S] Shutdown"
    echo "----------------------------------------------"
    sendlog &> /dev/null
    while true; do
      answer=$(stty -icanon -echo; dd ibs=1 count=1 2>/dev/null)
      case "$answer" in
        c|C) linbo_login ;;
        r|R) /sbin/reboot ;;
        s|S) /sbin/poweroff ;;
        *)
          isinteger $answer || continue
          menucmd="$(grep -w ^$answer /tmp/menu | sed "s|^$answer ||")"
          cmd="$(echo "$menucmd" | awk '{print $1}')"
          linbocmd="linbo_${cmd}"
          [ -z "$(which "$linbocmd")" ] && continue
          osnr="$(echo "$menucmd" | awk '{print $2}')"
          [ -s "/conf/os.$osnr" ] || continue
          $linbocmd $osnr || continue
          ;;
      esac
    done
  fi

fi
