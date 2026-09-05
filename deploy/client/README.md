# Client (Windows Runner) — 客户端/执行侧文件

Windows Runner（执行项目 + Coding Agent）所在机器上的脚本（已脱敏）：

- `webgpt-client.bat` / `webgpt-client.ps1` — 一键启动器 + 配置管理入口（杀残留 → 探测 → 回填 [acp] → 设 env → **提示词注入** → **应用连接配置** → 启动 Runner）
- `webgpt-config.ps1` — 配置管理库（MCP/APIKey/模式，本地缓存 `%USERPROFILE%\.webgpt\client.json`，icacls 保护）
- `codex-acp-proxy.js` — ACP v1 代理（桥接 WebCodex Runner ↔ codex；用真实 codex.exe 绝对路径 + stdin+EOF + --sandbox）
- `agent.toml.windows.example` — Windows Runner 配置（token 已脱敏，含 [acp]，allowed_roots=D:\work）
- `CODEX_SYSTEM_PROMPT.md` — Codex 系统注入提示词（44 工具，**项目级、可复用，不含硬编码路径**）
- `AGENTS.md` — 上面提示词的独立可落地版本，直接放到项目根目录即可（`work_on_project` 运行时确定项目与 allowed_root）

放法：解到 `D:\WebGpt`，双击 `webgpt-client.bat`（无参数 = 启动 Runner）。

## 配置管理（MCP / APIKey / 连接模式）

`webgpt-client.bat <子命令>` 管理本机 Codex 的连接配置，全部缓存到 `%USERPROFILE%\.webgpt\client.json`（可用 `WC_CONFIG` 换位置；文件用 icacls 限制为当前用户）。

| 子命令 | 作用 |
|---|---|
| `set-server <url> [username]` | 设置 WebCodex 服务器地址（如 `https://chatgpt.kunkun.chat`）与用户名 |
| `set-bootstrap <wc_pat>` | 设置**引导账号凭据**（一个已有可注册 token 的 wc_pat，用于签发新 token；仅存本地） |
| `add-mcp` | **自动生成 `wc_pat_xxx`**：调 `webcodex tokens create-local` 向服务器注册并取回明文 token，缓存 `mcp.bearer`，并执行 `codex mcp add webcodex --url <server>/mcp --bearer-token-env-var WEBCODEX_BEARER` |
| `mode mcp` / `mode tunnel`（或 `mcp` / `tunnel` 简写） | 切换连接模式，并同步 `codex mcp add` 的 URL（mcp=直连 `/mcp`；tunnel=走隧道端点） |
| `set-apikey [key]` | 缓存模型 API Key（不传则交互输入） |
| `edit-apikey [key]` | 修改本地缓存的 API Key（交互，可回车保留原值） |
| `show-apikey [--reveal]` | 查看缓存 API Key（默认脱敏；`--reveal` 显示明文） |
| `get-bearer` | 打印缓存的 `wc_pat` 明文（用于复制到隧道/别处） |
| `set-tunnel <url> [bearer]` | 配置 Tunnel 模式用的 MCP 端点与（可选）注入的 Bearer |
| `set-server-token <t>` | 缓存**服务器管理员令牌** `WEBCODEX_TOKEN`（方案 B 专用；用于客户端签发配对码） |
| `set-allowed-root <path>` | 设置 Runner 的 allowed root（`pair` 登录时使用，如 `D:\work`） |
| `pair [client-id]` | **方案 B 一键注册**：客户端调 `pairing create`（用管理员令牌，令牌经环境变量传递不落命令行）拿随机 `wc_pair_*` → 立刻自动 `login` 消费 |
| `show-config` | 查看全部缓存配置（密文脱敏） |
| `help` | 列出所有子命令 |

**默认签发 scope：** `runtime:read,session:collaborate,project:read,project:write,job:run,coding_agent:run`（MCP 直连 + 委托编码 Agent 都要用；可在 `client.json` 的 `scopes` 里改）。

**模式含义：**

- **mcp 模式**：本地 Codex 通过 `codex mcp add webcodex` 直连 `<server>/mcp`，启动时导出 `WEBCODEX_BEARER=<mcp.bearer>`（刚刚签发的 wc_pat）。
- **tunnel 模式**：走 OpenAI Secure MCP Tunnel（WebGpt）——启动时导出 `WEBCODEX_BEARER=<tunnel.bearer>`，MCP URL 指向 `tunnel.url`，不需要每用户 token。

**方案 B：完全客户端一侧注册 Runner（无需在服务器上执行任何命令）**

只需把服务器管理员令牌（`/etc/webcodex/webcodex.env` 里的 `WEBCODEX_TOKEN`）放进来一次，之后包括登录在内的所有步骤都在 Windows 上完成：

```powershell
D:\WebGpt\webgpt-client.bat set-server https://chatgpt.kunkun.chat saigou
D:\WebGpt\webgpt-client.bat set-server-token <WEBCODEX_TOKEN>   # 仅此一次；缓存于 client.json（icacls 保护）
D:\WebGpt\webgpt-client.bat set-allowed-root D:\work
D:\WebGpt\webgpt-client.bat pair                                 # 自动：签发 wc_pair_* → login → agent.toml
```

`pair` 的随机配对码由服务器 `POST /api/pairing/create` 生成并登记（客户端不能凭空造一个服务器认得的码，这是协议约束），脚本拿到后**立即消费并登录**（一次性码不经过手工复制）。之后照常 `add-mcp` / `set-apikey` / `mode`。

**启动时自动应用：** 无参数运行 `webgpt-client.bat` 会读取缓存配置并导出 `WEBCODEX_BEARER`（按模式取 mcp/tunnel 的 bearer）、`OPENAI_API_KEY`、`OPENAI_BASE_URL`（若已配置）——Codex/ACP 代理子进程自动继承。

## 提示词注入（脚本自动完成）

`webgpt-client.bat`/`.ps1` 启动时会把 Codex 的**项目级系统提示词**注入到 `%USERPROFILE%\.codex\AGENTS.md`（Codex 每次会话都会自动加载的全局指令），这样 Codex 一启动就拿到 WebCodex MCP 的全部规则。注入不受启动目录影响、跨项目复用，无需手动粘贴。

**提示词来源（按优先级）：**

1. 手动指定：`webgpt-client.bat <AGENTS.md 路径>`（非配置子命令的参数会被当作提示词文件路径），或先设 `set WC_INSTRUCTIONS_FILE=C:\...\AGENTS.md` 再运行。
2. `D:\WebGpt\AGENTS.md`（推荐，把 `deploy/client/AGENTS.md` 复制过去）。
3. `D:\WebGpt\CODEX_SYSTEM_PROMPT.md`（自动只提取里面 ```markdown``` 代码块，忽略周边说明文字）。

**不会重复注入（幂等、非破坏）：**

- 每次只选**一个**来源（从上到下第一个存在的），只写一次。
- 注入内容被包在一对 `<!-- webcodex-agents:start -->` / `<!-- webcodex-agents:end -->` 标记里。重复运行时**替换**旧块，绝不叠加。
- 若你的 `AGENTS.md` 里原本已有自己的全局指令，脚本会**保留它们**，只在我们自己的标记块里注入 WebCodex 规则（非破坏，原内容不丢）。
- 找不到任何提示词文件时，脚本打印提示并**照常启动**（注入是可选增强，不影响启动）。

**关键：请只留一个注入点。** Codex 会把**全局 `AGENTS.md` + 项目仓库里的 `AGENTS.md`** 全部拼接起来，所以你**不要**再把同一份 `AGENTS.md` 复制进项目根目录，也**不要**在会话首条指令里重复粘贴——否则模型会读到两份 44 工具清单。

**其他注意：**

- 注入写的是 `AGENTS.md`（默认）；若 Codex 主目录里已有 `AGENTS.override.md`，它会优先于 `AGENTS.md`，此时可改名或把我们的内容合进 `%USERPROFILE%\.codex\AGENTS.override.md`。
- 别把真实 token/凭据写进提示词文件——脚本只会原样复制到 AGENTS.md。
