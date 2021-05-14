#!/bin/bash
#
# configure script for linuxmuster-linbo7 package
# thomas@linuxmuster.net
# 20210514
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

update-linbofs || exit 1

exit 0
