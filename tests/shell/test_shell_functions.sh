#!/bin/sh
#
# test_shell_functions.sh
# thomas@linuxmuster.net
# 20260801
#
# Wave 1 tests: pure string/validation helpers from the shared
# shell_functions library sourced by nearly every linbofs script.
# No filesystem/device/network access.

SCRIPT="$(dirname "$0")/../../src/linbofs/usr/share/linbo/shell_functions"

oneTimeSetUp() {
  . "$(dirname "$0")/lib/extract_function.sh"
  extract_function "$SCRIPT" isinteger stringinstring remote_cache validip validhostname \
    > "$SHUNIT_TMPDIR/shell_functions.sh"
  . "$SHUNIT_TMPDIR/shell_functions.sh"
}

test_isinteger_accepts_digits_only() {
  isinteger 123
  assertEquals 0 $?
  isinteger 0
  assertEquals 0 $?
  isinteger 007
  assertEquals 0 $?
}

test_isinteger_rejects_non_digit_or_empty() {
  for value in "" "12a" "-5" " 5"; do
    isinteger "$value"
    assertNotEquals "\"$value\" should be rejected: " 0 $?
  done
}

test_isinteger_rejects_wrong_arg_count() {
  isinteger 1 2
  assertNotEquals 0 $?
  isinteger
  assertNotEquals 0 $?
}

test_stringinstring_finds_substring() {
  stringinstring "abc" "xxabcyy"
  assertEquals 0 $?
  stringinstring "cache" "/srv/linbo/cache"
  assertEquals 0 $?
}

test_stringinstring_rejects_missing_substring() {
  stringinstring "abc" "xyz"
  assertNotEquals 0 $?
}

test_stringinstring_empty_needle_always_matches() {
  # "*$1*" with an empty $1 becomes "**", which matches anything - this
  # documents that behavior rather than endorsing it
  stringinstring "" "anything"
  assertEquals 0 $?
}

test_remote_cache_detects_network_paths() {
  for value in "server::linbo/cache" "//server/share" '\\server\share' "server:/export/cache"; do
    remote_cache "$value"
    assertEquals "\"$value\" should be detected as remote: " 0 $?
  done
}

test_remote_cache_rejects_local_path() {
  remote_cache "/srv/linbo/cache"
  assertNotEquals 0 $?
}

test_validip_accepts_valid_addresses() {
  for value in "192.168.1.1" "1.2.3.4" "10.0.0.254"; do
    validip "$value"
    assertEquals "\"$value\" should be accepted: " 0 $?
  done
}

test_validip_rejects_invalid_addresses() {
  # 0.0.0.0 and any x.x.x.255 broadcast address are rejected by design
  # (last octet range is 1-254), not just malformed input
  for value in "" "not-an-ip" "999.1.1.1" "10.0.0.256" "0.0.0.0" "255.255.255.255"; do
    validip "$value"
    assertNotEquals "\"$value\" should be rejected: " 0 $?
  done
}

test_validhostname_accepts_valid_names() {
  for value in "server" "server-01"; do
    validhostname "$value"
    assertEquals "\"$value\" should be accepted: " 0 $?
  done
}

test_validhostname_rejects_invalid_names() {
  for value in "" "server.example.com" "server_01" "server 01"; do
    validhostname "$value"
    assertNotEquals "\"$value\" should be rejected: " 0 $?
  done
}

. "$(dirname "$0")/shunit2"
