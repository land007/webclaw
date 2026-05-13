#!/usr/bin/env bash
set -euo pipefail

# Hermes Agent 一键安装脚本
export DISPLAY="${DISPLAY:-:1}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/1000}"
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR" || true

# 检查是否在 Docker 构建环境中
if [ -f "/.dockerenv" ] || [ "${HERMES_DOCKER_BUILD:-}" = "1" ]; then
    export HERMES_DOCKER_BUILD=1
fi

# 检查是否已安装
if [ -d "/opt/hermes-agent" ] && [ -f "/opt/hermes-agent/venv/bin/hermes" ] && [ -f "/opt/hermes-browser.sh" ]; then
    # 已安装
    if [ "${HERMES_DOCKER_BUILD:-}" != "1" ]; then
        # 非 Docker 构建环境，直接启动 Dashboard
        /opt/hermes-browser.sh
    fi
    exit 0
fi

# 检查是否由 webclaw-app-launcher 调用（跳过重复的确认对话框）
# webclaw-app-launcher 会先显示确认对话框，所以这里不需要再问一次
if [ "${WEBCLAW_APP_LAUNCHER:-}" = "1" ]; then
    echo "[INFO] 由 webclaw-app-launcher 调用，跳过确认对话框"
else
    # 显示安装确认对话框（仅在手动直接运行脚本时）
    zenity --question \
      --title="安装 Hermes Agent" \
      --text="<b>确定要安装 Hermes Agent 吗？</b>\n\n这是一个自进化的 AI 代理，具有学习能力。\n\n安装过程可能需要几分钟，请确保网络连接正常。" \
      --ok-label="确定安装" \
      --cancel-label="取消" \
      --width=400 \
      --no-wrap || exit 0
fi

# # 更新桌面图标显示为"安装中..."
# cat > /home/ubuntu/Desktop/hermes.desktop << 'EOF'
# [Desktop Entry]
# Name=Hermes Agent (安装中...)
# Name[zh_CN]=Hermes 智能代理 (安装中...)
# Exec=/usr/bin/true
# Icon=/opt/desktop-icons/hermes.png
# Terminal=false
# Type=Application
# StartupNotify=false
# EOF

# 短暂延迟确保 zenity 对话框显示
sleep 0.5

# 安装步骤函数
install_step_1_dependencies() {
    echo "[10%] 安装 Python 依赖..."
    echo "10" > /tmp/hermes_progress 2>/dev/null || true
    # 检查并安装必要的包
    sudo apt-get update

    # 安装通用的Python依赖
    sudo apt-get install -y python3-venv python3-pip git curl software-properties-common

    # 尝试安装 Python 3.11（如果可用）
    if ! command -v python3.11 &> /dev/null; then
        sudo apt-get install -y python3.11 python3.11-venv 2>/dev/null || echo "Python 3.11 不可用，将使用系统默认Python"
    fi
}

install_step_2_clone() {
    echo "[30%] 克隆 Hermes 仓库..."
    echo "30" > /tmp/hermes_progress 2>/dev/null || true
    # 克隆 Hermes 仓库到用户目录，然后移动到 /opt
    if [ ! -d "/opt/hermes-agent" ]; then
        cd /tmp
        git clone https://github.com/NousResearch/hermes-agent.git
        sudo mv hermes-agent /opt/
        sudo chown -R ubuntu:ubuntu /opt/hermes-agent
    fi

    cd /opt/hermes-agent
    chmod +x setup-hermes.sh
    chmod +x hermes
}

install_step_3_setup() {
    echo "[50%] 运行安装脚本（这需要几分钟）..."
    echo "50" > /tmp/hermes_progress 2>/dev/null || true
    # 运行 Hermes 安装脚本（删除旧的 venv，用 ubuntu 用户运行）
    rm -rf venv
    sudo -u ubuntu bash -c './setup-hermes.sh 2>&1 | tee /tmp/hermes-setup.log' || true

    # 检查核心功能是否成功安装（允许 setup-hermes.sh 因缺少可选组件返回非零）
    if [ ! -f "venv/bin/hermes" ] || [ ! -x "venv/bin/hermes" ]; then
        echo "❌ Hermes 核心组件安装失败"
        return 1
    fi
    echo "✅ Hermes 核心组件安装成功"
    echo "60" > /tmp/hermes_progress 2>/dev/null || true
}

install_step_4_config() {
    echo "[70%] 创建启动脚本和配置..."
    echo "70" > /tmp/hermes_progress 2>/dev/null || true
    # 创建浏览器启动脚本
    cat > /opt/hermes-browser.sh << 'HERMES_EOF'
#!/usr/bin/env bash
xdg-open "http://127.0.0.1:10011" >/dev/null 2>&1 &
HERMES_EOF

    chmod +x /opt/hermes-browser.sh

    # 创建 Dashboard 启动脚本
    cat > /opt/start-hermes-dashboard.sh << 'HERMES_EOF'
#!/usr/bin/env bash
set -euo pipefail

export DISPLAY="${DISPLAY:-:1}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/1000}"
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR" || true

cd /opt/hermes-agent

# 确保 PATH 包含必要命令
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/opt/hermes-agent"

# Hermes 配置目录
HERMES_HOME="/home/ubuntu/.hermes"
mkdir -p "$HERMES_HOME"

# 初始化配置（如果首次运行）
if [ ! -f "$HERMES_HOME/config.yaml" ]; then
    echo "Initializing Hermes..."
    # 创建最小配置
    cat > "$HERMES_HOME/config.yaml" << 'CONFIGEOF'
model:
  default: "claude-opus-4"
  provider: "auto"
CONFIGEOF
fi

# 启动 Hermes Dashboard
source venv/bin/activate
exec hermes dashboard --host 0.0.0.0 --port 10011 --insecure --no-open
HERMES_EOF

    chmod +x /opt/start-hermes-dashboard.sh
    echo "75" > /tmp/hermes_progress 2>/dev/null || true

    # 创建 Supervisor 配置
    cat > /etc/supervisor/conf.d/supervisor-hermes.conf << 'HERMES_EOF'
[program:hermes]
command=/usr/bin/bash /opt/start-hermes-dashboard.sh
directory=/home/ubuntu
user=ubuntu
environment=HOME="/home/ubuntu",DISPLAY=":1",XDG_RUNTIME_DIR="/run/user/1000",PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/opt/hermes-agent"
priority=210
autostart=true
autorestart=false
startretries=5
startsecs=10
stopasgroup=true
killasgroup=true
stdout_logfile=/tmp/hermes_stdout.log
stderr_logfile=/tmp/hermes_stderr.log
stdout_logfile_maxbytes=10MB
stderr_logfile_maxbytes=10MB
HERMES_EOF

	# 添加到 Supervisor 主配置文件的 include 列表
	if [ -f "/etc/supervisor/supervisord.conf" ]; then
		# 检查是否已经在 include 列表中
		if ! grep -q "supervisor-hermes.conf" /etc/supervisor/supervisord.conf; then
			# 获取 include 行的 files 部分
			if grep -q "^files " /etc/supervisor/supervisord.conf; then
				# 在 files 行末尾添加（确保没有重复）
				sed -i "s|^files \\(.*\\)|files \\1 /etc/supervisor/conf.d/supervisor-hermes.conf|" /etc/supervisor/supervisord.conf
			else
				# 如果没有 files 行，在 [include] 部分添加
				sed -i '/\\[include\\]/a files = /etc/supervisor/conf.d/supervisor-hermes.conf' /etc/supervisor/supervisord.conf
			fi
		fi
	fi

    # 更新 Supervisor 配置
    supervisorctl reread >> /tmp/hermes-install.log 2>&1 || echo "Warning: supervisorctl reread failed"
    supervisorctl update >> /tmp/hermes-install.log 2>&1 || echo "Warning: supervisorctl update failed"
    echo "80" > /tmp/hermes_progress 2>/dev/null || true
}

install_step_5_start() {
    echo "[90%] 启动 Hermes 服务..."
    echo "90" > /tmp/hermes_progress 2>/dev/null || true
    # 创建配置目录
    mkdir -p /home/ubuntu/.hermes
    chown -R ubuntu:ubuntu /home/ubuntu/.hermes /opt/hermes-agent

    # 修复 venv 权限（确保 python3 可执行）
    if [ -d "/opt/hermes-agent/venv" ]; then
        chmod +x /opt/hermes-agent/venv/bin/python3 2>/dev/null || true
        chmod +x /opt/hermes-agent/venv/bin/hermes 2>/dev/null || true
        find /opt/hermes-agent/venv/bin -type f -name "*.py" -exec chmod +x {} \; 2>/dev/null || true
    fi

    # 启动 Hermes 服务
    supervisorctl start hermes >> /tmp/hermes-install.log 2>&1 || echo "Warning: failed to start hermes"

    # 等待服务启动，最多30秒
    TIMEOUT=30
    ELAPSED=0
    while [ $ELAPSED -lt $TIMEOUT ]; do
        if supervisorctl status hermes 2>/dev/null | grep -q "RUNNING"; then
            echo "✅ Hermes 服务已启动"
            break
        fi
        sleep 2
        ELAPSED=$((ELAPSED + 2))
    done

    if [ $ELAPSED -ge $TIMEOUT ]; then
        echo "⚠️ 警告：Hermes 服务启动超时（30秒）"
        supervisorctl status hermes >> /tmp/hermes-install.log 2>&1 || true
    fi

    echo "[100%] 安装完成！"
    echo "100" > /tmp/hermes_progress 2>/dev/null || true
}

# 安装进度函数
install_progress() {
    # 检查是否禁用 zenity（由 webclaw-app-launcher 调用时）
    if [ "${DISABLE_ZENITY:-}" = "1" ]; then
        # 直接运行安装步骤，不使用 zenity 进度条
        install_step_1_dependencies
        install_step_2_clone
        install_step_3_setup
        install_step_4_config
        install_step_5_start
        return 0
    fi

    {
        echo "10"
        echo "# 安装 Python 依赖..."
        install_step_1_dependencies

        echo "30"
        echo "# 克隆 Hermes 仓库..."
        install_step_2_clone

        echo "50"
        echo "# 运行安装脚本（这需要几分钟）..."
        install_step_3_setup

        echo "80"
        echo "# 创建启动脚本和配置..."
        install_step_4_config

        echo "90"
        echo "# 启动 Hermes 服务..."
        install_step_5_start

        echo "100"
        echo "# 安装完成！"

    } | zenity --progress \
      --title="安装 Hermes Agent" \
      --text="正在安装..." \
      --percentage=0 \
      --auto-close \
      --width=400
}

# 后台运行安装
install_progress &

# 等待安装完成
wait

# 检查安装是否成功（检查文件是否存在）
if [ -f "/opt/hermes-agent/venv/bin/hermes" ] && [ -x "/opt/hermes-agent/venv/bin/hermes" ]; then
    # 更新桌面图标为正常状态（带卸载菜单）
    cat > /home/ubuntu/Desktop/hermes.desktop << 'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Hermes Agent
Name[zh_CN]=Hermes 智能代理
Name[ja_JP]=Hermes エージェント
Name[es_ES]=Agente Hermes
Name[pt_BR]=Agente Hermes
Name[ko_KR]=Hermes 에이전트
Name[de_DE]=Hermes-Agent
Comment=Self-improving AI Agent with Web Dashboard
Comment[zh_CN]=具有学习能力的自进化 AI 代理 - Web 管理界面
Comment[ja_JP]=自己改善型 AI エージェント - Web ダッシュボード
Comment[es_ES]=Agente IA con bucle de aprendizaje - Panel web
Comment[pt_BR]=Agente IA com loop de aprendizado - Painel web
Comment[ko_KR]=학습 루프가 있는 자가 개선 AI 에이전트 - 웹 대시보드
Comment[de_DE]=Selbstverbessernder KI-Agent - Web-Dashboard
Exec=/usr/local/bin/webclaw-app-launcher hermes
Icon=/opt/desktop-icons/hermes.png
Terminal=false
Type=Application
Categories=Development;AI;Utility;
StartupNotify=true
Actions=Uninstall;

[Desktop Action Uninstall]
Name=Uninstall Hermes
Name[zh_CN]=卸载 Hermes
Name[ja_JP]=Hermes アンインストール
Name[es_ES]=Desinstalar Hermes
Name[pt_BR]=Desinstalar Hermes
Name[ko_KR]=Hermes 제거
Name[de_DE]=Hermes deinstallieren
Exec=/opt/uninstall-hermes.sh
Icon=/opt/desktop-icons/hermes.png
StartupNotify=false
EOF

    chown ubuntu:ubuntu /home/ubuntu/Desktop/hermes.desktop
    chmod +x /home/ubuntu/Desktop/hermes.desktop

    # 更新桌面图标系统（会自动创建卸载菜单）
    update-desktop-icons

    # 显示成功消息
    if [ "${DISABLE_ZENITY:-}" != "1" ]; then
        zenity --info \
          --title="安装成功" \
          --text="Hermes Agent 安装成功！\n\n点击桌面图标即可打开 Web Dashboard。\n\n访问地址: http://127.0.0.1:10011\n\n右键点击图标可选择「卸载」" \
          --no-wrap
    fi

    # 自动打开 Dashboard（仅在非 Docker 构建环境）
    if [ "${HERMES_DOCKER_BUILD:-}" != "1" ]; then
        /opt/hermes-browser.sh
    fi
else
    # 显示失败消息
    if [ "${DISABLE_ZENITY:-}" != "1" ]; then
        zenity --error \
          --title="安装失败" \
          --text="Hermes Agent 安装失败。\n\n请查看日志：\n/tmp/hermes_stderr.log" \
          --no-wrap
    fi
    exit 1
fi
