#!/bin/sh
#
# Filename     : test_linbo_wrapper.sh
# Description  : tests for run_cmd(), get_passwd() and image_name_file() of linbo_wrapper
# Signed-off by: thomas@linuxmuster.net
# Assisted by  : Claude
# Date         : 20261023
#
# Wave 1: run_cmd(), get_passwd() and image_name_file() (#133, pure string
# check) from linbo_wrapper.
# run_cmd() (added for --dry-run, issue #170) has no filesystem/device
# access of its own - it either runs its argument as a real command or
# just echoes it, so it's tested against stub commands, the same idiom
# shell_functions' interruptible() test already uses. get_passwd() reads
# $SECRETS, but that's a plain variable (not a hardcoded path), so it's
# testable against a $SHUNIT_TMPDIR fixture file.

SCRIPT="$(dirname "$0")/../../src/linbofs/usr/bin/linbo_wrapper"

oneTimeSetUp() {
  . "$(dirname "$0")/lib/extract_function.sh"
  extract_function "$SCRIPT" run_cmd get_passwd image_name_file > "$SHUNIT_TMPDIR/linbo_wrapper_functions.sh"
  . "$SHUNIT_TMPDIR/linbo_wrapper_functions.sh"
}

# --- run_cmd() ---------------------------------------------------------

test_run_cmd_runs_the_real_command_when_not_dry_run() {
  unset DRYRUN
  output="$(run_cmd echo hello)"
  assertEquals "hello" "$output"
}

test_run_cmd_propagates_real_exit_status_when_not_dry_run() {
  unset DRYRUN
  run_cmd true
  assertEquals 0 $?
  run_cmd false
  assertEquals 1 $?
}

test_run_cmd_does_not_run_the_command_when_dry_run() {
  DRYRUN="yes"
  marker="$SHUNIT_TMPDIR/run_cmd_marker"
  rm -f "$marker"
  run_cmd touch "$marker" > /dev/null
  assertFalse '[ -e "$marker" ]'
}

test_run_cmd_echoes_would_run_with_full_argument_list_when_dry_run() {
  DRYRUN="yes"
  output="$(run_cmd linbo_sync 1 force)"
  assertEquals "[dry-run] would run: linbo_sync 1 force" "$output"
}

test_run_cmd_always_succeeds_when_dry_run_even_for_a_failing_command() {
  # callers do "run_cmd linbo_xxx || exit 1" - a dry-run command must never
  # look like a failure just because the real command it stands in for
  # would have failed
  DRYRUN="yes"
  run_cmd false > /dev/null
  assertEquals 0 $?
}

# --- get_passwd() --------------------------------------------------------

test_get_passwd_extracts_password_from_secrets_file() {
  SECRETS="$SHUNIT_TMPDIR/rsyncd.secrets"
  echo "linbo:testpass123" > "$SECRETS"
  get_passwd
  assertEquals 0 $?
  assertEquals "testpass123" "$password"
  assertEquals "linbo" "$user"
}

test_get_passwd_fails_on_missing_secrets_file() {
  SECRETS="$SHUNIT_TMPDIR/no_such_secrets_file"
  rm -f "$SECRETS"
  get_passwd
  assertEquals 1 $?
}

test_get_passwd_fails_on_empty_secrets_file() {
  SECRETS="$SHUNIT_TMPDIR/empty.secrets"
  : > "$SECRETS"
  get_passwd
  assertEquals 1 $?
}

test_get_passwd_ignores_unrelated_lines() {
  SECRETS="$SHUNIT_TMPDIR/multi.secrets"
  cat > "$SECRETS" <<EOF
someoneelse:notthis
linbo:therealpassword
EOF
  get_passwd
  assertEquals "therealpassword" "$password"
}

# --- image_name_file() (#133) --------------------------------------------

test_image_name_file_appends_qcow2_to_a_valid_name() {
  assertEquals "noble.qcow2" "$(image_name_file noble)"
  assertEquals "Noble_24-04.qcow2" "$(image_name_file Noble_24-04)"
}

test_image_name_file_rejects_invalid_names() {
  assertFalse 'image_name_file ""'
  assertFalse 'image_name_file no.ble'
  assertFalse 'image_name_file noble.qcow2'
  assertFalse 'image_name_file ../noble'
  assertFalse 'image_name_file "no ble"'
}

. "$(dirname "$0")/shunit2"
