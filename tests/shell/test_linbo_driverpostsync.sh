#!/bin/sh
#
# test_linbo_driverpostsync.sh
# ahmed.alani@netzint.de
# 20260722
#
# Wave 1 tests: argument validation without filesystem, device or network
# access.

SCRIPT="$(dirname "$0")/../../src/linbofs/usr/bin/linbo_driverpostsync"

oneTimeSetUp() {
  . "$(dirname "$0")/lib/extract_function.sh"
  extract_function "$SCRIPT" valid_image_name valid_profile_name \
    > "$SHUNIT_TMPDIR/linbo_driverpostsync_validation.sh"
  . "$SHUNIT_TMPDIR/linbo_driverpostsync_validation.sh"
}

repeat_char() {
  awk -v count="$1" 'BEGIN { for (i = 0; i < count; i++) printf "a" }'
}

test_valid_image_name_accepts_supported_names() {
  valid_image_name "win11"
  assertEquals 0 $?
  valid_image_name "win11_2026-test"
  assertEquals 0 $?
  valid_image_name "$(repeat_char 100)"
  assertEquals 0 $?
}

test_valid_image_name_rejects_unsafe_or_oversized_names() {
  for value in "" "../win11" "win11.qcow2" "win 11" "win*" "$(repeat_char 101)"; do
    valid_image_name "$value"
    assertNotEquals "image '$value' should be rejected: " 0 $?
  done
}

test_valid_profile_name_accepts_supported_names() {
  for value in "Lenovo-21L4" "intel.graphics" "com10" "$(repeat_char 100)"; do
    valid_profile_name "$value"
    assertEquals "profile '$value' should be accepted: " 0 $?
  done
}

test_valid_profile_name_rejects_unsafe_names() {
  for value in "" ".hidden" "-profile" "_profile" "../profile" "profile/child" "profile name" "profile?" "profile." "$(repeat_char 101)"; do
    valid_profile_name "$value"
    assertNotEquals "profile '$value' should be rejected: " 0 $?
  done
}

test_valid_profile_name_rejects_windows_reserved_names() {
  for value in "aux" "CON" "nul.inf" "PrN" "com1" "COM9.driver" "lpt1" "LPT9.inf" "pnputil-install.cmd" "PnPUtil-Install.CMD"; do
    valid_profile_name "$value"
    assertNotEquals "reserved profile '$value' should be rejected: " 0 $?
  done
}

. "$(dirname "$0")/shunit2"
