#!/bin/bash
# Publishes a new version of Compact as a GitHub Release, so friends can install it with:
#   curl -fsSL https://github.com/trishabthakkar/compact/releases/latest/download/install.sh | sh
#
# Usage: scripts/release.sh 1.1
# Needs the GitHub CLI (`brew install gh`, then `gh auth login` once).
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-}"
[[ "$VERSION" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]] || { echo "Usage: scripts/release.sh <version>, e.g. 1.1" >&2; exit 1; }
command -v gh >/dev/null || { echo "Install the GitHub CLI first: brew install gh && gh auth login" >&2; exit 1; }
[[ -z "$(git status --porcelain)" ]] || { echo "Commit your changes before releasing." >&2; exit 1; }

# Stamp the version into the app, then build the zip.
plutil -replace CFBundleShortVersionString -string "$VERSION" Resources/Info.plist
plutil -replace CFBundleVersion -string "$(git rev-list --count HEAD)" Resources/Info.plist
git commit -qm "release: $VERSION" Resources/Info.plist || true
git push -q origin HEAD:main

scripts/package-zip.sh
cp scripts/install.sh build/install.sh
shasum -a 256 build/Compact.zip | tee build/Compact.zip.sha256

gh release create "v$VERSION" build/Compact.zip build/install.sh build/Compact.zip.sha256 \
    --target "$(git rev-parse HEAD)" \
    --title "Compact $VERSION" \
    --notes "Install or update by pasting this into Terminal:

\`\`\`
curl -fsSL https://github.com/trishabthakkar/compact/releases/latest/download/install.sh | sh
\`\`\`"
echo "Released Compact $VERSION."
