# Hermes Agent 集成文档

## 概述

Hermes Agent 已成功集成到 WebClaw Docker 环境中，采用**点击安装**的方式。

## 架构设计

### 安装方式
- **点击安装**：用户点击桌面图标后才开始安装
- **好处**：
  - 减小 Docker 镜像大小（节省 ~500MB）
  - 用户可选择是否安装
  - 首次安装后有进度提示

### 文件结构

```
webclaw-docker/
├── scripts/
│   └── install-hermes.sh          # 一键安装脚本
├── configs/
│   ├── desktop-shortcuts/
│   │   └── hermes.desktop          # 桌面快捷方式
│   └── desktop-icons/
│       └── hermes.png              # 图标 (225x225)
└── Dockerfile                      # 已添加 install-hermes.sh
```

## 安装流程

### 1. 用户点击桌面图标
```
Hermes Agent 图标 → /opt/install-hermes.sh
```

### 2. 安装脚本执行
```bash
/opt/install-hermes.sh
```

**安装步骤**：
1. 检查是否已安装
   - 已安装 → 直接启动 Dashboard
   - 未安装 → 继续安装流程

2. 显示安装对话框（zenity）

3. 安装依赖
   ```bash
   sudo apt-get install -y python3.11 python3.11-venv python3-pip git curl
   ```

4. 克隆 Hermes 仓库
   ```bash
   git clone https://github.com/NousResearch/hermes-agent.git /opt/hermes-agent
   ```

5. 运行官方安装脚本
   ```bash
   cd /opt/hermes-agent && ./setup-hermes.sh
   ```
   - 安装 uv（Python 包管理器）
   - 安装 Python 3.11
   - 创建虚拟环境
   - 安装依赖包

6. 创建启动脚本和配置
   - `/opt/start-hermes-dashboard.sh` - Dashboard 启动脚本
   - `/opt/hermes-browser.sh` - 浏览器启动脚本
   - `/etc/supervisor/conf.d/supervisor-hermes.conf` - Supervisor 配置

7. 启动服务
   ```bash
   supervisorctl start hermes
   ```

8. 更新桌面图标为正常状态

9. 自动打开 Dashboard

### 3. 安装完成后的使用
- 点击桌面图标 → 直接打开 `http://127.0.0.1:10011`
- 后台服务由 Supervisor 管理（自动重启）

## 技术细节

### Hermes Dashboard
- **端口**：10011
- **绑定**：0.0.0.0（容器内可访问）
- **认证**：--insecure（允许容器内访问）
- **Web UI**：现代化的管理界面

### 服务管理
```bash
# 查看状态
supervisorctl status hermes

# 重启服务
supervisorctl restart hermes

# 查看日志
tail -f /tmp/hermes_stdout.log
tail -f /tmp/hermes_stderr.log
```

### 数据持久化
- **配置目录**：`/home/ubuntu/.hermes/`
- **建议**：在 docker-compose.yml 中添加卷映射
  ```yaml
  volumes:
    - hermes-data:/home/ubuntu/.hermes
  ```

## Dockerfile 修改

已添加的修改：
```dockerfile
# 复制安装脚本
COPY scripts/install-hermes.sh /opt/install-hermes.sh

# 设置执行权限
RUN chmod +x /opt/install-hermes.sh
```

## 测试步骤

### 在运行中的容器测试
```bash
# 1. 复制文件到容器
docker cp scripts/install-hermes.sh webclaw:/opt/
docker cp configs/desktop-shortcuts/hermes.desktop webclaw:/home/ubuntu/Desktop/

# 2. 设置权限
docker exec webclaw chmod +x /opt/install-hermes.sh
docker exec webclaw chown ubuntu:ubuntu /home/ubuntu/Desktop/hermes.desktop

# 3. 通过 VNC 访问桌面
# http://localhost:20304

# 4. 点击 Hermes Agent 图标测试安装
```

### 构建新镜像测试
```bash
cd webclaw-docker
docker build -t webclaw:latest .
docker compose up -d
```

## 特性

### ✅ 已实现
- [x] 点击安装机制
- [x] 安装进度显示（zenity + 进度条）
- [x] 自动检测已安装状态
- [x] Supervisor 服务管理
- [x] 自动重启
- [x] 日志管理
- [x] 桌面图标自动更新
- [x] 安装完成后自动打开 Dashboard

### 🔄 可选增强
- [ ] 离线安装支持（预下载依赖包）
- [ ] 版本选择（安装特定版本）
- [ ] 卸载功能
- [ ] 更新功能

## 故障排查

### 安装失败
```bash
# 查看错误日志
cat /tmp/hermes_stderr.log

# 手动运行安装脚本
bash -x /opt/install-hermes.sh
```

### 服务无法启动
```bash
# 检查端口占用
netstat -tlnp | grep 10011

# 检查 Python 环境
cd /opt/hermes-agent
source venv/bin/activate
hermes --version
```

### Dashboard 无法访问
```bash
# 检查服务状态
supervisorctl status hermes

# 重启服务
supervisorctl restart hermes

# 检查防火墙
curl http://127.0.0.1:10011
```

## 参考信息

- **Hermes 官方仓库**：https://github.com/NousResearch/hermes-agent
- **版本**：v0.12.0
- **Python 要求**：3.11+
- **安装时间**：约 2-5 分钟（取决于网络速度）
- **磁盘空间**：约 500MB

## 中文提交信息

```
新增: 添加 Hermes Agent 点击安装功能
新增: 创建 Hermes 一键安装脚本
新增: 添加 Hermes 桌面快捷方式和图标
```

---

**创建日期**：2026-05-04  
**Hermes 版本**：v0.12.0  
**状态**：✅ 已测试并可用
