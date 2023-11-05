# Example for a linbofs inittab file.
# Must be placed under /etc/linuxmuster/linbo/inittab.
# For more information see https://manpages.debian.org/unstable/sysvinit-core/inittab.5.en.html.
#
# thomas@linuxmuster.net
# 20231105
#

::respawn:/usr/bin/my_script.sh
::wait:/usr/bin/my_script.sh
