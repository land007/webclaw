#!/bin/bash
# 构建期非交互预装所有按需桌面应用
#
# 用途: 在 Dockerfile.full 里跑一次,把 configs/on-demand-apps/*.json 声明的所有
#       应用按 manifest 装到与 webclaw-app-launcher.sh 期望一致的路径上,这样
#       桌面图标(Exec=webclaw-app-launcher <id>)首次点击就走"已安装→直接 exec"
#       的快速路径,不再弹 zenity 安装框。
#
# 设计要点:
#   - 与 webclaw-app-launcher.sh 共享同一份 manifest /opt/on-demand-apps/*.json
#   - 检测路径与启动器一致(apt: dpkg -s + [-x BIN]; appimage: [-x BIN])
#   - 单个应用失败软兜底,不拖垮整个 docker build;运行时 launcher 仍是 fallback
#   - 构建期以 root 运行,跳过 sudo
#
# 注意: 此脚本只负责装,不修改 .desktop 文件、不动 /usr/local/bin/webclaw-app-launcher。

set -u

MANIFEST_DIR="/opt/on-demand-apps"
ARCH=$(dpkg --print-architecture)

# ── 集中刷一次 apt 索引 ──────────────────────────────────────────────
apt-get update

log()  { echo "[preinstall] $*"; }
warn() { echo "[preinstall] WARN: $*" >&2; }

# ── apt 模式 ────────────────────────────────────────────────────────
preinstall_apt() {
    local id="$1" manifest="$2"
    local apt_pkg
    apt_pkg=$(jq -r '.apt_package' "$manifest")
    log "$id: apt install $apt_pkg"

    # Wireshark 装前预设 dumpcap setuid 不询问
    if [ "$apt_pkg" = "wireshark" ]; then
        echo "wireshark-common wireshark-common/setuid boolean true" | debconf-set-selections
    fi

    apt-get install -y "$apt_pkg"

    # Wireshark 装后给 dumpcap 抓包能力 + 把 ubuntu 加入 wireshark 组
    if [ "$apt_pkg" = "wireshark" ]; then
        usermod -a -G wireshark ubuntu || warn "$id: usermod failed"
        setcap cap_net_raw,cap_net_admin=ep /usr/bin/dumpcap || warn "$id: setcap failed"
    fi
}

# ── github_release(.deb) 模式 ──────────────────────────────────────
preinstall_github_release() {
    local id="$1" manifest="$2"
    local repo pattern arch_var version asset url deb

    repo=$(jq -r '.github_repo' "$manifest")
    pattern=$(jq -r '.asset_pattern' "$manifest")
    arch_var=$(jq -r --arg a "$ARCH" '.arch_map[$a] // empty' "$manifest")

    if [ -z "$arch_var" ]; then
        log "$id: arch=$ARCH 不在 arch_map 中,跳过"
        return 0
    fi

    version=$(curl -fsSL "https://api.github.com/repos/${repo}/releases/latest" \
        | grep '"tag_name"' | sed 's/.*"tag_name": *"v//;s/".*//')
    if [ -z "$version" ]; then
        warn "$id: 拿不到最新版本号,跳过"
        return 1
    fi

    asset=${pattern//\{version\}/$version}
    asset=${asset//\{arch\}/$arch_var}
    url="https://github.com/${repo}/releases/download/v${version}/${asset}"
    deb="/tmp/preinstall-${id}.deb"

    log "$id: 下载 $url"
    rm -f "$deb"
    if ! curl -fsSL "$url" -o "$deb"; then
        warn "$id: 下载失败"
        return 1
    fi

    log "$id: apt install .deb"
    apt-get install -y "$deb"
    rm -f "$deb"
}

# ── appimage 模式 ───────────────────────────────────────────────────
preinstall_appimage() {
    local id="$1" manifest="$2"
    local repo pattern arch_var version asset url tmp extract_dir extracted unbundle_gl

    repo=$(jq -r '.github_repo' "$manifest")
    pattern=$(jq -r '.asset_pattern' "$manifest")
    arch_var=$(jq -r --arg a "$ARCH" '.arch_map[$a] // empty' "$manifest")
    unbundle_gl=$(jq -r '.unbundle_gl // false' "$manifest")

    # arch_map 里登记了但 value 为空字符串(如 obsidian amd64="")也是合法的
    if ! jq -e --arg a "$ARCH" '.arch_map | has($a)' "$manifest" >/dev/null; then
        log "$id: arch=$ARCH 不在 arch_map 中,跳过"
        return 0
    fi

    version=$(curl -fsSL "https://api.github.com/repos/${repo}/releases/latest" \
        | grep '"tag_name"' | sed 's/.*"tag_name": *"v//;s/".*//')
    if [ -z "$version" ]; then
        warn "$id: 拿不到最新版本号,跳过"
        return 1
    fi

    asset=${pattern//\{version\}/$version}
    asset=${asset//\{arch_suffix\}/$arch_var}
    local download_url="https://github.com/${repo}/releases/download/v${version}/${asset}"

    extract_dir="/opt/ondemand-apps/${id}"
    tmp="/tmp/preinstall-${id}.AppImage"

    rm -f "$tmp"
    rm -rf "$extract_dir"
    mkdir -p "$extract_dir"

    # 使用 GitHub API 下载（更可靠，避免 404）
    if ! github_api_download "$repo" "$asset" "$tmp"; then
        # API 下载失败，尝试直接下载
        log "$id: API 下载失败，尝试直接下载 $download_url"
        if ! curl -fsSL "$download_url" -o "$tmp"; then
            warn "$id: 下载失败"
            return 1
        fi
    fi
    chmod +x "$tmp"

    log "$id: 解压 AppImage"
    rm -rf /tmp/squashfs-root /tmp/AppDir
    ( cd /tmp && "$tmp" --appimage-extract >/dev/null 2>&1 ) || {
        warn "$id: --appimage-extract 失败（可能是跨架构构建问题，请确保 Docker buildx QEMU 配置正确）"
        rm -f "$tmp"
        return 1
    }

    # pkgforge 系 AppImage: /tmp/squashfs-root 是个软链 → ./AppDir,
    # 必须解到真实目录,否则 mv 走的是软链本身、留下孤儿 AppDir
    extracted=$(readlink -f /tmp/squashfs-root)

    # 可选: 把 AppImage 自带的旧 Mesa GL 库换成系统 Mesa 软链
    # (与 webclaw-app-launcher.sh:227-246 保持一致)
    if [ "$unbundle_gl" = "true" ]; then
        log "$id: 卸绑 AppImage 自带 GL 库"
        local libd="$extracted/shared/lib"
        local sysd
        sysd="/usr/lib/$(gcc -print-multiarch 2>/dev/null || dpkg-architecture -qDEB_HOST_MULTIARCH 2>/dev/null || echo aarch64-linux-gnu)"
        if [ -d "$libd" ]; then
            mkdir -p "$libd/.gl-bundled-bak"
            local pat f
            for pat in libEGL libGL libGLX libGLES libGLdispatch libgbm; do
                for f in "$libd/${pat}"*; do
                    [ -e "$f" ] || continue
                    case "$f" in *.gl-bundled-bak*) continue ;; esac
                    mv -f "$f" "$libd/.gl-bundled-bak/" || true
                done
            done
            local name
            for name in libEGL.so.1 libGL.so.1 libGLX.so.0 libGLdispatch.so.0 \
                        libGLX_mesa.so.0 libEGL_mesa.so.0 libgbm.so.1 libGLESv2.so.2; do
                [ -e "$sysd/$name" ] && ln -sfn "$sysd/$name" "$libd/$name"
            done
        fi
    fi

    log "$id: 移动到 $extract_dir/AppDir"
    mv -f "$extracted" "$extract_dir/AppDir"

    rm -f "$tmp"
    rm -rf /tmp/squashfs-root
}

# ── cursor_api 模式 (Cursor 编辑器) ─────────────────────────────────────
preinstall_cursor_api() {
    local id="$1" manifest="$2"
    local api_base arch_var version api_url install_dir tmp

    api_base=$(jq -r '.api_base' "$manifest")
    arch_var=$(jq -r --arg a "$ARCH" '.arch_map[$a] // empty' "$manifest")

    if [ -z "$arch_var" ]; then
        log "$id: arch=$ARCH 不在 arch_map 中,跳过"
        return 0
    fi

    # 动态获取最新版本
    version=$(curl -fsSL "https://api2.cursor.sh/updates/latest" 2>/dev/null | jq -r '.version // empty' 2>/dev/null)
    if [ -z "$version" ]; then
        # 如果动态获取失败,使用 manifest 中硬编码的版本
        version=$(jq -r '.version' "$manifest")
        log "$id: 使用硬编码版本 $version"
    else
        log "$id: 获取到最新版本 $version"
    fi

    install_dir="/opt/${id}"
    api_url="${api_base}/${arch_var}/cursor/${version}"
    tmp="/tmp/preinstall-${id}.AppImage"

    log "$id: 下载 $api_url"
    rm -f "$tmp"
    rm -rf "$install_dir"
    mkdir -p "$install_dir"

    if ! curl -fsSL "$api_url" -o "$tmp"; then
        warn "$id: 下载失败"
        return 1
    fi
    chmod +x "$tmp"

    log "$id: 解压 AppImage"
    rm -rf /tmp/squashfs-root /tmp/AppDir
    ( cd /tmp && "$tmp" --appimage-extract >/dev/null 2>&1 ) || {
        warn "$id: --appimage-extract 失败（可能是跨架构构建问题）"
        rm -f "$tmp"
        return 1
    }

    # 处理软链
    local extracted
    extracted=$(readlink -f /tmp/squashfs-root)

    log "$id: 移动到 $install_dir"
    mv -f "$extracted"/* "$install_dir/" 2>/dev/null || mv -f "$extracted" "$install_dir/cursor"

    # 确保 cursor 可执行文件存在
    if [ ! -e "$install_dir/cursor" ]; then
        # 尝试查找可执行文件
        find "$install_dir" -type f -name "cursor" -exec mv {} "$install_dir/cursor" \; 2>/dev/null
    fi
    chmod +x "$install_dir/cursor" 2>/dev/null

    rm -f "$tmp"
    rm -rf /tmp/squashfs-root /tmp/AppDir
}

# ── direct_download 模式 (webclaw-launcher 等) ─────────────────────────
preinstall_direct_download() {
    local id="$1" manifest="$2"
    local download_url version_api arch_var arch_suffix version install_dir tmp

    download_url=$(jq -r '.download_url' "$manifest")
    version_api=$(jq -r '.version_api // empty' "$manifest")
    arch_var=$(jq -r --arg a "$ARCH" '.arch_map[$a] // empty' "$manifest")
    arch_suffix=$(jq -r --arg a "$ARCH" --arg fallback "$arch_var" '.arch_suffix_map[$a] // $fallback // empty' "$manifest")

    if [ -z "$arch_var" ] && [ -z "$arch_suffix" ]; then
        log "$id: arch=$ARCH 不在 arch_map 中,跳过"
        return 0
    fi

    # 如果提供了 version_api，先获取版本号
    if [ -n "$version_api" ]; then
        version=$(curl -fsSL "$version_api" 2>/dev/null | jq -r '.version // .latest // empty' 2>/dev/null)
        if [ -z "$version" ]; then
            warn "$id: 无法获取版本号"
            return 1
        fi
        log "$id: 获取到版本 $version"
    else
        version=$(jq -r '.version // empty' "$manifest")
    fi

    # 替换 URL 中的占位符
    download_url=$(echo "$download_url" | sed "s/{version}/${version}/g")
    download_url=$(echo "$download_url" | sed "s/{arch}/${arch_var}/g")
    download_url=$(echo "$download_url" | sed "s/{arch_suffix}/${arch_suffix}/g")

    install_dir="/opt/${id}"
    tmp="/tmp/preinstall-${id}"

    log "$id: 下载 $download_url"
    rm -f "$tmp".*

    # 检测文件类型
    local file_type="unknown"
    if [[ "$download_url" == *".AppImage" ]] || [[ "$download_url" == *"appimage" ]]; then
        file_type="appimage"
    elif [[ "$download_url" == *".zip" ]]; then
        file_type="zip"
    elif [[ "$download_url" == *".tar.gz" ]]; then
        file_type="tar.gz"
    fi

    # GitHub URL 使用 API 下载
    if [[ "$download_url" == *"github.com"* ]] && [[ "$download_url" == *"/releases/download/"* ]]; then
        local asset_name
        asset_name=$(basename "$download_url")
        if ! github_api_download "$(echo "$download_url" | sed 's|.*github.com/\([^/]*\)/\([^/]*\)/releases/download/.*|\1/\2|')" "$asset_name" "${tmp}.${file_type}"
        then
            # API 下载失败,尝试直接下载
            if ! curl -fsSL "$download_url" -o "${tmp}.${file_type}"; then
                warn "$id: 下载失败"
                return 1
            fi
        fi
    else
        # 非 GitHub URL,直接下载
        if ! curl -fsSL -L "$download_url" -o "${tmp}.${file_type}"; then
            warn "$id: 下载失败"
            return 1
        fi
    fi

    mkdir -p "$install_dir"

    case "$file_type" in
        appimage)
            log "$id: 解压 AppImage"
            chmod +x "${tmp}.${file_type}"
            rm -rf /tmp/squashfs-root /tmp/AppDir
            ( cd /tmp && "${tmp}.${file_type}" --appimage-extract >/dev/null 2>&1 ) || {
                warn "$id: AppImage 解压失败"
                rm -f "${tmp}.${file_type}"
                return 1
            }
            local extracted
            extracted=$(readlink -f /tmp/squashfs-root)
            mv -f "$extracted"/* "$install_dir/" 2>/dev/null || mv -f "$extracted" "$install_dir/${id}"
            rm -rf /tmp/squashfs-root /tmp/AppDir
            ;;
        zip)
            log "$id: 解压 zip"
            if ! unzip -q "${tmp}.zip" -d "$install_dir"; then
                warn "$id: zip 解压失败"
                rm -f "${tmp}.zip"
                return 1
            fi
            # 如果 zip 里有单层目录,把内容提出来
            local files
            files=("$install_dir"/*)
            if [ "${#files[@]}" -eq 1 ] && [ -d "${files[0]}" ]; then
                mv "${files[0]}"/* "$install_dir/"
                rmdir "${files[0]}"
            fi
            ;;
        tar.gz)
            log "$id: 解压 tar.gz"
            if ! tar -xzf "${tmp}.tar.gz" -C "$install_dir"; then
                warn "$id: tar.gz 解压失败"
                rm -f "${tmp}.tar.gz"
                return 1
            fi
            # 同样处理单层目录
            local files
            files=("$install_dir"/*)
            if [ "${#files[@]}" -eq 1 ] && [ -d "${files[0]}" ]; then
                mv "${files[0]}"/* "$install_dir/"
                rmdir "${files[0]}"
            fi
            ;;
        *)
            warn "$id: 未知文件类型: $file_type"
            rm -f "${tmp}".*
            return 1
            ;;
    esac

    rm -f "${tmp}".*
}

# ── GitHub API 下载辅助函数 ───────────────────────────────────────────
# 直接访问 GitHub releases URL 可能返回 404,通过 API 下载更可靠
github_api_download() {
    local repo="$1"
    local asset_name="$2"
    local output="$3"

    log "通过 GitHub API 下载 $asset_name"

    # 获取 asset 的 API URL
    local asset_url
    asset_url=$(curl -fsSL "https://api.github.com/repos/${repo}/releases/latest" \
        | jq -r --arg name "$asset_name" '.assets[] | select(.name == $name) | .url')

    if [ -z "$asset_url" ]; then
        warn "未找到 asset: $asset_name"
        return 1
    fi

    # 使用 API 下载（需要 Accept: application/octet-stream header）
    if ! curl -fsSL -H "Accept: application/octet-stream" "$asset_url" -o "$output"; then
        warn "GitHub API 下载失败: $asset_name"
        return 1
    fi

    return 0
}

# ── 检测应用是否已装,跳过 ───────────────────────────────────────────
already_installed() {
    local install_method="$1" pkg="$2" bin="$3"
    # appimage, cursor_api, direct_download, r2_download 都检查二进制文件
    if [[ "$install_method" =~ ^(appimage|cursor_api|direct_download|r2_download)$ ]]; then
        [ -x "$bin" ]
    else
        dpkg -s "$pkg" >/dev/null 2>&1 && [ -x "$bin" ]
    fi
}

# ── 主循环 ──────────────────────────────────────────────────────────
shopt -s nullglob
for manifest in "$MANIFEST_DIR"/*.json; do
    id=$(jq -r '.id' "$manifest")
    pkg=$(jq -r '.package' "$manifest")
    bin=$(jq -r '.binary' "$manifest")
    install_method=$(jq -r '.install_method // "github_release"' "$manifest")

    if already_installed "$install_method" "$pkg" "$bin"; then
        log "$id: 已安装,跳过"
        continue
    fi

    case "$install_method" in
        apt)            preinstall_apt            "$id" "$manifest" || warn "$id: 预装失败,运行时按需安装可兜底" ;;
        github_release) preinstall_github_release "$id" "$manifest" || warn "$id: 预装失败,运行时按需安装可兜底" ;;
        appimage)       preinstall_appimage       "$id" "$manifest" || warn "$id: 预装失败,运行时按需安装可兜底" ;;
        cursor_api)     preinstall_cursor_api     "$id" "$manifest" || warn "$id: 预装失败,运行时按需安装可兜底" ;;
        direct_download) preinstall_direct_download "$id" "$manifest" || warn "$id: 预装失败,运行时按需安装可兜底" ;;
        *)              warn "$id: 未知 install_method=$install_method,跳过" ;;
    esac
done

log "完成,清理 apt 缓存"
apt-get clean
rm -rf /var/lib/apt/lists/*
