#!/usr/bin/python3
#
# Filename     : linbo_remote_cli.py
# Description  : linbo-remote's CLI orchestration - option parsing, host
#                resolution, onboot file writing, wake-on-LAN and the
#                tmux/SSH dispatch for -c/-p. The actual /usr/sbin/linbo-remote
#                executable is a thin launcher that calls main() here (kept
#                importable/testable, unlike a hyphenated top-level script).
#                Step 2 of the linbo-remote Python rewrite (issue #169).
# Signed-off by: thomas@linuxmuster.net
# Assisted by  : Claude
# Date         : 20260902
#
"""
linbo-remote's CLI orchestration.

Preserves the external contract of the original bash implementation
(exit codes, key stdout strings, tmux session/logfile naming, onboot
.cmd-file format - see the tracking issue for the full consumer list),
while fixing two confirmed bugs rather than replicating them (see issue
#169 step 2 notes and tests/python/README.md):

- create_image/create_qdiff comments containing a space used to be
  truncated at the first space when relayed to linbo_wrapper
  (render_remote_script() in linbo_remote_lib.py quotes the whole
  command token now).
- `-u` (use broadcast address for WOL) used to accumulate every
  previously resolved host's `-i <bcaddr>` into the same wakeonlan
  invocation instead of using a fresh one per host.

Also deliberately changed: `-h`/`--help` exits 0 (the original exited 1
unconditionally from usage()); no known consumer depends on that exit
code, and it isn't a rejected invocation.
"""

import getopt
import glob
import grp
import os
import pwd
import shlex
import shutil
import subprocess
import sys
import time

sys.path.insert(0, '/usr/lib/linuxmuster')
sys.path.insert(0, '/usr/share/linuxmuster/linbo')
import environment  # noqa: E402

import linbo_remote_lib as lib  # noqa: E402

SECRETS_FILE = '/etc/rsyncd.secrets'
TMPDIR = '/var/tmp'
SESSION_MATCH = '_linbo-remote'


# --- usage/help --------------------------------------------------------------

def print_usage(msg=None):
    print()
    print('Usage: linbo-remote <options>')
    print()
    print('Options:')
    print()
    print(' -h                 Show this help.')
    print(' -a <hostname>      Attach the running tmux session for this hostname.')
    print(' -b <sec>           Wait <sec> second(s) between sending wake-on-lan magic')
    print('                    packets to the particular hosts. Must be used in')
    print('                    conjunction with "-w".')
    print(' -c <cmd1,cmd2,...> Comma separated list of linbo commands transfered')
    print('                    per ssh direct to the client(s). Gui will be disabled')
    print('                    during execution.')
    print(' -d                 Disables gui on next boot.')
    print(' -g <group>         All hosts of this hostgroup will be processed.')
    print(' -i <i1,i2,...>     Single ip or hostname or comma separated list of ips')
    print('                    or hostnames of clients to be processed.')
    print(' -l                 List current linbo-remote tmux sessions.')
    print(' -n                 Bypasses start.conf configured auto functions')
    print('                    (partition, format, initcache, start) on next boot.')
    print(' -r <room>          All hosts of this room will be processed.')
    print(' -s <school>        Select a school other than default-school')
    print(' -p <cmd1,cmd2,...> Create an onboot command file executed automatically')
    print('                    once next time the client boots.')
    print(' -u                 Use broadcast address for wol additionally.')
    print(' -w <sec>           Send wake-on-lan magic packets to the client(s)')
    print('                    and wait <sec> seconds before executing the')
    print('                    commands given with "-c" or in case of "-p" after')
    print('                    the creation of the pxe boot files.')
    print()
    print('Important: * Options "-r", "-g" and "-i" exclude each other, "-c" and')
    print('             "-p" as well.')
    print()
    print('Supported commands for -c or -p options are:')
    print()
    print('partition                : Writes the partition table.')
    print('label                    : Labels all partitions defined in start.conf.')
    print('                           Note: Partitions have to be formatted.')
    print('format                   : Writes the partition table and formats all')
    print('                           partitions.')
    print('format:<#>               : Writes the partition table and formats only')
    print('                           partition nr <#>.')
    print('initcache:<dltype>       : Updates local cache. <dltype> is one of')
    print('                           rsync|multicast|torrent.')
    print('                           If dltype is not specified it is read from')
    print('                           start.conf.')
    print('sync:<#>                 : Syncs the operating system on position nr <#>.')
    print('new:<#>                  : Clean sync of the operating system on position nr <#>')
    print('                           (formats the according partition before).')
    print('postsync:<#>             : Invokes postsync script of the os on position nr <#>.')
    print('start:<#>                : Starts the operating system on pos. nr <#>.')
    print('prestart:<#>             : Invokes prestart script of the os on position nr <#>.')
    print('create_image:<#>:<"msg"> : Creates a full image from operating system nr <#>.')
    print('upload_image:<#>         : Uploads a full image from operating system nr <#>.')
    print('create_qdiff:<#>:<"msg"> : Creates a differential image from operating system nr <#>.')
    print('upload_qdiff:<#>         : Uploads a differential image from operating system nr <#>.')
    print('reboot                   : Reboots the client.')
    print('halt                     : Shuts the client down.')
    print()
    print('<"msg"> is an optional image comment.')
    print('The position numbers are related to the position in start.conf.')
    print('The commands were sent per ssh to the linbo_wrapper on the client and processed')
    print('in the order given on the commandline.')
    print('create_* and upload_* commands cannot be used with hostlists, -r and -g options.')
    if msg:
        print()
        print(msg)


def usage_error(msg=None):
    print_usage(msg)
    sys.exit(1)


# --- tmux session listing/attach (-l/-a) -------------------------------------

def list_sessions():
    result = subprocess.run(['tmux', 'list-sessions'], capture_output=True, text=True, check=False)
    for line in result.stdout.splitlines():
        if SESSION_MATCH in line:
            print(line)


def attach_session(hostname):
    target = lib.tmux_attach_target(hostname)
    result = subprocess.run(['tmux', 'list-sessions'], capture_output=True, text=True, check=False)
    if not any(line.startswith(target) for line in result.stdout.splitlines()):
        usage_error(f'There is no session for host {hostname}.')
    rc = subprocess.run(['tmux', 'attach', '-t', target], check=False).returncode
    if rc != 0:
        sys.exit(1)


# --- online check / waiting --------------------------------------------------

def is_online(hostname):
    result = subprocess.run(
        [
            '/usr/sbin/linbo-ssh', '-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=no',
            '-o', 'ConnectTimeout=1', hostname, '/bin/ls', '/start.conf',
        ],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False,
    )
    return result.returncode == 0


def do_wait(seconds, message, leading_blank_line=False):
    if not seconds:
        return
    if leading_blank_line:
        print()
    print(f'{message} ', end='', flush=True)
    for _ in range(seconds):
        time.sleep(1)
        print('.', end='', flush=True)
    print()


# --- onboot command files (-p, and/or -n/-d alone) ---------------------------

def onboot_cmd_file(hostname):
    return os.path.join(environment.LINBODIR, 'linbocmd', f'{hostname}.cmd')


def read_secrets_line():
    """The "linbo:<hash>" line from /etc/rsyncd.secrets, or None if absent."""
    try:
        with open(SECRETS_FILE) as f:
            for line in f:
                if line.startswith('linbo:'):
                    return line.strip()
    except OSError:
        pass
    return None


def fix_onboot_dir_permissions():
    """chown nobody:root, chmod 660 on every file in linbocmd/ - matches the
    bash version applying this to the whole directory, not just the files
    just written."""
    try:
        uid = pwd.getpwnam('nobody').pw_uid
        gid = grp.getgrnam('root').gr_gid
    except KeyError:
        return
    for path in glob.glob(os.path.join(environment.LINBODIR, 'linbocmd', '*')):
        try:
            os.chown(path, uid, gid)
            os.chmod(path, 0o660)
        except OSError:
            continue


def write_onboot_files(hosts, onboot_string):
    print()
    print('Preparing onboot linbo tasks:')
    for host in hosts:
        print(f' {host} ... ', end='')
        with open(onboot_cmd_file(host), 'w') as f:
            f.write(onboot_string + '\n')
        print('Done.')
    fix_onboot_dir_permissions()


# --- wake-on-lan --------------------------------------------------------------

def send_wol(mac, extra_args=None):
    wakeonlan_bin = shutil.which('wakeonlan')
    if not wakeonlan_bin:
        print('wakeonlan not found!')
        sys.exit(1)
    cmd = [wakeonlan_bin] + list(extra_args or []) + [mac]
    subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)


def wake_hosts(hosts, school, between, use_bcaddr, is_direct, is_onboot):
    print()
    print('Trying to wake up:')
    try:
        from linuxmuster_base7.functions import getSetupValue
        basedn = getSetupValue('basedn')
    except Exception:
        basedn = None

    prefix = f'{school}-' if school != 'default-school' else ''
    for index, host in enumerate(hosts):
        if between and index != 0:
            do_wait(between, '  ')
        print(f' {host} ... ', end='')
        bare_host = host[len(prefix):] if prefix and host.startswith(prefix) else host
        mac, ip = lib.resolve_wol_target(bare_host, basedn)

        # a fresh -i <bcaddr> per host, not accumulated across the loop
        # (the original bash implementation reused and kept extending the
        # same $WOL variable across iterations - see module docstring)
        extra_args = []
        if use_bcaddr and lib.is_valid_ipv4(ip):
            bcaddr = lib.get_broadcast_address(ip)
            if bcaddr and lib.is_valid_ipv4(bcaddr):
                extra_args = ['-i', bcaddr]

        if not lib.is_valid_mac(mac):
            print(f'{mac} is no valid mac address!' if mac else 'No mac address found!')
            continue

        if is_onboot:
            if is_online(host):
                print('Client is already online, rebooting ...')
                subprocess.run(
                    [
                        '/usr/sbin/linbo-ssh', '-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=no',
                        host, 'reboot',
                    ],
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False,
                )
            else:
                send_wol(mac, extra_args)
                print('Sent.')
        elif is_direct:
            send_wol(mac, extra_args)
            print('Sent.')
        else:
            send_wol(mac, extra_args)
            print('Sent.')


# --- direct command dispatch (-c) --------------------------------------------

def send_cmds(hosts, commands, wait, secrets_uploaded):
    if wait:
        do_wait(wait, f'Waiting {wait} second(s) for client(s) to boot', leading_blank_line=True)

    print()
    print('Sending command(s) to:')
    for host in hosts:
        print(f' {host} ... ', end='')

        if not is_online(host):
            print('Not online, host skipped.')
            continue

        if secrets_uploaded:
            print('Uploading secrets ... ', end='')
            subprocess.run(
                ['/usr/sbin/linbo-scp', SECRETS_FILE, f'{host}:/tmp'],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False,
            )

        session_name = lib.tmux_session_name(host)
        logfile = os.path.join(environment.LINBOLOGDIR, session_name)
        script_path = os.path.join(TMPDIR, f'{os.getpid()}.{host}.sh')

        script_text = lib.render_remote_script(host, commands, script_path, secrets_uploaded=secrets_uploaded)
        with open(script_path, 'w') as f:
            f.write(script_text)
        os.chmod(script_path, 0o755)

        subprocess.run(
            [
                'tmux', 'new', '-Ads', session_name, script_path,
                ';', 'pipe-pane', f'cat > {shlex.quote(logfile)}',
            ],
            check=False,
        )
        pid_result = subprocess.run(['pgrep', '-f', logfile], capture_output=True, text=True, check=False)
        pid = pid_result.stdout.split()[0] if pid_result.stdout.strip() else 'unknown'
        print(f'Started with PID {pid}. Log see {logfile}.')


def test_onboot(hosts, wait):
    do_wait(wait, f'Waiting {wait} second(s) for client(s) to boot', leading_blank_line=True)
    print()
    print('Verifying onboot tasks:')
    for host in hosts:
        print(f' {host} ... ', end='')
        path = onboot_cmd_file(host)
        if os.path.exists(path):
            os.remove(path)
            print('Not done, host skipped!')
        else:
            print('Ok!')


def test_online(hosts, wait):
    do_wait(wait, f'Waiting {wait} second(s) for client(s) to boot', leading_blank_line=True)
    print()
    print('Testing if clients have booted:')
    for host in hosts:
        print(f' {host} ... ', end='')
        print('Online!' if is_online(host) else 'Not online!')


# --- linuxmuster-base7 availability -------------------------------------------

def ensure_base7_available():
    """
    linbo-remote needs linuxmuster-base7 for devices.csv/subnet lookups
    (getDevicesArray, getSetupValue, getIpBcAddress, all used downstream via
    linbo_remote_lib.py's lazy imports) - but linuxmuster-linbo7 is also used
    standalone, without linuxmuster-base7 installed. That's exactly why
    debian/control lists it under Recommends, not Depends (a hard Depends
    would also create a package cycle: linuxmuster-base7 itself Depends on
    linuxmuster-linbo7). So this can't be caught at install time - fail
    fast with a clear message instead of a bare ImportError traceback
    partway through host resolution.

    Not needed for -h/-a/-l, which touch neither devices.csv nor subnets.csv
    - callers check those first and return before ever reaching this.
    """
    try:
        import linuxmuster_base7.functions  # noqa: F401
    except ImportError:
        print('linbo-remote requires linuxmuster-base7 to be installed (for devices.csv/subnet lookups).')
        sys.exit(1)


# --- main ---------------------------------------------------------------------

def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv

    try:
        opts, _ = getopt.getopt(argv, 'a:b:c:dg:hi:lnp:r:uw:s:')
    except getopt.GetoptError as error:
        usage_error(str(error))
        return 1  # unreachable, keeps type-checkers happy

    attach_host = None
    do_list = False
    between_raw = None
    direct_cmds = None
    disablegui = False
    group = None
    hosts_raw = None
    noauto = False
    onboot_cmds = None
    room = None
    school = 'default-school'
    use_bcaddr = False
    wait_raw = None

    for opt, val in opts:
        if opt == '-h':
            print_usage()
            return 0
        elif opt == '-a':
            attach_host = val
        elif opt == '-l':
            do_list = True
        elif opt == '-b':
            between_raw = val
        elif opt == '-c':
            direct_cmds = val
        elif opt == '-d':
            disablegui = True
        elif opt == '-g':
            group = val
        elif opt == '-i':
            hosts_raw = val
        elif opt == '-n':
            noauto = True
        elif opt == '-p':
            onboot_cmds = val
        elif opt == '-r':
            room = val
        elif opt == '-u':
            use_bcaddr = True
        elif opt == '-w':
            wait_raw = val
        elif opt == '-s':
            school = val

    if attach_host is not None:
        attach_session(attach_host)
        return 0
    if do_list:
        list_sessions()
        return 0

    ensure_base7_available()

    # --- option-combination validation (mirrors the bash checks 1:1) -------
    if not group and not hosts_raw and not room:
        usage_error('No hosts, no group, no room defined!')
    if group and hosts_raw:
        usage_error('Group and hosts defined!')
    if group and room:
        usage_error('Group and room defined!')
    if direct_cmds and onboot_cmds:
        usage_error('Direct and onboot commands defined!')
    if not direct_cmds and not onboot_cmds and not wait_raw and not disablegui and not noauto:
        usage_error('No commands or wakeonlan defined!')

    wait = None
    if wait_raw is not None:
        if not wait_raw.isdigit():
            usage_error(f'{wait_raw} is not an integer variable!')
        wait = int(wait_raw)
        if not shutil.which('wakeonlan'):
            print('wakeonlan not found!')
            return 1
        if direct_cmds and wait == 0:
            wait = None

    between = None
    if between_raw is not None:
        if wait is None:
            usage_error('Option -b can only be used with -w!')
        if not between_raw.isdigit():
            usage_error(f'{between_raw} is not an integer variable!')
        between = int(between_raw)

    is_direct = bool(direct_cmds)
    is_onboot = bool(onboot_cmds)
    cmds_string = direct_cmds if is_direct else onboot_cmds

    # no upload or create commands for lists/groups/rooms
    is_multi_host_selection = bool(group) or bool(room) or (
        hosts_raw is not None and len([h for h in hosts_raw.split(',') if h]) > 1
    )
    try:
        parsed_cmds = lib.parse_command_string(cmds_string) if cmds_string else []
    except lib.LinboRemoteError as error:
        usage_error(str(error))
        return 1

    if is_multi_host_selection and any(
        c.startswith(('create_image', 'create_qdiff', 'upload_image', 'upload_qdiff')) for c in parsed_cmds
    ):
        usage_error('Upload or create cannot be used with lists!')

    needs_secrets = any(c.startswith(('upload_image', 'upload_qdiff')) for c in parsed_cmds)

    print()
    print('###')
    print(f'### linbo-remote ({os.getpid()}) start: {time.strftime("%c")}')
    print('###')

    # --- host resolution ----------------------------------------------------
    devices = lib.get_group_room_devices(school=school)
    if group:
        hosts = lib.hosts_in_group(devices, group)
        if not hosts:
            usage_error(f'No hosts in group {group}!')
    elif room:
        hosts = lib.hosts_in_room(devices, room)
        if not hosts:
            usage_error(f'No hosts in room {room}!')
    else:
        items = [h for h in hosts_raw.split(',') if h]
        hosts, skip_messages = lib.resolve_explicit_hosts(items, devices, school=school)
        for skip_message in skip_messages:
            print(skip_message)
        if not hosts:
            usage_error('No valid hosts in list!')

    # --- onboot command files (-p, and/or bare -n/-d) ------------------------
    secrets_line = read_secrets_line() if needs_secrets else None
    onboot_string = lib.build_onboot_cmds(
        parsed_cmds if is_onboot else [], noauto=noauto, disablegui=disablegui, secrets_line=secrets_line,
    )
    if onboot_string:
        write_onboot_files(hosts, onboot_string)

    # --- wake-on-lan ----------------------------------------------------------
    if wait is not None:
        wake_hosts(hosts, school, between, use_bcaddr, is_direct, is_onboot)

    # --- dispatch -------------------------------------------------------------
    if is_direct:
        send_cmds(hosts, parsed_cmds, wait, needs_secrets)
    if is_onboot and wait:
        test_onboot(hosts, wait)
    elif not is_onboot and not is_direct and wait:
        test_online(hosts, wait)

    print()
    print('###')
    print(f'### linbo-remote ({os.getpid()}) end: {time.strftime("%c")}')
    print('###')
    return 0


if __name__ == '__main__':
    sys.exit(main())
