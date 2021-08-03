<img src="https://raw.githubusercontent.com/linuxmuster/linuxmuster-artwork/master/linbo/linbo_logo_small.svg" alt="linbo icon" width="200"/>

# linuxmuster-linbo7 (next generation)
 is the free and opensource imaging solution for linuxmuster.net 7. It handles Windows 10 and Linux 64bit operating systems. Via TFTP and Grub's PXE implementation it boots a small linux system (linbofs) with a [gui](https://github.com/linuxmuster/linuxmuster-linbo-gui7), which can manage all the imaging tasks on the client. Console tools are also available to manage clients and imaging remotely via the server.

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
* Add following entry to `/etc/apt/sources.list.d/lmn7.list`:
  `deb http://archive.linuxmuster.net/ lmn7-testing/`
  and perform a dist-upgrade.
* Convert your cloop images to qcow2 format with `linbo-cloop2qcow2`:
  - invoke for example `linbo-cloop2qcow2 ubuntu.cloop` and
  - the converted image will be created in `/srv/linbo/images/ubuntu/ubuntu.qcow2`.
* Change the image name in the start.conf.
* Restart the image deployment services with `linbo-torrent|linbo-multicast restart`.
* See the status of the image deployment services with `systemctl status linbo-torrent|linbo-multicast`.
* Finally start the import script `linuxmuster-import-devices`, which will remove the obsolete start.conf links.
* Now you can create and deploy images as usual.
* Explore the new linbo-torrent tool:  
  ```
  Usage: /usr/sbin/linbo-torrent <start|stop|restart|reload|status|create|check> [torrent_filename|image_filename]

  Note:
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

## Source tree structure
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

## Build instructions:
* Install 64bit Ubuntu 18.04
* If you are using Ubuntu server or minimal:
  `sudo apt install dpkg-dev`
* Install build depends (uses sudo):  
  `./get-depends.sh`
* Build package:  
  `./buildpackage.sh`  

Or for better convenience use the new [linbo-build-docker](https://github.com/linuxmuster/linbo-build-docker) environment.
