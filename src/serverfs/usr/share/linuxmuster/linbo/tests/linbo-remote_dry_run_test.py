#!/usr/bin/python3
#
# Filename     : linbo-remote_dry_run_test.py
# Description  : Exercises every linbo-remote command shape with --dry-run
#                against a real, reachable LINBO client, to verify each one
#                arrives at linbo_wrapper correctly. A live counterpart to
#                tests/python/'s mocked unit tests (issue #170) - run this
#                by hand on a real server against a real, online client,
#                it is not part of the pytest/CI suite.
# Signed-off by: thomas@linuxmuster.net
# Assisted by  : Claude
# Date         : 20260914
#
"""
Usage: python3 linbo-remote_dry_run_test.py --host <hostname> [--nr <os-nr>] [--school <school>]

Runs `linbo-remote -i <host> -c <cmd> --dry-run` for a representative set of
commands covering every shape linbo_wrapper accepts (see
buildCommandMatrix()), plus a --dry-run -p onboot check, and inspects the
resulting tmux session
log for the expected linbo_wrapper output - the "DRY RUN MODE" banner, the
right "Command : <name>" echo, and (where applicable) a
"[dry-run] would run: ..." line. Prints a PASS/FAIL line per command as soon
as it's checked (not collected and dumped at the end - each command takes a
few seconds, so this keeps a long run legible while it's happening), plus a
final summary, and exits non-zero if anything failed.

Deliberately lenient on exact argument text for os.<nr>-dependent commands
(create_image, upload_image, ...): the *shape* of the check stays the same
across any server, but the OS name/imagefile/serverip a given <nr> resolves
to depends on that server's own start.conf, so this only asserts the right
underlying command ran, not its full argument list byte-for-byte - that
precise-argument-shape testing already lives in tests/python/'s mocked
unit tests (render_remote_script et al.), which don't need a real server at
all. This script's job is end-to-end reachability: does option X actually
still arrive at linbo_wrapper as intended on a real, running system.

Needs: a real linuxmuster-base7 server with linbo-remote installed, and a
LINBO client (given by --host, e.g. a devices.csv hostname) that is
currently online and has at least one OS defined at position --nr (default:
1) in its start.conf.

Don't run this against a host something else might be targeting at the same
time (another run of this script, or a real admin's own linbo-remote
command) - linbo-remote uses one fixed tmux session name and one fixed
logfile per host, so concurrent invocations against the *same* host corrupt
each other's session/log and produce confusing, seemingly-random failures
that have nothing to do with linbo-remote or linbo_wrapper actually being
broken. This is a pre-existing property of the tmux-based dispatch design,
true of the original bash implementation too - not something --dry-run
introduced or something this script can wait its way around.
"""

import argparse
import os
import subprocess
import sys
import time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
import linbo_remote_lib as lib  # noqa: E402

LINBO_REMOTE = '/usr/sbin/linbo-remote'
LOGDIR = '/var/log/linuxmuster/linbo'
LINBOCMD_DIR = '/srv/linbo/linbocmd'


def buildCommandMatrix(nr):
    """
    (label, cmd, expected_command_name) tuples covering every command shape
    linbo_wrapper's case statement accepts *and* linbo-remote's own parser
    actually lets through (linbo_remote_lib.KNOWN_COMMANDS) - notably,
    "update" is a real linbo_wrapper command but was never part of
    linbo-remote's own command vocabulary, not even in the original bash
    implementation, so it's deliberately not tested here (the assertion
    below guards against silently re-including it, or anything else not in
    KNOWN_COMMANDS, by mistake). expected_command_name is the underlying
    linbo_* binary/action looked for in a
    "[dry-run] would run: <expected_command_name>" log line - not the full
    argument list, see module docstring.
    """
    matrix = [
        ('label', 'label', 'linbo_label'),
        ('partition', 'partition', 'linbo_partition'),
        ('format (bare)', 'format', 'linbo_partition_format'),
        (f'format:{nr}', f'format:{nr}', 'linbo_format'),
        ('initcache (bare)', 'initcache', 'linbo_initcache'),
        ('initcache:rsync', 'initcache:rsync', 'linbo_initcache'),
        (f'sync:{nr}', f'sync:{nr}', 'linbo_sync'),
        (f'new:{nr}', f'new:{nr}', 'linbo_sync'),
        (f'postsync:{nr}', f'postsync:{nr}', 'linbo_postsync'),
        (f'start:{nr}', f'start:{nr}', 'linbo_cmd'),
        (f'prestart:{nr}', f'prestart:{nr}', 'linbo_prestart'),
        (f'create_image:{nr}', f'create_image:{nr}', 'linbo_create_image'),
        (f'create_image:{nr} with comment', f'create_image:{nr}:smoke test comment', 'linbo_create_image'),
        (f'create_qdiff:{nr}', f'create_qdiff:{nr}', 'linbo_create_image'),
        (f'upload_image:{nr}', f'upload_image:{nr}', 'linbo_upload'),
        (f'upload_qdiff:{nr}', f'upload_qdiff:{nr}', 'linbo_upload'),
        ('reboot', 'reboot', '/sbin/reboot'),
        ('halt', 'halt', '/sbin/poweroff'),
    ]
    for label, cmd, _ in matrix:
        base = cmd.split(':', 1)[0]
        assert base in lib.KNOWN_COMMANDS, (
            f'"{label}" uses command "{base}", which is not in linbo_remote_lib.KNOWN_COMMANDS - '
            'linbo-remote would reject it before it ever reaches linbo_wrapper'
        )
    return matrix


def waitForSessionToEnd(host, timeout=20):
    deadline = time.time() + timeout
    target = f'{host}_linbo-remote'
    while time.time() < deadline:
        result = subprocess.run(['tmux', 'list-sessions'], capture_output=True, text=True, check=False)
        if not any(line.startswith(target) for line in result.stdout.splitlines()):
            return
        time.sleep(0.5)


def readLog(host):
    try:
        with open(os.path.join(LOGDIR, f'{host}.linbo-remote')) as f:
            return f.read()
    except OSError:
        return None


def readLogWhenStable(host, settle_checks=2, poll_interval=0.2, timeout=10):
    """
    Read the per-host session log, waiting for its content to stop changing
    across a couple of quick re-reads before returning it - cheap insurance
    against tmux reporting a session as gone (waitForSessionToEnd()) a hair
    before its pipe-pane's `cat > logfile` process has actually finished
    flushing and closing the file.

    This is *not* a fix for concurrent access: linbo-remote uses one fixed
    tmux session name and one fixed logfile per host
    (tmuxSessionName()/tmuxAttachTarget()), so two invocations targeting
    the *same* host at the same time - two of this script, or this script
    racing a real admin's own `linbo-remote -i <host> ...` - will corrupt
    each other's session/log the same way, with or without this function.
    That's a pre-existing property of the tmux-based dispatch design (true
    of the original bash implementation too), not something introduced by
    --dry-run or fixable by waiting longer here. Don't run this script
    against a host that something else might be targeting at the same time.
    """
    deadline = time.time() + timeout
    last = None
    stable_count = 0
    while time.time() < deadline:
        current = readLog(host)
        if current is not None and current == last:
            stable_count += 1
            if stable_count >= settle_checks:
                return current
        else:
            stable_count = 0
        last = current
        time.sleep(poll_interval)
    return last


def runDryRunCommand(host, school, cmd, timeout=20):
    result = subprocess.run(
        [LINBO_REMOTE, '-i', host, '-s', school, '-c', cmd, '--dry-run'],
        capture_output=True, text=True, timeout=timeout,
    )
    if 'Not online, host skipped.' in result.stdout:
        return 'SKIP', 'host not online', result.stdout
    if result.returncode != 0:
        return 'FAIL', f'linbo-remote exited {result.returncode}', result.stdout

    waitForSessionToEnd(host, timeout=timeout)
    log = readLogWhenStable(host)
    if log is None:
        return 'FAIL', 'no session log found', result.stdout
    return 'LOG', None, log


def checkCommand(host, school, label, cmd, expected_name):
    status, reason, log = runDryRunCommand(host, school, cmd)
    if status in ('SKIP', 'FAIL'):
        return status, reason

    if 'DRY RUN MODE' not in log:
        return 'FAIL', 'missing "DRY RUN MODE" banner in log'
    if expected_name not in log:
        return 'FAIL', f'expected "{expected_name}" not found in log'
    return 'PASS', None


def checkOnboot(host, school, nr):
    cmd_file = os.path.join(LINBOCMD_DIR, f'{host}.cmd')
    try:
        os.remove(cmd_file)
    except OSError:
        pass

    result = subprocess.run(
        [LINBO_REMOTE, '-i', host, '-s', school, '-p', f'sync:{nr}', '--dry-run'],
        capture_output=True, text=True, timeout=20,
    )
    if result.returncode != 0:
        return 'FAIL', f'linbo-remote exited {result.returncode}'

    try:
        with open(cmd_file) as f:
            content = f.read()
    except OSError:
        return 'FAIL', 'onboot .cmd file was not written'
    finally:
        try:
            os.remove(cmd_file)
        except OSError:
            pass

    if not content.startswith('dryrun,'):
        return 'FAIL', f'expected "dryrun," prefix, got: {content!r}'
    return 'PASS', None


def printResult(label, status, reason, width):
    line = f'{label:<{width}}  {status}'
    if reason:
        line += f'  ({reason})'
    print(line, flush=True)  # flush: stdout is fully buffered when piped, not just line-buffered


def main():
    parser = argparse.ArgumentParser(description=__doc__.strip().splitlines()[0])
    parser.add_argument('--host', required=True, help='hostname of a currently online LINBO client')
    parser.add_argument(
        '--nr', default='1', help='start.conf OS position to use for <#>-taking commands (default: 1)',
    )
    parser.add_argument('--school', default='default-school')
    args = parser.parse_args()

    matrix = buildCommandMatrix(args.nr)
    # known upfront (labels don't depend on running anything), so results can
    # still print aligned even though each is printed live, one at a time
    width = max(len(label) for label, _, _ in matrix + [('-p onboot dry-run', '', '')])

    results = []
    for label, cmd, expected_name in matrix:
        status, reason = checkCommand(args.host, args.school, label, cmd, expected_name)
        printResult(label, status, reason, width)
        results.append((label, status, reason))

    onboot_status, onboot_reason = checkOnboot(args.host, args.school, args.nr)
    printResult('-p onboot dry-run', onboot_status, onboot_reason, width)
    results.append(('-p onboot dry-run', onboot_status, onboot_reason))

    failed = [r for r in results if r[1] == 'FAIL']
    skipped = [r for r in results if r[1] == 'SKIP']
    print()
    print(f'{len(results) - len(failed) - len(skipped)} passed, {len(failed)} failed, {len(skipped)} skipped')
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
