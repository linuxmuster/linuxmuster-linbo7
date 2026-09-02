# test_linbo_remote_cli.py
#
# pytest coverage for linbo_remote_cli.py's option validation and
# orchestration. Real subprocess/tmux/ssh/AD calls are mocked - see
# tests/python/README.md for the "Wave 1 vs Wave 2" testing philosophy this
# follows.
#
# thomas@linuxmuster.net
# 20260902

from unittest.mock import MagicMock

import pytest

import linbo_remote_cli as cli


DEVICES = [
    ('r100', 'r100-pc01', 'group1', '1'),
    ('r100', 'r100-pc02', 'group1', '2'),
]


@pytest.fixture(autouse=True)
def no_real_devices_csv(monkeypatch):
    """Every test in this file gets a fixed device list instead of touching a real devices.csv."""
    monkeypatch.setattr(cli.lib, 'get_group_room_devices', lambda school='default-school': DEVICES)


# --- usage_error / print_usage ------------------------------------------------

def test_usage_error_exits_1(capsys):
    with pytest.raises(SystemExit) as exc_info:
        cli.usage_error('boom')
    assert exc_info.value.code == 1
    out = capsys.readouterr().out
    assert 'Usage: linbo-remote <options>' in out
    assert out.rstrip().splitlines()[-1] == 'boom'


def test_help_exits_0(capsys):
    # -h is a deliberate deviation from the original bash (which exited 1
    # unconditionally from usage()) - see module docstring.
    assert cli.main(['-h']) == 0
    assert 'Usage: linbo-remote <options>' in capsys.readouterr().out


# --- option-combination validation --------------------------------------------

@pytest.mark.parametrize('argv, expected_message', [
    (['-c', 'reboot'], 'No hosts, no group, no room defined!'),
    (['-g', 'group1', '-i', 'r100-pc01', '-c', 'reboot'], 'Group and hosts defined!'),
    (['-g', 'group1', '-r', 'r100', '-c', 'reboot'], 'Group and room defined!'),
    (['-i', 'r100-pc01', '-c', 'reboot', '-p', 'reboot'], 'Direct and onboot commands defined!'),
    (['-i', 'r100-pc01'], 'No commands or wakeonlan defined!'),
    (['-i', 'r100-pc01', '-w', 'x'], 'x is not an integer variable!'),
    (['-i', 'r100-pc01', '-w', '10', '-b', 'x'], 'x is not an integer variable!'),
    (['-i', 'r100-pc01', '-b', '5', '-c', 'reboot'], 'Option -b can only be used with -w!'),
])
def test_validation_errors(argv, expected_message, capsys, monkeypatch):
    monkeypatch.setattr(cli.shutil, 'which', lambda name: '/usr/bin/wakeonlan')
    with pytest.raises(SystemExit) as exc_info:
        cli.main(argv)
    assert exc_info.value.code == 1
    assert capsys.readouterr().out.rstrip().splitlines()[-1] == expected_message


def test_unknown_command_reports_parser_error(capsys):
    with pytest.raises(SystemExit) as exc_info:
        cli.main(['-i', 'r100-pc01', '-c', 'frobnicate'])
    assert exc_info.value.code == 1
    assert 'not known' in capsys.readouterr().out


def test_create_image_rejected_for_group_selection(capsys):
    with pytest.raises(SystemExit) as exc_info:
        cli.main(['-g', 'group1', '-c', 'create_image:1'])
    assert exc_info.value.code == 1
    assert capsys.readouterr().out.rstrip().splitlines()[-1] == 'Upload or create cannot be used with lists!'


def test_no_hosts_in_group(capsys):
    with pytest.raises(SystemExit) as exc_info:
        cli.main(['-g', 'nosuchgroup', '-c', 'reboot'])
    assert exc_info.value.code == 1
    assert capsys.readouterr().out.rstrip().splitlines()[-1] == 'No hosts in group nosuchgroup!'


def test_wakeonlan_missing(capsys, monkeypatch):
    monkeypatch.setattr(cli.shutil, 'which', lambda name: None)
    assert cli.main(['-i', 'r100-pc01', '-w', '5']) == 1
    assert capsys.readouterr().out.rstrip().splitlines()[-1] == 'wakeonlan not found!'


# --- successful dispatch, with subprocess/filesystem mocked -------------------

def test_direct_dispatch_happy_path(monkeypatch, tmp_path, capsys):
    monkeypatch.setattr(cli, 'is_online', lambda host: True)
    monkeypatch.setattr(cli.environment, 'LINBOLOGDIR', str(tmp_path))
    monkeypatch.setattr(cli, 'TMPDIR', str(tmp_path))
    run_calls = []
    monkeypatch.setattr(cli.subprocess, 'run', lambda *a, **kw: run_calls.append((a, kw)) or MagicMock(
        returncode=0, stdout='12345\n',
    ))

    rc = cli.main(['-i', 'r100-pc01', '-c', 'reboot'])

    assert rc == 0
    out = capsys.readouterr().out
    assert 'Sending command(s) to:' in out
    assert 'Started with PID' in out
    # a tmux invocation happened, targeting the dot-form session name
    tmux_calls = [c for c in run_calls if c[0][0][0] == 'tmux']
    assert any('r100-pc01.linbo-remote' in c[0][0] for c in tmux_calls)


def test_direct_dispatch_offline_host_skipped(monkeypatch, capsys):
    monkeypatch.setattr(cli, 'is_online', lambda host: False)

    rc = cli.main(['-i', 'r100-pc01', '-c', 'reboot'])

    assert rc == 0
    out = capsys.readouterr().out
    assert 'Not online, host skipped.' in out


def test_onboot_writes_file_with_noauto_and_disablegui(monkeypatch, tmp_path, capsys):
    monkeypatch.setattr(cli.environment, 'LINBODIR', str(tmp_path))
    (tmp_path / 'linbocmd').mkdir()
    monkeypatch.setattr(cli, 'fix_onboot_dir_permissions', lambda: None)

    rc = cli.main(['-i', 'r100-pc01', '-p', 'sync:1', '-n', '-d'])

    assert rc == 0
    content = (tmp_path / 'linbocmd' / 'r100-pc01.cmd').read_text()
    assert content == 'sync:1,noauto,disablegui\n'
    assert 'Preparing onboot linbo tasks:' in capsys.readouterr().out


def test_list_sessions_filters_by_marker(monkeypatch, capsys):
    monkeypatch.setattr(
        cli.subprocess, 'run',
        lambda *a, **kw: MagicMock(stdout='other_session: 1 windows\nr100-pc01_linbo-remote: 1 windows\n'),
    )
    cli.list_sessions()
    out = capsys.readouterr().out
    assert 'r100-pc01_linbo-remote' in out
    assert 'other_session' not in out


def test_attach_session_no_such_session(monkeypatch, capsys):
    monkeypatch.setattr(cli.subprocess, 'run', lambda *a, **kw: MagicMock(stdout=''))
    with pytest.raises(SystemExit) as exc_info:
        cli.attach_session('r100-pc01')
    assert exc_info.value.code == 1
    assert 'There is no session for host r100-pc01.' in capsys.readouterr().out
