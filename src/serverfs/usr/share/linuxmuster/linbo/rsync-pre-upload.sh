#!/bin/bash
#
# Filename     : rsync-pre-upload.sh
# Description  : rsync pre-xfer hook of the linbo-upload module
# Signed-off by: thomas@linuxmuster.net
# Assisted by  : Claude
# Date         : 20261023
#
# (C) Klaus Knopper 2007
# Pre-Upload script for rsync/LINBO:
# Moves old version of file out of the way,
# and installs a new version.
# GPL v3
#


#### functions begin ####

# is_image_path file imgdir
# true if file lies below imgdir, compared as canonical paths
is_image_path(){
  local file
  local imgdir
  file="$(realpath -m "$1")"
  imgdir="$(realpath -m "$2")"
  case "$file" in
    "$imgdir"/*) return 0 ;;
  esac
  return 1
}


# upload_host_registered ip
# true if devices.csv has a device with exactly this ip whose machine account
# is registered in ldap ("lmncli devices" filters by substring, so the ip
# column is compared exactly), prints the group of the device
upload_host_registered(){
  local ip="$1"
  [ -n "$ip" ] || return 1
  lmncli --csv devices "$ip" 2> /dev/null | awk -F';' -v ip="$ip" '
    { gsub(/\r/, "") }
    NR == 1 { for (i = 1; i <= NF; i++) col[$i] = i ; next }
    col["IP"] && col["LDAP"] && $col["IP"] == ip && $col["LDAP"] == "Registered" {
      found = 1
      if (col["Group"]) group = $col["Group"]
    }
    END { if (found) print group ; exit !found }'
}


# other_school_device ip [sophomorixdir]
# true if ip belongs to a device of a school other than default-school
# (<school>/<school>.devices.csv). Multi-school environments are not
# supported by the image upload checks yet, so these devices stay unchecked.
other_school_device(){
  local ip="$1"
  local dir="${2:-/etc/linuxmuster/sophomorix}"
  local csv
  [ -n "$ip" ] || return 1
  for csv in "$dir"/*/*.devices.csv; do
    [ -s "$csv" ] || continue
    awk -F';' -v ip="$ip" '
      { gsub(/\r/, "") }
      $1 !~ /^#/ && $5 == ip { found = 1 }
      END { exit !found }' "$csv" && return 0
  done
  return 1
}

# startconf_baseimages startconf
# prints the BaseImage entries of a start.conf, one per line
startconf_baseimages(){
  [ -s "$1" ] || return 0
  awk -F= '
    { gsub(/\r/, "") }
    tolower($1) ~ /^[ \t]*baseimage[ \t]*$/ {
      value = $2
      sub(/#.*/, "", value)
      gsub(/[ \t]/, "", value)
      if (value != "") print value
    }' "$1"
}


# valid_image_basename name
# a new image name may only consist of letters, digits, "_" and "-"
valid_image_basename(){
  case "$1" in
    ""|*[!A-Za-z0-9_-]*) return 1 ;;
  esac
  return 0
}


# image_upload_allowed imgdir file baseimages
# Decides on an upload below the image dir (both canonical paths). baseimages
# are the native images of the client's start.conf, one per line.
# - image files reside directly in images/<name>/ and are named <name>.*
# - differential image files need the base image on the server
# - a native image of the client may always be uploaded
# - an image under a new name must have a valid name, cannot be differential
#   and must not overwrite an image that is not derived from a native image
#   of the client (decided by the sourceimage of the existing info file)
image_upload_allowed(){
  local imgdir="$1"
  local file="$2"
  local baseimages="$3"
  local rel="${file#"$imgdir"/}"
  local name="${rel%%/*}"
  local filename="${rel#*/}"
  local image="${name}.qcow2"
  local infofile="$imgdir/$name/${image}.info"
  local sourceimage
  if [ "$rel" = "$name" ] || [ "$filename" != "${filename#*/}" ]; then
    echo "$rel is not an image file in an image directory."
    return 1
  fi
  case "$filename" in
    "$name".*) ;;
    *)
      echo "$filename does not belong to image $image."
      return 1
      ;;
  esac
  case "$filename" in
    "$name".qdiff|"$name".qdiff.*)
      if [ ! -s "$imgdir/$name/$image" ]; then
        echo "Base image $image of $filename is missing on the server."
        return 1
      fi
      ;;
  esac
  echo "$baseimages" | grep -qxF -e "$image" && return 0
  # image under a new name
  if ! valid_image_basename "$name"; then
    echo "Invalid image name $name, allowed are letters, digits, \"_\" and \"-\"."
    return 1
  fi
  case "$filename" in
    "$name".qdiff|"$name".qdiff.*)
      echo "Differential images cannot be uploaded under a new name."
      return 1
      ;;
  esac
  [ -s "$infofile" ] || return 0
  sourceimage="$(grep ^sourceimage= "$infofile" | awk -F\" '{print $2}')"
  if [ -n "$sourceimage" ] && echo "$baseimages" | grep -qxF -e "$sourceimage"; then
    return 0
  fi
  echo "Image $image exists and is not derived from a native image of this client."
  return 1
}

#### functions end ####


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

# image files are only accepted from devices registered in devices.csv and
# ldap, other uploads (e.g. the registration of a new host) are not affected;
# devices of other schools are not checked until multi-school is supported
if is_image_path "$FILE" "$LINBOIMGDIR"; then
  if GROUP="$(upload_host_registered "$RSYNC_HOST_ADDR")"; then
    # native images of the client and guards for images under a new name
    BASEIMAGES="$(startconf_baseimages "$LINBODIR/start.conf.$GROUP")"
    if ! image_upload_allowed "$(realpath -m "$LINBOIMGDIR")" "$(realpath -m "$FILE")" "$BASEIMAGES"; then
      echo "Upload of $BASENAME refused."
      exit 1
    fi
  elif other_school_device "$RSYNC_HOST_ADDR"; then
    echo "$RSYNC_HOST_ADDR is a device of another school, upload of $BASENAME is not checked."
  else
    echo "Upload of $BASENAME refused: $RSYNC_HOST_ADDR is not a registered device."
    exit 1
  fi
fi

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
