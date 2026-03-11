[English](README.md) | 中文

# uninstall-openclaw

完整卸载 [OpenClaw](https://github.com/openclaw/openclaw) 个人 AI 助手系统的指南与脚本。

---

## 📋 安装组成分析

OpenClaw 是一个多组件的个人 AI 助手系统，安装后在系统中留下以下痕迹：

| 组件 | 安装位置 | 安装方式 |
|---|---|---|
| **CLI 命令行工具** | 全局 npm/pnpm/bun 包 | `npm install -g openclaw@latest` |
| **Gateway 守护进程服务** | macOS: launchd / Linux: systemd / Windows: schtasks | `openclaw onboard --install-daemon` |
| **状态 + 配置目录** | `~/.openclaw/` (或 `$OPENCLAW_STATE_DIR`) | 运行时自动创建 |
| **配置文件** | `~/.openclaw/openclaw.json` (或 `$OPENCLAW_CONFIG_PATH`) | 向导/手动创建 |
| **工作区 (Workspace)** | `~/.openclaw/workspace/` | 包含 AGENTS.md, SOUL.md, skills 等 |
| **凭据文件** | `~/.openclaw/credentials/` | WhatsApp 等渠道登录后创建 |
| **日志文件** | `/tmp/openclaw/openclaw-gateway.log` (macOS) | Gateway 运行时产生 |
| **macOS 应用** | `/Applications/OpenClaw.app` | 可选安装 |
| **macOS 应用 LaunchAgent** | `~/Library/LaunchAgents/ai.openclaw.mac.plist` | macOS app 自行安装 |
| **Gateway LaunchAgent** | `~/Library/LaunchAgents/ai.openclaw.gateway.plist` | daemon install 安装 |
| **Swabble 语音守护进程** | `~/Library/LaunchAgents/com.swabble.agent.plist` | 可选安装 (macOS 26) |
| **Swabble 配置 + 日志** | `~/.config/swabble/` 及 `~/Library/Application Support/swabble/` | swabble setup 创建 |
| **Docker 容器/镜像** | Docker 运行时 | 可选 `docker-setup.sh` |
| **Podman 容器/systemd quadlet** | `~/.config/containers/systemd/openclaw.container` | 可选 `setup-podman.sh` |
| **Tailscale Serve/Funnel 配置** | Tailscale 系统配置 | 可选启用 |
| **浏览器 Profile** | OpenClaw 管理的 Chrome/Chromium 数据 | 浏览器工具可选启用 |
| **iOS/Android 节点配对** | Gateway 中存储的设备配对信息 | 可选配对 |
| **环境变量** | 系统 shell profile | 用户手动设置 |
| **Nix 声明式安装** | home-manager/launchd service | 可选 nix-openclaw |
| **Profile 变体** | `~/.openclaw-<profile>/` | 使用 `--profile` 时创建 |

---

## 🚀 快速卸载

### macOS / Linux

```bash
# 方式一：使用本仓库提供的卸载脚本（推荐）
bash <(curl -fsSL https://raw.githubusercontent.com/easeus/uninstall-openclaw/main/uninstall.sh)

# 方式二：克隆后运行
git clone https://github.com/easeus/uninstall-openclaw.git
cd uninstall-openclaw
chmod +x uninstall.sh
./uninstall.sh
```

### Windows

```powershell
# PowerShell (以管理员身份运行)
irm https://raw.githubusercontent.com/easeus/uninstall-openclaw/main/uninstall.ps1 | iex
```

---

## 🗑️ 完整卸载计划

按照**从高层到底层、从运行时到静态文件**的顺序执行。

### 阶段 1: 一键自动卸载（如果 CLI 还在）

最简单的方式，先尝试内置卸载器：

```bash
openclaw uninstall --all --yes --non-interactive
```

如果 CLI 已被删除但仍有 Node.js，可以用 npx：

```bash
npx -y openclaw uninstall --all --yes --non-interactive
```

> ⚠️ 如果一键卸载成功，仍建议继续执行后续步骤做最终验证和清理残留。

---

### 阶段 2: 停止所有运行中的服务

#### 2.1 停止 Gateway 服务

```bash
openclaw gateway stop
```

#### 2.2 卸载 Gateway 守护进程

```bash
openclaw daemon uninstall
# 或等价的:
openclaw gateway uninstall
```

#### 2.3 手动停止（如果 CLI 不可用）

**macOS (launchd):**
```bash
# Gateway 服务
launchctl bootout gui/$UID/ai.openclaw.gateway
rm -f ~/Library/LaunchAgents/ai.openclaw.gateway.plist

# 如果有 profile 变体
# launchctl bootout gui/$UID/ai.openclaw.<profile>
# rm -f ~/Library/LaunchAgents/ai.openclaw.<profile>.plist

# 清理可能存在的旧版标签
ls ~/Library/LaunchAgents/com.openclaw.* 2>/dev/null && \
  launchctl bootout gui/$UID/com.openclaw.gateway 2>/dev/null; \
  rm -f ~/Library/LaunchAgents/com.openclaw.*.plist

# macOS 应用的 LaunchAgent
launchctl bootout gui/$UID/ai.openclaw.mac 2>/dev/null
rm -f ~/Library/LaunchAgents/ai.openclaw.mac.plist
```

**Linux (systemd):**
```bash
systemctl --user disable --now openclaw-gateway.service
rm -f ~/.config/systemd/user/openclaw-gateway.service
systemctl --user daemon-reload

# 如果有 profile 变体
# systemctl --user disable --now openclaw-gateway-<profile>.service
# rm -f ~/.config/systemd/user/openclaw-gateway-<profile>.service
# systemctl --user daemon-reload
```

**Windows (计划任务):**
```powershell
schtasks /Delete /F /TN "OpenClaw Gateway"
Remove-Item -Force "$env:USERPROFILE\.openclaw\gateway.cmd"
```

---

### 阶段 3: 卸载可选子组件

#### 3.1 Swabble 语音守护进程（macOS 26, 如已安装）

```bash
# 卸载 launchd 服务
launchctl bootout gui/$UID/com.swabble.agent 2>/dev/null
rm -f ~/Library/LaunchAgents/com.swabble.agent.plist

# 删除配置和日志
rm -rf ~/.config/swabble/
rm -rf ~/Library/Application\ Support/swabble/
```

#### 3.2 Docker 安装（如已使用 docker-setup.sh）

```bash
# 停止并移除容器
docker compose down

# 移除 Docker 镜像
docker rmi openclaw:local 2>/dev/null
docker rmi openclaw-sandbox:bookworm-slim 2>/dev/null

# 如果创建了专门的 openclaw 用户
# sudo userdel openclaw (谨慎操作)
```

#### 3.3 Podman 安装（如已使用 setup-podman.sh）

```bash
# 停止 systemd quadlet 服务
systemctl --user disable --now openclaw.service 2>/dev/null

# 移除 quadlet 配置
rm -f ~/.config/containers/systemd/openclaw.container
systemctl --user daemon-reload

# 移除 Podman 镜像
podman rmi openclaw:local 2>/dev/null
```

#### 3.4 Tailscale 配置还原（如已启用）

```bash
# 如果启用了 Serve 或 Funnel
tailscale serve off 2>/dev/null
tailscale funnel off 2>/dev/null
```

#### 3.5 macOS 应用

```bash
# 先退出应用
osascript -e 'quit app "OpenClaw"' 2>/dev/null
rm -rf /Applications/OpenClaw.app
```

---

### 阶段 4: 删除数据和配置文件

```bash
# 主状态目录（包含配置、凭据、会话数据）
rm -rf "${OPENCLAW_STATE_DIR:-$HOME/.openclaw}"

# 如果使用了自定义配置路径，也删除它
# rm -f "$OPENCLAW_CONFIG_PATH"

# 如果使用了 profile，删除对应的状态目录
# rm -rf ~/.openclaw-<profile>

# 日志文件（macOS）
rm -rf /tmp/openclaw/

# 工作区（如果之前已单独配置路径）
# 默认在 ~/.openclaw/workspace/ 中，上面已一起删除
```

---

### 阶段 5: 卸载 CLI 全局包

根据你使用的包管理器选择：

```bash
npm rm -g openclaw
# 或
pnpm remove -g openclaw
# 或
bun remove -g openclaw
```

---

### 阶段 6: 清理源码安装（如果从 git clone 安装）

```bash
# 删除仓库目录
rm -rf /path/to/openclaw/

# 如果安装了 pnpm 仅供 openclaw 使用
# npm rm -g pnpm
```

---

### 阶段 7: 清理环境变量

检查并移除 shell 配置文件中可能手动设置的环境变量（`~/.bashrc`, `~/.zshrc`, `~/.profile` 等）：

需要移除的变量列表：
- `OPENCLAW_STATE_DIR`
- `OPENCLAW_CONFIG_PATH`
- `OPENCLAW_HOME`
- `OPENCLAW_PROFILE`
- `OPENCLAW_NIX_MODE`
- `OPENCLAW_GATEWAY_BIND`
- `OPENCLAW_GATEWAY_TOKEN`
- `OPENCLAW_SKIP_CANVAS_HOST`
- `TELEGRAM_BOT_TOKEN`
- `DISCORD_BOT_TOKEN`
- `SLACK_BOT_TOKEN`
- `SLACK_APP_TOKEN`
- `ZALO_BOT_TOKEN`
- 以及其他 `OPENCLAW_*` 开头的变量

macOS Nix mode defaults（如设置过）：
```bash
defaults delete ai.openclaw.mac 2>/dev/null
```

---

### 阶段 8: 验证卸载完成

```bash
# 确认 CLI 已移除
which openclaw 2>/dev/null && echo "⚠️ CLI 仍存在" || echo "✅ CLI 已移除"

# 确认没有残留进程
pgrep -f openclaw && echo "⚠️ 仍有 openclaw 进程" || echo "✅ 无残留进程"

# 确认没有残留服务 (macOS)
launchctl list | grep -i openclaw && echo "⚠️ 仍有 launchd 服务" || echo "✅ 无残留服务"

# 确认没有残留服务 (Linux)
systemctl --user list-units | grep -i openclaw && echo "⚠️ 仍有 systemd 服务" || echo "✅ 无残留服务"

# 确认目录已清理
ls -la ~/.openclaw 2>/dev/null && echo "⚠️ 状态目录仍存在" || echo "✅ 状态目录已清理"
```

---

## 📝 注意事项

1. **先卸载服务，再删文件** — 如果从源码运行，一定要在删除仓库之前先卸载守护进程服务，否则服务配置会指向不存在的路径。
2. **多 Profile 需逐个清理** — 如果使用了 `--profile`/`OPENCLAW_PROFILE`，每个 profile 都会有独立的状态目录和服务实例。
3. **远程 Gateway** — 如果在远程 Linux 主机上运行 Gateway，需要在该主机上也执行相应的清理步骤。
4. **第三方服务集成** — Telegram Bot、Discord Bot、Slack App 等第三方配置需要在对应平台上手动撤销/删除。
5. **备份提醒** — 卸载前建议备份 `~/.openclaw/workspace/`（包含你的 AGENTS.md、SOUL.md、skills 等个性化文件）和 `~/.openclaw/openclaw.json`（配置文件）。

---

## 📁 文件说明

| 文件 | 说明 |
|---|---|
| `uninstall.sh` | macOS / Linux 完整卸载脚本 |
| `uninstall.ps1` | Windows PowerShell 卸载脚本 |
| `README.md` | 安装分析与卸载指南（英文版） |
| `README.zh-CN.md` | 本文档：安装分析与卸载指南（中文版） |