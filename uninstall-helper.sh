#!/bin/zsh
set -euo pipefail

PLIST_DEST="/Library/LaunchDaemons/local.cloudflare-warp-helper.plist"
HELPER_DEST="/Library/PrivilegedHelperTools/local.cloudflare-warp-helper"
SOCKET_PATH="/var/run/cloudflare-warp-helper.sock"
OLD_PLIST_DEST="/Library/LaunchDaemons/local.cloudflare-warp-toggle.helper.plist"
OLD_HELPER_DEST="/Library/PrivilegedHelperTools/local.cloudflare-warp-toggle.helper"
OLD_SOCKET_PATH="/var/run/cloudflare-warp-toggle.sock"

sudo launchctl bootout system "$PLIST_DEST" 2>/dev/null || true
sudo launchctl bootout system "$OLD_PLIST_DEST" 2>/dev/null || true
sudo rm -f "$PLIST_DEST" "$HELPER_DEST" "$SOCKET_PATH" \
  "$OLD_PLIST_DEST" "$OLD_HELPER_DEST" "$OLD_SOCKET_PATH"

echo "Removed helper: local.cloudflare-warp-helper"
