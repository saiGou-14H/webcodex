@echo off
setlocal EnableDelayedExpansion
set "DIR=%~dp0"

REM --- locate webcodex.js ---
set "CLI="
if exist "%DIR%webcodex-cli-win\bin\webcodex.js" set "CLI=%DIR%webcodex-cli-win\bin\webcodex.js"
if not defined CLI if exist "%DIR%..\webcodex-cli-win\bin\webcodex.js" set "CLI=%DIR%..\webcodex-cli-win\bin\webcodex.js"
if not defined CLI if exist "D:\WebGpt\webcodex-cli-win\bin\webcodex.js" set "CLI=D:\WebGpt\webcodex-cli-win\bin\webcodex.js"
if not defined CLI (
  echo [x] webcodex.js not found. Put webcodex-cli-win\bin\webcodex.js under D:\WebGpt.
  pause
  exit /b 1
)

set "PROXY=%DIR%codex-acp-proxy.js"
if not exist "%PROXY%" set "PROXY=D:\WebGpt\codex-acp-proxy.js"
if not exist "%PROXY%" (
  echo [x] codex-acp-proxy.js not found.
  pause
  exit /b 1
)

set "AGENT=%APPDATA%\webcodex\https_chatgpt.kunkun.chat\saigou\agent.toml"

REM --- find node.exe ---
set "NODE="
for /f "delims=" %%i in ('where node 2^>nul') do if not defined NODE set "NODE=%%i"
if not defined NODE (
  echo [x] node.exe not found on PATH.
  pause
  exit /b 1
)

set "WC_NODE=%NODE%"
set "WC_CLI=%CLI%"
set "WC_PROXY=%PROXY%"
set "WC_AGENT=%AGENT%"

REM --- forward all args to the launcher: config subcommands (show-config/add-mcp/...) ---
REM --- or an AGENTS.md/instructions file path (legacy). No args = launch runner. ---

if not exist "%DIR%webgpt-client.ps1" (
  echo [x] webgpt-client.ps1 not found next to this bat.
  pause
  exit /b 1
)

echo [.] DIR=%DIR%
powershell -NoProfile -ExecutionPolicy Bypass -File "%DIR%webgpt-client.ps1" %*
endlocal
