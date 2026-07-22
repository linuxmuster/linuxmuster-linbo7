#!/bin/sh
#
# run.sh
# thomas@linuxmuster.net
# 20260722
#
# Runs all tests/shell/test_*.sh files under whichever shell this script
# itself is invoked with - that's how the shell to test against is chosen:
#   sh tests/shell/run.sh
#   busybox ash tests/shell/run.sh
#
# Each test file runs in its own subshell (same interpreter as this
# script), so test files stay isolated from each other while still running
# under the intended shell.

TESTDIR="$(cd "$(dirname "$0")" && pwd)"
fail=0

for test in "$TESTDIR"/test_*.sh; do
  echo "=== $(basename "$test") ==="
  # SHUNIT_PARENT tells shunit2 which file to introspect for test_*
  # functions - since we source the test file rather than executing it as
  # its own process, $0 would otherwise still point at this runner.
  ( SHUNIT_PARENT="$test"; . "$test" )
  rc=$?
  [ "$rc" -eq 0 ] || fail=1
done

exit "$fail"
