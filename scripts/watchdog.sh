#!/bin/sh
# /userdata/netbird/watchdog.sh - restart supervision for the NetBird
# daemon, invoked every 5 minutes by crond. No-op if already running.

NETBIRD_BIN="/userdata/netbird/netbird"
NETBIRD_CONFIG="/userdata/netbird/state/default.json"
INIT_SCRIPT="/userdata/init.d/S50netbird"
LOG="/userdata/netbird/watchdog.log"

log() {
  echo "$(date -Iseconds) $1" >> "$LOG"
}

if pgrep -f "$NETBIRD_BIN service run" > /dev/null 2>&1; then
  exit 0
fi

log "netbird daemon not running, restarting"
"$INIT_SCRIPT" start

sleep 5

if pgrep -f "$NETBIRD_BIN service run" > /dev/null 2>&1; then
  log "restart succeeded"
else
  log "restart FAILED - daemon still not running after start attempt"
fi
