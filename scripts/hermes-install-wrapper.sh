#!/bin/bash
# Hermes 安装 wrapper 脚本
# 设置需要的环境变量，然后执行实际的安装脚本
export WEBCLAW_APP_LAUNCHER=1
export DISABLE_ZENITY=1
exec /opt/install-hermes.sh "$@"
