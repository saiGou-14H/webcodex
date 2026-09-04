# kunkun-chat deployment artifacts

Actual (server-side) deployment files for this WebGpt instance, redacted of secrets.

- `webcodex.service` / `webcodex.socket` — WebCodex Server systemd units (127.0.0.1:8080)
- `webcodex-runner.service` — Linux Runner unit (root, CODEX_HOME/HOME env for ACP)
- `webcodex-tunnel.service` — OpenAI Secure MCP Tunnel client unit
- `run-tunnel.sh` — tunnel-client wrapper (references private key/bearer files)
- `nginx.chatgpt.kunkun.chat.conf` — Nginx reverse proxy (https://chatgpt.kunkun.chat -> 127.0.0.1:8080) + /webcodex-dl/ static
- `webcodex.env.example` — Server env (token redacted)
- `agent.toml.linux.example` / `agent.toml.windows.example` — Runner config (token redacted), incl. `[acp]` coding-agent section

Note: systemd units are the ACTUAL ones used; upstream generic templates remain in `deploy/*.example`.
