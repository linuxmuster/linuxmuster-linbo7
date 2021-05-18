<img src="https://raw.githubusercontent.com/linuxmuster/linuxmuster-artwork/master/linbo/linbo_logo_small.svg" alt="linbo icon" width="200"/>

# linuxmuster-linbo7 (next generation)
 is the free and opensource imaging solution for linuxmuster.net 7. It handles Windows 10 and Linux 64bit operating systems. Via TFTP and Grub's PXE implementation it boots a small linux system (linbofs) with a [gui](https://github.com/linuxmuster/linuxmuster-linbo-gui7), which can manage all the imaging tasks on the client. Console tools are also available to manage clients and imaging remotely via the server.

## Important notices:
* The code in this repo is currently experimental.
* There is only a linuxmuster-linbo7 package. The old common package is deprecated and will be removed by upgrade.
* In spite of former [linuxmuster-linbo](https://github.com/linuxmuster/linuxmuster-linbo) images in cloop format where only supported for restore.
* For image creation only qcow2 format is supported. You have to change the baseimage name in the start.conf accordingly (e.g. image.qcow2).
* Supplemental macct and reg image files were now named without the image format part (e.g. image.macct and image.reg, former: image.cloop.macct etc.).
* [qemu-img](http://manpages.ubuntu.com/manpages/bionic/man1/qemu-img.1.html) is used for qcow2 image creation and restore.
* Only 64bit client hardware is supported.
* No more support for linuxmuster.net <=6.2.
* No differential imaging yet.
* Packages were published in the [lmn7-experimental repository](http://archive.linuxmuster.net/lmn7-experimental/).

## Migration
* Add following entry to `/etc/apt/sources.list.d/lmn7.list`:
  `deb http://archive.linuxmuster.net/ lmn7-experimental/`
  and perform a dist-upgrade. Note: This will deinstall the deprecated linuxmuster-linbo-common7 package.
* Convert your cloop images to qcow2 format with `linbo-cloop2qcow2`.
* Change the image name in the start.conf.
* Restart the image deployment services with `linbo-torrent|linbo-multicast restart`.
* See the status of the image deployment services with `systemctl status linbo-torrent|linbo-multicast`.
* Create and deploy images as usual.
* Note: Your current cloop images will be still available for client restauration after migration.
* Explore the new linbo-torrent tool:  
  ```
  Usage: /usr/sbin/linbo-torrent <start|stop|restart|reload|status|create|check> [torrent_file]

  Note:
   * The commands start, stop and restart may have optionally a torrent file
     as parameter. So the command is only processed to this certain file.
   * A torrent file parameter is mandatory with the commands create and check.
  ```  

## Features
* Kernel 5.10.x.
* qcow2 image format.
* More performant image deployment based on ctorrent and opentracker.

## In planning:
* place images in subdirs of /srv/linbo.
* start.conf in yaml format.
* step by step changeover of the scripting to python.

## Source tree structure
* build: all files, which are used to build the package.
  - bin: helper scripts (only get kernel archive script at the moment).
  - conf.d: environment variables definition for the various build components.
  - config: configuration files for various source packages (eg. busybox, kernel).
  - initramfs.d: initramfs configurations for the various components, which are picked from the ubuntu build system to create the linbofs system from it.
  - patches: source patches, which are to be applied (eg. cloop).
  - run.d: the build scripts for the package components.
* debian: debian packaging stuff
* linbofs: files, which are needed to be installed to the initramfs file system.
* serverfs: files, which are needed to be installed to the server root file system.

## Build instructions:
* Install 64bit Ubuntu 18.04
* If you are using Ubuntu server or minimal:
  `sudo apt install dpkg-dev`
* Install build depends (uses sudo):  
  `./get-depends.sh`
* Build package:  
  `./buildpackage.sh`  

Or for better convenience use the new [linbo-build-docker](https://github.com/linuxmuster/linbo-build-docker) environment.
