#!/usr/bin/env bash

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "${SCRIPT_DIR}/common.sh"

DS_API_URL="${DS_API_URL:-https://api.deepseek.com/v1/chat/completions}"
DS_MODEL="${DS_MODEL:-deepseek-chat}"
CONTENT_WHITEBOARD="$CONTENT_WHITEBOARD_FILE"
ensure_content_whiteboard "$CONTENT_WHITEBOARD"

log() { echo "[$(date '+%H:%M:%S')] $1"; }

log "开始生成文案..."

export CONTENT_WHITEBOARD DS_API_URL DS_MODEL
if [ -n "${DS_API_KEY:-}" ]; then
  export DS_API_KEY
fi

python3 - <<'PY'
import json
import os
import re
import urllib.error
import urllib.request
from datetime import datetime

whiteboard_path = os.environ["CONTENT_WHITEBOARD"]
ds_api_url = os.environ.get("DS_API_URL", "https://api.deepseek.com/v1/chat/completions")
ds_model = os.environ.get("DS_MODEL", "deepseek-chat")
ds_api_key = os.environ.get("DS_API_KEY", "")


def has_real_api_key(value):
    if not value or not value.strip():
        return False

    lowered = value.strip().lower()
    placeholder_markers = (
        "replace-with-",
        "<deepseek api key>",
        "replace-with-deepseek-api-key",
    )
    return not any(marker in lowered for marker in placeholder_markers)


can_use_deepseek = has_real_api_key(ds_api_key)


def load_json(path):
    with open(path, "r", encoding="utf-8") as handle:
        return json.load(handle)


def save_json(path, payload):
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, ensure_ascii=False, indent=2)


def clean_reason(text):
    return (text or "店内推荐").replace("本地演示数据：", "").strip()


def style_profile(category):
    profiles = {
        "T恤": {
            "opening": "不管单穿还是叠穿都很省心",
            "occasion": "通勤、周末出门",
            "mood": "轻松不费力",
            "detail": "版型和上身比例都比较利落",
            "need": "一件能反复搭配的基础款",
            "scenes": [
                "镜头1：平铺或衣架展示正面版型和图案",
                "镜头2：上身近景展示领口、肩线和面料垂感",
                "镜头3：搭配牛仔裤或半裙，走两步展示整体氛围",
            ],
        },
        "连衣裙": {
            "opening": "一件就能把整套状态拉起来",
            "occasion": "约会、聚会、周末拍照",
            "mood": "温柔又显气色",
            "detail": "裙摆和线条感在镜头里会更出片",
            "need": "一套有氛围感的穿搭",
            "scenes": [
                "镜头1：手提裙摆或转身展示整体轮廓",
                "镜头2：近景展示领口、袖型和花色细节",
                "镜头3：上身走动或转圈，拍出裙摆动态",
            ],
        },
        "衬衫": {
            "opening": "气质干净，搭配空间也很大",
            "occasion": "通勤、见客户、日常外出",
            "mood": "利落但不生硬",
            "detail": "肩线和衣摆处理会让整个人看起来更精神",
            "need": "兼顾通勤和日常的衣橱核心单品",
            "scenes": [
                "镜头1：展示衬衫正面版型和面料挺度",
                "镜头2：近景拍袖口、领型和纽扣细节",
                "镜头3：半扎衣摆搭配裤装，展示通勤状态",
            ],
        },
    }
    return profiles.get(
        category,
        {
            "opening": "上身很容易穿出状态",
            "occasion": "通勤和日常出门",
            "mood": "自然显精神",
            "detail": "细节和整体比例都比较在线",
            "need": "快速完成日常穿搭的主力单品",
            "scenes": [
                "镜头1：展示单品整体轮廓",
                "镜头2：近景展示面料和细节",
                "镜头3：上身搭配展示完整造型",
            ],
        },
    )


def build_hashtags(product_name, category, angles):
    candidates = [product_name, f"{category}穿搭", *angles]
    hashtags = []
    for tag in candidates:
        normalized = f"#{tag}".replace("##", "#")
        if normalized not in hashtags:
            hashtags.append(normalized)
        if len(hashtags) == 3:
            break
    return hashtags


def fallback_copy(item):
    product_name = item.get("product_name", "今日主推")
    price = item.get("price_yuan", 0)
    stock = item.get("stock", 0)
    reason = clean_reason(item.get("reason", "店内推荐"))
    angles = item.get("angles", []) or ["今日穿搭", "实穿推荐", "店内热销"]
    category = item.get("category", "服饰")
    style = style_profile(category)
    is_low_stock = stock <= 5
    stock_line = f"店里现在还有{stock}件" if stock > 0 else "当前需要预留补货节奏"
    urgency_line = "喜欢这种风格建议早点试穿" if is_low_stock else "这类单品很适合这周先安排试穿"

    wechat = (
        f"今天想认真推一下这件{product_name}。{style['opening']}，{angles[0]}这点特别明显。"
        f"{style['detail']}，{style['occasion']}都能直接穿。现在到手大约{price}元，{stock_line}。"
        f"{reason}，{urgency_line}。"
    )
    xiaohongshu = (
        f"✨最近想找一件{style['mood']}单品的姐妹，可以先看看这件{product_name}。"
        f"它不是那种第一眼很吵的款，但上身之后会发现{angles[0]}感特别顺，镜头里也更显精神。"
        f"{style['detail']}，而且适合{style['occasion']}。价格大约{price}元，{stock_line}，{reason}。"
        f"如果你最近衣橱里正缺{style['need']}，这件可以直接放进本周试穿清单。"
        f" {' '.join(build_hashtags(product_name, category, angles))}"
    )
    title = f"15秒种草{product_name}"
    scenes = style["scenes"]
    narration = (
        f"今天这件{product_name}属于上身就能进入状态的那种。"
        f"{angles[0]}很明确，{style['occasion']}都能穿，价格大约{price}元，{stock_line}。"
        f"{reason}，喜欢这种路线这周可以先安排试穿。"
    )
    hashtags = build_hashtags(product_name, category, angles)

    return {
        "product_id": item.get("id", product_name),
        "wechat_moments": wechat,
        "xiaohongshu": xiaohongshu,
        "video_script": {
            "title": title,
            "scenes": scenes,
            "narration": narration,
        },
        "hashtags": hashtags,
        "source": "template",
    }


def extract_json_text(content):
    stripped = content.strip()
    fence_match = re.search(r"```(?:json)?\s*(\{.*\})\s*```", stripped, re.S)
    if fence_match:
        return fence_match.group(1)
    return stripped


def call_deepseek(item):
    prompt = f"""你是一个女性服装品牌的内容创作者。请根据以下商品信息生成推广文案，并且只返回一个 JSON 对象，不要输出解释。

商品：{item.get('product_name', '未知商品')}
价格：{item.get('price_yuan', 0)}元
风格：{'、'.join(item.get('angles', []))}
库存：{item.get('stock', 0)}件
推荐理由：{item.get('reason', '店内推荐')}

JSON 字段要求：
- wechat_moments: 80-150 字朋友圈文案
- xiaohongshu: 150-300 字小红书笔记
- video_script: 对象，包含 title、scenes、narration
- hashtags: 数组，3 个以内
"""

    payload = {
        "model": ds_model,
        "temperature": 0.8,
        "messages": [
            {"role": "system", "content": "你擅长输出规范 JSON。"},
            {"role": "user", "content": prompt},
        ],
    }
    request = urllib.request.Request(
        ds_api_url,
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {ds_api_key}",
        },
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=45) as response:
        body = json.loads(response.read().decode("utf-8"))

    content = body["choices"][0]["message"]["content"]
    parsed = json.loads(extract_json_text(content))
    return {
        "product_id": item.get("id", item.get("product_name", "unknown")),
        "wechat_moments": parsed.get("wechat_moments", ""),
        "xiaohongshu": parsed.get("xiaohongshu", ""),
        "video_script": parsed.get("video_script", {}),
        "hashtags": parsed.get("hashtags", []),
        "source": "deepseek",
    }


whiteboard = load_json(whiteboard_path)
selection = whiteboard.get("select", {})

if selection.get("status") != "done":
    print("skip: selector not done")
    raise SystemExit(0)

selected_items = selection.get("output", [])
generated = []
errors = []

for item in selected_items:
    if can_use_deepseek:
        try:
            generated.append(call_deepseek(item))
            continue
        except Exception as exc:  # noqa: BLE001
            errors.append(f"{item.get('product_name', 'unknown')}: {exc}")

    generated.append(fallback_copy(item))

whiteboard["last_updated"] = datetime.now().astimezone().isoformat()
whiteboard["copy"] = {
    "status": "done",
    "output": generated,
    "meta": {
        "generated_count": len(generated),
        "mode": "deepseek" if any(item.get("source") == "deepseek" for item in generated) else "template",
        "errors": errors,
    },
}
whiteboard["package"] = {"status": "pending", "output_path": "", "files": []}
save_json(whiteboard_path, whiteboard)

print(json.dumps({"generated_count": len(generated), "errors": errors}, ensure_ascii=False))
PY

status=$?
if [ "$status" -ne 0 ]; then
  log "文案 Agent 执行失败"
  exit "$status"
fi

log "文案 Agent 完成"