# webgpt-config.ps1 — WebGpt client configuration manager (dot-source library)
#
# Dot-sourced by webgpt-client.ps1; all config subcommands run through the launcher:
#   webgpt-client.bat show-config | add-mcp | mode mcp|tunnel | mcp | tunnel |
#   set-apikey | edit-apikey | show-apikey | get-bearer | set-server | set-bootstrap | set-tunnel
#
# Config cache: %USERPROFILE%\.webgpt\client.json   (override with %WC_CONFIG%)
# Secrets (apikey / bearer / bootstrap) are stored there and protected with icacls.

$ErrorActionPreference = "Stop"

# Version stamp: printed by add-mcp/pair so we can tell which script build
# actually runs on a machine (update via the download bundle).
$script:WcScriptStamp = "2026-09-05-9"

$script:WcConfigCommands = @(
  'menu', 'show-config', 'add-mcp', 'mcp', 'tunnel', 'mode',
  'set-apikey', 'show-apikey', 'edit-apikey', 'get-bearer',
  'set-server', 'set-bootstrap', 'set-tunnel',
  'set-server-token', 'set-allowed-root', 'pair', 'help'
)

function Is-WcConfigCommand {
  param([string]$Command)
  return ($script:WcConfigCommands -contains $Command)
}

function Get-WcConfigPath {
  if ($env:WC_CONFIG) { return $env:WC_CONFIG }
  return (Join-Path (Join-Path $env:USERPROFILE ".webgpt") "client.json")
}

function ConvertFrom-JsonAsHashtable($obj) {
  if ($null -eq $obj) { return @{} }
  if ($obj -is [System.Collections.IList]) {
    $list = @()
    foreach ($it in $obj) { $list += ConvertFrom-JsonAsHashtable $it }
    return ,$list
  }
  if ($obj -is [pscustomobject]) {
    $h = @{}
    foreach ($p in $obj.PSObject.Properties) { $h[$p.Name] = ConvertFrom-JsonAsHashtable $p.Value }
    return $h
  }
  return $obj
}

function Load-WcConfig {
  $p = Get-WcConfigPath
  if (-not (Test-Path $p)) { return @{} }
  try { return ConvertFrom-JsonAsHashtable (Get-Content $p -Raw | ConvertFrom-Json) } catch { return @{} }
}

function Save-WcConfig {
  param($Cfg)
  $p = Get-WcConfigPath
  $dir = Split-Path $p -Parent
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  $json = $Cfg | ConvertTo-Json -Depth 8
  [System.IO.File]::WriteAllText($p, $json, (New-Object System.Text.UTF8Encoding($false)))
  try {
    $who = "$env:USERDOMAIN\$env:USERNAME"
    if (-not $env:USERDOMAIN) { $who = $env:USERNAME }
    & icacls $p /inheritance:r /grant:r "${who}:(R,W)" 2>$null | Out-Null
  } catch { }
}

function Set-WcField {
  param([string]$Name, $Value)
  $cfg = Load-WcConfig
  $cfg[$Name] = $Value
  Save-WcConfig $cfg
}

function Mask-Secret([string]$s) {
  if ([string]::IsNullOrWhiteSpace($s)) { return "(none)" }
  if ($s.Length -le 8) { return "****" }
  return "****" + $s.Substring($s.Length - 4)
}

function Get-WcTokenFromOutput([string]$out) {
  $m = [regex]::Match($out, 'wc_pat_[0-9a-fA-F]+')
  if ($m.Success) { return $m.Value }
  return $null
}

function Get-WcDefaultScopesCsv {
  return "runtime:read,session:collaborate,project:read,project:write,job:run,coding_agent:run"
}

function Get-WcCodexCmd {
  $c = $env:CODEX_CMD
  if ($c -and (Test-Path $c)) { return $c }
  try {
    $real = Get-ChildItem "$env:LOCALAPPDATA\OpenAI\Codex\bin" -Recurse -Filter "codex.exe" -ErrorAction SilentlyContinue |
      Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($real) { return $real.FullName }
  } catch { }
  try { return (Get-Command codex -ErrorAction Stop).Source } catch { }
  return $null
}

# ---- webgpt.env (extracted config next to the launcher) ----

function Get-WcEnvFilePath {
  if ($env:WC_ENV_FILE) { return $env:WC_ENV_FILE }
  $base = $null
  try { $base = Split-Path -Parent $MyInvocation.MyCommand.Path } catch { }
  if (-not $base) { $base = $PSScriptRoot }
  return (Join-Path $base "webgpt.env")
}

function Read-WcEnvFile {
  $p = Get-WcEnvFilePath
  if (-not (Test-Path $p)) { return @{} }
  $cfg = @{}
  foreach ($line in (Get-Content $p -ErrorAction SilentlyContinue)) {
    $line = $line.Trim()
    if (-not $line -or $line.StartsWith('#')) { continue }
    if ($line -notmatch '^([A-Za-z_][A-Za-z0-9_]*)\s*=') { continue }
    $k = $Matches[1]
    $v = $line.Substring($line.IndexOf('=') + 1).Trim()
    $v = $v.Trim('"').Trim("'")
    $cfg[$k] = $v
  }
  return $cfg
}

function Test-WcPlaceholder([string]$v) {
  if (-not $v) { return $false }
  return ($v -match '[<>]' -or $v -match '(?i)redacted|change|your|example|placeholder')
}

# Run native CLI via PowerShell's call operator with file redirection.
# PowerShell passes argv natively (no .NET ProcessStartInfo string parsing,
# which delivered an empty command line on the user's Windows box), and
# stderr goes to a file so the PS 5.1 EAP=Stop stderr trap cannot fire.
# Run native CLI via PowerShell's call operator with file redirection.
# PowerShell passes argv natively (no .NET ProcessStartInfo string parsing,
# which delivered an empty command line on the user's Windows box), and
# stderr goes to a file so the PS 5.1 EAP=Stop stderr trap cannot fire.
# NOTE: param is named ArgList - a param named $Args collides with the
# automatic $args variable (case-insensitive) and swallows the binding.
function Invoke-NativeCapture {
  param([string]$Exe, [string[]]$ArgList = @(), [int]$TimeoutMs = 120000)
  if (-not $Exe) { return @{ out = ""; err = "(internal: empty exe)"; code = -1; timedOut = $false } }
  if ($env:WC_DEBUG -eq '1') { Write-Host ("[debug-capture] exe=" + $Exe + " argc=" + $ArgList.Count) }
  $base = Join-Path $env:TEMP ("wcrun_" + [guid]::NewGuid().ToString("N"))
  $outFile = $base + ".out"
  $errFile = $base + ".err"
  $prevEAP = $ErrorActionPreference
  $code = -1
  try {
    $ErrorActionPreference = "Continue"
    & $Exe @ArgList 1> $outFile 2> $errFile
    $code = $LASTEXITCODE
  } catch {
    $code = -1
  } finally {
    $ErrorActionPreference = $prevEAP
  }
  $stdout = ""
  if (Test-Path $outFile) { $stdout = [string](Get-Content $outFile -Raw -ErrorAction SilentlyContinue); Remove-Item $outFile -Force -ErrorAction SilentlyContinue }
  $stderr = ""
  if (Test-Path $errFile) { $stderr = [string](Get-Content $errFile -Raw -ErrorAction SilentlyContinue); Remove-Item $errFile -Force -ErrorAction SilentlyContinue }
  return @{ out = $stdout; err = $stderr; code = $code; timedOut = $false }
}

function Invoke-WcWithRetry {
  param([string]$Exe, [string[]]$ArgList = @(), [int]$TimeoutMs = 120000, [int]$Retries = 3)
  $attempt = 0
  while ($true) {
    $attempt++
    $r = Invoke-NativeCapture -Exe $Exe -ArgList $ArgList -TimeoutMs $TimeoutMs
    if ($r.timedOut -and $attempt -lt $Retries) {
      Write-Host ("[retry] attempt " + $attempt + "/" + $Retries + " timed out - reconnecting (the CLI has no HTTP timeout; retries usually win)...")
      Start-Sleep -Seconds 3
      continue
    }
    return $r
  }
}

# Extra CLI proxy flags from env/config:
#   WC_CLI_PROXY=http://host:port  -> --proxy <url>
#   WC_CLI_NO_PROXY=1              -> --no-system-proxy (force direct)
# NOTE: do NOT read $env:WC_PROXY - the launcher already uses it for the
# ACP proxy script path (codex-acp-proxy.js), which is NOT an HTTP proxy.
function Get-WcCliProxyArgs {
  $cfg = Load-WcConfig
  $proxy = $env:WC_CLI_PROXY
  if (-not $proxy) { $proxy = [string]$cfg['cli_proxy'] }
  if ($proxy) { return @('--proxy', $proxy) }
  $noProxy = $env:WC_CLI_NO_PROXY
  if (-not $noProxy) { $noProxy = [string]$cfg['cli_no_proxy'] }
  if ($noProxy -and ($noProxy -eq '1' -or $noProxy -eq 'true' -or $noProxy -eq 'yes')) { return @('--no-system-proxy') }
  return @()
}

# Prefer the native webcodex binary (vendor\bin\webcodex.exe) directly,
# bypassing the node wrapper (webcodex.js) which has shown hangs under
# redirected stdio on Windows. Override: $env:WC_NATIVE=<exe path>;
# $env:WC_USE_WRAPPER=1 forces the node wrapper instead.
function Get-WcCliInvocation {
  param([string[]]$CliArgs)
  if ($env:WC_USE_WRAPPER -ne '1') {
    if ($env:WC_NATIVE -and (Test-Path $env:WC_NATIVE)) { return @{ exe = $env:WC_NATIVE; args = $CliArgs } }
    $cli = $env:WC_CLI
    if ($cli -and (Test-Path $cli)) {
      $bin = Split-Path -Parent $cli
      $pkg = Split-Path -Parent $bin
      $cand = Join-Path (Join-Path $pkg "vendor\bin") "webcodex.exe"
      if (Test-Path $cand) { return @{ exe = $cand; args = $CliArgs } }
    }
  }
  $node = $env:WC_NODE
  if ($node -and $env:WC_CLI) {
    $wrapperArgs = @($env:WC_CLI) + $CliArgs
    return @{ exe = $node; args = $wrapperArgs }
  }
  return $null
}

# ---- mode ----

function Set-WcMode([string]$mode) {
  if ($mode -ne 'mcp' -and $mode -ne 'tunnel') {
    Write-Host "[x] mode must be 'mcp' or 'tunnel' (got '$mode')"
    return
  }
  Set-WcField 'mode' $mode
  Write-Host ("[mode] connection mode = " + $mode)
  Apply-WcMcpConfig
}

function Show-WcMode {
  $cfg = Load-WcConfig
  $mode = [string]$cfg['mode']
  if (-not $mode) { $mode = "(not set; default = mcp)" }
  Write-Host ("[mode] " + $mode)
}

# ---- api key (cached locally) ----

function Set-WcApiKey {
  param([string]$Value = $null, [switch]$Edit)
  $cfg = Load-WcConfig
  $cur = [string]$cfg['apikey']
  $val = $Value
  if (-not $val) {
    if ($Edit -and $cur) {
      Write-Host ("[apikey] current (masked): " + (Mask-Secret $cur))
      $val = Read-Host "Enter NEW API key (Enter to keep current)"
      if (-not $val) { Write-Host "[apikey] unchanged"; return }
    } else {
      $val = Read-Host "Enter API key"
    }
  }
  $val = $val.Trim()
  if (-not $val) { Write-Host "[x] no API key provided"; return }
  Set-WcField 'apikey' $val
  Write-Host ("[apikey] saved and cached locally (masked: " + (Mask-Secret $val) + ")")
}

function Show-WcApiKey {
  param([switch]$Reveal)
  $cfg = Load-WcConfig
  $key = [string]$cfg['apikey']
  if (-not $key) { Write-Host "[apikey] not configured. Use: webgpt-client.bat set-apikey"; return }
  if ($Reveal) { Write-Host $key } else { Write-Host ("[apikey] (masked) " + (Mask-Secret $key)) }
}

# ---- server / bootstrap / tunnel ----

function Set-WcServer {
  param([string]$Url, [string]$Username)
  if (-not $Url) { Write-Host "[x] usage: set-server <server-url> [username]"; return }
  $cfg = Load-WcConfig
  $cfg['server_url'] = $Url.TrimEnd('/')
  if ($Username) { $cfg['username'] = $Username.Trim() }
  Save-WcConfig $cfg
  Write-Host ("[server] server_url = " + [string]$cfg['server_url'])
  if ($Username) { Write-Host ("[server] username   = " + $Username.Trim()) }
}

function Set-WcBootstrap {
  param([string]$Credential)
  if (-not $Credential) { Write-Host "[x] usage: set-bootstrap <wc_pat...>"; return }
  Set-WcField 'bootstrap' $Credential.Trim()
  Write-Host ("[bootstrap] saved (masked: " + (Mask-Secret $Credential.Trim()) + ")")
}

function Set-WcTunnel {
  param([string]$Url, [string]$Bearer)
  if (-not $Url) { Write-Host "[x] usage: set-tunnel <tunnel-mcp-url> [bearer]"; return }
  $cfg = Load-WcConfig
  $cfg['tunnel'] = @{ url = $Url.Trim(); bearer = [string]$Bearer }
  Save-WcConfig $cfg
  Write-Host ("[tunnel] url    = " + $Url.Trim())
  if ($Bearer) { Write-Host ("[tunnel] bearer = " + (Mask-Secret $Bearer.Trim())) }
}

# ---- server admin token (Option B: fully client-side provisioning) ----

function Set-WcServerToken {
  param([string]$Token)
  $val = $Token
  if (-not $val) {
    $val = Read-Host "Enter server admin token (WEBCODEX_TOKEN)"
  }
  if ($val) { $val = $val.Trim() }
  if (-not $val) { Write-Host "[x] no server token provided"; return }
  Set-WcField 'server_token' $val
  Write-Host ("[server-token] saved locally (masked: " + (Mask-Secret $val) + ")")
}

function Set-WcAllowedRoot {
  param([string]$Root)
  if (-not $Root) { Write-Host "[x] usage: set-allowed-root <path>"; return }
  Set-WcField 'allowed_root' $Root.Trim()
  Write-Host ("[allowed-root] " + $Root.Trim())
}

# ---- pair: fully client-side runner provisioning (Option B) ----
#   pairing create (client, admin token) -> auto login (client, consumes code once)
#   The wc_pair_... code is minted by POST /api/pairing/create and consumed once
#   by login/enroll; keep it purely automated here (no manual copy/paste).

function Pair-WcClient {
  param([string]$ClientId = $null)
  $cfg = Load-WcConfig
  $envMap = Read-WcEnvFile
  $node = $env:WC_NODE
  $cli  = $env:WC_CLI
  if (-not $cli -or -not $node) {
    Write-Host "[x] WC_NODE/WC_CLI not set. Run via: webgpt-client.bat pair"
    return 1
  }
  # resolve server / username / admin token / allowed root:
  #   1) config cache (set-server / set-server-token / set-allowed-root)
  #   2) webgpt.env (extracted config, read here)
  #   3) WC_SERVER_TOKEN env var
  $server = [string]$cfg['server_url']; if (-not $server) { $server = [string]$envMap['WEBCODEX_SERVER_URL'] }
  $user   = [string]$cfg['username'];   if (-not $user)   { $user   = [string]$envMap['WEBCODEX_USERNAME'] }
  $tok    = [string]$cfg['server_token']
  if (-not $tok) { $tok = [string]$envMap['WEBCODEX_TOKEN'] }
  if (-not $tok -and $env:WC_SERVER_TOKEN) { $tok = $env:WC_SERVER_TOKEN }
  if (Test-WcPlaceholder $tok) { $tok = "" }
  $allowedRoot = [string]$cfg['allowed_root']
  if (-not $allowedRoot) { $allowedRoot = [string]$envMap['WEBCODEX_ALLOWED_ROOT'] }
  if (-not $server) { Write-Host "[x] server_url not set. Use: webgpt-client.bat set-server <url> [username] or fill webgpt.env WEBCODEX_SERVER_URL"; return 1 }
  if (-not $user)   { Write-Host "[x] username not set. Use: webgpt-client.bat set-server <url> <username> or fill webgpt.env WEBCODEX_USERNAME"; return 1 }
  if (-not $tok)    { Write-Host "[x] server admin token not set. Use: webgpt-client.bat set-server-token <WEBCODEX_TOKEN>"; Write-Host "       or fill WEBCODEX_TOKEN in: $((Get-WcEnvFilePath))"; return 1 }

  # already logged in? find agent.toml (CLI names the dir like the server
  # URL with non-alphanumerics -> '_', e.g. https://x -> https_x)
  $hostPath = $server -replace '^https?://', ''
  $sanPath  = $server -replace '[^A-Za-z0-9.]', '_'
  $agentBase = Join-Path $env:APPDATA "webcodex"
  $candidates = @(
    (Join-Path (Join-Path (Join-Path $agentBase $sanPath) $user) "agent.toml"),
    (Join-Path (Join-Path (Join-Path $agentBase $hostPath) $user) "agent.toml")
  )
  $agentPath = $null
  foreach ($c in $candidates) { if (Test-Path $c) { $agentPath = $c; break } }
  if ($agentPath) {
    Write-Host ("[pair] already logged in to " + $server + " as " + $user + " (agent.toml: " + $agentPath + ")")
    Write-Host "       Nothing to do. To re-enroll: delete that agent.toml and re-run pair."
    return 0
  }

  # 1) client-side pairing create (token via env var, never on the command line)
  $env:WEBCODEX_TOKEN = $tok
  $pairInv = Get-WcCliInvocation -CliArgs @('pairing', 'create', '--server-url', $server,
    '--username', $user, '--ttl-secs', '600', '--json')
  if (-not $pairInv) { Write-Host "[x] no webcodex CLI executable found (WC_CLI/WC_NODE)"; return 1 }
  $pairArgs = [string[]]$pairInv.args
  $pairArgs += @(Get-WcCliProxyArgs)
  if ($ClientId) { $pairArgs += @('--client-id', $ClientId) }
  if ($env:WC_DEBUG -eq '1') { Write-Host ("[debug] exe=" + $pairInv.exe + " args=" + ($pairArgs -join ' ')) }
  Write-Host ("[pair] minting one-time code via server: " + $server)
  try {
    $r = Invoke-WcWithRetry -Exe $pairInv.exe -ArgList $pairArgs
    $out = $r.out; $code = $r.code
  } finally {
    Remove-Item Env:\WEBCODEX_TOKEN -ErrorAction SilentlyContinue
  }
  if ($code -ne 0) {
    Write-Host "[x] pairing create failed (exit $code):"
    Write-Host ($out + $r.err)
    return 1
  }
  $pc = $null
  try { $pc = $out.Trim() | ConvertFrom-Json } catch { }
  if (-not $pc -or -not $pc.pairing_code) {
    Write-Host "[x] could not parse pairing code from output:"
    Write-Host ($out + $r.err)
    return 1
  }
  $pcode = [string]$pc.pairing_code
  $did   = [string]$pc.client_id
  Write-Host ("[pair] one-time code minted (masked: " + (Mask-Secret $pcode) + "), expires " + [string]$pc.expires_at)

  # 2) auto login (consumes the code exactly once, right here)
  $loginInv = Get-WcCliInvocation -CliArgs @('login', $server, '--code', $pcode)
  $loginArgs = [string[]]$loginInv.args
  $loginArgs += @(Get-WcCliProxyArgs)
  if ($did) { $loginArgs += @('--device', $did) }
  if ($allowedRoot) { $loginArgs += @('--allowed-root', $allowedRoot) }
  Write-Host "[pair] logging in (code consumed on this machine)..."
  $r2 = Invoke-WcWithRetry -Exe $loginInv.exe -ArgList $loginArgs
  $out2 = $r2.out; $err2 = $r2.err; $code2 = $r2.code
  if (($out2 + $err2) -match 'Already logged in') {
    Write-Host "[pair] already logged in to $server as $user — nothing to change."
    Write-Host ("       agent.toml: " + $agentPath)
    return 0
  }
  if ($code2 -ne 0) {
    Write-Host "[x] login failed (exit $code2):"
    Write-Host ($out2 + $err2)
    Write-Host "(!) the one-time code was consumed; re-run: webgpt-client.bat pair"
    return 1
  }
  if ($out2) { Write-Host $out2 }
  Write-Host ("[pair] done. agent.toml = " + $agentPath)
  Write-Host "       Next: run 'webgpt-client.bat' (no args) to start the Runner."
  return 0
}

# ---- helpers ----

function Get-WcEffectiveMcpUrl {
  $cfg = Load-WcConfig
  $envMap = Read-WcEnvFile
  if ([string]$cfg['mode'] -eq 'tunnel') {
    if ($cfg['tunnel'] -and [string]$cfg['tunnel'].url) { return [string]$cfg['tunnel'].url }
  } else {
    if ($cfg['mcp'] -and [string]$cfg['mcp'].url) { return [string]$cfg['mcp'].url }
  }
  $server = [string]$cfg['server_url']
  if (-not $server) { $server = [string]$envMap['WEBCODEX_SERVER_URL'] }
  if ($server) { return $server.TrimEnd('/') + '/mcp' }
  return $null
}

function Apply-WcMcpConfig {
  $url = Get-WcEffectiveMcpUrl
  if (-not $url) { Write-Host "[!] no MCP url available; set server-url or tunnel url first"; return }
  $codex = Get-WcCodexCmd
  if (-not $codex) {
    Write-Host "[!] codex not found; configure manually:"
    Write-Host ("      codex mcp add webcodex --url " + $url + " --bearer-token-env-var WEBCODEX_BEARER")
    return
  }
  Write-Host ("[mcp] codex mcp add webcodex --url " + $url + " --bearer-token-env-var WEBCODEX_BEARER")
  $rc = Invoke-NativeCapture -Exe $codex -ArgList @('mcp', 'add', 'webcodex', '--url', $url, '--bearer-token-env-var', 'WEBCODEX_BEARER')
  if ($rc.out) { Write-Host $rc.out }
  if ($rc.err) { Write-Host $rc.err }
}

# ---- add-mcp: mint wc_pat_xxx via `webcodex tokens create-local` + configure Codex MCP ----

function Add-WcMcp {
  $cfg = Load-WcConfig
  $envMap = Read-WcEnvFile
  $node = $env:WC_NODE
  $cli  = $env:WC_CLI
  if (-not $cli -or -not $node) {
    Write-Host "[x] WC_NODE/WC_CLI not set. Run via: webgpt-client.bat add-mcp"
    return 1
  }
  $server = [string]$cfg['server_url']
  if (-not $server) { $server = [string]$envMap['WEBCODEX_SERVER_URL'] }
  $user = [string]$cfg['username']
  if (-not $user) { $user = [string]$envMap['WEBCODEX_USERNAME'] }
  # credential used by tokens create-local (register_hash needs admin-or-self):
  #   1) set-bootstrap value  2) webgpt.env WEBCODEX_BOOTSTRAP  3) server admin token
  $boot = [string]$cfg['bootstrap']
  if (-not $boot) { $boot = [string]$envMap['WEBCODEX_BOOTSTRAP'] }
  if (-not $boot) { $boot = [string]$cfg['server_token'] }
  if (-not $boot) { $boot = [string]$envMap['WEBCODEX_TOKEN'] }
  if (Test-WcPlaceholder $boot) { $boot = "" }
  if (-not $server) { Write-Host "[x] server_url not set. Use: webgpt-client.bat set-server <server-url> [username] OR fill webgpt.env WEBCODEX_SERVER_URL"; return 1 }
  if (-not $user)   { Write-Host "[x] username not set. Use: webgpt-client.bat set-server <server-url> <username> OR fill webgpt.env WEBCODEX_USERNAME"; return 1 }
  if (-not $boot)   { Write-Host "[x] no account/admin credential for token mint. Use: webgpt-client.bat set-bootstrap <wc_pat> OR fill webgpt.env WEBCODEX_BOOTSTRAP / WEBCODEX_TOKEN"; return 1 }
  $scopesCsv = Get-WcDefaultScopesCsv
  if ($cfg['scopes'] -and ($cfg['scopes'] -is [array])) { $scopesCsv = ($cfg['scopes'] -join ',') }
  Write-Host ("[mcp] script=" + $script:WcScriptStamp + " minting token: webcodex tokens create-local (server=" + $server + ", user=" + $user + ")")
  $env:WEBCODEX_ACCOUNT_CREDENTIAL = $boot
  try {
    $mcpInv = Get-WcCliInvocation -CliArgs @('tokens', 'create-local',
      '--server-url', $server, '--username', $user,
      '--credential-env', 'WEBCODEX_ACCOUNT_CREDENTIAL', '--name', 'webgpt-mcp', '--scopes', $scopesCsv)
    if (-not $mcpInv) { Write-Host "[x] no webcodex CLI executable found (WC_CLI/WC_NODE)"; return 1 }
    $mcpArgs = [string[]]$mcpInv.args
    $mcpArgs += @(Get-WcCliProxyArgs)
    Write-Host ("[diag] exe=" + $mcpInv.exe + " argc=" + $mcpArgs.Count + " argv=" + ($mcpArgs -join ' | '))
    if ($env:WC_DEBUG -eq '1') { Write-Host ("[debug] exe=" + $mcpInv.exe + " args=" + ($mcpArgs -join ' ')) }
    $r = Invoke-WcWithRetry -Exe $mcpInv.exe -ArgList $mcpArgs
    $out = $r.out; $code = $r.code
  } finally {
    Remove-Item Env:\WEBCODEX_ACCOUNT_CREDENTIAL -ErrorAction SilentlyContinue
  }
  if ($code -ne 0) {
    Write-Host "[x] tokens create-local failed (exit $code):"
    Write-Host ($out + $r.err)
    return 1
  }
  $tok = Get-WcTokenFromOutput $out
  if (-not $tok) {
    Write-Host "[x] could not parse wc_pat from output:"
    Write-Host ($out + $r.err)
    return 1
  }
  $cfg['mcp'] = @{ url = ($server.TrimEnd('/') + '/mcp'); bearer = $tok; bearer_env = 'WEBCODEX_BEARER' }
  $cfg['mode'] = 'mcp'
  Save-WcConfig $cfg
  Write-Host ("[mcp] token minted + cached (masked: " + (Mask-Secret $tok) + "), mode set to mcp")
  Apply-WcMcpConfig
  Write-Host "[mcp] done. Running 'webgpt-client.bat' (no args) will export WEBCODEX_BEARER for Codex."
  Write-Host "      (want the tunnel path instead? run: webgpt-client.bat mode tunnel)"
  return 0
}

# ---- inspect ----

function Show-WcConfig {
  $cfg = Load-WcConfig
  $envMap = Read-WcEnvFile
  Write-Host ("[config] file: " + (Get-WcConfigPath))
  $envFile = Get-WcEnvFilePath
  Write-Host ("[config] webgpt.env: " + $envFile + " (" + $(if (Test-Path $envFile) { "present" } else { "missing" }) + ")")
  if ($cfg.Count -eq 0) { Write-Host "  (empty - nothing configured yet)"; return }
  Write-Host ("  server_url    = " + [string]$cfg['server_url'])
  Write-Host ("  username      = " + [string]$cfg['username'])
  Write-Host ("  bootstrap     = " + (Mask-Secret ([string]$cfg['bootstrap'])))
  Write-Host ("  server_token  = " + (Mask-Secret ([string]$cfg['server_token'])))
  Write-Host ("  allowed_root  = " + [string]$cfg['allowed_root'])
  Write-Host ("  mode          = " + [string]$cfg['mode'])
  Write-Host ("  mcp.url       = " + [string]$cfg['mcp'].url)
  Write-Host ("  mcp.bearer    = " + (Mask-Secret ([string]$cfg['mcp'].bearer)))
  if ($cfg['tunnel']) {
    Write-Host ("  tunnel.url    = " + [string]$cfg['tunnel'].url)
    Write-Host ("  tunnel.bearer = " + (Mask-Secret ([string]$cfg['tunnel'].bearer)))
  }
  Write-Host ("  apikey        = " + (Mask-Secret ([string]$cfg['apikey'])))
  Write-Host ("  api_base_url  = " + [string]$cfg['api_base_url'])
  $envKeys = @()
  foreach ($k in @('WEBCODEX_SERVER_URL', 'WEBCODEX_USERNAME', 'WEBCODEX_BOOTSTRAP', 'WEBCODEX_ALLOWED_ROOT')) {
    if ([string]$envMap[$k]) { $envKeys += $k }
  }
  if ([string]$envMap['WEBCODEX_TOKEN'] -and -not (Test-WcPlaceholder ([string]$envMap['WEBCODEX_TOKEN']))) { $envKeys += 'WEBCODEX_TOKEN' }
  if ($envKeys.Count -gt 0) { Write-Host ("  webgpt.env keys = " + ($envKeys -join ', ')) }
}

function Show-WcConfigHelp {
  Write-Host "WebGpt client config commands:"
  Write-Host "  webgpt-client.bat menu                       # interactive menu (same as no args)"
  Write-Host "  webgpt-client.bat show-config               # show cached config (secrets masked)"
  Write-Host "  webgpt-client.bat set-server <url> [username]"
  Write-Host "  webgpt-client.bat set-bootstrap <wc_pat>    # account credential used to mint tokens"
  Write-Host "  webgpt-client.bat add-mcp                   # mint wc_pat_... + configure Codex MCP"
  Write-Host "  webgpt-client.bat mode [mcp|tunnel]         # choose connection mode"
  Write-Host "  webgpt-client.bat mcp | tunnel              # shorthand for mode"
  Write-Host "  webgpt-client.bat set-apikey [key]          # cache model API key (prompts if omitted)"
  Write-Host "  webgpt-client.bat edit-apikey [key]         # change cached API key"
  Write-Host "  webgpt-client.bat show-apikey [--reveal]    # show cached API key (masked by default)"
  Write-Host "  webgpt-client.bat get-bearer                # print cached wc_pat (full)"
  Write-Host "  webgpt-client.bat set-tunnel <url> [bearer]"
  Write-Host "  webgpt-client.bat set-server-token <t>      # cache server admin token (or fill webgpt.env)"
  Write-Host "  webgpt-client.bat set-allowed-root <path>   # Runner allowed root (used by pair)"
  Write-Host "  webgpt-client.bat pair [client-id]          # CLI-side pairing create + auto login"
  Write-Host "  webgpt-client.bat                           # interactive menu (no args)"
}

# Interactive menu (bt-panel style). Returns 'launch' to continue into the
# runner start chain, 'exit' to quit, or loops until the user chooses.
function Show-WcMenu {
  while ($true) {
    Write-Host ""
    Write-Host "==================================================="
    Write-Host " WebGpt Client -- Windows Runner + Codex"
    Write-Host "==================================================="
    Write-Host " (1) Start Runner (launch)"
    Write-Host " (2) One-shot setup / login (pair)"
    Write-Host " (3) Add MCP config (add-mcp)"
    Write-Host " (4) Set / edit API key (edit-apikey)"
    Write-Host " (5) Connection mode: mcp / tunnel"
    Write-Host " (6) Show config (masked)"
    Write-Host " (7) Show MCP bearer (get-bearer)"
    Write-Host " (8) Show API key (show-apikey)"
    Write-Host " (9) Command help"
    Write-Host " (0) Exit"
    Write-Host "==================================================="
    $ans = Read-Host "Please enter a number"
    $ans = ($ans -as [int])
    switch ($ans) {
      1 { Write-Host "=> Starting Runner..."; return "launch" }
      2 { $null = Invoke-WcConfigCommand -Command 'pair' }
      3 { $null = Invoke-WcConfigCommand -Command 'add-mcp' }
      4 { $null = Invoke-WcConfigCommand -Command 'edit-apikey' }
      5 {
        $m = Read-Host "mode (mcp/tunnel)"
        if ($m) { $null = Invoke-WcConfigCommand -Command 'mode' -Rest @($m.Trim()) }
      }
      6 { $null = Invoke-WcConfigCommand -Command 'show-config' }
      7 { $null = Invoke-WcConfigCommand -Command 'get-bearer' }
      8 { $null = Invoke-WcConfigCommand -Command 'show-apikey' }
      9 { $null = Invoke-WcConfigCommand -Command 'help' }
      0 { Write-Host "Bye."; return "exit" }
      default { Write-Host "[x] invalid choice: $ans" }
    }
    $null = Read-Host "Press Enter to go back to the menu"
  }
}

function Invoke-WcConfigCommand {
  param([string]$Command, [string[]]$Rest = @())
  switch ($Command) {
    'menu'        { $r = Show-WcMenu; if ($r -eq 'launch') { Write-Host "To launch the Runner, run 'webgpt-client.bat' with no args." }; return 0 }
    'help'        { Show-WcConfigHelp; return 0 }
    'show-config' { Show-WcConfig; return 0 }
    'add-mcp'     { return (Add-WcMcp) }
    'mcp'         { Set-WcMode 'mcp'; return 0 }
    'tunnel'      { Set-WcMode 'tunnel'; return 0 }
    'mode' {
      if ($Rest.Count -gt 0 -and $Rest[0] -in @('mcp', 'tunnel')) { Set-WcMode $Rest[0] }
      else { Show-WcMode }
      return 0
    }
    'set-apikey' {
      if ($Rest.Count -gt 0) { Set-WcApiKey -Value $Rest[0] } else { Set-WcApiKey }
      return 0
    }
    'edit-apikey'   { Set-WcApiKey -Edit; return 0 }
    'show-apikey'   { Show-WcApiKey -Reveal:($Rest -contains '--reveal'); return 0 }
    'get-bearer' {
      $cfg = Load-WcConfig
      if ($cfg['mcp'] -and [string]$cfg['mcp'].bearer) { Write-Host ([string]$cfg['mcp'].bearer); return 0 }
      Write-Host "[x] no mcp bearer cached. Run add-mcp first."
      return 1
    }
    'set-server' {
      $u = $null; if ($Rest.Count -gt 1) { $u = $Rest[1] }
      Set-WcServer -Url $(if ($Rest.Count -gt 0) { $Rest[0] } else { $null }) -Username $u
      return 0
    }
    'set-bootstrap' {
      Set-WcBootstrap -Credential $(if ($Rest.Count -gt 0) { $Rest[0] } else { $null })
      return 0
    }
    'set-tunnel' {
      $b = $null; if ($Rest.Count -gt 1) { $b = $Rest[1] }
      Set-WcTunnel -Url $(if ($Rest.Count -gt 0) { $Rest[0] } else { $null }) -Bearer $b
      return 0
    }
    'set-server-token' {
      Set-WcServerToken -Token $(if ($Rest.Count -gt 0) { $Rest[0] } else { $null })
      return 0
    }
    'set-allowed-root' {
      Set-WcAllowedRoot -Root $(if ($Rest.Count -gt 0) { $Rest[0] } else { $null })
      return 0
    }
    'pair' {
      return (Pair-WcClient -ClientId $(if ($Rest.Count -gt 0) { $Rest[0] } else { $null }))
    }
    default { Write-Host ("[x] unknown config command: " + $Command); Show-WcConfigHelp; return 2 }
  }
}
