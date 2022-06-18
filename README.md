<img src="https://raw.githubusercontent.com/linuxmuster/linuxmuster-artwork/master/linbo/linbo_logo_small.svg" alt="linbo icon" width="200"/>

# linuxmuster-linbo7 (next generation)
 is the free and opensource imaging solution for linuxmuster.net 7. It handles Windows 10 and Linux 64bit operating systems. Via TFTP and Grub's PXE implementation it boots a small linux system (linbofs) with a [gui](https://github.com/linuxmuster/linuxmuster-linbo-gui), which can manage all the imaging tasks on the client. Console tools are also available to manage clients and imaging remotely via the server.

 ## Features
 * Kernel >5.18.
 * qcow2 image format.
 * Differential images.
 * Complete [refactoring of linbo_cmd](https://github.com/linuxmuster/linuxmuster-linbo7/issues/72).
 * switch to new ntfs3 kernel driver.

## Important notices:
* Currently the code in this repo is not for production use. For the currently stable version go to [branch 4.0](https://github.com/linuxmuster/linuxmuster-linbo7/tree/4.0).
* The [README](https://github.com/linuxmuster/linuxmuster-linbo7/tree/4.0#readme) for the stable version is still valid.
* Packages were published in the [lmn72 testing repository](https://github.com/linuxmuster/deb).

## Migration from linuxmuster.net 7.1
* Perform a two step upgrade of the server from Ubuntu 18.04 to 20.04 and finally to 22.04 using `do-release-upgrade`.
* Reconfigure the linuxmuster packages (webui package may fail for the moment):
  `dpkg-reconfigure sophomorix-samba linuxmuster-base7 linuxmuster-webui7`
* Reactivate the lmn71 repo (`/etc/apt/sources-list.d/lmn71.list.distUpgrade`).
* Add the lmn72 repo according to this instruction https://github.com/linuxmuster/deb/blob/main/README.md#setup
* Perform a dist-upgrade subsequently.

## Differential imaging
* Differential imagefile uses the qcow2 baseimage as so called *backingstore*.
* Differential image gets extension `qdiff`: `image.qdiff` -> `image.qcow2`.
* the diffimage will be created in the same directory as the baseimage, so they are virtually "bundled".
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
* Diffimage wll be restored file-based:
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
  `linbo-remote -c|-p create_qdiff:1 ...`
  `linbo_wrapper create_qdiff:1`
  `linbo_cmd create /dev/sda4 image.qdiff /dev/sda1`
* Image upload accordingly:
  `linbo-remote -c|-p upload_qdiff:1 ...`
  `linbo_wrapper upload_qdiff:1`
  `linbo_cmd upload 10.0.0.1 linbo geheim /dev/sda4 image.qdiff`

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

## Usage infos

### linbo-remote
gets two new commands for differential imaging:
```
create_qdiff:<#>:<"msg"> : Creates a differential image from operating system nr <#>.
upload_qdiff:<#>         : Uploads a differential image from operating system nr <#>.
```

Further infos see [README](https://github.com/linuxmuster/linuxmuster-linbo7/tree/4.0#readme) of stable branch.
