#!/bin/bash
# GNOME Flashback desktop language switch script
export DISPLAY=:1
export XDG_RUNTIME_DIR=/run/user/1000

if [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1; then
    if sudo -n /usr/local/bin/lang-switch "$@" 2>/dev/null; then
        exit 0
    fi
fi

# 保存语言偏好到 ubuntu 用户的 home 目录
LANG_FILE="/home/ubuntu/.config/gnome-language"
mkdir -p "$(dirname "$LANG_FILE")"

set_locale_key() {
    local file="$1"
    local key="$2"
    local value="$3"

    if [ "$(id -u)" -ne 0 ]; then
        return 0
    fi

    touch "$file"
    if grep -q "^${key}=" "$file" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${value}|" "$file"
    else
        echo "${key}=${value}" >> "$file"
    fi
}

apply_locale() {
    local lang="$1"
    local language="$2"

    set_locale_key /etc/environment LANG "$lang"
    set_locale_key /etc/environment LANGUAGE "$language"
    set_locale_key /etc/environment LC_ALL "$lang"

    set_locale_key /etc/default/locale LANG "$lang"
    set_locale_key /etc/default/locale LANGUAGE "$language"
    set_locale_key /etc/default/locale LC_ALL "$lang"

    if [ "$(id -u)" -eq 0 ]; then
        update-locale LANG="$lang" LC_ALL="$lang" LANGUAGE="$language" 2>/dev/null || true
    fi
}

set_gnome_locale() {
    local lang="$1"

    if [ "$(id -u)" -eq 0 ]; then
        sudo -u ubuntu DISPLAY="$DISPLAY" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
            gsettings set org.gnome.system.locale locale "$lang" 2>/dev/null || true
    else
        gsettings set org.gnome.system.locale locale "$lang" 2>/dev/null || true
    fi
}

case "$1" in
    zh|zh_CN|chinese|中文)
        # 保存语言偏好
        echo "zh_CN.UTF-8" > "$LANG_FILE"
        if [ "$(id -u)" -eq 0 ]; then
            chown ubuntu:ubuntu "$LANG_FILE"
        fi

        apply_locale "zh_CN.UTF-8" "zh_CN:zh"
        set_gnome_locale "zh_CN.UTF-8"

        echo "已切换到中文 (zh_CN.UTF-8)"
        echo "正在重启桌面..."
        ;;
    en|en_US|english)
        # 保存语言偏好
        echo "en_US.UTF-8" > "$LANG_FILE"
        if [ "$(id -u)" -eq 0 ]; then
            chown ubuntu:ubuntu "$LANG_FILE"
        fi

        apply_locale "en_US.UTF-8" "en_US:en"
        set_gnome_locale "en_US.UTF-8"

        echo "已切换到英文 (en_US.UTF-8)"
        echo "Restarting desktop..."
        ;;
    *)
        echo "用法: lang-switch {zh|en}"
        echo "  zh    - 切换到中文 (Switch to Chinese)"
        echo "  en    - 切换到英文 (Switch to English)"
        exit 1
        ;;
esac

# 重启 supervisor 的 desktop 进程以应用新语言
if command -v supervisorctl >/dev/null 2>&1; then
    supervisorctl restart desktop >/dev/null 2>&1 &
fi
