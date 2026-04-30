#!/bin/bash
# Prepare a writable per-app launcher log.

set -u

APP_ID="${1:-}"

if [[ ! "$APP_ID" =~ ^[a-zA-Z0-9._-]+$ ]]; then
    echo "Invalid app id: $APP_ID" >&2
    exit 1
fi

LOG="/tmp/webclaw-ondemand-${APP_ID}.log"

: > "$LOG"
chown ubuntu:ubuntu "$LOG"
chmod 644 "$LOG"

exit 0
