#!/bin/sh
set -eu

if [ -z "${CF_TUNNEL_TOKEN:-}" ] || [ "${CF_TUNNEL_TOKEN}" = "unused" ]; then
  echo "[cloudflared] CF_TUNNEL_TOKEN not set; skipping tunnel startup"
  exit 0
fi

if ! command -v cloudflared >/dev/null 2>&1; then
  echo "[cloudflared] cloudflared is not installed in this image; Cloudflare Tunnel is unavailable"
  exit 78
fi

exec cloudflared tunnel --no-autoupdate run --token "${CF_TUNNEL_TOKEN}"
