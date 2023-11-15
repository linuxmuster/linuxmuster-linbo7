

<img src="https://raw.githubusercontent.com/linuxmuster/linuxmuster-artwork/master/linbo/linbo_logo_small.svg" alt="linbo icon" width="200"/>

# linuxmuster-linbo7 (next generation)
 is the free and opensource imaging solution for linuxmuster.net 7. It handles Windows 10 (TM) and Linux 64bit operating systems. Via TFTP and Grub's PXE implementation it boots a small linux system (linbofs) with a [gui](https://github.com/linuxmuster/linuxmuster-linbo-gui), which can manage all the imaging tasks on the client. Console tools are also available to manage clients and imaging remotely via the server.

 ## Features
 * Kernel 6.1.*.
 * qcow2 image format.
 * Differential images.
 * Complete [refactoring of linbo_cmd](https://github.com/linuxmuster/linuxmuster-linbo7/issues/72).
 * switch to new ntfs3 kernel driver, allows file sync for ntfs partitions.

## Important notices:
* Currently the code in this repo is not for production use. For the currently stable version go to [branch 4.0](https://github.com/linuxmuster/linuxmuster-linbo7/tree/4.0).
* The [README](https://github.com/linuxmuster/linuxmuster-linbo7/tree/4.0#readme) for the stable version is still valid.
* Packages were published in the [lmn72 testing repository](https://github.com/linuxmuster/deb).

## Migration from linuxmuster.net 7.1
* Perform a two step upgrade of the server from Ubuntu 18.04 to 20.04 and finally to 22.04 using `do-release-upgrade`.
* Reconfigure the linuxmuster packages:
  `dpkg-reconfigure sophomorix-samba linuxmuster-base7 linuxmuster-webui7`
* Reactivate the lmn71 repo `/etc/apt/sources-list.d/lmn71.list.distUpgrade`.
* Add the lmn72 repo according to this [instruction](https://github.com/linuxmuster/deb/blob/main/README.md#setup).
* Perform a dist-upgrade subsequently.

## Differential imaging
* Differential imagefile uses the qcow2 baseimage as so called *backingstore*.
* Differential image gets extension `qdiff`: `image.qcow2` -> `image.qdiff`.
* The diffimage will be created in the same directory as the baseimage, so they are virtually "bundled".
* If a diffimage exists for a baseimage, the diffimage is used for the restore.
* If you remove the diffimage on the server, it is also deleted on the client during the sync and only the baseimage is used for the restore.
* When uploading a new diffimage, any existing old diffimage is moved to a backup folder.
* When uploading a new baseimage, the old baseimage and diffimage (if any) are moved to a backup folder.
* Diffimage is created file-based by rsync:
  ```
  qemu-img create -f qcow2 -b image.qcow2 image.qdiff
  qemu-nbd --connect /dev/nbd0 image.qdiff
  mount /dev/nbd0 /image
  mount /dev/sda1 /mnt
  rsync -HAa --exclude="/.linbo" --exclude-from="/etc/rsync.exclude" --delete --delete-excluded  /mnt/ /image
  umount /mnt
  umount /image
  qemu-nbd --disconnect /dev/nbd0
  ```
* Diffimage is restored file-based:
  ```
  qemu-nbd -r --connect /dev/nbd0 image.qdiff
  mount /dev/nbd0 /image
  mount /dev/sda1 /mnt
  rsync -HAa --exclude="/.linbo" --exclude-from="/etc/rsync.exclude" --delete --delete-excluded  /image/ /mnt
  umount /mnt
  umount /image
  qemu-img --disconnect /dev/nbd0
  ```
* This also works with Windows10 thanks to the new native ntfs3 driver.
* The entry `Image =` in start.conf becomes obsolete, because diffimage is always bundled with baseimage.
* For image creation, you only specify whether you want to create a base image or a diffimage:
  ```
  linbo-remote -c|-p create_qdiff:<#> ...
  linbo_cmd create <cache> <imagefile> <root>
  linbo_create_image <#> qdiff
  ```
* Image upload accordingly:
  ```
  linbo-remote -c|-p upload_qdiff:<#> ...
  linbo_cmd upload <server> <user> <password> <cache> <imagefile>
  linbo_upload <password> <imagefile>
  ```
Note:
* <#>: start.conf position number of operating system.
* qdiff: option to indicate a differential image, if omitted a baseimage will be created.
* Further infos about the new linbo commands see [refactor linbo_cmd #72](https://github.com/linuxmuster/linuxmuster-linbo7/issues/72).

### In the gui
* Log in to the admin section.
* Press the big os button.
* Select "Create differential image."

## New kernel parameters
Parameter  |  Description
--|--
nogui  |  Does not start linbo_gui (for debugging purposes), console only mode.
nowarmstart  |  Suppresses linbo warmstart after downloading a new linbo kernel from the server (in case warmstart causes problems). Note: The old parameter `warmstart=no` is still functional for compatibility reasons.

## Improved LINBO server scripts

For background jobs `screen` is replaced by [`tmux`](https://manpages.ubuntu.com/manpages/jammy/man1/tmux.1.html). Note: To detach a tmux session you have to use the key combination [CTRL-D] + [B].

### linbo-remote
* There are two new commands `create_qdiff` and `upload_qdiff` for differential imaging.
* The options `-d` and `-n` receive a different behaviour. They may be used to set the client into maintenance mode:
  ```
  linbo-remote -d -n -c reboot -i <hostname>
  linbo-remote -d -n -w 0 -i <hostname>
  ```
* The option `-c` now disables the gui by default during command execution. 
* The new option `-a` allows to attach a host's tmux session.

Full linbo-remote help:

```
Usage: linbo-remote <options>

Options:

 -h                 Show this help.
 -a <hostname>      Attach the running tmux session for this hostname.
 -b <sec>           Wait <sec> second(s) between sending wake-on-lan magic
                    packets to the particular hosts. Must be used in
                    conjunction with "-w".
 -c <cmd1,cmd2,...> Comma separated list of linbo commands transfered
                    per ssh direct to the client(s). Gui will be disabled
                    during execution.
 -d                 Disables gui on next boot.
 -g <group>         All hosts of this hostgroup will be processed.
 -i <i1,i2,...>     Single ip or hostname or comma separated list of ips
                    or hostnames of clients to be processed.
 -l                 List current linbo-remote tmux sessions.
 -n                 Bypasses start.conf configured auto functions
                    (partition, format, initcache, start) on next boot.
 -r <room>          All hosts of this room will be processed.
 -s <school>        Select a school other than default-school
 -p <cmd1,cmd2,...> Create an onboot command file executed automatically
                    once next time the client boots.
 -u                 Use broadcast address for wol additionally.
 -w <sec>           Send wake-on-lan magic packets to the client(s)
                    and wait <sec> seconds before executing the
                    commands given with "-c" or in case of "-p" after
                    the creation of the pxe boot files.

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
new:<#>                  : Clean sync of the operating system on position nr <#>
                           (formats the according partition before).
start:<#>                : Starts the operating system on pos. nr <#>.
create_image:<#>:<"msg"> : Creates a full image from operating system nr <#>.
upload_image:<#>         : Uploads a full image from operating system nr <#>.
create_qdiff:<#>:<"msg"> : Creates a differential image from operating system nr <#>.
upload_qdiff:<#>         : Uploads a differential image from operating system nr <#>.
reboot                   : Reboots the client.
halt                     : Shuts the client down.

<"msg"> is an optional image comment.
The position numbers are related to the position in start.conf.
The commands were sent per ssh to the linbo_wrapper on the client and processed
in the order given on the commandline.
create_* and upload_* commands cannot be used with hostlists, -r and -g options.
```

### linbo-torrent
* The new command `attach` attaches a torrent's tmux session.
* The `status` command lists all running tmux sessions of the torrents.
  ```
  ubuntu2004_qcow2_torrent: 1 windows (created Fri Jan 27 14:40:01 2023)
  ubuntu2004_qdiff_torrent: 1 windows (created Fri Jan 27 14:40:03 2023)
  win10-efi_qcow2_torrent: 1 windows (created Fri Jan 27 14:40:02 2023)
  win10-efi_qdiff_torrent: 1 windows (created Fri Jan 27 14:40:04 2023)
  ```

Full linbo-torrent help:
```
Info: linbo-torrent manages the torrent tmux sessions of linbo images.

Usage:
 linbo-torrent <start|stop|restart|reload|status|create|check> [image_name]
 linbo-torrent attach <image_name|session_name>

Note:
 * Only qcow2 & qdiff image files located below /srv/linbo/images are processed.
 * The commands "start", "stop" and "restart" may have optionally an image
   filename as parameter. In this case the commands are only applied to the tmux
   session of the certain file. Without an explicit image filename the commands
   were applied to all image file sessions currently running.
 * An image filename parameter is mandatory with the commands "check", "create"
   and "attach".
 * "check" checks if the image file matches to the correspondig torrent.
 * "create" creates/recreates the torrent of a certain image file.
 * "status" shows a list of currently running torrent tmux sessions.
 * "attach" attaches a torrent tmux session of a certain image. An image or
   session name must be given as parameter.
   Press [CTRL+B]+[D] to detach the session again.
 * "reload" is the identical to "restart" and is there for backwards compatibility.
```

### linbo-multicast
* The `status` command lists all running multicast tmux sessions.
  ```
  ubuntu2004_qcow2_mcast: 1 windows (created Sat Jan 28 14:05:44 2023)
  ubuntu2004_qdiff_mcast: 1 windows (created Sat Jan 28 14:05:43 2023)
  win10-efi_qcow2_mcast: 1 windows (created Sat Jan 28 14:05:45 2023)
  win10-efi_qdiff_mcast: 1 windows (created Sat Jan 28 14:05:46 2023)
  ```
* To watch the output of a multicast tmux session you have to follow its logfile:  
  `tail -f /var/log/linuxmuster/linbo/ubuntu2004_qdiff_mcast.log`

## Improved LINBO client shell

The improved LINBO client shell not only presents a new login prompt
```
Welcome to
 _      _____ _   _ ____   ____
| |    |_   _| \ | |  _ \ / __ \
| |      | | |  \| | |_) | |  | |
| |      | | | . ` |  _ <| |  | |
| |____ _| |_| |\  | |_) | |__| |
|______|_____|_| \_|____/ \____/

LINBO 4.1.18-0: One Step Beyond | IP: 10.0.100.1 | MAC: 95:6a:45:12:67:d5

Linux 6.1.8 #1 SMP PREEMPT_DYNAMIC Thu Jan 26 22:13:55 UTC 2023 x86_64 GNU/Linux

linboclient-01: ~ #
```
but also offers a complete set of environment variables:
```
PS1='\h: \w # '
PATH='/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'
LINBOFULLVER='LINBO 4.1.25-0: One Step Beyond'
LINBOVER='4.1.25-0'
RSYNC_PERMISSIONS="--chmod=ug=rw,o=r"
RSYNC_SKIP_COMPRESS="/7z/arc/arj/bz2/cab/cloop/deb/gz/gpg/iso/jar/jp2/jpg/jpeg/lz/lz4/lzma/lzo/png/qcow2/qdiff/qt/rar/rzip/s7z/sfx/svgz/tbz/tgz/tlz/txz/xz/z/zip/zst"
QUIET='yes'
SPLASH='yes'
FORCEGRUB='yes'
LOCALBOOT='yes'
BROADCAST='10.0.255.255'
DHCPRETRY='5'
DNS='10.0.0.1'
DOMAIN='linuxmuster.lan'
HOSTNAME='linbo-01'
INTERFACE='eth0'
IP='10.0.100.1'
LEASE='172800'
MASK='16'
HOSTGROUP='tuxwin'
NTPSRV='10.0.0.1'
OPT53='05'
ROUTER='10.0.0.254'
SERVERID='10.0.0.1'
SIADDR='10.0.0.1'
SNAME='server.linuxmuster.lan'
SUBNET='255.255.0.0'
FQDN='linbo-01.linuxmuster.lan'
LINBOSERVER='10.0.0.1'
MACADDR='96:9b:31:46:54:f3'
```
The `linbo_cmd` script is splitted into multiple scripts, each for a certain function. The legacy `linbo_cmd` remains functional for backwards compatibility. The client's `start.conf` is divided into better parseable chunks that reside under _/conf_.
```
linboclient-01: ~ # ls -1 /conf/*
/conf/linbo
/conf/os.1
/conf/os.2
/conf/part.1.sda1
/conf/part.2.sda2
/conf/part.3.sda3
/conf/part.4.sda4
/conf/part.5.sda5 
```
```
linboclient-01: ~ # cat /conf/linbo 
server="10.0.0.1"
group="tuxwin"
cache="/dev/sda5"
roottimeout="600"
autopartition="no"
autoformat="no"
autoinitcache="no"
downloadtype="torrent"
guidisabled="no"
theme="test_theme"
useminimallayout="no"
locale="de-de"
systemtype="efi64"12
kerneloptions="quiet splash forcegrub"
icons="win10.svg ubuntu.svg"
```
 This makes the LINBO client shell more powerful than ever. For more details please take a look at [#72](https://github.com/linuxmuster/linuxmuster-linbo7/issues/72).

## Adding firmware
From Linbo 4.2.0 there is a configuration file `/etc/linuxmuster/linbo/firmware` which can be used to integrate supplemental firmware files into the Linbo filesystem. Here is an example:
```
# /etc/linuxmuster/linbo/firmware

# Realtek r8168 ethernet adapters firmware (whole directory)
rtl_nic

# Realtek RTL8821AE wifi firmware (single file)
rtlwifi/rtl8821aefw.bin

# Intel Wi-Fi 6 AX200 firmware (single file)
iwlwifi-cc-a0-77.ucode
```
You can enter files or whole directories, one per line. The firmware files are taken from the linux-firmware package, which is installed on the server per default. Note that the path to the firmware must be specified relative to /lib/firmware.
Examine the output of `dmesg` on the Linbo client to get infos about missing firmware:
```
nb-01: ~ # dmesg | grep firmware
i915 0000:00:02.0: Direct firmware load for i915/kbl_dmc_ver1_04.bin failed with error -2
i915 0000:00:02.0: [drm] Failed to load DMC firmware i915/kbl_dmc_ver1_04.bin. Disabling runtime power management.
i915 0000:00:02.0: [drm] DMC firmware homepage: https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/tree/i915
```
In this case you have to add the line "i915/kbl_dmc_ver1_04.bin" to the firmware configuration file. Finally you have to invoke `update-linbofs` on the server terminal to add the firmware file to the linbofs archive.

## Wifi support
From version 4.2.0 Linbo is able to use wireless networks. For this purpose the program [wpa_supplicant](https://w1.fi/wpa_supplicant/) was integrated.
To use this feature you first have to examine whether the built-in wireless network adapter misses any firmware (see the above section).
Additionally there is a configuration file `/etc/linuxmuster/linbo/wpa_supplicant.conf`, in which you have to<> define the wireless network to be used. Here are two examples:
```
# /etc/linuxmuster/linbo/wpa_supplicant.conf

# wpa-psk secured
network={
  ssid="LINBO_MGMT"
  scan_ssid=1
  key_mgmt=WPA-PSK
  psk="My Secret Passphrase"
}

# open
network={
   ssid="LINBO_MGMT"
   key_mgmt=NONE
}
```
For more examples see https://linux.die.net/man/5/wpa_supplicant.conf.
After you have provided the configuration file, you have to invoke the command `update-linbofs` on the server to apply the changes to linbofs.
In the last step you have to add an entry with the wifi adapter's mac address in the file devices.csv or in the School Console under "Devices". Note that you then have two entries for the same device and the hostnames must differ:
```
notebooks;nb-01;nbclass;4d:b6:a7:12:45:79;10.0.100.1;;;;classroom-studentcomputer;;1
notebooks;nb-01w;nbclass;b2:5f:5e:32:12:65;DHCP;;;;classroom-studentcomputer;;1
```
Don't forget to apply the changes either by invoking the command `linuxmuster-import-devices` on the server terminal or by pressing the button "Save & import" in the School Console.
Note that there are some restrictions by the use of wireless network connections:
* Wireless pxe boot is not possible. Linbo establishes the wireless connection only during the boot process.
* The initial Linbo installation on a client has to be done over a wired network connection.
* Assume that huge downloads of operating system images may reduce your wireless experience.
* Consider to setup a restricted wireless network for Linbo management purposes to limit unauthorized use.

## Execute your own boot scripts
Perform the following 4 steps to execute your own boot script during the linbo-client's init process:
1. Create the script, which you want to execute during linbo boot, for example under `/root/linbofs/mybootscript.sh`. Note that you can use the linbo environment in your script by sourcing the file `/.env` (see above).  
2. Create an update-linbofs pre-hook script in the directory `/var/lib/linuxmuster/hooks/update-linbofs.pre.d` named for example `copy_myscript` to copy your boot script to the linbo filesystem:
    ```
    #!/bin/bash
    # copies my script to /usr/bin in the linbo filesystem
    myscript="/root/linbofs/mybootscript.sh"
    echo "### copy $myscript ###"
    cp "$myscript" usr/bin

    ```
    Note that the pre-hook script will be executed in the root directory of the linbo filesystem so you have to give the target path relative to it (no leading /). Don't forget to make the pre-hook script executable.  
3. Create a file `/etc/linuxmuster/linbo/inittab` with the following content:
    ```
    ::wait:/usr/bin/mybootscript.sh
    ```
    The content of this file will be appended to the inittab in the linbo filesystem by `update-linbofs`. In the example the init process will wait until the script has been completed. For more information about inittab see https://manpages.debian.org/unstable/sysvinit-core/inittab.5.en.html.  
4. Apply your changes to the linbo filesystem by executing `update-linbofs`.

## Integrate your own kernel
From Linbo version 4.2.4 you can integrate an alternative kernel into the Linbo file system. Simply create a file under `/etc/linuxmuster/linbo/custom_kernel` and define the paths to the kernel image and the modules directory:
```
# currently active kernel image and modules used by the server
# path to kernel image
KERNELPATH="/boot/vmlinuz-$(uname -r)"
# path to the corresponding modules directory
MODULESPATH="/lib/modules/$(uname -r)"

# custom kernel image and modules
KERNELPATH="/path/to/my/kernelimage"
# path to the corresponding modules directory
MODULESPATH="/path/to/my/lib/modules/n.n.n"
```
If you want to use the legacy or longterm kernels shipped with Linbo you have to make simply the following entries:
```
# use Linbo's alternative legacy kernel
KERNELPATH="legacy"

# use Linbo's alternative longterm kernel
KERNELPATH="longterm"
```
To apply your changes you have to execute `update-linbofs`. The example above points to the alternative Linbo legacy kernel image and modules. But you can use any other kernel, kernels delivered with the server or other distros or even one compiled on another machine and copied to the server. You only have to provide the paths to the kernel image and the modules directory. Note that your own kernel will be a much larger than the included linbo kernels and that you have to test it if it fits to your client hardware. With self-compiled Linbo kernels, art is to omit unneededed modules to optimize size. A starting point can be the [configuration file of the supplied kernel](https://github.com/linuxmuster/linuxmuster-linbo7/blob/main/build/config/kernel).

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
* Install Ubuntu 22.04
* If you are using Ubuntu server or minimal:
  `sudo apt install dpkg-dev`
* Install build depends (uses sudo):
  `./get-depends.sh`
* Build package:
  `./buildpackage.sh`

Or for better convenience use the new [linbo-build-docker](https://github.com/linuxmuster/linbo-build-docker) environment.

Further infos see [README](https://github.com/linuxmuster/linuxmuster-linbo7/tree/4.0#readme) of stable branch.
