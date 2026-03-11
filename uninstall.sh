#!/usr/bin/env bash
# uninstall.sh — 完整卸载 OpenClaw 的 macOS / Linux 脚本
# 仓库: https://github.com/easeus/uninstall-openclaw
#
# 用法:
#   chmod +x uninstall.sh && ./uninstall.sh
#   或一行命令:
#   bash <(curl -fsSL https://raw.githubusercontent.com/easeus/uninstall-openclaw/main/uninstall.sh)

set -euo pipefail

# ── 颜色输出 ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
ok()      { echo -e "${GREEN}[✅]${RESET}   $*"; }
warn()    { echo -e "${YELLOW}[⚠️]${RESET}   $*"; }
section() { echo -e "\n${BOLD}${CYAN}━━━ $* ━━━${RESET}"; }

# ── 交互确认 ──────────────────────────────────────────────────────────────────
NON_INTERACTIVE=false
YES_ALL=false

for arg in "$@"; do
  case "$arg" in
    --non-interactive) NON_INTERACTIVE=true ;;
    --yes|-y)          YES_ALL=true ;;
  esac
done

confirm() {
  # $1 = prompt message
  if $YES_ALL || $NON_INTERACTIVE; then
    return 0
  fi
  read -r -p "$1 [y/N] " _answer
  [[ "${_answer,,}" == "y" ]]
}

# ── 系统检测 ──────────────────────────────────────────────────────────────────
OS="$(uname -s)"
case "$OS" in
  Darwin) PLATFORM="macos" ;;
  Linux)  PLATFORM="linux" ;;
  *)
    echo "不支持的操作系统: $OS（请使用 uninstall.ps1 用于 Windows）"
    exit 1
    ;;
esac

echo -e "${BOLD}"
echo "╔═══════════════════════════════════════════════╗"
echo "║         OpenClaw 完整卸载脚本                 ║"
echo "║  https://github.com/easeus/uninstall-openclaw ║"
echo "╚═══════════════════════════════════════════════╝"
echo -e "${RESET}"
warn "此脚本将从你的系统中完整移除 OpenClaw 及其所有组件。"
warn "建议在继续前备份 ~/.openclaw/workspace/ 和 ~/.openclaw/openclaw.json"
echo ""

if ! confirm "确定要继续卸载吗？"; then
  echo "卸载已取消。"
  exit 0
fi

# ──────────────────────────────────────────────────────────────────────────────
# 阶段 1: 尝试 CLI 内置卸载器
# ──────────────────────────────────────────────────────────────────────────────
section "阶段 1: 尝试 CLI 内置卸载器"

if command -v openclaw &>/dev/null; then
  info "发现 openclaw CLI，尝试内置卸载器..."
  openclaw uninstall --all --yes --non-interactive 2>/dev/null && ok "CLI 内置卸载器执行完毕" || warn "CLI 内置卸载器未完全成功，继续手动清理..."
elif command -v npx &>/dev/null; then
  info "未发现 openclaw CLI，尝试通过 npx 运行内置卸载器..."
  npx -y openclaw uninstall --all --yes --non-interactive 2>/dev/null && ok "npx 内置卸载器执行完毕" || warn "npx 内置卸载器未完全成功，继续手动清理..."
else
  warn "未找到 openclaw CLI 和 npx，跳过内置卸载器，继续手动清理..."
fi

# ──────────────────────────────────────────────────────────────────────────────
# 阶段 2: 停止并卸载 Gateway 服务
# ──────────────────────────────────────────────────────────────────────────────
section "阶段 2: 停止并卸载 Gateway 服务"

if command -v openclaw &>/dev/null; then
  info "停止 openclaw gateway..."
  openclaw gateway stop 2>/dev/null || true
  openclaw daemon uninstall 2>/dev/null || openclaw gateway uninstall 2>/dev/null || true
fi

if [[ "$PLATFORM" == "macos" ]]; then
  info "清理 macOS LaunchAgent 服务..."

  # Gateway LaunchAgent
  launchctl bootout "gui/$UID/ai.openclaw.gateway" 2>/dev/null || true
  if [[ -f "$HOME/Library/LaunchAgents/ai.openclaw.gateway.plist" ]]; then
    rm -f "$HOME/Library/LaunchAgents/ai.openclaw.gateway.plist"
    ok "已移除 ai.openclaw.gateway.plist"
  fi

  # 旧版 com.openclaw.* 标签
  for _plist in "$HOME/Library/LaunchAgents/com.openclaw."*.plist; do
    [[ -e "$_plist" ]] || continue
    _label="$(basename "$_plist" .plist)"
    launchctl bootout "gui/$UID/$_label" 2>/dev/null || true
    rm -f "$_plist"
    ok "已移除 $_plist"
  done

  # profile 变体 LaunchAgents (ai.openclaw.<profile>.plist)
  for _plist in "$HOME/Library/LaunchAgents/ai.openclaw."*.plist; do
    [[ -e "$_plist" ]] || continue
    _label="$(basename "$_plist" .plist)"
    # 跳过 mac 和 gateway（已单独处理）
    [[ "$_label" == "ai.openclaw.mac" || "$_label" == "ai.openclaw.gateway" ]] && continue
    launchctl bootout "gui/$UID/$_label" 2>/dev/null || true
    rm -f "$_plist"
    ok "已移除 $_plist"
  done

  # macOS App LaunchAgent
  launchctl bootout "gui/$UID/ai.openclaw.mac" 2>/dev/null || true
  if [[ -f "$HOME/Library/LaunchAgents/ai.openclaw.mac.plist" ]]; then
    rm -f "$HOME/Library/LaunchAgents/ai.openclaw.mac.plist"
    ok "已移除 ai.openclaw.mac.plist"
  fi

elif [[ "$PLATFORM" == "linux" ]]; then
  info "清理 Linux systemd 用户服务..."

  if command -v systemctl &>/dev/null; then
    # 主 gateway 服务
    if systemctl --user list-unit-files "openclaw-gateway.service" &>/dev/null; then
      systemctl --user disable --now openclaw-gateway.service 2>/dev/null || true
      ok "已停用 openclaw-gateway.service"
    fi
    rm -f "$HOME/.config/systemd/user/openclaw-gateway.service"

    # profile 变体服务
    for _svc in "$HOME/.config/systemd/user/openclaw-gateway-"*.service; do
      [[ -e "$_svc" ]] || continue
      _name="$(basename "$_svc")"
      systemctl --user disable --now "$_name" 2>/dev/null || true
      rm -f "$_svc"
      ok "已移除 $_svc"
    done

    systemctl --user daemon-reload 2>/dev/null || true
  fi
fi

# ──────────────────────────────────────────────────────────────────────────────
# 阶段 3: 卸载可选子组件
# ──────────────────────────────────────────────────────────────────────────────
section "阶段 3: 卸载可选子组件"

# 3.1 Swabble 语音守护进程 (macOS)
if [[ "$PLATFORM" == "macos" ]]; then
  if [[ -f "$HOME/Library/LaunchAgents/com.swabble.agent.plist" ]]; then
    info "发现 Swabble，正在卸载..."
    launchctl bootout "gui/$UID/com.swabble.agent" 2>/dev/null || true
    rm -f "$HOME/Library/LaunchAgents/com.swabble.agent.plist"
    ok "已移除 com.swabble.agent.plist"
  fi
  if [[ -d "$HOME/.config/swabble" ]]; then
    rm -rf "$HOME/.config/swabble"
    ok "已删除 ~/.config/swabble/"
  fi
  if [[ -d "$HOME/Library/Application Support/swabble" ]]; then
    rm -rf "$HOME/Library/Application Support/swabble"
    ok "已删除 ~/Library/Application Support/swabble/"
  fi
fi

# 3.2 Docker 安装
if command -v docker &>/dev/null; then
  if docker image inspect openclaw:local &>/dev/null || docker image inspect openclaw-sandbox:bookworm-slim &>/dev/null; then
    if confirm "发现 OpenClaw Docker 镜像，是否移除？"; then
      docker compose down 2>/dev/null || true
      docker rmi openclaw:local 2>/dev/null || true
      docker rmi openclaw-sandbox:bookworm-slim 2>/dev/null || true
      ok "已移除 OpenClaw Docker 镜像"
    fi
  fi
fi

# 3.3 Podman 安装
if command -v podman &>/dev/null; then
  if [[ -f "$HOME/.config/containers/systemd/openclaw.container" ]]; then
    info "发现 Podman quadlet 配置，正在卸载..."
    if command -v systemctl &>/dev/null; then
      systemctl --user disable --now openclaw.service 2>/dev/null || true
    fi
    rm -f "$HOME/.config/containers/systemd/openclaw.container"
    if command -v systemctl &>/dev/null; then
      systemctl --user daemon-reload 2>/dev/null || true
    fi
    ok "已移除 Podman quadlet 配置"
  fi
  if podman image inspect openclaw:local &>/dev/null 2>&1; then
    if confirm "发现 OpenClaw Podman 镜像，是否移除？"; then
      podman rmi openclaw:local 2>/dev/null || true
      ok "已移除 OpenClaw Podman 镜像"
    fi
  fi
fi

# 3.4 Tailscale
if command -v tailscale &>/dev/null; then
  if tailscale status &>/dev/null 2>&1; then
    if confirm "是否重置 Tailscale Serve/Funnel 配置？"; then
      tailscale serve off 2>/dev/null || true
      tailscale funnel off 2>/dev/null || true
      ok "已重置 Tailscale Serve/Funnel 配置"
    fi
  fi
fi

# 3.5 macOS 应用
if [[ "$PLATFORM" == "macos" ]]; then
  if [[ -d "/Applications/OpenClaw.app" ]]; then
    if confirm "发现 OpenClaw.app，是否删除？"; then
      osascript -e 'quit app "OpenClaw"' 2>/dev/null || true
      sleep 1
      rm -rf "/Applications/OpenClaw.app"
      ok "已删除 /Applications/OpenClaw.app"
    fi
  fi
fi

# ──────────────────────────────────────────────────────────────────────────────
# 阶段 4: 删除数据和配置文件
# ──────────────────────────────────────────────────────────────────────────────
section "阶段 4: 删除数据和配置文件"

_state_dir="${OPENCLAW_STATE_DIR:-$HOME/.openclaw}"

if [[ -d "$_state_dir" ]]; then
  if confirm "是否删除状态目录 $_state_dir（包含配置、凭据、会话数据）？"; then
    rm -rf "$_state_dir"
    ok "已删除 $_state_dir"
  fi
else
  info "状态目录 $_state_dir 不存在，跳过。"
fi

# 自定义配置路径
if [[ -n "${OPENCLAW_CONFIG_PATH:-}" && -f "$OPENCLAW_CONFIG_PATH" ]]; then
  if confirm "是否删除自定义配置文件 $OPENCLAW_CONFIG_PATH？"; then
    rm -f "$OPENCLAW_CONFIG_PATH"
    ok "已删除 $OPENCLAW_CONFIG_PATH"
  fi
fi

# profile 变体状态目录
for _dir in "$HOME/.openclaw-"*/; do
  [[ -d "$_dir" ]] || continue
  if confirm "是否删除 profile 状态目录 $_dir？"; then
    rm -rf "$_dir"
    ok "已删除 $_dir"
  fi
done

# 日志目录 (macOS)
if [[ -d "/tmp/openclaw" ]]; then
  rm -rf "/tmp/openclaw"
  ok "已删除 /tmp/openclaw/"
fi

# macOS Nix mode defaults
if [[ "$PLATFORM" == "macos" ]] && command -v defaults &>/dev/null; then
  defaults delete ai.openclaw.mac 2>/dev/null && ok "已删除 macOS defaults ai.openclaw.mac" || true
fi

# ──────────────────────────────────────────────────────────────────────────────
# 阶段 5: 卸载 CLI 全局包
# ──────────────────────────────────────────────────────────────────────────────
section "阶段 5: 卸载 CLI 全局包"

_removed_cli=false

if command -v npm &>/dev/null && npm list -g --depth=0 openclaw 2>/dev/null | grep -q openclaw; then
  info "通过 npm 卸载 openclaw..."
  npm rm -g openclaw && ok "已通过 npm 卸载 openclaw" && _removed_cli=true
fi

if command -v pnpm &>/dev/null && pnpm list -g --depth=0 2>/dev/null | grep -q openclaw; then
  info "通过 pnpm 卸载 openclaw..."
  pnpm remove -g openclaw && ok "已通过 pnpm 卸载 openclaw" && _removed_cli=true
fi

if command -v bun &>/dev/null && bun pm ls -g 2>/dev/null | grep -q openclaw; then
  info "通过 bun 卸载 openclaw..."
  bun remove -g openclaw && ok "已通过 bun 卸载 openclaw" && _removed_cli=true
fi

if ! $_removed_cli; then
  warn "未通过包管理器找到 openclaw，可能已手动安装或已卸载。"
fi

# ──────────────────────────────────────────────────────────────────────────────
# 阶段 6: 清理源码安装
# ──────────────────────────────────────────────────────────────────────────────
section "阶段 6: 清理源码安装"

# 常见的 openclaw 源码克隆路径
_common_src_paths=(
  "$HOME/openclaw"
  "$HOME/src/openclaw"
  "$HOME/projects/openclaw"
  "$HOME/code/openclaw"
)

for _src in "${_common_src_paths[@]}"; do
  if [[ -d "$_src" && -f "$_src/package.json" ]]; then
    if grep -q '"name".*"openclaw"' "$_src/package.json" 2>/dev/null; then
      if confirm "发现 openclaw 源码目录 $_src，是否删除？"; then
        rm -rf "$_src"
        ok "已删除 $_src"
      fi
    fi
  fi
done

info "如果你的源码安装路径不在上述常见位置，请手动执行: rm -rf /path/to/openclaw/"

# ──────────────────────────────────────────────────────────────────────────────
# 阶段 7: 提示清理环境变量
# ──────────────────────────────────────────────────────────────────────────────
section "阶段 7: 提示清理环境变量"

cat << 'EOF'
请手动检查并移除以下 shell 配置文件中的 OpenClaw 相关环境变量：
  ~/.bashrc  ~/.zshrc  ~/.profile  ~/.bash_profile

需要移除的变量：
  OPENCLAW_STATE_DIR    OPENCLAW_CONFIG_PATH   OPENCLAW_HOME
  OPENCLAW_PROFILE      OPENCLAW_NIX_MODE      OPENCLAW_GATEWAY_BIND
  OPENCLAW_GATEWAY_TOKEN                       OPENCLAW_SKIP_CANVAS_HOST
  TELEGRAM_BOT_TOKEN    DISCORD_BOT_TOKEN      SLACK_BOT_TOKEN
  SLACK_APP_TOKEN       ZALO_BOT_TOKEN
  以及其他 OPENCLAW_* 开头的变量

示例（sed 命令，谨慎使用）：
  sed -i.bak '/OPENCLAW_/d' ~/.bashrc ~/.zshrc ~/.profile 2>/dev/null || true
EOF

# ──────────────────────────────────────────────────────────────────────────────
# 阶段 8: 验证卸载完成
# ──────────────────────────────────────────────────────────────────────────────
section "阶段 8: 验证卸载完成"

echo ""
if command -v openclaw &>/dev/null; then
  warn "CLI 仍存在: $(command -v openclaw)"
else
  ok "CLI 已移除"
fi

if pgrep -f openclaw &>/dev/null; then
  warn "仍有 openclaw 进程运行: $(pgrep -f openclaw | tr '\n' ' ')"
else
  ok "无残留 openclaw 进程"
fi

if [[ "$PLATFORM" == "macos" ]] && command -v launchctl &>/dev/null; then
  _launchd_result="$(launchctl list 2>/dev/null | grep -i openclaw || true)"
  if [[ -n "$_launchd_result" ]]; then
    warn "仍有 launchd 服务:\n$_launchd_result"
  else
    ok "无残留 launchd 服务"
  fi
fi

if [[ "$PLATFORM" == "linux" ]] && command -v systemctl &>/dev/null; then
  _systemd_result="$(systemctl --user list-units 2>/dev/null | grep -i openclaw || true)"
  if [[ -n "$_systemd_result" ]]; then
    warn "仍有 systemd 服务:\n$_systemd_result"
  else
    ok "无残留 systemd 服务"
  fi
fi

_state_dir="${OPENCLAW_STATE_DIR:-$HOME/.openclaw}"
if [[ -d "$_state_dir" ]]; then
  warn "状态目录仍存在: $_state_dir"
else
  ok "状态目录已清理"
fi

echo ""
echo -e "${BOLD}${GREEN}OpenClaw 卸载完成！${RESET}"
echo "如有残留项（显示 ⚠️），请根据提示手动处理。"
echo "如需帮助，请访问: https://github.com/easeus/uninstall-openclaw"
