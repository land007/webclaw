#!/bin/bash
# 通用按需安装调度器
#
# 用法: webclaw-app-launcher <app-id> [args...]
#
# 行为:
#   - 读 /opt/on-demand-apps/<app-id>.json 拿到包名/二进制/安装方式
#   - 若已装,直接 setsid exec 二进制(透传 args)
#   - 未装则 zenity 询问,确认后按 install_method 执行安装
#
# 支持的 install_method:
#   - "github_release" (默认): 从 .github_repo 拿最新 release,按 .asset_pattern + .arch_map
#                              下载 .deb 到 /tmp/webclaw-ondemand-<id>.deb,sudo apt-get install
#   - "apt":                   直接 sudo apt-get update && sudo apt-get install -y <apt_package>
#                              (适合本来就在 apt 仓库的包,如 VS Code)
#
# sudo 授权由 /etc/sudoers.d/webclaw-app-launcher 提供:
#   - apt-get install -y /tmp/webclaw-ondemand-*.deb (固定路径前缀)
#   - apt-get update
#   - 每个 apt 模式应用各自的 apt-get install -y <pkg> 白名单

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
INSTALL_METHOD=$(jq -r '.install_method // "github_release"' "$MANIFEST")

# 可选: manifest 里固定要传给二进制的参数(比如 VS Code 在容器里必须 --no-sandbox,
# 不带的话 chrome-sandbox SUID 检查失败立刻静默退出)
mapfile -t DEFAULT_ARGS < <(jq -r '.default_args // [] | .[]' "$MANIFEST")

# 已装 -> 直接启动,setsid 脱离终端避免阻塞 dbus-launch 等
# 根据安装方法使用不同的检查方式
if [ "$INSTALL_METHOD" = "appimage" ]; then
    # AppImage 解压安装: 检查解压目录是否存在且可执行
    APPIMAGE_EXTRACT_DIR="/opt/ondemand-apps/${APP_ID}"
    if [ -x "$BIN" ]; then
        setsid "$BIN" "${DEFAULT_ARGS[@]}" "$@" </dev/null >/dev/null 2>&1 &
        exit 0
    fi
else
    # apt/github_release: 检查 dpkg 包是否已安装
    if dpkg -s "$PKG" >/dev/null 2>&1 && [ -x "$BIN" ]; then
        setsid "$BIN" "${DEFAULT_ARGS[@]}" "$@" </dev/null >/dev/null 2>&1 &
        exit 0
    fi
fi

# 未装 -> 询问
zenity --question \
    --title="$NAME" \
    --text="<b>$NAME</b> 尚未安装。\n\n点「安装」会下载并安装最新版,\n这会占用一些磁盘空间。" \
    --ok-label="安装" --cancel-label="取消" \
    --width=400 || exit 0

case "$INSTALL_METHOD" in
    apt)
        # ─── apt 仓库直装(VS Code 等) ───────────────────────────────
        APT_PKG=$(jq -r '.apt_package' "$MANIFEST")
        {
            echo "10"
            echo "# 正在刷新 apt 索引..."
            if ! sudo /usr/bin/apt-get update >>"$LOG" 2>&1; then
                echo "apt-get update 失败" >> "$LOG"
                echo "100"; exit 1
            fi

            echo "40"
            echo "# 正在安装 $NAME ($APT_PKG)..."
            # Wireshark 需要预配置 debconf 避免交互提示
            if [ "$APT_PKG" = "wireshark" ]; then
                echo "wireshark-common wireshark-common/setuid boolean true" | sudo debconf-set-selections >>"$LOG" 2>&1
            fi
            if ! sudo /usr/bin/apt-get install -y "$APT_PKG" >>"$LOG" 2>&1; then
                echo "apt-get install $APT_PKG 失败" >> "$LOG"
                echo "100"; exit 1
            fi

            # Wireshark 特殊处理: 配置 dumpcap 权限
            if [ "$APT_PKG" = "wireshark" ]; then
                echo "70"
                echo "# 正在配置网络捕获权限..."
                # 将 ubuntu 用户添加到 wireshark 组
                sudo usermod -a -G wireshark ubuntu >>"$LOG" 2>&1
                # 设置 dumpcap 的 capabilities
                sudo setcap cap_net_raw,cap_net_admin=ep /usr/bin/dumpcap >>"$LOG" 2>&1
            fi

            echo "100"
            echo "# 完成"
        } | zenity --progress \
            --title="安装 $NAME" \
            --text="准备中..." \
            --percentage=0 --auto-close --no-cancel --width=420
        ;;

    github_release)
        # ─── GitHub release 下 .deb 装(OpenTypeless / CC Switch 等) ──
        REPO=$(jq -r '.github_repo' "$MANIFEST")
        ASSET_PATTERN=$(jq -r '.asset_pattern' "$MANIFEST")
        ARCH=$(dpkg --print-architecture)
        ARCH_VAR=$(jq -r --arg a "$ARCH" '.arch_map[$a] // empty' "$MANIFEST")
        if [ -z "$ARCH_VAR" ]; then
            zenity --error --title="$NAME" --text="不支持的架构: $ARCH" --width=320
            exit 1
        fi

        {
            echo "5"
            echo "# 正在查询最新版本..."
            VERSION=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" 2>>"$LOG" \
                | grep '"tag_name"' | sed 's/.*"tag_name": *"v//;s/".*//')
            if [ -z "$VERSION" ]; then
                echo "无法获取最新版本号" >> "$LOG"
                echo "100"; exit 1
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
                echo "100"; exit 1
            fi

            echo "65"
            echo "# 正在安装 .deb 包..."
            if ! sudo /usr/bin/apt-get install -y "$DEB" >>"$LOG" 2>&1; then
                echo "apt-get install 失败" >> "$LOG"
                rm -f "$DEB"
                echo "100"; exit 1
            fi

            rm -f "$DEB"
            echo "100"
            echo "# 完成"
        } | zenity --progress \
            --title="安装 $NAME" \
            --text="准备中..." \
            --percentage=0 --auto-close --no-cancel --width=420
        ;;

    appimage)
        # ─── GitHub release 下 AppImage 解压安装(Obsidian 等) ───────
        # AppImage 解压安装更可靠，不依赖 fuse 挂载
        REPO=$(jq -r '.github_repo' "$MANIFEST")
        ASSET_PATTERN=$(jq -r '.asset_pattern' "$MANIFEST")
        ARCH=$(dpkg --print-architecture)
        ARCH_VAR=$(jq -r --arg a "$ARCH" '.arch_map[$a] // empty' "$MANIFEST")
        if [ -z "$ARCH_VAR" ]; then
            zenity --error --title="$NAME" --text="不支持的架构: $ARCH" --width=320
            exit 1
        fi

        # AppImage 解压目录
        APPIMAGE_EXTRACT_DIR="/opt/ondemand-apps/${APP_ID}"
        APPIMAGE_TMP="/tmp/webclaw-ondemand-${APP_ID}.AppImage"
        sudo /bin/mkdir -p "$APPIMAGE_EXTRACT_DIR" 2>>"$LOG"

        {
            echo "5"
            echo "# 正在查询最新版本..."
            VERSION=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" 2>>"$LOG" \
                | grep '"tag_name"' | sed 's/.*"tag_name": *"v//;s/".*//')
            if [ -z "$VERSION" ]; then
                echo "无法获取最新版本号" >> "$LOG"
                echo "100"; exit 1
            fi

            # 替换版本和架构后缀(注意: arch_var 可能是空字符串)
            ASSET=${ASSET_PATTERN//\{version\}/$VERSION}
            ASSET=${ASSET//\{arch_suffix\}/$ARCH_VAR}
            URL="https://github.com/${REPO}/releases/download/v${VERSION}/${ASSET}"

            echo "15"
            echo "# 正在下载 $NAME v$VERSION..."
            rm -f "$APPIMAGE_TMP"
            rm -rf "$APPIMAGE_EXTRACT_DIR"
            if ! curl -fsSL "$URL" -o "$APPIMAGE_TMP" 2>>"$LOG"; then
                echo "下载失败: $URL" >> "$LOG"
                echo "100"; exit 1
            fi

            echo "40"
            echo "# 正在准备 AppImage..."
            chmod +x "$APPIMAGE_TMP" 2>>"$LOG"

            echo "50"
            echo "# 正在解压 AppImage..."
            cd /tmp
            if ! "$APPIMAGE_TMP" --appimage-extract >/dev/null 2>>"$LOG"; then
                echo "解压失败" >> "$LOG"
                rm -f "$APPIMAGE_TMP"
                echo "100"; exit 1
            fi

            echo "75"
            echo "# 正在安装..."
            # 移动解压内容到目标目录
            if ! sudo /bin/mv -f squashfs-root "$APPIMAGE_EXTRACT_DIR" 2>>"$LOG"; then
                echo "移动失败" >> "$LOG"
                rm -f "$APPIMAGE_TMP"
                rm -rf /tmp/squashfs-root
                echo "100"; exit 1
            fi

            # 清理临时文件
            rm -f "$APPIMAGE_TMP"
            rm -rf /tmp/squashfs-root

            echo "100"
            echo "# 完成"
        } | zenity --progress \
            --title="安装 $NAME" \
            --text="准备中..." \
            --percentage=0 --auto-close --no-cancel --width=420
        ;;

    *)
        zenity --error --title="$NAME" \
            --text="未知的 install_method: $INSTALL_METHOD" --width=380
        exit 1
        ;;
esac

# 验证安装结果
if [ "$INSTALL_METHOD" = "appimage" ]; then
    # AppImage: 检查文件是否存在且可执行
    if [ -x "$BIN" ]; then
        INSTALL_OK=1
    else
        INSTALL_OK=0
    fi
else
    # apt/github_release: 检查 dpkg 包
    if dpkg -s "$PKG" >/dev/null 2>&1; then
        INSTALL_OK=1
    else
        INSTALL_OK=0
    fi
fi

if [ "$INSTALL_OK" = 1 ]; then
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
