#!/bin/sh
#
# test_linbo_partition.sh
# thomas@linuxmuster.net
# 20260801
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

test_convert_size_megabyte_rounds_down_to_even() {
  # 513 / 2 = 256 (integer division), * 2 = 512
  assertEquals "512" "$(convert_size 513M)"
}

test_convert_size_small_kilobyte_rounds_to_zero() {
  # below the 2048 KiB (= 2 MiB) threshold, integer division floors to 0
  assertEquals "0" "$(convert_size 1K)"
  assertEquals "0" "$(convert_size 2047K)"
}

test_convert_size_accepts_multi_letter_unit_suffix() {
  # only the unit's first letter is significant, so "GB", "Gib" etc. all
  # behave like a plain "G"
  assertEquals "10240" "$(convert_size 10GB)"
}

test_convert_size_truncates_fractional_input() {
  # digit-extraction stops at the first non-digit character, so the
  # fractional part is silently dropped rather than rounded - this test
  # documents that behavior rather than endorsing it
  assertEquals "1024" "$(convert_size 1.5G)"
}

test_convert_size_rejects_missing_leading_digit() {
  # a unit with no leading digit (e.g. a malformed start.conf entry) must
  # fail cleanly instead of crashing the arithmetic expansion below it
  convert_size M
  assertEquals 1 $?
}

. "$(dirname "$0")/shunit2"
