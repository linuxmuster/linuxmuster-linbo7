#!/usr/bin/python3
#
# Filename     : linbo_remote_lib.py
# Description  : Helper functions for linbo-remote: the cmd:nr:msg command
#                parser, host resolution (group/room/explicit list), onboot
#                command-file assembly, per-host script rendering and
#                MAC/IP/broadcast-address resolution for wake-on-LAN.
#                Steps 1+2 of the linbo-remote Python rewrite (issue #169).
# Signed-off by: thomas@linuxmuster.net
# Assisted by  : Claude
# Date         : 20260902
#
"""
Helper functions for the linbo-remote Python rewrite.

Most functions here are pure: no filesystem, network or subprocess access,
so they can be unit-tested with plain fixture data (see
tests/python/test_linbo_remote_lib.py). The exceptions - anything that reads
devices.csv, queries Samba AD via ldbsearch, or shells out to arp/ldbsearch -
take their subprocess/lookup dependency as an injectable callable defaulting
to a real implementation, so the calling logic stays testable without a real
server environment; only the default implementations themselves are
untested (matching tests/shell's own "Wave 1 vs Wave 2" split - see
tests/python/README.md).

Command-string wire format
---------------------------
`parseCommandString()` returns the *logical* normalized commands (e.g.
`create_image:1:"my comment"` with real quote characters). `renderRemoteScript()`
is responsible for shell-quoting each command as a whole when embedding it
into the generated per-host script - unlike the original bash implementation,
which embedded the raw (backslash-escaped) command text unquoted, silently
truncating any create_image/create_qdiff comment at its first space (see
issue #169 step 2 notes; reproduced and fixed, not preserved).

Wake-on-LAN MAC/IP resolution deliberately queries Samba AD (via ldbsearch),
not devices.csv: for DHCP clients devices.csv only holds the literal string
"DHCP", while AD's sophomorixComputerMAC/-IP attributes are kept current by
the DHCP lease hook (see dhcpd-update-samba-dns.py) - devices.csv would not
give a usable IP for those hosts at all.
"""

import re
import shlex
import subprocess

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


def _splitHead(text):
    """Return the leading token of `text`, up to the first ':' or ','."""
    return text.split(':', 1)[0].split(',', 1)[0]


def _extractToken(remaining):
    """Consume a leading ':<token>' and return (token, rest)."""
    rest = remaining[1:]
    token = _splitHead(rest)
    return token, rest[len(token):]


def _extractNr(remaining):
    """Consume a leading ':<nr>' where <nr> must be a plain non-negative integer."""
    nr, rest = _extractToken(remaining)
    if not nr.isdigit():
        raise LinboRemoteError(f'{nr} is not an integer variable!')
    return nr, rest


def _extractComment(remaining):
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


def parseCommandString(cmds):
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
        cmd = _splitHead(remaining)
        if cmd not in KNOWN_COMMANDS:
            raise LinboRemoteError(f'Command "{cmd}" is not known!')
        remaining = remaining[len(cmd):]
        entry = cmd

        if cmd in _OPTIONAL_NR_COMMANDS:
            if remaining[:1] == ':':
                nr, remaining = _extractNr(remaining)
                entry = f'{cmd}:{nr}'

        elif cmd in _REQUIRED_NR_COMMANDS:
            if remaining[:1] != ':':
                raise LinboRemoteError(f'Command string "{remaining}" is not valid!')
            nr, remaining = _extractNr(remaining)
            entry = f'{cmd}:{nr}'

        elif cmd == _INITCACHE_COMMAND:
            if remaining[:1] == ':':
                dltype, remaining = _extractToken(remaining)
                if dltype not in DOWNLOAD_TYPES:
                    raise LinboRemoteError(f'{dltype} is not known!')
                entry = f'{cmd}:{dltype}'

        elif cmd in _COMMENT_COMMANDS:
            nr, remaining = _extractNr(remaining)
            entry = f'{cmd}:{nr}'
            if remaining[:1] == ':':
                comment, remaining = _extractComment(remaining)
                entry = f'{entry}:"{comment}"'

        # label/partition/reboot/halt: no arguments, nothing further to consume

        commands.append(entry)

        # remove one separating comma between commands, if present
        if remaining[:1] == ',':
            remaining = remaining[1:]

    return commands


def isValidHostname(name):
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


def isValidIpv4(ip):
    """Same rule as linuxmuster-base7's isValidHostIpv4(), self-contained (see isValidHostname)."""
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


def hostsInGroup(devices, group):
    """
    devices: rows as returned by getGroupRoomDevices(), i.e.
        (room, hostname, group, pxeflag) tuples, already pxe-flag-filtered
        and school-prefixed by getDevicesArray().
    Returns the hostnames belonging to `group`, in devices.csv order.
    """
    return [row[1] for row in devices if row[2] == group]


def hostsInRoom(devices, room):
    """Same as hostsInGroup(), but matching the room field (column 0)."""
    return [row[1] for row in devices if row[0] == room]


def resolveExplicitHosts(items, devices, school='default-school', ip_to_hostname=None):
    """
    Resolve a -i <i1,i2,...> list of hostnames/IPs against `devices`.

    devices: rows as returned by getGroupRoomDevices(), already pxe-flag
        filtered and school-prefixed.
    ip_to_hostname: callable(ip) -> short hostname or None, used only for
        tokens that are a valid IP rather than a valid hostname. Defaults to
        `defaultIpToHostname` (reverse DNS); injectable for tests.

    Returns (matched_hostnames, skip_messages). `skip_messages` mirrors the
    two kinds of skip line the bash version printed per unusable token:
    "Host <i> not found!" (no hostname could be derived at all) and
    "Skipping <i>, not a pxe host!" (hostname derived, but absent or not
    pxe-flagged in devices.csv).
    """
    if ip_to_hostname is None:
        ip_to_hostname = defaultIpToHostname

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
        if isValidHostname(item):
            hostname = item
        elif isValidIpv4(item):
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


def defaultIpToHostname(ip):
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


def getGroupRoomDevices(school='default-school'):
    """
    Read devices.csv for `school` via linuxmuster-base7 and return
    (room, hostname, group, pxeflag) rows, already filtered to pxe-flags 1/2
    (the linbo-related ones) and school-prefixed - the same filtering
    `getDevicesArray()` already does, so hostsInGroup()/hostsInRoom()/
    resolveExplicitHosts() don't have to.
    """
    from linuxmuster_base7.functions import getDevicesArray
    return getDevicesArray(fieldnrs='0,1,2,10', pxeflag='1,2', school=school)


def buildOnbootCmds(commands, noauto=False, disablegui=False, secrets_line=None):
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


# --- tmux session / logfile naming ------------------------------------------

def tmuxSessionName(hostname):
    """
    The name passed to `tmux new -Ads` when starting a host's session, and
    the per-host logfile's basename (LINBOLOGDIR/<this>). tmux itself
    rewrites the '.' to '_' internally for the *session* it actually
    creates - see tmuxAttachTarget() for the name to use when looking an
    existing session back up. The logfile is a plain path, not subject to
    tmux's renaming, so it keeps the dot.
    """
    return f'{hostname}.linbo-remote'


def tmuxAttachTarget(hostname):
    """The actual tmux session name to use for `-a`/`-l` (attach/list) - see tmuxSessionName()."""
    return f'{hostname}_linbo-remote'


# --- per-host remote script rendering (-c direct-send mode) -----------------

SSH_CMD = '/usr/sbin/linbo-ssh -o BatchMode=yes -o StrictHostKeyChecking=no'
WRAPPER = '/usr/bin/linbo_wrapper'

_BACKGROUNDED_COMMAND_PREFIXES = ('start', 'reboot', 'halt', 'poweroff')


def renderRemoteScript(hostname, commands, script_path, secrets_uploaded=False):
    """
    Build the per-host shell script executed inside a tmux session for -c
    (direct) mode: disables the GUI, runs each normalized command
    (parseCommandString() output) against linbo_wrapper in order via
    linbo-ssh, restores the GUI, then removes itself.

    start*/reboot/halt commands are backgrounded with a 10s grace period
    (the client's SSH connection can drop mid-command when it reboots)
    instead of being awaited like every other command; RC stops being
    checked for anything queued after one of these.

    Each command is shell-quoted as a *whole* token (shlex.quote) rather than
    embedded raw - this is what makes a multi-word create_image/create_qdiff
    comment survive the round-trip through linbo-ssh's own unquoted argument
    forwarding intact (verified against a simulated ssh remote-command-join +
    remote-shell-reparse); the original bash implementation embedded it
    unquoted and silently truncated it at the first space.
    """
    lines = ['#!/bin/bash', f'{SSH_CMD} {hostname} gui_ctl disable', 'RC=0']
    has_backgrounded = False
    for index, cmd in enumerate(commands):
        if index > 0:
            lines.append('sleep 3')
        quoted = shlex.quote(cmd)
        if cmd.startswith(_BACKGROUNDED_COMMAND_PREFIXES):
            has_backgrounded = True
            lines.append(f'[ $RC = 0 ] && {SSH_CMD} {hostname} {WRAPPER} {quoted} &')
            lines.append('sleep 10')
        else:
            lines.append(f'[ $RC = 0 ] && {SSH_CMD} {hostname} {WRAPPER} {quoted} || RC=1')
    if secrets_uploaded and not has_backgrounded:
        lines.append(f'{SSH_CMD} {hostname} /bin/rm -f /tmp/rsyncd.secrets')
    lines.append(f'{SSH_CMD} {hostname} gui_ctl restore')
    lines.append(f'rm -f {shlex.quote(script_path)}')
    lines.append('exit $RC')
    return '\n'.join(lines) + '\n'


# --- wake-on-LAN target resolution -------------------------------------------

def isValidMac(mac):
    """Same rule as linuxmuster-base7's isValidMac(), self-contained (see isValidHostname)."""
    try:
        return bool(re.match(r'[0-9a-f]{2}([-:])[0-9a-f]{2}(\1[0-9a-f]{2}){4}$', mac.lower()))
    except (TypeError, AttributeError):
        return False


def defaultLdbsearch(filter_expr, attribute, basedn):
    """
    Query a single attribute from Samba's local AD database via ldbsearch -
    the Python equivalent of helperfunctions.sh's $LDBSEARCH pipeline
    (`ldbsearch -b OU=SCHOOLS,<basedn> -H /var/lib/samba/private/sam.ldb
    <filter> <attribute> | grep ^<attribute> | awk '{print $2}'`). Returns
    the attribute value, or None if not found or ldbsearch failed.
    """
    cmd = [
        'ldbsearch', '-b', f'OU=SCHOOLS,{basedn}', '-H', '/var/lib/samba/private/sam.ldb',
        filter_expr, attribute,
    ]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, check=False)
    except OSError:
        return None
    prefix = f'{attribute}:'
    for line in result.stdout.splitlines():
        if line.startswith(prefix):
            return line[len(prefix):].strip()
    return None


def getMacFromAd(query, basedn, ldbsearch=None):
    """
    Resolve a device's MAC address (sophomorixComputerMAC) from Samba AD by
    hostname, IP or MAC - mirrors helperfunctions.sh's get_mac(). `ldbsearch`
    is injectable (see defaultLdbsearch); defaults to a real AD query.
    """
    ldbsearch = ldbsearch or defaultLdbsearch
    attr = 'sophomorixComputerMAC'
    if isValidIpv4(query):
        return ldbsearch(f'(sophomorixComputerIP={query})', attr, basedn)
    if isValidHostname(query):
        return ldbsearch(f'(sophomorixDnsNodename={query.lower()})', attr, basedn)
    if isValidMac(query):
        return ldbsearch(f'({attr}={query.upper()})', attr, basedn)
    return None


def getIpFromAd(query, basedn, ldbsearch=None):
    """Resolve a device's IP (sophomorixComputerIP) from Samba AD - mirrors helperfunctions.sh's get_ip()."""
    ldbsearch = ldbsearch or defaultLdbsearch
    attr = 'sophomorixComputerIP'
    if isValidHostname(query):
        return ldbsearch(f'(sophomorixDnsNodename={query.lower()})', attr, basedn)
    if isValidMac(query):
        return ldbsearch(f'(sophomorixComputerMAC={query.upper()})', attr, basedn)
    if isValidIpv4(query):
        return ldbsearch(f'({attr}={query})', attr, basedn)
    return None


def defaultArpLookup(hostname):
    """
    Resolve a hostname's IP from the local ARP cache - the Python equivalent
    of `arp -a "$host" | awk -F\\( '{print $2}' | awk -F\\) '{print $1}'`.
    Returns None if not found or the `arp` binary isn't available.
    """
    try:
        result = subprocess.run(['arp', '-a', hostname], capture_output=True, text=True, check=False)
    except OSError:
        return None
    match = re.search(r'\(([^)]+)\)', result.stdout)
    return match.group(1) if match else None


def defaultDhcpLeaseMac(ip, leases_file='/var/lib/dhcp/dhcpd.leases'):
    """
    Resolve the most recent MAC address leased to `ip` from the ISC DHCP
    leases file - the Python equivalent of the bash pipeline
    `grep -A10 "$ip" dhcpd.leases | grep "hardware ethernet" |
     awk '{print $3}' | awk -F\\; '{print $1}' | tr A-Z a-z`.
    Returns None if not found or the leases file doesn't exist.
    """
    try:
        with open(leases_file) as f:
            lines = f.readlines()
    except OSError:
        return None
    for index, line in enumerate(lines):
        if ip in line:
            for candidate in lines[index:index + 11]:
                if 'hardware ethernet' in candidate:
                    fields = candidate.split()
                    if len(fields) >= 3:
                        return fields[2].rstrip(';').lower()
            break
    return None


def resolveWolTarget(hostname, basedn, ldbsearch=None, arp_lookup=None, dhcp_lease_mac=None):
    """
    Resolve the MAC address and IP to use for waking `hostname` up,
    replicating the fallback chain in linbo-remote's WOL loop:
    1. MAC/IP from Samba AD (current for DHCP clients, unlike devices.csv
       which only holds the literal string "DHCP" for them).
    2. If the AD IP isn't a valid IPv4, fall back to the local ARP cache.
    3. If the AD MAC isn't valid, fall back to the ISC DHCP leases file for
       the (possibly ARP-resolved) IP.

    Returns (mac, ip) - either may be None if every source failed.
    """
    arp_lookup = arp_lookup or defaultArpLookup
    dhcp_lease_mac = dhcp_lease_mac or defaultDhcpLeaseMac

    mac = getMacFromAd(hostname, basedn, ldbsearch=ldbsearch)
    ip = getIpFromAd(hostname, basedn, ldbsearch=ldbsearch)

    if not isValidIpv4(ip):
        ip = arp_lookup(hostname)

    if not isValidMac(mac) and ip:
        mac = dhcp_lease_mac(ip)

    return mac, ip


def getBroadcastAddress(ip):
    """
    The subnet broadcast address for `ip`, via linuxmuster-base7's
    getIpBcAddress() (subnets.csv-based) - imported lazily, see
    getGroupRoomDevices(). Returns None if it can't be determined (no
    matching subnet, or linuxmuster-base7 unavailable).
    """
    try:
        from linuxmuster_base7.functions import getIpBcAddress
        return getIpBcAddress(ip)
    except Exception:
        return None
