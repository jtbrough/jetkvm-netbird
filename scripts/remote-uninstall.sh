#!/bin/sh
# Remove NetBird from a JetKVM device from your own machine.
#
#   curl -fsSL https://raw.githubusercontent.com/jtbrough/jetkvm-netbird/main/scripts/remote-uninstall.sh \
#     | sh -s -- <jetkvm-ip>
#
# Flags:
#   -y, --yes   Skip the confirmation prompt

set -eu

RAW_BASE="https://raw.githubusercontent.com/jtbrough/jetkvm-netbird/main/scripts"

AUTO_YES=false
JETKVM_IP=""

while [ $# -gt 0 ]; do
  case $1 in
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
  echo "Usage: $0 [-y] <jetkvm-ip>" >&2
  exit 1
fi

if [ "$AUTO_YES" = false ]; then
  printf "Remove NetBird from %s? [y/N]: " "$JETKVM_IP"
  read -r response
  case "$response" in
    [yY] | [yY][eE][sS]) ;;
    *)
      echo "Uninstall cancelled"
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

echo "[2/3] Transferring uninstall script..."
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STAGING_DIR="/tmp/jetkvm-netbird-install"
ssh root@"$JETKVM_IP" "mkdir -p $STAGING_DIR" </dev/null
if [ -f "$SCRIPT_DIR/uninstall.sh" ]; then
  src="$SCRIPT_DIR/uninstall.sh"
else
  src="$(mktemp)"
  curl -fsSL "$RAW_BASE/uninstall.sh" -o "$src"
fi
ssh root@"$JETKVM_IP" "cat > $STAGING_DIR/uninstall.sh" <"$src"
ssh root@"$JETKVM_IP" "chmod +x $STAGING_DIR/uninstall.sh" </dev/null
echo "       Transfer complete"

echo "[3/3] Uninstalling on device..."
ssh root@"$JETKVM_IP" "sh $STAGING_DIR/uninstall.sh" </dev/null

echo ""
echo "SUCCESS: NetBird removed from $JETKVM_IP"
