#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Cloudflare WARP Helper"
BUILD_DIR="$ROOT_DIR/build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
HELPER_DIR="$BUILD_DIR/helper"
ICON_SOURCE="$ROOT_DIR/Sources/applicationIcon.png"
ICONSET_DIR="$BUILD_DIR/applicationIcon.iconset"

rm -rf "$APP_DIR" \
  "$BUILD_DIR/Cloudflare WARP Toggle.app" \
  "$HELPER_DIR/cloudflare-warp-toggle-helper"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$HELPER_DIR"

if [ ! -f "$ICON_SOURCE" ]; then
  echo "App icon was not found: $ICON_SOURCE"
  exit 1
fi

swiftc \
  "$ROOT_DIR/Sources/WarpLauncher/main.swift" \
  -framework AppKit \
  -o "$MACOS_DIR/WarpLauncher"

swiftc \
  "$ROOT_DIR/Sources/WarpHelper/main.swift" \
  -o "$HELPER_DIR/cloudflare-warp-helper"

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>WarpLauncher</string>
  <key>CFBundleIdentifier</key>
  <string>local.cloudflare-warp-helper</string>
  <key>CFBundleName</key>
  <string>Cloudflare WARP Helper</string>
  <key>CFBundleDisplayName</key>
  <string>Cloudflare WARP Helper</string>
  <key>CFBundleIconFile</key>
  <string>applicationIcon.icns</string>
  <key>CFBundleIconName</key>
  <string>applicationIcon</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>11.0</string>
  <key>LSUIElement</key>
  <true/>
</dict>
</plist>
PLIST

rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"

sips -z 16 16 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
sips -z 64 64 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
sips -z 1024 1024 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null

iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/applicationIcon.icns"
cp "$ICON_SOURCE" "$RESOURCES_DIR/applicationIcon.png"
cp "$HELPER_DIR/cloudflare-warp-helper" "$RESOURCES_DIR/cloudflare-warp-helper"
rm -rf "$ICONSET_DIR"

chmod +x "$MACOS_DIR/WarpLauncher"
chmod +x "$HELPER_DIR/cloudflare-warp-helper"
chmod +x "$RESOURCES_DIR/cloudflare-warp-helper"
touch "$APP_DIR"

echo "Built: $APP_DIR"
echo "Built helper: $HELPER_DIR/cloudflare-warp-helper"
