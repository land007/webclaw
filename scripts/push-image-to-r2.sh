#!/bin/bash
# 构建完成后执行，将镜像打包上传到 R2
# 用法: ./push-image-to-r2.sh linux/amd64
#        ./push-image-to-r2.sh linux/arm64
#
# 所需环境变量:
#   AWS_ACCESS_KEY_ID     = R2_ACCESS_KEY_ID
#   AWS_SECRET_ACCESS_KEY = R2_SECRET_ACCESS_KEY

set -e

PLATFORM=${1:-linux/amd64}
IMAGE=land007/webclaw:latest
NAME=webclaw
PUBLIC_BASE_URL="https://launcher.qhkly.com"

R2_ENDPOINT="https://0aa088497f85e67a7eae3fbe77521797.r2.cloudflarestorage.com"
R2_BUCKET="webcode-launcher"

ARCH=${PLATFORM//\//-}   # linux/amd64 → linux-amd64
TARFILE="${NAME}-${ARCH}.tar.gz"

echo "==> Exporting ${IMAGE} (platform: ${PLATFORM})..."
docker save "$IMAGE" | gzip > "$TARFILE"

SIZE=$(wc -c < "$TARFILE" | tr -d ' ')

# Prefer repo digest (set after docker push); fall back to image ID
DIGEST=$(docker inspect --format='{{index .RepoDigests 0}}' "$IMAGE" 2>/dev/null || true)
if [ -z "$DIGEST" ]; then
  DIGEST=$(docker inspect --format='{{.Id}}' "$IMAGE" 2>/dev/null || true)
fi
echo "==> Digest: ${DIGEST}"

echo "==> Uploading ${TARFILE} to R2..."
aws s3 cp "$TARFILE" \
  "s3://${R2_BUCKET}/registry/${NAME}-${ARCH}-latest.tar.gz" \
  --endpoint-url "$R2_ENDPOINT" \
  --region auto

TMP_JSON=$(mktemp)
aws s3 cp \
  "s3://${R2_BUCKET}/registry/${NAME}/latest.json" "${TMP_JSON}" \
  --endpoint-url "$R2_ENDPOINT" \
  --region auto 2>/dev/null || echo '{}' > "${TMP_JSON}"

python3 - <<EOF
import json, sys

with open('${TMP_JSON}') as f:
    try:
        data = json.load(f)
    except Exception:
        data = {}

data['image'] = '${NAME}'
data['tag'] = 'latest'
data['version'] = data.get('version') or 'manual'
data.setdefault('platforms', {})
data['platforms']['${PLATFORM}'] = {
    'digest': '${DIGEST}' or None,
    'url': '${PUBLIC_BASE_URL}/registry/${NAME}-${ARCH}-latest.tar.gz',
    'size': ${SIZE},
}

with open('${TMP_JSON}', 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
EOF

echo "==> Uploading latest.json..."
aws s3 cp "${TMP_JSON}" \
  "s3://${R2_BUCKET}/registry/${NAME}/latest.json" \
  --endpoint-url "$R2_ENDPOINT" \
  --region auto \
  --content-type "application/json"
aws s3 cp "${TMP_JSON}" \
  "s3://${R2_BUCKET}/docker/${NAME}/latest.json" \
  --endpoint-url "$R2_ENDPOINT" \
  --region auto \
  --content-type "application/json"

echo "==> Done!"
echo "==> Verify: ${PUBLIC_BASE_URL}/registry/${NAME}/latest.json"

rm -f "$TARFILE" "$TMP_JSON"
