#!/usr/bin/env bash
# 一键热部署脚本 - 将本地脚本快速部署到运行中的容器
#
# 用法:
#   ./hot-deploy.sh [容器ID/名称] [选项]
#
# 选项:
#   --all               部署所有脚本（默认）
#   --hermes            仅部署 Hermes 相关脚本
#   --app-launcher      仅部署 webclaw-app-launcher
#   --startup           仅部署 startup.sh
#   --clean             清理安装状态
#   --verify            部署后验证
#   -h, --help          显示帮助信息
#
# 示例:
#   ./hot-deploy.sh webclaw-inst-xxx --all --clean --verify
#   ./hot-deploy.sh --hermes  # 使用默认容器
#   ./hot-deploy.sh webclaw-inst-xxx --app-launcher

set -euo pipefail

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 打印带颜色的消息
print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

print_success() {
    echo -e "${GREEN}✅${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}❌${NC} $1"
}

print_header() {
    echo ""
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC} $1"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# 显示帮助信息
show_help() {
    cat << EOF
一键热部署脚本 - 将本地脚本快速部署到运行中的容器

用法:
    $0 [容器ID/名称] [选项]

参数:
    容器ID/名称        可选，默认自动查找 webclaw-inst- 开头的容器

选项:
    --all               部署所有脚本（默认）
    --hermes            仅部署 Hermes 相关脚本
    --app-launcher      仅部署 webclaw-app-launcher
    --startup           仅部署 startup.sh
    --clean             清理安装状态
    --verify            部署后验证
    -h, --help          显示帮助信息

示例:
    $0 webclaw-inst-xxx --all --clean --verify
    $0 --hermes                                    # 使用默认容器
    $0 webclaw-inst-xxx --app-launcher             # 仅部署 app-launcher

EOF
}

# 查找默认容器
find_default_container() {
    local container
    container=$(docker ps --filter "name=webclaw-inst-" --format "{{.Names}}" | head -1)
    if [ -z "$container" ]; then
        print_error "未找到运行中的 webclaw-inst- 容器"
        print_info "请手动指定容器 ID 或名称"
        exit 1
    fi
    echo "$container"
}

# 验证容器是否运行
verify_container() {
    local container="$1"
    if ! docker inspect "$container" &>/dev/null; then
        print_error "容器不存在: $container"
        exit 1
    fi

    local status
    status=$(docker inspect -f '{{.State.Status}}' "$container")
    if [ "$status" != "running" ]; then
        print_error "容器未运行: $container (状态: $status)"
        exit 1
    fi

    print_success "容器验证通过: $container"
}

# 部署单个脚本（使用 docker cp 复制文件）
deploy_script() {
    local container="$1"
    local local_path="$2"
    local remote_path="$3"
    local description="$4"

    print_info "部署 $description..."

    # 构建完整的本地路径
    local full_local_path="${PROJECT_ROOT}/${local_path}"

    if [ ! -f "$full_local_path" ]; then
        print_error "本地文件不存在: $full_local_path"
        return 1
    fi

    # 使用 docker cp 复制文件到容器（模拟 Dockerfile COPY）
    if ! docker cp "$full_local_path" "${container}:${remote_path}" 2>/dev/null; then
        print_error "部署失败: $description"
        return 1
    fi

    # 确保脚本可执行
    docker exec "$container" chmod +x "$remote_path" 2>/dev/null

    print_success "部署成功: $description"
    return 0
}

# 清理 Hermes 安装状态
clean_hermes_state() {
    local container="$1"

    print_header "清理 Hermes 安装状态"

    print_info "终止卡住的安装进程..."
    docker exec "$container" bash -c '
        pkill -9 -f "install-hermes.sh" 2>/dev/null || true
        pkill -9 -f "setup-hermes.sh" 2>/dev/null || true
        pkill -9 zenity 2>/dev/null || true
    ' >/dev/null 2>&1 || true

    print_info "清理安装状态文件..."
    docker exec "$container" bash -c '
        rm -f /opt/hermes-agent/.install_done 2>/dev/null || true
        rm -f /tmp/hermes-install-progress 2>/dev/null || true
        > /tmp/hermes-install.log
        > /tmp/webclaw-ondemand-hermes.log
    ' >/dev/null 2>&1 || true

    print_info "重置桌面图标..."
    docker exec "$container" bash -c '
        cat > /home/ubuntu/Desktop/hermes.desktop << "EOF"
[Desktop Entry]
Version=1.0
Type=Application
Name=Hermes Agent
Name[zh_CN]=Hermes 智能体
Comment=自进化 AI 代理
Comment[zh_CN]=具有学习能力的自进化 AI 代理
Exec=/usr/local/bin/webclaw-app-launcher hermes
Icon=/opt/on-demand-icons/hermes.png
Terminal=false
Categories=Application;Network;
EOF
        chmod +x /home/ubuntu/Desktop/hermes.desktop
        chown ubuntu:ubuntu /home/ubuntu/Desktop/hermes.desktop
    ' >/dev/null 2>&1 || true

    print_success "清理完成"
}

# 验证部署结果
verify_deployment() {
    local container="$1"

    print_header "验证部署结果"

    local all_ok=true

    # 检查 install-hermes.sh
    echo "1️⃣  检查 install-hermes.sh:"
    if docker exec "$container" bash -c '[ -x /opt/install-hermes.sh ]'; then
        print_success "可执行"
        if docker exec "$container" bash -c 'grep -q "WEBCLAW_APP_LAUNCHER" /opt/install-hermes.sh'; then
            print_success "包含环境变量检测"
        else
            print_warning "缺少环境变量检测"
            all_ok=false
        fi
    else
        print_error "不存在或不可执行"
        all_ok=false
    fi

    # 检查 webclaw-app-launcher
    echo ""
    echo "2️⃣  检查 webclaw-app-launcher:"
    if docker exec "$container" bash -c '[ -x /usr/local/bin/webclaw-app-launcher ]'; then
        print_success "可执行"
        if docker exec "$container" bash -c 'grep -q "DISABLE_ZENITY=1" /usr/local/bin/webclaw-app-launcher'; then
            print_success "包含进度反馈改进"
        else
            print_warning "缺少进度反馈改进"
            all_ok=false
        fi
    else
        print_error "不存在或不可执行"
        all_ok=false
    fi

    # 检查 hermes.json
    echo ""
    echo "3️⃣  检查 hermes.json:"
    if docker exec "$container" bash -c '[ -f /opt/on-demand-apps/hermes.json ]'; then
        print_success "存在"
    else
        print_error "不存在"
        all_ok=false
    fi

    # 检查桌面图标
    echo ""
    echo "4️⃣  检查桌面图标:"
    if docker exec "$container" bash -c '[ -f /home/ubuntu/Desktop/hermes.desktop ]'; then
        print_success "存在"
    else
        print_error "不存在"
        all_ok=false
    fi

    echo ""
    if [ "$all_ok" = true ]; then
        print_success "所有验证通过！"
        return 0
    else
        print_warning "部分验证未通过，请检查"
        return 1
    fi
}

# 主函数
main() {
    local container=""
    local deploy_all=true
    local deploy_hermes=false
    local deploy_app_launcher=false
    local deploy_startup=false
    local clean_state=false
    local verify_after=false

    # 解析参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            --all)
                deploy_all=true
                shift
                ;;
            --hermes)
                deploy_all=false
                deploy_hermes=true
                shift
                ;;
            --app-launcher)
                deploy_all=false
                deploy_app_launcher=true
                shift
                ;;
            --startup)
                deploy_all=false
                deploy_startup=true
                shift
                ;;
            --clean)
                clean_state=true
                shift
                ;;
            --verify)
                verify_after=true
                shift
                ;;
            -*)
                print_error "未知选项: $1"
                show_help
                exit 1
                ;;
            *)
                container="$1"
                shift
                ;;
        esac
    done

    # 查找容器
    if [ -z "$container" ]; then
        container=$(find_default_container)
        print_info "使用默认容器: $container"
    fi

    # 验证容器
    verify_container "$container"

    # 部署脚本
    print_header "开始热部署"

    local deploy_count=0
    local deploy_failed=0

    # 确保在项目根目录执行
    cd "$PROJECT_ROOT"

    if [ "$deploy_all" = true ] || [ "$deploy_hermes" = true ]; then
        if deploy_script "$container" \
            "scripts/install-hermes.sh" \
            "/opt/install-hermes.sh" \
            "install-hermes.sh"; then
            deploy_count=$((deploy_count + 1))
        else
            deploy_failed=$((deploy_failed + 1))
        fi

        # 部署 Hermes 配置文件
        print_info "部署 Hermes 配置文件..."
        if [ -f "${PROJECT_ROOT}/configs/on-demand-apps/hermes.json" ]; then
            docker cp "${PROJECT_ROOT}/configs/on-demand-apps/hermes.json" \
                "${container}:/opt/on-demand-apps/hermes.json" 2>/dev/null || true
            docker exec "$container" bash -c "chown ubuntu:ubuntu /opt/on-demand-apps/hermes.json" 2>/dev/null || true
            print_success "配置文件已部署"
        else
            print_warning "本地配置文件不存在"
        fi

        # 部署 Hermes sudoers 配置
        print_info "部署 Hermes sudoers 配置..."
        if [ -f "${PROJECT_ROOT}/configs/sudoers/webclaw-app-launcher" ]; then
            # 先复制到临时位置（避免直接写入 /etc/sudoers.d/ 导致权限问题）
            docker cp "${PROJECT_ROOT}/configs/sudoers/webclaw-app-launcher" \
                "${container}:/tmp/webclaw-app-launcher.sudoers" 2>/dev/null || true

            # 使用 root 权限移动到目标位置并设置正确的权限
            docker exec "$container" bash -c "
                # 验证临时文件内容
                if [ -f /tmp/webclaw-app-launcher.sudoers ]; then
                    # 使用 visudo 语法检查
                    visudo -c -f /tmp/webclaw-app-launcher.sudoers >/dev/null 2>&1 || exit 1

                    # 删除旧文件（如果存在）
                    rm -f /etc/sudoers.d/webclaw-app-launcher 2>/dev/null || true

                    # 移动到目标位置（需要 root 权限，通过现有 sudo 配置或容器 root 用户）
                    if [ -w /etc/sudoers.d/ ]; then
                        # 直接复制（如果当前是 root 或有写权限）
                        cp /tmp/webclaw-app-launcher.sudoers /etc/sudoers.d/webclaw-app-launcher
                        chmod 0440 /etc/sudoers.d/webclaw-app-launcher
                        chown root:root /etc/sudoers.d/webclaw-app-launcher 2>/dev/null || true
                    else
                        # 尝试通过 sudo
                        if sudo -n true 2>/dev/null; then
                            sudo cp /tmp/webclaw-app-launcher.sudoers /etc/sudoers.d/webclaw-app-launcher
                            sudo chmod 0440 /etc/sudoers.d/webclaw-app-launcher
                            sudo chown root:root /etc/sudoers.d/webclaw-app-launcher
                        else
                            # 最后尝试：从宿主机直接操作
                            exit 1
                        fi
                    fi

                    # 清理临时文件
                    rm -f /tmp/webclaw-app-launcher.sudoers
                    exit 0
                else
                    exit 1
                fi
            " 2>/dev/null

            if [ $? -eq 0 ]; then
                print_success "sudoers 配置已部署"
            else
                # 如果容器内操作失败，从宿主机直接操作（通过 docker exec 以 root 用户）
                docker exec "$container" bash -c "cat > /etc/sudoers.d/webclaw-app-launcher" < "${PROJECT_ROOT}/configs/sudoers/webclaw-app-launcher" 2>/dev/null || true
                docker exec "$container" bash -c "chmod 0440 /etc/sudoers.d/webclaw-app-launcher && chown root:root /etc/sudoers.d/webclaw-app-launcher" 2>/dev/null || true

                # 验证部署
                if docker exec "$container" bash -c "[ -f /etc/sudoers.d/webclaw-app-launcher ] && [ \$(stat -c %U:%G /etc/sudoers.d/webclaw-app-launcher 2>/dev/null || stat -f %Su:%Sg /etc/sudoers.d/webclaw-app-launcher) = 'root:root' ] && [ \$(stat -c %a /etc/sudoers.d/webclaw-app-launcher 2>/dev/null || stat -f %Op /etc/sudoers.d/webclaw-app-launcher | sed 's/.*\(....\)/\1/') = '0440' ]" 2>/dev/null; then
                    print_success "sudoers 配置已部署"
                else
                    print_warning "sudoers 配置可能未正确部署（权限问题）"
                fi
            fi
        else
            print_warning "本地 sudoers 配置不存在"
        fi

        # 部署 Hermes 卸载脚本
        print_info "部署 Hermes 卸载脚本..."
        if [ -f "${PROJECT_ROOT}/scripts/uninstall-hermes.sh" ]; then
            docker cp "${PROJECT_ROOT}/scripts/uninstall-hermes.sh" \
                "${container}:/opt/uninstall-hermes.sh" 2>/dev/null || true
            docker exec "$container" chmod +x /opt/uninstall-hermes.sh 2>/dev/null || true
            print_success "卸载脚本已部署"
        fi

        # 部署桌面公共文件（desktop-shortcuts 和 desktop-icons）
        print_info "部署桌面公共文件..."

        # desktop-icons
        if [ -d "${PROJECT_ROOT}/configs/desktop-icons" ]; then
            docker exec "$container" mkdir -p /opt/desktop-icons 2>/dev/null || true
            docker cp "${PROJECT_ROOT}/configs/desktop-icons/"*.png \
                "${container}:/opt/desktop-icons/" 2>/dev/null || true
        fi

        # desktop-shortcuts
        if [ -d "${PROJECT_ROOT}/configs/desktop-shortcuts" ]; then
            docker exec "$container" mkdir -p /opt/desktop-shortcuts 2>/dev/null || true
            docker cp "${PROJECT_ROOT}/configs/desktop-shortcuts/"*.desktop \
                "${container}:/opt/desktop-shortcuts/" 2>/dev/null || true
            docker exec "$container" chmod +x /opt/desktop-shortcuts/*.desktop 2>/dev/null || true
        fi

        print_success "桌面公共文件已部署"

        # 部署 Hermes 图标文件
        print_info "部署 Hermes 图标文件..."
        if [ -f "${PROJECT_ROOT}/configs/desktop-icons/hermes.png" ]; then
            docker cp "${PROJECT_ROOT}/configs/desktop-icons/hermes.png" \
                "${container}:/opt/desktop-icons/hermes.png" 2>/dev/null || true
            docker cp "${PROJECT_ROOT}/configs/desktop-icons/hermes.png" \
                "${container}:/opt/on-demand-icons/hermes.png" 2>/dev/null || true
            print_success "图标文件已部署"
        else
            print_warning "本地图标文件不存在"
        fi
    fi

    if [ "$deploy_all" = true ] || [ "$deploy_app_launcher" = true ]; then
        if deploy_script "$container" \
            "scripts/webclaw-app-launcher.sh" \
            "/usr/local/bin/webclaw-app-launcher" \
            "webclaw-app-launcher.sh"; then
            deploy_count=$((deploy_count + 1))
        else
            deploy_failed=$((deploy_failed + 1))
        fi

        # 同时部署 update-desktop-icons.sh
        if deploy_script "$container" \
            "scripts/update-desktop-icons.sh" \
            "/usr/local/bin/update-desktop-icons" \
            "update-desktop-icons.sh"; then
            deploy_count=$((deploy_count + 1))
        else
            deploy_failed=$((deploy_failed + 1))
        fi
    fi

    if [ "$deploy_all" = true ] || [ "$deploy_startup" = true ]; then
        if deploy_script "$container" \
            "scripts/startup.sh" \
            "/opt/startup.sh" \
            "startup.sh"; then
            deploy_count=$((deploy_count + 1))
        else
            deploy_failed=$((deploy_failed + 1))
        fi
    fi

    # 清理安装状态
    if [ "$clean_state" = true ]; then
        clean_hermes_state "$container"
    fi

    # 验证部署
    if [ "$verify_after" = true ]; then
        verify_deployment "$container"
    fi

    # 更新桌面图标状态（添加下载箭头等）
    print_info "更新桌面图标状态..."
    if docker exec "$container" bash -c "[ -x /usr/local/bin/update-desktop-icons ]"; then
        docker exec "$container" /usr/local/bin/update-desktop-icons >/dev/null 2>&1 || true
        print_success "桌面图标已更新"
    fi

    # 显示总结
    print_header "部署总结"
    echo "✅ 成功部署: $deploy_count 个脚本"
    if [ $deploy_failed -gt 0 ]; then
        echo "❌ 部署失败: $deploy_failed 个脚本"
    fi
    echo "📦 容器: $container"

    if [ $deploy_failed -eq 0 ]; then
        print_success "热部署完成！"
        exit 0
    else
        print_error "部分部署失败"
        exit 1
    fi
}

# 获取脚本所在目录的父目录（项目根目录）
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# 运行主函数
main "$@"
