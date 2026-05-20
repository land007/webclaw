#!/bin/bash
# Wrapper around Xtigervnc that computes total geometry from MONITOR_LAYOUT
# or the persisted launcher layout file, otherwise falls back to VNC_RESOLUTION.

set -eu

LAYOUT_FILE="${MONITOR_LAYOUT_FILE:-/home/ubuntu/.config/webclaw/monitor-layout}"
if [ -f "$LAYOUT_FILE" ]; then
    LAYOUT="$(cat "$LAYOUT_FILE" 2>/dev/null || true)"
else
    LAYOUT="${MONITOR_LAYOUT:-}"
fi

if [ -n "$LAYOUT" ]; then
    TOTAL_GEOMETRY="$(python3 /opt/compute-total-geometry.py "$LAYOUT" 2>/dev/null || true)"
    if [ -z "$TOTAL_GEOMETRY" ]; then
        echo "[start-xvnc] compute-total-geometry failed, falling back to VNC_RESOLUTION" >&2
        TOTAL_GEOMETRY="${VNC_RESOLUTION:-1920x1080}"
    fi
else
    TOTAL_GEOMETRY="${VNC_RESOLUTION:-1920x1080}"
fi

echo "[start-xvnc] geometry=$TOTAL_GEOMETRY MONITOR_LAYOUT='$LAYOUT'"

exec Xtigervnc :1 \
    -geometry "$TOTAL_GEOMETRY" \
    -depth 24 \
    -rfbauth /home/ubuntu/.vnc/passwd \
    -rfbport 10005 \
    -pn \
    -SecurityTypes VncAuth
