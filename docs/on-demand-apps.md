# 按需应用清单

本文档列出了 WebClaw Docker 镜像中所有按需安装的应用及其安装方式。

## 应用列表

| 应用 | 安装方式 | 大小/复杂度 | 说明 |
|------|----------|-------------|------|
| flameshot | apt | 小 | 截图工具 |
| wireshark | apt | 中 | 网络分析工具 |
| audacity | apt | 中 | 音频编辑 |
| blender | apt | 大 (~500MB) | 3D 建模 |
| gimp | apt | 大 (~200MB) | 图像编辑 |
| vscode | apt | 中 (~100MB) | Visual Studio Code |
| antigravity | apt(自定义仓库) | 小 | Google Antigravity |
| cursor | Cursor API | 中 | AI 编辑器 |
| ghostty | AppImage | 中 | 终端模拟器 |
| obsidian | AppImage | 中 | 笔记应用 |
| dbeaver | GitHub Release | 中 | 数据库工具 |
| eclipse | 直接下载 | 大 (~300MB) | Eclipse IDE |
| pycharm | 直接下载 | 大 (~400MB) | PyCharm Community |
| intellij | 直接下载 | 大 (~600MB) | IntelliJ IDEA |
| trae | 直接下载 | 中 | Trae AI |
| dockyard | GitHub Release | 小 | Dockyard |
| codex | 直接下载 | 小 | Codex |
| android-studio | 直接下载 | 很大 (~1GB+) | Android Studio |
| webclaw-launcher | 直接下载 | 小 | WebClaw Launcher |
| cc-switch | GitHub Release | 小 | CC Switch |
| opentypeless | GitHub Release | 小 | OpenTypeless |

## 预装策略

- **Full 版本**（desktop 模式）：构建时自动预装所有应用
- **Lite 版本**：不预装，保持镜像精简

## 预装影响

| 指标 | 影响 |
|------|------|
| 镜像大小增加 | 约 3-5GB |
| 构建时间 | 增加 10-20 分钟 |
| 首次启动 | 无需等待下载，点击即用 |

## 配置文件位置

- 应用配置：`configs/on-demand-apps/*.json`
- 应用图标：`configs/on-demand-icons/*.png`
- 桌面快捷方式：`configs/desktop-shortcuts/*.desktop`
- 预装脚本：`scripts/preinstall-on-demand.sh`
