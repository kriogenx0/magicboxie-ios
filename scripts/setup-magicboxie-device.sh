#!/usr/bin/env sh
set -euo pipefail

HOSTNAME="magicboxie-device"

if [ "$(uname -s)" != "Linux" ]; then
  echo "This script is intended for Raspberry Pi / Debian-based Linux."
  exit 1
fi

if ! command -v apt >/dev/null 2>&1; then
  echo "apt not found; this script expects Debian/Ubuntu/Raspbian."
  exit 1
fi

echo "Setting hostname to $HOSTNAME..."
sudo hostnamectl set-hostname "$HOSTNAME"

echo "Ensuring /etc/hosts contains an entry for $HOSTNAME..."
if ! grep -qE "127\\.0\\.1\\.1\\s+$HOSTNAME" /etc/hosts; then
  sudo sh -c 'printf "\n127.0.1.1 %s\n" "$HOSTNAME" >> /etc/hosts'
fi

echo "Installing Avahi for local network hostname resolution..."
sudo apt update
test -x /usr/sbin/avahi-daemon || sudo apt install -y avahi-daemon avahi-utils

echo "Enabling and starting Avahi daemon..."
sudo systemctl enable --now avahi-daemon

echo "Setup complete. The Pi should now be reachable as $HOSTNAME.local on the local network."
