#!/bin/bash
# Builds Compact.app and zips it for sharing: build/Compact.zip
set -euo pipefail
cd "$(dirname "$0")/.."

scripts/build-app.sh
rm -f build/Compact.zip
ditto -c -k --keepParent build/Compact.app build/Compact.zip
echo "$PWD/build/Compact.zip"
