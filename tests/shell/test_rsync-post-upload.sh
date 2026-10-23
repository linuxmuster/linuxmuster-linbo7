#!/bin/sh
#
# Filename     : test_rsync-post-upload.sh
# Description  : tests for the supplemental file takeover of rsync-post-upload.sh (issue #133)
# Signed-off by: thomas@linuxmuster.net
# Assisted by  : Claude
# Date         : 20261023
#
# copy_source_supplements() works on a fixture image dir below
# $SHUNIT_TMPDIR. The function is plain POSIX, so it is tested under dash
# and busybox ash although the hook itself runs under bash.

SCRIPT="$(dirname "$0")/../../src/serverfs/usr/share/linuxmuster/linbo/rsync-post-upload.sh"

oneTimeSetUp() {
  . "$(dirname "$0")/lib/extract_function.sh"
  extract_function "$SCRIPT" copy_source_supplements \
    > "$SHUNIT_TMPDIR/rsync-post-upload_functions.sh"
  . "$SHUNIT_TMPDIR/rsync-post-upload_functions.sh"
}

setUp() {
  IMGDIR="$SHUNIT_TMPDIR/images"
  rm -rf "$IMGDIR"
  # native image debian with all supplemental files
  mkdir -p "$IMGDIR/debian" "$IMGDIR/noble"
  echo "reg of debian" > "$IMGDIR/debian/debian.reg"
  echo "rsync linbo::images/debian/debian.postsync" > "$IMGDIR/debian/debian.postsync"
  echo "prestart" > "$IMGDIR/debian/debian.prestart"
  INFO="$IMGDIR/noble/noble.qcow2.info"
}

# writes the info file of noble with the given sourceimage line
mkinfo() {
  printf '%s\n' '["noble.qcow2" Info File]' 'image="noble.qcow2"' "$@" > "$INFO"
}

test_copy_source_supplements_takes_over_all_files_of_the_source() {
  mkinfo 'sourceimage="debian.qcow2"'
  copy_source_supplements "$IMGDIR" noble "$INFO" > /dev/null
  assertEquals "reg of debian" "$(cat "$IMGDIR/noble/noble.reg")"
  assertTrue '[ -s "$IMGDIR/noble/noble.postsync" ]'
  assertEquals "prestart" "$(cat "$IMGDIR/noble/noble.prestart")"
}

test_copy_source_supplements_never_overwrites_existing_files() {
  mkinfo 'sourceimage="debian.qcow2"'
  echo "own reg" > "$IMGDIR/noble/noble.reg"
  copy_source_supplements "$IMGDIR" noble "$INFO" > /dev/null
  assertEquals "own reg" "$(cat "$IMGDIR/noble/noble.reg")"
  assertEquals "prestart" "$(cat "$IMGDIR/noble/noble.prestart")"
}

test_copy_source_supplements_skips_missing_source_files() {
  mkinfo 'sourceimage="debian.qcow2"'
  rm -f "$IMGDIR/debian/debian.prestart"
  copy_source_supplements "$IMGDIR" noble "$INFO" > /dev/null
  assertFalse '[ -e "$IMGDIR/noble/noble.prestart" ]'
  assertTrue '[ -e "$IMGDIR/noble/noble.reg" ]'
}

test_copy_source_supplements_notes_a_file_mentioning_the_source() {
  mkinfo 'sourceimage="debian.qcow2"'
  output="$(copy_source_supplements "$IMGDIR" noble "$INFO")"
  assertContains "$output" "noble.postsync mentions debian"
}

test_copy_source_supplements_does_nothing_without_sourceimage() {
  mkinfo
  copy_source_supplements "$IMGDIR" noble "$INFO" > /dev/null
  assertEquals "" "$(ls "$IMGDIR/noble" | grep -v info)"
}

test_copy_source_supplements_does_nothing_for_a_missing_info_file() {
  copy_source_supplements "$IMGDIR" noble "$IMGDIR/noble/none.info" > /dev/null
  assertEquals 0 $?
  assertEquals "" "$(ls "$IMGDIR/noble")"
}

test_copy_source_supplements_ignores_differential_or_own_sources() {
  mkinfo 'sourceimage="debian.qdiff"'
  copy_source_supplements "$IMGDIR" noble "$INFO" > /dev/null
  mkinfo 'sourceimage="noble.qcow2"'
  copy_source_supplements "$IMGDIR" noble "$INFO" > /dev/null
  assertEquals "" "$(ls "$IMGDIR/noble" | grep -v info)"
}

test_copy_source_supplements_ignores_path_components_in_the_source() {
  mkdir -p "$IMGDIR/debian/x"
  echo "reg" > "$IMGDIR/debian/x/x.reg"
  mkinfo 'sourceimage="debian/x.qcow2"'
  copy_source_supplements "$IMGDIR" noble "$INFO" > /dev/null
  mkinfo 'sourceimage="..qcow2"'
  copy_source_supplements "$IMGDIR" noble "$INFO" > /dev/null
  assertEquals "" "$(ls "$IMGDIR/noble" | grep -v info)"
}

. "$(dirname "$0")/shunit2"
