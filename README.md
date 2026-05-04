# 时一搭配师 · Agent 系统

独立的多 Agent 内容生产与运营助手系统。

## 项目结构

```text
shiyi-agents/
├── .env.example              # 环境变量示例
├── scripts/
│   ├── common.sh             # 共享配置与公共函数
│   ├── run-agent.ps1         # Windows 启动器
│   ├── daily-briefing.sh      # 每日经营简报生成
│   ├── orchestrator.sh         # 总调度 Agent（任务编排）
│   ├── task-manager.sh         # 任务管理工具
│   ├── agent-selector.sh       # 选品 Agent
│   ├── agent-copywriter.sh     # 文案 Agent
│   ├── agent-packager.sh       # 打包 Agent
│   ├── content-pipeline.sh     # 内容生产流水线
│   └── preview-content.sh      # 最新内容预览生成
├── workspace/
│   ├── HEARTBEAT.md            # 心跳机制配置
│   └── shared_whiteboard.json  # Agent 间共享数据白板
│   └── content_whiteboard.json # 内容生产白板
└── 内容生产Agent系统-需求文档.md   # 需求文档
```

## 依赖

- agent_data_gateway（CloudBase 云函数）：提供销售/库存/客户数据
- DeepSeek API：文案生成
- 企业微信 WebSocket Bot：消息推送
- Linux / WSL 环境中的 bash、curl、python3、bc

## 配置

1. 复制 `.env.example` 为 `.env`
2. 填写 `GW_URL`、`GW_TOKEN`、`CHATID`
3. 如需 AI 生成真实文案，再填写 `DS_API_KEY`
4. 按需覆盖 `WHITEBOARD_FILE`、`CONTENT_WHITEBOARD_FILE` 或 `TMP_DIR`

如果 `GW_URL` 或 `GW_TOKEN` 缺失，或者仍是示例占位值，`agent-selector.sh` 会自动切到 demo 选品数据，方便本地联调整条内容流水线。
如果 `DS_API_KEY` 缺失，或者仍是示例占位值，`agent-copywriter.sh` 会自动切到模板文案，不会请求 DeepSeek。

`.env.example` 示例：

```bash
GW_URL=https://your-cloudbase-domain/agent-data-gateway
GW_TOKEN=replace-with-gateway-token
CHATID=replace-with-wecom-chatid
DS_API_KEY=replace-with-deepseek-api-key
DS_API_URL=https://api.deepseek.com/v1/chat/completions
DS_MODEL=deepseek-chat
MAX_SELECTIONS=3

# Optional overrides
# WHITEBOARD_FILE=/absolute/path/to/shared_whiteboard.json
# CONTENT_WHITEBOARD_FILE=/absolute/path/to/content_whiteboard.json
# CONTENT_PACKAGE_ROOT=/tmp
# TMP_DIR=/tmp
```

## 本地调试

```bash
bash scripts/agent-selector.sh
bash scripts/agent-copywriter.sh
bash scripts/agent-packager.sh
bash scripts/content-pipeline.sh
bash scripts/preview-content.sh
bash scripts/orchestrator.sh
bash scripts/task-manager.sh list
```

Windows 下可用 PowerShell 启动器自动探测 Git Bash 或已初始化发行版的 WSL：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\run-agent.ps1 content-pipeline
powershell -ExecutionPolicy Bypass -File .\scripts\run-agent.ps1 preview-content
powershell -ExecutionPolicy Bypass -File .\scripts\run-agent.ps1 task-manager list
powershell -ExecutionPolicy Bypass -File .\scripts\run-agent.ps1 -List
```

`preview-content.sh` 会基于当前 `workspace/content_whiteboard.json`、最新摘要文件和内容包目录生成 `内容包首页.html`、`内容预览.md` 和 `内容预览.html`。其中首页适合分发文件和快速跳转，HTML 预览页内置目录导航、复制按钮和打印样式，适合本地过稿或直接导出给运营同事查看。

预览交付建议：

1. 运行 `powershell -ExecutionPolicy Bypass -File .\scripts\run-agent.ps1 preview-content`
2. 先打开内容包目录下的 `内容包首页.html`，从首页进入 `内容预览.html` 或各渠道单文件
3. 在预览页里用顶部目录快速跳转到群摘要、选题总览或具体商品
4. 直接复制群摘要、朋友圈文案、小红书笔记或视频脚本，粘贴到企业微信、内容文档或排期表
5. 如需发给同事审稿，可直接使用浏览器打印为 PDF，或者把首页和单文件一起交付

默认情况下，预览文件会写入当天内容包目录；如果内容包尚未生成，则会退回到 `workspace/content_whiteboard.json` 所在目录。

如果本机没有可用的 Bash 运行时，启动器会直接报错并提示两种处理方式：

1. 安装 Git for Windows，或安装并初始化一个可用的 WSL Linux 发行版
2. 手动设置环境变量 `SHIYI_BASH=C:\path\to\bash.exe`

## 服务器部署

```bash
# crontab
0 9 * * * /bin/bash /path/to/shiyi-agents/scripts/daily-briefing.sh
30 9 * * * /bin/bash /path/to/shiyi-agents/scripts/content-pipeline.sh
```
