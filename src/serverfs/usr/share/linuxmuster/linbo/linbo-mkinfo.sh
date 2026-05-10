#!/bin/sh
#
# linbo-mkinfo
# thomas@linuxmuster.net
# 20250510
#

usage(){
  RC="$1"
  echo
  echo "Creates a simple image info file."
  echo
  echo "Usage: linbo-mkinfo.sh <path_to_imagefile> | [help]"
  echo
  exit "$RC"
}

# print help
[ -z "$1" -o "$1" = "help" ] && usage 0

# check options
[ -s "$1" ] || usage 1

imagefile="$1"
imageinfo="${imagefile}.info"
imagebase="$(basename "$imagefile")"

# get isofile size
imagesize_new="$(ls -l "$imagefile" 2>/dev/null | awk '{print $5}' 2>/dev/null)"

# check if existent infofile is up to date
if [ -s "$imageinfo" ]; then
  eval "$(grep ^imagesize "$imageinfo")"
  if [ "$imagesize" = "$imagesize_new" ]; then
    echo "$imagebase has not changed, infofile will not be updated."
    exit 0
  fi
fi

timestamp="$(date +%Y%m%d%H%M)"

# write infofile
cat <<EOF > "$imageinfo"
[$imagebase Info File]
timestamp="$timestamp"
image="$imagebase"
imagesize="$imagesize_new"
EOF
