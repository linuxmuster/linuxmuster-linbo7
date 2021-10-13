#!/bin/bash
#
# configure script for linuxmuster-linbo7 package
# thomas@linuxmuster.net
# 20211013
#

# read constants & setup values
. /usr/share/linuxmuster/defaults.sh

# config file backup dir
mkdir -p "$LINBODIR/backup"
# windows activation stuff
mkdir -p "$LINBODIR/winact"
# temp dir
mkdir -p "$LINBODIR/tmp"

# change owner of logdir to nobody
[ -d "$LINBOLOGDIR" ] || mkdir -p $LINBOLOGDIR
chown nobody $LINBOLOGDIR -R

# create dropbear ssh keys
if [ ! -s "$SYSDIR/linbo/ssh_host_rsa_key" ]; then
  ssh-keygen -t rsa -N "" -f $SYSDIR/linbo/ssh_host_rsa_key
  /usr/lib/dropbear/dropbearconvert openssh dropbear $SYSDIR/linbo/ssh_host_rsa_key $SYSDIR/linbo/dropbear_rsa_host_key
fi
if [ ! -s "$SYSDIR/linbo/ssh_host_dsa_key" ]; then
  ssh-keygen -t dsa -N "" -f $SYSDIR/linbo/ssh_host_dsa_key
  /usr/lib/dropbear/dropbearconvert openssh dropbear $SYSDIR/linbo/ssh_host_dsa_key $SYSDIR/linbo/dropbear_dss_host_key
fi

# provide grub menu background
wp_std="linbo_wallpaper_800x600.png"
wp_lnk="$LINBODIR/icons/linbo_wallpaper.png"
wp_grub="$LINBODIR/boot/grub/linbo_wallpaper.png"
rm -f "$wp_lnk" "$wp_grub"
ln -sf "$wp_std" "$wp_lnk"
cp -fL "$wp_lnk" "$wp_grub"

# create tftpd configs if necessary
conf="/etc/default/tftpd-hpa"
if ! grep -q "$LINBODIR" "$conf"; then
  echo "Patching $conf."
  cp "$conf" "$conf".dpkg-bak
  sed -i "s|^TFTP_DIRECTORY=.*|TFTP_DIRECTORY=\"$LINBODIR\"|" "$conf"
  tftpd_restart=yes
fi
[ -n "$tftpd_restart" ] && service tftpd-hpa restart

# create grub netboot directory
"$LINBOSHAREDIR/mkgrubnetdir.sh"

# remove deprecated linbo-bittorrent
if [ -e /etc/init.d/linbo-bittorrent ]; then
  systemctl stop linbo-bittorrent
  systemctl disable linbo-bittorrent
  pid="$(ps ax | grep bttrack | grep -v grep | awk '{print $1}')"
  [ -n "$pid" ] && kill $pid
  rm -f /etc/init.d/linbo-bittorrent
fi

# remove outdated linbo-multicast start script
if [ -e /etc/init.d/linbo-multicast ]; then
  # lookup for running udp-sender and save status
  ps ax | grep -v grep | grep -q udp-sender && RUNMCAST="yes"
  systemctl stop linbo-multicast
  systemctl disable linbo-multicast
  rm -f /etc/init.d/linbo-multicast
fi

# apply any systemd changes
systemctl daemon-reload

# opentracker
if ! systemctl status opentracker &> /dev/null; then
  systemctl enable opentracker
  systemctl start opentracker
fi

# do the rest only on configured systems
[ -e "$SETUPINI" ] || exit 0

# update serverip in start.conf
echo "Setting correct serverip in start.conf examples."
for i in $LINBODIR/start.conf $LINBODIR/examples/start.conf.*; do
if ! grep -qi ^"Server = $serverip" "$i"; then
  sed -i "s/^[Ss][Ee][Rr][Vv][Ee][Rr] = \([0-9]\{1,3\}[.]\)\{3\}[0-9]\{1,3\}/Server = $serverip/" "$i"
fi
done

# linbo-torrent service
if ! systemctl status linbo-torrent &> /dev/null; then
  systemctl enable linbo-torrent
  systemctl start linbo-torrent
fi

# activate linbo-multicast service if it was running before
if [ -n "$RUNMCAST" ]; then
  systemctl enable linbo-multicast
  systemctl start linbo-multicast
fi

update-linbofs || exit 1

exit 0
