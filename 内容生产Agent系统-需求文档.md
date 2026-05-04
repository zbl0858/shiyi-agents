# 时一搭配师 · 内容生产 Agent 系统需求文档

> 版本：v1.0 | 日期：2026-05-04
> 设计原则：简单、透明、可调试、零新增成本

---

## 一、系统概述

### 1.1 目标

每天早上 9:30 自动生成当日内容素材，推送到企业微信群。包括：
- 今日主推商品选题
- 朋友圈文案
- 小红书笔记文案
- 视频号拍摄脚本

### 1.2 架构原则

- **Agent 拆分**：选品、文案、打包各为独立脚本，互不耦合
- **通信方式**：通过共享 JSON 文件（白板）交换数据
- **执行方式**：线性流水线（选品 → 文案 → 打包）
- **触发方式**：系统 crontab 定时执行
- **推送方式**：写入 /tmp 文件，由 AI 推送至企微群

### 1.3 技术栈

| 组件 | 技术 | 原因 |
|------|------|------|
| Agent 脚本 | Bash Shell | 服务器原生，零依赖 |
| 数据加工 | Python3（内嵌） | JSON 处理方便 |
| 文案生成 | DeepSeek V4 Flash API | 速度快、成本低 |
| 图片生成 | pollinations.ai（二期） | 免费、已验证 |
| 视频合成 | FFmpeg（二期） | 免费、本地 GPU |
| 数据源 | agent_data_gateway | 已有 CloudBase 接口 |
| 任务编排 | crontab + Shell | 简单可靠 |

---

## 二、共享白板设计

### 2.1 文件位置

```
${REPO_ROOT}/workspace/content_whiteboard.json
```

### 2.2 数据结构

```json
{
  "version": "1.0",
  "date": "2026-05-04",
  "last_updated": "2026-05-04T09:25:00+08:00",

  "select": {
    "status": "done",
    "output": [
      {
        "id": "mickey_tee",
        "product_name": "月亮米奇t",
        "price_yuan": 150,
        "stock": 5,
        "reason": "昨日热销TOP1",
        "priority": "primary",
        "angles": ["百搭基础款", "性价比高", "适合通勤"],
        "category": "T恤"
      }
    ]
  },

  "copy": {
    "status": "done",
    "output": [
      {
        "product_id": "mickey_tee",
        "wechat_moments": "初夏必备！这件米奇T...",
        "xiaohongshu": "✨发现一件神仙T恤！...",
        "video_script": {
          "title": "15秒种草月亮米奇t",
          "scenes": ["正面展示", "侧面细节", "搭配示范"],
          "narration": "今天种草一件超百搭的..."
        },
        "hashtags": ["#每日穿搭", "#百搭T恤", "#夏季新款"]
      }
    ]
  },

  "package": {
    "status": "done",
    "output_path": "/tmp/content_package_20260504/",
    "files": ["朋友圈文案.txt", "小红书笔记.txt", "视频脚本.txt"]
  }
}
```

### 2.3 白板操作规范

- 每个 Agent 只写自己负责的字段
- 每个 Agent 只读上游 Agent 已写入的字段
- 写入后必须设置 `status: "done"`
- 下游 Agent 启动时检查上游 `status == "done"`

---

## 三、Agent 详细设计

### 3.1 选品 Agent（agent-selector.sh）

**职责**：分析昨日数据，选出今日推荐商品

**输入**：
- agent_data_gateway 的 `sales.productRanking` 视图
- agent_data_gateway 的 `product.inventoryRiskReport` 视图

**输出**：写入 `whiteboard.select.output`

**选品规则**：

| 规则 | 条件 | 优先级 |
|------|------|--------|
| 热销主推 | 昨日销量 TOP 3 | primary |
| 清仓促销 | 库存 > 5 且 30 天未动销 | secondary |
| 新品推荐 | 最新上架商品 | secondary |

**关键配置**：
```bash
GW_URL="https://your-cloudbase-domain/agent-data-gateway"
GW_TOKEN="<GW_TOKEN>"
MAX_SELECTIONS=3   # 最多推荐几款
```

**实现要点**：
1. 调用 agent_data_gateway 获取销售排行和库存数据
2. 按规则排序，取前 N 款
3. 生成 `angles`（推荐角度）：基于商品类目 + 销售数据 + 季节
4. 写入白板 JSON

---

### 3.2 文案 Agent（agent-copywriter.sh）

**职责**：根据选品结果，生成多平台文案

**输入**：读取 `whiteboard.select.output`
**输出**：写入 `whiteboard.copy.output`

**DeepSeek API 配置**：
```bash
DS_API_URL="https://api.deepseek.com/v1/chat/completions"
DS_API_KEY="<DeepSeek API Key>"
DS_MODEL="deepseek-chat"    # V4 Flash 走这个入口
```

**多平台文案格式**：

| 平台 | 字数 | 风格 | 结构 |
|------|------|------|------|
| 朋友圈 | 80-150 字 | 亲切自然 | 开头吸引 + 产品亮点 + 行动号召 |
| 小红书 | 150-300 字 | 种草感 | 痛点/场景 + 产品 + 效果 + 标签 |
| 视频号脚本 | 15 秒分镜 | 快节奏 | 场景列表 + 旁白 |

**Prompt 模板结构**：
```
你是一个女性服装品牌的内容创作者。请根据以下商品信息生成推广文案：

商品：{{product_name}}
价格：{{price_yuan}}元
风格：{{angles}}
库存：{{stock}}件
推荐理由：{{reason}}

请生成三种文案：
1. 朋友圈文案（80字左右，亲切自然风）
2. 小红书笔记（200字左右，种草风，带emoji）
3. 视频号脚本（15秒，3-4个分镜+旁白）

输出 JSON 格式...
```

**实现要点**：
1. 从白板读取选品结果
2. 对每个选品，构造 prompt 调用 DeepSeek
3. 解析返回的 JSON
4. 写入白板

---

### 3.3 打包 Agent（agent-packager.sh）

**职责**：把文案组装成可直接使用的内容包

**输入**：读取 `whiteboard.copy.output`
**输出**：
- 文件：`/tmp/content_package_YYYYMMDD/`
- 推送到企微群的消息文本

**产出结构**：
```
/tmp/content_package_20260504/
├── 00_今日选题.txt          # 选品摘要
├── 朋友圈/
│   ├── 月亮米奇t.txt
│   └── 碎花连衣裙.txt
├── 小红书/
│   ├── 月亮米奇t.txt
│   └── 碎花连衣裙.txt
└── 视频号/
    ├── 月亮米奇t_脚本.txt
    └── 碎花连衣裙_脚本.txt
```

**群推送消息格式**：
```
📦 今日内容包（5月4日）

🎯 今日主推：月亮米奇t | ¥150 | 库存5件

📱 朋友圈文案：
初夏必备！这件米奇T又甜又酷...

📕 小红书笔记：
✨发现一件神仙T恤！...

🎬 视频号脚本：
15秒，3个分镜，旁白已写好

━━━━━━━━━━━━━━━━━━━━
📂 完整文件：/tmp/content_package_20260504/
```

**实现要点**：
1. 读取白板中的所有产出
2. 创建日期目录，按平台分子目录
3. 写入文本文件
4. 生成群推送内容，写入 `/tmp/daily_content_msg.txt`
5. 写入 `/tmp/daily_content_pending.txt`（时间戳标记）

---

### 3.4 流水线 Runner（content-pipeline.sh）

**职责**：按顺序执行所有 Agent

```bash
#!/bin/bash
PIPELINE_LOG="/tmp/content_pipeline.log"

echo "[$(date)] 内容生产流水线启动" >> $PIPELINE_LOG

# Step 1: 选品
echo "[$(date)] Step 1: 选品 Agent" >> $PIPELINE_LOG
bash /root/.openclaw/scripts/agent-selector.sh

# Step 2: 文案
echo "[$(date)] Step 2: 文案 Agent" >> $PIPELINE_LOG
bash /root/.openclaw/scripts/agent-copywriter.sh

# Step 3: 打包
echo "[$(date)] Step 3: 打包 Agent" >> $PIPELINE_LOG
bash /root/.openclaw/scripts/agent-packager.sh

echo "[$(date)] 流水线完成" >> $PIPELINE_LOG
```

**容错设计**：
- 每个 Agent 独立，失败不影响其他
- 下游 Agent 检查上游 `status == "done"`，否则跳过
- 所有日志写入 `/tmp/content_pipeline.log`

---

## 四、部署配置

### 4.1 文件清单

```
/root/.openclaw/scripts/
├── agent-selector.sh        # 选品 Agent
├── agent-copywriter.sh      # 文案 Agent
├── agent-packager.sh        # 打包 Agent
└── content-pipeline.sh      # 流水线 Runner

/root/.openclaw/workspace/
└── content_whiteboard.json  # 共享白板（初始化为空模板）
```

### 4.2 Crontab 定时任务

```bash
# 每天早上 9:30 执行内容生产
30 9 * * * /bin/bash /root/.openclaw/scripts/content-pipeline.sh >> /tmp/content_pipeline.log 2>&1
```

### 4.3 企业微信推送

复用已有的推送机制：
- 打包 Agent 写入 `/tmp/daily_content_msg.txt`
- 打包 Agent 写入 `/tmp/daily_content_pending.txt`
- OpenClaw cron 或心跳检测到 pending → 推送到「运营管理群」

### 4.4 环境变量（需要在脚本中配置）

```bash
# agent_data_gateway
GW_URL="https://your-cloudbase-domain/agent-data-gateway"
GW_TOKEN="<GW_TOKEN>"

# DeepSeek API
DS_API_KEY="<需要用户提供>"
DS_API_URL="https://api.deepseek.com/v1/chat/completions"

# 企微群
CHATID="<WECOM_CHAT_ID>"
```

---

## 五、二期扩展（暂不实现）

| Agent | 功能 | 依赖 |
|-------|------|------|
| 视觉 Agent | 根据文案生成配图/海报 | pollinations.ai |
| 视频 Agent | 根据脚本+图片合成视频 | FFmpeg + 本地 GPU |
| 数据 Agent | 回收各平台发布数据 | 各平台 API/爬虫 |

---

## 六、非功能需求

1. **所有脚本必须有 shebang + 可执行权限**
2. **JSON 处理使用 `python3 -c`，不依赖 jq**（服务器可能没装）
3. **每个 Agent 单独可测试**：可以直接 `./agent-selector.sh` 跑，查看白板结果
4. **错误不阻塞**：某个 Agent 失败，流水线继续，日志记录
5. **不修改任何生产数据库**
