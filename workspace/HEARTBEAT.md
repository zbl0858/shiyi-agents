# HEARTBEAT.md

## 定时任务：每日经营简报推送

每天 9:05 AM 收到系统事件 `DAILY_BRIEFING_CHECK` 时：
1. 检查 `/tmp/daily_briefing_pending.txt`（时间戳是否在 24h 内）
2. 读取 `/tmp/daily_briefing_msg.txt`
3. 读取 `/tmp/daily_briefing_target.txt`
4. 使用 message 工具发送：target=群ID, message=简报内容
5. 完成后删除 `/tmp/daily_briefing_pending.txt`

## 心跳兜底

每次心跳（未收到 DAILY_BRIEFING_CHECK 事件时）也检查上述文件。有则推送，无则 HEARTBEAT_OK。
