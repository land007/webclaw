#!/bin/bash
# 通用按需安装调度器
#
# 用法: webclaw-app-launcher <app-id> [args...]
#
# 行为:
#   - 读 /opt/on-demand-apps/<app-id>.json 拿到包名/二进制/下载信息
#   - 若 .deb 包已装,直接 exec 二进制（透传 args）
#   - 未装则 zenity 询问用户,确认后下载 + apt-get install,装完提示再次点击启动
#
# .deb 落到固定前缀 /tmp/webclaw-ondemand-<id>.deb,
# 由 /etc/sudoers.d/webclaw-app-launcher 免密授权该路径的安装命令。

set -u

APP_ID="${1:-}"
shift || true

if [ -z "$APP_ID" ]; then
    zenity --error --title="按需安装" --text="缺少应用 ID 参数" --width=320
    exit 1
fi

MANIFEST="/opt/on-demand-apps/${APP_ID}.json"
LOG="/tmp/webclaw-ondemand-${APP_ID}.log"

if [ ! -f "$MANIFEST" ]; then
    zenity --error --title="按需安装" --text="未找到应用清单:\n$MANIFEST" --width=380
    exit 1
fi

PKG=$(jq -r '.package' "$MANIFEST")
NAME=$(jq -r '.name' "$MANIFEST")
BIN=$(jq -r '.binary' "$MANIFEST")
REPO=$(jq -r '.github_repo' "$MANIFEST")
ASSET_PATTERN=$(jq -r '.asset_pattern' "$MANIFEST")

# 已装 -> 直接启动,后台脱离终端避免阻塞 dbus-launch 等
if dpkg -s "$PKG" >/dev/null 2>&1 && [ -x "$BIN" ]; then
    setsid "$BIN" "$@" </dev/null >/dev/null 2>&1 &
    exit 0
fi

# 架构映射
ARCH=$(dpkg --print-architecture)
ARCH_VAR=$(jq -r --arg a "$ARCH" '.arch_map[$a] // empty' "$MANIFEST")
if [ -z "$ARCH_VAR" ]; then
    zenity --error --title="$NAME" --text="不支持的架构: $ARCH" --width=320
    exit 1
fi

# 询问用户
zenity --question \
    --title="$NAME" \
    --text="<b>$NAME</b> 尚未安装。\n\n点「安装」会从 GitHub 下载并安装最新版,\n这会占用一些磁盘空间。" \
    --ok-label="安装" --cancel-label="取消" \
    --width=400 || exit 0

{
    echo "5"
    echo "# 正在查询最新版本..."

    VERSION=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" 2>>"$LOG" \
        | grep '"tag_name"' | sed 's/.*"tag_name": *"v//;s/".*//')

    if [ -z "$VERSION" ]; then
        echo "# 无法获取最新版本号" >> "$LOG"
        echo "100"
        exit 1
    fi

    ASSET=${ASSET_PATTERN//\{version\}/$VERSION}
    ASSET=${ASSET//\{arch\}/$ARCH_VAR}
    URL="https://github.com/${REPO}/releases/download/v${VERSION}/${ASSET}"
    DEB="/tmp/webclaw-ondemand-${APP_ID}.deb"

    echo "15"
    echo "# 正在下载 $NAME v$VERSION (${ARCH_VAR})..."
    rm -f "$DEB"
    if ! curl -fsSL "$URL" -o "$DEB" 2>>"$LOG"; then
        echo "下载失败: $URL" >> "$LOG"
        echo "100"
        exit 1
    fi

    echo "65"
    echo "# 正在安装 .deb 包..."
    if ! sudo /usr/bin/apt-get install -y "$DEB" >>"$LOG" 2>&1; then
        echo "apt-get install 失败" >> "$LOG"
        rm -f "$DEB"
        echo "100"
        exit 1
    fi

    rm -f "$DEB"
    echo "100"
    echo "# 完成"
} | zenity --progress \
    --title="安装 $NAME" \
    --text="准备中..." \
    --percentage=0 --auto-close --no-cancel --width=420

if dpkg -s "$PKG" >/dev/null 2>&1; then
    zenity --info \
        --title="$NAME" \
        --text="<b>$NAME</b> 安装完成!\n\n再次点击桌面图标即可启动。" \
        --width=360
else
    zenity --error \
        --title="$NAME" \
        --text="安装失败,详细日志:\n$LOG" \
        --width=420
    exit 1
fi
