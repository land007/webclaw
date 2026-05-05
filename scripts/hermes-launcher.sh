#!/usr/bin/env bash
# Hermes-specific launcher for webclaw-app-launcher compatibility

set -u

APP_ID="hermes"
MANIFEST="/opt/on-demand-apps/${APP_ID}.json"

# 检查是否已安装
if [ -d "/opt/hermes-agent" ] && [ -f "/opt/hermes-agent/venv/bin/hermes" ]; then
    # 已安装，检查服务状态
    if ! supervisorctl status hermes 2>/dev/null | grep -q "RUNNING"; then
        # 服务未运行，尝试启动
        supervisorctl start hermes 2>/dev/null || true
        sleep 3

        # 再次检查状态
        if ! supervisorctl status hermes 2>/dev/null | grep -q "RUNNING"; then
            # 启动失败，显示错误
            export DISPLAY="${DISPLAY:-:1}"
            zenity --error \
              --title="Hermes 启动失败" \
              --text="Hermes 服务启动失败。\n\n请检查日志：\n/tmp/hermes_stderr.log\n\n您可以尝试：\n1. 右键点击图标选择「卸载」\n2. 重新安装" \
              --width=400 \
              --no-wrap &
            exit 1
        fi
    fi

    # 检查浏览器启动脚本是否存在
    if [ ! -f "/opt/hermes-browser.sh" ]; then
        # 创建缺失的脚本
        cat > /opt/hermes-browser.sh << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
export DISPLAY="${DISPLAY:-:1}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/1000}"
xdg-open "http://127.0.0.1:10011" >/dev/null 2>&1 &
EOF
        chmod +x /opt/hermes-browser.sh
    fi

    # 打开 Dashboard
    /opt/hermes-browser.sh
    exit 0
fi

# 未安装，运行安装脚本
exec /opt/install-hermes.sh
