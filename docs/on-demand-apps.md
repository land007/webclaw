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

## 安装方式说明

| 安装方式 | 说明 | 优势 | 应用 |
|---------|------|------|------|
| **apt** | 从 Ubuntu 仓库或自定义仓库安装 .deb 包 | 安装快速，依赖自动处理，便于更新 | flameshot, wireshark, audacity, blender, gimp, vscode, antigravity |
| **github_release** | 从 GitHub Releases 下载 .deb 文件安装 | 直接获取最新版本，无需额外仓库 | dbeaver, dockyard, opentypeless, cc-switch |
| **appimage** | 下载 AppImage 并解压到 /opt/ondemand-apps/ | 无需 root 安装，自包含依赖 | ghostty, obsidian |
| **cursor_api** | 使用 Cursor 官方 API 下载 AppImage | 获取 Cursor 编辑器的最新版本 | cursor |
| **direct_download** | 从指定 URL 直接下载并解压 | 灵活支持任意下载源 | eclipse, pycharm, intellij, trae, android-studio, webclaw-launcher, codex |

### 安装方式详情

#### apt
```bash
apt-get install -y <package>
```
- 需要预先配置 apt 仓库（如 VS Code 需要微软仓库）
- 安装后二进制通常位于 `/usr/bin/` 或 `/opt/`

#### github_release
```bash
curl -fsSL "https://github.com/<repo>/releases/download/v<version>/<asset>" -o /tmp/app.deb
apt-get install -y /tmp/app.deb
```
- 使用 GitHub API 获取最新版本号
- 支持架构映射（amd64/arm64）

#### appimage
```bash
curl -fsSL "<url>" -o /tmp/app.AppImage
/tmp/app.AppImage --appimage-extract
mv squashfs-root /opt/ondemand-apps/<id>/AppDir
```
- 解压 AppImage 到固定目录
- 支持卸载自带 GL 库（Ghostty）

#### cursor_api
```bash
version=$(curl -s "https://api2.cursor.sh/updates/latest" | jq -r '.version')
curl -fsSL "https://api2.cursor.sh/updates/download/golden/<arch>/cursor/<version>" -o /tmp/cursor.AppImage
```
- 使用 Cursor 官方 API 获取版本
- AppImage 解压后移动到 `/opt/cursor/`

#### direct_download
```bash
curl -fsSL "<url>" -o /tmp/file.<ext>
# 根据 .AppImage / .zip / .tar.gz 分别处理
```
- 支持多种压缩格式
- 自动处理单层目录展开

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
