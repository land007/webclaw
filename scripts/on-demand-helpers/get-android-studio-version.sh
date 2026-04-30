#!/bin/bash
# 动态获取 Android Studio 最新版本号
# 用法: get-android-studio-version

set -e

# Android Studio 版本信息 API
VERSION_INFO_URL="https://dl.google.com/android/studio/versions/info.txt"

# 尝试从官方 API 获取版本号
VERSION=$(curl -fsSL --connect-timeout 10 "$VERSION_INFO_URL" 2>/dev/null \
    | grep -oP 'build\[\K[0-9.]+' \
    | head -1)

# 备选方案：从开发者页面抓取
if [ -z "$VERSION" ]; then
    VERSION=$(curl -fsSL --connect-timeout 10 "https://developer.android.com/studio" 2>/dev/null \
        | grep -oP 'android-studio-[\d.]+-linux' \
        | grep -oP '[\d.]+' \
        | head -1)
fi

# 回退版本（当所有方法都失败时）
if [ -z "$VERSION" ]; then
    VERSION="2024.2.1.10"
fi

# 输出 JSON 格式
echo "{\"version\": \"$VERSION\"}"
