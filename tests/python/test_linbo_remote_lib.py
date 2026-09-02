# test_linbo_remote_lib.py
#
# pytest coverage for the pure functions in linbo_remote_lib.py: the -c/-p
# command-string parser, group/room/explicit-list host resolution and
# onboot command-file assembly. See tests/python/README.md.
#
# thomas@linuxmuster.net
# 20260902

import pytest

from linbo_remote_lib import (
    LinboRemoteError,
    buildOnbootCmds,
    getMacFromAd,
    getIpFromAd,
    hostsInGroup,
    hostsInRoom,
    parseCommandString,
    renderRemoteScript,
    resolveExplicitHosts,
    resolveWolTarget,
    tmuxAttachTarget,
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


# --- tmux session / logfile naming ------------------------------------------

def test_tmux_session_name_uses_dot():
    assert tmuxSessionName('r100-pc01') == 'r100-pc01.linbo-remote'


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
