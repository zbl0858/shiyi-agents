# 时一搭配师 · Agent 系统

独立的多 Agent 内容生产与运营助手系统。

## 项目结构

```
shiyi-agents/
├── scripts/
│   ├── daily-briefing.sh      # 每日经营简报生成
│   ├── orchestrator.sh         # 总调度 Agent（任务编排）
│   ├── task-manager.sh         # 任务管理工具
│   ├── agent-selector.sh       # 选品 Agent（待实现）
│   ├── agent-copywriter.sh     # 文案 Agent（待实现）
│   ├── agent-packager.sh       # 打包 Agent（待实现）
│   └── content-pipeline.sh     # 内容生产流水线（待实现）
├── workspace/
│   ├── HEARTBEAT.md            # 心跳机制配置
│   └── shared_whiteboard.json  # Agent 间共享数据白板
└── 内容生产Agent系统-需求文档.md   # 需求文档
```

## 依赖

- agent_data_gateway（CloudBase 云函数）：提供销售/库存/客户数据
- DeepSeek API：文案生成
- 企业微信 WebSocket Bot：消息推送

## 服务器部署

```bash
# crontab
0 9 * * * /bin/bash /root/projects/shiyi-agents/scripts/daily-briefing.sh
30 9 * * * /bin/bash /root/projects/shiyi-agents/scripts/content-pipeline.sh
```
