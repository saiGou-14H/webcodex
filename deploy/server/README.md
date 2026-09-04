# Server (Linux) — 服务器侧部署文件

WebCodex 服务器所在 Linux 机器上的实际部署文件（已脱敏）：

- `webcodex.service` / `webcodex.socket` — Server systemd（监听 127.0.0.1:8080）
- `webcodex-runner.service` — Linux Runner unit（root + CODEX_HOME/HOME，供 ACP Coding Agent）
- `webcodex-tunnel.service` — OpenAI Secure MCP Tunnel 客户端 unit
- `run-tunnel.sh` — tunnel-client 启动脚本（引用私有 key/bearer 文件）
- `nginx.chatgpt.kunkun.chat.conf` — Nginx 反代（https://chatgpt.kunkun.chat -> 127.0.0.1:8080）+ /webcodex-dl/
- `webcodex.env.example` — Server 环境（token 已脱敏）
- `agent.toml.linux.example` — Linux Runner 配置（token 已脱敏，含 [acp]）
