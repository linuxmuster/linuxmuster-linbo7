![linbo icon](files/srv/linbo/boot/grub/themes/linbo/linbo_logo_big.png)  

# linuxmuster-linbo7 (next generation)

 is the free and opensource imaging solution for linuxmuster.net 7. It handles Windows 10 and Linux 64bit operating systems. Via TFTP and Grub's PXE implementation it boots a small linux system (linbofs) with a [gui](https://github.com/linuxmuster/linuxmuster-linbo-gui7), which can manage all the imaging tasks on the client. Console tools are also available to manage clients and imaging remotely via the server.

Important notices:
* The code in this repo is currently experimental.
* In spite of former [linuxmuster-linbo](https://github.com/linuxmuster/linuxmuster-linbo) images in cloop format where only supported for restore.
* For image creation only qcow2 format is supported. You have to change the baseimage name in the start.conf accordingly (e.g. image.qcow2).
* [qemu-img](http://manpages.ubuntu.com/manpages/bionic/man1/qemu-img.1.html) is used for qcow2 image creation and restore.
* Only 64bit client hardware is supported.
* No more support for linuxmuster.net <=6.2.
* No differential imaging yet.
* Packages were published in the [lmn7-experimental repository](http://archive.linuxmuster.net/lmn7-experimental/).

Build instructions:

* Install 64bit Ubuntu 18.04

* If you are using Ubuntu server or minimal:
  `sudo apt install dpkg-dev`

* Install build depends (uses sudo):  
  `./get-depends.sh`

* Build package:  
  `./buildpackage.sh`
