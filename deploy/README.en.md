# WebGpt (chatgpt.kunkun.chat) — Deployment Checklist & File Mapping

> [简体中文](README.md) | English
> Full tutorial: [`../docs/WEBGPT_DEPLOYMENT.zh-CN.md`](../docs/WEBGPT_DEPLOYMENT.zh-CN.md).
> This is only the "which machine, which files, in what order, how to verify" quick checklist. All tokens are redacted as `<REDACTED>`.

## 1. Roles & file mapping

```
Linux public server 66.92.18.39        Windows (Runner + project + Codex)
┌─────────────────────────┐        ┌──────────────────────────────┐
│ WebCodex Server 127.0.0.1:8080   │ webcodex-runner (polling)      │
│ webcodex.service / .socket        │ allowed_root=D:\work          │
│ webcodex-runner.service (Linux)   │ kunkun-tools.bat/.ps1        │
│ webcodex-tunnel.service           │ codex-acp-proxy.js (ACP)      │
│ run-tunnel.sh  ← tunnel-client    │ agent.toml (Windows)          │
│ Nginx + Cloudflare + Let's Encrypt│ project D:\work\dj-product   │
└─────────────────────────┘        └──────────────────────────────┘
```

| Machine | Copy from `deploy/` | Files |
|---|---|---|
| **Linux server** | `deploy/server/` | `webcodex.service`, `webcodex.socket`, `webcodex-runner.service`, `webcodex-tunnel.service`, `run-tunnel.sh`, `nginx.chatgpt.kunkun.chat.conf`, `webcodex.env.example`, `agent.toml.linux.example` |
| **Windows Runner** | `deploy/client/` | `kunkun-tools.bat`, `kunkun-tools.ps1`, `kunkun-config.ps1`, `kunkun-tools.env.example`, `codex-acp-proxy.js`, `agent.toml.windows.example`, `CODEX_SYSTEM_PROMPT.md`, `AGENTS.md` |

> `server/` and `client/` have their own READMEs; upstream `deploy/*.example` are generic templates, not used here.

## 2. Linux server — install checklist

> Prereqs: Node 18+, Git, Nginx, certbot; public domain `chatgpt.kunkun.chat` points to this host (Cloudflare-proxied).

- [ ] **① Install WebCodex**: `npm install -g @yyjeqhc/webcodex` && `webcodex --version`
- [ ] **② Init Server** (fill `webcodex.env.example` values):
  ```bash
  mkdir -p /etc/webcodex /root/.local/share/webcodex
  WEBCODEX_ADDR=127.0.0.1:8080
  WEBCODEX_DATA=/root/.local/share/webcodex
  WEBCODEX_PUBLIC_URL=https://chatgpt.kunkun.chat
  WEBCODEX_TOKEN=<REDACTED>
  WEBCODEX_SHARED_KEY_ENABLED=true
  ```
  or: `webcodex server init --listen 127.0.0.1:8080 --data-dir /root/.local/share/webcodex --env-file /etc/webcodex/webcodex.env --public-url https://chatgpt.kunkun.chat`
  > Pitfall: 0.3.9 `server install` fails because `systemctl is-active` returns non-zero for a not-yet-created unit; write `webcodex.service`/`webcodex.socket` manually (from `--dry-run`) then `daemon-reload; enable; start`.
- [ ] **③ systemd units**: copy `deploy/server/webcodex.service`, `webcodex.socket`, `webcodex-runner.service`, `webcodex-tunnel.service` to `/etc/systemd/system/`, then `systemctl daemon-reload && systemctl enable --now webcodex webcodex-runner webcodex-tunnel`.
- [ ] **④ Tunnel private files (0600)**: `/root/.config/openai/tunnel-api-key` (OpenAI `CONTROL_PLANE_API_KEY`), `webcodex-bearer` (`Bearer <wc_pat>`), `tunnel-health.url`.
- [ ] **⑤ OpenAI Tunnel env**: `/opt/openai-tunnel/run-tunnel.sh` references `--control-plane.tunnel-id tunnel_<...>`, `--control-plane.api-key file:...`, `--mcp.server-url http://127.0.0.1:8080/mcp`, `--mcp.extra-headers Authorization: file:...`.
- [ ] **⑥ Nginx + cert**: `/www/server/panel/vhost/nginx/chatgpt.kunkun.chat.conf`; `certbot certonly --webroot -w ... -d chatgpt.kunkun.chat`; `nginx -t && nginx -s reload`. `/webcodex-dl/` serves the client package.
- [ ] **⑦ Linux Runner** (`agent.toml.linux.example` → `/etc/webcodex/http_127.0.0.1_8080/saigou/agent.toml`): `allowed_roots=["/"]`; add `[acp]` for Coding Agent; Runner unit needs `Environment=CODEX_HOME=/root/.codex`, `Environment=HOME=/root`.
- [ ] **⑧ Grant `coding_agent:run`** (optional):
  ```bash
  webcodex tokens create --server-url http://127.0.0.1:8080 --username saigou \
    --name tunnel-full \
    --scope runtime:read --scope session:collaborate --scope project:read \
    --scope project:write --scope job:run --scope coding_agent:run
  # write the returned wc_pat_... into /root/.config/openai/webcodex-bearer, then restart webcodex-tunnel.service
  ```

## 3. Windows Runner — install checklist

- [ ] **① Standalone webcodex-cli**: `D:\WebGpt\webcodex-cli-win\bin\webcodex.js` (not in this repo; use the offline bundle). `node ...webcodex.js --version` → 0.3.9.
- [ ] **② Place client scripts**: extract `deploy/client/` into `D:\WebGpt` (`kunkun-tools.bat`, `kunkun-tools.ps1`, `kunkun-config.ps1`, `codex-acp-proxy.js`, `agent.toml.windows.example`, `CODEX_SYSTEM_PROMPT.md`, `AGENTS.md`).
- [ ] **③ Login (if not yet)**: `node webcodex-cli-win\bin\webcodex.js login https://chatgpt.kunkun.chat --code <wc_pair> --allowed-root D:\work`; the `agent.toml` lands at `%APPDATA%\webcodex\https_chatgpt.kunkun.chat\saigou\agent.toml`.
- [ ] **④ (Optional) Configure the connection**: `kunkun-tools.bat set-server https://chatgpt.kunkun.chat saigou` → `set-bootstrap <wc_pat>` → `add-mcp` (mints a `wc_pat_xxx` and writes the Codex MCP) → `set-apikey` (cache model API key) → `mode mcp|tunnel` to pick the connection mode. Config cache: `%USERPROFILE%\.kunkun-tools\client.json`.
- [ ] **⑤ Double-click `kunkun-tools.bat`** (auto: kill leftovers → detect node/codex → rewrite `[acp]` → set env → inject prompt → apply connection config → start Runner).
- [ ] **⑥ Prereq**: Codex CLI installed & logged in (`codex --version`; proxy uses the real `codex.exe` absolute path or `codex.js`).

## 4. Usage

- **Path A (recommended, core tools)**: in ChatGPT connect `WebGpt`, use `work_on_project`+`read_file`+`apply_text_edits`+`run_process`+`show_changes`. **No Codex dependency.**
- **Path B (optional, delegate Codex)**: `coding_agent_start(provider_id=codex,...)` + `coding_agent_observe`; requires a healthy Codex Responses API.

## 5. Verification

```bash
# Linux
webcodex ops agents --env-file /etc/webcodex/webcodex.env        # both Linux + Windows online
webcodex server status --env-file /etc/webcodex/webcodex.env      # HTTP reachable, configured_public_url
cat /root/.config/openai/tunnel-health.url | xargs -I{} curl -sS -o /dev/null -w "readyz=%{http_code}\n" {}/readyz
```
```powershell
# Windows (in the kunkun-tools.bat window)
# expect: registered client_id=... actual_transport=polling/websocket projects=N
```

---

> ⚠️ All `.example`/README are templates; tokens are `<REDACTED>`. Use your own private values at runtime; never commit real credentials.
