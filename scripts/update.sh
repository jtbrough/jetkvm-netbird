#!/bin/sh
# Update the NetBird binary on a JetKVM device, without re-peering.
#
#   NETBIRD_VERSION=0.79.0 sh update.sh   # pin a version
#   sh update.sh                          # latest release
#
# Delegates to install.sh, reusing the existing peer's management URL and
# state. Requires an existing install (see install.sh for first-time setup).

set -e

INSTALL_DIR="/userdata/netbird"
STATE_FILE="$INSTALL_DIR/state/default.json"
MGMT_URL_FILE="$INSTALL_DIR/management-url.txt"

if [ ! -f "$STATE_FILE" ]; then
  echo "No existing peer state at $STATE_FILE - use install.sh for first-time setup" >&2
  exit 1
fi

MGMT_URL="$(cat "$MGMT_URL_FILE" 2>/dev/null)"
if [ -z "$MGMT_URL" ]; then
  echo "Could not read management URL from $MGMT_URL_FILE" >&2
  exit 1
fi

NB_MANAGEMENT_URL="$MGMT_URL" sh "$(dirname "$0")/install.sh"
