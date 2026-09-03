@echo off
setlocal EnableDelayedExpansion
chcp 65001 >nul
set "DIR=%~dp0"

REM ---- 自动定位 webcodex.js（在本目录及父目录找）----
set "CLI="
for %%p in (
  "%DIR%webcodex-cli-win\bin\webcodex.js"
  "%DIR%..\webcodex-cli-win\bin\webcodex.js"
  "%DIR%..\..\webcodex-cli-win\bin\webcodex.js"
) do if not defined CLI if exist "%%~p" set "CLI=%%~p"
if not defined CLI ( echo [x] 未找到 webcodex-cli-win\bin\webcodex.js & pause & exit /b 1 )

set "PROXY=%DIR%codex-acp-proxy.js"
if not exist "%PROXY%" ( echo [x] 未找到代理 %PROXY% & pause & exit /b 1 )

set "AGENT=%APPDATA%\webcodex\https_chatgpt.kunkun.chat\saigou\agent.toml"

REM ---- 探测 node.exe（优先 .exe，其次任意 node）----
set "NODE="
for /f "delims=" %%i in ('where node 2^>nul ^| findstr /i "node\.exe$"') do if not defined NODE set "NODE=%%i"
if not defined NODE (
  for /f "delims=" %%i in ('where node 2^>nul') do if not defined NODE set "NODE=%%i"
)
if not defined NODE ( echo [x] 未找到 node.exe，请确认 Node 已安装并在 PATH & pause & exit /b 1 )
if not exist "%NODE%" ( echo [x] node.exe 不存在: "%NODE%" & pause & exit /b 1 )

set "WC_NODE=%NODE%"
set "WC_CLI=%CLI%"
set "WC_PROXY=%PROXY%"
set "WC_AGENT=%AGENT%"

set "H=%DIR%webgpt-client.ps1"
if not exist "%H%" ( echo [x] 缺少助手脚本 %H% & pause & exit /b 1 )

echo [.] 目录: %DIR%
echo [.] 将自动探测 codex.js、回填 [acp]、并启动 Runner...
powershell -NoProfile -ExecutionPolicy Bypass -File "%H%"
endlocal
