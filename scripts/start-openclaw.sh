#!/usr/bin/env bash
set -euo pipefail

TOKEN="${OPENCLAW_GATEWAY_TOKEN:-changeme}"
export DISPLAY="${DISPLAY:-:1}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/1000}"
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR" || true

# Ensure gateway config is set correctly before starting
openclaw config set gateway.mode local
openclaw config set gateway.auth.mode token
openclaw config set gateway.auth.token "$TOKEN"
openclaw config set browser.noSandbox true
openclaw config set tools.alsoAllow '["browser"]'

exec openclaw gateway --port 10003
