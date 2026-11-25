#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Universal binary (Apple silicon + Intel). Multi-arch `--arch` needs Xcode's xcbuild, so build each
# architecture separately (command line tools only) and join them with lipo.
swift build -c release --triple arm64-apple-macosx14.0
swift build -c release --triple x86_64-apple-macosx14.0 --scratch-path .build-x86
ARM=$(swift build -c release --triple arm64-apple-macosx14.0 --show-bin-path)
X86=$(swift build -c release --triple x86_64-apple-macosx14.0 --scratch-path .build-x86 --show-bin-path)

APP=build/Compact.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create "$ARM/Compact" "$X86/Compact" -output "$APP/Contents/MacOS/Compact"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
for b in "$ARM"/*.bundle; do
  [ -e "$b" ] && cp -R "$b" "$APP/Contents/Resources/"
done
# Ad-hoc signature with a stable designated requirement: macOS remembers camera/mic
# permission by this requirement, so rebuilds keep the user's Allow instead of asking again.
codesign --force --deep --sign - -r='designated => identifier "com.compact.app"' "$APP"
echo "$PWD/$APP"
