# Example file for firmware to be integrated in linbofs.
# One entry per line, path has to be relative to /lib/firmware.
# Must be provided under /etc/linuxmuster/linbo/firmware.
# Be sure to invoke update-linbofs after you have made changes.
#
# thomas@linuxmuster.net
# 20240920
#

# all firmware files for Realtek ethernet adaptors (content of whole directory will be packed)
rtl_nic

# all firmware files for Realtek wifi adaptors (content of whole directory will be packed)
rtlwifi

# Realtek RTL8821AE wifi firmware (single file only)
rtlwifi/rtl8821aefw.bin

# Intel Wi-Fi 6 AX200 firmware (single file only)
iwlwifi-cc-a0-77.ucode
