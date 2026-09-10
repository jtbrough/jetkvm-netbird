#!/bin/sh
# Install NetBird on a JetKVM device from your own machine - no manual SSH
# steps. Run this here, not on the device:
#
#   curl -fsSL https://raw.githubusercontent.com/jtbrough/jetkvm-netbird/main/scripts/remote-install.sh \
#     | sh -s -- -m https://mesh.example.com -k <setup-key> <jetkvm-ip>
#
# or from a local clone:
#
#   sh scripts/remote-install.sh -m https://mesh.example.com -k <setup-key> <jetkvm-ip>
#
# Flags (mirrors JetKVM's own install-tailscale.sh where the concepts
# carry over):
#   -m, --management-url   NetBird management URL (required)
#   -k, --setup-key        NetBird setup key (required for first-time
#                           registration; omit when re-running against an
#                           already-registered device)
#   -v, --version           NetBird release tag, e.g. "0.78.1". Default: latest
#   -y, --yes               Skip the confirmation prompt
#   -c, --clean             Wipe existing peer state first (new identity)
#   --                       Remaining args are passed through to `netbird up`
#                            on the device, e.g. -- --allow-server-ssh
#
# Requires curl locally and SSH access to the device (Developer Mode
# enabled, your key added - see
# https://jetkvm.com/docs/advanced-usage/developing#developer-mode).
# Doesn't run this repo's scripts unreviewed on the device without your
# say-so: pulls them from this repo at the ref you're running, transfers
# them over SSH, then runs install.sh there with the flags you gave it.

set -eu

RAW_BASE="https://raw.githubusercontent.com/jtbrough/jetkvm-netbird/main/scripts"

MANAGEMENT_URL=""
SETUP_KEY=""
NETBIRD_VERSION="latest"
AUTO_YES=false
CLEAN_INSTALL=false
JETKVM_IP=""
UP_ARGS=""

while [ $# -gt 0 ]; do
  case $1 in
    -m | --management-url)
      MANAGEMENT_URL="$2"
      shift 2
      ;;
    -k | --setup-key)
      SETUP_KEY="$2"
      shift 2
      ;;
    -v | --version)
      NETBIRD_VERSION="$2"
      shift 2
      ;;
    -y | --yes)
      AUTO_YES=true
      shift
      ;;
    -c | --clean)
      CLEAN_INSTALL=true
      shift
      ;;
    --)
      shift
      UP_ARGS="$*"
      break
      ;;
    *)
      JETKVM_IP="$1"
      shift
      ;;
  esac
done

if [ -z "$JETKVM_IP" ] || [ -z "$MANAGEMENT_URL" ]; then
  echo "Usage: $0 -m <management-url> [-k <setup-key>] [-v <version>] [-y] [-c] <jetkvm-ip> [-- <netbird-up-args>]" >&2
  exit 1
fi

if [ "$AUTO_YES" = false ]; then
  echo "──────────────────────────────────────────────────────────"
  echo "           NetBird Installation (JetKVM)"
  echo "──────────────────────────────────────────────────────────"
  echo ""
  echo "  JetKVM IP:       $JETKVM_IP"
  echo "  Management URL:  $MANAGEMENT_URL"
  echo "  NetBird version: $NETBIRD_VERSION"
  [ "$CLEAN_INSTALL" = true ] && echo "  Clean install:   yes (existing peer identity will be wiped)"
  [ -n "$UP_ARGS" ] && echo "  Extra up args:   $UP_ARGS"
  echo ""
  printf "Continue? [y/N]: "
  read -r response
  case "$response" in
    [yY] | [yY][eE][sS]) ;;
    *)
      echo "Installation cancelled"
      exit 0
      ;;
  esac
fi

echo "[1/3] Checking SSH access to $JETKVM_IP..."
if ! ssh -o ConnectTimeout=5 -o BatchMode=yes root@"$JETKVM_IP" 'echo ok' </dev/null >/dev/null 2>&1; then
  echo "ERROR: SSH connection to root@$JETKVM_IP failed." >&2
  echo "       Enable Developer Mode and add your SSH key first:" >&2
  echo "       https://jetkvm.com/docs/advanced-usage/developing#developer-mode" >&2
  exit 1
fi
echo "       SSH access confirmed"

echo "[2/3] Transferring install scripts..."
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STAGING_DIR="/tmp/jetkvm-netbird-install"
ssh root@"$JETKVM_IP" "mkdir -p $STAGING_DIR" </dev/null
for f in install.sh netbird-init.sh watchdog.sh ca-certificates.crt; do
  if [ -f "$SCRIPT_DIR/$f" ]; then
    src="$SCRIPT_DIR/$f"
  else
    src="$(mktemp)"
    curl -fsSL "$RAW_BASE/$f" -o "$src"
  fi
  ssh root@"$JETKVM_IP" "cat > $STAGING_DIR/$f" <"$src"
done
ssh root@"$JETKVM_IP" "chmod +x $STAGING_DIR/install.sh $STAGING_DIR/netbird-init.sh $STAGING_DIR/watchdog.sh" </dev/null
echo "       Transfer complete"

echo "[3/3] Installing on device..."
# shellcheck disable=SC2029
ssh root@"$JETKVM_IP" \
  "NB_MANAGEMENT_URL=$MANAGEMENT_URL NB_SETUP_KEY=$SETUP_KEY NETBIRD_VERSION=$NETBIRD_VERSION NB_CLEAN_INSTALL=$CLEAN_INSTALL NB_EXTRA_UP_ARGS='$UP_ARGS' sh $STAGING_DIR/install.sh" </dev/null

echo ""
echo "SUCCESS: NetBird installed on $JETKVM_IP"
