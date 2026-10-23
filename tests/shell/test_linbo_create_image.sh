#!/bin/sh
#
# Filename     : test_linbo_create_image.sh
# Description  : tests for creating an image under a new name (issue #133)
# Signed-off by: thomas@linuxmuster.net
# Assisted by  : Claude
# Date         : 20261023
#
# valid_image_basename() and get_sourceimage() are pure string checks.
# check_server_image() asks the server via linbo_download, which is replaced
# by a stub function here: it "downloads" a fixture info file into the
# current directory, or fails like rsync does for a missing file. TMPDIR
# points to $SHUNIT_TMPDIR, so no real /tmp path is touched.

SCRIPT="$(dirname "$0")/../../src/linbofs/usr/bin/linbo_create_image"

oneTimeSetUp() {
  . "$(dirname "$0")/lib/extract_function.sh"
  extract_function "$SCRIPT" valid_image_basename get_sourceimage check_server_image \
    > "$SHUNIT_TMPDIR/linbo_create_image_functions.sh"
  . "$SHUNIT_TMPDIR/linbo_create_image_functions.sh"
}

setUp() {
  TMPDIR="$SHUNIT_TMPDIR"
  FIXTURE="$SHUNIT_TMPDIR/fixture.info"
  REQUESTED="$SHUNIT_TMPDIR/requested"
  rm -f "$FIXTURE" "$REQUESTED"
}

# linbo_download stub: records the requested path and copies $FIXTURE into
# the current directory under the requested file name, if there is one
linbo_download() {
  echo "$1" > "$REQUESTED"
  [ -s "$FIXTURE" ] || return 23
  cp "$FIXTURE" "$(basename "$1")"
}

# --- valid_image_basename() ----------------------------------------------

test_valid_image_basename_accepts_letters_digits_underscore_dash() {
  assertTrue 'valid_image_basename noble'
  assertTrue 'valid_image_basename Noble_24-04'
  assertTrue 'valid_image_basename win11-2026'
}

test_valid_image_basename_rejects_empty_name() {
  assertFalse 'valid_image_basename ""'
}

test_valid_image_basename_rejects_dots_slashes_and_spaces() {
  assertFalse 'valid_image_basename no.ble'
  assertFalse 'valid_image_basename ../noble'
  assertFalse 'valid_image_basename images/noble'
  assertFalse 'valid_image_basename "no ble"'
}

# --- get_sourceimage() ---------------------------------------------------

test_get_sourceimage_prints_nothing_for_the_native_base_image() {
  output="$(get_sourceimage jammy.qcow2 jammy.qcow2)"
  assertEquals 0 $?
  assertEquals "" "$output"
}

test_get_sourceimage_prints_nothing_for_the_native_differential_image() {
  output="$(get_sourceimage jammy.qdiff jammy.qcow2)"
  assertEquals 0 $?
  assertEquals "" "$output"
}

test_get_sourceimage_prints_the_native_image_for_a_new_name() {
  output="$(get_sourceimage noble.qcow2 jammy.qcow2)"
  assertEquals 0 $?
  assertEquals "jammy.qcow2" "$output"
}

test_get_sourceimage_rejects_a_differential_image_under_a_new_name() {
  output="$(get_sourceimage noble.qdiff jammy.qcow2 2> /dev/null)"
  assertEquals 1 $?
  assertEquals "" "$output"
}

test_get_sourceimage_rejects_an_invalid_new_name() {
  get_sourceimage no.ble.qcow2 jammy.qcow2 > /dev/null 2>&1
  assertEquals 1 $?
  get_sourceimage ../noble.qcow2 jammy.qcow2 > /dev/null 2>&1
  assertEquals 1 $?
}

test_get_sourceimage_rejects_an_unknown_image_type() {
  get_sourceimage noble.img jammy.qcow2 > /dev/null 2>&1
  assertEquals 1 $?
}

# --- check_server_image() ------------------------------------------------

test_check_server_image_asks_for_the_info_file_in_the_image_dir() {
  check_server_image noble.qcow2 jammy.qcow2 > /dev/null
  assertEquals "images/noble/noble.qcow2.info" "$(cat "$REQUESTED")"
}

test_check_server_image_accepts_an_image_missing_on_the_server() {
  check_server_image noble.qcow2 jammy.qcow2 > /dev/null
  assertEquals 0 $?
}

test_check_server_image_accepts_an_image_derived_from_the_same_source() {
  cat > "$FIXTURE" <<EOF
["noble.qcow2" Info File]
timestamp="202610231200"
image="noble.qcow2"
sourceimage="jammy.qcow2"
EOF
  check_server_image noble.qcow2 jammy.qcow2 > /dev/null
  assertEquals 0 $?
}

test_check_server_image_rejects_an_image_derived_from_another_source() {
  cat > "$FIXTURE" <<EOF
["noble.qcow2" Info File]
image="noble.qcow2"
sourceimage="focal.qcow2"
EOF
  check_server_image noble.qcow2 jammy.qcow2 > /dev/null
  assertEquals 1 $?
}

test_check_server_image_rejects_an_existing_native_image() {
  cat > "$FIXTURE" <<EOF
["noble.qcow2" Info File]
image="noble.qcow2"
EOF
  check_server_image noble.qcow2 jammy.qcow2 > /dev/null
  assertEquals 1 $?
}

test_check_server_image_removes_its_temporary_dir() {
  check_server_image noble.qcow2 jammy.qcow2 > /dev/null
  assertFalse '[ -e "$SHUNIT_TMPDIR/check_server_image.$$" ]'
}

. "$(dirname "$0")/shunit2"
