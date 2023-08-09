#!/bin/bash
#
# configure script for linuxmuster-linbo7 package
# thomas@linuxmuster.net
# 20230801
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
for i in rsa dsa; do
  if [ "$i" = "dsa" ]; then
    db_key="${SYSDIR}/linbo/dropbear_dss_host_key"
  else
    db_key="${SYSDIR}/linbo/dropbear_${i}_host_key"
  fi
  ssh_key="${SYSDIR}/linbo/ssh_host_${i}_key"
  if [ ! -s "$db_key" ]; then
    rm -f "$ssh_key"*
    ssh-keygen -m PEM -t "$i" -N "" -f "$ssh_key"
    /usr/lib/dropbear/dropbearconvert openssh dropbear "$ssh_key" "$db_key"
  fi
done

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

# do the rest only on configured systems
[ -e "$SETUPINI" ] || exit 0

# update serverip in start.conf
echo "Setting serverip in start.conf examples."
for i in $LINBODIR/start.conf $LINBODIR/examples/start.conf.*; do
  if ! grep -qi ^"Server = $serverip" "$i"; then
    sed -i "s/^[Ss][Ee][Rr][Vv][Ee][Rr] = \([0-9]\{1,3\}[.]\)\{3\}[0-9]\{1,3\}/Server = $serverip/" "$i"
  fi
done

# activate linbo-multicast service if it was running before migration
if [ -n "$RUNMCAST" ]; then
  systemctl enable linbo-multicast.service
  systemctl restart linbo-multicast.service
fi

# check services
for i in opentracker linbo-torrent linbo-multicast; do
  if systemctl is-enabled $i.service &> /dev/null; then
    if ! systemctl is-active $i.service &> /dev/null; then
      systemctl start $i.service
    fi
  else
    echo "$i.service is disabled. Consider to enable and start it via systemctl."
  fi
done

# repair ssh_config
conf="$SYSDIR/linbo/ssh_config"
lmn71_string="PubkeyAcceptedKeyTypes=+ssh-dss"
if grep -q "$lmn71_string" "$conf"; then
  cp "$conf" "${conf}.lmn71"
  lmn72_string="HostKeyAlgorithms +ssh-rsa"
  sed -i "s|$lmn71_string|$lmn72_string|" "$conf"
fi

# provide rsync service override
tpl="$TPLDIR/rsync.override.conf"
conf="$(head -1 "$tpl" | awk '{print $2}')"
if [ ! -s "$conf" ]; then
  mkdir -p "$(dirname "$conf")"
  cp -f "$tpl" "$conf"
  systemctl daemon-reload
  systemctl restart rsync.service
fi

update-linbofs || exit 1

exit 0
