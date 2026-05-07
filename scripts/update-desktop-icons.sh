#!/bin/bash
# 更新桌面图标状态
# 为未安装的应用添加视觉标记

set -u

DESKTOP_DIR="/home/ubuntu/Desktop"
MANIFEST_DIR="/opt/on-demand-apps"
UNINSTALL_APP_DIR="/home/ubuntu/.local/share/applications/webclaw-uninstall"
UNINSTALL_MENU_DIR="/home/ubuntu/.local/share/desktop-directories"
UNINSTALL_MENU_FILE="/home/ubuntu/.config/menus/applications-merged/webclaw-uninstall.menu"
UNINSTALL_CATEGORY="WebClawUninstall"
INSTALL_MENU_DIR="/home/ubuntu/.local/share/desktop-directories"
INSTALL_MENU_FILE="/home/ubuntu/.config/menus/applications-merged/webclaw-install.menu"
INSTALL_CATEGORY="WebClawInstall"

cleanup_desktop_temp_files() {
    find "$DESKTOP_DIR" -maxdepth 1 -type f \( -name 'sed*' -o -name '*.tmp' \) -delete 2>/dev/null || true
}

# 检查应用是否已安装
is_installed() {
    local manifest="$1"
    local install_method=$(jq -r '.install_method // "github_release"' "$manifest")
    local pkg=$(jq -r '.package' "$manifest")
    local bin=$(jq -r '.binary' "$manifest")

    if [ "$install_method" = "appimage" ] || [ "$install_method" = "r2_download" ] || [ "$install_method" = "direct_download" ] || [ "$install_method" = "cursor_api" ] || [ "$install_method" = "custom_script" ]; then
        [ -x "$bin" ]
    else
        dpkg -s "$pkg" 2>/dev/null | grep -q "Status: install ok installed" && [ -x "$bin" ]
    fi
}

normalize_desktop_file() {
    local desktop="$1"
    local name="$2"
    local tmp="/tmp/webclaw-desktop-$(basename "$desktop").$$.tmp"

    awk -v name="$name" '
        BEGIN { in_entry = 0; skip_action = 0; saw_zh = 0 }
        /^\[Desktop Action Uninstall\]/ { skip_action = 1; next }
        /^\[/ && skip_action == 1 { skip_action = 0 }
        skip_action == 1 { next }
        /^\[Desktop Entry\]/ { in_entry = 1; print; next }
        /^\[/ && in_entry == 1 { in_entry = 0; if (!saw_zh) print "Name[zh_CN]=" name; print; next }
        in_entry == 1 && /^Name=/ { print "Name=" name; next }
        in_entry == 1 && /^Name\[zh_CN\]=/ { print "Name[zh_CN]=" name; saw_zh = 1; next }
        in_entry == 1 && /^Actions=/ { next }
        { print }
    ' "$desktop" > "$tmp"

    # 使用删除后重建的方式，触发 gnome-flashback 正确刷新缓存
    # 如果内容相同则跳过
    if cmp -s "$desktop" "$tmp" 2>/dev/null; then
        rm -f "$tmp"
        return
    fi

    # 先删除原文件，再移动新文件（避免 gnome-flashback 缓存累积）
    rm -f "$desktop"
    mv -f "$tmp" "$desktop"
    chown ubuntu:ubuntu "$desktop" 2>/dev/null || true
    chmod +x "$desktop" 2>/dev/null || true
}

write_uninstall_menu() {
    mkdir -p "$UNINSTALL_APP_DIR" "$UNINSTALL_MENU_DIR" "$(dirname "$UNINSTALL_MENU_FILE")"

    cat > "$UNINSTALL_MENU_DIR/webclaw-uninstall.directory" <<EOF
[Desktop Entry]
Name=Uninstall Installed Apps
Name[zh_CN]=卸载已安装应用
Icon=applications-system
Type=Directory
EOF

    cat > "$UNINSTALL_MENU_FILE" <<EOF
<!DOCTYPE Menu PUBLIC "-//freedesktop//DTD Menu 1.0//EN"
 "http://www.freedesktop.org/standards/menu-spec/1.0/menu.dtd">
<Menu>
  <Name>Applications</Name>
  <Menu>
    <Name>webclaw-uninstall</Name>
    <Directory>webclaw-uninstall.directory</Directory>
    <Include>
      <Category>${UNINSTALL_CATEGORY}</Category>
    </Include>
  </Menu>
</Menu>
EOF

    chown -R ubuntu:ubuntu "$UNINSTALL_APP_DIR" "$UNINSTALL_MENU_DIR" "$(dirname "$UNINSTALL_MENU_FILE")" 2>/dev/null || true
}

write_install_menu() {
    mkdir -p "$INSTALL_MENU_DIR" "$(dirname "$INSTALL_MENU_FILE")"

    cat > "$INSTALL_MENU_DIR/webclaw-install.directory" <<'EOF'
[Desktop Entry]
Name=Install Apps
Name[zh_CN]=安装应用
Icon=package-install
Type=Directory
EOF

    cat > "$INSTALL_MENU_FILE" <<'EOF'
<!DOCTYPE Menu PUBLIC "-//freedesktop//DTD Menu 1.0//EN"
 "http://www.freedesktop.org/standards/menu-spec/1.0/menu.dtd">
<Menu>
  <Name>Applications</Name>
  <Menu>
    <Name>webclaw-install</Name>
    <Directory>webclaw-install.directory</Directory>
    <Include>
      <Category>WebClawInstall</Category>
    </Include>
  </Menu>
</Menu>
EOF

    chown -R ubuntu:ubuntu "$INSTALL_MENU_DIR" "$(dirname "$INSTALL_MENU_FILE")" 2>/dev/null || true
}

ensure_uninstall_menu_entry() {
    local app_id="$1"
    local name="$2"
    local manifest="$3"
    local icon
    local entry="$UNINSTALL_APP_DIR/webclaw-uninstall-${app_id}.desktop"
    local uninstall_cmd

    icon="/opt/on-demand-icons/${app_id}.png"
    if [ ! -e "$icon" ]; then
        icon=$(jq -r '.icon // empty' "$manifest")
    fi
    [ -n "$icon" ] && [ "$icon" != "null" ] || icon="$app_id"

    # Hermes 使用自定义卸载脚本
    if [ "$app_id" = "hermes" ]; then
        uninstall_cmd="/opt/uninstall-hermes.sh"
    else
        uninstall_cmd="/usr/local/bin/webclaw-app-launcher --uninstall $app_id"
    fi

    cat > "$entry" <<EOF
[Desktop Entry]
Name=Uninstall $name
Name[zh_CN]=卸载 $name
Comment=Uninstall $name
Comment[zh_CN]=卸载 $name
Exec=$uninstall_cmd
Icon=$icon
Type=Application
Categories=${UNINSTALL_CATEGORY};
NoDisplay=false
StartupNotify=true
EOF

    chown ubuntu:ubuntu "$entry" 2>/dev/null || true
    chmod 644 "$entry" 2>/dev/null || true
}

remove_uninstall_menu_entry() {
    local app_id="$1"
    rm -f "$UNINSTALL_APP_DIR/webclaw-uninstall-${app_id}.desktop"
}

ensure_install_menu_entry() {
    local app_id="$1"
    local name="$2"
    local manifest="$3"
    local icon
    local entry="/home/ubuntu/.local/share/applications/webclaw-install-${app_id}.desktop"

    icon="/opt/on-demand-icons/${app_id}.png"
    if [ ! -e "$icon" ]; then
        icon=$(jq -r '.icon // empty' "$manifest")
    fi
    [ -n "$icon" ] && [ "$icon" != "null" ] || icon="$app_id"

    # Hermes 使用自定义启动器
    if [ "$app_id" = "hermes" ]; then
        exec_cmd="/opt/hermes-browser.sh"
    else
        exec_cmd="/usr/local/bin/webclaw-app-launcher $app_id"
    fi

    cat > "$entry" <<EOF
[Desktop Entry]
Name=$name
Name[zh_CN]=$name
Comment=Click to install $name
Comment[zh_CN]=点击安装 $name
Exec=$exec_cmd
Icon=$icon
Type=Application
Categories=${INSTALL_CATEGORY};
NoDisplay=false
StartupNotify=true
EOF

    chown ubuntu:ubuntu "$entry" 2>/dev/null || true
    chmod 644 "$entry" 2>/dev/null || true
}

remove_install_menu_entry() {
    local app_id="$1"
    rm -f "/home/ubuntu/.local/share/applications/webclaw-install-${app_id}.desktop"
}

create_desktop_icon() {
    local app_id="$1"
    local manifest="$2"
    local desktop="$DESKTOP_DIR/${app_id}.desktop"
    local name=$(jq -r '.name' "$manifest")
    local icon
    local exec_cmd

    # 如果已存在，跳过
    [ -f "$desktop" ] && return 0

    icon="/opt/on-demand-icons/${app_id}.png"
    if [ ! -e "$icon" ]; then
        icon=$(jq -r '.icon // empty' "$manifest")
    fi
    [ -n "$icon" ] && [ "$icon" != "null" ] || icon="$app_id"

    # Hermes 使用自定义启动器
    if [ "$app_id" = "hermes" ]; then
        exec_cmd="/opt/hermes-browser.sh"
    else
        exec_cmd="/usr/local/bin/webclaw-app-launcher $app_id"
    fi

    cat > "$desktop" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=$name
Name[zh_CN]=$name
Comment=Click to install or launch $name
Comment[zh_CN]=点击安装或启动 $name
Exec=$exec_cmd
Icon=$icon
Terminal=false
StartupNotify=true
EOF

    chown ubuntu:ubuntu "$desktop" 2>/dev/null || true
    chmod +x "$desktop" 2>/dev/null || true
}

restore_missing_desktop_icons() {
    # 恢复缺失的桌面图标
    for manifest in "$MANIFEST_DIR"/*.json; do
        [ -f "$manifest" ] || continue
        app_id=$(basename "$manifest" .json)
        desktop="$DESKTOP_DIR/${app_id}.desktop"

        # 如果桌面图标不存在，重新创建
        if [ ! -f "$desktop" ]; then
            create_desktop_icon "$app_id" "$manifest"
        fi
    done
}

cleanup_desktop_temp_files
write_uninstall_menu

# 恢复缺失的桌面图标（支持模式切换）
restore_missing_desktop_icons

# 读取环境变量
CLEAN_DESKTOP="${CLEAN_DESKTOP:-true}"

# 根据环境变量决定是否创建"安装应用"菜单
if [ "$CLEAN_DESKTOP" = "true" ]; then
    write_install_menu
fi

# 处理每个桌面图标
for desktop in "$DESKTOP_DIR"/*.desktop; do
    [ -f "$desktop" ] || continue
    case "$(basename "$desktop")" in
        uninstall-*.desktop) continue ;;
    esac

    # 检查是否是按需安装的应用
    # Hermes 的桌面图标使用 /opt/hermes-browser.sh 启动
    if ! grep -q "webclaw-app-launcher\|hermes-launcher\|/opt/hermes-browser.sh" "$desktop"; then
        continue
    fi

    # 获取 app-id
    if grep -q "hermes-launcher" "$desktop"; then
        app_id="hermes"
    else
        app_id=$(grep -m1 "^Exec=/usr/local/bin/webclaw-app-launcher " "$desktop" | sed 's/.*webclaw-app-launcher //' | sed 's/ .*//')
    fi
    [ -n "$app_id" ] || continue

    manifest="$MANIFEST_DIR/${app_id}.json"
    [ -f "$manifest" ] || continue

    name=$(jq -r '.name' "$manifest")

    if is_installed "$manifest"; then
        # === 已安装应用 ===
        # 移除"未安装"标记，显示正常名称
        normalize_desktop_file "$desktop" "$name"
        ensure_uninstall_menu_entry "$app_id" "$name" "$manifest"

        # 如果启用简洁桌面模式，从"安装应用"菜单移除
        if [ "$CLEAN_DESKTOP" = "true" ]; then
            remove_install_menu_entry "$app_id"
        fi
    else
        # === 未安装应用 ===
        if [ "$CLEAN_DESKTOP" = "true" ]; then
            # 简洁桌面模式：隐藏桌面图标，添加到"安装应用"菜单
            normalize_desktop_file "$desktop" "⬇ $name"
            # 设置 NoDisplay=true 隐藏桌面图标
            if ! grep -q "^NoDisplay=true" "$desktop"; then
                sed -i '/^Type=Application/a NoDisplay=true' "$desktop"
            fi
            ensure_install_menu_entry "$app_id" "$name" "$manifest"
        else
            # 传统模式：在桌面显示，添加"待安装"标记
            normalize_desktop_file "$desktop" "⬇ $name"
            # 确保移除 NoDisplay，让图标显示在桌面
            sed -i '/^NoDisplay=true/d' "$desktop"
        fi

        # 未安装应用不需要卸载菜单项
        remove_uninstall_menu_entry "$app_id"
    fi
done
