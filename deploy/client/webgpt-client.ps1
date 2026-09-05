$ErrorActionPreference = "Stop"

# ---- config manager (dot-source; dispatched before any process action) ----
$cfgLib = Join-Path $PSScriptRoot "webgpt-config.ps1"
if (Test-Path $cfgLib) { . $cfgLib }

# ---- subcommand dispatch: config commands first, then interactive menu, then legacy arg ----
if ($args.Count -gt 0 -and (Get-Command Is-WcConfigCommand -ErrorAction SilentlyContinue) -and (Is-WcConfigCommand $args[0])) {
  $rest = @(); if ($args.Count -gt 1) { $rest = $args[1..($args.Count - 1)] }
  exit (Invoke-WcConfigCommand -Command $args[0] -Rest $rest)
}
if ($args.Count -eq 0) {
  # interactive menu (bt-panel style); option (1) continues into the launch chain
  if (Get-Command Show-WcMenu -ErrorAction SilentlyContinue) {
    $menuResult = Show-WcMenu
    if ($menuResult -ne 'launch') { exit }
  }
} else {
  $env:WC_INSTRUCTIONS_FILE = $args[0]
}

# ---- [0] kill leftover WebGpt/Codex processes from a previous run ----
Write-Host "[0] killing previous WebGpt/Codex processes..."
try {
  $cands = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
    $_.Name -match '^(node|webcodex-runner|codex)' -and $_.CommandLine -match 'codex-acp-proxy|webcodex\.js agent run|webcodex-runner'
  }
  foreach ($c in $cands) { try { Stop-Process -Id $c.ProcessId -Force -ErrorAction SilentlyContinue } catch {} }
} catch { }
cmd /c "taskkill /IM webcodex-runner.exe /F >nul 2>nul"
cmd /c "taskkill /IM codex.exe /F >nul 2>nul"
cmd /c "taskkill /IM codex-command-runner.exe /F >nul 2>nul"
cmd /c "taskkill /IM codex-windows-sandbox-setup.exe /F >nul 2>nul"
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
$raw  = Get-Content $agent -Raw -Encoding UTF8
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
env_from_env = { "HOME" = "HOME", "CODEX_HOME" = "CODEX_HOME", "PATH" = "PATH", "CODEX_CMD" = "CODEX_CMD", "WEBCODEX_BEARER" = "WEBCODEX_BEARER", "OPENAI_API_KEY" = "OPENAI_API_KEY", "OPENAI_BASE_URL" = "OPENAI_BASE_URL" }
allowed_config_options = []
"@
Set-Content $agent -Value ($raw.TrimEnd() + "`r`n" + $block) -NoNewline
Write-Host "[6] [acp] written to agent.toml (with PATH + WEBCODEX_BEARER/OPENAI_API_KEY/OPENAI_BASE_URL)"

# ---- env ----
$env:HOME = $env:USERPROFILE
$env:CODEX_HOME = Join-Path $env:USERPROFILE ".codex"
$env:CODEX_CMD = $codexcmd
Write-Host "[7] HOME=$env:HOME"
Write-Host "    CODEX_HOME=$env:CODEX_HOME"
Write-Host "    CODEX_CMD=$env:CODEX_CMD"

# ---- [7b] prompt injection (shared function from webgpt-config.ps1) ----
if (Get-Command Invoke-WcPromptInjection -ErrorAction SilentlyContinue) {
  Invoke-WcPromptInjection
} else {
  Write-Host "[7b] prompt injection skipped (config library not loaded)"
}

# ---- [7c] apply cached connection config (mode / bearer / apikey) ----
if (Get-Command Load-WcConfig -ErrorAction SilentlyContinue) {
  $wcCfg = Load-WcConfig
  if ($wcCfg -and $wcCfg.Count -gt 0) {
    Write-Host ("[7c] connection mode = " + [string]$wcCfg['mode'])
    if ([string]$wcCfg['apikey']) {
      $env:OPENAI_API_KEY = [string]$wcCfg['apikey']
      Write-Host ("      OPENAI_API_KEY  = " + (Mask-Secret ([string]$wcCfg['apikey'])))
    }
    if ([string]$wcCfg['api_base_url']) {
      $env:OPENAI_BASE_URL = [string]$wcCfg['api_base_url']
      Write-Host ("      OPENAI_BASE_URL = " + [string]$wcCfg['api_base_url'])
    }
    if ([string]$wcCfg['mode'] -eq 'tunnel' -and $wcCfg['tunnel'] -and [string]$wcCfg['tunnel'].bearer) {
      $env:WEBCODEX_BEARER = [string]$wcCfg['tunnel'].bearer
      Write-Host ("      WEBCODEX_BEARER = " + (Mask-Secret ([string]$wcCfg['tunnel'].bearer)) + " (tunnel)")
    } elseif ($wcCfg['mcp'] -and [string]$wcCfg['mcp'].bearer) {
      $env:WEBCODEX_BEARER = [string]$wcCfg['mcp'].bearer
      Write-Host ("      WEBCODEX_BEARER = " + (Mask-Secret ([string]$wcCfg['mcp'].bearer)) + " (mcp)")
    }
  }
}

# ---- run runner ----
Write-Host "[8] starting runner: node $cli agent run --config $agent"
& $node $cli agent run --config $agent
