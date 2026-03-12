#!/bin/bash
#
# Enable Platform mode for ClaudeCodeUI（免登录配置）
#
# 原理：
# 1. 通过环境变量 VITE_IS_PLATFORM=true 启用Platform模式
# 2. 修改 auth.js 的 /status 端点，让Platform模式下返回已认证
# 3. 不指定数据库路径，让ClaudeCodeUI自己管理
#

echo "[claudecodeui] 正在启用 Platform mode（免登录）..."

AUTH_JS="/usr/lib/node_modules/@siteboon/claude-code-ui/server/routes/auth.js"

# 检查文件是否存在
if [ ! -f "$AUTH_JS" ]; then
  echo "[错误] 未找到文件: $AUTH_JS"
  echo "ClaudeCodeUI 可能未安装或版本不兼容"
  exit 1
fi

# 备份原文件
if [ ! -f "${AUTH_JS}.platform.bak" ]; then
  cp "$AUTH_JS" "${AUTH_JS}.platform.bak"
  echo "[备份] 已备份原文件"
fi

# 检查是否有 status 端点（使用更宽松的检查）
if grep -q "router\.get.*['\"]\/status['\"]" "$AUTH_JS" || grep -q "'/status'" "$AUTH_JS"; then
  echo "[✓] 找到 /status 端点"
else
  echo "[错误] 未找到 /status 端点，可能版本不兼容"
  echo "[提示] 请手动检查: cat $AUTH_JS | grep -n status"
  exit 1
fi

# 添加 IS_PLATFORM 导入（如果还没有）
if grep -q "IS_PLATFORM" "$AUTH_JS"; then
  echo "[✓] IS_PLATFORM 导入已存在"
else
  # 添加 IS_PLATFORM 导入
  sed -i '1a import { IS_PLATFORM } from "../constants/config.js";' "$AUTH_JS"
  echo "[✓] 已添加 IS_PLATFORM 导入"
fi

# 修改 /status 端点的认证逻辑
# 替换 isAuthenticated: false 为条件判断
sed -i 's/isAuthenticated: false \/\/ Will be overridden by frontend if token exists/isAuthenticated: IS_PLATFORM \&\& hasUsers ? true : false/g' "$AUTH_JS"

# 检查是否修改成功
if grep -q "isAuthenticated: IS_PLATFORM" "$AUTH_JS"; then
  echo "[✓] 已修改 /status 端点的认证逻辑"
else
  echo "[警告] 可能未能正确修改"
  echo "[提示] 请手动检查: grep -A 10 'router.get.*status' $AUTH_JS"
fi

echo ""
echo "[完成] ClaudeCodeUI Platform mode 配置完成"
echo "[提示] 请确保在环境变量中设置 VITE_IS_PLATFORM=true"
