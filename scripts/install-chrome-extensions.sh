#!/bin/bash
#
# Chrome 扩展自动安装脚本
#
# 用法:
#   ./install-chrome-extensions.sh <extension_id> [extension_id...]
#   ./install-chrome-extensions.sh nglingapjinhecnfejdcpihlpneeadjp
#   ./install-chrome-extensions.sh ext1 ext2 ext3
#
# 从 Chrome Web Store URL 中提取扩展 ID:
#   https://chromewebstore.google.com/detail/XXXXX
#                                         ↑ 扩展 ID
#
# 容器名称 (可通过环境变量覆盖)
CONTAINER_NAME="${CONTAINER_NAME:-webcode}"

# 临时工作目录
TEMP_DIR="$(pwd)/.chrome-ext-temp"
EXT_DIR="$(pwd)/.chrome-extensions"

# Chrome 版本 (用于 CRX 下载 URL)
CHROME_VERSION="134.0.6998.118"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ─── 打印消息 ─────────────────────────────────────────────────────────────
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# ─── 检查容器是否运行 ─────────────────────────────────────────────────────
check_container() {
    if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        log_error "容器 '${CONTAINER_NAME}' 未运行"
        log_info "请先启动容器: docker compose up -d"
        exit 1
    fi
    log_success "容器 '${CONTAINER_NAME}' 正在运行"
}

# ─── 检查必需命令 ─────────────────────────────────────────────────────────
check_dependencies() {
    local missing=()

    for cmd in curl unzip docker; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        log_error "缺少必需的命令: ${missing[*]}"
        log_info "请安装后重试"
        exit 1
    fi
}

# ─── 下载并解压单个扩展 ───────────────────────────────────────────────────
download_extension() {
    local ext_id="$1"
    local crx_url="https://clients2.google.com/service/update2/crx?response=redirect&prodversion=${CHROME_VERSION}&x=${ext_id}"
    local crx_file="${TEMP_DIR}/${ext_id}.crx"
    local extract_dir="${EXT_DIR}/${ext_id}"

    log_info "正在下载扩展: ${ext_id}"

    # 下载 CRX 文件
    if ! curl -fsSL -o "$crx_file" "$crx_url"; then
        log_error "下载失败: ${ext_id}"
        return 1
    fi

    # 检查文件是否为有效的 ZIP/CRX 文件
    if ! file "$crx_file" | grep -qE "(Zip|ZIP)"; then
        log_error "下载的文件格式不正确: ${ext_id}"
        rm -f "$crx_file"
        return 1
    fi

    log_info "解压扩展文件..."

    # 创建解压目录
    mkdir -p "$extract_dir"

    # 解压 CRX 文件 (跳过 CRX 头部的前几字节)
    # 方法 1: 直接解压 (Chrome 的新 CRX 格式就是标准 ZIP)
    if ! unzip -q -o "$crx_file" -d "$extract_dir" 2>/dev/null; then
        # 方法 2: 跳过 CRX v3 文件头 (前 8-16 字节)
        if ! tail -c +9 "$crx_file" | unzip -q -o -d "$extract_dir" 2>/dev/null; then
            log_error "解压失败: ${ext_id}"
            rm -rf "$extract_dir" "$crx_file"
            return 1
        fi
    fi

    # 清理 CRX 文件
    rm -f "$crx_file"

    # 验证 manifest.json 存在
    if [ ! -f "${extract_dir}/manifest.json" ]; then
        log_error "扩展缺少 manifest.json: ${ext_id}"
        rm -rf "$extract_dir"
        return 1
    fi

    log_success "扩展下载并解压成功: ${ext_id}"
    return 0
}

# ─── 复制扩展到容器 ───────────────────────────────────────────────────────
copy_to_container() {
    local ext_id="$1"

    log_info "复制扩展到容器: ${ext_id}"

    if ! docker cp "${EXT_DIR}/${ext_id}" "${CONTAINER_NAME}:/home/ubuntu/extensions/"; then
        log_error "复制失败: ${ext_id}"
        return 1
    fi

    # 修复权限
    docker exec "${CONTAINER_NAME}" chown -R ubuntu:ubuntu "/home/ubuntu/extensions/${ext_id}"

    log_success "扩展已复制到容器: ${ext_id}"
    return 0
}

# ─── 配置 Chrome 自动加载 ─────────────────────────────────────────────────
configure_chrome_flags() {
    log_info "配置 Chrome 启动参数..."

    # 收集所有已安装的扩展 ID
    local ext_list=()
    if [ -d "$EXT_DIR" ]; then
        for ext_dir in "${EXT_DIR}"/*; do
            if [ -d "$ext_dir" ]; then
                ext_list+=("$(basename "$ext_dir")")
            fi
        done
    fi

    if [ ${#ext_list[@]} -eq 0 ]; then
        log_warn "没有找到已安装的扩展"
        return 1
    fi

    # 构建扩展路径列表 (逗号分隔)
    local ext_paths=""
    for ext_id in "${ext_list[@]}"; do
        ext_paths="${ext_paths}/home/ubuntu/extensions/${ext_id},"
    done
    ext_paths="${ext_paths%,}"  # 移除末尾的逗号

    # 更新 Chrome 配置文件
    docker exec "${CONTAINER_NAME}" bash -c "
        mkdir -p /home/ubuntu/.config
        echo '--load-extension=${ext_paths}' > /home/ubuntu/.config/chrome-flags.conf
        chown ubuntu:ubuntu /home/ubuntu/.config/chrome-flags.conf
    "

    log_success "Chrome 已配置为加载 ${#ext_list[@]} 个扩展:"
    for ext_id in "${ext_list[@]}"; do
        echo "  - ${ext_id}"
    done
}

# ─── 清理临时文件 ─────────────────────────────────────────────────────────
cleanup() {
    log_info "清理临时文件..."
    rm -rf "$TEMP_DIR"
    log_success "清理完成"
}

# ─── 显示使用帮助 ─────────────────────────────────────────────────────────
show_help() {
    cat << EOF
Chrome 扩展自动安装脚本

用法:
  $0 <extension_id> [extension_id...]

参数:
  extension_id    Chrome 扩展 ID (从 Web Store URL 中提取)

示例:
  # 安装单个扩展
  $0 nglingapjinhecnfejdcpihlpneeadjp

  # 安装多个扩展
  $0 ext1 ext2 ext3

环境变量:
  CONTAINER_NAME    Docker 容器名称 (默认: webcode)

如何获取扩展 ID:
  Chrome Web Store URL 格式:
  https://chromewebstore.google.com/detail/XXXXX
                                         ↑ 扩展 ID

注意:
  - 扩展将在容器重启后生效
  - 多次运行此脚本会累积添加扩展
  - 使用 docker compose restart 重启容器

EOF
}

# ─── 主函数 ───────────────────────────────────────────────────────────────
main() {
    # 检查参数
    if [ "$1" = "-h" ] || [ "$1" = "--help" ] || [ $# -eq 0 ]; then
        show_help
        exit 0
    fi

    # 解析参数
    local extension_ids=("$@")

    log_info "开始安装 Chrome 扩展..."
    log_info "容器名称: ${CONTAINER_NAME}"
    log_info "扩展数量: ${#extension_ids[@]}"

    # 检查依赖和容器
    check_dependencies
    check_container

    # 创建工作目录
    mkdir -p "$TEMP_DIR"
    mkdir -p "$EXT_DIR"

    # 处理每个扩展
    local success_count=0
    local failed_ids=()

    for ext_id in "${extension_ids[@]}"; do
        # 验证扩展 ID 格式 (32 个字符的字母数字字符串)
        if ! echo "$ext_id" | grep -qE '^[a-z]{32}$'; then
            log_warn "跳过无效的扩展 ID: ${ext_id}"
            failed_ids+=("$ext_id")
            continue
        fi

        # 下载并解压
        if download_extension "$ext_id"; then
            # 复制到容器
            if copy_to_container "$ext_id"; then
                ((success_count++))
            else
                failed_ids+=("$ext_id")
            fi
        else
            failed_ids+=("$ext_id")
        fi
    done

    # 配置 Chrome 加载所有扩展
    configure_chrome_flags

    # 清理临时文件
    cleanup

    # 显示结果摘要
    echo ""
    echo "═══════════════════════════════════════════════════════════"
    log_info "安装完成: ${success_count}/${#extension_ids[@]} 成功"

    if [ ${#failed_ids[@]} -gt 0 ]; then
        log_warn "失败的扩展:"
        for ext_id in "${failed_ids[@]}"; do
            echo "  - ${ext_id}"
        done
    fi

    if [ $success_count -gt 0 ]; then
        echo ""
        log_info "重启容器使扩展生效:"
        echo "  docker compose restart"
        echo ""
        log_info "或者重启 Chrome 进程:"
        echo "  docker exec -it ${CONTAINER_NAME} pkill chrome"
    fi
    echo "═══════════════════════════════════════════════════════════"
}

# ─── 执行主函数 ───────────────────────────────────────────────────────────
main "$@"
