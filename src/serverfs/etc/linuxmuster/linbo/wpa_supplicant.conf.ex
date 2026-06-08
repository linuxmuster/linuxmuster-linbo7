# A simple wpa_supplicant config example.
# For more examples see https://linux.die.net/man/5/wpa_supplicant.conf.
# Must be provided under /etc/linuxmuster/linbo/wpa_supplicant.conf.
#
# thomas@linuxmuster.net
# 20260608
#

# disable P2P (Peer-to-Peer) interface creation, unecessary for Linbo
p2p_disabled=1

# wpa-psk secured
network={
  ssid="LINBO_MGMT"
  scan_ssid=1
  key_mgmt=WPA-PSK
  psk="My Secret Passphrase"
}

# open
network={
   ssid="LINBO_MGMT"
   key_mgmt=NONE
}
