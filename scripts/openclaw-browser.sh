#!/usr/bin/env bash
# OpenClaw 浏览器启动脚本（无菜单栏模式）
set -euo pipefail

# 从环境变量或 openclaw 配置中读取 token
if [ -n "${OPENCLAW_GATEWAY_TOKEN:-}" ]; then
    TOKEN="$OPENCLAW_GATEWAY_TOKEN"
else
    TOKEN="$(openclaw config get gateway.auth.token 2>/dev/null || echo "changeme")"
fi

URL="http://127.0.0.1:10003?token=${TOKEN}"

# 使用 --app 模式打开，隐藏菜单栏和地址栏
exec chromium --app="$URL" "$@"
