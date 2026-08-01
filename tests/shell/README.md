# Shell test harness for linbofs scripts

Lightweight unit tests for individual functions inside `src/linbofs/usr/bin/`
scripts, using [shunit2](https://github.com/kward/shunit2) (vendored as a
single file in `shunit2`, no external dependency).

linbofs scripts run under busybox `ash` on real clients. This directory
provides the repository's general shell-test harness (see
`docs/proposal-shell-test-harness.de.md` for the full design rationale). Tests
run under both `dash` (`/bin/sh` in the `lmndev-runner` build container) and
`busybox ash`, since those are the two shells linbofs code actually has to
work under.

## Running the tests locally

```sh
sh tests/shell/run.sh            # against dash / whatever /bin/sh is
busybox ash tests/shell/run.sh   # against busybox ash
```

Or via the `lmndev-runner` container, which has both:

```sh
docker run --rm -v "$PWD:/workspace/build:ro" -w /workspace/build \
  ghcr.io/linuxmuster/lmndev-runner:latest sh tests/shell/run.sh
```

## How it works

Most `linbofs` scripts are single files mixing top-level statements (sourcing
`shell_functions`, reading environment variables, ...) with function
definitions. To unit-test one function without dragging in the rest of the
script (and its real filesystem/device dependencies), `lib/extract_function.sh`
cuts out just the named `name(){ ... }` block via `awk`, independent of
whether it sits inside a `#### functions begin/end ####` marker.

A test file (see `test_linbo_partition.sh` for the full pattern):

```sh
SCRIPT="$(dirname "$0")/../../src/linbofs/usr/bin/linbo_partition"

oneTimeSetUp() {
  . "$(dirname "$0")/lib/extract_function.sh"
  extract_function "$SCRIPT" convert_size > "$SHUNIT_TMPDIR/convert_size.sh"
  . "$SHUNIT_TMPDIR/convert_size.sh"
}

test_convert_size_megabyte_passthrough() {
  assertEquals "512" "$(convert_size 512M)"
}

. "$(dirname "$0")/shunit2"
```

`run.sh` sources each `test_*.sh` in its own subshell (so tests stay isolated
from each other) under whichever shell `run.sh` itself was invoked with. It
sets `SHUNIT_PARENT` to the test file's own path before sourcing it - shunit2
uses `$0` to find `test_*` functions to run, which would otherwise still point
at `run.sh` since sourcing doesn't change `$0`.

### Extracting more than one function

`extract_function` takes any number of function names and concatenates them,
in order, to stdout - useful when the functions under test call each other or
you just want them in one file:

```sh
oneTimeSetUp() {
  . "$(dirname "$0")/lib/extract_function.sh"
  extract_function "$SCRIPT" valid_image_name valid_profile_name \
    > "$SHUNIT_TMPDIR/functions.sh"
  . "$SHUNIT_TMPDIR/functions.sh"
}
```

### Gotcha: "works under ash" is not the same as "POSIX-portable"

busybox `ash` supports some bash-style extensions that plain `dash` doesn't,
e.g. `${var/pattern/replacement}` substitution. Code that only gets tried
against a real LINBO client (which runs busybox `ash`) can look portable
while actually relying on such an extension - it'll fail under `dash` with
"Bad substitution" the first time it's tested there.

This actually happened during Phase 1: `convert_size()`'s original
`${1/$unit}` passed under `ash` and failed under `dash`; fixed to the POSIX
suffix-removal form `${1%%[!0-9]*}`. Since the harness runs both shells, this
kind of thing surfaces on its own - just don't assume a function is portable
only because it's already used in production.

## Adding a new test

1. Pick a function that's pure enough to test today (see "Wave 1 vs. Wave 2"
   below).
2. Create `tests/shell/test_<script_name>.sh` following the pattern above.
3. Run it locally under both shells before committing (see above).

## Wave 1 vs. Wave 2

**Wave 1** - functions with no filesystem/device/network dependencies, testable
today without stubs:

- `convert_size()` (`linbo_partition`) - covered by `test_linbo_partition.sh`.
- `valid_image_name()` and `valid_profile_name()` (`linbo_driverpostsync`) -
  covered by `test_linbo_driverpostsync.sh`.
- `isinteger()`, `stringinstring()`, `remote_cache()`, `validip()` and
  `validhostname()` (`shell_functions`, the shared library sourced by nearly
  every linbofs script) - covered by `test_shell_functions.sh`. Testing
  `validip()`/`validhostname()` surfaced a real bug: both used `&>` to
  redirect `expr match`, a bashism dash parses as background (`&`) plus a
  bare `> /dev/null` (a no-op that always succeeds) - so under dash they
  validated any input at all as valid. Fixed to the POSIX
  `> /dev/null 2>&1` form.

**Wave 2** - functions that need stubs or fixtures before they're unit-testable;
tracked here rather than forced or used as an excuse to refactor the code
first:

- `mk_label()` (`linbo_label`) - calls `fstype_startconf`/`partlabel_startconf`
  from `shell_functions`, which read real `start.conf` files and sometimes
  block devices. Needs those helpers stubbed, or a fixture variant of
  `shell_functions`.
- The inline `match.conf` parsing and DMI matching in
  `linbo_driverpostsync` combines downloaded or cached metadata, file reads
  and local sysfs data. It needs fixtures and stubs before it can be
  unit-tested; extracting it into a separate function is intentionally
  outside this behavior-preserving runtime move.
- `findcache()` (`linbo_mountcache`) - iterates `/dev/disk/by-id/*part*` and
  mounts real partitions. Not sensibly unit-testable without abstracting the
  device enumeration (e.g. an overridable variable instead of a hardcoded
  path); only viable as an integration test on a real or virtual machine for
  now.

Phase 1 deliberately does not attempt retroactive coverage of the whole
`linbofs` script inventory - the goal is a usable, documented harness plus one
convincing pilot test, not full coverage.
