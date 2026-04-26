# webclaw 容器全局代理与 LAN 隔离方案

> **目的**: 给 webclaw 容器做全局透明代理，**且禁止 webclaw 访问宿主机所在 LAN 的任何 IP**。
>
> **状态**: 研究文档，记录第一性原理分析结果与实施蓝图。尚未落地到 `docker-compose.yml`。
>
> **对照文档**: `docs/transparent-proxy-technical-analysis.md`（先前方案，本文档指出其根本问题并提出替代）。
>
> **创建时间**: 2026-04-19

---

## 目录

- [0. TL;DR](#0-tldr)
- [1. 先前方案的根本问题](#1-先前方案的根本问题)
- [2. 第一性原理](#2-第一性原理)
- [3. 架构](#3-架构)
- [4. 已澄清的约束](#4-已澄清的约束)
- [5. 关键实现](#5-关键实现)
- [6. 坑位清单](#6-坑位清单)
- [7. 验证方法](#7-验证方法)
- [8. 回滚](#8-回滚)

---

## 0. TL;DR

**一句话方案**: `webclaw` 容器用 `network_mode: "service:openwrt"` **共享 OpenWrt 容器的 network namespace**，所有隔离策略只写一处 —— OpenWrt 容器里的 `iptables OUTPUT` 白名单。

**不需要**：
- `set-route.sh`（自改路由脚本）
- `protect-route.sh`（守护进程）
- blackhole 路由
- 修改 webclaw 镜像

**只需要**：
- 新增一个 openwrt sidecar 容器（同 Docker Host 上）
- 一个 `firewall.sh`（约 20 行 iptables 规则）
- compose 里 3 处改动

---

## 1. 先前方案的根本问题

先前 `docs/transparent-proxy-technical-analysis.md` 推荐的"方案 2（启动脚本注入路由 + cap_drop + 守护进程）"存在以下根本缺陷：

### 1.1 自相矛盾 —— 方案本身跑不起来

文档同时要求：
- `cap_drop: NET_ADMIN`
- 在容器 entrypoint 里执行 `ip route del default` / `ip route add default via ...` / `ip route add blackhole ...`

**没有 `CAP_NET_ADMIN` 的进程无法修改路由表**，这是 Linux 硬性设计，跟是否 root 无关。entrypoint 会在第一条 `ip route del` 就返回 `Operation not permitted` 并退出。整个 docker-compose 根本起不来。

### 1.2 "protect-route.sh" 守护进程是安全剧场

- 如果真的 drop 了 `NET_ADMIN`：没人能改路由，守护进程完全多余。
- 如果保留 `NET_ADMIN` 让 entrypoint 能工作：同一个 root 攻击者也能 `kill $PROTECT_PID` + `ip route del`，守护挡不住。
- 轮询间隔 10 秒的窗口里，流量已经泄光。

这整套是为了绕过矛盾 1.1 临时加的补丁，没解决根本问题。

### 1.3 职责分散到错误位置

OpenWrt 的本职工作就是防火墙 + 路由 + 代理。把"转发到代理"和"阻断 LAN"拆成被代理容器内部的 `default route` + `blackhole route`，等于让"工件"管策略而真正的执行者（OpenWrt）闲着。单一职责应该归到 OpenWrt 的 firewall zone。

### 1.4 blackhole 路由语义有限

`ip route add blackhole 192.168.0.0/16` 只拦**目的 IP 在该段**的包，走 FIB 查表丢弃。但：
- 如果容器 eth0 本身就在 192.168.x.x（典型 Docker bridge 或 macvlan 就是），同子网通信不一定经过默认路由表决策，ARP/L2 广播可直达。
- 真正的"LAN 隔离"是 L3 + firewall zone 的组合事，单靠路由层不够。

### 1.5 方案 3（共享网络命名空间）被错误否决

先前文档称共享 netns "本地网络隔离困难"，理由是"OpenWrt 自己也无法访问 LAN"。这是误判：
- OpenWrt 的 **zone-based firewall** 天生就是做这件事的 —— WAN zone 走代理、LAN zone 默认 drop，容器共享 netns 后受同一套规则约束。
- 用 iptables OUTPUT 白名单同样干净：ACCEPT 到代理上游 IP + REJECT 全部 RFC1918。

---

## 2. 第一性原理

> **谁拥有 network namespace，谁就是唯一执行点。**

不要让"被代理的容器"自己维护代理策略（它利益相反、权限模糊）。让"代理执行者（OpenWrt）"拥有 netns，被代理容器直接寄生其上，没有独立网络栈可供绕过。

由此推出 5 条直接收益：

| 收益 | 机制 |
|------|------|
| 策略只写一处 | OpenWrt firewall |
| 容器能力可以全部 drop | `cap_drop: [NET_ADMIN, NET_RAW]` |
| 没有"entrypoint 脚本 vs 权限"矛盾 | 根本不需要 entrypoint 脚本 |
| 没有"blackhole vs 同子网 L2"死角 | iptables 在 netfilter 层过滤，不依赖路由表 |
| OpenWrt 故障 = 网络断 = fail-closed | 天然满足"故障不泄漏" |

---

## 3. 架构

```
┌─ Docker Host ────────────────────────────────────────┐
│                                                      │
│  网桥 proxy_net  172.30.0.0/24  (非 LAN 常见段)      │
│       ↑                                              │
│       │ (openwrt 唯一对外网卡)                       │
│                                                      │
│  ┌─ openwrt 容器 ─────────────┐                      │
│  │ cap_add: NET_ADMIN          │                      │
│  │ eth0: 172.30.0.2            │                      │
│  │ 运行:                       │                      │
│  │   - shadowsocks/v2ray 客户端│                      │
│  │   - iptables OUTPUT 防火墙  │                      │
│  │   - dnsmasq (53)            │                      │
│  │                             │                      │
│  │ ┌─ webclaw 容器 ─────────┐ │                      │
│  │ │ network_mode:          │ │                      │
│  │ │   service:openwrt      │ │  <-- 共享 netns       │
│  │ │ cap_drop:              │ │                      │
│  │ │   NET_ADMIN, NET_RAW   │ │                      │
│  │ │ (无独立网卡)            │ │                      │
│  │ └────────────────────────┘ │                      │
│  └─────────────────────────────┘                      │
│                                                      │
│  宿主 eth0: 192.168.1.x (LAN)  ← webclaw 不能访问     │
└──────────────────────────────────────────────────────┘
```

关键点：
- **proxy_net 刻意用 172.30.0.0/24**，避开家庭路由器常用的 192.168.x.x 与 Docker 默认的 172.17/172.18。防火墙按 RFC1918 大段 block 时，只需在前面单独放行 172.30 这一段。
- webclaw **不再**映射 `host.docker.internal`，**不再能** ping 宿主 LAN IP。

---

## 4. 已澄清的约束

| 约束 | 决定 |
|------|------|
| 上游代理（shadowsocks/v2ray 落地节点） IP | **公网 IP**，`firewall.sh` 无需为 LAN 内代理开例外 |
| `/var/run/docker.sock` 挂载 | **可选**。隔离模式下默认不挂，避免 `docker run --network host` 绕过。需要 DNA 自演化时用 override 额外挂载。 |
| host-api 调用 (`HOST_API_TOKEN` / `host.docker.internal`) | **本模式下不使用**。删除 `extra_hosts` 与 `HOST_API_TOKEN`。`host-ops` skill 在本模式不可用。 |
| IPv6 | **关闭**。`sysctls: net.ipv6.conf.all.disable_ipv6=1` 防 v6 侧漏。 |

---

## 5. 关键实现

### 5.1 `docker-compose.yml` 改动（3 处）

```yaml
services:
  openwrt:
    image: <openwrt-with-ss-image>           # 自建或 openwrtorg/rootfs + shadowsocks-libev + dnsmasq
    container_name: webclaw-gw
    cap_add: [NET_ADMIN]
    sysctls:
      net.ipv4.ip_forward: "1"
      net.ipv6.conf.all.disable_ipv6: "1"
    networks:
      proxy_net:
        ipv4_address: 172.30.0.2
    # webclaw 的端口映射全部挪到这里（webclaw 没有独立 netns）
    ports:
      - "20000:20000"
      - "20001:20001"
      - "20002:20002"
      - "20003:20003"
      - "20004:20004"
    volumes:
      - ./openwrt/firewall.sh:/etc/firewall.sh:ro
      - ./openwrt/ss-config.json:/etc/shadowsocks/config.json:ro
    environment:
      - PROXY_UPSTREAM_IP=${PROXY_UPSTREAM_IP}
    restart: unless-stopped
    # 先刷防火墙，再起 init —— 避免几秒的裸流量窗口
    command: ["/bin/sh", "-c", "/etc/firewall.sh && exec /sbin/init"]

  webclaw:
    image: land007/webclaw:latest
    container_name: webclaw
    network_mode: "service:openwrt"           # 核心：共享 netns
    cap_drop: [NET_ADMIN, NET_RAW]            # 容器内改不了防火墙/路由
    depends_on:
      openwrt:
        condition: service_started
    # 删除：ports, extra_hosts, networks, HOST_API_TOKEN
    environment:
      - MODE=${MODE:-desktop}
      - AUTH_USER=${AUTH_USER:-admin}
      - AUTH_PASSWORD=${AUTH_PASSWORD:-changeme}
      - OPENCLAW_GATEWAY_TOKEN=${OPENCLAW_GATEWAY_TOKEN:-changeme}
      - VNC_PASSWORD=${VNC_PASSWORD:-changeme}
      - VNC_RESOLUTION=${VNC_RESOLUTION:-1920x1080}
    volumes:
      # docker.sock 默认不挂；需要 DNA 自演化时用 docker-compose.dna.yml override 加回
      - dna-data:/home/ubuntu/dna
      - projects:/home/ubuntu/projects
      - vibe-kanban-data:/home/ubuntu/.local/share/vibe-kanban
      - code-server-data:/home/ubuntu/.code-server
      - user-data:/home/ubuntu/.local/share
      - gitconfig:/home/ubuntu/.gitconfig-vol
      - openclaw-data:/home/ubuntu/.openclaw
      - chrome-data:/home/ubuntu/.config
      - recordings:/home/ubuntu/recordings
      - webclaw-config:/home/ubuntu/.webclaw
    shm_size: "512m"
    restart: unless-stopped

networks:
  proxy_net:
    driver: bridge
    ipam:
      config:
        - subnet: 172.30.0.0/24

volumes:
  dna-data:
  projects:
  vibe-kanban-data:
  code-server-data:
  user-data:
  gitconfig:
  openclaw-data:
  chrome-data:
  recordings:
  webclaw-config:
```

### 5.2 `openwrt/firewall.sh` —— 整个方案的"灵魂"

```sh
#!/bin/sh
set -eu

PROXY_UPSTREAM_IP="${PROXY_UPSTREAM_IP:?must set: the remote SS/V2Ray server public IP}"

# 清空
iptables -F OUTPUT
iptables -F FORWARD

# 默认 DROP，白名单放行
iptables -P OUTPUT DROP
iptables -P FORWARD DROP

# 1) 环回
iptables -A OUTPUT -o lo -j ACCEPT

# 2) proxy_net 网桥（让包能出 openwrt 容器）
#    必须出现在第 4 步 RFC1918 REJECT 之前
iptables -A OUTPUT -d 172.30.0.0/24 -j ACCEPT

# 3) 上游代理服务器公网 IP
iptables -A OUTPUT -d "$PROXY_UPSTREAM_IP" -j ACCEPT

# 4) 显式 REJECT 所有 RFC1918（覆盖宿主 LAN / 其他 Docker 网络 / 链路本地）
iptables -A OUTPUT -d 192.168.0.0/16 -j REJECT --reject-with icmp-net-unreachable
iptables -A OUTPUT -d 172.16.0.0/12  -j REJECT --reject-with icmp-net-unreachable
iptables -A OUTPUT -d 10.0.0.0/8     -j REJECT --reject-with icmp-net-unreachable
iptables -A OUTPUT -d 169.254.0.0/16 -j REJECT
iptables -A OUTPUT -d 127.0.0.0/8 ! -o lo -j REJECT

# 5) 剩余（公网）交给 shadowsocks 透明代理（ss-redir / redsocks / v2ray tproxy）
#    具体 NAT 规则依代理实现补充
iptables -A OUTPUT -j ACCEPT

# IPv6：全 DROP（v6 已在 sysctls 里关闭，这里做双保险）
ip6tables -P OUTPUT DROP || true
ip6tables -P FORWARD DROP || true
```

### 5.3 `openwrt/ss-config.json`

```json
{
  "server":       "PROXY_UPSTREAM_PUBLIC_IP",
  "server_port":  8388,
  "local_address":"127.0.0.1",
  "local_port":   1080,
  "password":     "CHANGE_ME",
  "method":       "aes-256-gcm",
  "mode":         "tcp_and_udp"
}
```

### 5.4 `.env` 新增

```bash
PROXY_UPSTREAM_IP=<公网落地节点 IP>
```

### 5.5 `docker-compose.dna.yml` —— 可选 override，启用 DNA 自演化

```yaml
services:
  webclaw:
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
```

启动：
```bash
# 隔离模式（默认）
docker compose up -d

# 启用 DNA 自演化（关闭隔离天窗警告：webclaw 可 docker run --network host 绕过）
docker compose -f docker-compose.yml -f docker-compose.dna.yml up -d
```

### 5.6 webclaw 镜像

**零改动**。不写 `set-route.sh`、不写 `protect-route.sh`、不改 Dockerfile、不挂任何额外脚本。

---

## 6. 坑位清单

1. **DNS 必须过代理**。webclaw 若去查 8.8.8.8 等公网 DNS，被 OUTPUT 的 ACCEPT 兜底放行（后续由透明代理转发）；若硬编码查 LAN DNS（如 192.168.1.1:53）则会被 REJECT 导致解析失败。推荐做法：openwrt 内跑 dnsmasq 监听 127.0.0.1:53，上游通过 SS 隧道查；webclaw 共享 netns 自动继承 `/etc/resolv.conf` 里的 127.0.0.1。

2. **IPv6**: 必须 `sysctls: net.ipv6.conf.all.disable_ipv6=1`，并在 firewall.sh 里 `ip6tables -P OUTPUT DROP`。否则 LAN 可通过 fe80:/fc00: 可达，绕过 v4 iptables。

3. **Docker 默认 bridge (172.17.0.0/16)**：本方案不用它。firewall.sh 里 172.30.0.0/24 的 ACCEPT **必须出现在** 172.16.0.0/12 的 REJECT **之前**，否则 openwrt 自己出不去。

4. **端口映射位置**：`ports:` 必须写在 openwrt 服务下。webclaw 无独立 netns，在它底下写 `ports` 是无效的（compose 会警告）。所有 20000-20004 对外暴露由 openwrt 承担。

5. **docker.sock 默认不挂**：避免 webclaw 内 `docker run --network host` 直接访问 LAN、彻底绕过隔离。要用 DNA 自演化必须主动使用 `docker-compose.dna.yml`，用户自知风险。

6. **host-api 能力移除**：删除 `extra_hosts: host.docker.internal`、删除 `HOST_API_TOKEN` env。容器内的 `host-ops` skill 在本模式下不可用。

7. **Supervisor / code-server 不需改动**：它们绑 127.0.0.1:100xx，openwrt 的 OUTPUT 里 lo 被 ACCEPT，本地回环正常。

8. **openwrt 启动顺序**：firewall.sh 必须在任何用户态代理/监听进程前执行，否则有几秒的裸流量窗口。`command: /etc/firewall.sh && exec /sbin/init` 保证顺序。

9. **webclaw 启动顺序**：`depends_on.openwrt.condition: service_started` 只等待 openwrt 进程拉起。因为 openwrt 的 `command` 先跑 firewall.sh 再 `exec /sbin/init`，防火墙就位后才会被视为 started，隐式保证顺序。

10. **若上游代理用域名**：iptables 基于 IP 工作。如果代理服务器地址会变，`PROXY_UPSTREAM_IP` 需要定时刷新 —— 建议固定公网 IP，或在 openwrt 里跑定时 resolve + `iptables -R` 的脚本。

---

## 7. 验证方法

```bash
cd webclaw-docker
docker compose up -d

# 1. 确认 webclaw 共享了 openwrt 的 netns（两者 ip addr 应一致）
diff <(docker exec webclaw ip addr) <(docker exec webclaw-gw ip addr)
# 期望：无差异

# 2. 确认容器无 NET_ADMIN
docker exec webclaw capsh --print | grep -i net_admin
# 期望：输出为空

# 3. 出站真实 IP = 代理出口
docker exec webclaw curl -s --max-time 10 https://api.ipify.org
# 期望：返回 SS 落地节点公网 IP，而非宿主机公网 IP

# 4. 【核心】宿主 LAN 完全不可达
HOST_LAN_IP=$(ip -4 addr show $(ip route | awk '/default/{print $5;exit}') | awk '/inet /{print $2}' | cut -d/ -f1)
echo "Host LAN IP: $HOST_LAN_IP"
docker exec webclaw curl --max-time 3 "http://$HOST_LAN_IP" && echo "FAIL: LAN reachable" || echo "PASS: LAN blocked"
docker exec webclaw ping -c1 -W2 192.168.1.1 && echo "FAIL" || echo "PASS"

# 5. 容器内即使 root 也改不了 iptables
docker exec -u root webclaw iptables -F 2>&1 | grep -iE "permission|not permitted"
# 期望：命中权限拒绝字样

# 6. fail-closed：openwrt 挂掉时 webclaw 网络应断
docker stop webclaw-gw
docker exec webclaw curl --max-time 3 https://api.ipify.org && echo "FAIL: leak" || echo "PASS: fail-closed"
docker start webclaw-gw
```

**验收标准**：第 4、5、6 项必须 PASS。其中第 4 项是本方案的核心硬需求。

---

## 8. 回滚

保留原 `docker-compose.yml` 作 `docker-compose.direct.yml`（直连、无代理、无隔离）：

```bash
docker compose down
docker compose -f docker-compose.direct.yml up -d
```

---

## 附：与先前文档的核心对比

| 维度 | 先前方案 2（不推荐） | 本方案 |
|------|---------------------|--------|
| 可运行性 | ❌ 自相矛盾（cap_drop + ip route add） | ✅ 无矛盾 |
| 脚本数量 | 2 个（set-route + protect-route） | 0 个（容器内） |
| 守护进程 | 需要（且是安全剧场） | 不需要 |
| 执行点 | 容器内（策略与工件耦合） | OpenWrt 单点 |
| LAN 隔离机制 | blackhole 路由（L3 层，有死角） | iptables OUTPUT REJECT（netfilter 层，严密） |
| fail-closed | 依赖守护进程轮询 | 天然（openwrt 挂 = 网络断） |
| webclaw 镜像改动 | 需 entrypoint 替换 | 零改动 |

---

**文档结束**。需要落地时请参考第 5 节按步骤改造，并按第 7 节的 6 项验证全部跑过再投产。
