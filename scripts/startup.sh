#!/bin/bash
set -e

MODE="${MODE:-desktop}"

# ─── Docker socket GID fix ───────────────────────────────────────────
if [ -S /var/run/docker.sock ]; then
    DOCKER_GID=$(stat -c '%g' /var/run/docker.sock)
    groupmod -g "$DOCKER_GID" docker 2>/dev/null || true
    usermod -aG docker ubuntu 2>/dev/null || true
fi

# ─── Docker-in-Docker (DinD) mode ────────────────────────────────────
# dockerd 现在由 supervisor 自动管理，根据 DOCKER_SOCK_MODE 环境变量启动
DOCKER_SOCK_MODE="${DOCKER_SOCK_MODE:-host}"
export DOCKER_SOCK_MODE
usermod -aG docker ubuntu 2>/dev/null || true

# ─── Create project directory and fix permissions ────────────────────
mkdir -p /home/ubuntu/projects
mkdir -p /home/ubuntu/Desktop
mkdir -p /home/ubuntu/.local/share/vibe-kanban

# 后台执行 projects 目录的 chown，避免阻塞启动（包含大量文件）
echo "[startup] Starting background chown for /home/ubuntu/projects (may take several minutes)..."
(chown -R ubuntu:ubuntu /home/ubuntu/projects >/dev/null 2>&1 || true) &

chown -R ubuntu:ubuntu /home/ubuntu/Desktop
chown -R ubuntu:ubuntu /home/ubuntu/.local

mkdir -p /home/ubuntu/recordings
chown ubuntu:ubuntu /home/ubuntu/recordings

# Ensure .config is writable by ubuntu (chrome-data volume mounts here)
mkdir -p /home/ubuntu/.config
chown ubuntu:ubuntu /home/ubuntu/.config

# # ─── DNA directory (self-evolution source) ───────────────────────────
# # DNA_REPO_URL: 机器人的基因来源，支持 fork 仓库，默认指向原始库
# DNA_REPO_URL="${DNA_REPO_URL:-https://github.com/land007/webcode}"
# mkdir -p /home/ubuntu/dna
# if [ -z "$(ls -A /home/ubuntu/dna 2>/dev/null)" ]; then
#     echo "[startup] DNA directory is empty, cloning from ${DNA_REPO_URL} ..."
#     git clone "$DNA_REPO_URL" /home/ubuntu/dna \
#         && echo "[startup] DNA cloned successfully" \
#         || echo "[startup] WARNING: Failed to clone DNA repository, robot will retry manually"
# fi
# chown -R ubuntu:ubuntu /home/ubuntu/dna

# ─── Persist bash history ────────────────────────────────────────────
HIST_DIR="/home/ubuntu/.local/share/shell"
mkdir -p "$HIST_DIR"
if [ ! -f "$HIST_DIR/.bash_history" ]; then
    touch "$HIST_DIR/.bash_history"
fi
ln -sf "$HIST_DIR/.bash_history" /home/ubuntu/.bash_history
chown -R ubuntu:ubuntu "$HIST_DIR"

# ─── Persist gitconfig ──────────────────────────────────────────────
if [ -f /home/ubuntu/.gitconfig-vol ]; then
    ln -sf /home/ubuntu/.gitconfig-vol /home/ubuntu/.gitconfig
fi
# Set git user from environment variables (if provided)
if [ -n "$GIT_USER_NAME" ]; then
    sudo -u ubuntu git config --global user.name "$GIT_USER_NAME"
fi
if [ -n "$GIT_USER_EMAIL" ]; then
    sudo -u ubuntu git config --global user.email "$GIT_USER_EMAIL"
fi

# ─── code-server data directory ─────────────────────────────────────
mkdir -p /home/ubuntu/.code-server/User
# Generate languagepacks.json on first start (CLI install doesn't create it)
if [ ! -f /home/ubuntu/.code-server/languagepacks.json ]; then
    /opt/create-languagepacks.sh /home/ubuntu/.code-server /opt/code-server-extensions
fi
# Write default argv.json (locale) if not already set by user
if [ ! -f /home/ubuntu/.code-server/User/argv.json ]; then
    echo '{"locale":"zh-cn"}' > /home/ubuntu/.code-server/User/argv.json
fi
chown -R ubuntu:ubuntu /home/ubuntu/.code-server

# ─── OpenClaw data directory ───────────────────────────────────────
mkdir -p /home/ubuntu/.openclaw
chown -R ubuntu:ubuntu /home/ubuntu/.openclaw

# ─── OpenClaw config ────────────────────────────────────────────────
# OpenClaw reads openclaw.json (not openclaw.json5).
# We need to ensure three things regardless of whether onboard has run:
#   1. gateway.port = 10003  (matches supervisor --port flag, fixes CLI tools)
#   2. gateway.controlUi.dangerouslyDisableDeviceAuth = true
#      (disable browser device-pairing; token auth is sufficient in a container)
#   3. gateway.controlUi.allowInsecureAuth = true  (allow HTTP, not just HTTPS)
OPENCLAW_JSON="/home/ubuntu/.openclaw/openclaw.json"
if [ -f "$OPENCLAW_JSON" ]; then
    # Patch existing config (written by openclaw onboard)
    PATCHED=$(jq '
        .gateway.port = 10003 |
        .gateway.controlUi.dangerouslyDisableDeviceAuth = true |
        .gateway.controlUi.allowInsecureAuth = true
    ' "$OPENCLAW_JSON") && echo "$PATCHED" > "$OPENCLAW_JSON" \
        && echo "[startup] OpenClaw config patched (port=10003, dangerouslyDisableDeviceAuth=true)" \
        || echo "[startup] WARNING: Failed to patch OpenClaw config"
else
    # First-ever run before onboard: write a minimal bootstrap config
    cat > "$OPENCLAW_JSON" <<'EOF'
{
  "gateway": {
    "port": 10003,
    "mode": "local",
    "bind": "loopback",
    "auth": { "mode": "token" },
    "controlUi": {
      "allowInsecureAuth": true,
      "dangerouslyDisableDeviceAuth": true
    }
  }
}
EOF
    echo "[startup] OpenClaw bootstrap config written"
fi
chown ubuntu:ubuntu "$OPENCLAW_JSON"

# ─── Load persisted runtime config (overrides docker run env vars) ───
WEBCODE_CFG=/home/ubuntu/.webcode/config.json
if [ -f "$WEBCODE_CFG" ]; then
  echo "[startup] Loading persisted config from $WEBCODE_CFG"
  for KEY in AUTH_USER AUTH_PASSWORD VNC_PASSWORD OPENCLAW_TOKEN \
             GIT_USER_NAME GIT_USER_EMAIL CF_TUNNEL_TOKEN \
             ENABLE_KANBAN ENABLE_OPENCLAW ENABLE_CLAUDECODEUI; do
    VAL=$(python3 -c "
import json,sys
try:
  d=json.load(open('$WEBCODE_CFG'))
  print(d.get('$KEY',''),end='')
except: pass
" 2>/dev/null)
    [ -n "$VAL" ] && export "$KEY=$VAL"
  done
fi

# ─── Dashboard auth setup (Basic Auth for all web services) ──────────
export AUTH_USER="${AUTH_USER:-admin}"
export AUTH_PASSWORD="${AUTH_PASSWORD:-changeme}"
export OPENCLAW_TOKEN="${OPENCLAW_TOKEN:-sk-webcode}"
export VNC_PASSWORD="${VNC_PASSWORD:-changeme}"
echo "[startup] Basic Auth enabled — user: $AUTH_USER"

# ─── Cloudflare Tunnel (optional) ─────────────────────────────────
if [ -n "$CF_TUNNEL_TOKEN" ]; then
    echo "[startup] Cloudflare Tunnel enabled"
    export CF_TUNNEL_TOKEN
else
    echo "[startup] Cloudflare Tunnel disabled (CF_TUNNEL_TOKEN not set)"
    export CF_TUNNEL_TOKEN="unused"
    sed -i 's/autostart=true/autostart=false/' /etc/supervisor/conf.d/supervisor-cloudflared.conf
fi

# ─── Background tool upgrades (non-blocking) ─────────────────────────
# Upgrade openclaw in system Node global (takes effect after supervisord restart)
nohup npm install -g openclaw@2026.3.8 >> /tmp/npm-upgrade.log 2>&1 &
# Upgrade claude-code for ubuntu user via nvm
su -l ubuntu -c \
    'source ~/.nvm/nvm.sh 2>/dev/null && npm install -g @anthropic-ai/claude-code@latest >> /tmp/claude-upgrade.log 2>&1' &

# ─── Enable ClaudeCodeUI Platform mode (no authentication required) ───
if [ -f /opt/enable-claudecodeui-platform-mode.sh ]; then
    bash /opt/enable-claudecodeui-platform-mode.sh
fi

# ─── Export service enable flags for supervisor ───────────────────────
export WEBCODE_HAS_VIBE_KANBAN="${WEBCODE_HAS_VIBE_KANBAN:-false}"
export WEBCODE_HAS_CLAUDECODEUI="${WEBCODE_HAS_CLAUDECODEUI:-false}"
export ENABLE_KANBAN="${ENABLE_KANBAN:-$WEBCODE_HAS_VIBE_KANBAN}"
export ENABLE_OPENCLAW="${ENABLE_OPENCLAW:-true}"
export ENABLE_CLAUDECODEUI="${ENABLE_CLAUDECODEUI:-$WEBCODE_HAS_CLAUDECODEUI}"
export ENABLE_FUSE="${ENABLE_FUSE:-false}"

# ─── Mode selection ─────────────────────────────────────────────────
if [ "$MODE" = "lite" ]; then
    echo "[startup] Lite mode: starting Theia + Vibe Kanban only (no VNC desktop)"
    exec /usr/bin/supervisord -n -c /etc/supervisor/conf.d/supervisord-lite.conf
else
    echo "[startup] Desktop mode: starting full GNOME desktop + all services"

    # VNC password setup
    mkdir -p /home/ubuntu/.vnc
    VNC_PASS="${PASSWORD:-$(openssl rand -base64 8)}"
    if [ -z "$PASSWORD" ]; then
        echo "[startup] Generated VNC password: $VNC_PASS"
    fi

    # Find vncpasswd binary (could be vncpasswd or tigervncpasswd)
    VNCPASSWD_BIN=""
    for cmd in vncpasswd tigervncpasswd /usr/bin/vncpasswd /usr/bin/tigervncpasswd; do
        if command -v "$cmd" &>/dev/null || [ -x "$cmd" ]; then
            VNCPASSWD_BIN="$cmd"
            break
        fi
    done

    if [ -n "$VNCPASSWD_BIN" ]; then
        echo "$VNC_PASS" | "$VNCPASSWD_BIN" -f > /home/ubuntu/.vnc/passwd
    else
        echo "[startup] WARNING: vncpasswd not found, writing password via Python"
        python3 /opt/vnc-setpass.py "$VNC_PASS" /home/ubuntu/.vnc/passwd
    fi

    chmod 600 /home/ubuntu/.vnc/passwd
    chown -R ubuntu:ubuntu /home/ubuntu/.vnc

    # XDG_RUNTIME_DIR for ubuntu user (fcitx5, dbus, dconf need it)
    mkdir -p /run/user/1000
    chown ubuntu:ubuntu /run/user/1000
    chmod 700 /run/user/1000

    # PulseAudio socket directory
    mkdir -p /run/user/1000/pulse
    chown ubuntu:ubuntu /run/user/1000/pulse

    # D-Bus system bus (needed by PulseAudio for null-sink module)
    mkdir -p /run/dbus
    if [ ! -S /run/dbus/system_bus_socket ]; then
        dbus-daemon --system --fork
        echo "[startup] D-Bus system bus started"
    fi

    # fcitx 4 configuration
    FCITX_DIR=/home/ubuntu/.config/fcitx
    mkdir -p "$FCITX_DIR"

    # fcitx 4 global config - hotkey to toggle Chinese input
    cat > "$FCITX_DIR/config" <<'FCITX_EOF'
[Hotkey]
TriggerKey=CTRL_SPACE
AltTriggerKey=SHIFT_SHIFT
IMSwitchKey=False
FCITX_EOF

    # fcitx 4 profile - pinyin as active IM (fcitx 4 format, NOT fcitx5)
    # IMName: the IM to activate on trigger; EnabledIM/IMOrder: IM list
    if [ ! -f "$FCITX_DIR/profile" ]; then
        # Prefer googlepinyin if installed, fall back to pinyin
        if dpkg -l fcitx-googlepinyin 2>/dev/null | grep -q '^ii'; then
            PINYIN_IM=googlepinyin
        else
            PINYIN_IM=pinyin
        fi
        cat > "$FCITX_DIR/profile" <<FCITX_PROFILE_EOF
[Profile]
IMName=${PINYIN_IM}
EnabledIM=${PINYIN_IM},keyboard-us:1
IMOrder=${PINYIN_IM},keyboard-us:1
FCITX_PROFILE_EOF
    fi

    chown -R ubuntu:ubuntu /home/ubuntu/.config

    # Reset gnome-panel layout in user dconf so it reads from layout file.
    # This handles stale layout data persisted in Docker volumes.
    sudo -u ubuntu dbus-run-session -- dconf reset -f /org/gnome/gnome-panel/ 2>/dev/null || true

    # Clean stale X locks (previously in vnc-wrapper.sh)
    rm -f /tmp/.X1-lock /tmp/.X11-unix/X1

    # Clean stale Chromium/Chrome locks (including hostname-specific profiles)
    rm -f /home/ubuntu/.config/chromium/SingletonLock
    rm -f /home/ubuntu/.config/google-chrome/SingletonLock
    rm -f /home/ubuntu/.config/chromium-*/SingletonLock 2>/dev/null || true
    rm -f /home/ubuntu/.config/google-chrome-*/SingletonLock 2>/dev/null || true

    # Copy xsession (supervisor desktop process reads ~/.xsession)
    cp /opt/xsession /home/ubuntu/.xsession
    chmod +x /home/ubuntu/.xsession
    chown ubuntu:ubuntu /home/ubuntu/.xsession

    # Desktop shortcuts
    cp /opt/desktop-shortcuts/*.desktop /home/ubuntu/Desktop/ 2>/dev/null || true
    chmod +x /home/ubuntu/Desktop/*.desktop 2>/dev/null || true
    chown -R ubuntu:ubuntu /home/ubuntu/Desktop

    exec /usr/bin/supervisord -n -c /etc/supervisor/supervisord.conf
fi
