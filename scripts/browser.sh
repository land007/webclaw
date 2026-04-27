#!/bin/bash
# 桌面 Browser 图标的统一启动脚本
# 自动选择 Chrome (amd64) 或 Chromium (arm64),用 hostname 隔离 user-data-dir
# 防止多容器共享 chrome-data 卷时的 SingletonLock 冲突

export PULSE_SERVER="unix:/run/user/1000/pulse/native"
export PULSE_SINK="webcode_null"
export PULSE_SOURCE="webcode_mic"

if [ -x /usr/bin/google-chrome-stable ]; then
    BIN=/usr/bin/google-chrome-stable
    USER_DATA_DIR="$HOME/.config/google-chrome-$(hostname)"
elif [ -x /usr/bin/chromium ]; then
    BIN=/usr/bin/chromium
    USER_DATA_DIR="$HOME/.config/chromium-$(hostname)"
else
    echo "browser: 找不到 google-chrome-stable 或 chromium" >&2
    exit 1
fi

mkdir -p "$USER_DATA_DIR"
exec "$BIN" --user-data-dir="$USER_DATA_DIR" --password-store=basic "$@"
