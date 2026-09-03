$ErrorActionPreference = "Stop"
$node  = $env:WC_NODE
$cli   = $env:WC_CLI
$proxy = $env:WC_PROXY
$agent = $env:WC_AGENT

Write-Host "[1] node.exe  = $node"
Write-Host "[2] CLI       = $cli"
Write-Host "[3] proxy     = $proxy"
Write-Host "[4] agent.toml= $agent"

# ---- 探测 codex.js（从 codex 命令/已知全局路径）----
$codexjs = $null
try {
  $codex = (Get-Command codex -ErrorAction Stop).Source
  $codexDir = Split-Path $codex -Parent
  $cand = Join-Path $codexDir "node_modules\@openai\codex\bin\codex.js"
  if (Test-Path $cand) { $codexjs = $cand }
} catch { }
if (-not $codexjs) {
  $cands = @(
    (Join-Path (Split-Path $node -Parent) "node_modules\@openai\codex\bin\codex.js"),
    "$env:USERPROFILE\AppData\Local\nvm\v24.2.0\node_modules\@openai\codex\bin\codex.js"
  )
  foreach ($p in $cands) { if (Test-Path $p) { $codexjs = $p; break } }
}
if (-not $codexjs) { Write-Host "[x] codex.js 未找到。请先运行: npm i -g @openai/codex"; exit 1 }
Write-Host "[5] codex.js  = $codexjs"

if (-not (Test-Path $agent)) { Write-Host "[x] agent.toml 未找到: $agent"; exit 1 }

# ---- 回填 [acp]：去掉旧 [acp]，追加带 PATH 的新段 ----
$raw = Get-Content $agent -Raw
$raw = [regex]::Replace($raw, '(?s)\r?\n\[acp\].*$', '')
$noded  = $node  -replace '\\', '\\'
$proxyd = $proxy -replace '\\', '\\'
$block = @"

[acp]
max_concurrent_runs = 1
permission_timeout_secs = 5

[[acp.agents]]
id = "codex"
name = "Codex"
executable = "$noded"
args = ["$proxyd"]
env_from_env = { "HOME" = "HOME", "CODEX_HOME" = "CODEX_HOME", "PATH" = "PATH" }
allowed_config_options = []
"@
Set-Content $agent -Value ($raw.TrimEnd() + "`r`n" + $block) -NoNewline
Write-Host "[6] 已将 [acp] 写入 agent.toml（含 PATH）"

# ---- 环境变量 ----
$env:HOME = $env:USERPROFILE
$env:CODEX_HOME = Join-Path $env:USERPROFILE ".codex"
$env:CODEX_CMD = $codexjs
Write-Host "[7] HOME=$env:HOME"
Write-Host "    CODEX_HOME=$env:CODEX_HOME"
Write-Host "    CODEX_CMD=$env:CODEX_CMD"

# ---- 拉起 Runner（前台）----
Write-Host "[8] 启动 Runner: node $cli agent run --config $agent"
& $node $cli agent run --config $agent
