$ErrorActionPreference = "Stop"

# ---- [0] kill leftover WebGpt/Codex processes from a previous run ----
Write-Host "[0] killing previous WebGpt/Codex processes..."
try {
  $cands = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
    $_.Name -match '^(node|webcodex-runner|codex)' -and $_.CommandLine -match 'codex-acp-proxy|webcodex\.js agent run|webcodex-runner'
  }
  foreach ($c in $cands) { try { Stop-Process -Id $c.ProcessId -Force -ErrorAction SilentlyContinue } catch {} }
} catch { }
taskkill /IM webcodex-runner.exe /F 2>$null
taskkill /IM codex.exe /F 2>$null
taskkill /IM codex-command-runner.exe /F 2>$null
taskkill /IM codex-windows-sandbox-setup.exe /F 2>$null
Start-Sleep -Seconds 1
Write-Host "    cleanup done."

$node  = $env:WC_NODE
$cli   = $env:WC_CLI
$proxy = $env:WC_PROXY
$agent = $env:WC_AGENT

Write-Host "[1] node.exe   = $node"
Write-Host "[2] webcodex   = $cli"
Write-Host "[3] proxy      = $proxy"
Write-Host "[4] agent.toml = $agent"

# ---- resolve codex: prefer real codex.exe, then codex.js ----
$codexcmd = $null
$real = Get-ChildItem "$env:LOCALAPPDATA\OpenAI\Codex\bin" -Recurse -Filter "codex.exe" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($real) { $codexcmd = $real.FullName }
if (-not $codexcmd) {
  try {
    $c = (Get-Command codex -ErrorAction Stop).Source
    $cand = Join-Path (Split-Path $c -Parent) "node_modules\@openai\codex\bin\codex.js"
    if (Test-Path $cand) { $codexcmd = $cand }
  } catch { }
}
if (-not $codexcmd) {
  foreach ($p in @((Join-Path (Split-Path $node -Parent) "node_modules\@openai\codex\bin\codex.js"))) {
    if (Test-Path $p) { $codexcmd = $p; break }
  }
}
if (-not $codexcmd) { Write-Host "[x] codex not found. Install: npm i -g @openai/codex"; exit 1 }
Write-Host "[5] codex      = $codexcmd"

if (-not (Test-Path $agent)) { Write-Host "[x] agent.toml NOT found: $agent"; exit 1 }

# ---- rewrite [acp] section ----
$raw  = Get-Content $agent -Raw
$raw  = [regex]::Replace($raw, '(?s)\r?\n\[acp\].*$', '')
$nod  = $node  -replace '\\','\\'
$pxy  = $proxy -replace '\\','\\'
$block = @"

[acp]
max_concurrent_runs = 1
permission_timeout_secs = 5

[[acp.agents]]
id = "codex"
name = "Codex"
executable = "$nod"
args = ["$pxy"]
env_from_env = { "HOME" = "HOME", "CODEX_HOME" = "CODEX_HOME", "PATH" = "PATH", "CODEX_CMD" = "CODEX_CMD" }
allowed_config_options = []
"@
Set-Content $agent -Value ($raw.TrimEnd() + "`r`n" + $block) -NoNewline
Write-Host "[6] [acp] written to agent.toml (with PATH)"

# ---- env ----
$env:HOME = $env:USERPROFILE
$env:CODEX_HOME = Join-Path $env:USERPROFILE ".codex"
$env:CODEX_CMD = $codexcmd
Write-Host "[7] HOME=$env:HOME"
Write-Host "    CODEX_HOME=$env:CODEX_HOME"
Write-Host "    CODEX_CMD=$env:CODEX_CMD"

# ---- run runner ----
Write-Host "[8] starting runner: node $cli agent run --config $agent"
& $node $cli agent run --config $agent
