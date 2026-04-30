#!/bin/bash
# Root-side post-install hook for webclaw-app-launcher.
# 用法: sudo webclaw-app-postinstall <app_id>
#
# 用 root-side 硬编码动作的方式做安装后处置（建组、加用户、setcap 等），
# 避免在 sudoers 里写带 = 号的 setcap 参数（sudo 会把 = 当 env 赋值导致匹配失败）。
# 添加新应用的 post-install 钩子时，仅在下方 case 中加一段，sudoers 不需要改。

set -u

APP_ID="${1:-}"

if [[ ! "$APP_ID" =~ ^[a-zA-Z0-9._-]+$ ]]; then
    echo "Invalid app id: $APP_ID" >&2
    exit 1
fi

case "$APP_ID" in
    wireshark)
        # wireshark-common 包安装时本应通过 dpkg-reconfigure 自动创建 wireshark 组并
        # setcap dumpcap；但 apt -y 在容器环境下 debconf 时序不稳定，常常没生效。
        # 这里幂等地补做一次（groupadd -f / usermod -a / setcap 都可重复执行）。
        groupadd -f wireshark
        usermod -a -G wireshark ubuntu
        setcap cap_net_raw,cap_net_admin=ep /usr/bin/dumpcap
        ;;
    *)
        # 没有钩子的应用直接成功返回（避免 launcher 误判失败）
        exit 0
        ;;
esac

exit 0
