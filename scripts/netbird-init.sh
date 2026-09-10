#!/bin/sh
# /userdata/init.d/S50netbird - start/stop the NetBird client daemon.
# Installed by install.sh; re-run install.sh to update, don't edit in place.
#
# Background on the design decisions below is in docs/jetkvm-behavior.md
# and docs/netbird-behavior.md.

NETBIRD_BIN="/userdata/netbird/netbird"
NETBIRD_CONFIG="/userdata/netbird/state/default.json"
NETBIRD_LOG="/userdata/netbird/netbird.log"
WATCHDOG="/userdata/netbird/watchdog.sh"
MGMT_URL_FILE="/userdata/netbird/management-url.txt"
export SSL_CERT_FILE="/userdata/netbird/ca-certificates.crt"
STARTUP_TIMEOUT=30
UP_TIMEOUT=30

start() {
  # tun.ko is not loaded by JetKVM's own boot process.
  insmod /oem/usr/ko/tun.ko 2>/dev/null || true

  # Written before crond starts: crond needs its spool directory to
  # exist first, and /var/spool/cron/crontabs does not survive a reboot.
  mkdir -p /var/spool/cron/crontabs
  CRON_FILE="/var/spool/cron/crontabs/root"
  touch "$CRON_FILE"
  grep -vF "$WATCHDOG" "$CRON_FILE" > "$CRON_FILE.new" 2>/dev/null || true
  echo "*/5 * * * * $WATCHDOG" >> "$CRON_FILE.new"
  mv "$CRON_FILE.new" "$CRON_FILE"
  crontab "$CRON_FILE" 2>/dev/null || true

  # crond is not started by anything in stock firmware.
  pgrep crond > /dev/null 2>&1 || crond

  "$NETBIRD_BIN" service run --config "$NETBIRD_CONFIG" >> "$NETBIRD_LOG" 2>&1 &

  waited=0
  while [ "$waited" -lt "$STARTUP_TIMEOUT" ]; do
    "$NETBIRD_BIN" status --config "$NETBIRD_CONFIG" > /dev/null 2>&1 && break
    sleep 1
    waited=$((waited + 1))
  done

  # First boot after a fresh install has no config/management URL yet;
  # install.sh's own `up` call runs right after this.
  if [ ! -f "$NETBIRD_CONFIG" ] || [ ! -f "$MGMT_URL_FILE" ]; then
    echo "no persisted config/management URL yet - daemon running idle" >> "$NETBIRD_LOG"
    return 0
  fi

  mgmt_url="$(cat "$MGMT_URL_FILE")"
  if [ -z "$mgmt_url" ]; then
    echo "$MGMT_URL_FILE is empty - daemon running idle" >> "$NETBIRD_LOG"
    return 0
  fi

  timeout "$UP_TIMEOUT" "$NETBIRD_BIN" up --config "$NETBIRD_CONFIG" --management-url "$mgmt_url" >> "$NETBIRD_LOG" 2>&1
}

case "$1" in
  start)
    start
    ;;
  stop)
    killall netbird 2>/dev/null
    ;;
  *)
    echo "Usage: $0 {start|stop}"
    exit 1
    ;;
esac
