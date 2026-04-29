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
    url="https://github.com/${repo}/releases/download/v${version}/${asset}"

    extract_dir="/opt/ondemand-apps/${id}"
    tmp="/tmp/preinstall-${id}.AppImage"

    log "$id: 下载 $url"
    rm -f "$tmp"
    rm -rf "$extract_dir"
    mkdir -p "$extract_dir"
    if ! curl -fsSL "$url" -o "$tmp"; then
        warn "$id: 下载失败"
        return 1
    fi
    chmod +x "$tmp"

    log "$id: 解压 AppImage"
    rm -rf /tmp/squashfs-root /tmp/AppDir
    ( cd /tmp && "$tmp" --appimage-extract >/dev/null ) || {
        warn "$id: --appimage-extract 失败"
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

# ── 检测应用是否已装,跳过 ───────────────────────────────────────────
already_installed() {
    local install_method="$1" pkg="$2" bin="$3"
    if [ "$install_method" = "appimage" ]; then
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
        *)              warn "$id: 未知 install_method=$install_method,跳过" ;;
    esac
done

log "完成,清理 apt 缓存"
apt-get clean
rm -rf /var/lib/apt/lists/*
