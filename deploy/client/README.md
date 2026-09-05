# Client (Windows Runner) — 客户端/执行侧文件

Windows Runner（执行项目 + Coding Agent）所在机器上的脚本（已脱敏）：

- `webgpt-client.bat` / `webgpt-client.ps1` — 一键启动器（杀残留 → 探测 → 回填 [acp] → 设 env → **提示词注入** → 启动 Runner）
- `codex-acp-proxy.js` — ACP v1 代理（桥接 WebCodex Runner ↔ codex；用真实 codex.exe 绝对路径 + stdin+EOF + --sandbox）
- `agent.toml.windows.example` — Windows Runner 配置（token 已脱敏，含 [acp]，allowed_roots=D:\work）
- `CODEX_SYSTEM_PROMPT.md` — Codex 系统注入提示词（44 工具，**项目级、可复用，不含硬编码路径**）
- `AGENTS.md` — 上面提示词的独立可落地版本，直接放到项目根目录即可（`work_on_project` 运行时确定项目与 allowed_root）

放法：解到 `D:\WebGpt`，双击 `webgpt-client.bat`。

## 提示词注入（脚本自动完成）

`webgpt-client.bat`/`.ps1` 启动时会把 Codex 的**项目级系统提示词**注入到 `%USERPROFILE%\.codex\AGENTS.md`（Codex 每次会话都会自动加载的全局指令），这样 Codex 一启动就拿到 WebCodex MCP 的全部规则。注入不受启动目录影响、跨项目复用，无需手动粘贴。

**提示词来源（按优先级）：**

1. 手动指定：`webgpt-client.bat <AGENTS.md 路径>`，或先设 `set WC_INSTRUCTIONS_FILE=C:\...\AGENTS.md` 再运行。
2. `D:\WebGpt\AGENTS.md`（推荐，把 `deploy/client/AGENTS.md` 复制过去）。
3. `D:\WebGpt\CODEX_SYSTEM_PROMPT.md`（自动只提取里面 ```markdown``` 代码块，忽略周边说明文字）。

**说明：**

- 找不到任何提示词文件时，脚本会打印提示并**照常启动**（不会失败）——注入是可选增强。
- 注入写的是 `AGENTS.md`（默认）；若 Codex 主目录里已有 `AGENTS.override.md`，它会优先于 `AGENTS.md`，此时可改名或用 `%USERPROFILE%\.codex\AGENTS override.md` 直接顶替你自己的内容。
- 别把真实 token/凭据写进提示词文件——脚本只会原样复制到 AGENTS.md。
