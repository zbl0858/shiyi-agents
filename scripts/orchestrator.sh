#!/bin/bash
# 总调度 Agent - 每日作战计划生成
# 09:05 执行，汇总各 Agent 数据，生成任务列表

GW_URL="https://shiyi-prod-6gq3nx2d1a6978fd-1305154841.ap-shanghai.app.tcloudbase.com/agent-data-gateway"
GW_TOKEN="fde858974fc37ea88e4a9b3d02e8995093959ec6698619d6c21bc68409bead69"
CHATID="wrZepjCQAAT711wN3p85BWnbqWJNMmyQ"

YESTERDAY=$(date -d "yesterday" '+%Y-%m-%d')
TODAY=$(date '+%Y-%m-%d')
DATE_LABEL=$(date '+%m月%d日')

WHITEBOARD="/root/.openclaw/workspace/shared_whiteboard.json"

log() { echo "[$(date '+%H:%M:%S')] $1"; }

# 调用数据网关
fetch_view() {
  curl -s --connect-timeout 10 --max-time 30 \
    -X POST "$GW_URL" -H "Content-Type: application/json" \
    -d "{\"action\":\"read.view\",\"internalToken\":\"$GW_TOKEN\",\"agentId\":\"orchestrator\",\"viewName\":\"$1\",\"purpose\":\"daily_plan\",\"operator\":{\"wecomUserid\":\"system\",\"role\":\"admin\"},\"params\":$2,\"traceId\":\"orch_$(date +%s)\"}"
}

# 更新白板
update_whiteboard() {
  local key="$1"
  local value="$2"
  python3 -c "
import json, sys
wb = json.load(open('$WHITEBOARD'))
keys = '$key'.split('.')
d = wb
for k in keys[:-1]:
    d = d.setdefault(k, {})
d[keys[-1]] = json.loads('$value')
wb['last_updated'] = '$(date -Iseconds)'
wb['date'] = '$TODAY'
json.dump(wb, open('$WHITEBOARD', 'w'), ensure_ascii=False, indent=2)
"
}

# 读取白板
read_whiteboard() {
  local key="$1"
  python3 -c "
import json
wb = json.load(open('$WHITEBOARD'))
keys = '$key'.split('.')
d = wb
for k in keys:
    d = d.get(k, {})
print(json.dumps(d, ensure_ascii=False))
"
}

log "🚀 总调度 Agent 启动"

# ========== 1. 数据 Agent：收集昨日销售 ==========
log "📊 数据 Agent 收集销售数据..."
BRIEF=$(fetch_view "business.dailySnapshot" "{\"dateRange\":{\"start\":\"$YESTERDAY\",\"end\":\"$TODAY\"},\"storeId\":\"ALL\"}")

SALES_CENT=$(echo "$BRIEF" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('data',{}).get('summary',{}).get('salesAmountCent',0))" 2>/dev/null || echo 0)
ORDERS=$(echo "$BRIEF" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('data',{}).get('summary',{}).get('paidOrderCount',0))" 2>/dev/null || echo 0)
NEW_MEMBERS=$(echo "$BRIEF" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('data',{}).get('summary',{}).get('newMemberCount',0))" 2>/dev/null || echo 0)
REFUND_CENT=$(echo "$BRIEF" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('data',{}).get('summary',{}).get('refundAmountCent',0))" 2>/dev/null || echo 0)
TOTAL_STOCK=$(echo "$BRIEF" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('data',{}).get('summary',{}).get('totalStock',0))" 2>/dev/null || echo 0)

update_whiteboard "sales.yesterday" "{\"amount_cent\":$SALES_CENT,\"order_count\":$ORDERS,\"avg_price_cent\":$([ $ORDERS -gt 0 ] && echo $((SALES_CENT / ORDERS)) || echo 0),\"refund_cent\":$REFUND_CENT}"
update_whiteboard "inventory.total_stock" "$TOTAL_STOCK"
update_whiteboard "customers.new_members_today" "$NEW_MEMBERS"

# ========== 2. 库存 Agent：分析库存风险 ==========
log "📦 库存 Agent 分析库存..."
RISK=$(fetch_view "product.inventoryRiskReport" "{\"storeId\":\"ALL\",\"limit\":50}")

OUT_OF_STOCK=$(echo "$RISK" | python3 -c "
import sys, json
d = json.load(sys.stdin)
items = d.get('data', {}).get('items', [])
out = [i for i in items if i.get('riskType') == 'out_of_stock']
over = [i for i in items if i.get('riskType') == 'overstock']
print(json.dumps({'out_of_stock': out, 'overstock': over}, ensure_ascii=False))
" 2>/dev/null || echo '{"out_of_stock":[],"overstock":[]}')

update_whiteboard "inventory" "$OUT_OF_STOCK"

# ========== 3. 客户 Agent：分析客户状态 ==========
log "👥 客户 Agent 分析客户..."
# TODO: 需要更多客户数据视图
# 目前先用新会员数据

# ========== 4. 总调度：生成任务列表 ==========
log "🎯 总调度生成作战计划..."

# 读取白板数据
SALES_JSON=$(read_whiteboard "sales.yesterday")
INV_JSON=$(read_whiteboard "inventory")

TASKS=$(python3 -c "
import json

sales = json.loads('$SALES_JSON')
inv = json.loads('$INV_JSON')

tasks = []
priority = 'normal'

# 规则1：缺货提醒
for item in inv.get('out_of_stock', []):
    tasks.append({
        'id': f\"stock_{item.get('productId', 'unknown')}\",
        'category': '库存',
        'title': f\"补货提醒：{item.get('title', '未知商品')}\",
        'detail': f\"库存为0，建议联系供应商补货\",
        'assignee': '店长',
        'deadline': '明日12:00',
        'priority': 'high'
    })

# 规则2：滞销清仓
for item in inv.get('overstock', []):
    tasks.append({
        'id': f\"promo_{item.get('productId', 'unknown')}\",
        'category': '营销',
        'title': f\"清仓建议：{item.get('title', '未知商品')}\",
        'detail': f\"库存{item.get('stock', 0)}件，建议促销清仓\",
        'assignee': '店长',
        'deadline': '今日闭店',
        'priority': 'medium'
    })

# 规则3：销售目标
if sales.get('amount_cent', 0) < 150000:  # 低于1500元
    tasks.append({
        'id': 'target_sales',
        'category': '销售',
        'title': '销售目标提醒',
        'detail': f\"昨日销售额{sales.get('amount_cent', 0)//100}元，今日目标3000元\",
        'assignee': '全员',
        'deadline': '今日闭店',
        'priority': 'high'
    })

# 规则4：新会员跟进
if $NEW_MEMBERS > 0:
    tasks.append({
        'id': 'follow_new_member',
        'category': '客户',
        'title': f'新会员转化：{$NEW_MEMBERS}位待跟进',
        'detail': '推送首购优惠券，推荐搭配商品',
        'assignee': '导购',
        'deadline': '今日18:00',
        'priority': 'medium'
    })

print(json.dumps(tasks, ensure_ascii=False))
" 2>/dev/null || echo '[]')

update_whiteboard "tasks.pending" "$TASKS"

# ========== 5. 生成群消息 ==========
TASK_COUNT=$(echo "$TASKS" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))")

if [ "$TASK_COUNT" -eq 0 ]; then
  MSG="📋 时一今日作战计划（${DATE_LABEL}）

✅ 今日无紧急任务，保持正常运营"
else
  HIGH_COUNT=$(echo "$TASKS" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len([t for t in d if t.get('priority')=='high']))")
  
  MSG="📋 时一今日作战计划（${DATE_LABEL}）
━━━━━━━━━━━━━━━━━━━━

🎯 昨日回顾：销售额 ${SALES_CENT}分 | ${ORDERS}单 | 新会员 ${NEW_MEMBERS}位
📦 库存状态：总库存 ${TOTAL_STOCK}件

⚡ 高优先级任务 [${HIGH_COUNT}项]"

  # 高优先级任务
  HIGH_TASKS=$(echo "$TASKS" | python3 -c "
import sys, json
tasks = [t for t in json.load(sys.stdin) if t.get('priority') == 'high']
for t in tasks:
    print(f\"□ {t['title']}\")
    print(f\"  → {t['detail']}\")
    print(f\"  → 负责人：{t['assignee']} | 截止：{t['deadline']}\")
")
  MSG="$MSG
$HIGH_TASKS"

  # 中优先级任务
  MED_TASKS=$(echo "$TASKS" | python3 -c "
import sys, json
tasks = [t for t in json.load(sys.stdin) if t.get('priority') == 'medium']
if tasks:
    print('\n📌 常规任务 [' + str(len(tasks)) + '项]')
    for t in tasks:
        print(f\"□ {t['title']}\")
        print(f\"  → {t['detail']}\")
        print(f\"  → 负责人：{t['assignee']} | 截止：{t['deadline']}\")
")
  MSG="$MSG
$MED_TASKS"

  MSG="$MSG

━━━━━━━━━━━━━━━━━━━━
💡 总调度建议：优先处理高优先级任务，确保今日目标达成"
fi

# 写入待推送文件
echo "$MSG" > /tmp/daily_briefing_msg.txt
echo "$CHATID" > /tmp/daily_briefing_target.txt
echo "$(date +%s)" > /tmp/daily_briefing_pending.txt

log "✅ 作战计划已生成，${TASK_COUNT}项任务待执行"
