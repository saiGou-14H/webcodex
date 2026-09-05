# WebGpt（chatgpt.kunkun.chat）部署清单与文件对照

[简体中文](README.md) | [English](README.en.md)

> 完整教程见 [`../docs/WEBGPT_DEPLOYMENT.zh-CN.md`](../docs/WEBGPT_DEPLOYMENT.zh-CN.md)。
> 本文只给「哪台机器、放哪些文件、按什么顺序、怎么验证」的速览清单。所有 token 均脱敏为 `<REDACTED>`。

## 1. 角色与文件对应

```
Linux 公网服务器 66.92.18.39        Windows（Runner + 项目 + Codex）
┌─────────────────────────┐        ┌──────────────────────────────┐
│ WebCodex Server 127.0.0.1:8080   │ webcodex-runner（polling）      │
│ webcodex.service / .socket        │ allowed_root=D:\work          │
│ webcodex-runner.service (Linux)   │ webgpt-client.bat/.ps1        │
│ webcodex-tunnel.service           │ codex-acp-proxy.js (ACP)      │
│ run-tunnel.sh  ← tunnel-client    │ agent.toml (Windows)          │
│ Nginx + Cloudflare + Let's Encrypt│ 项目 D:\work\dj-product       │
└─────────────────────────┘        └──────────────────────────────┘
```

| 机器 | 复制 `deploy/` 里的路径 | 对应文件 |
|---|---|---|
| **Linux 服务器** | `deploy/server/` | `webcodex.service`、`webcodex.socket`、`webcodex-runner.service`、`webcodex-tunnel.service`、`run-tunnel.sh`、`nginx.chatgpt.kunkun.chat.conf`、`webcodex.env.example`、`agent.toml.linux.example` |
| **Windows Runner** | `deploy/client/` | `webgpt-client.bat`、`webgpt-client.ps1`、`webgpt-config.ps1`、`codex-acp-proxy.js`、`agent.toml.windows.example`、`CODEX_SYSTEM_PROMPT.md`、`AGENTS.md` |

> `server/` 与 `client/` 各自 README 有更细说明；`deploy/*.example`（上游通用模板）与本实例无关，仅作参考。

## 2. Linux 服务器 —— 部署清单

> 假设：Node 18+、Git、Nginx、certbot 已装；公网域名 `chatgpt.kunkun.chat` 已指向本机（Cloudflare 代理）。

- [ ] **① 装 WebCodex**：`npm install -g @yyjeqhc/webcodex` && `webcodex --version`
- [ ] **② Server 初始化（写入 `webcodex.env.example` 的实际值）**：
  ```bash
  mkdir -p /etc/webcodex /root/.local/share/webcodex
  WEBCODEX_ADDR=127.0.0.1:8080
  WEBCODEX_DATA=/root/.local/share/webcodex
  WEBCODEX_PUBLIC_URL=https://chatgpt.kunkun.chat
  WEBCODEX_TOKEN=<REDACTED>
  WEBCODEX_SHARED_KEY_ENABLED=true
  ```
  或：`webcodex server init --listen 127.0.0.1:8080 --data-dir /root/.local/share/webcodex --env-file /etc/webcodex/webcodex.env --public-url https://chatgpt.kunkun.chat`
  > 坑：0.3.9 的 `server install` 会因 `systemctl is-active` 对全新 unit 返回非零而失败；需按 `--dry-run` 手动写 `webcodex.service`/`webcodex.socket` 再 `daemon-reload; enable; start`。
- [ ] **③ systemd 单元**：把 `deploy/server/webcodex.service`、`webcodex.socket`、`webcodex-runner.service`、`webcodex-tunnel.service` 放到 `/etc/systemd/system/`，`systemctl daemon-reload && systemctl enable --now webcodex webcodex-runner webcodex-tunnel`。
- [ ] **④ 隧道私有文件（0600）**：`/root/.config/openai/tunnel-api-key`（OpenAI `CONTROL_PLANE_API_KEY`）、`webcodex-bearer`（`Bearer <wc_pat>`）、`tunnel-health.url`。
- [ ] **⑤ OpenAI Tunnel 环境**：`/opt/openai-tunnel/run-tunnel.sh` 引用 `--control-plane.tunnel-id tunnel_<...>` 与 `--control-plane.api-key file:...`、`--mcp.server-url http://127.0.0.1:8080/mcp`、`--mcp.extra-headers Authorization: file:...`。
- [ ] **⑥ Nginx + 证书**：`/www/server/panel/vhost/nginx/chatgpt.kunkun.chat.conf`；`certbot certonly --webroot -w ... -d chatgpt.kunkun.chat`；`nginx -t && nginx -s reload`。`/webcodex-dl/` 静态用于分发客户端包。
- [ ] **⑦ Linux Runner（`agent.toml.linux.example` → `/etc/webcodex/http_127.0.0.1_8080/saigou/agent.toml`）**：`allowed_roots=["/"]`；若启用 Coding Agent 加 `[acp]`；Runner 服务需 `Environment=CODEX_HOME=/root/.codex`、`Environment=HOME=/root`。
- [ ] **⑧ 授予 `coding_agent:run`**（可选）：
  ```bash
  webcodex tokens create --server-url http://127.0.0.1:8080 --username saigou \
    --name tunnel-full \
    --scope runtime:read --scope session:collaborate --scope project:read \
    --scope project:write --scope job:run --scope coding_agent:run
  # 生成的 wc_pat_... 写入 /root/.config/openai/webcodex-bearer，并重启 webcodex-tunnel.service
  ```

## 3. Windows Runner —— 部署清单

- [ ] **① 自包含 webcodex-cli**：`D:\WebGpt\webcodex-cli-win\bin\webcodex.js`（本仓库无此文件，用免安装包；README 见 `docs/`）。`node ...webcodex.js --version` 应 0.3.9。
- [ ] **② 放置客户端脚本**：`deploy/client/` 全部解到 `D:\WebGpt`（`webgpt-client.bat`、`webgpt-client.ps1`、`webgpt-config.ps1`、`codex-acp-proxy.js`、`agent.toml.windows.example`、`CODEX_SYSTEM_PROMPT.md`、`AGENTS.md`）。
- [ ] **③ 登录（若未登录）**：`node webcodex-cli-win\bin\webcodex.js login https://chatgpt.kunkun.chat --code <wc_pair> --allowed-root D:\work`，拿到 `agent.toml`（在 `%APPDATA%\webcodex\https_chatgpt.kunkun.chat\saigou\agent.toml`）。
- [ ] **④ （可选）配置连接**：`webgpt-client.bat set-server https://chatgpt.kunkun.chat saigou` → `set-bootstrap <wc_pat>` → `add-mcp`（自动签发 `wc_pat_xxx` 并写入 Codex MCP）→ `set-apikey`（缓存模型 API Key）→ `mode mcp|tunnel` 选连接模式。配置缓存于 `%USERPROFILE%\.webgpt\client.json`。
- [ ] **⑤ 双击 `webgpt-client.bat`**（自动：杀残留 → 探测 node/codex → 回填 `[acp]` → 设 env → 提示词注入 → 应用连接配置 → 启动 Runner）。
- [ ] **⑥ 前置**：Codex CLI 已装且登录（`codex --version`；代理用真实 `codex.exe` 绝对路径或 `codex.js`）。

## 4. 使用

- **路径 A（推荐，核心工具）**：在 ChatGPT 连 `WebGpt`，用 `work_on_project`+`read_file`+`apply_text_edits`+`run_process`+`show_changes` 直接开发。**不依赖 Codex。**
- **路径 B（可选，委托 Codex）**：`coding_agent_start(provider_id=codex,...)` + `coding_agent_observe`；需 Codex Responses API 健康。

## 5. 验证清单

```bash
# Linux
webcodex ops agents --env-file /etc/webcodex/webcodex.env        # Linux + Windows 都 online
webcodex server status --env-file /etc/webcodex/webcodex.env      # HTTP reachable、configured_public_url
cat /root/.config/openai/tunnel-health.url | xargs -I{} curl -sS -o /dev/null -w "readyz=%{http_code}\n" {}/readyz
```
```powershell
# Windows（在 webgpt-client.bat 窗口）
# 应看到 registered client_id=... actual_transport=polling/websocket projects=N
```

---

> ⚠️ 所有 `.example`/README 均为模板，token 用 `<REDACTED>`；真实运行时请用各自的私密值，且不要提交到 Git。
