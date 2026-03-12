# Webcode Skills

这个目录包含打包到 Docker 镜像中的 Claude Code skills。

## 已包含的 Skills

### host-ops.skill

允许容器内的 openclaw 操作宿主机的文件系统和执行命令。

**功能：**
- ✅ 执行宿主机 shell 命令
- ✅ 读取/写入/删除宿主机文件
- ✅ 列出宿主机目录内容
- ✅ 获取宿主机系统信息

**使用方法：**

```javascript
// 在容器内的 openclaw 中使用

// 方式 1: 直接使用 skill（推荐）
// host-ops skill 会自动加载，可以直接调用 host 对象的方法

const result = await host.exec('ls -la /Users/jiayiqiu/projects');
console.log(result.stdout);

const content = await host.readFile('/Users/jiayiqiu/projects/myapp/package.json');
await host.writeFile('/Users/jiayiqiu/projects/test.txt', 'Hello from container!');
const files = await host.listDir('/Users/jiayiqiu/projects');
await host.deleteFile('/Users/jiayiqiu/projects/test.txt');
const info = await host.getSystemInfo();

// 方式 2: 手动加载 skill 脚本
const hostModule = require('/opt/skills/host-ops/scripts/host.js');
const result = await hostModule.exec('ls -la /Users/jiayiqiu/projects');
```

**环境变量：**

- `HOST_API_URL`: API 地址，默认 `http://host.docker.internal:30000`
- `HOST_API_TOKEN`: 认证 token，默认 `webcode-host-token-change-me`

**配置：**

在 `docker-compose.yml` 中配置：
```yaml
environment:
  - HOST_API_TOKEN=your-custom-token
extra_hosts:
  - "host.docker.internal:host-gateway"
```

## 添加新 Skill

1. 将 `.skill` 文件放入此目录
2. 重新构建 Docker 镜像
3. skill 会自动复制到容器内的 `/home/ubuntu/.claude/skills/`

```bash
# 复制 skill
cp /path/to/new-skill.skill /Users/jiayiqiu/智能体/webcode/webcode-docker/skills/

# 重新构建
docker build -t webcode .
```
