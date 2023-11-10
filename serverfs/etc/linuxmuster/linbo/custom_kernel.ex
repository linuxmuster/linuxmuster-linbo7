# example file for custom linbo kernel, used by update-linbofs
# to be placed under /etc/linuxmuster/linbo/custom_kernel
#
# thomas@linuxmuster.net
# 20231110
#

# the example below points to the currently active kernel image
# and modules used by the server

# path to kernel image
KERNELPATH="/boot/vmlinuz-$(uname -r)"

# path to the corresponding modules directory
MODULESPATH="/lib/modules/$(uname -r)"