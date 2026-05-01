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

# 检测可用浏览器（x86 用 google-chrome，arm 用 chromium）
BROWSER=""
if command -v google-chrome >/dev/null 2>&1; then
    BROWSER="google-chrome"
elif command -v chromium >/dev/null 2>&1; then
    BROWSER="chromium"
else
    echo "Error: No browser found (google-chrome or chromium required)" >&2
    exit 1
fi

# 使用 --app 模式打开，隐藏菜单栏和地址栏，并最大化窗口
exec "$BROWSER" --app="$URL" --start-maximized "$@"
