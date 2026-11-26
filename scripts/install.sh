#!/bin/sh
# Installs (or updates) Compact from the latest GitHub release.
#
#   curl -fsSL https://github.com/trishabthakkar/compact/releases/latest/download/install.sh | sh
#
# For testing: COMPACT_ZIP_URL overrides the download, COMPACT_INSTALL_DIR the destination,
# and COMPACT_NO_OPEN=1 skips opening the app afterwards.
set -eu

REPO="trishabthakkar/compact"
URL="${COMPACT_ZIP_URL:-https://github.com/${REPO}/releases/latest/download/Compact.zip}"

say() { printf '%s\n' "$*"; }
fail() { say "✗ $*" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || fail "Compact only runs on a Mac."
major=$(sw_vers -productVersion | cut -d. -f1)
[ "${major}" -ge 14 ] || fail "Compact needs macOS 14 (Sonoma) or newer. This Mac has $(sw_vers -productVersion)."

# Install to /Applications when we can write there, otherwise to ~/Applications.
if [ -n "${COMPACT_INSTALL_DIR:-}" ]; then
    DEST="${COMPACT_INSTALL_DIR}"
elif [ -w /Applications ]; then
    DEST=/Applications
else
    DEST="${HOME}/Applications"
fi
mkdir -p "${DEST}"

TMP=$(mktemp -d)
trap 'rm -rf "${TMP}"' EXIT

say "→ Downloading Compact…"
curl -fsSL "${URL}" -o "${TMP}/Compact.zip" || fail "Couldn't download Compact. Check your internet connection and try again."
ditto -x -k "${TMP}/Compact.zip" "${TMP}/unzipped" || fail "The download looks damaged. Try again."
APP=$(find "${TMP}/unzipped" -maxdepth 3 -name Compact.app -type d | head -n 1)
[ -n "${APP}" ] || fail "The download didn't contain Compact.app."

# Quit a running copy so it can be replaced (it finishes saving any recording first).
if pgrep -x Compact >/dev/null 2>&1; then
    say "→ Quitting the running copy of Compact…"
    osascript -e 'tell application id "com.compact.app" to quit' >/dev/null 2>&1 || pkill -x Compact || true
    i=0
    while pgrep -x Compact >/dev/null 2>&1 && [ ${i} -lt 15 ]; do sleep 1; i=$((i + 1)); done
fi

say "→ Installing to ${DEST}…"
rm -rf "${DEST}/Compact.app"
ditto "${APP}" "${DEST}/Compact.app"
# Only needed if the app came through a browser; harmless otherwise.
xattr -dr com.apple.quarantine "${DEST}/Compact.app" 2>/dev/null || true

say "✓ Compact is installed in ${DEST}."
if [ -z "${COMPACT_NO_OPEN:-}" ]; then
    open "${DEST}/Compact.app"
    say "  Look for the lipstick in your menu bar (top right). Click Allow when it asks for the camera and microphone."
fi
