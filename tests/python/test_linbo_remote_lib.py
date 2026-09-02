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
    build_onboot_cmds,
    hosts_in_group,
    hosts_in_room,
    parse_command_string,
    resolve_explicit_hosts,
)


# --- parse_command_string ---------------------------------------------------

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
    assert parse_command_string(cmds) == expected


def test_create_image_with_comment():
    assert parse_command_string('create_image:1:my comment') == ['create_image:1:"my comment"']


def test_create_qdiff_with_comment_then_more_commands():
    # the comment is truncated at the first ",<knowncommand>" boundary, the
    # remaining commands are parsed normally afterwards
    assert parse_command_string('create_qdiff:1:my comment,reboot') == [
        'create_qdiff:1:"my comment"',
        'reboot',
    ]


def test_comment_containing_a_literal_comma_before_the_boundary():
    # a comma inside the comment text that isn't followed by a known command
    # name is kept as part of the comment - only the boundary right before
    # "reboot" gets cut
    assert parse_command_string('create_image:1:my comment, with a comma,reboot') == [
        'create_image:1:"my comment, with a comma"',
        'reboot',
    ]


def test_create_image_without_comment_before_next_command():
    assert parse_command_string('create_image:1,reboot') == ['create_image:1', 'reboot']


def test_unknown_command_raises():
    with pytest.raises(LinboRemoteError, match='not known'):
        parse_command_string('frobnicate')


def test_required_nr_missing_raises():
    with pytest.raises(LinboRemoteError, match='not valid'):
        parse_command_string('sync')


def test_required_nr_not_an_integer_raises():
    with pytest.raises(LinboRemoteError, match='not an integer'):
        parse_command_string('sync:abc')


def test_initcache_bad_dltype_raises():
    with pytest.raises(LinboRemoteError, match='not known'):
        parse_command_string('initcache:carrierpigeon')


def test_format_nr_not_an_integer_raises():
    with pytest.raises(LinboRemoteError, match='not an integer'):
        parse_command_string('format:x')


# --- hosts_in_group / hosts_in_room -----------------------------------------

DEVICES = [
    ('r100', 'r100-pc01', 'group1', '1'),
    ('r100', 'r100-pc02', 'group1', '2'),
    ('r200', 'r200-pc01', 'group2', '1'),
]


def test_hosts_in_group():
    assert hosts_in_group(DEVICES, 'group1') == ['r100-pc01', 'r100-pc02']


def test_hosts_in_group_no_match():
    assert hosts_in_group(DEVICES, 'nosuchgroup') == []


def test_hosts_in_room():
    assert hosts_in_room(DEVICES, 'r100') == ['r100-pc01', 'r100-pc02']


def test_hosts_in_room_no_match():
    assert hosts_in_room(DEVICES, 'r999') == []


# --- resolve_explicit_hosts --------------------------------------------------

def test_resolve_explicit_hosts_by_hostname():
    matched, skipped = resolve_explicit_hosts(['r100-pc01'], DEVICES)
    assert matched == ['r100-pc01']
    assert skipped == []


def test_resolve_explicit_hosts_unknown_hostname_skipped_as_not_pxe():
    matched, skipped = resolve_explicit_hosts(['r999-pc99'], DEVICES)
    assert matched == []
    assert skipped == ['Skipping r999-pc99, not a pxe host!']


def test_resolve_explicit_hosts_by_ip_resolves_via_injected_lookup():
    matched, skipped = resolve_explicit_hosts(
        ['10.16.100.1'], DEVICES, ip_to_hostname=lambda ip: 'r100-pc01',
    )
    assert matched == ['r100-pc01']
    assert skipped == []


def test_resolve_explicit_hosts_ip_lookup_fails():
    matched, skipped = resolve_explicit_hosts(
        ['10.16.100.99'], DEVICES, ip_to_hostname=lambda ip: None,
    )
    assert matched == []
    assert skipped == ['Host 10.16.100.99 not found!']


def test_resolve_explicit_hosts_with_school_prefix():
    prefixed_devices = [
        ('r100', 'myschool-r100-pc01', 'group1', '1'),
    ]
    matched, skipped = resolve_explicit_hosts(
        ['r100-pc01'], prefixed_devices, school='myschool',
    )
    assert matched == ['myschool-r100-pc01']
    assert skipped == []


def test_resolve_explicit_hosts_mixed_list():
    matched, skipped = resolve_explicit_hosts(
        ['r100-pc01', 'bogus-host'], DEVICES,
    )
    assert matched == ['r100-pc01']
    assert skipped == ['Skipping bogus-host, not a pxe host!']


# --- build_onboot_cmds -------------------------------------------------------

def test_build_onboot_cmds_plain():
    assert build_onboot_cmds(['sync:1', 'reboot']) == 'sync:1,reboot'


def test_build_onboot_cmds_with_noauto_and_disablegui():
    assert build_onboot_cmds(['sync:1'], noauto=True, disablegui=True) == 'sync:1,noauto,disablegui'


def test_build_onboot_cmds_with_secrets_line():
    assert build_onboot_cmds(
        ['upload_image:1'], secrets_line='linbo:somehash',
    ) == 'linbo:somehash,upload_image:1'


def test_build_onboot_cmds_noauto_only_no_commands():
    assert build_onboot_cmds([], noauto=True) == 'noauto'
