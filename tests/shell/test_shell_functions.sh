#!/bin/sh
#
# Filename     : test_shell_functions.sh
# Description  : Wave 1 tests for shell_functions
# Signed-off by: thomas@linuxmuster.net
# Assisted by  : Claude
# Date         : 20260817
#
# Wave 1 tests: pure string/validation helpers from the shared
# shell_functions library sourced by nearly every linbofs script.
# No filesystem/device/network access, except where noted (getinfo,
# get_filesize, cleanlog operate on an explicit file argument - a fixture
# under $SHUNIT_TMPDIR, never a hardcoded real path).

SCRIPT="$(dirname "$0")/../../src/linbofs/usr/share/linbo/shell_functions"

oneTimeSetUp() {
  . "$(dirname "$0")/lib/extract_function.sh"
  extract_function "$SCRIPT" isinteger stringinstring remote_cache validip validhostname \
    tolower isalnum iseven printargs warmstart localmode get_disk_from_partition \
    getinfo get_filesize cleanlog \
    > "$SHUNIT_TMPDIR/shell_functions.sh"
  . "$SHUNIT_TMPDIR/shell_functions.sh"
}

# warmstart()/localmode() branch on these env vars - reset before every
# test so one test's setting can't leak into the next (shunit2 runs all
# test_* functions in the same shell process, not a fresh one per test).
setUp() {
  unset WARMSTART NOWARMSTART LOCALMODE LINBOSERVER
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

test_tolower_converts_uppercase() {
  assertEquals "foo-bar" "$(tolower FOO-Bar)"
  assertEquals "already" "$(tolower already)"
}

test_isalnum_accepts_letters_and_digits() {
  for value in "abc123" "ABC" "007"; do
    isalnum "$value"
    assertEquals "\"$value\" should be accepted: " 0 $?
  done
}

test_isalnum_rejects_non_alnum_or_empty() {
  # confirmed live under real dash: the original "[[ =~ ]]" implementation
  # made this always return 1 for *every* input, including valid ones -
  # same class of bug as validip()/validhostname() above
  for value in "" "ab-12" "abc 123" "foo_bar"; do
    isalnum "$value"
    assertNotEquals "\"$value\" should be rejected: " 0 $?
  done
}

test_iseven_accepts_even_numbers() {
  for value in 0 4 100; do
    iseven "$value"
    assertEquals "$value should be even: " 0 $?
  done
}

test_iseven_rejects_odd_or_non_integer() {
  # confirmed live under real dash: the original "[ ... == ... ]"
  # implementation made this always return 1, including for even numbers
  for value in 1 5 abc ""; do
    iseven "$value"
    assertNotEquals "$value should be rejected: " 0 $?
  done
}

test_printargs_numbers_and_quotes_each_argument() {
  # confirmed live under real dash: the original "$((count++))" postfix
  # increment crashed outright ("expecting primary: count++") - dash's
  # arithmetic expansion doesn't support ++/--
  assertEquals "1: »foo« 2: »bar« " "$(printargs foo bar)"
}

test_warmstart_is_on_by_default() {
  warmstart
  assertEquals 0 $?
}

test_warmstart_off_when_warmstart_is_no() {
  WARMSTART="no"
  warmstart
  assertNotEquals 0 $?
}

test_warmstart_off_when_nowarmstart_is_set() {
  NOWARMSTART="1"
  warmstart
  assertNotEquals 0 $?
}

test_localmode_is_on_by_default() {
  # no LOCALMODE, no LINBOSERVER configured -> nothing to sync against
  localmode
  assertEquals 0 $?
}

test_localmode_on_when_localmode_flag_set() {
  LOCALMODE="1"
  LINBOSERVER="server"
  localmode
  assertEquals "LOCALMODE overrides a configured LINBOSERVER: " 0 $?
}

test_localmode_off_when_server_configured() {
  LINBOSERVER="server"
  localmode
  assertNotEquals 0 $?
}

test_get_disk_from_partition_strips_trailing_p_partition_number() {
  # nvme/mmcblk-style names: diskNpM
  assertEquals "/dev/nvme0n1" "$(get_disk_from_partition /dev/nvme0n1p1)"
  assertEquals "/dev/mmcblk0" "$(get_disk_from_partition /dev/mmcblk0p2)"
}

test_get_disk_from_partition_strips_trailing_number() {
  # sd?/hd?/vd?-style names: diskN
  assertEquals "/dev/sda" "$(get_disk_from_partition /dev/sda1)"
  assertEquals "/dev/vdb" "$(get_disk_from_partition /dev/vdb3)"
}

test_get_disk_from_partition_passes_through_unmatched_input() {
  get_disk_from_partition /dev/disk/by-id/foo > /dev/null
  assertNotEquals 0 $?
  assertEquals "/dev/disk/by-id/foo" "$(get_disk_from_partition /dev/disk/by-id/foo)"
}

test_getinfo_returns_value_for_matching_key() {
  printf 'foo=bar\nbaz=qux\n' > "$SHUNIT_TMPDIR/info.txt"
  assertEquals "bar" "$(getinfo "$SHUNIT_TMPDIR/info.txt" foo)"
  assertEquals "qux" "$(getinfo "$SHUNIT_TMPDIR/info.txt" baz)"
}

test_getinfo_rejects_missing_key_or_file() {
  printf 'foo=bar\n' > "$SHUNIT_TMPDIR/info.txt"
  getinfo "$SHUNIT_TMPDIR/info.txt" missing
  assertNotEquals 0 $?
  getinfo "$SHUNIT_TMPDIR/does-not-exist" foo
  assertNotEquals 0 $?
}

test_get_filesize_reports_byte_count() {
  printf '12345' > "$SHUNIT_TMPDIR/size.txt"
  assertEquals "5" "$(get_filesize "$SHUNIT_TMPDIR/size.txt")"
}

test_cleanlog_strips_prefix_collapses_spaces_and_dedupes() {
  printf '[StdOut] hello  world\nfoo\nfoo\nbar\n' > "$SHUNIT_TMPDIR/log.txt"
  cleanlog "$SHUNIT_TMPDIR/log.txt"
  assertEquals "hello world
foo
bar" "$(cat "$SHUNIT_TMPDIR/log.txt")"
}

. "$(dirname "$0")/shunit2"
