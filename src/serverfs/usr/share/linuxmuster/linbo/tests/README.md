# linbo-remote dry-run smoke test

`linbo-remote_dry_run_test.py` is a live, on-server counterpart to the mocked unit
tests in `tests/python/` (repository root) - see issue
[#170](https://github.com/linuxmuster/linuxmuster-linbo7/issues/170). It
exercises every command shape `linbo-remote`'s own command parser accepts
(`linbo_remote_lib.KNOWN_COMMANDS`) against a real, currently-online LINBO
client via `--dry-run`, and checks the resulting tmux session log for the
expected `linbo_wrapper` output - without performing any actual
partitioning, syncing, image creation/upload, reboot or halt.

This ships as part of the package (installed to
`/usr/share/linuxmuster/linbo/tests/`), unlike `tests/python/`, which is
repo/CI-only and never installed - `linbo-remote_dry_run_test.py` needs a real
server (linuxmuster-base7, real `devices.csv`/AD data, real `linbo-remote`
install) and a real, reachable LINBO client, none of which CI has.

## Running it

On a real server, with a LINBO client (`--host`) currently online:

```sh
python3 /usr/share/linuxmuster/linbo/tests/linbo-remote_dry_run_test.py --host <hostname>
```

Optional: `--nr <#>` (default `1`) picks which `start.conf` OS position to
use for `<#>`-taking commands, `--school <school>` for a non-default
school. Prints a PASS/FAIL/SKIP line per command plus a summary, and exits
non-zero if anything failed.

**Don't run it against a host something else might be targeting at the same
time** (another run of this script, or a real admin's own `linbo-remote`
command) - see "A note on concurrent access" below. Confirmed by hitting
this directly during development: two overlapping runs against the same
host produced consistent-looking but entirely bogus failures across
unrelated commands.

## What it checks, and what it deliberately doesn't

For each command it runs `linbo-remote -i <host> -c <cmd> --dry-run` and
waits for the tmux session to finish, then checks the session log for:

- the `DRY RUN MODE` banner (confirms `linbo_wrapper` actually received
  `--dry-run`, not just that `linbo-remote` accepted the option)
- the expected underlying action name (e.g. `linbo_sync`, `linbo_cmd`,
  `/sbin/reboot`) in a `[dry-run] would run: ...` line

It's deliberately lenient on the *exact* argument text for
`start.conf`/`os.<nr>`-dependent commands (`create_image`, `upload_image`,
...) - the OS name, image filename and server IP a given `<#>` resolves to
depend on that particular server's own configuration, so byte-for-byte
argument checking only makes sense against fixture data, which is exactly
what `tests/python/`'s mocked `render_remote_script()` tests already do.
This script's job is end-to-end *reachability*: does a given option still
actually arrive at `linbo_wrapper` correctly on a real, running system -
not re-deriving what `tests/python/` already covers precisely.

`buildCommandMatrix()` asserts every command it tests is actually a member
of `linbo_remote_lib.KNOWN_COMMANDS` - this caught a real mistake during
development: `update` is a real `linbo_wrapper` command, but was never part
of `linbo-remote`'s own command vocabulary (not even in the original bash
implementation), so it's excluded on purpose, not by oversight.

## A note on concurrent access

`linbo-remote` uses one fixed tmux session name and one fixed logfile per
*host* (`tmuxSessionName()`/`tmuxAttachTarget()` in `linbo_remote_lib.py`),
not per invocation. Two invocations targeting the same host at the same
time - two runs of this script, or this script racing a real admin's own
`linbo-remote -i <host> ...` - corrupt each other's session/log and produce
confusing, seemingly-random failures scattered across unrelated commands,
even though neither `linbo-remote` nor `linbo_wrapper` did anything wrong.
This is a pre-existing property of the tmux-based dispatch design (true of
the original bash implementation too), not something `--dry-run`
introduced, and not something this script's log-reading can wait its way
around - it only ever targets one host at a time itself, but has no way to
know if someone else is doing the same.

## Not covered

A full `-p` (onboot) boot-cycle - only that the onboot `.cmd` file gets
written with the `dryrun` token first. Verifying `linbofs`' `init.sh` side
of onboot dry-run needs a real reboot against a rebuilt `linbofs` image
(`update-linbofs`), which this script doesn't attempt.