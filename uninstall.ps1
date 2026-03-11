# uninstall.ps1 — 完整卸载 OpenClaw 的 Windows PowerShell 脚本
# 仓库: https://github.com/easeus/uninstall-openclaw
#
# 用法（以管理员身份运行 PowerShell）:
#   irm https://raw.githubusercontent.com/easeus/uninstall-openclaw/main/uninstall.ps1 | iex
#   或本地运行:
#   Set-ExecutionPolicy Bypass -Scope Process -Force; .\uninstall.ps1

[CmdletBinding()]
param(
    [switch]$Yes,
    [switch]$NonInteractive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

# ── 颜色输出 ──────────────────────────────────────────────────────────────────
function Write-Info    { param($msg) Write-Host "[INFO]  $msg" -ForegroundColor Cyan }
function Write-Ok      { param($msg) Write-Host "[OK]    $msg" -ForegroundColor Green }
function Write-Warn    { param($msg) Write-Host "[WARN]  $msg" -ForegroundColor Yellow }
function Write-Section { param($msg) Write-Host "`n━━━ $msg ━━━" -ForegroundColor Cyan }

# ── 交互确认 ──────────────────────────────────────────────────────────────────
function Confirm-Action {
    param([string]$Prompt)
    if ($Yes -or $NonInteractive) { return $true }
    $answer = Read-Host "$Prompt [y/N]"
    return $answer -match '^[Yy]$'
}

# ── 横幅 ──────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "╔═══════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║         OpenClaw 完整卸载脚本 (Windows)       ║" -ForegroundColor Cyan
Write-Host "║  https://github.com/easeus/uninstall-openclaw ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""
Write-Warn "此脚本将从你的系统中完整移除 OpenClaw 及其所有组件。"
Write-Warn "建议在继续前备份 %USERPROFILE%\.openclaw\workspace\ 和 openclaw.json"
Write-Host ""

if (-not (Confirm-Action "确定要继续卸载吗？")) {
    Write-Host "卸载已取消。"
    exit 0
}

# ──────────────────────────────────────────────────────────────────────────────
# 阶段 1: 尝试 CLI 内置卸载器
# ──────────────────────────────────────────────────────────────────────────────
Write-Section "阶段 1: 尝试 CLI 内置卸载器"

$ocPath = Get-Command openclaw -ErrorAction SilentlyContinue
if ($ocPath) {
    Write-Info "发现 openclaw CLI，尝试内置卸载器..."
    & openclaw uninstall --all --yes --non-interactive 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Ok "CLI 内置卸载器执行完毕"
    } else {
        Write-Warn "CLI 内置卸载器未完全成功，继续手动清理..."
    }
} else {
    $npxPath = Get-Command npx -ErrorAction SilentlyContinue
    if ($npxPath) {
        Write-Info "未发现 openclaw CLI，尝试通过 npx 运行内置卸载器..."
        & npx -y openclaw uninstall --all --yes --non-interactive 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Ok "npx 内置卸载器执行完毕"
        } else {
            Write-Warn "npx 内置卸载器未完全成功，继续手动清理..."
        }
    } else {
        Write-Warn "未找到 openclaw CLI 和 npx，跳过内置卸载器，继续手动清理..."
    }
}

# ──────────────────────────────────────────────────────────────────────────────
# 阶段 2: 停止并卸载 Gateway 服务 (Windows 计划任务)
# ──────────────────────────────────────────────────────────────────────────────
Write-Section "阶段 2: 停止并卸载 Gateway 服务"

if (Get-Command openclaw -ErrorAction SilentlyContinue) {
    Write-Info "停止 openclaw gateway..."
    & openclaw gateway stop 2>$null
    & openclaw daemon uninstall 2>$null
}

# 删除计划任务
$taskName = "OpenClaw Gateway"
$task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($task) {
    Write-Info "删除计划任务 '$taskName'..."
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    Write-Ok "已删除计划任务 '$taskName'"
}

# profile 变体计划任务
$profileTasks = Get-ScheduledTask -ErrorAction SilentlyContinue |
    Where-Object { $_.TaskName -like "OpenClaw*" }
foreach ($t in $profileTasks) {
    Write-Info "删除计划任务 '$($t.TaskName)'..."
    Unregister-ScheduledTask -TaskName $t.TaskName -Confirm:$false -ErrorAction SilentlyContinue
    Write-Ok "已删除计划任务 '$($t.TaskName)'"
}

# 删除 gateway.cmd 包装脚本
$gatewayCmdPath = Join-Path $env:USERPROFILE ".openclaw\gateway.cmd"
if (Test-Path $gatewayCmdPath) {
    Remove-Item -Force $gatewayCmdPath -ErrorAction SilentlyContinue
    Write-Ok "已删除 $gatewayCmdPath"
}

# ──────────────────────────────────────────────────────────────────────────────
# 阶段 3: 卸载可选子组件
# ──────────────────────────────────────────────────────────────────────────────
Write-Section "阶段 3: 卸载可选子组件"

# 3.2 Docker 安装
$dockerCmd = Get-Command docker -ErrorAction SilentlyContinue
if ($dockerCmd) {
    $hasImage = & docker image inspect openclaw:local 2>$null
    if ($LASTEXITCODE -eq 0) {
        if (Confirm-Action "发现 OpenClaw Docker 镜像，是否移除？") {
            & docker compose down 2>$null
            & docker rmi openclaw:local 2>$null
            & docker rmi "openclaw-sandbox:bookworm-slim" 2>$null
            Write-Ok "已移除 OpenClaw Docker 镜像"
        }
    }
}

# 3.3 Podman 安装
$podmanCmd = Get-Command podman -ErrorAction SilentlyContinue
if ($podmanCmd) {
    $podmanContainer = Join-Path $env:USERPROFILE ".config\containers\systemd\openclaw.container"
    if (Test-Path $podmanContainer) {
        Write-Info "发现 Podman 配置，正在清理..."
        Remove-Item -Force $podmanContainer -ErrorAction SilentlyContinue
        Write-Ok "已删除 $podmanContainer"
    }
    $hasImage = & podman image inspect openclaw:local 2>$null
    if ($LASTEXITCODE -eq 0) {
        if (Confirm-Action "发现 OpenClaw Podman 镜像，是否移除？") {
            & podman rmi openclaw:local 2>$null
            Write-Ok "已移除 OpenClaw Podman 镜像"
        }
    }
}

# 3.4 Tailscale
$tailscaleCmd = Get-Command tailscale -ErrorAction SilentlyContinue
if ($tailscaleCmd) {
    if (Confirm-Action "是否重置 Tailscale Serve/Funnel 配置？") {
        & tailscale serve off 2>$null
        & tailscale funnel off 2>$null
        Write-Ok "已重置 Tailscale Serve/Funnel 配置"
    }
}

# ──────────────────────────────────────────────────────────────────────────────
# 阶段 4: 删除数据和配置文件
# ──────────────────────────────────────────────────────────────────────────────
Write-Section "阶段 4: 删除数据和配置文件"

$stateDir = if ($env:OPENCLAW_STATE_DIR) { $env:OPENCLAW_STATE_DIR } else { Join-Path $env:USERPROFILE ".openclaw" }

if (Test-Path $stateDir) {
    if (Confirm-Action "是否删除状态目录 $stateDir（包含配置、凭据、会话数据）？") {
        Remove-Item -Recurse -Force $stateDir -ErrorAction SilentlyContinue
        Write-Ok "已删除 $stateDir"
    }
} else {
    Write-Info "状态目录 $stateDir 不存在，跳过。"
}

# 自定义配置路径
if ($env:OPENCLAW_CONFIG_PATH -and (Test-Path $env:OPENCLAW_CONFIG_PATH)) {
    if (Confirm-Action "是否删除自定义配置文件 $env:OPENCLAW_CONFIG_PATH？") {
        Remove-Item -Force $env:OPENCLAW_CONFIG_PATH -ErrorAction SilentlyContinue
        Write-Ok "已删除 $env:OPENCLAW_CONFIG_PATH"
    }
}

# profile 变体状态目录
$profileDirs = Get-ChildItem -Path $env:USERPROFILE -Filter ".openclaw-*" -Directory -ErrorAction SilentlyContinue
foreach ($d in $profileDirs) {
    if (Confirm-Action "是否删除 profile 状态目录 $($d.FullName)？") {
        Remove-Item -Recurse -Force $d.FullName -ErrorAction SilentlyContinue
        Write-Ok "已删除 $($d.FullName)"
    }
}

# 日志目录
$logDir = Join-Path $env:TEMP "openclaw"
if (Test-Path $logDir) {
    Remove-Item -Recurse -Force $logDir -ErrorAction SilentlyContinue
    Write-Ok "已删除 $logDir"
}

# ──────────────────────────────────────────────────────────────────────────────
# 阶段 5: 卸载 CLI 全局包
# ──────────────────────────────────────────────────────────────────────────────
Write-Section "阶段 5: 卸载 CLI 全局包"

$removedCli = $false

if (Get-Command npm -ErrorAction SilentlyContinue) {
    $npmList = & npm list -g --depth=0 2>$null | Select-String "openclaw"
    if ($npmList) {
        Write-Info "通过 npm 卸载 openclaw..."
        & npm rm -g openclaw
        Write-Ok "已通过 npm 卸载 openclaw"
        $removedCli = $true
    }
}

if (Get-Command pnpm -ErrorAction SilentlyContinue) {
    $pnpmList = & pnpm list -g --depth=0 2>$null | Select-String "openclaw"
    if ($pnpmList) {
        Write-Info "通过 pnpm 卸载 openclaw..."
        & pnpm remove -g openclaw
        Write-Ok "已通过 pnpm 卸载 openclaw"
        $removedCli = $true
    }
}

if (Get-Command bun -ErrorAction SilentlyContinue) {
    $bunList = & bun pm ls -g 2>$null | Select-String "openclaw"
    if ($bunList) {
        Write-Info "通过 bun 卸载 openclaw..."
        & bun remove -g openclaw
        Write-Ok "已通过 bun 卸载 openclaw"
        $removedCli = $true
    }
}

if (-not $removedCli) {
    Write-Warn "未通过包管理器找到 openclaw，可能已手动安装或已卸载。"
}

# ──────────────────────────────────────────────────────────────────────────────
# 阶段 6: 清理源码安装
# ──────────────────────────────────────────────────────────────────────────────
Write-Section "阶段 6: 清理源码安装"

# 常见的 openclaw 源码克隆路径
$commonSrcPaths = @(
    (Join-Path $env:USERPROFILE "openclaw"),
    (Join-Path $env:USERPROFILE "src\openclaw"),
    (Join-Path $env:USERPROFILE "projects\openclaw"),
    (Join-Path $env:USERPROFILE "code\openclaw")
)

foreach ($srcPath in $commonSrcPaths) {
    $pkgJson = Join-Path $srcPath "package.json"
    if ((Test-Path $srcPath) -and (Test-Path $pkgJson)) {
        $pkgContent = Get-Content $pkgJson -Raw -ErrorAction SilentlyContinue
        if ($pkgContent -match '"name"\s*:\s*"openclaw"') {
            if (Confirm-Action "发现 openclaw 源码目录 $srcPath，是否删除？") {
                Remove-Item -Recurse -Force $srcPath -ErrorAction SilentlyContinue
                Write-Ok "已删除 $srcPath"
            }
        }
    }
}

Write-Info "如果你的源码安装路径不在上述常见位置，请手动执行: Remove-Item -Recurse -Force C:\path\to\openclaw"

# ──────────────────────────────────────────────────────────────────────────────
# 阶段 7: 提示清理环境变量
# ──────────────────────────────────────────────────────────────────────────────
Write-Section "阶段 7: 提示清理环境变量"

Write-Host @"
请手动检查并移除以下用户环境变量（系统属性 -> 环境变量）：
  OPENCLAW_STATE_DIR    OPENCLAW_CONFIG_PATH   OPENCLAW_HOME
  OPENCLAW_PROFILE      OPENCLAW_NIX_MODE      OPENCLAW_GATEWAY_BIND
  OPENCLAW_GATEWAY_TOKEN                       OPENCLAW_SKIP_CANVAS_HOST
  TELEGRAM_BOT_TOKEN    DISCORD_BOT_TOKEN      SLACK_BOT_TOKEN
  SLACK_APP_TOKEN       ZALO_BOT_TOKEN
  以及其他 OPENCLAW_* 开头的变量

也可以通过 PowerShell 批量删除（仅删除当前用户级别的变量）：
  [System.Environment]::GetEnvironmentVariables('User').Keys |
    Where-Object { $_ -like 'OPENCLAW_*' } |
    ForEach-Object { [System.Environment]::SetEnvironmentVariable($_, `$null, 'User') }
"@

# ──────────────────────────────────────────────────────────────────────────────
# 阶段 8: 验证卸载完成
# ──────────────────────────────────────────────────────────────────────────────
Write-Section "阶段 8: 验证卸载完成"

Write-Host ""

# CLI
if (Get-Command openclaw -ErrorAction SilentlyContinue) {
    Write-Warn "CLI 仍存在: $(Get-Command openclaw | Select-Object -ExpandProperty Source)"
} else {
    Write-Ok "CLI 已移除"
}

# 进程
$ocProcesses = Get-Process -Name "*openclaw*" -ErrorAction SilentlyContinue
if ($ocProcesses) {
    Write-Warn "仍有 openclaw 进程: $($ocProcesses.Id -join ', ')"
} else {
    Write-Ok "无残留 openclaw 进程"
}

# 计划任务
$remainingTasks = Get-ScheduledTask -ErrorAction SilentlyContinue |
    Where-Object { $_.TaskName -like "*openclaw*" -or $_.TaskName -like "*OpenClaw*" }
if ($remainingTasks) {
    Write-Warn "仍有计划任务: $($remainingTasks.TaskName -join ', ')"
} else {
    Write-Ok "无残留计划任务"
}

# 状态目录
$stateDir = if ($env:OPENCLAW_STATE_DIR) { $env:OPENCLAW_STATE_DIR } else { Join-Path $env:USERPROFILE ".openclaw" }
if (Test-Path $stateDir) {
    Write-Warn "状态目录仍存在: $stateDir"
} else {
    Write-Ok "状态目录已清理"
}

Write-Host ""
Write-Host "OpenClaw 卸载完成！" -ForegroundColor Green
Write-Host "如有残留项（显示 WARN），请根据提示手动处理。"
Write-Host "如需帮助，请访问: https://github.com/easeus/uninstall-openclaw"
