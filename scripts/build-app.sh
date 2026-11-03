#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release --arch arm64 "$@"
bin_dir="$(swift build -c release --arch arm64 --show-bin-path "$@")"
app_dir="$PWD/dist/Transcripted.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$bin_dir/Transcripted" "$app_dir/Contents/MacOS/Transcripted"
cp Resources/Info.plist "$app_dir/Contents/Info.plist"
codesign --force --sign "${SIGNING_IDENTITY:--}" "$app_dir"
printf 'Built %s\nLaunch with: open "%s"\n' "$app_dir" "$app_dir"
