#!/bin/sh
#
# test_linbo_sync.sh
# tom.lehmann@netzint.de
# 20260928
#
# group_bootfile: fallback from the school qualified to the plain hardware
# group for windows boot files stored in existing images (#178).

SCRIPT="$(dirname "$0")/../../src/linbofs/usr/bin/linbo_sync"

oneTimeSetUp() {
  . "$(dirname "$0")/lib/extract_function.sh"
  extract_function "$SCRIPT" group_bootfile > "$SHUNIT_TMPDIR/linbo_sync_group_bootfile.sh"
  . "$SHUNIT_TMPDIR/linbo_sync_group_bootfile.sh"
}

setUp() {
  bootdir="$SHUNIT_TMPDIR/boot"
  rm -rf "$bootdir"
  mkdir -p "$bootdir"
}

test_default_school_group_is_unchanged() {
  HOSTGROUP="raum101"
  assertEquals "$bootdir/BCD.raum101" "$(group_bootfile "$bootdir"/BCD)"
  touch "$bootdir/BCD.raum101"
  assertEquals "$bootdir/BCD.raum101" "$(group_bootfile "$bootdir"/BCD)"
}

test_qualified_file_is_preferred() {
  HOSTGROUP="abc+raum101"
  touch "$bootdir/bsmbr.abc+raum101" "$bootdir/bsmbr.raum101"
  assertEquals "$bootdir/bsmbr.abc+raum101" "$(group_bootfile "$bootdir"/bsmbr)"
}

test_falls_back_to_plain_group() {
  HOSTGROUP="abc+raum101"
  touch "$bootdir/gptlabel.raum101"
  assertEquals "$bootdir/gptlabel.raum101" "$(group_bootfile "$bootdir"/gptlabel)"
}

test_suffix_is_kept_on_fallback() {
  HOSTGROUP="abc+raum101"
  touch "$bootdir/BCD.raum101.nvme0n1p3"
  assertEquals "$bootdir/BCD.raum101.nvme0n1p3" "$(group_bootfile "$bootdir"/BCD .nvme0n1p3)"
}

test_neither_exists_gives_qualified_name() {
  HOSTGROUP="abc+raum101"
  assertEquals "$bootdir/BCD.abc+raum101" "$(group_bootfile "$bootdir"/BCD)"
}

test_plain_group_with_hyphen() {
  HOSTGROUP="gs-nord+raum-1_a"
  touch "$bootdir/BCD.raum-1_a"
  assertEquals "$bootdir/BCD.raum-1_a" "$(group_bootfile "$bootdir"/BCD)"
}

. "$(dirname "$0")/shunit2"
