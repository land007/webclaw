#!/bin/bash
# Configure logical monitors on the running TigerVNC X server via xrandr --setmonitor.
# MONITOR_LAYOUT format: "WxH+X+Y,WxH+X+Y,..." (matches X11 geometry strings)
# The first logical monitor is bound to the underlying VNC-0 output; subsequent ones use "none".

set -u

LAYOUT="${1:-${MONITOR_LAYOUT:-}}"
if [ -z "$LAYOUT" ]; then
    exit 0
fi

DISPLAY="${DISPLAY:-:1}"
export DISPLAY

# Wait for X server (up to 10s)
for _ in $(seq 1 20); do
    xrandr >/dev/null 2>&1 && break
    sleep 0.5
done

if ! xrandr >/dev/null 2>&1; then
    echo "[setup-monitors] xrandr unreachable on DISPLAY=$DISPLAY" >&2
    exit 1
fi

# Underlying output name produced by TigerVNC (typically "VNC-0").
SOURCE_OUTPUT="$(xrandr --listmonitors 2>/dev/null | awk 'NR==2 {print $NF}')"
if [ -z "$SOURCE_OUTPUT" ]; then
    SOURCE_OUTPUT="VNC-0"
fi

# Idempotency: drop any monitors we created in previous runs (WC-*).
existing="$(xrandr --listmonitors 2>/dev/null | awk 'NR>1 && $2 ~ /^WC-/ {print $2}')"
for name in $existing; do
    xrandr --delmonitor "$name" 2>/dev/null || true
done

i=0
IFS=','
for spec in $LAYOUT; do
    # Strip whitespace
    spec="${spec#"${spec%%[![:space:]]*}"}"
    spec="${spec%"${spec##*[![:space:]]}"}"
    [ -z "$spec" ] && continue

    # Parse WxH+X+Y → xrandr setmonitor geometry "W/0xH/0+X+Y"
    if ! [[ "$spec" =~ ^([0-9]+)x([0-9]+)\+([0-9]+)\+([0-9]+)$ ]]; then
        echo "[setup-monitors] invalid spec: $spec" >&2
        continue
    fi
    W="${BASH_REMATCH[1]}"
    H="${BASH_REMATCH[2]}"
    X="${BASH_REMATCH[3]}"
    Y="${BASH_REMATCH[4]}"
    geom="${W}/0x${H}/0+${X}+${Y}"

    if [ "$i" -eq 0 ]; then
        xrandr --setmonitor "WC-$i" "$geom" "$SOURCE_OUTPUT" \
            && echo "[setup-monitors] WC-$i ${spec} bound to $SOURCE_OUTPUT" \
            || echo "[setup-monitors] failed to set WC-$i" >&2
    else
        xrandr --setmonitor "WC-$i" "$geom" none \
            && echo "[setup-monitors] WC-$i ${spec} (none)" \
            || echo "[setup-monitors] failed to set WC-$i" >&2
    fi
    i=$((i + 1))
done

xrandr --listmonitors
