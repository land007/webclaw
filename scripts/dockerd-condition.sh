#!/bin/bash
# dockerd 条件启动脚本
# 仅在 DinD 模式下实际启动 dockerd，否则 sleep infinity

if [ "${DOCKER_SOCK_MODE:-host}" = "dind" ]; then
  # DinD 模式：启动 dockerd
  # 存储驱动选择：
  # - macOS Docker Desktop: 必须使用 vfs（overlay2 会挂载失败）
  # - 真实 Linux 环境: 自动检测（通常是 overlay2）
  if grep -q "Darwin\|macOS\|linuxkit" /proc/version 2>/dev/null; then
    # macOS Docker Desktop 环境
    exec /usr/bin/dockerd --host=unix:///var/run/docker.sock --storage-driver=vfs
  else
    # 真实 Linux 环境，让 dockerd 自动检测最佳驱动
    exec /usr/bin/dockerd --host=unix:///var/run/docker.sock
  fi
else
  # 非 DinD 模式：睡眠不启动（supervisor 不会重启）
  sleep infinity
fi
