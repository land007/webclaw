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

cleanup_desktop_temp_files() {
    find "$DESKTOP_DIR" -maxdepth 1 -type f \( -name 'sed*' -o -name '*.tmp' \) -delete 2>/dev/null || true
}

# 检查应用是否已安装
is_installed() {
    local manifest="$1"
    local install_method=$(jq -r '.install_method // "github_release"' "$manifest")
    local pkg=$(jq -r '.package' "$manifest")
    local bin=$(jq -r '.binary' "$manifest")

    if [ "$install_method" = "appimage" ] || [ "$install_method" = "r2_download" ] || [ "$install_method" = "direct_download" ] || [ "$install_method" = "cursor_api" ]; then
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

ensure_uninstall_menu_entry() {
    local app_id="$1"
    local name="$2"
    local manifest="$3"
    local icon
    local entry="$UNINSTALL_APP_DIR/webclaw-uninstall-${app_id}.desktop"

    icon="/opt/on-demand-icons/${app_id}.png"
    if [ ! -e "$icon" ]; then
        icon=$(jq -r '.icon // empty' "$manifest")
    fi
    [ -n "$icon" ] && [ "$icon" != "null" ] || icon="$app_id"

    cat > "$entry" <<EOF
[Desktop Entry]
Name=Uninstall $name
Name[zh_CN]=卸载 $name
Comment=Uninstall $name
Comment[zh_CN]=卸载 $name
Exec=/usr/local/bin/webclaw-app-launcher --uninstall $app_id
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

cleanup_desktop_temp_files
write_uninstall_menu

# 处理每个桌面图标
for desktop in "$DESKTOP_DIR"/*.desktop; do
    [ -f "$desktop" ] || continue
    case "$(basename "$desktop")" in
        uninstall-*.desktop) continue ;;
    esac

    # 检查是否是按需安装的应用
    if ! grep -q "webclaw-app-launcher" "$desktop"; then
        continue
    fi

    # 获取 app-id
    app_id=$(grep -m1 "^Exec=/usr/local/bin/webclaw-app-launcher " "$desktop" | sed 's/.*webclaw-app-launcher //' | sed 's/ .*//')
    [ -n "$app_id" ] || continue

    manifest="$MANIFEST_DIR/${app_id}.json"
    [ -f "$manifest" ] || continue

    name=$(jq -r '.name' "$manifest")

    if is_installed "$manifest"; then
        # 已安装 - 移除"未安装"标记
        normalize_desktop_file "$desktop" "$name"
        ensure_uninstall_menu_entry "$app_id" "$name" "$manifest"
    else
        # 未安装 - 添加"待安装"标记
        normalize_desktop_file "$desktop" "⬇ $name"
        remove_uninstall_menu_entry "$app_id"
    fi
done
