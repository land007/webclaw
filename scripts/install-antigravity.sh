#!/bin/bash
# Google Antigravity 安装脚本
set -e

# 1. 添加仓库密钥
curl -fsSL https://us-central1-apt.pkg.dev/doc/repo-signing-key.gpg | sudo gpg --dearmor -o /etc/apt/keyrings/antigravity-repo-key.gpg

# 2. 添加仓库
echo "deb [signed-by=/etc/apt/keyrings/antigravity-repo-key.gpg] https://us-central1-apt.pkg.dev/projects/antigravity-auto-updater-dev/ antigravity-debian main" | sudo tee /etc/apt/sources.list.d/antigravity.list > /dev/null

# 3. 更新并安装
sudo apt update
sudo apt install -y antigravity
