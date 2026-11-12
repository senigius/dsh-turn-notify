#!/usr/bin/env bash
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
app="${1:-"$here/../build/DSHNotify.app"}"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "error: the helper app can only be built on macOS" >&2
  exit 1
fi

cache="${DSH_NOTIFY_MODULE_CACHE:-"$here/../build/module-cache"}"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$cache"
cp "$here/Info.plist" "$app/Contents/Info.plist"
swiftc -O "$here/main.swift" -o "$app/Contents/MacOS/DSHNotify" \
  -module-cache-path "$cache" \
  -framework AppKit -framework UserNotifications
codesign --force --sign - "$app" >/dev/null 2>&1 || true

echo "built $app"
