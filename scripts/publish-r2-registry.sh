#!/bin/bash

set -euo pipefail

if [ "$#" -ne 4 ]; then
  echo "Usage: $0 <image-name> <version-label> <amd64-tar.gz> <arm64-tar.gz>" >&2
  exit 1
fi

IMAGE_NAME="$1"
VERSION_LABEL="$2"
AMD64_FILE="$3"
ARM64_FILE="$4"

: "${R2_BUCKET:?R2_BUCKET is required}"
: "${R2_ENDPOINT:?R2_ENDPOINT is required}"

PUBLIC_BASE_URL="${PUBLIC_BASE_URL:-https://launcher.qhkly.com}"
TMP_DIR="$(mktemp -d)"
MANIFEST_PATH="${TMP_DIR}/latest.json"

upload_file() {
  local src="$1"
  local dest="$2"
  aws s3 cp "$src" "s3://${R2_BUCKET}/${dest}" --endpoint-url "${R2_ENDPOINT}"
}

build_manifest() {
  local amd64_size arm64_size
  amd64_size="$(wc -c < "${AMD64_FILE}" | tr -d ' ')"
  arm64_size="$(wc -c < "${ARM64_FILE}" | tr -d ' ')"

  python3 - <<PY
import json

data = {
  "image": "${IMAGE_NAME}",
  "tag": "latest",
  "version": "${VERSION_LABEL}",
  "platforms": {
    "linux/amd64": {
      "digest": None,
      "size": int("${amd64_size}"),
      "url": "${PUBLIC_BASE_URL}/registry/${IMAGE_NAME}-amd64-latest.tar.gz",
    },
    "linux/arm64": {
      "digest": None,
      "size": int("${arm64_size}"),
      "url": "${PUBLIC_BASE_URL}/registry/${IMAGE_NAME}-arm64-latest.tar.gz",
    },
  },
}

with open("${MANIFEST_PATH}", "w", encoding="utf-8") as f:
  json.dump(data, f, ensure_ascii=False, indent=2)
  f.write("\\n")
PY
}

upload_file "${AMD64_FILE}" "registry/${IMAGE_NAME}-amd64-${VERSION_LABEL}.tar.gz"
upload_file "${AMD64_FILE}" "registry/${IMAGE_NAME}-amd64-latest.tar.gz"
upload_file "${ARM64_FILE}" "registry/${IMAGE_NAME}-arm64-${VERSION_LABEL}.tar.gz"
upload_file "${ARM64_FILE}" "registry/${IMAGE_NAME}-arm64-latest.tar.gz"

build_manifest

# New canonical manifest location.
upload_file "${MANIFEST_PATH}" "registry/${IMAGE_NAME}/latest.json"

# Legacy manifest location kept for launcher compatibility.
upload_file "${MANIFEST_PATH}" "docker/${IMAGE_NAME}/latest.json"

rm -rf "${TMP_DIR}"
