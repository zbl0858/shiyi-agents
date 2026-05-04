# HEARTBEAT.md

## 定时任务：每日经营简报推送

每天 9:05 AM 收到系统事件 `DAILY_BRIEFING_CHECK` 时：

1. 检查 `/tmp/daily_briefing_pending.txt`（时间戳是否在 24h 内）
2. 读取 `/tmp/daily_briefing_msg.txt`
3. 读取 `/tmp/daily_briefing_target.txt`
4. 使用 message 工具发送：target=群ID, message=简报内容
5. 完成后删除 `/tmp/daily_briefing_pending.txt`

## 定时任务：每日内容包推送

每天 9:35 AM 收到系统事件 `DAILY_CONTENT_CHECK` 时：

1. 检查 `/tmp/daily_content_pending.txt`（时间戳是否在 24h 内）
2. 读取 `/tmp/daily_content_msg.txt`
3. 如果存在 `/tmp/daily_content_target.txt`，读取目标群 ID
4. 使用 message 工具发送：target=群ID, message=内容包摘要
5. 完成后删除 `/tmp/daily_content_pending.txt`

## 心跳兜底

每次心跳（未收到 DAILY_BRIEFING_CHECK 或 DAILY_CONTENT_CHECK 事件时）也检查上述 pending 文件。有则推送，无则 HEARTBEAT_OK。
