#!/bin/bash
# Generate languagepacks.json (and default argv.json) for code-server language support.
#
# Background: VS Code has a bug where CLI-installed language pack extensions do not
# auto-generate languagepacks.json. Without this file, argv.json locale settings
# have no effect. This script replicates what the VS Code UI would normally generate.
#
# Usage: /opt/create-languagepacks.sh [user-data-dir] [extensions-dir]

USER_DATA_DIR="${1:-/home/ubuntu/.code-server}"
EXTENSIONS_DIR="${2:-/opt/code-server-extensions}"
LANGUAGE_PACK_PREFIX="ms-ceintl.vscode-language-pack-"
LANGUAGEPACKS_FILE="$USER_DATA_DIR/languagepacks.json"
ARGV_FILE="$USER_DATA_DIR/User/argv.json"
EXTENSIONS_JSON="$EXTENSIONS_DIR/extensions.json"

mkdir -p "$(dirname "$ARGV_FILE")"

# Find language pack extension directories
mapfile -t LANGUAGE_PACK_FOLDERS < <(find "$EXTENSIONS_DIR" -maxdepth 1 -type d -name "${LANGUAGE_PACK_PREFIX}*" | sort)
if [ "${#LANGUAGE_PACK_FOLDERS[@]}" -eq 0 ]; then
    echo "[create-languagepacks] No language pack found in $EXTENSIONS_DIR, skipping."
    exit 0
fi

if [ ! -f "$EXTENSIONS_JSON" ]; then
    echo "[create-languagepacks] Missing extensions.json, skipping."
    exit 0
fi

LANGUAGEPACKS_TMP=$(mktemp)
echo '{}' > "$LANGUAGEPACKS_TMP"

for LANGUAGE_PACK_FOLDER in "${LANGUAGE_PACK_FOLDERS[@]}"; do
    PACKAGE_JSON="$LANGUAGE_PACK_FOLDER/package.json"
    if [ ! -f "$PACKAGE_JSON" ]; then
        echo "[create-languagepacks] Missing package.json in $LANGUAGE_PACK_FOLDER, skipping."
        continue
    fi

    # Extract metadata (UUID is in metadata.id, not identifier.uuid)
    LANGUAGE_PACK_NAME=$(jq -r '.name' "$PACKAGE_JSON")
    LANGUAGE_PACK_UUID=$(jq -r --arg id "ms-ceintl.$LANGUAGE_PACK_NAME" \
        '.[] | select(.identifier.id == $id) | .metadata.id' "$EXTENSIONS_JSON")
    LANGUAGE_ID=$(jq -r '.contributes.localizations[0].languageId' "$PACKAGE_JSON")
    LANGUAGE_LABEL=$(jq -r '.contributes.localizations[0].localizedLanguageName' "$PACKAGE_JSON")
    LANGUAGE_PACK_VERSION=$(jq -r '.version' "$PACKAGE_JSON")

    if [ -z "$LANGUAGE_ID" ] || [ "$LANGUAGE_ID" = "null" ]; then
        echo "[create-languagepacks] Missing languageId in $LANGUAGE_PACK_FOLDER, skipping."
        continue
    fi

    if [ -z "$LANGUAGE_PACK_UUID" ] || [ "$LANGUAGE_PACK_UUID" = "null" ]; then
        echo "[create-languagepacks] UUID not found for $LANGUAGE_PACK_NAME, using extension ID as fallback."
        LANGUAGE_PACK_UUID="$LANGUAGE_PACK_NAME"
    fi

    # Build translations map from package.json (relative -> absolute paths)
    TRANSLATIONS=$(jq -n \
        --arg dir "$LANGUAGE_PACK_FOLDER" \
        --argjson t "$(jq '.contributes.localizations[0].translations' "$PACKAGE_JSON")" \
        'reduce $t[] as $item ({}; . + {($item.id): "\($dir)/\($item.path)"})')

    # Hash: md5(UUID + VERSION) - matches VS Code's updateHash() implementation
    HASH=$(printf '%s' "${LANGUAGE_PACK_UUID}${LANGUAGE_PACK_VERSION}" | md5sum | awk '{print $1}')
    ENTRY_TMP=$(mktemp)

    jq -n \
        --arg lang_id "$LANGUAGE_ID" \
        --arg hash "$HASH" \
        --arg name "$LANGUAGE_PACK_NAME" \
        --arg uuid "$LANGUAGE_PACK_UUID" \
        --arg version "$LANGUAGE_PACK_VERSION" \
        --argjson translations "$TRANSLATIONS" \
        --arg label "$LANGUAGE_LABEL" \
        '{($lang_id):{"hash":$hash,"extensions":[{"extensionIdentifier":{"id":$name,"uuid":$uuid},"version":$version}],"translations":$translations,"label":$label}}' \
        > "$ENTRY_TMP"

    jq -s '.[0] * .[1]' "$LANGUAGEPACKS_TMP" "$ENTRY_TMP" > "${LANGUAGEPACKS_TMP}.next"
    mv "${LANGUAGEPACKS_TMP}.next" "$LANGUAGEPACKS_TMP"
    rm -f "$ENTRY_TMP"
    echo "[create-languagepacks] added lang=$LANGUAGE_ID, version=$LANGUAGE_PACK_VERSION"
done

mv "$LANGUAGEPACKS_TMP" "$LANGUAGEPACKS_FILE"
echo "[create-languagepacks] languagepacks.json written: $LANGUAGEPACKS_FILE"
