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

# Find language pack extension directory
LANGUAGE_PACK_FOLDER=$(find "$EXTENSIONS_DIR" -maxdepth 1 -type d -name "${LANGUAGE_PACK_PREFIX}*" | head -n 1)
if [ -z "$LANGUAGE_PACK_FOLDER" ]; then
    echo "[create-languagepacks] No language pack found in $EXTENSIONS_DIR, skipping."
    exit 0
fi

PACKAGE_JSON="$LANGUAGE_PACK_FOLDER/package.json"
if [ ! -f "$PACKAGE_JSON" ] || [ ! -f "$EXTENSIONS_JSON" ]; then
    echo "[create-languagepacks] Missing package.json or extensions.json, skipping."
    exit 0
fi

# Extract metadata (UUID is in metadata.id, not identifier.uuid)
LANGUAGE_PACK_NAME=$(jq -r '.name' "$PACKAGE_JSON")
LANGUAGE_PACK_UUID=$(jq -r --arg id "ms-ceintl.$LANGUAGE_PACK_NAME" \
    '.[] | select(.identifier.id == $id) | .metadata.id' "$EXTENSIONS_JSON")
LANGUAGE_ID=$(jq -r '.contributes.localizations[0].languageId' "$PACKAGE_JSON")
LANGUAGE_LABEL=$(jq -r '.contributes.localizations[0].localizedLanguageName' "$PACKAGE_JSON")
LANGUAGE_PACK_VERSION=$(jq -r '.version' "$PACKAGE_JSON")

if [ -z "$LANGUAGE_PACK_UUID" ] || [ "$LANGUAGE_PACK_UUID" = "null" ]; then
    echo "[create-languagepacks] UUID not found, using extension ID as fallback."
    LANGUAGE_PACK_UUID="$LANGUAGE_PACK_NAME"
fi

# Build translations map from package.json (relative → absolute paths)
TRANSLATIONS=$(jq -n \
    --arg dir "$LANGUAGE_PACK_FOLDER" \
    --argjson t "$(jq '.contributes.localizations[0].translations' "$PACKAGE_JSON")" \
    'reduce $t[] as $item ({}; . + {($item.id): "\($dir)/\($item.path)"})')

# Hash: md5(UUID + VERSION) — matches VS Code's updateHash() implementation
HASH=$(printf '%s' "${LANGUAGE_PACK_UUID}${LANGUAGE_PACK_VERSION}" | md5sum | awk '{print $1}')

# Write languagepacks.json
jq -n \
    --arg lang_id "$LANGUAGE_ID" \
    --arg hash "$HASH" \
    --arg name "$LANGUAGE_PACK_NAME" \
    --arg uuid "$LANGUAGE_PACK_UUID" \
    --arg version "$LANGUAGE_PACK_VERSION" \
    --argjson translations "$TRANSLATIONS" \
    --arg label "$LANGUAGE_LABEL" \
    '{($lang_id):{"hash":$hash,"extensions":[{"extensionIdentifier":{"id":$name,"uuid":$uuid},"version":$version}],"translations":$translations,"label":$label}}' \
    > "$LANGUAGEPACKS_FILE"

echo "[create-languagepacks] languagepacks.json written: $LANGUAGEPACKS_FILE (lang=$LANGUAGE_ID, version=$LANGUAGE_PACK_VERSION)"
