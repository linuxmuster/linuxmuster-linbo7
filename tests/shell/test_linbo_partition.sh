#!/bin/sh
#
# test_linbo_partition.sh
# thomas@linuxmuster.net
# 20260722
#
# Wave 1 pilot test: convert_size() from linbo_partition.
# Pure string/arithmetic conversion, no filesystem/device/network access.

SCRIPT="$(dirname "$0")/../../src/linbofs/usr/bin/linbo_partition"

oneTimeSetUp() {
  . "$(dirname "$0")/lib/extract_function.sh"
  extract_function "$SCRIPT" convert_size > "$SHUNIT_TMPDIR/convert_size.sh"
  . "$SHUNIT_TMPDIR/convert_size.sh"
}

test_convert_size_megabyte_passthrough() {
  assertEquals "512" "$(convert_size 512M)"
}

test_convert_size_gigabyte_to_mib() {
  assertEquals "10240" "$(convert_size 10G)"
}

test_convert_size_terabyte_to_mib() {
  assertEquals "1048576" "$(convert_size 1T)"
}

test_convert_size_kilobyte_rounds_down_to_even() {
  # 5000 KiB / 2048 = 2 (integer division), * 2 = 4
  assertEquals "4" "$(convert_size 5000K)"
}

test_convert_size_unit_is_case_insensitive() {
  assertEquals "10240" "$(convert_size 10g)"
}

test_convert_size_rejects_unknown_unit() {
  convert_size 10X
  assertEquals 1 $?
}

. "$(dirname "$0")/shunit2"
