#!/bin/bash
# Wrapper around Xtigervnc that computes total geometry from MONITOR_LAYOUT
# when present, otherwise falls back to the legacy VNC_RESOLUTION variable.

set -eu

if [ -n "${MONITOR_LAYOUT:-}" ]; then
    TOTAL_GEOMETRY="$(python3 /opt/compute-total-geometry.py "$MONITOR_LAYOUT" 2>/dev/null || true)"
    if [ -z "$TOTAL_GEOMETRY" ]; then
        echo "[start-xvnc] compute-total-geometry failed, falling back to VNC_RESOLUTION" >&2
        TOTAL_GEOMETRY="${VNC_RESOLUTION:-1920x1080}"
    fi
else
    TOTAL_GEOMETRY="${VNC_RESOLUTION:-1920x1080}"
fi

echo "[start-xvnc] geometry=$TOTAL_GEOMETRY MONITOR_LAYOUT='${MONITOR_LAYOUT:-}'"

exec Xtigervnc :1 \
    -geometry "$TOTAL_GEOMETRY" \
    -depth 24 \
    -rfbauth /home/ubuntu/.vnc/passwd \
    -rfbport 10005 \
    -pn \
    -SecurityTypes VncAuth
