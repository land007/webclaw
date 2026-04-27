#!/bin/bash
# Desktop language picker with zenity menu
export DISPLAY=:1
export XDG_RUNTIME_DIR=/run/user/1000

LANG_FILE="/home/ubuntu/.config/gnome-language"
CURRENT_LANG="zh_CN.UTF-8"
[ -f "$LANG_FILE" ] && CURRENT_LANG=$(cat "$LANG_FILE")

CHOICE=$(zenity --list --title="Language / 语言" \
    --text="Select language / 选择语言" \
    --radiolist --column="" --column="Language" \
    "$( [ "$CURRENT_LANG" = "zh_CN.UTF-8" ] && echo TRUE || echo FALSE )" "中文 Chinese" \
    "$( [ "$CURRENT_LANG" = "en_US.UTF-8" ] && echo TRUE || echo FALSE )" "English 英文" \
    --width=300 --height=200)

if [ $? -eq 0 ]; then
    case "$CHOICE" in
        "中文 Chinese")
            /usr/local/bin/lang-switch zh
            ;;
        "English 英文")
            /usr/local/bin/lang-switch en
            ;;
    esac
fi
