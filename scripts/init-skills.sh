#!/bin/bash
set -e

echo "[init-skills] Initializing common skills directory..."

# 创建公共 skills 目录
mkdir -p /home/ubuntu/skills

# 为每个工具创建软链接
for tool_dir in .claude .openclaw .codex .gemini; do
    tool_path="/home/ubuntu/$tool_dir"
    skills_link="$tool_path/skills"

    # 确保工具目录存在
    mkdir -p "$tool_path"

    # 如果软链接已存在，先删除
    if [ -L "$skills_link" ]; then
        rm "$skills_link"
    fi

    # 如果是真实目录且非空，备份
    if [ -d "$skills_link" ] && [ ! -L "$skills_link" ]; then
        if [ "$(ls -A $skills_link 2>/dev/null)" ]; then
            backup_dir="$skills_link.backup.$(date +%Y%m%d%H%M%S)"
            echo "[init-skills] Backing up existing $skills_link to $backup_dir"
            mv "$skills_link" "$backup_dir"
        else
            rm -rf "$skills_link"
        fi
    fi

    # 创建软链接
    echo "[init-skills] Creating symlink: $skills_link -> /home/ubuntu/skills"
    ln -s /home/ubuntu/skills "$skills_link"
done

# 设置权限
chown -h ubuntu:ubuntu /home/ubuntu/.claude/skills 2>/dev/null || true
chown -h ubuntu:ubuntu /home/ubuntu/.openclaw/skills 2>/dev/null || true
chown -h ubuntu:ubuntu /home/ubuntu/.codex/skills 2>/dev/null || true
chown -h ubuntu:ubuntu /home/ubuntu/.gemini/skills 2>/dev/null || true
chown ubuntu:ubuntu /home/ubuntu/skills

echo "[init-skills] Common skills directory initialized successfully"
