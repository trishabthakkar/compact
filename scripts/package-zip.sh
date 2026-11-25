#!/bin/bash
# Builds Compact.app and zips it for sharing: build/Compact.zip
# The zip holds a folder with the app and "How to open Compact.txt" (a copy of the README).
set -euo pipefail
cd "$(dirname "$0")/.."

scripts/build-app.sh
STAGE=build/zip-stage/Compact
rm -rf build/zip-stage build/Compact.zip
mkdir -p "$STAGE"
cp -R build/Compact.app "$STAGE/Compact.app"
cp README.md "$STAGE/How to open Compact.txt"
ditto -c -k --norsrc --noextattr --keepParent "$STAGE" build/Compact.zip
rm -rf build/zip-stage
echo "$PWD/build/Compact.zip"
