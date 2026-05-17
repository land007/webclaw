#!/usr/bin/env bash
set -euo pipefail

SSH_PORT="${SSH_PORT:-10022}"
SSH_AUTHORIZED_KEYS="${SSH_AUTHORIZED_KEYS:-}"

# 设置 SSH 端口
sed -i "s/#Port 22/Port ${SSH_PORT}/" /etc/ssh/sshd_config

# 确保 ubuntu 用户可以 SSH 登录
if [ -n "${PASSWORD:-}" ]; then
  echo "ubuntu:$PASSWORD" | chpasswd
  echo "[ssh-server] Ubuntu user password configured"
fi

# 设置授权公钥（如果提供）
# 只在 authorized_keys 文件为空或不存在时写入，避免覆盖用户手动添加的公钥
AUTHORIZED_KEYS_FILE="/home/ubuntu/.ssh/authorized_keys"
if [ -n "$SSH_AUTHORIZED_KEYS" ]; then
  mkdir -p /home/ubuntu/.ssh
  chmod 700 /home/ubuntu/.ssh

  # 检查文件是否已存在且有内容
  if [ -s "$AUTHORIZED_KEYS_FILE" ]; then
    echo "[ssh-server] Authorized keys file already exists, keeping existing keys"
  else
    echo "$SSH_AUTHORIZED_KEYS" > "$AUTHORIZED_KEYS_FILE"
    echo "[ssh-server] Authorized keys configured from environment"
  fi

  chmod 600 "$AUTHORIZED_KEYS_FILE"
  chown -R ubuntu:ubuntu /home/ubuntu/.ssh
fi

# 禁用 PAM
sed -i 's/UsePAM yes/UsePAM no/' /etc/ssh/sshd_config

echo "[ssh-server] Starting SSH server on port ${SSH_PORT}"
exec /usr/sbin/sshd -D -e
