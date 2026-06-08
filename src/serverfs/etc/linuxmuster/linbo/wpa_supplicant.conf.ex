# A simple wpa_supplicant config example.
# For more examples see https://linux.die.net/man/5/wpa_supplicant.conf.
# Must be provided under /etc/linuxmuster/linbo/wpa_supplicant.conf.
#
# thomas@linuxmuster.net
# 20260608
#

# Disable P2P (Peer-to-Peer) interface creation to avoid "nl80211: Could not set interface 'p2p-dev-wlan0' UP" errors.
# This is required for Ubuntu 26.04+ where some wireless drivers don't support P2P interfaces.
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
