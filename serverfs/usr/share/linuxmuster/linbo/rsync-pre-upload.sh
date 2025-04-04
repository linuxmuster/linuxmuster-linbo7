#!/bin/bash
#
# (C) Klaus Knopper 2007
# Pre-Upload script for rsync/LINBO:
# Moves old version of file out of the way,
# and installs a new version.
#
# thomas@linuxmuster.net
# 20250326
# GPL v3
#

# read in linuxmuster specific environment
source /usr/share/linuxmuster/helperfunctions.sh || exit 1

# Debug
LOGFILE="$RSYNC_MODULE_PATH/log/rsync-pre-upload.log"
exec >>$LOGFILE 2>&1
#echo "$0 $*, Variables:" ; set

echo "### rsync pre upload begin: $(date) ###"

# Needs Version 2.9 of rsync
[ -n "$RSYNC_PID" ] || exit 0

FILE="${RSYNC_MODULE_PATH}/${RSYNC_REQUEST##$RSYNC_MODULE_NAME/}"
DIRNAME="$(dirname $FILE)"
BASENAME="$(basename $FILE)"
BACKUP="${FILE}.BAK"
PIDFILE="/tmp/rsync.$RSYNC_PID"

# Save filename for post-script and exit, if it is a new host data file
EXT="${BASENAME##*.}"

# fetch host & domainname
do_rsync_hostname

echo "HOSTNAME: $RSYNC_HOST_NAME"
echo "IP: $RSYNC_HOST_ADDR"
echo "RSYNC_REQUEST: $RSYNC_REQUEST"
echo "FILE: $FILE"
echo "PIDFILE: $PIDFILE"
echo "EXT: $EXT"

if [ "$EXT" = "new" ]; then
  [ -e "$PIDFILE" ] && rm -f "$PIDFILE"
  echo "$FILE" > "$PIDFILE"
  exit 0
fi

# create image directory in case of qcow2
[ "$EXT" = "qcow2" -o "$EXT" = "qdiff" ] && mkdir -p "$DIRNAME"

# Bailout with error if backup file exists (another process is uploading)
if [ -e "$BACKUP" ]; then
  # check if there is another upload for the same file
  TMPFILE="$(ls -t ${DIRNAME}/.${BASENAME}.* 2> /dev/null | head -1)"
  if [ -n "$TMPFILE" ]; then
    # check if file grows
    size1="$(ls -l $TMPFILE | awk '{ print $5 }')"
    sleep 5
    size2="$(ls -l $TMPFILE | awk '{ print $5 }')"
    # if file is not growing remove it
    if [ "$size1" = "$size2" ]; then
      echo "Removing stale temp file $TMPFILE!"
      rm -f "$TMPFILE"
    else
      echo "Backup file exists for ${FILE##*/}, another upload in progress?" >&2
      exit 1
    fi
  fi
fi
if [ -e "$BACKUP" ]; then
  echo "Removing stale backup file $BACKUP!"
  rm -f "$BACKUP"
fi

# Create backups, if file exists, otherwise save only the filename.
[ -d "$FILE" ] && exit 0
if [ -e "$FILE" ]; then
  # Move file out of the way
  mv -fv "$FILE" "$BACKUP" ; RC="$?"
else
  RC=0
fi

# Save filename for post-script and exit
[ "$RC" = "0" ] && { rm -f "$PIDFILE" ; echo "$FILE" > "$PIDFILE"; }

echo "RC: $RC"
echo "### rsync pre upload end: $(date) ###"

exit $RC
# post-script will change the name of the backup to a more meaningful one,
# or rename it back in case of a failed download.
