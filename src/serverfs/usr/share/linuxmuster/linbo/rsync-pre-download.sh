#!/bin/bash
#
# Pre-Download script for rsync/LINBO
# thomas@linuxmuster.net
# 20260520
#

# read in linuxmuster specific environment
source /usr/share/linuxmuster/helperfunctions.sh || exit 1

# Debug
LOGFILE="$RSYNC_MODULE_PATH/log/rsync-pre-download.log"
exec >>$LOGFILE 2>&1
#echo "$0 $*, Variables:" ; set

echo "### rsync pre download begin: $(date) ###"

FILE="${RSYNC_MODULE_PATH}/${RSYNC_REQUEST##$RSYNC_MODULE_NAME/}"
PIDFILE="/tmp/rsync.$RSYNC_PID"
echo "$FILE" > "$PIDFILE"

BASENAME="$(basename "$FILE")"
EXT="${BASENAME##*.}"
BASE="$(echo "$BASENAME" | sed 's/\(.*\)\..*/\1/')"
case "$EXT" in desc|info|macct|torrent|hash) BASE="$(echo "$BASE" | sed 's/\(.*\)\..*/\1/')" ;; esac
IMGDIR="$LINBOIMGDIR/$BASE"

# fetch host & domainname
do_rsync_hostname

# recognize download request of local grub.cfg
stringinstring ".grub.cfg" "$FILE" && EXT="grub-local"

echo "HOSTNAME: $RSYNC_HOST_NAME"
echo "IP: $RSYNC_HOST_ADDR"
echo "RSYNC_REQUEST: $RSYNC_REQUEST"
echo "FILE: $FILE"
echo "PIDFILE: $PIDFILE"
echo "EXT: $EXT"

case $EXT in

  # handle machine account password
  macct)
    url="--url=/var/lib/samba/private/sam.ldb"
    # old version: image's macct file resides in LINBODIR
    imagemacct_old="$FILE"
    # new version: image's macct file resides in subdirs below LINBODIR/images
    imagemacct="$IMGDIR/$BASENAME"
    # new version first
    for i in "$imagemacct" "$imagemacct_old"; do
      # upload samba machine password hashes to host's ad machine account
      if [ -s "$imagemacct" ]; then
        echo "Machine account ldif file: $imagemacct"
        echo "Host: $compname"
        # get dn of host
        dn="$(ldbsearch "$url" "(&(sAMAccountName=$compname$))" | grep ^dn | awk '{ print $2 }')"
        if [ -n "$dn" ]; then
          echo "DN: $dn"
          ldif="/var/tmp/${compname}_macct.$$"
          ldbopts="--nosync --verbose --controls=relax:0 --controls=local_oid:1.3.6.1.4.1.7165.4.3.7:0 --controls=local_oid:1.3.6.1.4.1.7165.4.3.12:0"
          sed -e "s|@@dn@@|$dn|" "$imagemacct" > "$ldif"
          ldbmodify "$url" $ldbopts "$ldif"
          rm -f "$ldif"
        else
          echo "Cannot determine DN of $compname! Aborting!"
        fi
        break
      fi
    done
  ;;

  # fetch logfiles from client
  log|status|gz)
    targetfile="$LINBOLOGDIR/${RSYNC_HOST_NAME%%.*}_$(basename "$FILE")"
    sourcefile="$(echo "$FILE" | sed -e "s|$LINBODIR||" | sed -e "s|//|/|")"
    echo "Upload request for $FILE: $sourcefile -> $targetfile."
    linbo-scp -v "${RSYNC_HOST_ADDR}:$sourcefile" "$FILE" || RC="1"
    if [ -s "$FILE" ]; then
      if [ "$EXT" = "log" ]; then
        cat "$FILE" >> "$targetfile"
      else
        cp "$FILE" "$targetfile"
      fi
      rm -f "$FILE"
      #touch "$FILE"
    fi
  ;;

  # patch image registry files with sambadomain if necessary
  reg)
    search="Domain\"=\"$sambadomain\""
    if ! grep -q "$search" "$FILE"; then
      sed -i "s|Domain\"=.*|$search|g" "$FILE"
    fi
  ;;

  # prepare download of local grub.cfg
  grub-local)
    grubcfg_tpl="$LINBOTPLDIR/grub.cfg.local"
    group="$(basename "$FILE" | awk -F\. '{ print $2 }')"
    startconf="$LINBODIR/start.conf.$group"
    linbo_kopts="$(grep -iw ^kerneloptions "$startconf" | awk -F\= '{print $2}' | awk -F\# '{print $1}' | head -$nr | tail -1 | awk '{$1=$1};1')"
    append="$linbo_kopts localboot"
    sed -e "s|linux \$linbo_kernel .*|linux \$linbo_kernel $append|g" "$grubcfg_tpl" > "$FILE"
  ;;

esac

echo "RC: $RSYNC_EXIT_STATUS"
echo "### rsync pre download end: $(date) ###"

exit $RSYNC_EXIT_STATUS
