#!/bin/sh
#
# Filename     : test_linbo_upload.sh
# Description  : tests for image_size_matches() of linbo_upload
# Signed-off by: thomas@linuxmuster.net
# Assisted by  : Claude
# Date         : 20261024
#
# image_size_matches() compares the imagesize of an image's info file with
# the image's actual size, on fixture files below $SHUNIT_TMPDIR.
# get_filesize() comes from shell_functions.

SCRIPT="$(dirname "$0")/../../src/linbofs/usr/bin/linbo_upload"
FUNCTIONS="$(dirname "$0")/../../src/linbofs/usr/share/linbo/shell_functions"

oneTimeSetUp() {
  . "$(dirname "$0")/lib/extract_function.sh"
  {
    extract_function "$FUNCTIONS" get_filesize
    extract_function "$SCRIPT" image_size_matches
  } > "$SHUNIT_TMPDIR/linbo_upload_functions.sh"
  . "$SHUNIT_TMPDIR/linbo_upload_functions.sh"
}

setUp() {
  IMAGE="$SHUNIT_TMPDIR/noble.qcow2"
  rm -f "$IMAGE" "$IMAGE.info"
  # an image of 1000 bytes
  head -c 1000 /dev/zero > "$IMAGE"
}

test_image_size_matches_accepts_a_complete_image() {
  printf '%s\n' '["noble.qcow2" Info File]' 'image="noble.qcow2"' 'imagesize="1000"' > "$IMAGE.info"
  assertTrue 'image_size_matches "$IMAGE"'
}

test_image_size_matches_accepts_an_unquoted_imagesize() {
  printf '%s\n' 'imagesize=1000' > "$IMAGE.info"
  assertTrue 'image_size_matches "$IMAGE"'
}

test_image_size_matches_rejects_an_image_of_another_size() {
  # aborted creation: the info file of the former version is left
  printf '%s\n' 'imagesize="2000"' > "$IMAGE.info"
  assertFalse 'image_size_matches "$IMAGE"'
}

test_image_size_matches_rejects_a_missing_info_file() {
  # aborted creation under a new name: no info file yet
  assertFalse 'image_size_matches "$IMAGE"'
}

test_image_size_matches_rejects_an_info_file_without_imagesize() {
  printf '%s\n' 'image="noble.qcow2"' > "$IMAGE.info"
  assertFalse 'image_size_matches "$IMAGE"'
}

. "$(dirname "$0")/shunit2"
