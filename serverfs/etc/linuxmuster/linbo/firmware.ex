# Example file for firmware to be integrated in linbofs.
# One entry per line, path has to be relative to /lib/firmware.
# Must be provided under /etc/linuxmuster/linbo/firmware.
# Be sure to invoke update-linbofs after you have made changes.
#
# thomas@linuxmuster.net
# 20231016
#

# Realtek r8168 ethernet adaptors firmware (whole directory)
rtl_nic

# Realtek RTL8821AE wifi firmware (single file)
rtlwifi/rtl8821aefw.bin

# Intel Wi-Fi 6 AX200 firmware (single file)
iwlwifi-cc-a0-77.ucode
