#!/usr/bin/env bash

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "${SCRIPT_DIR}/common.sh"

MAX_SELECTIONS="${MAX_SELECTIONS:-3}"
CONTENT_WHITEBOARD="$CONTENT_WHITEBOARD_FILE"
ensure_content_whiteboard "$CONTENT_WHITEBOARD"

log() { echo "[$(date '+%H:%M:%S')] $1"; }

log "开始生成今日选题..."

# 显式加载 .env
set -a && . "${REPO_ROOT}/.env" 2>/dev/null && set +a || true

export GW_URL GW_TOKEN MAX_SELECTIONS CONTENT_WHITEBOARD
python3 - <<'PY'
import json
import os
import urllib.error
import urllib.request
from datetime import datetime, timedelta

gateway_url = os.environ.get("GW_URL", "")
gateway_token = os.environ.get("GW_TOKEN", "")
whiteboard_path = os.environ["CONTENT_WHITEBOARD"]
max_selections = int(os.environ.get("MAX_SELECTIONS", "3"))
today = datetime.now()
yesterday = today - timedelta(days=1)


def load_json(path):
    with open(path, "r", encoding="utf-8") as handle:
        return json.load(handle)


def save_json(path, payload):
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, ensure_ascii=False, indent=2)


def fetch_view(view_name, params, agent_id):
    payload = {
        "action": "read.view",
        "internalToken": gateway_token,
        "agentId": agent_id,
        "viewName": view_name,
        "purpose": "content_selection",
        "operator": {"wecomUserid": "content_pipeline", "role": "boss"},
        "params": params,
        "traceId": f"content_{agent_id}_{int(datetime.now().timestamp())}",
    }
    request = urllib.request.Request(
        gateway_url,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.loads(response.read().decode("utf-8"))


def has_real_gateway_config():
    placeholder_markers = (
        "your-cloudbase-domain",
        "replace-with-",
        "<gw_token>",
        "<wecom_chat_id>",
    )
    raw_values = (gateway_url or "", gateway_token or "")
    if not all(value.strip() for value in raw_values):
        return False
    lowered = tuple(value.strip().lower() for value in raw_values)
    return not any(marker in value for value in lowered for marker in placeholder_markers)


def build_demo_selection(limit):
    demo_items = [
        {
            "id": "demo_mickey_tee",
            "product_name": "月亮米奇T",
            "price_yuan": 159,
            "stock": 8,
            "reason": "本地演示数据：热销基础款，适合做今日主推",
            "priority": "primary",
            "angles": ["T恤穿搭", "初夏推荐", "门店热销"],
            "category": "T恤",
        },
        {
            "id": "demo_floral_dress",
            "product_name": "法式碎花连衣裙",
            "price_yuan": 229,
            "stock": 5,
            "reason": "本地演示数据：适合拍摄出镜和场景种草",
            "priority": "secondary",
            "angles": ["连衣裙穿搭", "初夏推荐", "约会氛围"],
            "category": "连衣裙",
        },
        {
            "id": "demo_white_shirt",
            "product_name": "通勤白衬衫",
            "price_yuan": 189,
            "stock": 11,
            "reason": "本地演示数据：高频通勤单品，适合多平台内容复用",
            "priority": "secondary",
            "angles": ["衬衫穿搭", "通勤友好", "当季推荐"],
            "category": "衬衫",
        },
    ]
    return demo_items[:limit]


def guess_category(item):
    for key in (
        "category",
        "categoryName",
        "category_name",
        "primaryCategory",
        "productCategory",
    ):
        value = item.get(key)
        if value:
            return str(value)

    title = str(item.get("title") or item.get("productName") or item.get("name") or "")
    mapping = {
        "裙": "连衣裙",
        "裤": "裤装",
        "衬衫": "衬衫",
        "外套": "外套",
        "T": "T恤",
        "t": "T恤",
    }
    for marker, category in mapping.items():
        if marker in title:
            return category
    return "服饰"


def build_angles(category, title, priority):
    current_month = today.month
    season = "初夏" if current_month in (5, 6) else "当季"
    angles = [f"{category}穿搭", f"{season}推荐"]
    if priority == "primary":
        angles.append("门店热销")
    else:
        angles.append("库存优化")
    if "通勤" in title or "衬衫" in title:
        angles.insert(1, "通勤友好")
    return angles[:3]


def item_key(item):
    candidates = [
        item.get("productId"),
        item.get("skuId"),
        item.get("id"),
        item.get("productName"),
        item.get("title"),
        item.get("name"),
    ]
    for candidate in candidates:
        if candidate:
            return str(candidate)
    return "unknown"


def normalize_name(item):
    return str(item.get("title") or item.get("productName") or item.get("name") or "未命名商品")


def build_risk_lookup(items):
    by_id = {}
    by_name = {}
    for item in items:
        key = item.get("productId") or item.get("skuId") or item.get("id")
        title = normalize_name(item)
        if key:
            by_id[str(key)] = item
        by_name[title] = item
    return by_id, by_name


def derive_stock(source_item, risk_item):
    candidates = []
    if risk_item:
        candidates.extend([risk_item.get("stock"), risk_item.get("availableStock")])
    candidates.extend([source_item.get("stock"), source_item.get("availableStock")])
    for candidate in candidates:
        if isinstance(candidate, (int, float)):
            return int(candidate)
        if isinstance(candidate, str) and candidate.isdigit():
            return int(candidate)
    return 0


def derive_price(source_item):
    for key in ("priceYuan", "price", "salePrice", "retailPrice"):
        value = source_item.get(key)
        if isinstance(value, (int, float)) and value > 0:
            return int(round(float(value)))
        if isinstance(value, str):
            try:
                parsed = float(value)
            except ValueError:
                parsed = 0
            if parsed > 0:
                return int(round(parsed))

    quantity = source_item.get("quantity") or source_item.get("saleCount") or 0
    amount_cent = source_item.get("amountCent") or source_item.get("salesAmountCent") or 0
    try:
        quantity = int(quantity)
        amount_cent = int(amount_cent)
    except (TypeError, ValueError):
        quantity = 0
        amount_cent = 0

    if quantity > 0 and amount_cent > 0:
        return max(1, round(amount_cent / quantity / 100))
    return 0


def append_selection(selected, seen, source_item, reason, priority, risk_item=None):
    product_key = item_key(source_item)
    if product_key in seen:
        return

    title = normalize_name(source_item)
    category = guess_category(source_item)
    stock = derive_stock(source_item, risk_item)
    record = {
        "id": product_key,
        "product_name": title,
        "price_yuan": derive_price(source_item),
        "stock": stock,
        "reason": reason,
        "priority": priority,
        "angles": build_angles(category, title, priority),
        "category": category,
    }
    selected.append(record)
    seen.add(product_key)


ranking_payload = {}
risk_payload = {}
errors = []
used_demo_data = False

if has_real_gateway_config():
    try:
        ranking_payload = fetch_view(
            "sales.productRanking",
            {
                "dateRange": {
                    "start": yesterday.strftime("%Y-%m-%d"),
                    "end": today.strftime("%Y-%m-%d"),
                },
                "storeId": "ALL",
                "limit": max_selections,
            },
            "data_analyst",
        )
    except Exception as exc:  # noqa: BLE001
        errors.append(f"sales.productRanking: {exc}")

    try:
        risk_payload = fetch_view(
            "product.inventoryRiskReport",
            {"storeId": "ALL", "limit": max(20, max_selections * 4)},
            "data_analyst",
        )
    except Exception as exc:  # noqa: BLE001
        errors.append(f"product.inventoryRiskReport: {exc}")
else:
    errors.append("gateway config missing or placeholder values detected, switched to demo selection")

ranking_items = ranking_payload.get("data", {}).get("ranking", []) or ranking_payload.get("data", {}).get("items", [])
risk_items = risk_payload.get("data", {}).get("items", [])
risk_by_id, risk_by_name = build_risk_lookup(risk_items)

selected = []
seen = set()

for index, item in enumerate(ranking_items[:max_selections], start=1):
    risk_item = risk_by_id.get(str(item.get("productId"))) or risk_by_name.get(normalize_name(item))
    append_selection(selected, seen, item, f"昨日热销 TOP {index}", "primary", risk_item)

overstock_items = [item for item in risk_items if item.get("riskType") == "overstock"]
for item in overstock_items:
    if len(selected) >= max_selections:
        break
    append_selection(selected, seen, item, "库存较高，建议做清仓促销", "secondary", item)

if not selected:
    selected = build_demo_selection(max_selections)
    used_demo_data = True

whiteboard = load_json(whiteboard_path)
whiteboard["version"] = whiteboard.get("version", "1.0")
whiteboard["date"] = today.strftime("%Y-%m-%d")
whiteboard["last_updated"] = datetime.now().astimezone().isoformat()
whiteboard["select"] = {
    "status": "done",
    "output": selected,
    "meta": {
        "selected_count": len(selected),
        "ranking_count": len(ranking_items),
        "risk_count": len(risk_items),
        "source": "demo" if used_demo_data else "gateway",
        "errors": errors,
    },
}
whiteboard["copy"] = {"status": "pending", "output": []}
whiteboard["package"] = {"status": "pending", "output_path": "", "files": []}
save_json(whiteboard_path, whiteboard)

print(json.dumps({"selected_count": len(selected), "errors": errors}, ensure_ascii=False))
PY

status=$?
if [ "$status" -ne 0 ]; then
  log "选品 Agent 执行失败"
  exit "$status"
fi

log "选品 Agent 完成"