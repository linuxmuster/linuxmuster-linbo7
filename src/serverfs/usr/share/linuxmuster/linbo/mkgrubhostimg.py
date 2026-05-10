#!/usr/bin/python3
#
# creates host specific image for grub network boot
# stored in /srv/linbo/boot/grub/hostcfg/<hostname>.img
#
# linuxmuster-mkgrubimg.py
# thomas@linuxmuster.net
# 20220416
#

import configparser
import environment
import getopt
import os
import re
import sys

from functions import getHostname
from functions import readTextfile
from functions import writeTextfile
from functions import getStartconfOption

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

# get cli args
try:
    opts, args = getopt.getopt(sys.argv[1:], "hn:sw:", ["help", "name=", "setfilename", "workstations="])
except getopt.GetoptError as err:
    # print help information and exit:
    print(err) # will print something like "option -a not recognized"
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
if hostname == None:
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
    modules = environment.GRUBI386MODS
    normal = 'normal'
elif systemtype == 'efi64':
    platform = 'x86_64-efi'
    imgtype = platform
    iface = 'efinet0'
    modules = environment.GRUBEFIMODS
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
