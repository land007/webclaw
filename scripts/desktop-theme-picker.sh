#!/bin/bash
# Desktop theme picker with zenity menu
export DISPLAY=:1
export XDG_RUNTIME_DIR=/run/user/1000

THEME_FILE="/home/ubuntu/.config/gnome-initial-theme"
CURRENT_THEME="dark"
[ -f "$THEME_FILE" ] && CURRENT_THEME=$(cat "$THEME_FILE")

CHOICE=$(zenity --list --title="Appearance / 外观" \
    --text="Select theme / 选择主题" \
    --radiolist --column="" --column="Theme" \
    "$( [ "$CURRENT_THEME" = "light" ] && echo TRUE || echo FALSE )" "Light Mode / 浅色模式" \
    "$( [ "$CURRENT_THEME" = "dark" ] && echo TRUE || echo FALSE )" "Dark Mode / 深色模式" \
    --width=300 --height=200)

if [ $? -eq 0 ]; then
    case "$CHOICE" in
        "Light Mode / 浅色模式") /usr/local/bin/theme-switch light ;;
        "Dark Mode / 深色模式") /usr/local/bin/theme-switch dark ;;
    esac
fi
