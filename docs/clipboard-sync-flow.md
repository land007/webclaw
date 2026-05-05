# 剪贴板同步数据流向文档

本文档记录 WebClaw Docker 容器中剪贴板同步功能的数据流向、程序调用路线、可能的卡点及解决方案。

## 功能概述

**两个核心按钮**：
- **📋 把本地内容粘到容器**：一键同步本地剪贴板（图片或文字）到容器
- **📥 把容器内容拷到本地**：一键同步容器剪贴板（图片或文字）到本地

**自动同步功能**（保留）：
- 在 noVNC 页面按 Ctrl+V：自动同步本地文字到容器
- 容器内复制文字：自动同步到本地剪贴板

## 简化版数据流向

### 本地 → 容器（点击按钮）

```
浏览器
    │
    ├─ 检查剪贴板：有图片？
    │        │
    │   是 → 上传图片到容器
    │        │
    │        ↓
    │   容器 xclip 把图片塞入剪贴板
    │        │
    │        ↓ (等 300ms)
    │   模拟按键 Ctrl+V
    │        │
    │        ↓
    │   粘贴成功 ✅
    │
    └─ 没图片 → 检查：有文字？
             │
        是 → 上传文字到容器
             │
             ↓
        容器 xclip 把文字塞入剪贴板
             │
             ↓ (等 80ms)
        模拟按键 Ctrl+V
             │
             ↓
        粘贴成功 ✅

        否 → 提示"剪贴板没有内容" ❌
```

### 容器 → 本地（点击按钮）

```
浏览器
    │
    ├─ 请求：容器剪贴板有图片？
    │        │
    │   是 → 下载图片
    │        │
    │        ↓
    │   写入本地剪贴板
    │        │
    │        ↓
    │   拷贝成功 ✅
    │
    └─ 没图片 → 请求：容器剪贴板有文字？
             │
        是 → 下载文字
             │
             ↓
        写入本地剪贴板
             │
             ↓
        拷贝成功 ✅

        否 → 提示"容器剪贴板没有内容" ❌
```

## 程序调用路线

### 本地 → 容器（点击 "把本地内容粘到容器"）

```
用户点击按钮
    ↓
handleMacToContainer()  ← 前端函数 (custom-clipboard-image.js)
    ↓
readImageFromMacClipboard()  ← 检测图片
    │
    ├─ 有图片 → uploadImageToServer()
    │             ↓
    │          POST /api/clipboard-image  ← 发给后端
    │             ↓
    │          clipboard-server.js 接收  ← 后端程序 (端口 10009)
    │             ↓
    │          xclip 写入剪贴板
    │             ↓
    │          返回成功
    │             ↓
    │          等待 300ms
    │             ↓
    │          sendCtrlVToContainer()  ← 模拟按键
    │             ↓
    │          RFB.sendKey()  ← noVNC 发送按键
    │             ↓
    │          容器接收 Ctrl+V ✅
    │
    └─ 没图片 → navigator.clipboard.readText()  ← 读文字
                  ↓
               POST /api/clipboard-text  ← 发给后端
                  ↓
               clipboard-server.js 接收  ← 后端程序
                  ↓
               xclip 写入剪贴板
                  ↓
               返回成功
                  ↓
               等待 80ms
                  ↓
               sendCtrlVToContainer()  ← 模拟按键
                  ↓
               RFB.sendKey()  ← noVNC 发送按键
                  ↓
               容器接收 Ctrl+V ✅
```

### 容器 → 本地（点击 "把容器内容拷到本地"）

```
用户点击按钮
    ↓
handleContainerToMac()  ← 前端函数 (custom-clipboard-image.js)
    ↓
GET /api/clipboard-image  ← 请求后端
    │
    ├─ 有图片 → clipboard-server.js 接收  ← 后端程序
    │             ↓
    │          xclip 读取剪贴板
    │             ↓
    │          返回图片数据
    │             ↓
    │          navigator.clipboard.write()  ← 写入剪贴板
    │             ↓
    │          本地剪贴板更新 ✅
    │
    └─ 没图片 (404) → GET /api/clipboard-text  ← 请求后端
                        ↓
                     clipboard-server.js 接收  ← 后端程序
                        ↓
                     xclip 读取剪贴板
                        ↓
                     返回文字数据
                        ↓
                     navigator.clipboard.writeText()  ← 写入剪贴板
                        ↓
                     本地剪贴板更新 ✅
```

## 涉及的文件

### 前端（浏览器）

| 文件 | 说明 | 是否修改 |
|------|------|---------|
| `webclaw-docker/configs/custom-clipboard-image.js` | 前端脚本，按钮逻辑和 i18n | ✅ 需要修改 |

### 后端（容器内）

| 文件 | 说明 | 是否修改 |
|------|------|---------|
| `webclaw-docker/configs/clipboard-server.js` | Express 服务器 (端口 10009) | ❌ 不需要修改 |
| `webclaw-docker/configs/supervisor-clipboard.conf` | Supervisor 配置 | ❌ 不需要修改 |

### 系统工具

| 工具 | 说明 | 备注 |
|------|------|------|
| `xclip` | Linux 剪贴板命令行工具 | 系统自带，按需调用 |
| `noVNC RFB` | VNC 客户端 | 已有，用于发送按键 |

## 3 个最容易卡住的地方

### 1️⃣ 浏览器剪贴板权限

**为什么**：浏览器安全策略

**什么时候**：没有用 HTTPS 或者不是 localhost

**表现**：拒绝访问、静默失败

**怎么办**：
- 已自动检测（`checkClipboardSupport()` 函数）
- 不支持时不显示按钮
- 用户需要通过 HTTPS 或 localhost 访问

### 2️⃣ 等待时间不够

**为什么**：容器 xclip 需要时间把数据写入剪贴板

**什么时候**：网络慢或容器忙

**表现**：Ctrl+V 发送时剪贴板还没准备好

**怎么办**：
- 图片：等待 300ms
- 文字：等待 80ms
- 代码位置：
  ```javascript
  await uploadImageToServer(imageBlob);
  await new Promise(resolve => setTimeout(resolve, 300));  // 图片
  sendCtrlVToContainer();

  await syncTextToContainer(text);
  setTimeout(sendCtrlVToContainer, 80);  // 文字
  ```

### 3️⃣ 容器剪贴板格式不对

**为什么**：容器里可能既不是图片也不是文字

**什么时候**：剪贴板是空的或者格式不支持

**表现**：读取到空数据或格式不匹配

**怎么办**：
- 图片返回 404 时自动尝试文字
- 文字返回 404 时显示"没有内容"错误
- 代码位置：
  ```javascript
  const resp = await fetch(getClipboardApiUrl(), { method: 'GET' });
  if (resp.status === 404) {
    // 尝试读取文字
    const textResp = await fetch(getClipboardTextApiUrl(), { method: 'GET' });
    // ...
  }
  ```

## 代码修改位置（行号级别）

**文件**：`webclaw-docker/configs/custom-clipboard-image.js`

| 行号 | 函数/区域 | 修改内容 |
|------|----------|---------|
| 20-60 | I18N 定义 | 更新按钮文案（"Mac" → "本地/local"） |
| 204 | `syncTextToContainer()` 后 | 新增 `pasteTextToContainer()` 公共函数 |
| 225-244 | `handleBrowserPaste()` | 重构为调用 `pasteTextToContainer()` |
| 369-404 | `handleMacToContainer()` | 增加文字检测和处理逻辑 |
| 407-433 | `handleContainerToMac()` | 增加文字检测和处理逻辑 |

## 核心逻辑

**本地 → 容器**：
```
检测剪贴板 → 上传 → 等待 → 按 Ctrl+V
```

**容器 → 本地**：
```
请求 → 下载 → 写入剪贴板
```

**关键**：
- 先试图片，没有就试文字
- 都没有才报错
- 不增加新的后台进程或服务
- 所有功能基于现有架构

## 维护要点

1. **不新增程序**：所有需要的服务都已存在（clipboard-server.js、xclip、noVNC RFB）
2. **代码复用**：新增 `pasteTextToContainer()` 公共函数，避免重复
3. **向后兼容**：保留所有现有的自动文字同步功能
4. **时序敏感**：等待时间（图片 300ms、文字 80ms）不能太短
5. **权限检查**：浏览器剪贴板 API 需要 HTTPS 或 localhost

## 故障排查

| 问题 | 可能原因 | 排查步骤 |
|------|---------|---------|
| 按钮不显示 | 浏览器不支持剪贴板 API | 检查是否使用 HTTPS 或 localhost |
| 点击后没反应 | clipboard-server 未启动 | 检查 `docker exec webcode supervisorctl status clipboard` |
| 粘贴失败 | 等待时间不够 | 增加延迟（300ms → 500ms） |
| 权限被拒绝 | 浏览器剪贴板权限未授予 | 在浏览器地址栏左侧允许剪贴板访问 |

## 更新日志

- **2026-05-05**：新增文字支持，按钮从"只支持图片"升级为"自动检测图片或文字"
- 初始版本：仅支持图片同步
