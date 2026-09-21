#!/bin/bash
#
# Filename     : rsync-pre-download.sh
# Description  : rsync pre-xfer hook for LINBO downloads; handles log/status
#                uploads, merges per-image status lines, and keeps
#                per-transfer staging files isolated.
# Signed-off by: thomas@linuxmuster.net
# Assisted by  : Claude
# Date         : 20260921
#

# read in linuxmuster specific environment
source /usr/share/linuxmuster/helperfunctions.sh || exit 1

# Debug
LOGFILE="$RSYNC_MODULE_PATH/log/rsync-pre-download.log"
exec >>$LOGFILE 2>&1
#echo "$0 $*, Variables:" ; set

echo "### rsync pre download begin: $(date) ###"

FILE="${RSYNC_MODULE_PATH}/${RSYNC_REQUEST##$RSYNC_MODULE_NAME/}"
BASENAME="$(basename "$FILE")"
EXT="${BASENAME##*.}"
BASE="$(echo "$BASENAME" | sed 's/\(.*\)\..*/\1/')"
case "$EXT" in desc|info|macct|torrent|hash) BASE="$(echo "$BASE" | sed 's/\(.*\)\..*/\1/')" ;; esac
IMGDIR="$LINBOIMGDIR/$BASE"

# Host log/status uploads share the same rsync request path for every client.
# Keep the staging file unique per transfer so concurrent clients cannot
# overwrite each other's temporary files while preserving the original target
# filename in the log directory. The same PID is already used for
# /tmp/rsync.$RSYNC_PID, so reusing it here keeps the path stable and unique.
STAGINGFILE="$FILE"
case "$EXT" in
  log|status|gz)
    STAGINGFILE="${FILE}.${RSYNC_PID}"
    ;;
esac

PIDFILE="/tmp/rsync.$RSYNC_PID"
echo "$STAGINGFILE" > "$PIDFILE"

# fetch host & domainname
do_rsync_hostname

# recognize download request of local grub.cfg
stringinstring ".grub.cfg" "$FILE" && EXT="grub-local"

echo "HOSTNAME: $RSYNC_HOST_NAME"
echo "IP: $RSYNC_HOST_ADDR"
echo "RSYNC_REQUEST: $RSYNC_REQUEST"
echo "FILE: $FILE"
[ -n "$STAGINGFILE" ] && echo "STAGINGFILE: $STAGINGFILE"
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
    echo "Upload request for $STAGINGFILE: $sourcefile -> $targetfile."
    RC=0
    linbo-scp -v "${RSYNC_HOST_ADDR}:$sourcefile" "$STAGINGFILE" || {
      RC=$?
      echo "ERROR: linbo-scp failed for $sourcefile -> $STAGINGFILE (rc=$RC)" >&2
    }
    if [ "$RC" -ne 0 ]; then
      rm -f "$STAGINGFILE"
      echo "RC: $RC"
      echo "### rsync pre download end: $(date) ###"
      exit "$RC"
    fi
    if [ -s "$STAGINGFILE" ]; then
      case "$EXT" in
        log)
          cat "$STAGINGFILE" >> "$targetfile"
        ;;
        status)
          # Keep one line per image: drop the previous entry for this image
          # before appending the new one. Client uploads exactly one line per
          # sync (see shell_functions' log_image_status()), so without this
          # merge, syncing a second image on the same host would silently
          # discard every other image's line (#171). Match field 3 exactly,
          # not a regex - the pre-13ff562 code used an unanchored sed match
          # on the image name, which e.g. "jammy.qcow2" also matched inside
          # "data-jammy.qcow2", deleting the wrong entry.
          image="$(awk '{ print $3 }' "$STAGINGFILE")"
          if [ -s "$targetfile" ] && [ -n "$image" ]; then
            awk -v img="$image" '$3 != img' "$targetfile" > "$targetfile.new" \
              && mv "$targetfile.new" "$targetfile"
          fi
          cat "$STAGINGFILE" >> "$targetfile"
        ;;
        *)
          cp "$STAGINGFILE" "$targetfile"
        ;;
      esac
      rm -f "$STAGINGFILE"
      #touch "$STAGINGFILE"
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
