#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BACKGROUND_DIR="${PROJECT_ROOT}/configs/backgrounds"
BACKGROUND_XML="${BACKGROUND_DIR}/webclaw-backgrounds.xml"

usage() {
    cat <<EOF
Usage: $0 <container-name-or-id> [wallpaper-filename]

Examples:
  $0 webclaw-inst-xxx
  $0 webclaw-inst-xxx webclaw-starry-mountain.jpg
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ] || [ $# -lt 1 ]; then
    usage
    exit 0
fi

CONTAINER="$1"
SELECTED_WALLPAPER="${2:-}"
TMP_DIR="/tmp/webclaw-backgrounds-deploy"

if ! docker inspect "$CONTAINER" >/dev/null 2>&1; then
    echo "Container not found: $CONTAINER" >&2
    exit 1
fi

if [ "$(docker inspect -f '{{.State.Status}}' "$CONTAINER")" != "running" ]; then
    echo "Container is not running: $CONTAINER" >&2
    exit 1
fi

WALLPAPERS=()
while IFS= read -r wallpaper; do
    WALLPAPERS+=("$wallpaper")
done < <(sed -n 's|.*<filename>/usr/share/backgrounds/webclaw/\([^<]*\)</filename>.*|\1|p' "$BACKGROUND_XML")

if [ "${#WALLPAPERS[@]}" -eq 0 ]; then
    echo "No wallpaper entries found in $BACKGROUND_XML" >&2
    exit 1
fi

for wallpaper in "${WALLPAPERS[@]}"; do
    if [ ! -f "${BACKGROUND_DIR}/${wallpaper}" ]; then
        echo "Missing wallpaper file referenced by XML: ${BACKGROUND_DIR}/${wallpaper}" >&2
        exit 1
    fi
done

if [ -n "$SELECTED_WALLPAPER" ]; then
    found=false
    for wallpaper in "${WALLPAPERS[@]}"; do
        if [ "$wallpaper" = "$SELECTED_WALLPAPER" ]; then
            found=true
            break
        fi
    done
    if [ "$found" != true ]; then
        echo "Selected wallpaper is not in the XML list: $SELECTED_WALLPAPER" >&2
        exit 1
    fi
fi

docker exec "$CONTAINER" rm -rf "$TMP_DIR"
docker exec "$CONTAINER" mkdir -p "$TMP_DIR"
docker cp "$BACKGROUND_XML" "${CONTAINER}:${TMP_DIR}/webclaw-backgrounds.xml"
docker cp "${PROJECT_ROOT}/configs/xsession" "${CONTAINER}:/opt/xsession"
docker cp "${PROJECT_ROOT}/scripts/theme-switch.sh" "${CONTAINER}:/usr/local/bin/theme-switch"
docker cp "${PROJECT_ROOT}/scripts/prune-gnome-backgrounds.py" "${CONTAINER}:${TMP_DIR}/prune-gnome-backgrounds.py"

for wallpaper in "${WALLPAPERS[@]}"; do
    docker cp "${BACKGROUND_DIR}/${wallpaper}" "${CONTAINER}:${TMP_DIR}/${wallpaper}"
done

docker exec "$CONTAINER" bash -lc "
    set -e
    mkdir -p /usr/share/backgrounds/webclaw /usr/share/gnome-background-properties
    find /usr/share/backgrounds/webclaw -maxdepth 1 -type f \( -name '*.jpg' -o -name '*.png' -o -name '*.webp' \) -delete
    cp '${TMP_DIR}/webclaw-backgrounds.xml' /usr/share/gnome-background-properties/webclaw-backgrounds.xml
    for wallpaper in ${WALLPAPERS[*]}; do
        cp '${TMP_DIR}/'\${wallpaper} /usr/share/backgrounds/webclaw/
    done
    chmod 755 /opt/xsession /usr/local/bin/theme-switch '${TMP_DIR}/prune-gnome-backgrounds.py'
    python3 '${TMP_DIR}/prune-gnome-backgrounds.py' \
        /usr/share/gnome-background-properties \
        Province_of_the_south_of_france_by_orbitelambda.jpg \
        Monument_valley_by_orbitelambda.jpg
    rm -f \
        /usr/share/backgrounds/Province_of_the_south_of_france_by_orbitelambda.jpg \
        /usr/share/backgrounds/Monument_valley_by_orbitelambda.jpg
"

if [ -n "$SELECTED_WALLPAPER" ]; then
    docker exec --user ubuntu "$CONTAINER" bash -lc "
        export DISPLAY=:1
        export XDG_RUNTIME_DIR=/run/user/1000
        FLASHBACK_PID=\$(pgrep -u \$(id -u) -x gnome-flashback | head -1 || true)
        if [ -n \"\$FLASHBACK_PID\" ] && [ -r \"/proc/\$FLASHBACK_PID/environ\" ]; then
            export DBUS_SESSION_BUS_ADDRESS=\$(tr '\0' '\n' < \"/proc/\$FLASHBACK_PID/environ\" | sed -n 's/^DBUS_SESSION_BUS_ADDRESS=//p' | head -1)
        fi
        gsettings set org.gnome.desktop.background picture-uri 'file:///usr/share/backgrounds/webclaw/${SELECTED_WALLPAPER}'
        gsettings set org.gnome.desktop.background picture-uri-dark 'file:///usr/share/backgrounds/webclaw/${SELECTED_WALLPAPER}'
    "
fi

echo "Deployed ${#WALLPAPERS[@]} wallpaper(s) to $CONTAINER"
