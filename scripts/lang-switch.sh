#!/bin/bash
# GNOME Flashback desktop language switch script
export DISPLAY=:1
export XDG_RUNTIME_DIR=/run/user/1000

# Language preference file (persists across container restarts)
LANG_FILE="/home/ubuntu/.config/gnome-language"
mkdir -p "$(dirname "$LANG_FILE")"

case "$1" in
    zh|zh_CN|chinese|中文)
        # Switch to Chinese
        echo "zh_CN.UTF-8" > "$LANG_FILE"
        export LANG=zh_CN.UTF-8
        export LC_ALL=zh_CN.UTF-8
        export LANGUAGE=zh_CN:zh
        # Update gsettings for new applications
        gsettings set org.gnome.system.locale locale "zh_CN.UTF-8" 2>/dev/null
        echo "已切换到中文 (zh_CN.UTF-8)"
        echo "请重启应用程序以使更改生效。"
        ;;
    en|en_US|english)
        # Switch to English
        echo "en_US.UTF-8" > "$LANG_FILE"
        export LANG=en_US.UTF-8
        export LC_ALL=en_US.UTF-8
        export LANGUAGE=en_US:en
        # Update gsettings for new applications
        gsettings set org.gnome.system.locale locale "en_US.UTF-8" 2>/dev/null
        echo "已切换到英文 (en_US.UTF-8)"
        echo "Please restart applications for changes to take effect."
        ;;
    *)
        echo "用法: lang-switch {zh|en}"
        echo "  zh    - 切换到中文 (Switch to Chinese)"
        echo "  en    - 切换到英文 (Switch to English)"
        exit 1
        ;;
esac
