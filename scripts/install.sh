#!/bin/sh
# Install or re-peer NetBird on a JetKVM device. Run directly on the
# device over SSH as root:
#
#   NB_MANAGEMENT_URL=https://mesh.example.com \
#   NB_SETUP_KEY=XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX \
#   sh install.sh
#
# Env vars:
#   NB_MANAGEMENT_URL  required.
#   NB_SETUP_KEY       required only for a first-time registration (no
#                       existing peer state, or after NB_CLEAN_INSTALL).
#   NETBIRD_VERSION    release tag, e.g. "0.78.1". Default: latest.
#   NB_CLEAN_INSTALL   "true" logs out and wipes existing peer state
#                       first, forcing a new peer identity.
#   NB_EXTRA_UP_ARGS   extra flags appended to the `netbird up` call.
#
# Safe to re-run. See docs/netbird-behavior.md for background on the
# design decisions below.

set -e

: "${NETBIRD_VERSION:=latest}"

if [ -z "$NB_MANAGEMENT_URL" ]; then
  echo "NB_MANAGEMENT_URL is required" >&2
  exit 1
fi

INSTALL_DIR="/userdata/netbird"
STATE_DIR="$INSTALL_DIR/state"
BIN="$INSTALL_DIR/netbird"
INIT_SCRIPT="/userdata/init.d/S50netbird"
TMP_DIR="$INSTALL_DIR/.install-tmp"

SCRIPT_DIR="$(dirname "$0")"

if [ "${NB_CLEAN_INSTALL:-false}" = "true" ] && [ -f "$STATE_DIR/default.json" ]; then
  echo "NB_CLEAN_INSTALL=true - logging out existing peer and wiping state..."
  if [ -x "$BIN" ]; then
    "$BIN" down --config "$STATE_DIR/default.json" 2>/dev/null || true
    "$BIN" logout --config "$STATE_DIR/default.json" 2>/dev/null || true
  fi
  if [ -x "$INIT_SCRIPT" ]; then
    "$INIT_SCRIPT" stop 2>/dev/null || true
    sleep 1
  fi
  rm -rf "$STATE_DIR"
fi

if [ ! -f "$STATE_DIR/default.json" ] && [ -z "$NB_SETUP_KEY" ]; then
  echo "NB_SETUP_KEY is required (no existing peer state - first-time registration)" >&2
  exit 1
fi

mkdir -p "$INSTALL_DIR" "$STATE_DIR" /userdata/init.d
rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"

# Plain-text record of the management URL, read back by netbird-init.sh
# and update.sh. See docs/netbird-behavior.md#management-url.
echo "$NB_MANAGEMENT_URL" > "$INSTALL_DIR/management-url.txt"

# See docs/jetkvm-behavior.md#no-ca-trust-store.
echo "Installing CA trust bundle..."
cp "$SCRIPT_DIR/ca-certificates.crt" "$INSTALL_DIR/ca-certificates.crt"
export SSL_CERT_FILE="$INSTALL_DIR/ca-certificates.crt"

if [ "$NETBIRD_VERSION" = "latest" ]; then
  echo "Resolving latest NetBird release..."
  RESOLVED_VERSION="$(wget -qO- https://api.github.com/repos/netbirdio/netbird/releases/latest \
    | sed -n 's/.*"tag_name": *"v\{0,1\}\([^"]*\)".*/\1/p')"
  if [ -z "$RESOLVED_VERSION" ]; then
    echo "Failed to resolve latest version from GitHub API" >&2
    exit 1
  fi
else
  RESOLVED_VERSION="$NETBIRD_VERSION"
fi
echo "Installing NetBird v$RESOLVED_VERSION (linux_armv6)"

ASSET="netbird_${RESOLVED_VERSION}_linux_armv6.tar.gz"
CHECKSUMS="netbird_${RESOLVED_VERSION}_checksums.txt"
BASE_URL="https://github.com/netbirdio/netbird/releases/download/v${RESOLVED_VERSION}"

echo "Downloading $ASSET..."
wget -qO "$TMP_DIR/$ASSET" "$BASE_URL/$ASSET"
wget -qO "$TMP_DIR/$CHECKSUMS" "$BASE_URL/$CHECKSUMS"

echo "Verifying checksum..."
EXPECTED="$(grep "  $ASSET\$" "$TMP_DIR/$CHECKSUMS" | awk '{print $1}')"
if [ -z "$EXPECTED" ]; then
  echo "Could not find checksum for $ASSET in $CHECKSUMS" >&2
  exit 1
fi
ACTUAL="$(sha256sum "$TMP_DIR/$ASSET" | awk '{print $1}')"
if [ "$EXPECTED" != "$ACTUAL" ]; then
  echo "Checksum mismatch: expected $EXPECTED, got $ACTUAL" >&2
  exit 1
fi
echo "Checksum OK"

echo "Extracting..."
tar xzf "$TMP_DIR/$ASSET" -C "$TMP_DIR" netbird

if [ -x "$INIT_SCRIPT" ]; then
  "$INIT_SCRIPT" stop 2>/dev/null || true
  sleep 1
fi

mv "$TMP_DIR/netbird" "$BIN.new"
chmod +x "$BIN.new"
mv "$BIN.new" "$BIN"
rm -rf "$TMP_DIR"
echo "Installed $BIN ($($BIN version 2>&1 | head -1))"

echo "Writing boot script ($INIT_SCRIPT)..."
cp "$SCRIPT_DIR/netbird-init.sh" "$INIT_SCRIPT"
chmod +x "$INIT_SCRIPT"

echo "Installing watchdog..."
cp "$SCRIPT_DIR/watchdog.sh" "$INSTALL_DIR/watchdog.sh"
chmod +x "$INSTALL_DIR/watchdog.sh"

# crond, its crontab, and the tun module are all handled by
# netbird-init.sh's start action, run fresh on every boot. See
# docs/jetkvm-behavior.md#boot-process-and-userdata.
echo "Starting NetBird daemon..."
"$INIT_SCRIPT" start
sleep 2

echo "Peering (netbird up)..."
UP_ARGS="up --config $STATE_DIR/default.json --management-url $NB_MANAGEMENT_URL"
[ -n "$NB_SETUP_KEY" ] && UP_ARGS="$UP_ARGS --setup-key $NB_SETUP_KEY"

# shellcheck disable=SC2086
timeout 30 "$BIN" $UP_ARGS $NB_EXTRA_UP_ARGS

echo ""
echo "Done. Status:"
timeout 10 "$BIN" status --config "$STATE_DIR/default.json"
