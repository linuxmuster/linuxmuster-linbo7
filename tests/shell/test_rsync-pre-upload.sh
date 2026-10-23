#!/bin/sh
#
# Filename     : test_rsync-pre-upload.sh
# Description  : tests for the image upload host check of rsync-pre-upload.sh (issue #133)
# Signed-off by: thomas@linuxmuster.net
# Assisted by  : Claude
# Date         : 20261023
#
# is_image_path() only compares canonical paths, no file has to exist.
# upload_host_registered() asks "lmncli --csv devices", which is replaced by
# a stub function here printing a fixture csv. The functions are plain POSIX,
# so they are tested under dash and busybox ash although the hook itself
# runs under bash.

SCRIPT="$(dirname "$0")/../../src/serverfs/usr/share/linuxmuster/linbo/rsync-pre-upload.sh"

oneTimeSetUp() {
  . "$(dirname "$0")/lib/extract_function.sh"
  extract_function "$SCRIPT" is_image_path upload_host_registered other_school_device \
    > "$SHUNIT_TMPDIR/rsync-pre-upload_functions.sh"
  . "$SHUNIT_TMPDIR/rsync-pre-upload_functions.sh"
}

setUp() {
  CSV="$SHUNIT_TMPDIR/devices.csv"
  ARGS="$SHUNIT_TMPDIR/lmncli.args"
  rm -f "$CSV" "$ARGS"
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

test_upload_host_registered_accepts_a_registered_device() {
  cat > "$CSV" <<EOF
$HEADER
r100;multi-1;multi-disk0;10.0.100.1;52:54:00:70:af:79;classroom-studentcomputer;Registered
EOF
  assertTrue 'upload_host_registered 10.0.100.1'
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
  assertTrue 'upload_host_registered 10.0.100.1'
}

test_upload_host_registered_copes_with_crlf_line_ends() {
  printf '%s\r\n%s\r\n' "$HEADER" \
    "r100;multi-1;multi-disk0;10.0.100.1;52:54:00:70:af:79;classroom-studentcomputer;Registered" > "$CSV"
  assertTrue 'upload_host_registered 10.0.100.1'
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

. "$(dirname "$0")/shunit2"
