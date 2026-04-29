#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
HELPER_SOURCE="$ROOT_DIR/build/helper/cloudflare-warp-helper"
HELPER_DEST="/Library/PrivilegedHelperTools/local.cloudflare-warp-helper"
PLIST_DEST="/Library/LaunchDaemons/local.cloudflare-warp-helper.plist"

if [ ! -x "$HELPER_SOURCE" ]; then
  echo "Helper binary was not found. Run ./build.sh first."
  exit 1
fi

sudo install -o root -g wheel -m 755 "$HELPER_SOURCE" "$HELPER_DEST"

sudo tee "$PLIST_DEST" >/dev/null <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>local.cloudflare-warp-helper</string>
  <key>ProgramArguments</key>
  <array>
    <string>$HELPER_DEST</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>/var/log/cloudflare-warp-helper.log</string>
  <key>StandardErrorPath</key>
  <string>/var/log/cloudflare-warp-helper.log</string>
</dict>
</plist>
PLIST

sudo chown root:wheel "$PLIST_DEST"
sudo chmod 644 "$PLIST_DEST"

sudo launchctl bootout system "$PLIST_DEST" 2>/dev/null || true
sudo launchctl bootstrap system "$PLIST_DEST"
sudo launchctl bootout system /Library/LaunchDaemons/local.cloudflare-warp-toggle.helper.plist 2>/dev/null || true
sudo rm -f /Library/LaunchDaemons/local.cloudflare-warp-toggle.helper.plist \
  /Library/PrivilegedHelperTools/local.cloudflare-warp-toggle.helper \
  /var/run/cloudflare-warp-toggle.sock

sudo launchctl enable system/local.cloudflare-warp-helper
sudo launchctl kickstart -k system/local.cloudflare-warp-helper

echo "Installed and started helper: local.cloudflare-warp-helper"
