#!/bin/bash
#
# Enable Platform mode for ClaudeCodeUI（免登录配置）
#
# 原理：
# 1. 通过环境变量 VITE_IS_PLATFORM=true 启用 Platform 模式
# 2. 修改 auth 路由的 /status 端点，让 Platform 模式下返回已认证
#

set -euo pipefail

log() {
  echo "[claudecodeui] $*"
}

warn() {
  echo "[警告] $*" >&2
}

fail() {
  echo "[错误] $*" >&2
  exit 1
}

find_package_root() {
  local npm_root=""
  local candidate=""

  if command -v npm >/dev/null 2>&1; then
    npm_root="$(npm root -g 2>/dev/null || true)"
    if [ -n "$npm_root" ] && [ -d "$npm_root/@siteboon/claude-code-ui" ]; then
      echo "$npm_root/@siteboon/claude-code-ui"
      return 0
    fi
  fi

  for candidate in \
    /usr/lib/node_modules/@siteboon/claude-code-ui \
    /usr/local/lib/node_modules/@siteboon/claude-code-ui \
    /home/ubuntu/.nvm/versions/node/*/lib/node_modules/@siteboon/claude-code-ui; do
    if [ -d "$candidate" ]; then
      echo "$candidate"
      return 0
    fi
  done

  return 1
}

find_auth_file() {
  local package_root="$1"
  local candidate=""

  for candidate in \
    "$package_root/server/routes/auth.js" \
    "$package_root/dist/server/routes/auth.js" \
    "$package_root/build/server/routes/auth.js"; do
    if [ -f "$candidate" ]; then
      echo "$candidate"
      return 0
    fi
  done

  while IFS= read -r candidate; do
    if grep -qE "['\"]/status['\"]" "$candidate" 2>/dev/null; then
      echo "$candidate"
      return 0
    fi
  done < <(find "$package_root" -type f \( -name "auth.js" -o -name "auth.mjs" -o -name "auth.cjs" \) 2>/dev/null | sort)

  return 1
}

ensure_platform_import() {
  local auth_file="$1"
  local config_import=""

  if grep -q "IS_PLATFORM" "$auth_file"; then
    log "IS_PLATFORM 导入已存在"
    return 0
  fi

  if grep -q '\.\./constants/config\.js' "$auth_file"; then
    config_import='import { IS_PLATFORM } from "../constants/config.js";'
  elif grep -q '\.\./constants/config' "$auth_file"; then
    config_import='import { IS_PLATFORM } from "../constants/config";'
  elif grep -q '\.\./constants/config\.mjs' "$auth_file"; then
    config_import='import { IS_PLATFORM } from "../constants/config.mjs";'
  else
    config_import='import { IS_PLATFORM } from "../constants/config.js";'
  fi

  perl -0pi -e 's#^(import .*\n)#$1'"$config_import"$'\n#' "$auth_file"
  log "已添加 IS_PLATFORM 导入"
}

patch_status_endpoint() {
  local auth_file="$1"

  if grep -q "isAuthenticated: IS_PLATFORM" "$auth_file"; then
    log "/status 端点已是 Platform 兼容版本"
    return 0
  fi

  perl -0pi -e 's#isAuthenticated:\s*false(\s*//[^\n]*)?#isAuthenticated: IS_PLATFORM && hasUsers ? true : false#g' "$auth_file"

  if grep -q "isAuthenticated: IS_PLATFORM" "$auth_file"; then
    log "已修改 /status 端点的认证逻辑"
    return 0
  fi

  return 1
}

log "正在启用 Platform mode（免登录）..."

PACKAGE_ROOT="$(find_package_root || true)"

if [ -z "${PACKAGE_ROOT:-}" ]; then
  fail "未找到 @siteboon/claude-code-ui 安装目录。请检查 npm install -g 是否成功。"
fi

log "检测到 ClaudeCodeUI 安装目录: $PACKAGE_ROOT"

AUTH_JS="$(find_auth_file "$PACKAGE_ROOT" || true)"

if [ -z "${AUTH_JS:-}" ]; then
  warn "在以下目录未找到可兼容的 auth 路由文件: $PACKAGE_ROOT"
  warn "可手动执行: find $PACKAGE_ROOT -type f | grep auth"
  fail "ClaudeCodeUI 目录结构可能已变化，暂时无法自动启用 Platform mode"
fi

log "检测到 auth 路由文件: $AUTH_JS"

if ! grep -qE "router\.get.*['\"]/status['\"]|['\"]/status['\"]" "$AUTH_JS"; then
  fail "未在 $AUTH_JS 中找到 /status 端点，版本结构可能已变化"
fi

if [ ! -f "${AUTH_JS}.platform.bak" ]; then
  cp "$AUTH_JS" "${AUTH_JS}.platform.bak"
  log "已备份原文件"
fi

ensure_platform_import "$AUTH_JS"

if ! patch_status_endpoint "$AUTH_JS"; then
  warn "未匹配到旧版 isAuthenticated: false 写法"
  warn "请手动检查: grep -n \"isAuthenticated\\|/status\" \"$AUTH_JS\""
  fail "未能自动修改 /status 端点"
fi

echo ""
log "Platform mode 配置完成"
log "请确保运行环境包含 VITE_IS_PLATFORM=true"
