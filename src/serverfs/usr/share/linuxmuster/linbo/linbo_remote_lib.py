#!/usr/bin/python3
#
# Filename     : linbo_remote_lib.py
# Description  : Pure, testable helper functions for linbo-remote: the
#                cmd:nr:msg command-string parser, host resolution
#                (group/room/explicit list) and onboot command-file
#                assembly. Step 1 of the linbo-remote Python rewrite
#                (issue #169) - the tmux/SSH execution engine (step 2)
#                stays untouched for now.
# Signed-off by: thomas@linuxmuster.net
# Assisted by  : Claude
# Date         : 20260902
#
"""
Helper functions for the linbo-remote Python rewrite.

Everything in here except `get_group_room_devices()` is a pure function: no
filesystem, network or subprocess access, so it can be unit-tested with
plain fixture data (see tests/python/test_linbo_remote_lib.py). The
`linuxmuster_base7` import (needed to read devices.csv) is done lazily
inside `get_group_room_devices()` only, so importing this module - and
testing everything else - does not require linuxmuster-base7 to be
installed.

Command-string wire format
---------------------------
`parse_command_string()` returns the *logical* normalized commands (e.g.
`create_image:1:"my comment"` with real quote characters). How step 2 embeds
that into whatever it ends up generating for the client-side SSH call
(quoting/escaping for a shell, or an argv list if it stops shelling out
altogether) is that step's concern, not this parser's.
"""

import re

DOWNLOAD_TYPES = ('multicast', 'rsync', 'torrent')

# Commands accepted for -c/-p, grouped by their argument shape - mirrors the
# `case "$cmd" in ...` block in the original bash parser.
_NO_ARG_COMMANDS = ('label', 'partition', 'reboot', 'halt')
_REQUIRED_NR_COMMANDS = ('new', 'sync', 'start', 'postsync', 'prestart', 'upload_image', 'upload_qdiff')
_OPTIONAL_NR_COMMANDS = ('format',)
_COMMENT_COMMANDS = ('create_image', 'create_qdiff')
_INITCACHE_COMMAND = 'initcache'

KNOWN_COMMANDS = (
    _NO_ARG_COMMANDS + _REQUIRED_NR_COMMANDS + _OPTIONAL_NR_COMMANDS
    + _COMMENT_COMMANDS + (_INITCACHE_COMMAND,)
)


class LinboRemoteError(ValueError):
    """Raised for an invalid -c/-p command string or host selection.

    Carries a human-readable message equivalent to what the bash version
    passed to usage(); the CLI layer decides how to present it (print
    "Usage: ..." plus this message, same as today).
    """


def _split_head(text):
    """Return the leading token of `text`, up to the first ':' or ','."""
    return text.split(':', 1)[0].split(',', 1)[0]


def _extract_token(remaining):
    """Consume a leading ':<token>' and return (token, rest)."""
    rest = remaining[1:]
    token = _split_head(rest)
    return token, rest[len(token):]


def _extract_nr(remaining):
    """Consume a leading ':<nr>' where <nr> must be a plain non-negative integer."""
    nr, rest = _extract_token(remaining)
    if not nr.isdigit():
        raise LinboRemoteError(f'{nr} is not an integer variable!')
    return nr, rest


def _extract_comment(remaining):
    """
    Consume a leading ':<comment>', where <comment> may itself contain commas.

    Mirrors the original parser's own ambiguity rather than fixing it: since
    commands are comma-separated, a comment is truncated at the first
    occurrence of ",<knowncommandname>" - a comment whose text happens to
    contain that exact sequence gets cut there too, same as in bash.
    """
    comment_full = remaining[1:].split(':', 1)[0]
    earliest = None
    for name in KNOWN_COMMANDS:
        idx = comment_full.find(f',{name}')
        if idx != -1 and (earliest is None or idx < earliest):
            earliest = idx
    comment = comment_full if earliest is None else comment_full[:earliest]
    rest = remaining[len(':' + comment):]
    return comment, rest


def parse_command_string(cmds):
    """
    Parse a -c/-p command-list string (e.g. "format:2,sync:1,reboot") into a
    list of normalized command strings ready to be sent one-by-one to
    linbo_wrapper, e.g. ["format:2", "sync:1", "reboot"].

    Raises LinboRemoteError with a human-readable message on anything the
    original bash parser would have rejected via usage().
    """
    commands = []
    remaining = cmds
    while remaining:
        cmd = _split_head(remaining)
        if cmd not in KNOWN_COMMANDS:
            raise LinboRemoteError(f'Command "{cmd}" is not known!')
        remaining = remaining[len(cmd):]
        entry = cmd

        if cmd in _OPTIONAL_NR_COMMANDS:
            if remaining[:1] == ':':
                nr, remaining = _extract_nr(remaining)
                entry = f'{cmd}:{nr}'

        elif cmd in _REQUIRED_NR_COMMANDS:
            if remaining[:1] != ':':
                raise LinboRemoteError(f'Command string "{remaining}" is not valid!')
            nr, remaining = _extract_nr(remaining)
            entry = f'{cmd}:{nr}'

        elif cmd == _INITCACHE_COMMAND:
            if remaining[:1] == ':':
                dltype, remaining = _extract_token(remaining)
                if dltype not in DOWNLOAD_TYPES:
                    raise LinboRemoteError(f'{dltype} is not known!')
                entry = f'{cmd}:{dltype}'

        elif cmd in _COMMENT_COMMANDS:
            nr, remaining = _extract_nr(remaining)
            entry = f'{cmd}:{nr}'
            if remaining[:1] == ':':
                comment, remaining = _extract_comment(remaining)
                entry = f'{entry}:"{comment}"'

        # label/partition/reboot/halt: no arguments, nothing further to consume

        commands.append(entry)

        # remove one separating comma between commands, if present
        if remaining[:1] == ',':
            remaining = remaining[1:]

    return commands


def _is_valid_hostname(name):
    """
    Same rule as linuxmuster-base7's isValidHostname(): plain, self-contained
    here (not imported) since it's a trivial syntax check with no I/O of its
    own - reusing base7's version would only add a cross-repo dependency for
    two lines of regex.
    """
    try:
        if len(name) > 63 or name[0] == '-' or name[-1] == '-':
            return False
        return bool(re.match(r'[a-z0-9\-]*$', name, re.IGNORECASE))
    except (IndexError, TypeError):
        return False


def _is_valid_ipv4(ip):
    """Same rule as linuxmuster-base7's isValidHostIpv4(), self-contained (see _is_valid_hostname)."""
    try:
        octets = ip.split('.')
        if len(octets) != 4:
            return False
        values = [int(o) for o in octets]
        if values[0] == 0 or any(v > 254 for v in (values[0], values[3])):
            return False
        return all(0 <= v <= 255 for v in values)
    except (ValueError, AttributeError):
        return False


def hosts_in_group(devices, group):
    """
    devices: rows as returned by get_group_room_devices(), i.e.
        (room, hostname, group, pxeflag) tuples, already pxe-flag-filtered
        and school-prefixed by getDevicesArray().
    Returns the hostnames belonging to `group`, in devices.csv order.
    """
    return [row[1] for row in devices if row[2] == group]


def hosts_in_room(devices, room):
    """Same as hosts_in_group(), but matching the room field (column 0)."""
    return [row[1] for row in devices if row[0] == room]


def resolve_explicit_hosts(items, devices, school='default-school', ip_to_hostname=None):
    """
    Resolve a -i <i1,i2,...> list of hostnames/IPs against `devices`.

    devices: rows as returned by get_group_room_devices(), already pxe-flag
        filtered and school-prefixed.
    ip_to_hostname: callable(ip) -> short hostname or None, used only for
        tokens that are a valid IP rather than a valid hostname. Defaults to
        `default_ip_to_hostname` (reverse DNS); injectable for tests.

    Returns (matched_hostnames, skip_messages). `skip_messages` mirrors the
    two kinds of skip line the bash version printed per unusable token:
    "Host <i> not found!" (no hostname could be derived at all) and
    "Skipping <i>, not a pxe host!" (hostname derived, but absent or not
    pxe-flagged in devices.csv).
    """
    if ip_to_hostname is None:
        ip_to_hostname = default_ip_to_hostname

    prefix = f'{school}-' if school != 'default-school' else ''

    def unprefixed(hostname):
        if prefix and hostname.startswith(prefix):
            return hostname[len(prefix):]
        return hostname

    by_bare_hostname = {unprefixed(row[1]): row[1] for row in devices}

    matched = []
    skipped = []
    for item in items:
        hostname = None
        if _is_valid_hostname(item):
            hostname = item
        elif _is_valid_ipv4(item):
            resolved = ip_to_hostname(item)
            hostname = unprefixed(resolved) if resolved else None

        if not hostname:
            skipped.append(f'Host {item} not found!')
            continue

        full_hostname = by_bare_hostname.get(hostname)
        if full_hostname is None:
            skipped.append(f'Skipping {item}, not a pxe host!')
            continue

        matched.append(full_hostname)

    return matched, skipped


def default_ip_to_hostname(ip):
    """
    Reverse-resolve an IP to its short hostname - the Python equivalent of
    the original `nslookup "$IP" | head -1 | awk '{print $4}' | awk -F. '{print $1}'`
    pipeline (domain part discarded, school-prefix stripping is handled by
    the caller). Returns None if reverse DNS fails.
    """
    import socket
    try:
        fqdn = socket.gethostbyaddr(ip)[0]
    except OSError:
        return None
    return fqdn.split('.', 1)[0]


def get_group_room_devices(school='default-school'):
    """
    Read devices.csv for `school` via linuxmuster-base7 and return
    (room, hostname, group, pxeflag) rows, already filtered to pxe-flags 1/2
    (the linbo-related ones) and school-prefixed - the same filtering
    `getDevicesArray()` already does, so hosts_in_group()/hosts_in_room()/
    resolve_explicit_hosts() don't have to.
    """
    from linuxmuster_base7.functions import getDevicesArray
    return getDevicesArray(fieldnrs='0,1,2,10', pxeflag='1,2', school=school)


def build_onboot_cmds(commands, noauto=False, disablegui=False, secrets_line=None):
    """
    Assemble the comma-separated onboot command string written to a client's
    linbocmd/<hostname>.cmd file (-p mode).

    secrets_line: the "linbo:<password-hash>" line from /etc/rsyncd.secrets,
        prepended when the command list contains an upload command - same as
        the bash version does. Passing it is the caller's decision (it knows
        whether an upload_image/upload_qdiff command is present); this
        function only assembles the string.

    The literal "noauto"/"disablegui" tokens must not change - linbofs'
    client-side init.sh greps for them by that exact name.
    """
    parts = []
    if secrets_line:
        parts.append(secrets_line)
    parts.extend(commands)
    if noauto:
        parts.append('noauto')
    if disablegui:
        parts.append('disablegui')
    return ','.join(parts)
