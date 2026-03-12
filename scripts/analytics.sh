#!/bin/bash

ANALYTICS_INTERVAL=60
MEASUREMENT_ID="G-46ZP151Y4E"
API_SECRET="x8d_heuwTayCt7SanLPZQw"
GA4_ENDPOINT="https://www.google-analytics.com/mp/collect"

image_name=$(cat /.image_name 2>/dev/null || echo "land007/webcode")
image_time=$(cat /.image_time 2>/dev/null || echo "unknown")

# UUID 持久化（跨重启保持同一容器标识）
uuid_file="/.uuid"
if [ ! -s "$uuid_file" ]; then
    uuid=$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid)
    echo "$uuid" > "$uuid_file"
fi
uuid=$(cat "$uuid_file")

# 首次启动时间持久化
start_time_file="/.start_time"
if [ ! -s "$start_time_file" ]; then
    echo $(date "+%Y-%m-%d_%H:%M:%S") > "$start_time_file"
fi
start_time=$(cat "$start_time_file")

while true; do
    body=$(cat <<EOF
{
  "client_id": "$uuid",
  "events": [{
    "name": "container_ping",
    "params": {
      "image_name": "$image_name",
      "image_time": "$image_time",
      "start_time": "$start_time"
    }
  }]
}
EOF
)
    curl -s -X POST \
        "${GA4_ENDPOINT}?measurement_id=${MEASUREMENT_ID}&api_secret=${API_SECRET}" \
        -H "Content-Type: application/json" \
        -d "$body" > /dev/null 2>&1

    sleep "$ANALYTICS_INTERVAL"
done
