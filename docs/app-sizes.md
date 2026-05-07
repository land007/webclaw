# WebClaw 应用磁盘占用统计

> 最后更新：2026-05-07  
> 容器：webclaw-inst-df33fc026fd7433881b0fb37586c4a00  
> 镜像：land007/webclaw_full:latest

## 📊 已安装应用

| 应用名称 | 占用空间 | 位置/包名 | 安装方式 |
|---------|---------|----------|---------|
| Flameshot | 2.9 MB | flameshot | apt |
| Wireshark | 10.2 MB | wireshark | apt |
| Dockyard | 13.0 MB | dockyard | apt |
| OpenTypeless | 13.0 MB | open-typeless | apt |
| Audacity | 23.0 MB | audacity | apt |
| GIMP | 23.9 MB | gimp | apt |
| CC Switch | 24.1 MB | cc-switch | apt |
| OpenCode | 39.7 MB | opencode | apt |
| Codex | 185 MB | /opt/codex | direct_download |
| DBeaver Community | 201.6 MB | dbeaver-ce | apt |
| Visual Studio Code | 626.7 MB | code | apt |
| Google Antigravity | 683.8 MB | antigravity | apt |
| Hermes Agent | 1.6 GB | /opt/hermes-agent | custom_script |

### 已安装应用统计

- **总数量：** 13 个
- **总大小：** ~3.5 GB
- **小型应用** (< 50 MB): 9 个
- **中型应用** (50-500 MB): 2 个
- **大型应用** (500 MB - 1 GB): 2 个
- **超大型应用** (> 1 GB): 1 个

---

## 📦 未安装应用（按需安装）

| 应用名称 | 预计大小 | 包名/位置 | 跳过预装原因 |
|---------|---------|----------|------------|
| Android Studio | ~1 GB | android-studio | 超大型 IDE |
| IntelliJ IDEA Community | ~600-800 MB | intellijidea-community-edition | JetBrains IDE |
| PyCharm Community | ~600-800 MB | pycharmcc | JetBrains IDE |
| Blender | ~500 MB | blender | 3D 建模软件 |
| Eclipse IDE | ~200-300 MB | eclipse | IDE |
| Trae | ~200 MB | trae | AI 编程工具 |
| Cursor | ~400-500 MB | /opt/cursor | cursor_api |
| Ghostty | ~100-200 MB | /opt/ondemand-apps/ghostty | appimage |
| Obsidian | ~200-300 MB | /opt/ondemand-apps/obsidian | appimage |
| WebClaw Launcher | ~100-200 MB | /opt/webclaw-launcher | r2_download |

**跳过预装原因：**
- 减少镜像构建时间
- 减少镜像大小
- 降低网络传输成本
- 用户可按需安装

---

## 🏷️ 按安装方式分类

### apt 安装（系统包管理器）

| 应用 | 大小 | 说明 |
|------|------|------|
| Flameshot | 2.9 MB | 截图工具 |
| Wireshark | 10.2 MB | 网络抓包 |
| Dockyard | 13.0 MB | 容器管理 |
| OpenTypeless | 13.0 MB | 字体工具 |
| Audacity | 23.0 MB | 音频编辑 |
| GIMP | 23.9 MB | 图像编辑 |
| CC Switch | 24.1 MB | 代码切换 |
| OpenCode | 39.7 MB | AI 编程助手 |
| DBeaver Community | 201.6 MB | 数据库工具 |
| Visual Studio Code | 626.7 MB | 代码编辑器 |
| Google Antigravity | 683.8 MB | AI 助手 |

### 自定义安装（AppImage/脚本下载）

| 应用 | 大小 | 安装方式 |
|------|------|---------|
| Codex | 185 MB | direct_download |
| Hermes Agent | 1.6 GB | custom_script (Python venv) |
| Cursor | ~400-500 MB | cursor_api |
| Ghostty | ~100-200 MB | appimage |
| Obsidian | ~200-300 MB | appimage |
| WebClaw Launcher | ~100-200 MB | r2_download |

---

## 📏 大小分布图

```
< 50 MB    ████████████████████ 9 个 (69%)
50-500 MB  ██ 2 个 (15%)
500MB-1GB  ██ 2 个 (15%)
> 1 GB     █ 1 个 (8%)
```

---

## 🔧 如何获取应用大小

### 方法 1：dpkg 包（apt 安装）

```bash
dpkg -s <package-name> | grep "Installed-Size"
```

### 方法 2：目录大小（自定义安装）

```bash
du -sh <directory>
```

### 方法 3：完整脚本

```bash
for manifest in /opt/on-demand-apps/*.json; do
    app_id=$(basename "$manifest" .json)
    name=$(jq -r ".name" "$manifest")
    bin=$(jq -r ".binary" "$manifest")
    install_method=$(jq -r ".install_method" "$manifest")
    
    if [ "$install_method" = "appimage" ] || [ "$install_method" = "direct_download" ]; then
        size=$(du -sh "$(dirname "$bin")" 2>/dev/null | cut -f1)
        echo "$name: $size"
    else
        size=$(dpkg -s "$(jq -r ".package" "$manifest")" 2>/dev/null | grep "^Installed-Size" | awk "{print \$2}")
        echo "$name: ${size} KB"
    fi
done
```

---

## 📝 备注

1. **Hermes Agent** 占用最大（1.6 GB），因为包含完整的 Python 虚拟环境和所有依赖
2. **Google Antigravity** 和 **VS Code** 是第二、第三大应用
3. **Antigravity** 已在 Dockerfile.full 中设置为跳过预装（PREINSTALL_SKIP）
4. 大部分工具类应用都在 50 MB 以下
5. 未安装的应用不占用磁盘空间

---

## 🔄 更新记录

- **2026-05-07:** 初始文档创建，记录所有已安装和未安装应用的大小
- 未来更新时请更新"最后更新"日期
