# example file for custom linbo kernel, used by update-linbofs
# to be placed under /etc/linuxmuster/linbo/custom_kernel
#
# thomas@linuxmuster.net
# 20231112
#

# use Linbo's alternative legacy kernel
# path to kernel image
KERNELPATH="/var/lib/linuxmuster/linbo/legacy/linbo64"
# path to the corresponding modules directory
MODULESPATH="/var/lib/linuxmuster/linbo/legacy/modules"

# the example below points to the currently active kernel image
# and modules used by the server
# path to kernel image
KERNELPATH="/boot/vmlinuz-$(uname -r)"
# path to the corresponding modules directory
MODULESPATH="/lib/modules/$(uname -r)"