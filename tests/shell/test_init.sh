#!/bin/sh
#
# Filename     : test_init.sh
# Description  : tests for run_with_status() and last_output_lines() of init.sh
# Signed-off by: thomas@linuxmuster.net
# Assisted by  : Claude
# Date         : 20261024
#
# run_with_status() in splash mode: print_status() is replaced by a stub
# recording its lines (the real one calls plymouth and uses ${var:0:1},
# which dash does not know). The console mode writes to /dev/console and
# is not tested here.

SCRIPT="$(dirname "$0")/../../src/linbofs/init.sh"

oneTimeSetUp() {
  . "$(dirname "$0")/lib/extract_function.sh"
  extract_function "$SCRIPT" run_with_status last_output_lines > "$SHUNIT_TMPDIR/init_functions.sh"
  . "$SHUNIT_TMPDIR/init_functions.sh"
}

setUp() {
  SPLASH="yes"
  RUN_STATUS_OUT="$SHUNIT_TMPDIR/run_with_status.out"
  rm -f "$RUN_STATUS_OUT"
  STATUS="$SHUNIT_TMPDIR/status"
  : > "$STATUS"
}

print_status() {
  echo "$1" >> "$STATUS"
}

test_run_with_status_shows_every_carriage_return_redraw() {
  run_with_status printf '(0.00/100%%)\r(50.00/100%%)\r(100.00/100%%)\r\nDone.\n'
  assertEquals "$(printf '%s\n' '(0.00/100%)' '(50.00/100%)' '(100.00/100%)' 'Done.')" "$(cat "$STATUS")"
}

test_run_with_status_shows_every_backspace_redraw() {
  # buildtorrent: draws the bar, then moves back with backspaces
  run_with_status printf 'hashing 2 pieces\n[=>  ]\b\b\b\b\b\b[===>]\b\b\b\b\b\b\n'
  assertEquals "$(printf '%s\n' 'hashing 2 pieces' '[=>  ]' '[===>]')" "$(cat "$STATUS")"
}

test_run_with_status_skips_blank_lines_and_trims_blanks() {
  run_with_status printf '\r   32.768   0%%  \r\n\n'
  assertEquals "32.768   0%" "$(cat "$STATUS")"
}

test_run_with_status_keeps_stderr_out_of_the_status() {
  run_with_status sh -c 'echo out; echo err >&2' 2> /dev/null
  assertEquals "out" "$(cat "$STATUS")"
}

test_run_with_status_ignores_a_comma_ifs_of_the_caller() {
  # the onboot loop in init.sh runs with IFS=","
  IFS=","
  run_with_status printf 'a, b\n'
  IFS="
"
  assertEquals "a, b" "$(cat "$STATUS")"
}

test_run_with_status_returns_the_exit_status_of_the_command() {
  run_with_status sh -c 'echo working; exit 3'
  assertEquals 3 $?
  run_with_status true
  assertEquals 0 $?
}

test_last_output_lines_reduces_progress_bars_to_their_last_state() {
  run_with_status printf 'Creating noble.qcow2\n(0.00/100%%)\r(42.00/100%%)\r\n[=> ]\b\b\b\b\b[==>]\b\b\b\b\b\nCreation of noble.qcow2 failed. :(\n'
  assertEquals "$(printf '%s\n' 'Creating noble.qcow2' '(42.00/100%)' '[==>]' 'Creation of noble.qcow2 failed. :(')" \
    "$(last_output_lines)"
}

test_last_output_lines_prints_the_last_n_lines() {
  run_with_status printf '1\n2\n3\n4\n'
  assertEquals "$(printf '%s\n' 3 4)" "$(last_output_lines 2)"
}

test_last_output_lines_prints_nothing_without_output() {
  assertEquals "" "$(last_output_lines)"
}

. "$(dirname "$0")/shunit2"
