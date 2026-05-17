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
if [ -n "$SSH_AUTHORIZED_KEYS" ]; then
  mkdir -p /home/ubuntu/.ssh
  chmod 700 /home/ubuntu/.ssh
  echo "$SSH_AUTHORIZED_KEYS" > /home/ubuntu/.ssh/authorized_keys
  chmod 600 /home/ubuntu/.ssh/authorized_keys
  chown -R ubuntu:ubuntu /home/ubuntu/.ssh
  echo "[ssh-server] Authorized keys configured"
fi

# 禁用 PAM
sed -i 's/UsePAM yes/UsePAM no/' /etc/ssh/sshd_config

echo "[ssh-server] Starting SSH server on port ${SSH_PORT}"
exec /usr/sbin/sshd -D -e
