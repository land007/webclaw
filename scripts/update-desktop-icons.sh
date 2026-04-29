#!/bin/bash
# 更新桌面图标状态
# 为未安装的应用添加视觉标记

set -u

DESKTOP_DIR="/home/ubuntu/Desktop"
MANIFEST_DIR="/opt/on-demand-apps"

# 检查应用是否已安装
is_installed() {
    local manifest="$1"
    local install_method=$(jq -r '.install_method // "github_release"' "$manifest")
    local pkg=$(jq -r '.package' "$manifest")
    local bin=$(jq -r '.binary' "$manifest")

    if [ "$install_method" = "appimage" ] || [ "$install_method" = "r2_download" ] || [ "$install_method" = "direct_download" ]; then
        [ -x "$bin" ]
    else
        dpkg -s "$pkg" >/dev/null 2>&1 && [ -x "$bin" ]
    fi
}

# 处理每个桌面图标
for desktop in "$DESKTOP_DIR"/*.desktop; do
    [ -f "$desktop" ] || continue

    # 检查是否是按需安装的应用
    if ! grep -q "webclaw-app-launcher" "$desktop"; then
        continue
    fi

    # 获取 app-id
    app_id=$(grep "Exec=" "$desktop" | sed 's/.*webclaw-app-launcher //' | sed 's/ .*//')
    [ -n "$app_id" ] || continue

    manifest="$MANIFEST_DIR/${app_id}.json"
    [ -f "$manifest" ] || continue

    name=$(jq -r '.name' "$manifest")

    if is_installed "$manifest"; then
        # 已安装 - 移除"未安装"标记
        sed -i "s|^Name=.*|Name=$name|" "$desktop"
        sed -i "s|^Name\[zh_CN\]=.*|Name[zh_CN]=$name|" "$desktop"
    else
        # 未安装 - 添加"待安装"标记
        sed -i "s|^Name=.*|Name=⬇ $name|" "$desktop"
        sed -i "s|^Name\[zh_CN\]=.*|Name[zh_CN]=⬇ $name|" "$desktop"
    fi
done
