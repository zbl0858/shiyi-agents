#!/usr/bin/env bash

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "${SCRIPT_DIR}/common.sh"

CONTENT_WHITEBOARD="$CONTENT_WHITEBOARD_FILE"
ensure_content_whiteboard "$CONTENT_WHITEBOARD"

log() { echo "[$(date '+%H:%M:%S')] $1"; }

log "开始打包内容产出..."

export CONTENT_WHITEBOARD CONTENT_PACKAGE_ROOT
package_message="$(python3 - <<'PY'
import json
import os
import re
import sys
from datetime import datetime

whiteboard_path = os.environ["CONTENT_WHITEBOARD"]
package_root = os.environ.get("CONTENT_PACKAGE_ROOT", "/tmp")

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")


def load_json(path):
    with open(path, "r", encoding="utf-8") as handle:
        return json.load(handle)


def save_json(path, payload):
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, ensure_ascii=False, indent=2)


def display_path(path):
    return path.replace("\\", "/")


def safe_filename(name):
    cleaned = re.sub(r"[\\/:*?\"<>|]", "_", name)
    cleaned = re.sub(r"\s+", "_", cleaned).strip("_")
    return cleaned or "content"


def write_text(path, content):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(content.rstrip() + "\n")


whiteboard = load_json(whiteboard_path)
copy_block = whiteboard.get("copy", {})

if copy_block.get("status") != "done":
    print("")
    raise SystemExit(0)

select_items = {item.get("id"): item for item in whiteboard.get("select", {}).get("output", [])}
copy_items = copy_block.get("output", [])
today = whiteboard.get("date") or datetime.now().strftime("%Y-%m-%d")
date_compact = today.replace("-", "")
package_dir = os.path.join(package_root, f"content_package_{date_compact}")
display_package_dir = display_path(package_dir)

written_files = []
summary_lines = [f"今日内容包 {today}", ""]

for copy_item in copy_items:
    select_item = select_items.get(copy_item.get("product_id"), {})
    product_name = select_item.get("product_name") or copy_item.get("product_id") or "未命名商品"
    price = select_item.get("price_yuan", 0)
    stock = select_item.get("stock", 0)
    summary_lines.append(f"- {product_name} | ¥{price} | 库存{stock}件")

summary_path = os.path.join(package_dir, "00_今日选题.txt")
write_text(summary_path, "\n".join(summary_lines))
written_files.append(display_path(summary_path))

for copy_item in copy_items:
    select_item = select_items.get(copy_item.get("product_id"), {})
    product_name = select_item.get("product_name") or copy_item.get("product_id") or "未命名商品"
    safe_name = safe_filename(product_name)

    moments_path = os.path.join(package_dir, "朋友圈", f"{safe_name}.txt")
    xhs_path = os.path.join(package_dir, "小红书", f"{safe_name}.txt")
    video_path = os.path.join(package_dir, "视频号", f"{safe_name}_脚本.txt")

    write_text(moments_path, copy_item.get("wechat_moments", ""))
    write_text(xhs_path, copy_item.get("xiaohongshu", ""))

    video_script = copy_item.get("video_script", {})
    video_content = "\n".join(
        [
            video_script.get("title", "视频脚本"),
            "",
            "分镜：",
            *[f"- {scene}" for scene in video_script.get("scenes", [])],
            "",
            "旁白：",
            video_script.get("narration", ""),
        ]
    )
    write_text(video_path, video_content)

    written_files.extend([display_path(moments_path), display_path(xhs_path), display_path(video_path)])

first_select = whiteboard.get("select", {}).get("output", [])
hero = first_select[0] if first_select else {}
hero_copy = copy_items[0] if copy_items else {}
date_label = today[5:].replace("-", "月", 1) + "日" if len(today) == 10 else today
other_items = first_select[1:]

message_lines = [f"📦 今日内容包（{date_label}）", ""]
if hero:
    message_lines.append(
        f"🎯 今日主推：{hero.get('product_name', '未命名商品')} | ¥{hero.get('price_yuan', 0)} | 库存{hero.get('stock', 0)}件"
    )
    message_lines.append("")

if hero_copy:
    message_lines.extend(
        [
            "📱 朋友圈文案：",
            hero_copy.get("wechat_moments", ""),
            "",
            "📕 小红书笔记：",
            hero_copy.get("xiaohongshu", ""),
            "",
            "🎬 视频号脚本：",
            hero_copy.get("video_script", {}).get("title", "15秒视频脚本"),
            "",
        ]
    )

if other_items:
    message_lines.append("🧾 今日补充选题：")
    for item in other_items:
        message_lines.append(
            f"- {item.get('product_name', '未命名商品')} | ¥{item.get('price_yuan', 0)} | {item.get('reason', '店内推荐').replace('本地演示数据：', '').strip()}"
        )
    message_lines.append("")

message_lines.extend(["━━━━━━━━━━━━━━━━━━━━", f"📂 完整文件：{display_package_dir}"])
message = "\n".join(message_lines)

whiteboard["last_updated"] = datetime.now().astimezone().isoformat()
whiteboard["package"] = {
    "status": "done",
    "output_path": display_package_dir,
    "files": written_files,
  }
save_json(whiteboard_path, whiteboard)

print(message)
PY
)"

status=$?
if [ "$status" -ne 0 ]; then
  log "打包 Agent 执行失败"
  exit "$status"
fi

if [ -n "$package_message" ]; then
  write_content_pending_message "$package_message" "${CHATID:-}"
fi

log "打包 Agent 完成"