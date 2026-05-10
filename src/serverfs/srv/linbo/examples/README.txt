Examples for LINBO
---------------------------------------

Note: The Windows 10 examples should also be usable for Windows 11.

* For every Windows image there has to be a registry patch file in
  /srv/linbo/images/<imagename> according to this naming scheme:
  <imagename>.reg, e.g. win10.reg for image win10.qcow2.

* Inside the registry patch file the samba domainname has to be modified.

* The patch files may contain custom registry entries.

There are 3 templates:
* win10.image.reg: Registry patch for hostname and custom entries,
  which accompanies the image file.
* win10.global.reg: Necessary and optional registry entries (see
  comments in the file), which must be imported once before joining the domain
  and creating the image.
  Note: SAMBADOMAIN has to be replaced with the name of your sambadomain!
* win11bypass.reg: Bypasses the hardware checks during the Windows 11 setup (see
  https://www.deskmodder.de/wiki/index.php?title=Windows_11_auch_ohne_TPM_und_Secure_Boot_installieren).

---
thomas@linuxmuster.net
08.05.2023
