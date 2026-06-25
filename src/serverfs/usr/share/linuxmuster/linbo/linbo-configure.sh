#!/bin/bash
#
# configure script for linuxmuster-linbo7 package
# thomas@linuxmuster.net
# 20260625
#

# read environment & setup values
. /usr/share/linuxmuster/helperfunctions.sh

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

# apply any systemd changes
systemctl daemon-reload

# do the rest only on configured systems
[ -e "$SETUPINI" ] || exit 0

# remove remnants of old opentracker service if it exists
conf="/etc/systemd/system/opentracker.service"
if [ -e "$conf" ]; then
  systemctl stop opentracker
  systemctl disable opentracker
  rm -f "$conf"
  systemctl daemon-reload
fi

# check linbo's multicast and torrent services
for service in linbo-multicast linbo-torrent; do
  tpl="$TPLDIR/$service"
  conf="$(get_confpath "$tpl")"
  changed=""
  if [ ! -e "$conf" ]; then
    # services should be restarted if config file was changed
    changed="yes"
    # copy missing config file from template
    cp "$tpl" "$conf"
  fi
  # copy linbo-torrent config file if does not contain aria2c options
  if [ "$service" = "linbo-torrent" -a -z "$(grep ^ARIA2C "$conf")" ]; then
    changed="yes"
    cp "$tpl" "$conf"
  fi
  # enable linbo-torrent service if necessary
  [ "$service" = "linbo-torrent" -a "$(systemctl is-enabled "$service" 2>/dev/null)" = "disabled" ] && systemctl enable "$service"
  # restart service if config file was changed
  if [ -n "$changed" ]; then
    case "$service" in
      # restart linbo-multicast if config file was copied and service is enabled
      linbo-multicast) systemctl is-enabled "$service" &> /dev/null && systemctl restart "$service" ;;
      # restart linbo-torrent if config file was copied and enable service if necessary
      *) systemctl restart "$service" ;;
    esac
  elif [ "$service" = "linbo-torrent" ]; then
    # start linbo-torrent if not running and config file was not changed
    systemctl is-active "$service" &> /dev/null || systemctl start "$service"
  fi
done

# enable and start opentracker again
systemctl is-enabled opentracker &> /dev/null || systemctl enable opentracker
systemctl is-active opentracker &> /dev/null || systemctl start opentracker

# check for linbo compliant opentracker config and create it if not
tpl="$TPLDIR/opentracker.conf"
conf="$(get_confpath "$tpl")"
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
conf="$(get_confpath "$tpl")"
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
