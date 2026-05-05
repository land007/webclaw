# 一键热部署脚本使用指南

## 什么是热部署？

热部署（Hot Deploy）是指在不需要重新构建 Docker 镜像或重启容器的情况下，将本地修改的脚本快速部署到运行中的容器里。

## 使用场景

- 开发过程中快速测试脚本修改
- 调试安装问题，需要多次修改脚本
- 不想等待漫长的镜像构建过程

## 快速开始

### 基本用法

```bash
# 部署所有脚本到默认容器
./scripts/hot-deploy.sh --all

# 部署所有脚本 + 清理安装状态 + 验证
./scripts/hot-deploy.sh --all --clean --verify
```

### 指定容器

```bash
# 部署到指定容器
./scripts/hot-deploy.sh webclaw-inst-xxx --all

# 查看运行中的容器
docker ps | grep webclaw-inst
```

### 选择性部署

```bash
# 仅部署 Hermes 相关脚本
./scripts/hot-deploy.sh --hermes

# 仅部署 app-launcher
./scripts/hot-deploy.sh --app-launcher

# 仅部署 startup.sh
./scripts/hot-deploy.sh --startup
```

## 常用选项

| 选项 | 说明 |
|------|------|
| `--all` | 部署所有脚本（默认） |
| `--hermes` | 仅部署 Hermes 相关脚本 |
| `--app-launcher` | 仅部署 webclaw-app-launcher |
| `--startup` | 仅部署 startup.sh |
| `--clean` | 清理安装状态（终止进程、清理日志） |
| `--verify` | 部署后验证脚本是否正确部署 |
| `-h, --help` | 显示帮助信息 |

## 典型工作流程

### 场景 1：调试 Hermes 安装问题

```bash
# 1. 修改脚本
vim scripts/install-hermes.sh

# 2. 热部署 + 清理状态
./scripts/hot-deploy.sh --hermes --clean

# 3. 在容器中测试安装
# 双击桌面上的 Hermes 图标
```

### 场景 2：快速验证多个修改

```bash
# 1. 修改多个脚本
vim scripts/install-hermes.sh
vim scripts/webclaw-app-launcher.sh

# 2. 全部部署 + 验证
./scripts/hot-deploy.sh --all --verify

# 3. 查看验证结果，确保所有修改都生效
```

### 场景 3：清理卡住的安装

```bash
# 安装卡住了，先清理状态再重新部署
./scripts/hot-deploy.sh --hermes --clean
```

## 输出说明

脚本使用彩色输出，便于快速识别问题：

- 📍 ℹ️ (蓝色) - 信息提示
- ✅ (绿色) - 操作成功
- ⚠️ (黄色) - 警告信息
- ❌ (红色) - 错误信息

## 验证部署结果

使用 `--verify` 选项会检查：

1. ✅ 脚本文件是否存在且可执行
2. ✅ 脚本是否包含关键特性（如环境变量检测）
3. ✅ 配置文件是否正确
4. ✅ 桌面图标是否正确

## 注意事项

1. **热部署是临时的**：容器重启后会恢复到镜像中的版本
2. **持久化修改**：需要重新构建镜像或提交到 Git
3. **权限问题**：脚本需要 docker 执行权限
4. **容器状态**：容器必须处于运行状态

## 故障排除

### 问题：找不到容器

```bash
# 手动查找容器
docker ps | grep webclaw-inst

# 使用容器 ID
./scripts/hot-deploy.sh <容器ID或名称> --all
```

### 问题：部署失败

```bash
# 检查本地文件是否存在
ls -la scripts/install-hermes.sh

# 检查容器是否运行
docker ps | grep <容器名称>

# 查看详细错误
./scripts/hot-deploy.sh --all 2>&1 | tee deploy.log
```

### 问题：脚本不生效

```bash
# 确认脚本已部署
docker exec <容器> cat /opt/install-hermes.sh | head -20

# 检查文件权限
docker exec <容器> ls -la /opt/install-hermes.sh

# 清理状态后重试
./scripts/hot-deploy.sh --all --clean
```

## 与镜像构建的区别

| 特性 | 热部署 | 镜像构建 |
|------|--------|----------|
| 速度 | 秒级 | 分钟级（5-15分钟） |
| 持久性 | 临时（容器重启后失效） | 永久 |
| 适用场景 | 快速测试 | 生产部署 |
| 依赖 | 需要运行中的容器 | Docker 环境 |

## 示例输出

```
ℹ 使用默认容器: webclaw-inst-xxx
✅ 容器验证通过: webclaw-inst-xxx

╔══════════════════════════════════════════════════════════════╗
║ 开始热部署
╚══════════════════════════════════════════════════════════════╝

ℹ 部署 install-hermes.sh...
✅ 部署成功: install-hermes.sh
ℹ 部署 webclaw-app-launcher.sh...
✅ 部署成功: webclaw-app-launcher.sh

╔══════════════════════════════════════════════════════════════╗
║ 部署总结
╚══════════════════════════════════════════════════════════════╝

✅ 成功部署: 2 个脚本
📦 容器: webclaw-inst-xxx
✅ 热部署完成！
```

## 进阶技巧

### 批量部署到多个容器

```bash
# 获取所有 webclaw 容器
for container in $(docker ps --filter "name=webclaw-inst-" --format "{{.Names}}"); do
    echo "部署到 $container ..."
    ./scripts/hot-deploy.sh "$container" --all
done
```

### 与 Git 钩子结合

在 `.git/hooks/post-commit` 中添加：

```bash
#!/bin/bash
# 提交后自动热部署到测试容器
./scripts/hot-deploy.sh webclaw-inst-test --all --verify
```

### 监控部署日志

```bash
# 部署时实时查看日志
./scripts/hot-deploy.sh --all --clean 2>&1 | tee -a deploy-history.log
```
