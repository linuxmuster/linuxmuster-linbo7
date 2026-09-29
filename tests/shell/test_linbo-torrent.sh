#!/bin/sh
#
# test_linbo-torrent.sh
# tom.lehmann@netzint.de
# 20260929
#
# update_permissions: machine account files (*.macct) anywhere below the
# images dir end up root:root 600 and are never handed to nobody on the way,
# everything else keeps going to nobody:nogroup (opentracker dir to its
# user) except the image sync's staging dir images/.incoming, symlinks are
# not followed, and no errors without any *.macct.
#
# linbo-torrent is a bash script on the server, so the function runs under
# bash here, whichever shell runs the tests. chown is replaced by a stub on
# PATH that logs "owner path" per file instead of changing anything, since
# the tests don't run as root (busybox ash would ignore the stub and run its
# own chown applet). chmod is the real one.

SCRIPT="$(dirname "$0")/../../src/serverfs/usr/sbin/linbo-torrent"

oneTimeSetUp() {
  . "$(dirname "$0")/lib/extract_function.sh"
  extract_function "$SCRIPT" update_permissions > "$SHUNIT_TMPDIR/linbo_torrent_update_permissions.sh"
  mkdir -p "$SHUNIT_TMPDIR/bin"
  cat > "$SHUNIT_TMPDIR/bin/chown" <<'EOF'
#!/bin/sh
# chown stub: logs "owner path" for every file chown would change. -R logs
# the whole tree without following symlinks; a symlink given without -h
# logs its target, as chown would change that one.
recursive=""
nodereference=""
for arg; do
  case "$arg" in
    -R) recursive=1 ;;
    -h) nodereference=1 ;;
  esac
done
owner=""
rc=0
for arg; do
  case "$arg" in -*) continue ;; esac
  if [ -z "$owner" ]; then
    owner="$arg"
  elif [ ! -e "$arg" ] && [ ! -L "$arg" ]; then
    echo "chown: cannot access '$arg': No such file or directory" >&2
    rc=1
  elif [ -n "$recursive" ]; then
    find "$arg" | sed "s|^|$owner |" >> "$CHOWN_LOG"
  elif [ -L "$arg" ] && [ -z "$nodereference" ]; then
    echo "$owner $(readlink -f "$arg")" >> "$CHOWN_LOG"
  else
    echo "$owner $arg" >> "$CHOWN_LOG"
  fi
done
exit "$rc"
EOF
  chmod 755 "$SHUNIT_TMPDIR/bin/chown"
}

setUp() {
  images="$SHUNIT_TMPDIR/images"
  outside="$SHUNIT_TMPDIR/outside"
  CHOWN_LOG="$SHUNIT_TMPDIR/chown.log"
  STDERR_LOG="$SHUNIT_TMPDIR/stderr.log"
  rm -rf "$images" "$outside" "$CHOWN_LOG" "$STDERR_LOG"
  mkdir -p "$images/win10/backups/202609011200" "$images/tmp" \
    "$images/.incoming/win11" "$images/opentracker" "$outside"
  for f in win10/win10.qcow2 win10/win10.qcow2.info win10/win10.qcow2.macct \
    win10/backups/202609011200/win10.qcow2 \
    win10/backups/202609011200/win10.qcow2.macct \
    tmp/win10.qcow2.macct \
    .incoming/win11/win11.qcow2 .incoming/win11/win11.qcow2.macct \
    opentracker/torrent.whitelist; do
    echo "$f" > "$images/$f"
    chmod 644 "$images/$f"
  done
  echo secret > "$outside/secret"
  chmod 644 "$outside/secret"
}

run_update_permissions() {
  CHOWN_LOG="$CHOWN_LOG" PATH="$SHUNIT_TMPDIR/bin:$PATH" \
    LINBOIMGDIR="$images" OTRDIR="$images/opentracker" OTRUSER="_opentracker" \
    bash -c '. "$1" && update_permissions' sh \
    "$SHUNIT_TMPDIR/linbo_torrent_update_permissions.sh" 2> "$STDERR_LOG"
}

# owner a file got last
owner_of() {
  awk -v f="$1" '$2 == f { owner = $1 } END { print owner }' "$CHOWN_LOG"
}

macct_files() {
  echo "$images/win10/win10.qcow2.macct"
  echo "$images/win10/backups/202609011200/win10.qcow2.macct"
  echo "$images/tmp/win10.qcow2.macct"
  echo "$images/.incoming/win11/win11.qcow2.macct"
}

test_macct_files_end_up_root_600_at_any_depth() {
  run_update_permissions
  for f in $(macct_files); do
    assertEquals "owner of $f" "root:root" "$(owner_of "$f")"
    assertEquals "mode of $f" "600" "$(stat -c %a "$f")"
  done
}

test_macct_files_are_never_given_to_nobody() {
  run_update_permissions
  for f in $(macct_files); do
    assertFalse "$f given to nobody" "grep -qxF 'nobody:nogroup $f' '$CHOWN_LOG'"
  done
}

test_other_files_go_to_nobody_unchanged_mode() {
  run_update_permissions
  for f in "$images" "$images/win10" "$images/win10/win10.qcow2" \
    "$images/win10/win10.qcow2.info" "$images/win10/backups" \
    "$images/win10/backups/202609011200" \
    "$images/win10/backups/202609011200/win10.qcow2" "$images/tmp"; do
    assertEquals "owner of $f" "nobody:nogroup" "$(owner_of "$f")"
  done
  assertEquals "644" "$(stat -c %a "$images/win10/win10.qcow2")"
}

test_incoming_is_left_to_the_image_sync() {
  run_update_permissions
  assertFalse ".incoming given to nobody" \
    "grep -qF 'nobody:nogroup $images/.incoming' '$CHOWN_LOG'"
  assertEquals "root:root" \
    "$(owner_of "$images/.incoming/win11/win11.qcow2.macct")"
}

test_opentracker_dir_goes_to_opentracker_user() {
  run_update_permissions
  assertEquals "_opentracker:_opentracker" "$(owner_of "$images/opentracker")"
  assertEquals "_opentracker:_opentracker" \
    "$(owner_of "$images/opentracker/torrent.whitelist")"
}

test_no_errors_without_macct_files() {
  for f in $(macct_files); do
    rm -f "$f"
  done
  run_update_permissions
  assertEquals 0 $?
  assertEquals "" "$(cat "$STDERR_LOG")"
}

test_symlinks_are_not_followed() {
  ln -s "$outside/secret" "$images/win10/link.qcow2.macct"
  ln -s "$outside/secret" "$images/win10/link.qcow2"
  run_update_permissions
  assertFalse "symlink target chowned" "grep -qF '$outside' '$CHOWN_LOG'"
  assertEquals "644" "$(stat -c %a "$outside/secret")"
}

. "$(dirname "$0")/shunit2"
