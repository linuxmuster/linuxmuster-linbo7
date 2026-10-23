#!/bin/sh
#
# Filename     : test_rsync-pre-upload.sh
# Description  : tests for the image upload checks of rsync-pre-upload.sh (issue #133)
# Signed-off by: thomas@linuxmuster.net
# Assisted by  : Claude
# Date         : 20261023
#
# is_image_path() only compares canonical paths, no file has to exist.
# upload_host_registered() asks "lmncli --csv devices", which is replaced by
# a stub function here printing a fixture csv. startconf_baseimages() and
# image_upload_allowed() work on a fixture start.conf and image dir below
# $SHUNIT_TMPDIR. The functions are plain POSIX, so they are tested under
# dash and busybox ash although the hook itself runs under bash.

SCRIPT="$(dirname "$0")/../../src/serverfs/usr/share/linuxmuster/linbo/rsync-pre-upload.sh"

oneTimeSetUp() {
  . "$(dirname "$0")/lib/extract_function.sh"
  extract_function "$SCRIPT" is_image_path upload_host_registered other_school_device \
    startconf_baseimages valid_image_basename image_upload_allowed \
    > "$SHUNIT_TMPDIR/rsync-pre-upload_functions.sh"
  . "$SHUNIT_TMPDIR/rsync-pre-upload_functions.sh"
}

setUp() {
  CSV="$SHUNIT_TMPDIR/devices.csv"
  ARGS="$SHUNIT_TMPDIR/lmncli.args"
  IMGDIR="$SHUNIT_TMPDIR/images"
  rm -rf "$CSV" "$ARGS" "$IMGDIR"
  mkdir -p "$IMGDIR"
  # native images of the client
  NATIVE="$(printf '%s\n' debian.qcow2 win11.qcow2)"
}

# creates image files below $IMGDIR: mkimage <name> <file> [<content>]
mkimage() {
  mkdir -p "$IMGDIR/$1"
  echo "${3:-x}" > "$IMGDIR/$1/$2"
}

# runs image_upload_allowed for a path relative to $IMGDIR
allowed() {
  image_upload_allowed "$IMGDIR" "$IMGDIR/$1" "$NATIVE" > /dev/null
}

# lmncli stub: records its arguments and prints the fixture csv
lmncli() {
  echo "$*" > "$ARGS"
  [ -e "$CSV" ] && cat "$CSV"
  return 0
}

HEADER='Room;Hostname;Group;IP;Mac;Role;LDAP'

# --- is_image_path() -----------------------------------------------------

test_is_image_path_accepts_files_below_the_image_dir() {
  assertTrue 'is_image_path /srv/linbo/images/noble/noble.qcow2 /srv/linbo/images'
}

test_is_image_path_rejects_files_outside_the_image_dir() {
  assertFalse 'is_image_path /srv/linbo/multi-1.new /srv/linbo/images'
  assertFalse 'is_image_path /srv/linbo/imagesfoo/x.qcow2 /srv/linbo/images'
}

test_is_image_path_rejects_the_image_dir_itself() {
  assertFalse 'is_image_path /srv/linbo/images /srv/linbo/images'
}

test_is_image_path_sees_through_double_slashes_and_dots() {
  assertTrue 'is_image_path /srv/linbo//images/./noble/noble.qcow2 /srv/linbo/images'
  assertTrue 'is_image_path /srv/linbo/x/../images/noble/noble.qcow2 /srv/linbo/images'
  assertFalse 'is_image_path /srv/linbo/images/../multi-1.new /srv/linbo/images'
}

# --- upload_host_registered() --------------------------------------------

test_upload_host_registered_asks_lmncli_for_the_ip() {
  upload_host_registered 10.0.100.1
  assertEquals "--csv devices 10.0.100.1" "$(cat "$ARGS")"
}

test_upload_host_registered_accepts_a_registered_device_and_prints_its_group() {
  cat > "$CSV" <<EOF
$HEADER
r100;multi-1;multi-disk0;10.0.100.1;52:54:00:70:af:79;classroom-studentcomputer;Registered
EOF
  output="$(upload_host_registered 10.0.100.1)"
  assertEquals 0 $?
  assertEquals "multi-disk0" "$output"
}

test_upload_host_registered_rejects_an_unregistered_device() {
  cat > "$CSV" <<EOF
$HEADER
r100;multi-1;multi-disk0;10.0.100.1;52:54:00:70:af:79;classroom-studentcomputer;Not registered
EOF
  assertFalse 'upload_host_registered 10.0.100.1'
}

test_upload_host_registered_rejects_an_unknown_ip() {
  echo "$HEADER" > "$CSV"
  assertFalse 'upload_host_registered 10.0.100.250'
}

test_upload_host_registered_rejects_a_substring_match_only() {
  # "lmncli devices 10.0.100.1" also lists 10.0.100.10 to .19
  cat > "$CSV" <<EOF
$HEADER
r100;pc10;multi-disk0;10.0.100.10;52:54:00:70:af:10;classroom-studentcomputer;Registered
EOF
  assertFalse 'upload_host_registered 10.0.100.1'
}

test_upload_host_registered_finds_the_columns_by_header_name() {
  cat > "$CSV" <<EOF
LDAP;IP;Hostname
Registered;10.0.100.1;multi-1
EOF
  assertTrue 'upload_host_registered 10.0.100.1 > /dev/null'
}

test_upload_host_registered_copes_with_crlf_line_ends() {
  printf '%s\r\n%s\r\n' "$HEADER" \
    "r100;multi-1;multi-disk0;10.0.100.1;52:54:00:70:af:79;classroom-studentcomputer;Registered" > "$CSV"
  assertTrue 'upload_host_registered 10.0.100.1 > /dev/null'
}

test_upload_host_registered_rejects_when_lmncli_prints_nothing() {
  assertFalse 'upload_host_registered 10.0.100.1'
}

test_upload_host_registered_rejects_an_empty_ip() {
  assertFalse 'upload_host_registered ""'
}

# --- other_school_device() -----------------------------------------------

# fixture sophomorix dir with default-school and school "s2"
mkschools() {
  SOPHDIR="$SHUNIT_TMPDIR/sophomorix"
  rm -rf "$SOPHDIR"
  mkdir -p "$SOPHDIR/default-school" "$SOPHDIR/s2"
  echo "r100;multi-1;multi-disk0;52:54:00:70:af:79;10.0.100.1;;;;classroom-studentcomputer;;1" \
    > "$SOPHDIR/default-school/devices.csv"
  printf '%s\r\n' "r1;pc1;g1;52:54:00:00:00:01;10.2.0.1;;;;classroom-studentcomputer;;1" \
    "#r1;pc2;g1;52:54:00:00:00:02;10.2.0.2;;;;classroom-studentcomputer;;1" \
    > "$SOPHDIR/s2/s2.devices.csv"
}

test_other_school_device_finds_a_device_of_another_school() {
  mkschools
  assertTrue 'other_school_device 10.2.0.1 "$SOPHDIR"'
}

test_other_school_device_ignores_default_school_and_comments() {
  mkschools
  assertFalse 'other_school_device 10.0.100.1 "$SOPHDIR"'
  assertFalse 'other_school_device 10.2.0.2 "$SOPHDIR"'
}

test_other_school_device_compares_the_ip_exactly() {
  mkschools
  assertFalse 'other_school_device 10.2.0.10 "$SOPHDIR"'
  assertFalse 'other_school_device 10.2.0 "$SOPHDIR"'
}

test_other_school_device_rejects_an_empty_ip() {
  mkschools
  assertFalse 'other_school_device "" "$SOPHDIR"'
}

# --- startconf_baseimages() ----------------------------------------------

test_startconf_baseimages_prints_all_baseimages() {
  startconf="$SHUNIT_TMPDIR/start.conf"
  printf '%s\r\n' '[OS]' 'Name = Windows' 'BaseImage = win11.qcow2' \
    '[OS]' 'baseimage=debian.qcow2   # comment' '#BaseImage = old.qcow2' \
    'Description = BaseImage = no' > "$startconf"
  assertEquals "$(printf '%s\n' win11.qcow2 debian.qcow2)" "$(startconf_baseimages "$startconf")"
}

test_startconf_baseimages_prints_nothing_for_a_missing_file() {
  assertEquals "" "$(startconf_baseimages "$SHUNIT_TMPDIR/no_such_start.conf")"
}

# --- image_upload_allowed() ----------------------------------------------

test_image_upload_allowed_accepts_native_images() {
  assertTrue 'allowed debian/debian.qcow2'
  assertTrue 'allowed debian/debian.qcow2.info'
  mkimage win11 win11.qcow2.info 'image="win11.qcow2"'
  assertTrue 'allowed win11/win11.qcow2'
}

test_image_upload_allowed_rejects_files_outside_an_image_dir() {
  assertFalse 'allowed debian.qcow2'
  assertFalse 'allowed debian/backups/202610231200/debian.qcow2'
}

test_image_upload_allowed_rejects_files_of_another_image() {
  assertFalse 'allowed debian/win11.qcow2'
  assertFalse 'allowed debian/debian-old.qcow2'
}

test_image_upload_allowed_needs_the_base_image_for_a_differential_image() {
  assertFalse 'allowed debian/debian.qdiff'
  assertFalse 'allowed debian/debian.qdiff.info'
  mkimage debian debian.qcow2
  assertTrue 'allowed debian/debian.qdiff'
  assertTrue 'allowed debian/debian.qdiff.info'
}

test_image_upload_allowed_accepts_a_new_image_name() {
  assertTrue 'allowed noble/noble.qcow2'
  # the info file follows the image, which is already uploaded then
  mkimage noble noble.qcow2
  assertTrue 'allowed noble/noble.qcow2.info'
}

test_image_upload_allowed_rejects_an_invalid_new_image_name() {
  assertFalse 'allowed no.ble/no.ble.qcow2'
}

test_image_upload_allowed_rejects_a_differential_image_under_a_new_name() {
  mkimage noble noble.qcow2
  assertFalse 'allowed noble/noble.qdiff'
}

test_image_upload_allowed_accepts_an_image_derived_from_a_native_image() {
  mkimage noble noble.qcow2.info 'sourceimage="debian.qcow2"'
  assertTrue 'allowed noble/noble.qcow2'
  assertTrue 'allowed noble/noble.qcow2.desc'
}

test_image_upload_allowed_rejects_overwriting_a_foreign_image() {
  # native image of another group
  mkimage ubuntu ubuntu.qcow2.info 'image="ubuntu.qcow2"'
  assertFalse 'allowed ubuntu/ubuntu.qcow2'
  # derived from an image that is not native for this client
  mkimage noble noble.qcow2.info 'sourceimage="focal.qcow2"'
  assertFalse 'allowed noble/noble.qcow2'
}

. "$(dirname "$0")/shunit2"
