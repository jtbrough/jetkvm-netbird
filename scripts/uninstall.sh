#!/bin/sh
# Remove NetBird from a JetKVM device: logs out of the mesh, stops the
# daemon, and removes every file install.sh created, including NetBird's
# own OS-default locations outside /userdata (see
# docs/netbird-behavior.md#default-paths). Does not touch Tailscale.

set -e

INSTALL_DIR="/userdata/netbird"
BIN="$INSTALL_DIR/netbird"
STATE_FILE="$INSTALL_DIR/state/default.json"
INIT_SCRIPT="/userdata/init.d/S50netbird"
CROND_FILE="/var/spool/cron/crontabs/root"

if [ -x "$BIN" ] && [ -f "$STATE_FILE" ]; then
  echo "Logging out of the mesh..."
  "$BIN" down --config "$STATE_FILE" 2>/dev/null || true
  "$BIN" logout --config "$STATE_FILE" 2>/dev/null || true
fi

if [ -x "$INIT_SCRIPT" ]; then
  echo "Stopping daemon..."
  "$INIT_SCRIPT" stop 2>/dev/null || true
fi

if [ -f "$CROND_FILE" ]; then
  echo "Removing crond watchdog entry..."
  grep -vF "$INSTALL_DIR/watchdog.sh" "$CROND_FILE" > "$CROND_FILE.new" 2>/dev/null || true
  mv "$CROND_FILE.new" "$CROND_FILE"
  crontab "$CROND_FILE" 2>/dev/null || true
fi

echo "Removing boot script..."
rm -f "$INIT_SCRIPT"

echo "Removing $INSTALL_DIR..."
rm -rf "$INSTALL_DIR"

echo "Removing NetBird's OS-default locations..."
rm -rf /root/.config/netbird /var/lib/netbird /tmp/netbird /oem/.config/netbird

echo "Done. NetBird removed."
