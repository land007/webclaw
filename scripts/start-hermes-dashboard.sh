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
    cat > "$HERMES_HOME/config.yaml" << 'EOF'
model:
  default: "claude-opus-4"
  provider: "auto"
EOF
fi

# 启动 Hermes Dashboard
source venv/bin/activate
exec hermes dashboard \
  --host 0.0.0.0 \
  --port 10011 \
  --insecure \
  --no-open
