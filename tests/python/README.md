# Python test harness (tests/python/)

Unit tests for the pure-function parts of the linbo-remote Python rewrite
(issue [#169](https://github.com/linuxmuster/linuxmuster-linbo7/issues/169)),
using [pytest](https://pytest.org). Currently covers
`linbo_remote_lib.py` (`src/serverfs/usr/share/linuxmuster/linbo/`): the
`-c`/`-p` command-string parser, group/room/explicit-list host resolution,
and onboot command-file assembly.

## Running the tests locally

```sh
pip install pytest   # or: apt install python3-pytest
pytest tests/python
```

`conftest.py` adds `src/serverfs/usr/share/linuxmuster/linbo/` to `sys.path`
so modules there import by their plain name (e.g. `import linbo_remote_lib`),
matching how they're laid out on a real server - this isn't an installable
Python package, same as the rest of `src/serverfs/`.

## Design: no linuxmuster-base7 dependency for these tests

`linbo_remote_lib.py` reads devices.csv via linuxmuster-base7's
`getDevicesArray()` on a real server, but that import is confined to the one
function that actually needs it (`get_group_room_devices()`) and done lazily
inside it. Every other function - the command parser, `hosts_in_group()`,
`hosts_in_room()`, `resolve_explicit_hosts()`, `build_onboot_cmds()` - takes
already-fetched device rows as plain data and has no filesystem, network or
cross-repo dependency of its own, so these tests run without
linuxmuster-base7 installed and without a real devices.csv.

`resolve_explicit_hosts()`'s hostname/IPv4 syntax validators
(`_is_valid_hostname`/`_is_valid_ipv4`) are likewise small, self-contained
reimplementations rather than imports from linuxmuster-base7 - reusing that
package here would trade a few lines of regex for a real cross-repo test
dependency, which isn't worth it for validators this small.

## What's still bash-only for now

The tmux/SSH execution engine (building the per-host command script,
launching it under `tmux new -Ads ... pipe-pane`, wake-on-LAN, `-a`/`-l`
session handling) is step 2 of the rewrite and hasn't moved to Python yet -
see the tracking issue for the full plan and the external contract
(`linuxmuster-tools`' `LinboRemote` class, `linuxmuster-api`'s `/linbo/sync/*`
router, linbofs' onboot `.cmd`-file consumer) that must keep working
unchanged.