# example file for custom linbo kernel, used by update-linbofs
# to be placed under /etc/linuxmuster/linbo/custom_kernel
#
# thomas@linuxmuster.net
# 20260518
#

# currently active kernel image and modules used by the server
# path to kernel image
KERNELPATH="/boot/vmlinuz-$(uname -r)"
# path to the corresponding modules directory
MODULESPATH="/lib/modules/$(uname -r)"

# custom kernel image and modules
KERNELPATH="/path/to/my/kernelimage"
# path to the corresponding modules directory
MODULESPATH="/path/to/my/lib/modules/n.n.n"