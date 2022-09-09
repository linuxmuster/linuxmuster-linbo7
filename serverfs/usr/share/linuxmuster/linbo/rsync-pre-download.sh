#!/bin/bash
#
# Pre-Download script for rsync/LINBO
# thomas@linuxmuster.net
# 20220909
#

# read in linuxmuster specific environment
source /usr/share/linuxmuster/linbo/helperfunctions.sh || exit 1

# Debug
LOGFILE="$RSYNC_MODULE_PATH/log/rsync-pre-download.log"
exec >>$LOGFILE 2>&1
#echo "$0 $*, Variables:" ; set

echo "### rsync pre download begin: $(date) ###"

FILE="${RSYNC_MODULE_PATH}/${RSYNC_REQUEST##$RSYNC_MODULE_NAME/}"
PIDFILE="/tmp/rsync.$RSYNC_PID"
echo "$FILE" > "$PIDFILE"

EXT="${FILE##*.}"
BASENAME="$(basename "$FILE")"
BASE="$(echo "$BASENAME" | sed 's/\(.*\)\..*/\1/')"
case "$EXT" in desc|info|macct|torrent) BASE="$(echo "$BASE" | sed 's/\(.*\)\..*/\1/')" ;; esac
case "$FILE" in
  *.cloop*) IMGDIR="$LINBODIR" ;;
  *.qcow2*) IMGDIR="$LINBOIMGDIR/$BASE" ;;
esac

# fetch host & domainname
do_rsync_hostname

# recognize upload of windows activation tokens
stringinstring "winact.tar.gz.upload" "$FILE" && EXT="winact-upload"

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
    LDBSEARCH="$(which ldbsearch) $url"
    LDBMODIFY="$(which ldbmodify) $url"
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
        dn="$($LDBSEARCH "(&(sAMAccountName=$compname$))" | grep ^dn | awk '{ print $2 }')"
        if [ -n "$dn" ]; then
          echo "DN: $dn"
          ldif="/var/tmp/${compname}_macct.$$"
          ldbopts="--nosync --verbose --controls=relax:0 --controls=local_oid:1.3.6.1.4.1.7165.4.3.7:0 --controls=local_oid:1.3.6.1.4.1.7165.4.3.12:0"
          sed -e "s|@@dn@@|$dn|" "$imagemacct" > "$ldif"
          $LDBMODIFY $ldbopts "$ldif"
          rm -f "$ldif"
        else
          echo "Cannot determine DN of $compname! Aborting!"
        fi
        break
      fi
    done
  ;;

  # fetch logfiles from client
  log)
    host_logfile="$(basename "$FILE")"
    echo "Upload request for $host_logfile."
    src_logfile="$(echo "$FILE" | sed -e "s|$LINBODIR/tmp/${compname}_|/tmp/|I")"
    tgt_logfile="$LINBOLOGDIR/$host_logfile"
    linbo-scp -v "${RSYNC_HOST_ADDR}:$src_logfile" "$FILE" || RC="1"
    if [ -s "$FILE" ]; then
      echo "## Log session begin: $(date) ##" >> "$tgt_logfile"
      cat "$FILE" >> "$tgt_logfile"
      echo "## Log session end: $(date) ##" >> "$tgt_logfile"
    fi
    rm -f "$FILE"
    touch "$FILE"
  ;;

  # fetch image status from client
  status)
    host_logfile="$(basename "$FILE")"
    echo "Upload request for $host_logfile."
    src_logfile="$(echo "$FILE" | sed -e "s|$LINBODIR/tmp/${compname}_|/tmp/|I")"
    tgt_logfile="$LINBOLOGDIR/$host_logfile"
    linbo-scp -v "${RSYNC_HOST_ADDR}:$src_logfile" "$FILE" || RC="1"
    if [ -s "$FILE" ]; then
      if [ -s "$tgt_logfile" ]; then
        # remove older entry for image
        image="$(cat "$FILE" | awk '{ print $3 }')"
        [ -n "$image" ] && sed -i "/$image/d" "$tgt_logfile"
      fi
      cat "$FILE" >> "$tgt_logfile"
    fi
    rm -f "$FILE"
    touch "$FILE"
  ;;

  # patch image registry files with sambadomain if necessary
  reg)
    search="Domain\"=\"$sambadomain\""
    if ! grep -q "$search" "$FILE"; then
      sed -i "s|Domain\"=.*|$search|g" "$FILE"
    fi
  ;;

  # handle windows product key request
  winkey)
    # get key from workstations and write it to temporary file
    if [ -n "$compname" ]; then
      winkey="$(grep ^[a-zA-Z0-9] $WIMPORTDATA | awk -F\; '{ print $2 " " $7 }' | grep -w $compname | awk '{ print $2 }' | tr a-z A-Z)"
      officekey="$(grep ^[a-zA-Z0-9] $WIMPORTDATA | awk -F\; '{ print $2 " " $6 }' | grep -w $compname | awk '{ print $2 }' | tr a-z A-Z)"
      [ -n "$winkey" ] && echo "winkey=$winkey" > "$FILE"
      [ -n "$officekey" ] && echo "officekey=$officekey" >> "$FILE"
    fi
  ;;

  # handle windows activation tokens archive
  winact-upload)
    RC=0
    FILE="${FILE%.upload}"
    # fetch archive from client
    echo "Upload request for windows activation tokens archive."
    linbo-scp "${RSYNC_HOST_ADDR}:/cache/$(basename $FILE)" "${FILE}.tmp" || RC="1"
    # if archive file already exists try to merge old and new archives
    if [ -s "$FILE" -a "$RC" = "0" ]; then
      echo "Updating existing archive $FILE."
      tmpdir="/var/tmp/winact-upload.$$"
      curdir="$(pwd)"
      mkdir -p "$tmpdir"
      # extract old archive to tmpdir
      tar xf "$FILE" -C "$tmpdir" || RC="1"
      if [ "$RC" = "0" ]; then
        # extract uploaded archive over old archive in tmpdir
        tar xf "${FILE}.tmp" -C "$tmpdir" || RC="1"
      fi
      if [ "$RC" = "0" ]; then
        rm -f "${FILE}.tmp"
        cd "$tmpdir"
        # pack content of tmpdir to temporary archive
        tar czf "${FILE}.tmp" * || RC="1"
        cd "$curdir"
      fi
      rm -rf "$tmpdir"
    fi
    # move uploaded file in place
    if [ "$RC" = "0" ]; then
      rm -f "$FILE"
      mv "${FILE}.tmp" "$FILE" || RC="1"
    fi
    if [ "$RC" = "0" ]; then
      echo "Upload of $FILE successfully finished."
    else
      echo "Sorry. Upload of $FILE failed."
    fi
    rm -f "$PIDFILE"
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

  # handle start.conf request
  conf_*)
    group="$(get_hostgroup "$compname")"
    startconf="$LINBODIR/start.conf.$group"
    if [ -n "$group" -a -s "$startconf" ]; then
      cp "$startconf" "$FILE"
    else
      cp -L "$LINBODIR/start.conf" "$FILE"
    fi
  ;;

  *) ;;

esac

echo "RC: $RSYNC_EXIT_STATUS"
echo "### rsync pre download end: $(date) ###"

exit $RSYNC_EXIT_STATUS
