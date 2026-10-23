## Troubleshooting
This document collects solutions to issues reported by users. It will be extended successively.

* **Internal display goes almost black right when sync starts, external monitor unaffected (Intel 8th-10th gen iGPUs)**: On some laptops with a PWM-controlled backlight (e.g. Kaby Lake, Coffee Lake, Ice Lake, Comet Lake), the backlight state gets lost during a DRM master switch (e.g. boot splash handing off the display to the Linbo gui) and only a full power-off restores normal brightness. Add the kernel parameter `i915.enable_dpcd_backlight=1` to the affected device's/group's `KernelOptions` in its `start.conf` to force AUX/DPCD based backlight control instead of PWM. Note: `acpi_backlight=native`/`acpi_backlight=vendor` do *not* help here, since they only choose between the ACPI-generic and the native GPU backlight interface, not between PWM and DPCD.

* **Image upload fails with `rsync error: requested action not supported (code 4)`**: The server only accepts image uploads (everything below `/srv/linbo/images`) from a client whose IP address belongs to a device in `devices.csv` with a registered machine account. Check with `lmncli devices <client ip>` on the server: the row with exactly that IP must show `Registered` in the `LDAP` column. Clients with a dynamic IP address are not accepted. Multi-school environments are not supported yet: uploads from devices of other schools are not checked at all for now (as before). Further reasons for a refusal:
  * A differential image (`.qdiff`) is uploaded, but its base image (`.qcow2`) does not exist on the server.
  * The image is not a `BaseImage` of the client's `start.conf` (an image under a new name) and its name contains other characters than letters, digits, `_` and `-`, or it is a differential image.
  * An image of that name already exists on the server and was not derived from a `BaseImage` of the client's `start.conf` (`sourceimage` in its info file), i.e. it would overwrite a foreign image.

  Refused uploads are logged with their reason in `/srv/linbo/log/rsync-pre-upload.log`.
