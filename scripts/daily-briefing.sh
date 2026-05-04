#!/usr/bin/env bash
# 每日经营简报 vFinal
# cron: 0 9 * * * /bin/bash /path/to/shiyi-agents/scripts/daily-briefing.sh
# 流程：拉数据 → 生成简报 → AI 醒来时推到运营管理群

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "${SCRIPT_DIR}/common.sh"

require_env GW_URL GW_TOKEN CHATID

YESTERDAY=$(date -d "yesterday" '+%Y-%m-%d')
TODAY=$(date '+%Y-%m-%d')
DATE_LABEL=$(date -d "yesterday" '+%m月%d日')

log() { echo "[$(date '+%H:%M:%S')] $1"; }

fetch_view() {
  curl -s --connect-timeout 10 --max-time 30 \
    -X POST "$GW_URL" -H "Content-Type: application/json" \
    -d "{\"action\":\"read.view\",\"internalToken\":\"$GW_TOKEN\",\"agentId\":\"data_analyst\",\"viewName\":\"$1\",\"purpose\":\"daily_brief\",\"operator\":{\"wecomUserid\":\"daily_cron\",\"role\":\"boss\"},\"params\":$2,\"traceId\":\"$3\"}"
}

log "拉取数据..."
BRIEF=$(fetch_view "business.dailySnapshot" "{\"dateRange\":{\"start\":\"$YESTERDAY\",\"end\":\"$TODAY\"},\"storeId\":\"ALL\"}" "daily_$(date +%s)")
RANKING=$(fetch_view "sales.productRanking" "{\"dateRange\":{\"start\":\"$YESTERDAY\",\"end\":\"$TODAY\"},\"storeId\":\"ALL\"}" "rk_$(date +%s)")
RISK=$(fetch_view "product.inventoryRiskReport" "{\"storeId\":\"ALL\"}" "risk_$(date +%s)")

SALES=$(echo "$BRIEF" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('data',{}).get('summary',{}).get('salesAmountCent',0))" 2>/dev/null || echo 0)
ORDERS=$(echo "$BRIEF" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('data',{}).get('summary',{}).get('paidOrderCount',0))" 2>/dev/null || echo 0)
NEW_MEMBERS=$(echo "$BRIEF" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('data',{}).get('summary',{}).get('newMemberCount',0))" 2>/dev/null || echo 0)
REFUND_CENT=$(echo "$BRIEF" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('data',{}).get('summary',{}).get('refundAmountCent',0))" 2>/dev/null || echo 0)
STOCK=$(echo "$BRIEF" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('data',{}).get('summary',{}).get('totalStock',0))" 2>/dev/null || echo 0)

[ "$ORDERS" -gt 0 ] 2>/dev/null && AVG=$((SALES / ORDERS / 100)) || AVG=0
SALES_YUAN=$(echo "scale=2; $SALES / 100" | bc 2>/dev/null || echo "$SALES")
REFUND_YUAN=$(echo "scale=2; $REFUND_CENT / 100" | bc 2>/dev/null || echo "0")

TOP3=$(echo "$RANKING" | python3 -c "
import sys,json
d=json.load(sys.stdin)
items = d.get('data',{}).get('ranking',[])
out = []
for i in items[:3]:
    out.append(f'{i.get(\"title\",\"\")}｜{i.get(\"quantity\",0)}件｜{i.get(\"amountCent\",0)/100:.0f}元')
print('\n'.join(out) if out else '暂无数据')
" 2>/dev/null)

OUT_OF_STOCK=$(echo "$RISK" | python3 -c "
import sys,json
d=json.load(sys.stdin)
items = d.get('data',{}).get('items',[])
print(len([i for i in items if i.get('riskType')=='out_of_stock']))
" 2>/dev/null || echo 0)

MSG="📊 时一服装店 · ${DATE_LABEL} 经营简报

💰 销售额：${SALES_YUAN}元（${ORDERS}单）
👤 平均客单价：${AVG}元
🆕 新增会员：${NEW_MEMBERS}位
🔙 退款：${REFUND_YUAN}元
📦 库存总件数：${STOCK}件"

[ "$OUT_OF_STOCK" -gt 0 ] 2>/dev/null && MSG="$MSG
⚠️ 缺货提醒：${OUT_OF_STOCK}款商品库存为0"

MSG="$MSG

🏆 昨日热销 TOP 3
${TOP3:-（暂无销售数据）}"

write_pending_message "$MSG" "$CHATID"

log "✅ 简报已生成，等待推送至群 $CHATID"
