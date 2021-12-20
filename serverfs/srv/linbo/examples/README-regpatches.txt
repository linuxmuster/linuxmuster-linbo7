Registry patches for LINBO
---------------------------------------

* For every Windows image there has to be a registry patch file in
  /srv/linbo/images/<imagename> according to this naming scheme:
  <imagename>.reg, e.g. win10.reg for image win10.qcow2.

* Inside the registry patch file the samba domainname has to be modified.

* The patch files may contain custom registry entries.

There are two templates:
* win10.image.reg: Registry patch for hostname and custom entries,
  which accompanies the image file.
* win10.global.reg: Necessary and optional registry entries (see
  comments in the file), which must be imported once before joining the domain
  and creating the image.
  Note: SAMBADOMAIN has to be adapted!

---
thomas@linuxmuster.net
20.12.2021
