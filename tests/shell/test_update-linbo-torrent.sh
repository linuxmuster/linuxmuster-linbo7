#!/bin/sh
#
# Filename     : test_update-linbo-torrent.sh
# Description  : tests for update-linbo-torrent (#152)
# Signed-off by: thomas@linuxmuster.net
# Assisted by  : Claude
# Date         : 20261018
#
# An outdated /etc/default/linbo-torrent (old header format and no
# --bt-enable-lpd) is backed up, replaced by the template and linbo-torrent
# is restarted. Anything else is left alone and not restarted, and a second
# run does nothing.
#
# update-linbo-torrent is a bash script on the server, so the functions run
# under bash here, whichever shell runs the tests. systemctl is replaced by
# a stub on PATH that only logs its arguments.

SCRIPT="$(dirname "$0")/../../src/serverfs/usr/share/linuxmuster/linbo/update-linbo-torrent"
TEMPLATE="$(dirname "$0")/../../src/serverfs/usr/share/linuxmuster/templates/linbo-torrent"

oneTimeSetUp() {
  . "$(dirname "$0")/lib/extract_function.sh"
  extract_function "$SCRIPT" is_outdated update_linbo_torrent \
    > "$SHUNIT_TMPDIR/update_linbo_torrent.sh"
  mkdir -p "$SHUNIT_TMPDIR/bin"
  cat > "$SHUNIT_TMPDIR/bin/systemctl" <<'EOF'
#!/bin/sh
echo "$*" >> "$SYSTEMCTL_LOG"
EOF
  chmod 755 "$SHUNIT_TMPDIR/bin/systemctl"
}

setUp() {
  dir="$SHUNIT_TMPDIR/default"
  conf="$dir/linbo-torrent"
  SYSTEMCTL_LOG="$SHUNIT_TMPDIR/systemctl.log"
  rm -rf "$dir" "$SYSTEMCTL_LOG"
  mkdir -p "$dir"
  touch "$SYSTEMCTL_LOG"
}

# default file of 7.4 releases before the new header format
write_old_default() {
  cat > "$conf" <<'EOF'
# /etc/default/linbo-torrent
#
# aria2c options, only change that if you know exactly what you're doing.
#
# thomas@linuxmuster.net
# 20260625
#

# used for both purposes
ARIA2C_GLOBAL_OPTS="--enable-color=false --enable-dht=false --disable-ipv6=true"

# used for torrent downloads
ARIA2C_DWNLD_OPTS="-c --console-log-level=notice --show-console-readout=true --summary-interval=3 --seed-time=0"

# used to seed torrents
ARIA2C_SEED_OPTS="-V --seed-ratio=0.0"
EOF
}

run_update() {
  SYSTEMCTL_LOG="$SYSTEMCTL_LOG" PATH="$SHUNIT_TMPDIR/bin:$PATH" \
    bash -c '. "$1" && update_linbo_torrent "$2" "$3"' sh \
    "$SHUNIT_TMPDIR/update_linbo_torrent.sh" "$conf" "$TEMPLATE" > /dev/null
}

backups() {
  find "$dir" -name 'linbo-torrent.*' | wc -l
}

test_old_default_is_replaced_backed_up_and_restarted() {
  write_old_default
  cp "$conf" "$SHUNIT_TMPDIR/expected_backup"
  run_update
  assertEquals "rc" 0 "$?"
  assertTrue "conf is the template" "cmp -s '$conf' '$TEMPLATE'"
  assertEquals "number of backups" 1 "$(backups)"
  assertTrue "backup holds the old file" \
    "cmp -s '$(find "$dir" -name 'linbo-torrent.*')' '$SHUNIT_TMPDIR/expected_backup'"
  assertEquals "systemctl calls" "restart linbo-torrent.service" "$(cat "$SYSTEMCTL_LOG")"
}

test_second_run_does_nothing() {
  write_old_default
  run_update
  run_update
  assertEquals "number of backups" 1 "$(backups)"
  assertEquals "number of restarts" 1 "$(wc -l < "$SYSTEMCTL_LOG")"
}

test_pre_aria2c_default_is_replaced() {
  printf 'SEEDHOURS="100000"\nMAXPEERS="100"\nPIECELEN="524288"\n' > "$conf"
  run_update
  assertTrue "conf is the template" "cmp -s '$conf' '$TEMPLATE'"
  assertEquals "number of backups" 1 "$(backups)"
}

test_old_header_with_lpd_is_left_alone() {
  write_old_default
  sed -i 's|--disable-ipv6=true"|--disable-ipv6=true --bt-enable-lpd=true"|' "$conf"
  cp "$conf" "$SHUNIT_TMPDIR/expected"
  run_update
  assertTrue "conf unchanged" "cmp -s '$conf' '$SHUNIT_TMPDIR/expected'"
  assertEquals "number of backups" 0 "$(backups)"
  assertEquals "systemctl calls" "" "$(cat "$SYSTEMCTL_LOG")"
}

test_new_header_without_lpd_is_left_alone() {
  sed 's| --bt-enable-lpd=true||' "$TEMPLATE" > "$conf"
  cp "$conf" "$SHUNIT_TMPDIR/expected"
  run_update
  assertTrue "conf unchanged" "cmp -s '$conf' '$SHUNIT_TMPDIR/expected'"
  assertEquals "number of backups" 0 "$(backups)"
  assertEquals "systemctl calls" "" "$(cat "$SYSTEMCTL_LOG")"
}

test_current_template_is_left_alone() {
  cp "$TEMPLATE" "$conf"
  run_update
  assertEquals "rc" 0 "$?"
  assertEquals "number of backups" 0 "$(backups)"
  assertEquals "systemctl calls" "" "$(cat "$SYSTEMCTL_LOG")"
}

test_missing_conf_does_nothing() {
  run_update
  assertEquals "rc" 0 "$?"
  assertFalse "conf not created" "[ -e '$conf' ]"
  assertEquals "systemctl calls" "" "$(cat "$SYSTEMCTL_LOG")"
}

. "$(dirname "$0")/shunit2"
