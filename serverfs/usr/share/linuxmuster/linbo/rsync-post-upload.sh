#!/bin/bash
#
# thomas@linuxmuster.net
# 20220908
#

# read in linuxmuster specific environment
source /usr/share/linuxmuster/linbo/helperfunctions.sh || exit 1

# where to place the temporary image backup
BAKTMP="$LINBOIMGDIR/tmp"
# logfile
LOGFILE="$LINBOLOGDIR/rsync-post-upload.log"

# Debug
exec >>$LOGFILE 2>&1
#echo "$0 $*, Variables:" ; set

echo "### rsync post upload begin: $(date) ###"

# Needs Version 2.9 of rsync
[ -n "$RSYNC_PID" ] || exit 0

PIDFILE="/tmp/rsync.$RSYNC_PID"

# Check for pidfile, exit if nothing to do
[ -s "$PIDFILE" ] || exit 0

FILE="$(<$PIDFILE)"
rm -f "$PIDFILE"
BACKUP="${FILE}.BAK"
EXT="${FILE##*.}"
BASENAME="$(basename "$FILE")"
BASE="$(echo "$BASENAME" | sed 's/\(.*\)\..*/\1/')"
case "$EXT" in desc|info|macct|torrent) BASE="$(echo "$BASE" | sed 's/\(.*\)\..*/\1/')" ;; esac
IMGDIR="$LINBOIMGDIR/$BASE"

# fetch host & domainname
do_rsync_hostname

echo "HOSTNAME: $RSYNC_HOST_NAME"
echo "IP: $RSYNC_HOST_ADDR"
echo "RSYNC_REQUEST: $RSYNC_REQUEST"
echo "FILE: $FILE"
echo "PIDFILE: $PIDFILE"
echo "EXT: $EXT"

# Check for backup file that should have been created by pre-upload script
if [ -s "$BACKUP" ]; then
  if [ "$RSYNC_EXIT_STATUS" = "0" ]; then
    echo "Upload of $BASENAME was successful." >&2
    case "$EXT" in
      qcow2)
        # qcow2 is the first file of image upload, so place backup file in temporary dir
        # cause without info file we don't know the timestamp
        mkdir -p "$BAKTMP"
        ARCHIVE="$BAKTMP/$BASENAME"
        mv -fv "$BACKUP" "$ARCHIVE"
        echo "$BASENAME successfully backed up." >&2
        # backup supplemental image files that reside on server
        for i in macct reg postsync prestart; do
          cp -f "$IMGDIR"/*."$i" "$BAKTMP" &> /dev/null
        done
        chmod 600 "$BAKTMP"/*.macct &> /dev/null
      ;;
      *)
        # next is the info file, so we can get the timestamp and create the final backup dir
        INFOFILE="$(ls $IMGDIR/*.info)"
        eval "$(grep -i ^timestamp "$INFOFILE")" &> /dev/null
        if [ -n "$timestamp" ]; then
          BAKDIR="$IMGDIR/backups/$timestamp"
          mkdir -p "$BAKDIR"
          ARCHIVE="$BAKDIR/$BASENAME"
          mv -fv "$BACKUP" "$ARCHIVE"
          echo "$BASENAME successfully backed up." >&2
          # move backups from temporary backup dir to final backup dir
          if [ -n "$(ls -A "$BAKTMP")" ]; then
            for i in "$BAKTMP/$BASE"*; do
              mv -fv "$i" "$BAKDIR"
            done
          fi
        fi
      ;;
    esac
  else
    # If upload failed, move old file back from backup.
    echo "Upload of $BASENAME failed." >&2
    mv -fv "$BACKUP" "$FILE"
    echo "Recovered $BASENAME from backup." >&2
    # remove empty BAKDIR
    if [ -d "$BAKDIR"]; then
      [ -z "$(ls -A "$BAKDIR")" ] && rm -rf "$BAKDIR"
    fi
  fi
fi

# do something depending on file type
case "$EXT" in

  qcow2)
    # restart multicast service if image file was uploaded.
    echo "Image file $BASENAME detected. Restarting multicast service if enabled." >&2
    linbo-multicast restart >&2

    # save samba passwords of host we made the new image
    LDBSEARCH="$(which ldbsearch)"
    if [ -n "$RSYNC_HOST_NAME" -a -n "$LDBSEARCH" -a -n "$basedn" ]; then
      #  fetch samba nt password hash from ldap machine account
      url="--url=/var/lib/samba/private/sam.ldb"
      unicodepwd="$("$LDBSEARCH" "$url" "(&(sAMAccountName=$compname$))" unicodePwd | grep ^unicodePwd:: | awk '{ print $2 }')"
      suppcredentials="$(ldbsearch "$url" "(&(sAMAccountName=$compname$))" supplementalCredentials | sed -n '/^'supplementalCredentials':/,/^$/ { /^'supplementalCredentials':/ { s/^'supplementalCredentials': *// ; h ; $ !d}; /^ / { H; $ !d}; /^ /! { x; s/\n //g; p; q}; $ { x; s/\n //g; p; q} }' | awk '{ print $2 }')"
      if [ -n "$unicodepwd" ]; then
        echo "Writing samba password hash file for image $image."
        template="$LINBOTPLDIR/machineacct"
        imagemacct="$IMGDIR/${BASENAME}.macct"
        sed -e "s|@@unicodepwd@@|$unicodepwd|" -e "s|@@suppcredentials@@|$suppcredentials|" "$template" > "$imagemacct"
        chmod 600 "$imagemacct"
        # remove obsolete macct file if present
        rm -f "$IMGDIR/${BASE}.macct"
      else
        rm -f "$imagemacct"
      fi
    fi

  ;;

  torrent)
    # restart torrent service if torrent file was uploaded.
    echo "Torrent file $BASENAME detected. Restarting linbo-torrent service." >&2
    linbo-torrent restart $BASENAME >&2
  ;;

  new)
    # make row lmn7 compatible
    search=";;;;;1;1"
    replace=";;;;classroom-studentcomputer;;1;;;;;"
    ROW="$(sed -e "s|$search|$replace|" $FILE)"
    # add row with new host data to devices file
    if grep -i "$ROW" $WIMPORTDATA | grep -qv ^#; then
      echo "$ROW"
      echo "is already present in workstations file. Skipped!" >&2
    else
      echo "Adding row to $WIMPORTDATA." >&2
      echo "$ROW" >> $WIMPORTDATA
      # save last registered host
      echo "$ROW" > "$LINBODIR/last_registered"
    fi
    rm $FILE
  ;;

  *) ;;

esac

echo "RC: $RSYNC_EXIT_STATUS"
echo "### rsync post upload end: $(date) ###"

exit $RSYNC_EXIT_STATUS
