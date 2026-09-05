$ErrorActionPreference = "Stop"

# ---- config manager (dot-source; dispatched before any process action) ----
$cfgLib = Join-Path $PSScriptRoot "webgpt-config.ps1"
if (Test-Path $cfgLib) { . $cfgLib }

# ---- subcommand dispatch: config commands first, then legacy instructions-file arg ----
if ($args.Count -gt 0 -and (Get-Command Is-WcConfigCommand -ErrorAction SilentlyContinue) -and (Is-WcConfigCommand $args[0])) {
  $rest = @(); if ($args.Count -gt 1) { $rest = $args[1..($args.Count - 1)] }
  exit (Invoke-WcConfigCommand -Command $args[0] -Rest $rest)
}
if ($args.Count -gt 0) { $env:WC_INSTRUCTIONS_FILE = $args[0] }

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

# ---- [7b] prompt injection: inject project-level instructions into Codex via AGENTS.md ----
# Codex auto-loads $CODEX_HOME\AGENTS.md (global instructions) on every session, so we
# stage our WebCodex MCP prompt there. Source order: $env:WC_INSTRUCTIONS_FILE, then
# AGENTS.md, then CODEX_SYSTEM_PROMPT.md next to this script. If the source is
# CODEX_SYSTEM_PROMPT.md (a doc with surrounding prose), extract the ```markdown block.
function Get-InjectContent([string]$path) {
  $raw = Get-Content $path -Raw
  $m = [regex]::Match($raw, '(?s)```markdown\s*\r?\n(.*?)\r?\n```')
  if ($m.Success) { return $m.Groups[1].Value.TrimEnd() }
  return $raw.TrimEnd()
}
$injectSrc = $env:WC_INSTRUCTIONS_FILE
if (-not $injectSrc) {
  foreach ($cand in @((Join-Path $PSScriptRoot "AGENTS.md"), (Join-Path $PSScriptRoot "CODEX_SYSTEM_PROMPT.md"))) {
    if ($cand -and (Test-Path $cand)) { $injectSrc = $cand; break }
  }
}
if ($injectSrc -and (Test-Path $injectSrc)) {
  if (-not (Test-Path $env:CODEX_HOME)) { New-Item -ItemType Directory -Path $env:CODEX_HOME -Force | Out-Null }
  $dest = Join-Path $env:CODEX_HOME "AGENTS.md"
  $content = Get-InjectContent $injectSrc
  $lineCount = ($content -split "`n").Count

  # Marker-delimited block so injection is idempotent and non-destructive:
  #   - we never inject ourselves twice (a previous injected block is replaced)
  #   - any pre-existing global instructions the user still has in AGENTS.md are preserved
  $startMark = "<!-- webcodex-agents:start -->"
  $endMark   = "<!-- webcodex-agents:end -->"
  $block     = $startMark + "`r`n" + $content + "`r`n" + $endMark
  $pattern   = '(?s)' + [regex]::Escape($startMark) + '.*?' + [regex]::Escape($endMark)

  $existing = ""
  if (Test-Path $dest) {
    $existing = [System.IO.File]::ReadAllText($dest)
    $existing = ($existing -replace $pattern, '').TrimEnd()
  }
  if ($existing) { $new = $existing + "`r`n`r`n" + $block + "`r`n" }
  else           { $new = $block + "`r`n" }
  [System.IO.File]::WriteAllText($dest, $new, (New-Object System.Text.UTF8Encoding($false)))

  Write-Host "[7b] injected Codex instructions   -> $dest"
  Write-Host "        (from $injectSrc, $lineCount lines, idempotent + non-destructive)"
} else {
  Write-Host "[7b] no instructions file found — skipping prompt injection"
  Write-Host "        (set WC_INSTRUCTIONS_FILE or drop AGENTS.md next to this script)"
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
