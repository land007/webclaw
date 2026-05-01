#!/usr/bin/env bash
# OpenClaw 浏览器启动脚本（无菜单栏模式）
set -euo pipefail

TOKEN="${OPENCLAW_GATEWAY_TOKEN:-changeme}"
URL="http://127.0.0.1:10003?token=${TOKEN}"

# 使用 --app 模式打开，隐藏菜单栏和地址栏
exec chromium --app="$URL" "$@"
