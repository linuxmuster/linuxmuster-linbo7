#
# Filename     : test_linbo_remote_lib.py
# Description  : pytest coverage for the pure functions in
#                linbo_remote_lib.py: the -c/-p command-string parser,
#                group/room/explicit-list host resolution, onboot
#                command-file assembly, per-host script rendering and
#                wake-on-LAN target resolution. See tests/python/README.md.
# Signed-off by: thomas@linuxmuster.net
# Assisted by  : Claude
# Date         : 20261001
#

import fnmatch
import json
import os
import re
import signal
import shutil
import subprocess
import time

import pytest

from linbo_remote_lib import (
    LinboRemoteError,
    RUN_RECORD_BASENAME,
    buildOnbootCmds,
    buildRunRecordPrefix,
    pruneRunLogs,
    getMacFromAd,
    getIpFromAd,
    hostsInGroup,
    hostsInRoom,
    isValidIpv4,
    parseCommandString,
    renderRemoteScript,
    resolveExplicitHosts,
    resolveWolTarget,
    tmuxAttachTarget,
    runLogName,
    tmuxSessionName,
)


# --- parseCommandString ---------------------------------------------------

@pytest.mark.parametrize('cmds, expected', [
    ('reboot', ['reboot']),
    ('halt', ['halt']),
    ('label', ['label']),
    ('partition', ['partition']),
    ('format', ['format']),
    ('format:2', ['format:2']),
    ('sync:1', ['sync:1']),
    ('new:3', ['new:3']),
    ('start:1', ['start:1']),
    ('postsync:1', ['postsync:1']),
    ('prestart:1', ['prestart:1']),
    ('upload_image:1', ['upload_image:1']),
    ('upload_qdiff:2', ['upload_qdiff:2']),
    ('initcache', ['initcache']),
    ('initcache:rsync', ['initcache:rsync']),
    ('initcache:multicast', ['initcache:multicast']),
    ('initcache:torrent', ['initcache:torrent']),
    ('create_image:1', ['create_image:1']),
    ('create_qdiff:2', ['create_qdiff:2']),
    # multiple commands, in order
    ('format,sync:1,reboot', ['format', 'sync:1', 'reboot']),
    ('initcache:rsync,new:1,postsync:1,start:1',
     ['initcache:rsync', 'new:1', 'postsync:1', 'start:1']),
])
def test_parse_command_string_known_shapes(cmds, expected):
    assert parseCommandString(cmds) == expected


def test_create_image_with_comment():
    assert parseCommandString('create_image:1:my comment') == ['create_image:1:"my comment"']


def test_create_qdiff_with_comment_then_more_commands():
    # the comment is truncated at the first ",<knowncommand>" boundary, the
    # remaining commands are parsed normally afterwards
    assert parseCommandString('create_qdiff:1:my comment,reboot') == [
        'create_qdiff:1:"my comment"',
        'reboot',
    ]


def test_comment_containing_a_literal_comma_before_the_boundary():
    # a comma inside the comment text that isn't followed by a known command
    # name is kept as part of the comment - only the boundary right before
    # "reboot" gets cut
    assert parseCommandString('create_image:1:my comment, with a comma,reboot') == [
        'create_image:1:"my comment, with a comma"',
        'reboot',
    ]


def test_create_image_without_comment_before_next_command():
    assert parseCommandString('create_image:1,reboot') == ['create_image:1', 'reboot']


def test_unknown_command_raises():
    with pytest.raises(LinboRemoteError, match='not known'):
        parseCommandString('frobnicate')


def test_required_nr_missing_raises():
    with pytest.raises(LinboRemoteError, match='not valid'):
        parseCommandString('sync')


def test_required_nr_not_an_integer_raises():
    with pytest.raises(LinboRemoteError, match='not an integer'):
        parseCommandString('sync:abc')


def test_initcache_bad_dltype_raises():
    with pytest.raises(LinboRemoteError, match='not known'):
        parseCommandString('initcache:carrierpigeon')


def test_format_nr_not_an_integer_raises():
    with pytest.raises(LinboRemoteError, match='not an integer'):
        parseCommandString('format:x')


# --- hostsInGroup / hostsInRoom -----------------------------------------

DEVICES = [
    ('r100', 'r100-pc01', 'group1', '1'),
    ('r100', 'r100-pc02', 'group1', '2'),
    ('r200', 'r200-pc01', 'group2', '1'),
]


def test_hosts_in_group():
    assert hostsInGroup(DEVICES, 'group1') == ['r100-pc01', 'r100-pc02']


def test_hosts_in_group_no_match():
    assert hostsInGroup(DEVICES, 'nosuchgroup') == []


def test_hosts_in_room():
    assert hostsInRoom(DEVICES, 'r100') == ['r100-pc01', 'r100-pc02']


def test_hosts_in_room_no_match():
    assert hostsInRoom(DEVICES, 'r999') == []


# --- isValidIpv4 -------------------------------------------------------------

@pytest.mark.parametrize('ip, expected', [
    ('10.16.100.1', True),
    ('0.0.0.0', True),
    ('255.255.255.255', True),
    # regression cases for #174: a trailing/leading .0 or .255 depends on the
    # subnet's prefix length, which this function doesn't know - it used to
    # reject these outright, assuming a /24-or-larger subnet
    ('10.0.0.0', True),
    ('10.0.0.255', True),
    ('10.0.1.255', True),
    # still-invalid syntax
    ('10.16.100', False),
    ('10.16.100.1.2', False),
    ('10.16.100.256', False),
    ('10.16.100.-1', False),
    ('10.16.100.abc', False),
    ('', False),
    (None, False),
])
def test_is_valid_ipv4(ip, expected):
    assert isValidIpv4(ip) == expected


# --- resolveExplicitHosts --------------------------------------------------

def test_resolve_explicit_hosts_by_hostname():
    matched, skipped = resolveExplicitHosts(['r100-pc01'], DEVICES)
    assert matched == ['r100-pc01']
    assert skipped == []


def test_resolve_explicit_hosts_unknown_hostname_skipped_as_not_pxe():
    matched, skipped = resolveExplicitHosts(['r999-pc99'], DEVICES)
    assert matched == []
    assert skipped == ['Skipping r999-pc99, not a pxe host!']


def test_resolve_explicit_hosts_by_ip_resolves_via_injected_lookup():
    matched, skipped = resolveExplicitHosts(
        ['10.16.100.1'], DEVICES, ip_to_hostname=lambda ip: 'r100-pc01',
    )
    assert matched == ['r100-pc01']
    assert skipped == []


def test_resolve_explicit_hosts_ip_lookup_fails():
    matched, skipped = resolveExplicitHosts(
        ['10.16.100.99'], DEVICES, ip_to_hostname=lambda ip: None,
    )
    assert matched == []
    assert skipped == ['Host 10.16.100.99 not found!']


def test_resolve_explicit_hosts_with_school_prefix():
    prefixed_devices = [
        ('r100', 'myschool-r100-pc01', 'group1', '1'),
    ]
    matched, skipped = resolveExplicitHosts(
        ['r100-pc01'], prefixed_devices, school='myschool',
    )
    assert matched == ['myschool-r100-pc01']
    assert skipped == []


def test_resolve_explicit_hosts_mixed_list():
    matched, skipped = resolveExplicitHosts(
        ['r100-pc01', 'bogus-host'], DEVICES,
    )
    assert matched == ['r100-pc01']
    assert skipped == ['Skipping bogus-host, not a pxe host!']


# --- buildOnbootCmds -------------------------------------------------------

def test_build_onboot_cmds_plain():
    assert buildOnbootCmds(['sync:1', 'reboot']) == 'sync:1,reboot'


def test_build_onboot_cmds_with_noauto_and_disablegui():
    assert buildOnbootCmds(['sync:1'], noauto=True, disablegui=True) == 'sync:1,noauto,disablegui'


def test_build_onboot_cmds_with_secrets_line():
    assert buildOnbootCmds(
        ['upload_image:1'], secrets_line='linbo:somehash',
    ) == 'linbo:somehash,upload_image:1'


def test_build_onboot_cmds_noauto_only_no_commands():
    assert buildOnbootCmds([], noauto=True) == 'noauto'


def test_build_onboot_cmds_dry_run_comes_first():
    # must be first, before secrets_line even, so linbofs' init.sh has the
    # flag active for the whole boot command sequence
    assert buildOnbootCmds(
        ['upload_image:1'], noauto=True, secrets_line='linbo:somehash', dry_run=True,
    ) == 'dryrun,linbo:somehash,upload_image:1,noauto'


# --- tmux session / per-run logfile naming ------------------------------------------

def test_tmux_session_name_uses_dot():
    assert tmuxSessionName('r100-pc01') == 'r100-pc01.linbo-remote'


def test_run_log_name_has_host_and_timestamp():
    assert runLogName('r100-pc01', '20261001120530') == 'r100-pc01_linbo-remote_20261001120530.log'


def test_run_log_name_default_timestamp_is_seconds_resolution():
    assert re.fullmatch(r'r100-pc01_linbo-remote_\d{14}\.log', runLogName('r100-pc01'))


def test_run_log_name_does_not_match_update_linbofs_glob():
    # update-linbofs scans LINBOLOGDIR/*_linbo.log for missing firmware
    assert not fnmatch.fnmatch(runLogName('r100-pc01'), '*_linbo.log')


def test_tmux_attach_target_uses_underscore():
    # tmux itself rewrites the '.' in tmuxSessionName() to '_' internally;
    # this is the name to look an existing session back up by.
    assert tmuxAttachTarget('r100-pc01') == 'r100-pc01_linbo-remote'


# --- renderRemoteScript -----------------------------------------------------

def test_render_remote_script_simple_commands():
    script = renderRemoteScript('r100-pc01', ['format:2', 'sync:1'], '/var/tmp/123.r100-pc01.sh')
    lines = script.splitlines()
    assert lines[0] == '#!/bin/bash'
    assert 'gui_ctl disable' in lines[1]
    assert lines[2] == 'RC=0'
    assert '/usr/bin/linbo_wrapper format:2 || RC=1' in lines[3]
    assert lines[4] == 'sleep 3'
    assert '/usr/bin/linbo_wrapper sync:1 || RC=1' in lines[5]
    assert 'gui_ctl restore' in lines[-3]
    assert lines[-2] == "rm -f /var/tmp/123.r100-pc01.sh"
    assert lines[-1] == 'exit $RC'


def test_render_remote_script_backgrounds_start_reboot_halt():
    script = renderRemoteScript('r100-pc01', ['start:1'], '/var/tmp/x.sh')
    assert '/usr/bin/linbo_wrapper start:1 &' in script
    assert 'sleep 10' in script

    script = renderRemoteScript('r100-pc01', ['reboot'], '/var/tmp/x.sh')
    assert '/usr/bin/linbo_wrapper reboot &' in script

    script = renderRemoteScript('r100-pc01', ['halt'], '/var/tmp/x.sh')
    assert '/usr/bin/linbo_wrapper halt &' in script


def test_render_remote_script_quotes_multiword_comment_as_one_token():
    commands = parseCommandString('create_image:1:my long comment')
    script = renderRemoteScript('r100-pc01', commands, '/var/tmp/x.sh')
    assert '\'create_image:1:"my long comment"\'' in script
    # and NOT split unquoted into the generated line
    assert 'linbo_wrapper create_image:1:"my long comment"\n' not in script


def test_render_remote_script_secrets_cleanup_when_no_backgrounded_command():
    script = renderRemoteScript('r100-pc01', ['sync:1'], '/var/tmp/x.sh', secrets_uploaded=True)
    assert '/bin/rm -f /tmp/rsyncd.secrets' in script


def test_render_remote_script_dry_run_flag_on_every_wrapper_call():
    script = renderRemoteScript('r100-pc01', ['format:2', 'sync:1'], '/var/tmp/x.sh', dry_run=True)
    assert '/usr/bin/linbo_wrapper --dry-run format:2 || RC=1' in script
    assert '/usr/bin/linbo_wrapper --dry-run sync:1 || RC=1' in script


def test_render_remote_script_dry_run_flag_on_backgrounded_commands_too():
    # especially there - that's exactly the case you don't want a real reboot
    script = renderRemoteScript('r100-pc01', ['reboot'], '/var/tmp/x.sh', dry_run=True)
    assert '/usr/bin/linbo_wrapper --dry-run reboot &' in script


def test_render_remote_script_no_dry_run_flag_by_default():
    script = renderRemoteScript('r100-pc01', ['reboot'], '/var/tmp/x.sh')
    assert '--dry-run' not in script


def test_render_remote_script_no_secrets_cleanup_when_backgrounded_command_present():
    script = renderRemoteScript('r100-pc01', ['sync:1', 'reboot'], '/var/tmp/x.sh', secrets_uploaded=True)
    assert '/bin/rm -f /tmp/rsyncd.secrets' not in script


# --- WOL target resolution ---------------------------------------------------

def test_get_mac_from_ad_by_hostname():
    calls = []

    def fake_ldbsearch(filter_expr, attribute, basedn):
        calls.append((filter_expr, attribute, basedn))
        return '52:54:00:AA:BB:CC'

    result = getMacFromAd('r100-pc01', 'DC=school,DC=lan', ldbsearch=fake_ldbsearch)
    assert result == '52:54:00:AA:BB:CC'
    assert calls == [('(sophomorixDnsNodename=r100-pc01)', 'sophomorixComputerMAC', 'DC=school,DC=lan')]


def test_get_ip_from_ad_by_hostname():
    result = getIpFromAd('r100-pc01', 'DC=school,DC=lan', ldbsearch=lambda *a: '10.16.100.1')
    assert result == '10.16.100.1'


def test_resolve_wol_target_uses_ad_values_when_valid():
    mac, ip = resolveWolTarget(
        'r100-pc01', 'DC=school,DC=lan',
        ldbsearch=lambda filter_expr, attribute, basedn: (
            '10.16.100.1' if attribute == 'sophomorixComputerIP' else '52:54:00:AA:BB:CC'
        ),
    )
    assert mac == '52:54:00:AA:BB:CC'
    assert ip == '10.16.100.1'


def test_resolve_wol_target_falls_back_to_arp_when_ad_ip_invalid():
    mac, ip = resolveWolTarget(
        'r100-pc01', 'DC=school,DC=lan',
        ldbsearch=lambda filter_expr, attribute, basedn: (
            'DHCP' if attribute == 'sophomorixComputerIP' else '52:54:00:AA:BB:CC'
        ),
        arp_lookup=lambda hostname: '10.16.100.42',
    )
    assert mac == '52:54:00:AA:BB:CC'
    assert ip == '10.16.100.42'


def test_resolve_wol_target_falls_back_to_dhcp_lease_when_ad_mac_invalid():
    mac, ip = resolveWolTarget(
        'r100-pc01', 'DC=school,DC=lan',
        ldbsearch=lambda filter_expr, attribute, basedn: (
            '10.16.100.1' if attribute == 'sophomorixComputerIP' else ''
        ),
        dhcp_lease_mac=lambda ip: '52:54:00:dd:ee:ff',
    )
    assert mac == '52:54:00:dd:ee:ff'
    assert ip == '10.16.100.1'


# --- per-run record (JSON line appended by the remote script) ----------------

STARTED = time.strptime('20261001120530', '%Y%m%d%H%M%S')


def test_run_record_prefix_is_open_json_object():
    prefix = buildRunRecordPrefix('r100-pc01', ['format:2', 'sync:1'], STARTED, '/log/x.log')
    assert not prefix.endswith('}')
    record = json.loads(prefix + '}')
    assert record['hostname'] == 'r100-pc01'
    assert record['mode'] == 'direct'
    assert record['commands'] == ['format:2', 'sync:1']
    assert record['dry_run'] is False
    assert record['log'] == '/log/x.log'
    assert record['start'].startswith('2026-10-01T12:05:30')


def test_render_remote_script_without_record_has_no_trap():
    script = renderRemoteScript('r100-pc01', ['sync:1'], '/var/tmp/x.sh')
    assert 'trap' not in script
    assert 'RUN_RECORD' not in script


def test_render_remote_script_with_record_installs_exit_trap_first():
    script = renderRemoteScript(
        'r100-pc01', ['sync:1'], '/var/tmp/x.sh',
        record_file='/log/' + RUN_RECORD_BASENAME, record_prefix='{"hostname":"r100-pc01"',
    )
    lines = script.splitlines()
    assert lines[0] == '#!/bin/bash'
    assert 'trap writeRunRecord EXIT' in lines
    assert lines.index('trap writeRunRecord EXIT') < next(
        i for i, line in enumerate(lines) if 'gui_ctl disable' in line
    )


needs_bash_flock = pytest.mark.skipif(
    not (shutil.which('bash') and shutil.which('flock')), reason='needs bash and flock',
)


def runRenderedScript(monkeypatch, tmp_path, ssh_cmd, commands):
    """Run a rendered script for real, with linbo-ssh replaced by `true`/`false`."""
    import linbo_remote_lib
    monkeypatch.setattr(linbo_remote_lib, 'SSH_CMD', ssh_cmd)
    record_file = tmp_path / RUN_RECORD_BASENAME
    prefix = buildRunRecordPrefix('r100-pc01', commands, STARTED, str(tmp_path / 'x.log'))
    script = tmp_path / 'run.sh'
    script.write_text(renderRemoteScript(
        'r100-pc01', commands, str(script), record_file=str(record_file), record_prefix=prefix,
    ))
    rc = subprocess.run(['bash', str(script)], check=False).returncode
    return rc, record_file


@needs_bash_flock
def test_run_record_written_on_success(monkeypatch, tmp_path):
    rc, record_file = runRenderedScript(monkeypatch, tmp_path, 'true', ['sync:1'])
    assert rc == 0
    lines = record_file.read_text().splitlines()
    assert len(lines) == 1
    record = json.loads(lines[0])
    assert record['rc'] == 0
    assert record['commands'] == ['sync:1']
    assert re.fullmatch(r'\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d[+-]\d{4}', record['end'])


@needs_bash_flock
def test_run_record_written_on_failure_and_appended(monkeypatch, tmp_path):
    runRenderedScript(monkeypatch, tmp_path, 'true', ['sync:1'])
    rc, record_file = runRenderedScript(monkeypatch, tmp_path, 'false', ['sync:1'])
    assert rc == 1
    records = [json.loads(line) for line in record_file.read_text().splitlines()]
    assert [r['rc'] for r in records] == [0, 1]


@needs_bash_flock
@pytest.mark.parametrize('sig, expected_rc', [
    (signal.SIGHUP, 129),    # tmux kill-session / closed pane
    (signal.SIGTERM, 143),
    (signal.SIGINT, 130),
])
def test_run_record_of_aborted_run_has_signal_exit_status(monkeypatch, tmp_path, sig, expected_rc):
    import linbo_remote_lib
    monkeypatch.setattr(linbo_remote_lib, 'SSH_CMD', 'sleep 30; true')
    record_file = tmp_path / RUN_RECORD_BASENAME
    prefix = buildRunRecordPrefix('r100-pc01', ['sync:1'], STARTED, str(tmp_path / 'x.log'))
    script = tmp_path / 'run.sh'
    script.write_text(renderRemoteScript(
        'r100-pc01', ['sync:1'], str(script), record_file=str(record_file), record_prefix=prefix,
    ))
    proc = subprocess.Popen(['bash', str(script)], start_new_session=True)
    time.sleep(1)
    os.killpg(proc.pid, sig)    # whole group, like tmux does - kills the running child too
    proc.wait(timeout=10)
    record = json.loads(record_file.read_text().splitlines()[0])
    assert record['rc'] == expected_rc


# --- retention of per-run logs ----------------------------------------------

def test_prune_run_logs_removes_only_old_per_run_logs(tmp_path):
    now = time.time()
    old = tmp_path / 'r100-pc01_linbo-remote_20260101000000.log'
    fresh = tmp_path / 'r100-pc01_linbo-remote_20261001120000.log'
    others = [
        tmp_path / 'r100-pc01_linbo.log',
        tmp_path / 'rsync-pre-download.log',
        tmp_path / RUN_RECORD_BASENAME,
        tmp_path / 'r100-pc01_linbo-remote_20260101000000.log.1.gz',
    ]
    for f in [old, fresh, *others]:
        f.write_text('x')
        os.utime(f, (now - 200 * 86400, now - 200 * 86400))
    os.utime(fresh, (now - 1 * 86400, now - 1 * 86400))

    assert pruneRunLogs(str(tmp_path), max_age_days=90, now=now) == 1
    assert not old.exists()
    assert fresh.exists()
    assert all(f.exists() for f in others)


def test_prune_run_logs_missing_dir_is_not_an_error(tmp_path):
    assert pruneRunLogs(str(tmp_path / 'nope')) == 0
