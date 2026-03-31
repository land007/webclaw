#!/usr/bin/env bash
set -euo pipefail

TOKEN="${OPENCLAW_GATEWAY_TOKEN:-changeme}"
export DISPLAY="${DISPLAY:-:1}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/1000}"
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR" || true

# Ensure gateway config is set correctly before starting
openclaw config set gateway.mode local
openclaw config set gateway.reload.mode hot
openclaw config set gateway.auth.mode token
openclaw config set gateway.auth.token "$TOKEN"
openclaw config set browser.noSandbox true
openclaw config set tools.alsoAllow '["browser"]'

# Keep the foreground gateway process under supervisor ownership.
# We do not want the CLI to detach into a replacement PID, otherwise
# supervisor marks the service as failed while the spawned gateway stays alive.
openclaw gateway stop >/dev/null 2>&1 || true
pkill -x openclaw-gateway >/dev/null 2>&1 || true

exec openclaw gateway run \
  --allow-unconfigured \
  --bind loopback \
  --auth token \
  --token "$TOKEN" \
  --port 10003 \
  --force
