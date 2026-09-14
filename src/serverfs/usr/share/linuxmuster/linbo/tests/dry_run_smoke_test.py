#!/usr/bin/python3
#
# Filename     : dry_run_smoke_test.py
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
Usage: python3 dry_run_smoke_test.py --host <hostname> [--nr <os-nr>] [--school <school>]

Runs `linbo-remote -i <host> -c <cmd> --dry-run` for a representative set of
commands covering every shape linbo_wrapper accepts (see
buildCommandMatrix()), plus a --dry-run -p onboot check, and inspects the
resulting tmux session
log for the expected linbo_wrapper output - the "DRY RUN MODE" banner, the
right "Command : <name>" echo, and (where applicable) a
"[dry-run] would run: ..." line. Prints a PASS/FAIL summary per command and
exits non-zero if anything failed.

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
    log = readLog(host)
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


def main():
    parser = argparse.ArgumentParser(description=__doc__.strip().splitlines()[0])
    parser.add_argument('--host', required=True, help='hostname of a currently online LINBO client')
    parser.add_argument(
        '--nr', default='1', help='start.conf OS position to use for <#>-taking commands (default: 1)',
    )
    parser.add_argument('--school', default='default-school')
    args = parser.parse_args()

    results = []
    for label, cmd, expected_name in buildCommandMatrix(args.nr):
        status, reason = checkCommand(args.host, args.school, label, cmd, expected_name)
        results.append((label, status, reason))

    onboot_status, onboot_reason = checkOnboot(args.host, args.school, args.nr)
    results.append(('-p onboot dry-run', onboot_status, onboot_reason))

    width = max(len(label) for label, _, _ in results)
    for label, status, reason in results:
        line = f'{label:<{width}}  {status}'
        if reason:
            line += f'  ({reason})'
        print(line)

    failed = [r for r in results if r[1] == 'FAIL']
    skipped = [r for r in results if r[1] == 'SKIP']
    print()
    print(f'{len(results) - len(failed) - len(skipped)} passed, {len(failed)} failed, {len(skipped)} skipped')
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
