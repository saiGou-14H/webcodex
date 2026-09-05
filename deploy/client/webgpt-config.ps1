# webgpt-config.ps1 — WebGpt client configuration manager (dot-source library)
#
# Dot-sourced by webgpt-client.ps1; all config subcommands run through the launcher:
#   webgpt-client.bat show-config | add-mcp | mode mcp|tunnel | mcp | tunnel |
#   set-apikey | edit-apikey | show-apikey | get-bearer | set-server | set-bootstrap | set-tunnel
#
# Config cache: %USERPROFILE%\.webgpt\client.json   (override with %WC_CONFIG%)
# Secrets (apikey / bearer / bootstrap) are stored there and protected with icacls.

$ErrorActionPreference = "Stop"

$script:WcConfigCommands = @(
  'show-config', 'add-mcp', 'mcp', 'tunnel', 'mode',
  'set-apikey', 'show-apikey', 'edit-apikey', 'get-bearer',
  'set-server', 'set-bootstrap', 'set-tunnel', 'help'
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

# ---- helpers ----

function Get-WcEffectiveMcpUrl {
  $cfg = Load-WcConfig
  if ([string]$cfg['mode'] -eq 'tunnel') {
    if ($cfg['tunnel'] -and [string]$cfg['tunnel'].url) { return [string]$cfg['tunnel'].url }
  } else {
    if ($cfg['mcp'] -and [string]$cfg['mcp'].url) { return [string]$cfg['mcp'].url }
  }
  if ([string]$cfg['server_url']) { return ([string]$cfg['server_url']).TrimEnd('/') + '/mcp' }
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
  & $codex mcp add webcodex --url $url --bearer-token-env-var WEBCODEX_BEARER 2>&1 | Out-String | Write-Host
}

# ---- add-mcp: mint wc_pat_xxx via `webcodex tokens create-local` + configure Codex MCP ----

function Add-WcMcp {
  $cfg = Load-WcConfig
  $node = $env:WC_NODE
  $cli  = $env:WC_CLI
  if (-not $cli -or -not $node) {
    Write-Host "[x] WC_NODE/WC_CLI not set. Run via: webgpt-client.bat add-mcp"
    return 1
  }
  $server = [string]$cfg['server_url']
  $user   = [string]$cfg['username']
  $boot   = [string]$cfg['bootstrap']
  if (-not $server) { Write-Host "[x] server_url not set. Use: webgpt-client.bat set-server <server-url> [username]"; return 1 }
  if (-not $user)   { Write-Host "[x] username not set. Use: webgpt-client.bat set-server <server-url> <username>"; return 1 }
  if (-not $boot)   { Write-Host "[x] bootstrap account credential not set. Use: webgpt-client.bat set-bootstrap <wc_pat>"; return 1 }
  $scopesCsv = Get-WcDefaultScopesCsv
  if ($cfg['scopes'] -and ($cfg['scopes'] -is [array])) { $scopesCsv = ($cfg['scopes'] -join ',') }
  Write-Host ("[mcp] minting token: webcodex tokens create-local (server=" + $server + ", user=" + $user + ")")
  $env:WEBCODEX_ACCOUNT_CREDENTIAL = $boot
  try {
    $out = (& $node $cli tokens create-local --server-url $server --username $user `
      --credential-env WEBCODEX_ACCOUNT_CREDENTIAL --name webgpt-mcp --scopes $scopesCsv 2>&1 | Out-String)
    $code = $LASTEXITCODE
  } finally {
    Remove-Item Env:\WEBCODEX_ACCOUNT_CREDENTIAL -ErrorAction SilentlyContinue
  }
  if ($code -ne 0) {
    Write-Host "[x] tokens create-local failed (exit $code):"
    Write-Host $out
    return 1
  }
  $tok = Get-WcTokenFromOutput $out
  if (-not $tok) {
    Write-Host "[x] could not parse wc_pat from output:"
    Write-Host $out
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
  Write-Host ("[config] file: " + (Get-WcConfigPath))
  if ($cfg.Count -eq 0) { Write-Host "  (empty - nothing configured yet)"; return }
  Write-Host ("  server_url    = " + [string]$cfg['server_url'])
  Write-Host ("  username      = " + [string]$cfg['username'])
  Write-Host ("  bootstrap     = " + (Mask-Secret ([string]$cfg['bootstrap'])))
  Write-Host ("  mode          = " + [string]$cfg['mode'])
  Write-Host ("  mcp.url       = " + [string]$cfg['mcp'].url)
  Write-Host ("  mcp.bearer    = " + (Mask-Secret ([string]$cfg['mcp'].bearer)))
  if ($cfg['tunnel']) {
    Write-Host ("  tunnel.url    = " + [string]$cfg['tunnel'].url)
    Write-Host ("  tunnel.bearer = " + (Mask-Secret ([string]$cfg['tunnel'].bearer)))
  }
  Write-Host ("  apikey        = " + (Mask-Secret ([string]$cfg['apikey'])))
  Write-Host ("  api_base_url  = " + [string]$cfg['api_base_url'])
}

function Show-WcConfigHelp {
  Write-Host "WebGpt client config commands:"
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
  Write-Host "  webgpt-client.bat                           # launch runner (applies cached config)"
}

function Invoke-WcConfigCommand {
  param([string]$Command, [string[]]$Rest = @())
  switch ($Command) {
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
    default { Write-Host ("[x] unknown config command: " + $Command); Show-WcConfigHelp; return 2 }
  }
}
