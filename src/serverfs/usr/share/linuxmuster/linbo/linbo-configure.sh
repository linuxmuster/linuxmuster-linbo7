#!/bin/bash
#
# configure script for linuxmuster-linbo7 package
# thomas@linuxmuster.net
# 20260518
#

# read environment & setup values
. /usr/share/linuxmuster/environment.sh

# config file backup dir
mkdir -p "$LINBODIR/backup"
# temp dir
mkdir -p "$LINBODIR/tmp"

# change owner of logdir to nobody
[ -d "$LINBOLOGDIR" ] || mkdir -p $LINBOLOGDIR
chown nobody $LINBOLOGDIR -R

# create dropbear ssh keys
for i in rsa ecdsa ed25519; do
  db_key="${SYSDIR}/linbo/dropbear_${i}_host_key"
  ssh_key="${SYSDIR}/linbo/ssh_host_${i}_key"
  if [ ! -s "$db_key" ]; then
    rm -f "$ssh_key" "${ssh_key}.pub"y
    ssh-keygen -m PEM -t "$i" -N "" -f "$ssh_key"
    /usr/lib/dropbear/dropbearconvert openssh dropbear "$ssh_key" "$db_key"
  fi
done

# provide grub menu background
wp_std="linbo_wallpaper_800x600.png"
wp_lnk="$LINBODIR/icons/linbo_wallpaper.png"
wp_grub="$LINBOGRUBDIR/linbo_wallpaper.png"
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

# remove deprecated linbo-bittorrent stuff
[ -e /etc/default/linbo-bittorrent ] && rm -f /etc/default/linbo-bittorrent
[ -e /etc/default/bittorrent ] && rm -f /etc/default/bittorrent

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

# activate linbo-multicast service if it was running before migration
if [ -n "$RUNMCAST" ]; then
  systemctl enable linbo-multicast.service
  systemctl restart linbo-multicast.service
fi

# check necessary services
for i in opentracker linbo-torrent; do
  systemctl is-enabled $i.service &> /dev/null || systemctl enable $i.service
  systemctl is-active $i.service &> /dev/null || systemctl start $i.service
done

# check for linbo compliant opentracker config and create it if not
tpl="$TPLDIR/opentracker.conf"
conf="$(head -1 "$tpl" | awk '{print $2}')"
if ! grep -q "$OTRDIR" "$conf" 2>/dev/null; then
  mkdir -p "$(dirname "$conf")"
  [ -e "$conf" ] && cp "$conf" "${conf}.dpkg-bak"
  sed -e "s|@@otrdir@@|$OTRDIR|g
          s|@@otrwlist@@|$OTRWLIST|g
          s|@@serverip@@|$serverip|g" "$tpl" > "$conf"
  mkdir -p "$OTRDIR"
  chown "$OTRUSER":"$OTRUSER" "$OTRDIR" -R
  linbo-torrent update-otr
fi

# repair ssh_config
conf="$LINBOSYSDIR/ssh_config"
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

# rename linbofs64
if grep -q linbofs64.lz "$LINBOGRUBDIR"/*.cfg; then
  echo "Note: Name of linbofs64.lz has changed to linbofs64. We will change this"
  echo "in your grub configs now. A backup of your files will be made with the"
  echo "extension dpkg-bak. Anyway, run linuxmuster-import-devices to update"
  echo "your configuration afterwards."
  for i in "$LINBOGRUBDIR"/*.cfg; do
    if grep -q linbofs64.lz "$i"; then
      echo " * $(basename $i)"
      cp "$i" "${i}.dpkg-bak"
      sed -i 's|linbofs64.lz|linbofs64|g' "$i"
    fi
  done
fi

update-linbofs || exit 1

exit 0
