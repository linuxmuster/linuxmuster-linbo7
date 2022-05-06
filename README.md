<img src="https://raw.githubusercontent.com/linuxmuster/linuxmuster-artwork/master/linbo/linbo_logo_small.svg" alt="linbo icon" width="200"/>

# linuxmuster-linbo7 (next generation)
 is the free and opensource imaging solution for linuxmuster.net 7. It handles Windows 10 and Linux 64bit operating systems. Via TFTP and Grub's PXE implementation it boots a small linux system (linbofs) with a [gui](https://github.com/linuxmuster/linuxmuster-linbo-gui), which can manage all the imaging tasks on the client. Console tools are also available to manage clients and imaging remotely via the server.

## Important notices:
* Currently the code in this repo is not for production use.
* There is only a linuxmuster-linbo7 package, the linuxmuster-linbo-common7 package is deprecated and will be removed on dist-upgrade.
* In spite of former [linuxmuster-linbo](https://github.com/linuxmuster/linuxmuster-linbo) images in cloop format where only supported for restore.
* For image creation only qcow2 format is supported. You have to change the baseimage name in the start.conf accordingly (e.g. image.qcow2).
* Supplemental postsync, prestart and reg image files were now named without the image format part (e.g. image.postsync, image.prestart and image.reg, former: image.cloop.postsync etc.).
* [qemu-img](http://manpages.ubuntu.com/manpages/bionic/man1/qemu-img.1.html) is used for qcow2 image creation and restore.
* Only 64bit client hardware is supported.
* No more support for linuxmuster.net <=6.2.
* No differential imaging yet.
* Packages were published in the [lmn7-testing repository](http://archive.linuxmuster.net/lmn7-testing/).

## Migration
* Add the new lmn71 repo according to this instruction https://github.com/linuxmuster/deb/blob/main/README.md#setup
* Perform a dist-upgrade subsequently.
* Convert your cloop images to qcow2 format with `linbo-cloop2qcow2`:
  - invoke for example `linbo-cloop2qcow2 ubuntu.cloop` and
  - the converted image will be created in `/srv/linbo/images/ubuntu/ubuntu.qcow2`.
  - Note: Images of Windows systems may not function as expected (especially UEFI). In this case it is necessary to create a new image.
* Change the image name in the start.conf.
* Restart the image deployment services with `linbo-torrent|linbo-multicast restart`.
* See the status of the image deployment services with `systemctl status linbo-torrent|linbo-multicast`.
* Important: Start all clients 2 times to ensure Linbo v2 was updated to v4.
* Finally start the import script `linuxmuster-import-devices`, which will remove the obsolete start.conf links.
* Now you can create and deploy images as usual.
* Explore the new linbo-torrent tool:
  ```
  Usage: /usr/sbin/linbo-torrent <start|stop|restart|reload|status|create|check> [torrent_filename|image_filename]

  * The commands start, stop and restart may have optionally a torrent filename
    as parameter. So the command is only processed to this certain file.
    Without an explicit torrent filename the commands were processed to all
    torrent files found recursivly below /srv/linbo.
  * A torrent filename parameter is mandatory with the command check.
  * An image filename parameter is mandatory with the command create.
  ```
* Note:
  - Your current cloop images will be still functional and available for client restauration after migration.
  - New images have to be in qcow2 format.
  - New uploaded images will be placed in subdirectories below `/srv/linbo/images`.
  - Backups of images will be moved to `/srv/linbo/images/<imagename>/backups/<timestamp>`.

## Features
* Kernel 5.10.x.
* qcow2 image format.
* images are placed in subdirectories of /srv/linbo/images.
* More performant image deployment based on ctorrent and [opentracker](https://erdgeist.org/arts/software/opentracker/).

## In planning:
* start.conf in yaml format.
* step by step changeover of the scripting to python.
* differential imaging.
* switch to new ntfs3 kernel driver.
* secure boot support.

## Build environment

### Source tree structure
* build: all files, which are used to build the package.
  - bin: helper scripts (only get kernel archive script at the moment).
  - conf.d: environment variables definition for the various build components.
  - config: configuration files for various source packages (eg. busybox, kernel).
  - initramfs.d: initramfs configurations for the various components, which are picked from the ubuntu build system to create the linbofs system from it.
  - patches: source patches, which are to be applied (eg. cloop).
  - run.d: the build scripts for the package components.
* debian: debian packaging stuff
* linbofs: files, which are installed to the initramfs file system.
* serverfs: files, which are installed to the server root file system.

### Build instructions:
* Install 64bit Ubuntu 18.04
* If you are using Ubuntu server or minimal:
  `sudo apt install dpkg-dev`
* Install build depends (uses sudo):
  `./get-depends.sh`
* Build package:
  `./buildpackage.sh`

Or for better convenience use the new [linbo-build-docker](https://github.com/linuxmuster/linbo-build-docker) environment.

## Usage infos

### Kernel parameters

are defined in the start.conf file (see [examples](https://github.com/linuxmuster/linuxmuster-linbo7/tree/main/serverfs/srv/linbo/examples)) of the hardware group:
`KernelOptions = quiet splash`
The command `linuxmuster-import-devices` writes the parameters into the grub configuration of the hardware group.
Option  |  Description
--|--
forcegrub  |  Forces grub boot on uefi systems (in case of uefi boot issues).
noefibootmgr  |  Skips providing the EFI boot files and boot entries (in case of uefi boot issues).
splash  |  Displays graphical splash screen at boot time. Without this parameter, only text is displayed on the console at boot time.
quiet  |  Suppresses kernel boot messages.
warmstart=no  |  Suppresses linbo warmstart after downloading a new linbo kernel from the server (in case this causes problems).

### Linbo services

Linbo's torrent and multicast services are controlled by systemd:
```
systemctl start|stop|restart|status|disable|enable linbo-multicast
systemctl start|stop|restart|status|disable|enable linbo-torrent
```

### Linbo commands

#### linbo-multicast

Can be used to control linbo's multicast service directly:
```
root@server:~# linbo-multicast --help
Usage: /usr/sbin/linbo-multicast {start|stop|restart|status}
```

#### linbo-torrent

offers possibilities beyond the control of the service:
```
root@server:~# linbo-torrent --help
Usage: /usr/sbin/linbo-torrent <start|stop|restart|reload|status|create|check> [torrent_filename|image_filename]
```

Note:
 * The commands start, stop and restart may have optionally a torrent filename
   as parameter. So the command is only processed to this certain file.
   Without an explicit torrent filename the commands were processed to all
   torrent files found recursivly below /srv/linbo.
 * A torrent filename parameter is mandatory with the command check.
 * An image filename parameter is mandatory with the command create.

#### linbo-remote

is used to remote control linbo actions on the client. Note that the `create_cloop` and `upload_cloop` commands have changed to `create_image` and `upload_image`:

```
root@server:~# linbo-remote -h

Usage: linbo-remote <options>

Options:

 -h                 Show this help.
 -b <sec>           Wait <sec> second(s) between sending wake-on-lan magic
                    packets to the particular hosts. Must be used in
                    conjunction with "-w".
 -c <cmd1,cmd2,...> Comma separated list of linbo commands transfered
                    per ssh direct to the client(s).
 -d                 Disables gui. To be used only together with option -c.
 -g <group>         All hosts of this hostgroup will be processed.
 -i <i1,i2,...>     Single ip or hostname or comma separated list of ips
                    or hostnames of clients to be processed.
 -l                 List current linbo-remote screens.
 -n                 Bypasses start.conf configured auto functions
                    (partition, format, initcache, start) on next boot.
                    To be used only together with options -p
                    or -c in conjunction with -w.
 -r <room>          All hosts of this room will be processed.
 -p <cmd1,cmd2,...> Create an onboot command file executed automatically
                    once next time the client boots.
 -w <sec>           Send wake-on-lan magic packets to the client(s)
                    and wait <sec> seconds before executing the
                    commands given with "-c" or in case of "-p" after
                    the creation of the pxe boot files.
 -u                 Use broadcast address with wol.

Important: * Options "-r", "-g" and "-i" exclude each other, "-c" and
             "-p" as well.

Supported commands for -c or -p options are:

partition                : Writes the partition table.
label                    : Labels all partitions defined in start.conf.
                           Note: Partitions have to be formatted.
format                   : Writes the partition table and formats all
                           partitions.
format:<#>               : Writes the partition table and formats only
                           partition nr <#>.
initcache:<dltype>       : Updates local cache. <dltype> is one of
                           rsync|multicast|torrent.
                           If dltype is not specified it is read from
                           start.conf.
sync:<#>                 : Syncs the operating system on position nr <#>.
start:<#>                : Starts the operating system on pos. nr <#>.
create_image:<#>:<"msg"> : Creates a image image from operating system nr <#>.
upload_image:<#>         : Uploads the image image from operating system nr <#>.
reboot                   : Reboots the client.
halt                     : Shuts the client down.

<"msg"> is an optional image comment.
The position numbers are related to the position in start.conf.
The commands were sent per ssh to the linbo_wrapper on the client and processed
in the order given on the commandline.
create_* and upload_* commands cannot be used with hostlists, -r and -g options.
```

#### linbo-mkgrubimg
creates hostspecific custom grub boot images to workaround buggy (UEFI-)BIOSes, which fail to netboot:
```
Purpose: linbo-mkgrubimg creates host specific image for grub network
boot and stores it in /srv/linbo/boot/grub/hostcfg/<hostname>.img.
Usage: linbo-mkgrubimg [options]
 [options] may be:
 -h,            --help                : print this help.
 -n <hostname>, --name=<hostname>     : hostname for which an image will be
                                        created.
 -s,            --setfilename         : sets filename option in dhcpd.conf and
                                        workstations file.
 -w <file>,     --workstations=<file> : path to workstations file, default is
                                        /etc/linuxmuster/sophomorix
                                        /default-school/devices.csv.
```

Note:
  * The `setfilename` option alters 2 files:
    - adds an entry `filename "boot/grub/hostcfg/<hostname>.img"` in the 8th field of the host's line in `/etc/linuxmuster/sophomorix/default-school/devices.csv`,
    - changes `filename` entry in `/etc/dhcp/devices/default-school.conf` accordingly.
  * To get rid of these changes simply remove the filename entry in `devices.csv` and invoke `linuxmuster-import-devices`.
