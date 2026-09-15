#!/usr/bin/python3
#
# Filename     : linbo_mkgrubimg.py
# Description  : Creates a host specific image for grub network boot,
#                stored in /srv/linbo/boot/grub/hostcfg/<hostname>.img.
#                The actual /usr/sbin/linbo-mkgrubimg executable is a thin
#                launcher that calls main() here (kept importable/testable,
#                unlike a hyphenated top-level script), analogous to
#                linbo-remote/linbo_remote_cli.py.
# Signed-off by: thomas@linuxmuster.net
# Assisted by  : Claude
# Date         : 20260903
#

import configparser
import getopt
import glob
import os
import re
import sys

sys.path.insert(0, '/usr/lib/linuxmuster')
import environment  # noqa: E402

from linuxmuster_base7.functions import getHostname, getStartconfOption, readTextfile, writeTextfile  # noqa: E402

# GRUB netboot module lists. Mirrors mkgrubnetdir.sh's GRUBI386MODS/GRUBEFIMODS
# (which builds the same lists as local shell variables at grub-mknetdir time,
# never persisted anywhere Python could read - environment.py never carried
# these despite this script referencing them as environment.GRUBI386MODS/
# GRUBEFIMODS, which never actually existed there).
GRUB_COMMON_MODULES = (
    'all_video boot chain configfile cpuid echo net ext2 extcmd fat gettext gfxmenu '
    'gfxterm gzio http iso9660 ntfs linux linux16 loadenv loopback minicmd net part_gpt part_msdos '
    'png progress read reiserfs search sleep terminal test tftp'
)


def getGrubI386Modules():
    """i386-pc netboot GRUB modules - static list, mirrors mkgrubnetdir.sh's GRUBI386MODS."""
    return GRUB_COMMON_MODULES + ' biosdisk gfxterm_background normal ntldr pxe'


def getGrubEfiModules(efi_dir='/usr/lib/grub/x86_64-efi'):
    """
    x86_64-efi netboot GRUB modules: the common list plus every *efi*.mod
    file actually present in `efi_dir` - mirrors mkgrubnetdir.sh's GRUBEFIMODS,
    which discovers these the same way (`ls "$EFI64_DIR"/*efi*.mod`) rather
    than hardcoding them, since the exact set depends on the installed
    grub-efi-amd64-bin package version.
    """
    efi_modules = sorted(
        os.path.splitext(os.path.basename(path))[0]
        for path in glob.glob(os.path.join(efi_dir, '*efi*.mod'))
    )
    return GRUB_COMMON_MODULES + ' ' + ' '.join(efi_modules)


def usage():
    print('Purpose: linbo-mkgrubimg creates host specific image for grub network')
    print('boot and stores it in /srv/linbo/boot/grub/hostcfg/<hostname>.img.')
    print('Usage: linbo-mkgrubimg [options]')
    print(' [options] may be:')
    print(' -h,            --help                : print this help.')
    print(' -n <hostname>, --name=<hostname>     : hostname for which an image will be')
    print('                                        created.')
    print(' -s,            --setfilename         : sets filename option in dhcpd.conf and')
    print('                                        workstations file.')
    print(' -w <file>,     --workstations=<file> : path to workstations file, default is')
    print('                                        /etc/linuxmuster/sophomorix')
    print('                                        /default-school/devices.csv.')


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv

    # get cli args
    try:
        opts, args = getopt.getopt(argv, "hn:sw:", ["help", "name=", "setfilename", "workstations="])
    except getopt.GetoptError as err:
        # print help information and exit:
        print(err)  # will print something like "option -a not recognized"
        usage()
        sys.exit(2)

    # default values
    setfilename = False
    wsfile = environment.WIMPORTDATA
    hostname = None

    # evaluate options
    for o, a in opts:
        if o in ("-s", "--setfilename"):
            setfilename = True
        elif o in ("-n", "--name"):
            hostname, hostrow = getHostname(wsfile, a)
        elif o in ("-w", "--workstations"):
            if os.path.isfile(a):
                wsfile = a
            else:
                usage()
                sys.exit()
        elif o in ("-h", "--help"):
            usage()
            sys.exit()
        else:
            assert False, "unhandled option"

    # evaluate hostname
    if hostname is None:
        usage()
        sys.exit(1)

    # grub image filename
    img = environment.LINBOGRUBDIR + '/hostcfg/' + hostname + '.img'
    imgrel = img.replace(environment.LINBOGRUBDIR, 'boot/grub')

    # path to host specific cfg
    hostcfg = img.replace('.img', '.cfg')

    # get other host parameters from hostrow
    field1 = hostrow[0]
    field2 = hostrow[1]
    group = hostrow[2]
    mac = hostrow[3]
    ip = hostrow[4]
    if ip == 'DHCP':
        ip = '0.0.0.0'
    field6 = hostrow[5]
    field7 = hostrow[6]
    field8 = hostrow[7]
    field9 = hostrow[8]
    field10 = hostrow[9]
    field11 = hostrow[10]

    # path to group specific cfg
    groupcfg = environment.LINBOGRUBDIR + '/' + group + '.cfg'

    # get systemtype specific parameters
    startconf = environment.LINBODIR + '/start.conf.' + group
    systemtype = getStartconfOption(startconf, 'LINBO', 'SYSTEMTYPE').lower()
    normal = '\n'
    if systemtype == 'bios' or systemtype == 'bios64':
        platform = 'i386-pc'
        imgtype = platform + '-pxe'
        iface = 'pxe'
        modules = getGrubI386Modules()
        normal = 'normal'
    elif systemtype == 'efi64':
        platform = 'x86_64-efi'
        imgtype = platform
        iface = 'efinet0'
        modules = getGrubEfiModules()
    else:
        print('Cannot get SystemType of ' + hostname + ' from start.conf.' + group + '!')
        sys.exit(1)

    # get domainname from setup.ini
    setup = configparser.ConfigParser(inline_comment_prefixes=('#', ';'))
    setup.read(environment.SETUPINI)
    domainname = setup.get('setup', 'domainname')

    # get serverip from start.conf
    serverip = getStartconfOption(startconf, 'LINBO', 'SERVER')

    # create grub config for host
    # necessary variables
    cfgtemplate = environment.LINBOTPLDIR + '/host.cfg.pxe'
    cfgout = '/var/tmp/' + hostname + '.cfg'
    if os.path.isfile(hostcfg):
        appendcfg = hostcfg
    else:
        appendcfg = groupcfg
    # read template
    rc, content = readTextfile(cfgtemplate)
    # replace placeholders
    content = content.replace('@@normal@@', normal)
    content = content.replace('@@serverip@@', serverip)
    content = content.replace('@@iface@@', iface)
    content = content.replace('@@hostip@@', ip)
    content = content.replace('@@mac@@', mac)
    content = content.replace('@@domainname@@', domainname)
    content = content.replace('@@group@@', group)
    content = content.replace('@@hostname@@', hostname)
    # write file
    rc = writeTextfile(cfgout, content, 'w')
    # append host/group specific cfg
    rc, content = readTextfile(appendcfg)
    rc = writeTextfile(cfgout, content, 'a')

    # create image file
    if systemtype == 'bios' or systemtype == 'bios64':
        cmd = 'grub-mkimage -p /boot/grub -d /usr/lib/grub/' + platform + ' -O ' + imgtype + ' -o ' + img + ' -c ' + cfgout + ' ' + modules
    else:
        cmd = 'grub-mkstandalone -d /usr/lib/grub/' + platform + ' -O ' + imgtype + ' -o ' + img + ' --modules="' + modules + '" --install-modules="' + modules + '" /boot/grub/grub.cfg="' + cfgout + '"'
    os.system(cmd)
    os.unlink(cfgout)

    print(img + ' successfully created.')

    if not setfilename:
        sys.exit(0)

    # set filename option in workstations file and dhcpd.conf
    foption = 'filename "' + imgrel + '"'
    # modify workstations file
    row_old = field1 + ';' + field2 + ';' + group + ';' + mac + ';' + ip + ';' + field6 + ';' + field7 + ';' + field8 + ';' + field9 + ';' + field10 + ';' + field11
    row_new = field1 + ';' + hostname + ';' + group + ';' + mac + ';' + ip + ';' + field6 + ';' + field7 + ';' + foption + ';' + field9 + ';' + field10 + ';' + field11
    rc, content = readTextfile(wsfile)
    rc = writeTextfile(wsfile, content.replace(row_old, row_new), 'w')
    # modify dhcp device entry
    # read included conf files
    rc, includes = readTextfile(environment.DHCPDEVCONF)
    prefix = os.path.dirname(environment.DHCPDEVCONF)
    # iterate over included files
    for item in includes.split('"'):
        # skip not relevant items
        if prefix not in item or not os.path.exists(item):
            continue
        rc, content = readTextfile(item)
        # find host entry
        if 'host ' + hostname in content:
            # replace device entry with custom grub img path
            row_old = re.findall('host ' + hostname + ' .*?(?=}|$)', content, re.DOTALL)[0]
            row_new = 'host ' + hostname + ' {\n  hardware ethernet ' + mac + ';\n  fixed-address ' + ip + ';\n  ' + foption + ';\n  option host-name "' + hostname + '";\n  option extensions-path "' + group + '";\n'
            row_new = row_new.replace('  fixed-address 0.0.0.0;\n', '')
            rc = writeTextfile(item, content.replace(row_old, row_new), 'w')
            break
    # finally restart dhcp service
    os.system('service isc-dhcp-server restart')

    print('Filename option in ' + hostname + '\'s dhcp config successfully set.')


if __name__ == '__main__':
    main()
