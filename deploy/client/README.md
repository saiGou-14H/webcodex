# Client (Windows Runner) — 客户端/执行侧文件

Windows Runner（执行项目 + Coding Agent）所在机器上的脚本（已脱敏）：

- `webgpt-client.bat` / `webgpt-client.ps1` — 一键启动器（杀残留 → 探测 → 回填 [acp] → 设 env → 启动 Runner）
- `codex-acp-proxy.js` — ACP v1 代理（桥接 WebCodex Runner ↔ codex；用真实 codex.exe 绝对路径 + stdin+EOF + --sandbox）
- `agent.toml.windows.example` — Windows Runner 配置（token 已脱敏，含 [acp]，allowed_roots=D:\work）

放法：解到 `D:\WebGpt`，双击 `webgpt-client.bat`。
