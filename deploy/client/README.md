# Client (Windows Runner) — 客户端/执行侧文件

Windows Runner（执行项目 + Coding Agent）所在机器上的脚本（已脱敏）：

- `webgpt-client.bat` / `webgpt-client.ps1` — 一键启动器（杀残留 → 探测 → 回填 [acp] → 设 env → 启动 Runner）
- `codex-acp-proxy.js` — ACP v1 代理（桥接 WebCodex Runner ↔ codex；用真实 codex.exe 绝对路径 + stdin+EOF + --sandbox）
- `agent.toml.windows.example` — Windows Runner 配置（token 已脱敏，含 [acp]，allowed_roots=D:\work）
- `CODEX_SYSTEM_PROMPT.md` — Codex 系统注入提示词（44 工具，**项目级、可复用，不含硬编码路径**）
- `AGENTS.md` — 上面提示词的独立可落地版本，直接放到项目根目录即可（`work_on_project` 运行时确定项目与 allowed_root）

放法：解到 `D:\WebGpt`，双击 `webgpt-client.bat`。
