#!/usr/bin/env bash
set -euo pipefail

export DISPLAY="${DISPLAY:-:1}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/1000}"

# 确认卸载
zenity --question \
  --title="卸载 Hermes Agent" \
  --text="<b>确定要卸载 Hermes Agent 吗？</b>\n\n这将：\n• 停止 Hermes 服务\n• 删除程序文件（/opt/hermes-agent）\n• 保留配置数据（/home/ubuntu/.hermes）\n\n如需完全清除，请手动删除配置目录。" \
  --ok-label="卸载" \
  --cancel-label="取消" \
  --width=400 \
  --no-wrap || exit 0

# 显示卸载进度
{
    echo "10"
    echo "# 停止 Hermes 服务..."

    # 停止 Supervisor 服务
    if [ -f /etc/supervisor/conf.d/supervisor-hermes.conf ]; then
        supervisorctl stop hermes 2>/dev/null || true
        supervisorctl reread
        supervisorctl update
        rm -f /etc/supervisor/conf.d/supervisor-hermes.conf
    fi

    # 杀死可能的残留进程
    pkill -f "hermes dashboard" 2>/dev/null || true
    pkill -f "hermes gateway" 2>/dev/null || true
    pkill -f "hermes" 2>/dev/null || true

    echo "30"
    echo "# 删除程序文件..."

    # 删除程序目录
    if [ -d "/opt/hermes-agent" ]; then
        rm -rf /opt/hermes-agent || {
            echo "# 删除失败，尝试强制删除..."
            sleep 1
            rm -rf /opt/hermes-agent
        }
    fi
    rm -f /opt/start-hermes-dashboard.sh
    rm -f /opt/hermes-browser.sh

    # 清理 Python 缓存（uv 缓存的 hermes_agent 包）
    rm -rf /home/ubuntu/.cache/uv/sdks/*hermes* 2>/dev/null || true
    rm -rf /home/ubuntu/.cache/uv/sdists-v9/editable/* 2>/dev/null || true
    rm -rf /home/ubuntu/.cache/uv/v0-cache/*hermes* 2>/dev/null || true
    find /home/ubuntu/.cache/uv -name "*hermes*" -delete 2>/dev/null || true
    rm -rf /home/ubuntu/.local/lib/python*/site-packages/hermes* 2>/dev/null || true

    echo "50"
    echo "# 清理配置和缓存..."

    # 清理 supervisord.conf 中的 hermes 引用
    if [ -f /etc/supervisor/supervisord.conf ]; then
        sed -i 's/\/etc\/supervisor\/conf.d\/supervisor-hermes\.conf[^ ]* *//g' /etc/supervisor/supervisord.conf
        sed -i 's/  *$//' /etc/supervisor/supervisord.conf  # 清理末尾空格
    fi

    # 清理临时日志文件
    rm -f /tmp/hermes*.log
    rm -f /tmp/hermes_progress
    rm -f /tmp/hermes_stdout.log
    rm -f /tmp/hermes_stderr.log

    # 清理 Git clone 临时目录
    rm -rf /tmp/hermes-agent 2>/dev/null || true

    echo "70"
    echo "# 更新桌面图标..."

    # 调用桌面图标更新系统（会自动添加"待安装"标记并移除卸载菜单）
    update-desktop-icons

    echo "100"
    echo "# 卸载完成！"

} | zenity --progress \
  --title="卸载 Hermes Agent" \
  --text="正在卸载..." \
  --percentage=0 \
  --auto-close \
  --no-cancel \
  --width=400

# 显示完成消息
zenity --info \
  --title="卸载完成" \
  --text="Hermes Agent 已成功卸载。\n\n配置数据已保留在：\n/home/ubuntu/.hermes\n\n如需完全清除，请手动删除此目录。" \
  --width=400 \
  --no-wrap
