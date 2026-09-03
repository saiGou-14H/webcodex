$ErrorActionPreference = "Stop"
$node  = $env:WC_NODE
$cli   = $env:WC_CLI
$proxy = $env:WC_PROXY
$agent = $env:WC_AGENT

Write-Host "[1] node.exe   = $node"
Write-Host "[2] webcodex   = $cli"
Write-Host "[3] proxy      = $proxy"
Write-Host "[4] agent.toml = $agent"

# ---- resolve codex.js ----
$codexjs = $null
try {
  $codex = (Get-Command codex -ErrorAction Stop).Source
  $cand = Join-Path (Split-Path $codex -Parent) "node_modules\@openai\codex\bin\codex.js"
  if (Test-Path $cand) { $codexjs = $cand }
} catch { }
if (-not $codexjs) {
  foreach ($p in @(
    (Join-Path (Split-Path $node -Parent) "node_modules\@openai\codex\bin\codex.js"),
    "$env:USERPROFILE\AppData\Local\nvm\v24.2.0\node_modules\@openai\codex\bin\codex.js"
  )) { if (Test-Path $p) { $codexjs = $p; break } }
}
if (-not $codexjs) { Write-Host "[x] codex.js NOT found. Install: npm i -g @openai/codex"; exit 1 }
Write-Host "[5] codex.js   = $codexjs"

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
$env:CODEX_CMD = $codexjs
Write-Host "[7] HOME=$env:HOME"
Write-Host "    CODEX_HOME=$env:CODEX_HOME"
Write-Host "    CODEX_CMD=$env:CODEX_CMD"

# ---- run runner ----
Write-Host "[8] starting runner: node $cli agent run --config $agent"
& $node $cli agent run --config $agent
