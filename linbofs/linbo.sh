#!/bin/sh
# linbo.sh - Start Linbo GUI (with optional debug shell before)
# This is a busybox 1.1.3 script
# (C) Klaus Knopper 2007
# License: GPL V2
# thomas@linuxmuster.net
# 20220508
#

# Reset fb color mode
RESET="]R"
# Clear and reset Screen
CLEAR="c"

source /.env

# plymouth
if [ -x "/sbin/plymouthd" -a -n "$SPLASH" ]; then
  if ! plymouth --ping &> /dev/null; then
    plymouthd --mode=boot --tty="/dev/tty2" --attach-to-session
    plymouth show-splash message --text="$LINBOFULLVER"
  fi
fi

# update & extract linbo_gui, disabled since there is no compatible version for 22.04
linbo_update_gui

# DEBUG mode
if [ -n "$DEBUG" ]; then
  plymouth quit
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
  ash >/dev/tty1 2>&1 < /dev/tty1
fi

# Start LINBO GUI
if [ -s /usr/bin/linbo_gui ]; then

  plymouth quit &> /dev/null
  export XKB_DEFAULT_LAYOUT=de
  /usr/bin/linbo_gui -platform linuxfb

else # handle missing gui problem

  plymouth quit
  if [ -n "$DEBUG" ]; then
    echo "Starting DEBUG shell."
    ash >/dev/tty1 2>&1 < /dev/tty1
  else
    export myname="| Name: $HOSTNAME"
    source /.profile
    echo
    echo -e "\nPress [1] to reboot or [2] to shutdown."
    echo
    answer="0"
    while [ "$answer" != "1" -a "$answer" != "2" ]; do
      read answer
      case "$answer" in
        1) /sbin/reboot ;;
        2) /sbin/poweroff ;;
        *) ;;
      esac
    done
  fi
fi
