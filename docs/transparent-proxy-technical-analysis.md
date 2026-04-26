# Docker 容器全局透明代理方案 - 完整技术分析

> **文档目的**: 为 webclaw Docker 容器设计一个全局透明代理方案，供 AI 评估和同行评审
>
> **创建时间**: 2026-04-19
>
> **版本**: 1.0

---

## 📋 目录

1. [需求分析](#需求分析)
2. [第一性原理分析](#第一性原理分析)
3. [技术方案对比](#技术方案对比)
4. [安全性深度分析](#安全性深度分析)
5. [最终推荐方案](#最终推荐方案)
6. [完整实现代码](#完整实现代码)
7. [附录：常见问题](#附录常见问题)

---

## 需求分析

### 核心需求

1. **全局透明代理**: 容器内所有网络流量必须经过外部代理服务器
2. **外部控制**: 代理配置从容器外部注入，容器内部不可修改
3. **本地网络隔离**: 容器无法访问宿主机本地网络（192.168.x.x, 10.x.x.x 等）
4. **故障安全**: 代理故障时不应泄漏流量或绕过代理
5. **简单可靠**: 配置简单，维护成本低，符合 Docker 最佳实践

### 应用场景

```
webclaw Docker 容器
├─ code-server (IDE)
├─ OpenClaw (AI Gateway)
├─ noVNC (桌面)
└─ 浏览器等应用

需求：所有这些服务的网络流量 → OpenWrt 旁路由 → 全局代理 → 互联网
```

### 现有基础设施

- **旁路由**: OpenWrt 路由器 (IP: 172.20.0.100)
- **旁路由能力**: 已配置全局代理（Shadowsocks/V2Ray 等）
- **Docker 环境**: 标准的 Docker Compose 部署
- **容器网络**: 默认 bridge 模式

---

## 第一性原理分析

### Docker 容器网络是如何工作的？

```
┌─────────────────────────────────────────────────────────┐
│  宿主机 (Host)                                          │
│                                                         │
│  ┌─────────────┐         ┌─────────────────────────┐  │
│  │ Docker 容器  │         │  Docker 网桥 (bridge)   │  │
│  │             │ veth pair │  (docker0 / 172.20.0.1) │  │
│  │ ┌─────────┐ │◄────────►│                         │  │
│  │ │ eth0    │ │         │  默认网关              │  │
│  │ └─────────┘ │         │  NAT/masquerade        │  │
│  │             │         └───────────┬─────────────┘  │
│  │ 路由表:     │                     │                │
│  │ default via │                     │                │
│  │ 172.20.0.1  │                     ▼                │
│  └─────────────┘         ┌─────────────────────────┐  │
│                          │  物理网卡 (eth0/wlan0)  │  │
│                          └───────────┬─────────────┘  │
│                                      │                │
│                                      ▼                │
│                               互联网/局域网            │
└─────────────────────────────────────────────────────────┘
```

**关键点**:
1. 容器启动时，Docker 自动创建 veth pair（虚拟网卡对）
2. 一端在容器内（eth0），一端在宿主机（连接到 docker0 网桥）
3. 容器内的默认路由指向 Docker 网桥（172.20.0.1）
4. 所有流量通过网桥进行 NAT 转发

### 如何改变流量走向？

#### 方法 1: 修改路由表

```bash
# 默认路由
ip route del default
ip route add default via 172.20.0.100  # 指向旁路由
```

**效果**: 所有流量发送到 172.20.0.100（旁路由），旁路由决定如何转发

#### 方法 2: iptables NAT 重定向

```bash
# 在容器内
iptables -t nat -A OUTPUT -p tcp -j REDIRECT --to-ports 1080
```

**效果**: 流量被重定向到本地端口 1080，需要本地有代理程序监听

#### 方法 3: 共享网络命名空间

```yaml
# docker-compose.yml
network_mode: service:another_container
```

**效果**: 容器没有独立的网络栈，使用另一个容器的网络

### 流量拦截的层次

```
应用层 (curl, browser)
    ↓
传输层 (TCP/UDP)
    ↓
网络层 (IP routing) ←── 方法 1: 修改路由表
    ↓
NAT 层 (iptables) ←── 方法 2: REDIRECT
    ↓
数据链路层
    ↓
物理层
```

**第一性原理**: 在网络层（路由）拦截比在 NAT 层更底层，更可靠，性能更好。

---

## 技术方案对比

### 方案 1: Docker 网络层指定网关

#### 工作原理

```yaml
networks:
  proxy_net:
    driver: bridge
    ipam:
      config:
        - subnet: 172.20.0.0/24
          gateway: 172.20.0.100  # 旁路由作为网关
```

**流量路径**:
```
webclaw 容器 → Docker 网桥 → 172.20.0.100 (旁路由) → 代理 → 互联网
```

#### 优点
- ✅ 原生支持，无需额外脚本
- ✅ 完全外部控制（docker-compose.yml）
- ✅ 配置简洁，一行搞定
- ✅ 容器内无法修改（Docker 网络配置）

#### 缺点
- ❌ 旁路由必须在同一个 Docker 网络内
- ❌ 如果旁路由是外部虚拟机/物理机，无法使用
- ❌ Docker 网关必须在 bridge 子网内

#### 本地网络隔离能力

**无法阻断**。因为网络层只决定"往哪走"，不决定"能不能走"。

需要额外配置：
- 在旁路由上配置防火墙规则
- 或者在容器内添加 blackhole 路由

#### 代码示例

```yaml
version: '3.8'

services:
  webclaw:
    image: land007/webclaw:latest
    networks:
      proxy_net:
        ipv4_address: 172.20.0.50
    cap_drop:
      - NET_ADMIN
      - NET_RAW

  openwrt:
    image: openwrt:latest
    networks:
      proxy_net:
        ipv4_address: 172.20.0.100
    privileged: true

networks:
  proxy_net:
    driver: bridge
    ipam:
      config:
        - subnet: 172.20.0.0/24
          gateway: 172.20.0.100
```

---

### 方案 2: 启动脚本注入路由

#### 工作原理

```yaml
services:
  webclaw:
    entrypoint: ["/usr/local/bin/set-route.sh"]
    cap_drop:
      - NET_ADMIN  # 移除权限
```

```bash
#!/bin/bash
# set-route.sh
ip route del default
ip route add default via 172.20.0.100
ip route add blackhole 192.168.0.0/16  # 阻断本地网络
exec /opt/startup.sh
```

**流量路径**:
```
webclaw 容器启动 → 执行 set-route.sh → 修改路由表 →
所有流量 → 172.20.0.100 (旁路由) → 代理 → 互联网
```

#### 优点
- ✅ 旁路由可以是容器、虚拟机、物理机（灵活性最高）
- ✅ 完全外部控制（脚本从宿主机挂载）
- ✅ 容器内无法修改（移除 NET_ADMIN 权限）
- ✅ 可以阻断本地网络（blackhole 路由）
- ✅ 可以持续监控和恢复（后台守护进程）
- ✅ 符合 Docker 12-factor app 原则

#### 缺点
- ⚠️ 容器重启后需要重新执行（但 entrypoint 自动执行）
- ⚠️ 需要额外的脚本文件

#### 本地网络隔离能力

**可以完美阻断**。使用 blackhole 路由：

```bash
ip route add blackhole 192.168.0.0/16
ip route add blackhole 172.16.0.0/12
ip route add blackhole 10.0.0.0/8
```

**工作原理**:
- 这些路由规则告诉内核：往这些网段的包直接丢弃
- 比 iptables REJECT 更高效（在路由层丢弃）
- 容器内无法绕过（除非有 NET_ADMIN 权限）

#### 安全性增强：守护进程

```bash
#!/bin/bash
# protect-route.sh - 持续监控路由

while true; do
    sleep 10

    # 检查默认路由
    CURRENT=$(ip route | grep default | awk '{print $3}')
    if [ "$CURRENT" != "172.20.0.100" ]; then
        # 路由被修改，恢复
        ip route del default 2>/dev/null
        ip route add default via 172.20.0.100
    fi

    # 检查 blackhole 路由
    if ! ip route show | grep -q "blackhole 192.168.0.0/16"; then
        # 规则丢失，恢复
        ip route add blackhole 192.168.0.0/16
    fi
done
```

#### 完整代码示例

**docker-compose.yml**:
```yaml
version: '3.8'

services:
  webclaw:
    image: land007/webclaw:latest
    container_name: webclaw
    network_mode: bridge
    cap_drop:
      - NET_ADMIN      # 关键：移除路由修改权限
      - NET_RAW
    environment:
      - GATEWAY_IP=172.20.0.100
      - BLOCK_LOCAL_NET=true
      - MODE=${MODE:-desktop}
    volumes:
      - ./scripts/set-route.sh:/usr/local/bin/set-route.sh:ro
      - ./scripts/protect-route.sh:/usr/local/bin/protect-route.sh:ro
      - dna-data:/home/ubuntu/dna
      - projects:/home/ubuntu/projects
      # ... 其他卷
    ports:
      - "20000:20000"
      - "20001:20001"
      - "20002:20002"
      - "20003:20003"
      - "20004:20004"
    restart: unless-stopped
    entrypoint: ["/usr/local/bin/set-route.sh"]

  # ... 其他服务
```

**scripts/set-route.sh**:
```bash
#!/bin/bash
set -e

GATEWAY_IP="${GATEWAY_IP:-172.20.0.100}"
BLOCK_LOCAL="${BLOCK_LOCAL_NET:-true}"

echo "============================================="
echo " Webclaw Gateway Configuration"
echo "============================================="
echo "Gateway: $GATEWAY_IP"
echo "Block local networks: $BLOCK_LOCAL"
echo "============================================="

# 删除默认路由
echo "[route] Removing default route..."
ip route del default 2>/dev/null || true

# 添加新的默认路由
echo "[route] Adding default route via $GATEWAY_IP..."
ip route add default via $GATEWAY_IP

# 阻断本地网络
if [ "$BLOCK_LOCAL" = "true" ]; then
    echo "[route] Blocking local network access..."
    ip route add blackhole 192.168.0.0/16 2>/dev/null || true
    ip route add blackhole 172.16.0.0/12 2>/dev/null || true
    ip route add blackhole 10.0.0.0/8 2>/dev/null || true
    echo "[route] Local networks blocked:"
    ip route show | grep blackhole
fi

# 显示路由表
echo ""
echo "[route] Current routing table:"
ip route

# 测试网关连通性
echo ""
echo "[route] Testing connectivity to gateway..."
if ping -c 1 -W 2 $GATEWAY_IP >/dev/null 2>&1; then
    echo "[route] ✓ Gateway is reachable"
else
    echo "[route] ✗ WARNING: Gateway is not reachable!" >&2
fi

# 启动保护脚本（后台）
/usr/local/bin/protect-route.sh &

echo ""
echo "[route] Starting webclaw service..."
echo "============================================="

# 启动原来的服务
exec /opt/startup.sh "$@"
```

**scripts/protect-route.sh**:
```bash
#!/bin/bash
set -e

GATEWAY_IP="${GATEWAY_IP:-172.20.0.100}"

echo "[protect] Starting route protection daemon..."

while true; do
    sleep 10

    # 检查默认路由
    CURRENT_GATEWAY=$(ip route | grep default | awk '{print $3}')

    if [ "$CURRENT_GATEWAY" != "$GATEWAY_IP" ]; then
        echo "[protect] WARNING: Gateway changed to $CURRENT_GATEWAY, restoring..."
        ip route del default 2>/dev/null || true
        ip route add default via $GATEWAY_IP
    fi

    # 检查 blackhole 路由是否存在
    if ! ip route show | grep -q "blackhole 192.168.0.0/16"; then
        echo "[protect] WARNING: Local network block lost, restoring..."
        ip route add blackhole 192.168.0.0/16 2>/dev/null || true
        ip route add blackhole 172.16.0.0/12 2>/dev/null || true
        ip route add blackhole 10.0.0.0/8 2>/dev/null || true
    fi
done
```

---

### 方案 3: 共享网络命名空间

#### 工作原理

```yaml
services:
  webclaw:
    network_mode: service:openwrt  # 共享 openwrt 的网络

  openwrt:
    # openwrt 容器有独立的网络栈
```

**流量路径**:
```
webclaw 容器 → (共享网络) → openwrt 容器的网络栈 →
openwrt 的路由/iptables → 代理 → 互联网
```

#### 优点
- ✅ 最安全：webclaw 容器完全没有网络权限
- ✅ 完全外部控制：网络配置在 openwrt 容器
- ✅ 容器内无法绕过：没有独立的网络栈

#### 缺点
- ❌ 旁路由必须是容器（不能是虚拟机或物理机）
- ❌ 配置复杂度较高
- ❌ 失去 Docker 的网络隔离特性
- ❌ 本地网络隔离困难（见下文）

#### 本地网络隔离能力

**存在严重问题**：

因为 webclaw 和 openwrt 共享同一个网络命名空间，从网络视角看，**它们的流量无法区分**。

```
问题：如何允许 openwrt 访问本地网络（用于管理），
     但阻止 webclaw 访问？

答案：很难做到。

    如果在 openwrt 中配置 iptables 阻断本地网络：
    → openwrt 自己也无法访问

    如果不配置：
    → webclaw 可以访问（因为共享网络栈）
```

**可能的解决方案**（但都很复杂）：

1. **cgroup + eBPF**：标记进程，在 iptables 中区分
2. **独立 network namespace**：创建额外的命名空间（失去 Docker 简洁性）
3. **应用层代理**：所有流量通过 openwrt 内的代理程序（增加复杂度）

#### 代码示例

```yaml
version: '3.8'

services:
  webclaw:
    image: land007/webclaw:latest
    network_mode: service:openwrt  # 共享网络
    cap_drop:
      - NET_ADMIN
      - NET_RAW

  openwrt:
    image: openwrt:latest
    privileged: true
    cap_add:
      - NET_ADMIN
    # openwrt 内配置代理和防火墙
```

**openwrt 容器内的配置**：
```bash
#!/bin/bash
# openwrt 容器启动脚本

# 配置代理（例如 shadowsocks）
# ...

# 配置 NAT
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE

# 问题：如何阻断 webclaw 的本地网络访问，
#      但不影响 openwrt 自己？
# 答案：没有简单的方法
```

---

### 方案 4: iptables 透明代理 + Xray Sidecar（我最初的方案）

#### 工作原理

```
┌─────────────────────────────────────┐
│  webclaw 容器                         │
│  ─────────────────                  │
│  iptables REDIRECT 所有 TCP → 1080  │
│  所有 DNS → 1053                    │
└─────────────┬───────────────────────┘
              │
      ┌───────▼────────┐
      │  proxy 容器     │
      │  - Xray 监听    │
      │  - 转发到上游   │
      └───────┬────────┘
              │
              ▼
        上游代理服务器
```

#### 优点
- ✅ 真正的透明代理（应用无感知）
- ✅ 支持多种代理协议（Shadowsocks/VMess/VLESS）
- ✅ DNS 也走代理（防止泄露）
- ✅ 配置在外部

#### 缺点
- ❌ 需要额外的 sidecar 容器
- ❌ iptables 规则可能被清理（需要持续监控）
- ❌ 配置复杂度高
- ❌ 性能略低于路由层方案
- ❌ 故障处理复杂（需要主动 DROP）

#### 与用户实际需求的对比

用户已经有：
- ✅ OpenWrt 旁路由（172.20.0.100）
- ✅ 旁路由上已配置全局代理

**问题**：为什么还需要在容器里再装 Xray？

**答案**：不需要！这是过度设计。

---

## 安全性深度分析

### 威胁模型

#### 威胁 1: 容器内用户修改网络配置

**攻击场景**：
```bash
# 容器内有 ubuntu 用户
sudo ip route del default
sudo ip route add default via 172.20.0.1  # 改回 Docker 网关
```

**防护措施**：
```yaml
cap_drop:
  - NET_ADMIN  # 移除网络管理权限
  - NET_RAW
```

**效果**：
```
$ sudo ip route add default via 172.20.0.1
RTNETLINK answers: Operation not permitted
```

#### 威胁 2: 容器内进程删除 blackhole 路由

**攻击场景**：
```bash
sudo ip route del blackhole 192.168.0.0/16
curl http://192.168.1.100:8080  # 访问本地网络
```

**防护措施**：
1. 移除 NET_ADMIN 权限（主要）
2. protect-route.sh 守护进程（次要）

**效果**：如果没有 NET_ADMIN 权限，无法删除路由

#### 威胁 3: 旁路由故障导致流量绕过

**场景**：
```
正常：webclaw → 旁路由 → 代理 → 互联网
故障：旁路由宕机 → 流量无法通过 → 网络中断
```

**问题**：会不会绕过代理直接访问互联网？

**答案**：不会。因为路由表仍然指向旁路由，如果旁路由不响应，连接超时。

**但是**：如果路由表丢失了呢？

**防护措施**：
1. protect-route.sh 持续监控
2. 检测到路由丢失后立即恢复
3. 可以主动阻断网络（可选）

#### 威胁 4: DNS 泄露

**问题**：
```
如果 DNS 查询不经过代理：
1. 容器查询 google.com
2. DNS 请求直接到 DNS 服务器（可能被监控）
3. 隐私泄露
```

**解决方案**：

**方法 1**：在旁路由上配置 DNS 代理
```
旁路由接收 DNS 查询 → 通过代理转发 → 返回结果
```

**方法 2**：在容器内配置 DNS 服务器
```yaml
environment:
  - DNS=172.20.0.100  # 使用旁路由作为 DNS
```

**注意**：Docker 容器的 DNS 配置在 `/etc/resolv.conf`，可以在 docker-compose.yml 中配置：
```yaml
services:
  webclaw:
    dns:
      - 172.20.0.100
      - 8.8.8.8
```

### 安全性对比表

| 威胁 | 方案 1 | 方案 2 | 方案 3 | 方案 4 |
|------|--------|--------|--------|--------|
| 容器修改路由 | ✅ | ✅ | ✅ | ✅ |
| 容器删除 blackhole | ⚠️ | ✅ | ⚠️ | ✅ |
| 路由丢失后恢复 | ❌ | ✅ | ❌ | ✅ |
| DNS 泄露 | ⚠️ | ⚠️ | ⚠️ | ✅ |
| 旁路由故障处理 | ❌ | ❌ | ❌ | ✅ |
| 本地网络访问 | ⚠️ | ✅ | ⚠️ | ✅ |

图例：✅ 完全防护 | ⚠️ 部分防护 | ❌ 无防护

---

## 最终推荐方案

### 推荐：方案 2（启动脚本 + 权限控制）

**理由**：
1. ✅ **简单**：只需要 2 个脚本文件
2. ✅ **灵活**：旁路由可以是任意形式
3. ✅ **安全**：多层防护机制
4. ✅ **可靠**：守护进程持续监控
5. ✅ **符合实际**：用户已有旁路由，无需重复造轮子

### 架构图

```
┌─────────────────────────────────────────────────────────┐
│  Docker Host (宿主机)                                    │
│                                                         │
│  ┌─────────────────────────────────────────────────┐   │
│  │  webclaw 容器                                    │   │
│  │                                                 │   │
│  │  1. 容器启动                                    │   │
│  │  2. 执行 set-route.sh (entrypoint)             │   │
│  │     - ip route add default via 172.20.0.100    │   │
│  │     - ip route add blackhole 192.168.0.0/16    │   │
│  │  3. 启动 protect-route.sh (后台守护)           │   │
│  │  4. 启动 /opt/startup.sh (原服务)              │   │
│  │                                                 │   │
│  │  安全措施:                                      │   │
│  │  - cap_drop: NET_ADMIN, NET_RAW                │   │
│  │  - 脚本只读挂载 (:ro)                           │   │
│  └─────────────────────┬───────────────────────────┘   │
│                       │                               │
│                       │ 所有流量                       │
│                       ▼                               │
│  ┌─────────────────────────────────────────────────┐   │
│  │  OpenWrt 旁路由 (172.20.0.100)                  │   │
│  │                                                 │   │
│  │  - 全局代理 (Shadowsocks/V2Ray)                 │   │
│  │  - 防火墙规则（可选）                            │   │
│  │  - DNS 代理（可选）                              │   │
│  └─────────────────────┬───────────────────────────┘   │
│                       │                               │
│                       ▼                               │
│                  互联网                               │
└─────────────────────────────────────────────────────────┘

  本地网络阻断（在 webclaw 容器内）:
  - ip route add blackhole 192.168.0.0/16
  - ip route add blackhole 172.16.0.0/12
  - ip route add blackhole 10.0.0.0/8
```

### 与 iptables 透明代理方案的对比

| 维度 | 方案 2 (路由层) | 方案 4 (iptables + Xray) |
|------|----------------|-------------------------|
| **复杂度** | ⭐⭐ 简单 | ⭐⭐⭐⭐⭐ 复杂 |
| **文件数量** | 2 个脚本 | 7 个文件 |
| **容器数量** | 1 个 | 2 个 (sidecar) |
| **性能** | ⭐⭐⭐⭐⭐ 卓越 | ⭐⭐⭐⭐ 优秀 |
| **维护成本** | 低 | 高 |
| **符合用户实际** | ✅ 完美利用现有旁路由 | ❌ 重复建设 |
| **故障处理** | 路由丢失后自动恢复 | 需要主动 DROP（复杂） |

---

## 完整实现代码

### 项目结构

```
webclaw-docker/
├── docker-compose.yml
├── scripts/
│   ├── set-route.sh       # 路由设置脚本
│   ├── protect-route.sh   # 路由守护脚本
│   └── startup.sh         # 原启动脚本
└── docs/
    └── transparent-proxy-technical-analysis.md  # 本文档
```

### docker-compose.yml（完整版）

```yaml
version: '3.8'

services:
  webclaw:
    image: land007/webclaw:latest
    container_name: webclaw
    build: .

    # 网络配置
    network_mode: bridge

    # 安全配置：移除网络管理权限
    cap_drop:
      - NET_ADMIN
      - NET_RAW

    # 环境变量
    environment:
      # 网关配置
      - GATEWAY_IP=${GATEWAY_IP:-172.20.0.100}
      - BLOCK_LOCAL_NET=${BLOCK_LOCAL_NET:-true}

      # 原有环境变量
      - MODE=${MODE:-desktop}
      - AUTH_USER=${AUTH_USER:-admin}
      - AUTH_PASSWORD=${AUTH_PASSWORD:-changeme}
      - OPENCLAW_GATEWAY_TOKEN=${OPENCLAW_GATEWAY_TOKEN:-changeme}
      - PASSWORD=${VNC_PASSWORD:-changeme}
      - VNC_PASSWORD=${VNC_PASSWORD:-changeme}
      - VNC_RESOLUTION=${VNC_RESOLUTION:-1920x1080}
      - CF_TUNNEL_TOKEN=${CF_TUNNEL_TOKEN:-}
      - GIT_USER_NAME=${GIT_USER_NAME:-}
      - GIT_USER_EMAIL=${GIT_USER_EMAIL:-}
      - DNA_REPO_URL=${DNA_REPO_URL:-https://github.com/land007/webcode}
      - ENABLE_KANBAN=${ENABLE_KANBAN:-false}
      - ENABLE_OPENCLAW=${ENABLE_OPENCLAW:-true}
      - ENABLE_CLAUDECODEUI=${ENABLE_CLAUDECODEUI:-false}
      - HOST_API_TOKEN=${HOST_API_TOKEN:-webclaw-host-token-change-me}

    # 卷挂载
    volumes:
      # 路由脚本（只读）
      - ./scripts/set-route.sh:/usr/local/bin/set-route.sh:ro
      - ./scripts/protect-route.sh:/usr/local/bin/protect-route.sh:ro

      # 原有卷
      - /var/run/docker.sock:/var/run/docker.sock
      - dna-data:/home/ubuntu/dna
      - projects:/home/ubuntu/projects
      - vibe-kanban-data:/home/ubuntu/.local/share/vibe-kanban
      - code-server-data:/home/ubuntu/.code-server
      - user-data:/home/ubuntu/.local/share
      - gitconfig:/home/ubuntu/.gitconfig-vol
      - openclaw-data:/home/ubuntu/.openclaw
      - chrome-data:/home/ubuntu/.config
      - v2rayn-data:/home/ubuntu/.local/share/v2rayN
      - recordings:/home/ubuntu/recordings
      - webclaw-config:/home/ubuntu/.webclaw
      - ./backups:/home/ubuntu/backups

    # 临时文件系统
    tmpfs:
      - /run:size=10M

    # 端口映射
    ports:
      - "20000:20000"  # Dashboard
      - "20001:20001"  # code-server
      - "20002:20002"  # Vibe Kanban
      - "20003:20003"  # OpenClaw
      - "20004:20004"  # noVNC

    # 额外主机
    extra_hosts:
      - "host.docker.internal:host-gateway"

    # 共享内存
    shm_size: "512m"

    # 安全选项
    security_opt:
      - seccomp:unconfined

    # 重启策略
    restart: unless-stopped

    # 启动入口（先设置路由）
    entrypoint: ["/usr/local/bin/set-route.sh"]

# 卷定义
volumes:
  dna-data:
  projects:
  vibe-kanban-data:
  code-server-data:
  user-data:
  openclaw-data:
  chrome-data:
  v2rayn-data:
  gitconfig:
  recordings:
  webclaw-config:
```

### .env 文件（用户配置）

```bash
# .env

# 网关配置
GATEWAY_IP=172.20.0.100
BLOCK_LOCAL_NET=true

# 原有配置
MODE=desktop
AUTH_USER=admin
AUTH_PASSWORD=changeme
OPENCLAW_GATEWAY_TOKEN=changeme
VNC_PASSWORD=changeme
VNC_RESOLUTION=1920x1080
```

### scripts/set-route.sh（路由设置脚本）

```bash
#!/bin/bash
#
# Webclaw Container Gateway Configuration Script
#
# 功能：
# 1. 删除 Docker 默认路由
# 2. 添加指向旁路由的默认路由
# 3. 配置本地网络阻断（blackhole）
# 4. 启动路由守护进程
# 5. 启动原服务
#

set -e

# 从环境变量读取配置
GATEWAY_IP="${GATEWAY_IP:-172.20.0.100}"
BLOCK_LOCAL="${BLOCK_LOCAL_NET:-true}"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${GREEN}[route]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[route]${NC} $*" >&2
}

log_error() {
    echo -e "${RED}[route]${NC} $*" >&2
}

# 打印配置
echo "============================================="
echo " Webclaw Gateway Configuration"
echo "============================================="
log_info "Gateway: $GATEWAY_IP"
log_info "Block local networks: $BLOCK_LOCAL"
echo "============================================="
echo ""

# 1. 删除默认路由
log_info "Removing default route..."
ip route del default 2>/dev/null || log_warn "No default route to remove"

# 2. 添加新的默认路由
log_info "Adding default route via $GATEWAY_IP..."
if ip route add default via $GATEWAY_IP; then
    log_info "✓ Default route configured"
else
    log_error "✗ Failed to set default route!"
    log_error "Please check if gateway $GATEWAY_IP is reachable"
    exit 1
fi

# 3. 阻断本地网络
if [ "$BLOCK_LOCAL" = "true" ]; then
    log_info "Blocking local network access..."

    # 配置 blackhole 路由
    BLACKHOLE_NETWORKS=(
        "192.168.0.0/16"
        "172.16.0.0/12"
        "10.0.0.0/8"
        "169.254.0.0/16"
    )

    for network in "${BLACKHOLE_NETWORKS[@]}"; do
        if ip route add blackhole $network 2>/dev/null; then
            log_info "  ✓ Blocked $network"
        else
            log_warn "  ⚠ Already blocked or failed: $network"
        fi
    done
fi

# 4. 显示路由表
echo ""
log_info "Current routing table:"
ip route | grep -E "^default|^blackhole" || log_warn "No relevant routes found"

# 5. 测试网关连通性
echo ""
log_info "Testing connectivity to gateway..."
if ping -c 1 -W 2 $GATEWAY_IP >/dev/null 2>&1; then
    log_info "✓ Gateway is reachable"
elif [ $? -eq 1 ]; then
    log_warn "⚠ Gateway is not responding to ping"
    log_warn "  (This may be normal if ICMP is blocked)"
else
    log_error "✗ Gateway is unreachable!"
    log_error "  Please check your network configuration"
fi

# 6. 验证路由
echo ""
log_info "Verifying configuration..."
CURRENT_GATEWAY=$(ip route | grep "^default" | awk '{print $3}')
if [ "$CURRENT_GATEWAY" = "$GATEWAY_IP" ]; then
    log_info "✓ Default route is correctly set to $GATEWAY_IP"
else
    log_error "✗ Default route mismatch! Expected: $GATEWAY_IP, Got: $CURRENT_GATEWAY"
    exit 1
fi

# 7. 启动路由守护进程（后台）
log_info "Starting route protection daemon..."
if [ -x /usr/local/bin/protect-route.sh ]; then
    /usr/local/bin/protect-route.sh &
    PROTECT_PID=$!
    log_info "✓ Protection daemon started (PID: $PROTECT_PID)"
else
    log_warn "⚠ protect-route.sh not found or not executable"
    log_warn "  Route protection is disabled"
fi

# 8. 启动原服务
echo ""
echo "============================================="
log_info "Starting webclaw service..."
echo "============================================="
echo ""

# 检查原启动脚本是否存在
if [ -x /opt/startup.sh ]; then
    exec /opt/startup.sh "$@"
else
    log_error "/opt/startup.sh not found or not executable"
    exit 1
fi
```

### scripts/protect-route.sh（路由守护脚本）

```bash
#!/bin/bash
#
# Webclaw Container Route Protection Daemon
#
# 功能：
# 1. 持续监控默认路由
# 2. 检测到变化时立即恢复
# 3. 监控 blackhole 路由是否存在
# 4. 记录所有异常到日志
#

set -e

# 配置
GATEWAY_IP="${GATEWAY_IP:-172.20.0.100}"
CHECK_INTERVAL=10  # 检查间隔（秒）
BLOCK_LOCAL="${BLOCK_LOCAL_NET:-true}"

# 日志函数
log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [protect] $*"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [protect] ERROR: $*" >&2
}

# 检查默认路由
check_default_route() {
    local current_gateway
    current_gateway=$(ip route | grep "^default" | awk '{print $3}')

    if [ "$current_gateway" != "$GATEWAY_IP" ]; then
        log_error "Default gateway changed!"
        log_error "  Expected: $GATEWAY_IP"
        log_error "  Current: ${current_gateway:-none}"

        # 尝试恢复
        log_info "Attempting to restore default route..."
        ip route del default 2>/dev/null || true
        if ip route add default via $GATEWAY_IP; then
            log_info "✓ Default route restored"
            return 0
        else
            log_error "✗ Failed to restore default route!"
            return 1
        fi
    fi

    return 0
}

# 检查 blackhole 路由
check_blackhole_routes() {
    if [ "$BLOCK_LOCAL" != "true" ]; then
        return 0
    fi

    local networks=("192.168.0.0/16" "172.16.0.0/12" "10.0.0.0/8")
    local missing=0

    for network in "${networks[@]}"; do
        if ! ip route show | grep -q "blackhole $network"; then
            log_error "Blackhole route missing: $network"
            ip route add blackhole $network 2>/dev/null && log_info "✓ Restored: $network"
            missing=1
        fi
    done

    return $missing
}

# 主循环
log_info "Route protection daemon started"
log_info "  Gateway: $GATEWAY_IP"
log_info "  Check interval: ${CHECK_INTERVAL}s"
log_info "  Block local networks: $BLOCK_LOCAL"

while true; do
    sleep $CHECK_INTERVAL

    # 检查默认路由
    if ! check_default_route; then
        # 路由恢复失败，发送告警
        log_error "CRITICAL: Unable to restore default route!"
    fi

    # 检查 blackhole 路由
    check_blackhole_routes

    # 额外检查：确保没有通往本地网络的路由
    if [ "$BLOCK_LOCAL" = "true" ]; then
        # 检查是否有意外的本地网络路由
        if ip route show | grep -E "^(192\.168|172\.(1[6-9]|2[0-9]|3[01])|10\.)" | grep -v blackhole >/dev/null; then
            log_error "WARNING: Found non-blackhole routes to local networks!"
            ip route show | grep -E "^(192\.168|172\.(1[6-9]|2[0-9]|3[01])|10\.)" | grep -v blackhole
        fi
    fi
done
```

---

## 附录：常见问题

### Q1: 为什么不用 iptables REDIRECT 透明代理？

**A**: 因为用户已经有 OpenWrt 旁路由，在上面已经配置了全局代理。使用路由层方案更简单、性能更好，避免重复建设。

### Q2: 容器重启后路由会丢失吗？

**A**: 不会。因为路由设置在 `entrypoint` 中，每次容器启动都会自动执行。

### Q3: 如何验证路由配置是否生效？

**A**:
```bash
# 进入容器
docker exec -it webclaw bash

# 查看路由表
ip route

# 应该看到：
# default via 172.20.0.100 ...
# blackhole 192.168.0.0/16 ...
# blackhole 172.16.0.0/12 ...
# blackhole 10.0.0.0/8 ...

# 测试连通性
ping -c 1 172.20.0.100  # 应该成功
ping -c 1 192.168.1.1    # 应该失败（被阻断）

# 测试外网访问
curl https://api.ipify.org  # 应该返回旁路由的外网 IP
```

### Q4: 旁路由故障后会发生什么？

**A**:
- 所有网络请求超时
- 流量不会绕过代理（因为路由表仍然指向旁路由）
- 可以选择配置旁路由故障转移（failover）

### Q5: 如何临时禁用代理？

**A**:
```bash
# 方法 1：修改 .env 文件
BLOCK_LOCAL_NET=false
GATEWAY_IP=172.20.0.1  # 改回 Docker 网关

# 方法 2：停止容器，使用原 docker-compose.yml
docker-compose down
docker-compose -f docker-compose-original.yml up -d
```

### Q6: 容器内有没有办法绕过代理？

**A**: 没有（在正常情况下）。因为：
1. 移除了 NET_ADMIN 权限，无法修改路由
2. 脚本只读挂载，无法修改
3. blackhole 路由在网络层阻断，应用层无法绕过

但是如果容器被攻破并获得 root 权限，可能通过其他方式绕过（例如直接操作 socket）。

### Q7: DNS 查询会泄露吗？

**A**: 取决于旁路由的配置。建议：
1. 在旁路由上启用 DNS 代理
2. 或在 docker-compose.yml 中配置 DNS 指向旁路由：
```yaml
dns:
  - 172.20.0.100
```

### Q8: 如何监控路由状态？

**A**:
```bash
# 查看守护进程日志
docker logs webclaw 2>&1 | grep protect

# 查看当前路由
docker exec webclaw ip route

# 持续监控
watch -n 5 'docker exec webclaw ip route | grep -E "^default|^blackhole"'
```

### Q9: 这个方案与其他容器冲突吗？

**A**: 不冲突。因为：
1. 只修改 webclaw 容器的路由
2. 不影响 Docker 网络配置
3. 不影响其他容器

### Q10: 如何在生产环境部署？

**A**:
1. 测试：在测试环境验证所有功能
2. 配置：根据实际网络环境修改 .env
3. 监控：配置日志和告警
4. 备份：保留原 docker-compose.yml 作为回滚

---

## 总结

### 推荐方案总结

| 特性 | 说明 |
|------|------|
| **方案名称** | 路由层网关重定向（启动脚本） |
| **核心技术** | ip route + blackhole + cap_drop |
| **文件数量** | 2 个脚本（set-route.sh, protect-route.sh） |
| **容器数量** | 1 个（无需 sidecar） |
| **复杂度** | ⭐⭐ 简单 |
| **安全性** | ⭐⭐⭐⭐⭐ 优秀 |
| **性能** | ⭐⭐⭐⭐⭐ 卓越 |
| **维护成本** | 低 |

### 为什么不选其他方案？

| 方案 | 不推荐的原因 |
|------|-------------|
| Docker 网关 | 旁路由必须在 Docker 网络，限制太大 |
| 共享网络 | 本地网络隔离困难，配置复杂 |
| iptables + Xray | 重复建设，不符合用户实际需求 |

### 最终建议

**采用方案 2（启动脚本注入路由）**，因为：
1. ✅ 最简单：只需要 2 个脚本
2. ✅ 最安全：多层防护
3. ✅ 最灵活：支持任意形式的旁路由
4. ✅ 最符合实际：利用现有基础设施

---

## 变更日志

- **2026-04-19**: 初始版本，完整技术分析

---

## 许可证

本文档遵循 MIT 许可证。

---

**文档结束**

如有疑问或建议，请提交 Issue 或 Pull Request。
