#!/bin/bash
# Theme switch for GNOME Flashback desktop
export DISPLAY=:1
export XDG_RUNTIME_DIR=/run/user/1000

# Save theme preference for next session
THEME_FILE="/home/ubuntu/.config/gnome-initial-theme"
mkdir -p "$(dirname "$THEME_FILE")"

# Light mode wallpapers (bright, cheerful scenes)
LIGHT_WALLPAPERS=(
    "/usr/share/backgrounds/Fuji_san_by_amaral.png"
    "/usr/share/backgrounds/Fuwafuwa_nanbatto_san_by_amaral-light.png"
    "/usr/share/backgrounds/Numbat_wallpaper_light_3480x2160.png"
    "/usr/share/backgrounds/Clouds_by_Tibor_Mokanszki.jpg"
)

# Dark mode wallpapers (dark, atmospheric scenes)
DARK_WALLPAPERS=(
    "/usr/share/backgrounds/Numbat_wallpaper_dimmed_3480x2160.png"
    "/usr/share/backgrounds/Fuwafuwa_nanbatto_san_by_amaral-dark.png"
    "/usr/share/backgrounds/Province_of_the_south_of_france_by_orbitelambda.jpg"
    "/usr/share/backgrounds/Monument_valley_by_orbitelambda.jpg"
    "/usr/share/backgrounds/Northan_lights_by_mizuno.webp"
)

# Random wallpaper selector
get_random_wallpaper() {
    local wallpapers=("$@")
    local count=${#wallpapers[@]}
    local index=$((RANDOM % count))
    echo "${wallpapers[$index]}"
}

# 设置壁纸：gnome-flashback 在跑就走 gsettings（它接管根窗口后 hsetroot 失效），
# 否则回退 hsetroot 直绘根窗口。
set_wallpaper() {
    local wp="$1"
    if pgrep -x gnome-flashback >/dev/null 2>&1; then
        gsettings set org.gnome.desktop.background picture-uri "file://$wp" 2>/dev/null || true
        gsettings set org.gnome.desktop.background picture-uri-dark "file://$wp" 2>/dev/null || true
    else
        hsetroot -cover "$wp" 2>/dev/null || true
    fi
}

case "$1" in
    light|bright)
        WALLPAPER=$(get_random_wallpaper "${LIGHT_WALLPAPERS[@]}")
        set_wallpaper "$WALLPAPER"
        gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita' 2>/dev/null
        gsettings set org.gnome.desktop.wm.preferences theme 'Adwaita' 2>/dev/null
        gsettings set org.gnome.gnome-panel.general theme-variant 'light' 2>/dev/null
        echo "light" > "$THEME_FILE"
        # Restart panel to apply theme immediately
        export XDG_MENU_PREFIX=gnome-flashback-
        killall gnome-panel 2>/dev/null
        sleep 0.2
        env GTK_THEME=Adwaita gnome-panel --replace >/dev/null 2>&1 &
        basename "$WALLPAPER"
        ;;
    dark)
        WALLPAPER=$(get_random_wallpaper "${DARK_WALLPAPERS[@]}")
        set_wallpaper "$WALLPAPER"
        gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita-dark' 2>/dev/null
        gsettings set org.gnome.desktop.wm.preferences theme 'Adwaita-dark' 2>/dev/null
        gsettings set org.gnome.gnome-panel.general theme-variant 'dark' 2>/dev/null
        echo "dark" > "$THEME_FILE"
        # Restart panel to apply theme immediately
        export XDG_MENU_PREFIX=gnome-flashback-
        killall gnome-panel 2>/dev/null
        sleep 0.2
        env GTK_THEME=Adwaita-dark gnome-panel --replace >/dev/null 2>&1 &
        basename "$WALLPAPER"
        ;;
    *)
        echo "Usage: theme-switch {light|dark}"
        exit 1
        ;;
esac
