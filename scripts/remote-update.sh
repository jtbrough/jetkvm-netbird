#!/bin/sh
# Update NetBird on a JetKVM device from your own machine.
#
#   curl -fsSL https://raw.githubusercontent.com/jtbrough/jetkvm-netbird/main/scripts/remote-update.sh \
#     | sh -s -- <jetkvm-ip>
#
# Flags:
#   -v, --version   NetBird release tag, e.g. "0.78.1". Default: latest
#   -y, --yes       Skip the confirmation prompt
#
# Requires an existing install (see remote-install.sh for first-time setup).

set -eu

RAW_BASE="https://raw.githubusercontent.com/jtbrough/jetkvm-netbird/main/scripts"

NETBIRD_VERSION="latest"
AUTO_YES=false
JETKVM_IP=""

while [ $# -gt 0 ]; do
  case $1 in
    -v | --version)
      NETBIRD_VERSION="$2"
      shift 2
      ;;
    -y | --yes)
      AUTO_YES=true
      shift
      ;;
    *)
      JETKVM_IP="$1"
      shift
      ;;
  esac
done

if [ -z "$JETKVM_IP" ]; then
  echo "Usage: $0 [-v <version>] [-y] <jetkvm-ip>" >&2
  exit 1
fi

if [ "$AUTO_YES" = false ]; then
  printf "Update NetBird on %s to %s? [y/N]: " "$JETKVM_IP" "$NETBIRD_VERSION"
  read -r response
  case "$response" in
    [yY] | [yY][eE][sS]) ;;
    *)
      echo "Update cancelled"
      exit 0
      ;;
  esac
fi

echo "[1/3] Checking SSH access to $JETKVM_IP..."
if ! ssh -o ConnectTimeout=5 -o BatchMode=yes root@"$JETKVM_IP" 'echo ok' </dev/null >/dev/null 2>&1; then
  echo "ERROR: SSH connection to root@$JETKVM_IP failed." >&2
  exit 1
fi
echo "       SSH access confirmed"

echo "[2/3] Transferring scripts..."
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STAGING_DIR="/tmp/jetkvm-netbird-install"
ssh root@"$JETKVM_IP" "mkdir -p $STAGING_DIR" </dev/null
for f in install.sh update.sh netbird-init.sh watchdog.sh ca-certificates.crt; do
  if [ -f "$SCRIPT_DIR/$f" ]; then
    src="$SCRIPT_DIR/$f"
  else
    src="$(mktemp)"
    curl -fsSL "$RAW_BASE/$f" -o "$src"
  fi
  ssh root@"$JETKVM_IP" "cat > $STAGING_DIR/$f" <"$src"
done
ssh root@"$JETKVM_IP" "chmod +x $STAGING_DIR/install.sh $STAGING_DIR/update.sh $STAGING_DIR/netbird-init.sh $STAGING_DIR/watchdog.sh" </dev/null
echo "       Transfer complete"

echo "[3/3] Updating on device..."
# shellcheck disable=SC2029
ssh root@"$JETKVM_IP" "NETBIRD_VERSION=$NETBIRD_VERSION sh $STAGING_DIR/update.sh" </dev/null

echo ""
echo "SUCCESS: NetBird updated on $JETKVM_IP"
