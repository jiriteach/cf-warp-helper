# Cloudflare WARP Helper

A native macOS launcher that toggles Cloudflare WARP. Designed due to allow for the Cloudlare WARP application to be opened and closed with one-click since there is no close open when using Cloudflare One. Also does not require an administrator password each time it runs.

- On start: shows `Checking ...` while it verifies that Cloudflare WARP is installed and gets the version .
- If installed: shows `Launching ...` or `Closing ...` for 2 seconds while it toggles Cloudflare WARP.
- If not installed: shows `Not Installed - Download` with `Download` linked to the Cloudflare macOS installer, plus a close button.

## How No Password Launching Works

macOS requires root privileges to load or unload `/Library/LaunchDaemons`. To avoid a password prompt every time, this project installs a small root-owned helper once as a LaunchDaemon.

The launcher app talks to that helper over a local Unix socket. The one-time helper install uses `sudo`; normal launch and close actions do not.

If the launcher is opened before the helper has been installed, it offers an `Install` button and installs the bundled helper immediately.

## Build

```sh
./build.sh
```

This creates:

```text
build/Cloudflare WARP Helper.app
build/helper/cloudflare-warp-helper
build/Cloudflare WARP Helper.dmg
```

The DMG contains:

```text
Cloudflare WARP Helper.app
Applications
install-helper.sh
uninstall-helper.sh
bypass-helper.sh
```

## Install From DMG

After opening the DMG, copy `Cloudflare WARP Helper.app` to `Applications`.

If macOS Gatekeeper prevents the app from opening, run the included bypass script:

```sh
./bypass-helper.sh
```

The script removes quarantine attributes from the installed app:

```sh
xattr -cr "/Applications/Cloudflare WARP Helper.app"
```

## Install Helper

Run this once after building:

```sh
./install-helper.sh
```

## Use

Double-click:

```text
build/Cloudflare WARP Helper.app
```

## Uninstall Helper

```sh
./uninstall-helper.sh
```

## Cloudflare Paths

The launcher expects the normal Cloudflare WARP install paths:

- `/Applications/Cloudflare WARP.app`
- `/Library/LaunchDaemons/com.cloudflare.1dot1dot1dot1.macos.warp.daemon.plist`
