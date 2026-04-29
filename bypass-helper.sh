#!/bin/zsh
set -euo pipefail

APP_PATH="/Applications/Cloudflare WARP Helper.app"

if [ ! -d "$APP_PATH" ]; then
  echo "Application was not found: $APP_PATH"
  echo "Copy Cloudflare WARP Helper.app to Applications, then run this script again."
  exit 1
fi

xattr -cr "$APP_PATH"

echo "Removed quarantine attributes from: $APP_PATH"
