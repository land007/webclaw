# Mac ↔ noVNC 容器文本剪贴板双向同步

## 概述

实现 Mac 和 noVNC 容器之间的文本剪贴板双向同步，无需手动复制粘贴。

- **Mac → 容器**：在 Mac 上复制文本，在 noVNC 中按 Ctrl+V 粘贴到容器
- **容器 → Mac**：在容器内复制文本，自动同步到 Mac 剪贴板

## 完整路径

### 路径 1：Mac → 容器（粘贴）

```
Mac 用户操作
    ↓
按 Ctrl+V / Cmd+V / Ctrl+Shift+V
    ↓
浏览器前端 (noVNC 页面)
    ├─ custom-clipboard-image.js 监听 keydown 事件
    ├─ navigator.clipboard.readText() 读取 Mac 剪贴板
    └─ fetch('/proxy/10009/api/clipboard-text', {method: 'POST'})
    ↓
dashboard-server (端口 20000)
    ├─ 反向代理 /proxy/10009/* → 127.0.0.1:10009
    └─ 转发 HTTP 请求
    ↓
clipboard-server.js (容器内，端口 10009)
    ├─ 接收 POST /api/clipboard-text
    ├─ 写入临时文件 /tmp/clipboard-text-xxx.txt
    ├─ xclip -selection clipboard -target UTF8_STRING -i 临时文件
    └─ 返回 {success: true, message: '文本已同步到剪贴板'}
    ↓
容器 X11 剪贴板
    └─ 文本已写入
    ↓
custom-clipboard-image.js
    └─ sendCtrlVToContainer() 发送 Ctrl+V 按键
    ↓
noVNC RFB 协议
    └─ RFB.sendKey() 发送按键事件
    ↓
容器应用（终端/编辑器）
    └─ Ctrl+V 粘贴文本 ✓
```

### 路径 2：容器 → Mac（复制）

```
容器用户操作
    ↓
按 Ctrl+C / Ctrl+Shift+C
    ↓
容器应用（终端/编辑器）
    └─ 文本复制到 X11 CLIPBOARD
    ↓
noVNC RFB 协议
    ├─ 检测到 X11 剪贴板内容变化
    └─ 触发 RFB clipboard 事件
    ↓
custom-clipboard-image.js (浏览器前端)
    ├─ 监听 rfb.addEventListener('clipboard', handleRfbClipboardText)
    ├─ 获取 e.detail.text
    └─ navigator.clipboard.writeText(text) 写入 Mac 剪贴板
    ↓
Mac 系统剪贴板
    └─ 文本已写入 ✓
```

## 依赖组件

| 组件 | 文件路径 | 端口 | 作用 |
|------|----------|------|------|
| 前端剪贴板桥 | `/opt/noVNC/custom-clipboard-image.js` | - | 监听按键/RFB 事件，调用剪贴板 API |
| 剪贴板服务 | `/opt/clipboard-server.js` | 10009 | 提供 X11 剪贴板读写 API |
| 反向代理 | `webclaw-dashboard-server` (npm 包) | 20000 | 代理 /proxy/10009/* 到容器 10009 |
| X11 剪贴板工具 | `/usr/bin/xclip` | - | 读写容器 X11 剪贴板 |

## API 端点

### GET /api/clipboard-text

读取容器 X11 文本剪贴板内容。

**请求**：
```
GET /api/clipboard-text
```

**响应**：
```json
{
  "text": "剪贴板内容"
}
```

### POST /api/clipboard-text

写入文本到容器 X11 剪贴板。

**请求**：
```json
POST /api/clipboard-text
Content-Type: application/json

{
  "text": "要写入的文本"
}
```

**响应**：
```json
{
  "success": true,
  "message": "文本已同步到剪贴板",
  "size": 123
}
```

## 快捷键

| 快捷键 | 功能 | 说明 |
|--------|------|------|
| Ctrl+V | 从 Mac 剪贴板粘贴到容器 | 适用于编辑器 |
| Cmd+V | 从 Mac 剪贴板粘贴到容器 | Mac 用户习惯 |
| Ctrl+Shift+V | 从 Mac 剪贴板粘贴到容器 | 适用于终端 |
| Ctrl+C | 容器内复制（应用原生） | 不干预 |
| Ctrl+Shift+C | 容器内复制（终端） | 不干预 |

## 技术细节

### 事件驱动架构

- **Mac → 容器**：监听键盘事件（keydown），检测 Ctrl+V/Cmd+V/Ctrl+Shift+V
- **容器 → Mac**：监听 noVNC RFB clipboard 事件

### 防抖机制

- 500ms 防抖：避免短时间内重复触发
- 循环引用检测：防止同步循环

### 容器内部复制粘贴不受影响

- 只拦截浏览器的按键事件
- 容器内部的 Ctrl+C/Ctrl+V 事件不被干扰
- 容器内部复制粘贴仍然使用容器剪贴板

## 文件位置

### 源代码

- `webclaw-docker/configs/custom-clipboard-image.js` - 前端脚本
- `webclaw-docker/configs/clipboard-server.js` - 剪贴板服务
- `webclaw-docker/configs/xsession` - 终端配置（粘贴快捷键）

### 容器内路径

- `/opt/noVNC/custom-clipboard-image.js` - 前端脚本
- `/opt/clipboard-server.js` - 剪贴板服务
- `/opt/xsession` - 终端配置

## 故障排查

### 容器 → Mac 不工作

**症状**：容器内复制文本，Mac 上无法粘贴

**检查**：
1. 浏览器控制台是否有 `[clipboard] 文本剪贴板桥已启用`
2. 浏览器是否允许剪贴板权限（可能需要用户授权）
3. noVNC RFB 是否已连接

### Mac → 容器不工作

**症状**：Mac 上复制文本，noVNC 中按 Ctrl+V 无反应

**检查**：
1. 浏览器控制台是否有 404 错误（`/proxy/10009/api/clipboard-text`）
2. clipboard-server 是否运行：`supervisorctl status clipboard-server`
3. dashboard-server 是否正确代理 10009 端口
4. xclip 是否可用：`echo "test" \| xclip -selection clipboard -target UTF8_STRING -i && xclip -o`

### 需要容器内部复制粘贴不受影响

**原理**：脚本只拦截浏览器的按键事件，不干扰容器内部的 X11 事件。

## 版本历史

- **v1.0** - 基础文本剪贴板同步
  - 支持 Ctrl+V 从 Mac 剪贴板粘贴
  - 支持容器复制自动同步到 Mac
  - 添加 Ctrl+Shift+V 支持

## 相关文档

- [noVNC 官方文档](https://github.com/novnc/noVNC)
- [X11 剪贴板协议](https://www.x.org/releases/X11R7.7/doc/xclip_1.1.0.htm)
