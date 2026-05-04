#!/usr/bin/env bash

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "${SCRIPT_DIR}/common.sh"

CONTENT_WHITEBOARD="$CONTENT_WHITEBOARD_FILE"
ensure_content_whiteboard "$CONTENT_WHITEBOARD"

log() { echo "[$(date '+%H:%M:%S')] $1"; }

log "开始生成内容预览..."

export CONTENT_WHITEBOARD DAILY_CONTENT_MSG_FILE
python3 - <<'PY'
import html
import json
import os
import re
from datetime import datetime

whiteboard_path = os.environ["CONTENT_WHITEBOARD"]
message_path = os.environ["DAILY_CONTENT_MSG_FILE"]


def load_json(path):
    with open(path, "r", encoding="utf-8") as handle:
        return json.load(handle)


def write_text(path, content):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(content.rstrip() + "\n")


def read_optional_text(path):
    if not path or not os.path.exists(path):
        return ""
    with open(path, "r", encoding="utf-8") as handle:
        return handle.read().strip()


def markdown_escape(text):
    return str(text).replace("|", "\\|").replace("\n", " ").strip()


def display_path(path):
    return path.replace("\\", "/")


def html_escape(text):
    return html.escape(str(text), quote=True)


def nl2br(text):
    return html_escape(text).replace("\n", "<br>")


def status_class(status):
    return {
        "done": "status-done",
        "pending": "status-pending",
    }.get(status, "status-muted")


def safe_id(value):
    parts = []
    for char in str(value):
        if re.match(r"[a-zA-Z0-9_-]", char):
            parts.append(char)
        elif char.isspace() or char in "/\\":
            parts.append("-")
        else:
            parts.append(f"u{ord(char):x}")
    normalized = re.sub(r"-+", "-", "".join(parts)).strip("-")
    return normalized or "item"


def clean_reason(text):
    return str(text or "店内推荐").replace("本地演示数据：", "").strip()


def build_script_copy(video_script):
    title = video_script.get("title", "未生成")
    scenes = video_script.get("scenes", [])
    narration = video_script.get("narration", "未生成")
    lines = [title, "", "分镜："]
    if scenes:
        lines.extend([f"- {scene}" for scene in scenes])
    else:
        lines.append("- 未生成")
    lines.extend(["", "旁白：", narration])
    return "\n".join(lines)


def relative_href(base_dir, target_path):
    try:
        return display_path(os.path.relpath(target_path, base_dir))
    except ValueError:
        return display_path(target_path)


def build_package_index(preview_date, preview_dir, display_package_dir, display_preview_path, display_html_path, display_index_path, summary_message, selected_items, package_files, select_block, copy_block, package_block):
    grouped_files = {}
    for path in package_files:
        rel_path = relative_href(preview_dir, path)
        group_name = os.path.dirname(rel_path)
        if group_name in ("", "."):
            group_name = "根目录"
        grouped_files.setdefault(group_name, []).append(
            {
                "name": os.path.basename(path),
                "href": rel_path,
                "path": rel_path,
            }
        )

    group_order = {"根目录": 0, "朋友圈": 1, "小红书": 2, "视频号": 3}
    ordered_groups = sorted(grouped_files.items(), key=lambda item: (group_order.get(item[0], 99), item[0]))
    nav_html = "".join(
        f'<a class="nav-chip" href="#group-{safe_id(group_name)}">{html_escape(group_name)}</a>'
        for group_name, _ in ordered_groups
    )

    group_sections = []
    for group_name, files in ordered_groups:
        file_cards = "".join(
            f"""
            <a class="file-card" href="{html_escape(file_info['href'])}">
              <strong>{html_escape(file_info['name'])}</strong>
              <span>{html_escape(file_info['path'])}</span>
            </a>
            """
            for file_info in files
        )
        group_sections.append(
            f"""
            <section class="group-panel" id="group-{safe_id(group_name)}">
              <div class="section-head">
                <div>
                  <p class="eyebrow">渠道文件</p>
                  <h2>{html_escape(group_name)}</h2>
                </div>
                <span class="count-badge">{len(files)} 个文件</span>
              </div>
              <div class="file-grid">{file_cards}</div>
            </section>
            """
        )

    summary_panel = ""
    if summary_message:
        summary_panel = f"""
        <section class="summary-panel panel">
          <div class="section-head">
            <div>
              <p class="eyebrow">群摘要</p>
              <h2>发送前总览</h2>
            </div>
          </div>
          <pre>{html_escape(summary_message)}</pre>
        </section>
        """

    product_cards = "".join(
        f"""
        <article class="product-card">
          <p class="eyebrow">{html_escape(item.get('category', '服饰'))}</p>
          <h3>{html_escape(item.get('product_name', '未命名商品'))}</h3>
          <p class="product-meta">¥{html_escape(item.get('price_yuan', 0))} · {html_escape(item.get('stock', 0))}件库存</p>
          <p class="product-reason">{html_escape(clean_reason(item.get('reason', '店内推荐')))}</p>
        </article>
        """
        for item in selected_items
    ) or '<article class="product-card"><h3>暂无选题</h3><p class="product-reason">请先执行内容流水线，再重新生成内容包首页。</p></article>'

    preview_html_href = relative_href(preview_dir, os.path.join(preview_dir, "内容预览.html"))
    preview_md_href = relative_href(preview_dir, os.path.join(preview_dir, "内容预览.md"))

    status_items = [
        ("选品状态", select_block.get("status", "pending")),
        ("文案状态", copy_block.get("status", "pending")),
        ("打包状态", package_block.get("status", "pending")),
        ("渠道文件", str(len(package_files))),
    ]
    status_html = "".join(
        f'<div class="status-card"><span>{html_escape(label)}</span><strong class="{status_class(status)}">{html_escape(status)}</strong></div>'
        if label != "渠道文件"
        else f'<div class="status-card"><span>{html_escape(label)}</span><strong>{html_escape(status)}</strong></div>'
        for label, status in status_items
    )

    template = """<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>内容包首页 - __PREVIEW_DATE__</title>
  <style>
    :root {
      --bg: #f7f0e5;
      --ink: #261d17;
      --muted: #6b5647;
      --line: rgba(84, 59, 39, 0.14);
      --panel: rgba(255, 252, 247, 0.86);
      --accent: #b3542c;
      --accent-deep: #7f3618;
      --ok: #2d7a4e;
      --shadow: 0 22px 60px rgba(76, 44, 22, 0.12);
      --radius-lg: 24px;
      --radius-md: 18px;
      --radius-sm: 14px;
      --font-display: Georgia, 'Times New Roman', serif;
      --font-body: 'IBM Plex Sans', 'Noto Sans SC', 'PingFang SC', sans-serif;
    }

    * { box-sizing: border-box; }
    html { scroll-behavior: smooth; }
    body {
      margin: 0;
      min-height: 100vh;
      font-family: var(--font-body);
      color: var(--ink);
      background:
        radial-gradient(circle at 12% 12%, rgba(255, 255, 255, 0.78), transparent 28%),
        radial-gradient(circle at 88% 8%, rgba(222, 177, 132, 0.28), transparent 24%),
        linear-gradient(180deg, #f8efe2 0%, #f1e4d4 100%);
    }

    .shell {
      width: min(1160px, calc(100% - 28px));
      margin: 0 auto;
      padding: 28px 0 44px;
    }

    .hero, .panel, .group-panel, .product-card, .status-card {
      background: var(--panel);
      border: 1px solid rgba(255, 255, 255, 0.72);
      backdrop-filter: blur(10px);
      box-shadow: var(--shadow);
    }

    .hero {
      border-radius: var(--radius-lg);
      padding: 28px;
      position: relative;
      overflow: hidden;
    }

    .hero::after {
      content: '';
      position: absolute;
      right: -40px;
      bottom: -60px;
      width: 240px;
      height: 240px;
      border-radius: 50%;
      background: radial-gradient(circle, rgba(179, 84, 44, 0.18), transparent 68%);
      pointer-events: none;
    }

    .eyebrow {
      margin: 0 0 8px;
      font-size: 12px;
      letter-spacing: 0.16em;
      text-transform: uppercase;
      color: var(--accent-deep);
      font-weight: 700;
    }

    h1, h2, h3, p { margin: 0; }
    h1 {
      font-family: var(--font-display);
      font-size: clamp(34px, 5vw, 56px);
      line-height: 1.04;
      max-width: 11ch;
    }

    .hero-desc {
      margin-top: 14px;
      max-width: 62ch;
      color: var(--muted);
      line-height: 1.75;
    }

    .action-row, .quick-nav, .status-grid, .entry-grid, .product-grid, .file-grid {
      display: grid;
      gap: 14px;
    }

    .action-row {
      grid-template-columns: repeat(auto-fit, minmax(220px, max-content));
      margin-top: 22px;
    }

    .quick-nav {
      grid-template-columns: repeat(auto-fit, minmax(120px, max-content));
      margin-top: 16px;
    }

    .status-grid {
      grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
      margin-top: 22px;
    }

    .entry-grid, .product-grid {
      grid-template-columns: repeat(auto-fit, minmax(240px, 1fr));
      margin-top: 22px;
    }

    .file-grid {
      grid-template-columns: repeat(auto-fit, minmax(240px, 1fr));
      margin-top: 18px;
    }

    .action-link, .nav-chip, .file-card {
      text-decoration: none;
      color: var(--ink);
      border: 1px solid rgba(127, 54, 24, 0.14);
      background: rgba(255, 255, 255, 0.7);
      transition: transform 180ms ease, box-shadow 180ms ease, border-color 180ms ease;
    }

    .action-link, .nav-chip {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      min-height: 44px;
      padding: 0 16px;
      border-radius: 999px;
      font-weight: 600;
    }

    .action-link.primary {
      background: linear-gradient(135deg, var(--accent), var(--accent-deep));
      color: #fffdf8;
      border-color: transparent;
    }

    .file-card {
      display: flex;
      flex-direction: column;
      gap: 8px;
      padding: 16px;
      border-radius: var(--radius-sm);
      min-height: 110px;
    }

    .file-card span, .entry-card p, .product-meta, .product-reason, .status-card span, .meta-line {
      color: var(--muted);
    }

    .file-card span {
      font-size: 13px;
      line-height: 1.6;
      word-break: break-all;
    }

    .action-link:hover, .nav-chip:hover, .file-card:hover {
      transform: translateY(-1px);
      box-shadow: 0 12px 24px rgba(76, 44, 22, 0.1);
    }

    .entry-card, .panel, .group-panel, .product-card {
      border-radius: var(--radius-md);
      padding: 20px;
    }

    .entry-card {
      background: rgba(255, 255, 255, 0.58);
      border: 1px solid var(--line);
    }

    .entry-card strong { display: block; margin-bottom: 10px; }
    .entry-card a { color: var(--accent-deep); font-weight: 600; }
    .meta-line { margin-top: 10px; font-size: 14px; line-height: 1.7; word-break: break-all; }

    .section-head {
      display: flex;
      align-items: start;
      justify-content: space-between;
      gap: 12px;
    }

    .count-badge {
      display: inline-flex;
      align-items: center;
      min-height: 34px;
      padding: 0 12px;
      border-radius: 999px;
      background: rgba(45, 122, 78, 0.12);
      color: var(--ok);
      font-weight: 700;
      font-size: 13px;
      white-space: nowrap;
    }

    .summary-panel { margin-top: 22px; }
    .summary-panel pre {
      margin: 16px 0 0;
      white-space: pre-wrap;
      background: rgba(255, 255, 255, 0.62);
      border: 1px solid var(--line);
      border-radius: var(--radius-sm);
      padding: 16px;
      line-height: 1.75;
      font-family: var(--font-body);
      font-size: 14px;
    }

    .sections { display: grid; gap: 18px; margin-top: 22px; }
    .product-card h3 { font-family: var(--font-display); font-size: 24px; }
    .product-meta { margin-top: 10px; font-size: 14px; }
    .product-reason { margin-top: 12px; line-height: 1.7; }

    .status-card {
      border-radius: var(--radius-sm);
      padding: 14px 16px;
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 12px;
    }

    .status-card strong { font-size: 14px; text-transform: uppercase; letter-spacing: 0.08em; }
    .status-done { color: var(--ok); }
    .status-pending { color: #9f6d18; }
    .status-muted { color: var(--muted); }

    @media (max-width: 720px) {
      .shell { width: min(100% - 20px, 1160px); padding: 18px 0 30px; }
      .hero, .panel, .group-panel, .product-card, .entry-card { padding: 18px; }
      .section-head { flex-direction: column; }
      .action-row, .quick-nav { grid-template-columns: 1fr; }
      .action-link, .nav-chip { width: 100%; }
    }

    @media print {
      body { background: #fff; }
      .shell { width: 100%; padding: 0; }
      .hero, .panel, .group-panel, .product-card, .entry-card, .status-card {
        box-shadow: none;
        background: #fff;
        border-color: #ddd2c5;
        backdrop-filter: none;
      }
      .action-row, .quick-nav { display: none; }
    }
  </style>
</head>
<body>
  <div class="shell">
    <header class="hero">
      <p class="eyebrow">Shiyi Content Package</p>
      <h1>今日内容包首页已就绪。</h1>
      <p class="hero-desc">这个首页把预览入口、渠道文件和今日主推选题放到同一页，适合你先做一轮检查，再把单文件或 PDF 发给运营同事。</p>
      <div class="action-row">
        <a class="action-link primary" href="__PREVIEW_HTML_HREF__">打开交互预览页</a>
        <a class="action-link" href="__PREVIEW_MD_HREF__">打开 Markdown 预览</a>
      </div>
      <nav class="quick-nav" aria-label="文件分组目录">__NAV_HTML__</nav>
      <div class="status-grid">__STATUS_HTML__</div>
    </header>

    <section class="entry-grid">
      <article class="entry-card">
        <strong>内容包目录</strong>
        <p class="meta-line">__PACKAGE_DIR__</p>
      </article>
      <article class="entry-card">
        <strong>首页文件</strong>
        <p class="meta-line">__INDEX_PATH__</p>
      </article>
      <article class="entry-card">
        <strong>预览文件</strong>
        <p class="meta-line">__PREVIEW_HTML_PATH__</p>
        <p class="meta-line">__PREVIEW_MD_PATH__</p>
      </article>
    </section>

    __SUMMARY_PANEL__

    <section class="panel sections">
      <div class="section-head">
        <div>
          <p class="eyebrow">今日选题</p>
          <h2>主推与补充内容</h2>
        </div>
        <span class="count-badge">__SELECTED_COUNT__ 个选题</span>
      </div>
      <div class="product-grid">__PRODUCT_CARDS__</div>
    </section>

    <div class="sections">__GROUP_SECTIONS__</div>
  </div>
</body>
</html>
"""

    return (
        template.replace("__PREVIEW_DATE__", html_escape(preview_date))
        .replace("__PREVIEW_HTML_HREF__", html_escape(preview_html_href))
        .replace("__PREVIEW_MD_HREF__", html_escape(preview_md_href))
        .replace("__NAV_HTML__", nav_html)
        .replace("__STATUS_HTML__", status_html)
        .replace("__PACKAGE_DIR__", html_escape(display_package_dir))
        .replace("__INDEX_PATH__", html_escape(display_index_path))
        .replace("__PREVIEW_HTML_PATH__", html_escape(display_html_path))
        .replace("__PREVIEW_MD_PATH__", html_escape(display_preview_path))
        .replace("__SUMMARY_PANEL__", summary_panel)
        .replace("__SELECTED_COUNT__", html_escape(len(selected_items)))
        .replace("__PRODUCT_CARDS__", product_cards)
        .replace("__GROUP_SECTIONS__", "".join(group_sections))
    )


def build_markdown_preview(preview_date, display_package_dir, display_preview_path, selected_items, copy_by_id, select_block, copy_block, package_block, summary_message):
    lines = [f"# 今日内容预览（{preview_date}）", ""]
    lines.extend(
        [
            "## 当前状态",
            "",
            f"- 选品状态：{select_block.get('status', 'pending')}",
            f"- 文案状态：{copy_block.get('status', 'pending')}",
            f"- 打包状态：{package_block.get('status', 'pending')}",
            f"- 内容包目录：{display_package_dir}",
            f"- 预览文件：{display_preview_path}",
            "",
        ]
    )

    if summary_message:
        lines.extend(["## 群摘要预览", "", summary_message, ""])

    if selected_items:
        lines.extend(["## 今日选题总览", "", "| 商品 | 价格 | 库存 | 推荐理由 |", "| --- | ---: | ---: | --- |"])
        for item in selected_items:
            lines.append(
                "| {name} | {price} | {stock} | {reason} |".format(
                    name=markdown_escape(item.get("product_name", "未命名商品")),
                    price=markdown_escape(f"¥{item.get('price_yuan', 0)}"),
                    stock=markdown_escape(f"{item.get('stock', 0)}件"),
                    reason=markdown_escape(clean_reason(item.get("reason", "店内推荐"))),
                )
            )
        lines.append("")

    for item in selected_items:
        copy_item = copy_by_id.get(item.get("id"), {})
        video_script = copy_item.get("video_script", {})
        lines.extend(
            [
                f"## {item.get('product_name', '未命名商品')}",
                "",
                f"- 价格：¥{item.get('price_yuan', 0)}",
                f"- 库存：{item.get('stock', 0)}件",
                f"- 角度：{' / '.join(item.get('angles', []))}",
                "",
                "### 朋友圈文案",
                "",
                copy_item.get("wechat_moments", "未生成"),
                "",
                "### 小红书笔记",
                "",
                copy_item.get("xiaohongshu", "未生成"),
                "",
                "### 视频号脚本",
                "",
                f"标题：{video_script.get('title', '未生成')}",
                "",
                "分镜：",
            ]
        )
        scenes = video_script.get("scenes", [])
        if scenes:
            lines.extend([f"- {scene}" for scene in scenes])
        else:
            lines.append("- 未生成")
        lines.extend(["", "旁白：", video_script.get("narration", "未生成"), ""])

    return "\n".join(lines)


def build_html_preview(preview_date, display_package_dir, display_preview_path, display_html_path, display_index_path, index_href, summary_message, selected_items, copy_by_id, select_block, copy_block, package_block):
    nav_items = []
    if summary_message:
        nav_items.append(("summary", "群摘要"))
    nav_items.append(("overview", "选题总览"))

    copy_stores = []
    if summary_message:
        copy_stores.append(
            f'<textarea id="copy-summary" class="copy-store" aria-hidden="true">{html_escape(summary_message)}</textarea>'
        )

    action_buttons = []
    if summary_message:
        action_buttons.append('<button type="button" class="action-btn action-primary" data-copy-target="copy-summary" data-copy-label="群摘要">复制群摘要</button>')
    action_buttons.append(f'<a class="action-btn" href="{html_escape(index_href)}">打开内容包首页</a>')
    action_buttons.append('<a class="action-btn" href="#overview">查看选题总览</a>')
    action_buttons.append('<button type="button" class="action-btn" data-print-page>打印页面</button>')
    action_bar_html = "".join(action_buttons)

    summary_html = ""
    if summary_message:
        summary_html = f"""
        <section class="panel summary-panel" id="summary">
          <div class="panel-heading panel-heading-inline">
            <div>
              <p class="eyebrow">群摘要</p>
              <h2>今日发送预览</h2>
            </div>
            <button type="button" class="copy-btn" data-copy-target="copy-summary" data-copy-label="群摘要">复制</button>
          </div>
          <pre class="summary-copy">{html_escape(summary_message)}</pre>
        </section>
        """

    if selected_items:
        overview_rows = "".join(
            f"""
            <tr>
              <td>{html_escape(item.get('product_name', '未命名商品'))}</td>
              <td>¥{html_escape(item.get('price_yuan', 0))}</td>
              <td>{html_escape(item.get('stock', 0))}件</td>
              <td>{html_escape(clean_reason(item.get('reason', '店内推荐')))}</td>
            </tr>
            """
            for item in selected_items
        )
    else:
        overview_rows = '<tr><td colspan="4">当前没有可展示的选题。</td></tr>'

    item_sections = []
    for item in selected_items:
        item_key = safe_id(item.get("id") or item.get("product_name", "item"))
        section_id = f"item-{item_key}"
        nav_items.append((section_id, item.get("product_name", "未命名商品")))

        copy_item = copy_by_id.get(item.get("id"), {})
        video_script = copy_item.get("video_script", {})
        scenes = video_script.get("scenes", [])
        scene_html = "".join(f'<li>{html_escape(scene)}</li>' for scene in scenes) or "<li>未生成</li>"
        hashtags = copy_item.get("hashtags", [])
        tags_html = "".join(f'<span class="tag">{html_escape(tag)}</span>' for tag in hashtags) or '<span class="tag">待补充标签</span>'
        angle_html = "".join(f'<span class="chip">{html_escape(angle)}</span>' for angle in item.get("angles", [])) or '<span class="chip">待补充角度</span>'

        wechat_id = f"copy-wechat-{item_key}"
        xhs_id = f"copy-xhs-{item_key}"
        script_id = f"copy-script-{item_key}"
        copy_stores.extend(
            [
                f'<textarea id="{wechat_id}" class="copy-store" aria-hidden="true">{html_escape(copy_item.get("wechat_moments", "未生成"))}</textarea>',
                f'<textarea id="{xhs_id}" class="copy-store" aria-hidden="true">{html_escape(copy_item.get("xiaohongshu", "未生成"))}</textarea>',
                f'<textarea id="{script_id}" class="copy-store" aria-hidden="true">{html_escape(build_script_copy(video_script))}</textarea>',
            ]
        )

        item_sections.append(
            f"""
            <section class="item-card" id="{section_id}">
              <div class="item-header">
                <div>
                  <p class="eyebrow">{html_escape(item.get('category', '服饰'))}</p>
                  <h3>{html_escape(item.get('product_name', '未命名商品'))}</h3>
                </div>
                <div class="item-meta">
                  <span>¥{html_escape(item.get('price_yuan', 0))}</span>
                  <span>{html_escape(item.get('stock', 0))}件库存</span>
                </div>
              </div>
              <p class="item-reason">{html_escape(clean_reason(item.get('reason', '店内推荐')))}</p>
              <div class="angle-row">{angle_html}</div>
              <div class="copy-grid">
                <article class="copy-panel">
                  <div class="panel-title-row">
                    <h4>朋友圈文案</h4>
                    <button type="button" class="copy-btn" data-copy-target="{wechat_id}" data-copy-label="朋友圈文案">复制</button>
                  </div>
                  <p>{nl2br(copy_item.get('wechat_moments', '未生成'))}</p>
                </article>
                <article class="copy-panel">
                  <div class="panel-title-row">
                    <h4>小红书笔记</h4>
                    <button type="button" class="copy-btn" data-copy-target="{xhs_id}" data-copy-label="小红书笔记">复制</button>
                  </div>
                  <p>{nl2br(copy_item.get('xiaohongshu', '未生成'))}</p>
                </article>
              </div>
              <article class="script-panel">
                <div class="script-header">
                  <div>
                    <p class="eyebrow">视频号脚本</p>
                    <h4>{html_escape(video_script.get('title', '未生成'))}</h4>
                  </div>
                  <div class="script-actions">
                    <div class="tag-row">{tags_html}</div>
                    <button type="button" class="copy-btn" data-copy-target="{script_id}" data-copy-label="视频脚本">复制脚本</button>
                  </div>
                </div>
                <div class="script-grid">
                  <div>
                    <p class="subhead">分镜</p>
                    <ol>{scene_html}</ol>
                  </div>
                  <div>
                    <p class="subhead">旁白</p>
                    <p>{nl2br(video_script.get('narration', '未生成'))}</p>
                  </div>
                </div>
              </article>
            </section>
            """
        )

    nav_html = "".join(
        f'<a class="nav-chip" href="#{html_escape(anchor)}">{html_escape(label)}</a>'
        for anchor, label in nav_items
    )
    copy_store_html = "\n".join(copy_stores)

    status_items = [
        ("选品状态", select_block.get("status", "pending")),
        ("文案状态", copy_block.get("status", "pending")),
        ("打包状态", package_block.get("status", "pending")),
    ]
    status_html = "".join(
        f'<div class="status-card"><span>{html_escape(label)}</span><strong class="{status_class(status)}">{html_escape(status)}</strong></div>'
        for label, status in status_items
    )

    template = """<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>今日内容预览 - __PREVIEW_DATE__</title>
  <style>
    :root {
      --bg: #f6efe4;
      --bg-accent: #f0dcc4;
      --panel: rgba(255, 250, 243, 0.86);
      --text: #2b2018;
      --muted: #6d5848;
      --line: rgba(77, 52, 34, 0.12);
      --brand: #c05a2b;
      --brand-deep: #8f3c18;
      --green: #2d7a4e;
      --amber: #9f6d18;
      --shadow: 0 18px 60px rgba(88, 48, 23, 0.16);
      --radius-xl: 28px;
      --radius-lg: 20px;
      --radius-md: 14px;
      --font-display: Georgia, 'Times New Roman', serif;
      --font-body: 'IBM Plex Sans', 'Noto Sans SC', 'PingFang SC', sans-serif;
    }

    * { box-sizing: border-box; }
    html { scroll-behavior: smooth; }
    body {
      margin: 0;
      font-family: var(--font-body);
      color: var(--text);
      background:
        radial-gradient(circle at top left, rgba(255, 255, 255, 0.7), transparent 34%),
        radial-gradient(circle at top right, rgba(240, 188, 129, 0.28), transparent 30%),
        linear-gradient(160deg, var(--bg) 0%, var(--bg-accent) 100%);
      min-height: 100vh;
    }

    section[id] { scroll-margin-top: 24px; }

    .shell {
      width: min(1180px, calc(100% - 32px));
      margin: 0 auto;
      padding: 32px 0 56px;
    }

    .hero {
      background: linear-gradient(140deg, rgba(255, 248, 238, 0.96), rgba(247, 228, 206, 0.9));
      border: 1px solid rgba(255, 255, 255, 0.65);
      border-radius: var(--radius-xl);
      box-shadow: var(--shadow);
      padding: 28px;
      position: relative;
      overflow: hidden;
    }

    .hero::after {
      content: '';
      position: absolute;
      inset: auto -120px -120px auto;
      width: 280px;
      height: 280px;
      background: radial-gradient(circle, rgba(192, 90, 43, 0.18), transparent 70%);
      pointer-events: none;
    }

    .eyebrow {
      margin: 0 0 8px;
      font-size: 12px;
      letter-spacing: 0.16em;
      text-transform: uppercase;
      color: var(--brand-deep);
      font-weight: 700;
    }

    h1, h2, h3, h4 {
      margin: 0;
      font-weight: 700;
    }

    h1 {
      font-family: var(--font-display);
      font-size: clamp(34px, 5vw, 54px);
      line-height: 1.04;
      max-width: 10ch;
    }

    .hero p.desc {
      max-width: 60ch;
      color: var(--muted);
      font-size: 16px;
      line-height: 1.7;
      margin: 14px 0 0;
    }

    .action-row {
      display: flex;
      gap: 10px;
      flex-wrap: wrap;
      margin-top: 20px;
    }

    .action-btn, .copy-btn, .nav-chip {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      min-height: 44px;
      padding: 0 16px;
      border-radius: 999px;
      border: 1px solid rgba(143, 60, 24, 0.18);
      background: rgba(255, 255, 255, 0.72);
      color: var(--text);
      font: inherit;
      font-size: 14px;
      font-weight: 600;
      cursor: pointer;
      text-decoration: none;
      transition: transform 180ms ease, background 180ms ease, border-color 180ms ease, box-shadow 180ms ease;
    }

    .action-primary {
      background: linear-gradient(135deg, var(--brand), var(--brand-deep));
      color: #fffdf8;
      border-color: transparent;
    }

    .action-btn:hover, .copy-btn:hover, .nav-chip:hover {
      transform: translateY(-1px);
      box-shadow: 0 10px 20px rgba(88, 48, 23, 0.12);
    }

    .action-btn:focus-visible, .copy-btn:focus-visible, .nav-chip:focus-visible {
      outline: 3px solid rgba(192, 90, 43, 0.28);
      outline-offset: 2px;
    }

    .quick-nav {
      display: flex;
      flex-wrap: wrap;
      gap: 10px;
      margin-top: 18px;
    }

    .nav-chip {
      min-height: 38px;
      padding: 0 14px;
      background: rgba(255, 255, 255, 0.58);
      font-size: 13px;
    }

    .status-grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
      gap: 12px;
      margin-top: 22px;
    }

    .status-card, .meta-card, .panel, .item-card {
      background: var(--panel);
      border: 1px solid rgba(255, 255, 255, 0.68);
      backdrop-filter: blur(12px);
      box-shadow: var(--shadow);
    }

    .status-card {
      border-radius: var(--radius-md);
      padding: 14px 16px;
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 12px;
    }

    .status-card span { color: var(--muted); font-size: 14px; }
    .status-card strong { font-size: 14px; text-transform: uppercase; letter-spacing: 0.08em; }
    .status-done { color: var(--green); }
    .status-pending { color: var(--amber); }
    .status-muted { color: var(--muted); }

    .meta-grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(260px, 1fr));
      gap: 16px;
      margin-top: 18px;
    }

    .meta-card {
      border-radius: var(--radius-lg);
      padding: 18px 20px;
    }

    .meta-card p { margin: 6px 0 0; color: var(--muted); line-height: 1.65; word-break: break-all; }

    .main-grid {
      display: grid;
      grid-template-columns: minmax(0, 1.15fr) minmax(300px, 0.85fr);
      gap: 18px;
      margin-top: 22px;
      align-items: start;
    }

    .panel {
      border-radius: var(--radius-lg);
      padding: 20px 22px;
    }

    .panel-heading { display: flex; flex-direction: column; gap: 6px; margin-bottom: 14px; }
    .panel-heading-inline { display: flex; flex-direction: row; align-items: start; justify-content: space-between; gap: 12px; }
    .summary-copy {
      white-space: pre-wrap;
      font-family: var(--font-body);
      font-size: 15px;
      line-height: 1.75;
      background: rgba(255, 255, 255, 0.6);
      border: 1px solid var(--line);
      border-radius: var(--radius-md);
      padding: 16px;
      margin: 0;
    }

    table { width: 100%; border-collapse: collapse; font-size: 14px; }
    th, td { text-align: left; padding: 12px 10px; border-bottom: 1px solid var(--line); vertical-align: top; }
    th { color: var(--muted); font-weight: 600; }

    .items { display: grid; gap: 18px; margin-top: 22px; }
    .item-card { border-radius: var(--radius-lg); padding: 22px; }
    .item-header { display: flex; justify-content: space-between; gap: 14px; align-items: start; }
    .item-header h3 { font-size: 26px; font-family: var(--font-display); }
    .item-meta { display: flex; gap: 10px; flex-wrap: wrap; color: var(--muted); font-size: 14px; }
    .item-reason { margin: 14px 0 0; color: var(--muted); line-height: 1.7; }
    .angle-row, .tag-row { display: flex; flex-wrap: wrap; gap: 8px; }
    .angle-row { margin-top: 14px; }
    .panel-title-row { display: flex; justify-content: space-between; gap: 12px; align-items: center; margin-bottom: 10px; }
    .chip, .tag {
      display: inline-flex;
      align-items: center;
      min-height: 32px;
      padding: 0 12px;
      border-radius: 999px;
      font-size: 13px;
      font-weight: 600;
    }
    .chip { background: rgba(192, 90, 43, 0.1); color: var(--brand-deep); }
    .tag { background: rgba(45, 122, 78, 0.12); color: var(--green); }

    .copy-grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 14px; margin-top: 18px; }
    .copy-panel, .script-panel { background: rgba(255, 255, 255, 0.58); border: 1px solid var(--line); border-radius: var(--radius-md); }
    .copy-panel { padding: 18px; }
    .copy-panel h4, .script-header h4 { margin-bottom: 10px; font-size: 17px; }
    .copy-panel p, .script-panel p, .script-panel li { color: var(--text); line-height: 1.75; margin: 0; }

    .script-panel { margin-top: 14px; padding: 18px; }
    .script-header { display: flex; justify-content: space-between; gap: 12px; align-items: start; margin-bottom: 14px; }
    .script-actions { display: flex; gap: 12px; align-items: center; justify-content: end; flex-wrap: wrap; }
    .script-grid { display: grid; grid-template-columns: minmax(200px, 0.9fr) minmax(0, 1.1fr); gap: 16px; }
    .subhead { margin: 0 0 8px; font-size: 13px; letter-spacing: 0.08em; text-transform: uppercase; color: var(--muted); font-weight: 700; }
    ol { margin: 0; padding-left: 20px; }
    .copy-store { position: absolute; left: -9999px; opacity: 0; pointer-events: none; }
    .copy-btn { min-height: 38px; padding: 0 14px; font-size: 13px; background: rgba(255, 248, 238, 0.9); }
    .copy-btn.is-copied { background: rgba(45, 122, 78, 0.12); color: var(--green); border-color: rgba(45, 122, 78, 0.18); }

    @media (max-width: 960px) {
      .main-grid, .copy-grid, .script-grid { grid-template-columns: 1fr; }
      .item-header, .script-header, .panel-heading-inline { flex-direction: column; }
    }

    @media (max-width: 640px) {
      .shell { width: min(100% - 20px, 1180px); padding: 18px 0 36px; }
      .hero, .panel, .item-card, .meta-card { padding: 18px; }
      h1 { max-width: none; }
      .summary-copy { font-size: 14px; }
      .action-row { flex-direction: column; }
      .action-btn, .copy-btn, .nav-chip { width: 100%; }
    }

    @media (prefers-reduced-motion: reduce) {
      *, *::before, *::after { scroll-behavior: auto; animation: none !important; transition: none !important; }
    }

    @page { margin: 14mm; }
    @media print {
      body { background: #fff; }
      .shell { width: 100%; padding: 0; }
      .hero::after, .action-row, .quick-nav, .copy-btn { display: none !important; }
      .status-card, .meta-card, .panel, .item-card, .copy-panel, .script-panel {
        box-shadow: none;
        background: #fff;
        border-color: #ddd2c5;
        backdrop-filter: none;
      }
      .main-grid, .copy-grid, .script-grid { grid-template-columns: 1fr; }
      .item-card, .panel, .meta-card, .hero { break-inside: avoid; }
    }
  </style>
</head>
<body>
  <div class="shell">
    <header class="hero">
      <p class="eyebrow">Shiyi Content Preview</p>
      <h1>今日内容包已经整理好了。</h1>
      <p class="desc">这份页面把当天的选题、平台文案、视频脚本和群摘要放进同一张预览面板里，方便你在本地快速过稿，再决定要不要切到真实数据或 AI 文案。</p>
      <div class="action-row">__ACTION_BAR_HTML__</div>
      <nav class="quick-nav" aria-label="页面目录">__NAV_HTML__</nav>
      <div class="status-grid">__STATUS_HTML__</div>
      <div class="meta-grid">
        <section class="meta-card">
          <p class="eyebrow">内容包目录</p>
          <p>__PACKAGE_DIR__</p>
        </section>
        <section class="meta-card">
          <p class="eyebrow">预览文件</p>
          <p>__PREVIEW_MD__</p>
          <p>__PREVIEW_HTML__</p>
          <p>__INDEX_HTML__</p>
        </section>
      </div>
    </header>

    <section class="main-grid">
      __SUMMARY_HTML__
      <section class="panel" id="overview">
        <div class="panel-heading">
          <p class="eyebrow">选题总览</p>
          <h2>今日主推与补充选题</h2>
        </div>
        <table>
          <thead>
            <tr>
              <th>商品</th>
              <th>价格</th>
              <th>库存</th>
              <th>推荐理由</th>
            </tr>
          </thead>
          <tbody>
            __OVERVIEW_ROWS__
          </tbody>
        </table>
      </section>
    </section>

    <section class="items">
      __ITEM_SECTIONS__
    </section>
  </div>
  __COPY_STORE_HTML__
  <script>
    (() => {
      const setCopiedState = (button, label) => {
        const original = button.dataset.originalLabel || button.textContent.trim();
        button.dataset.originalLabel = original;
        button.textContent = `${label}已复制`;
        button.classList.add('is-copied');
        window.setTimeout(() => {
          button.textContent = original;
          button.classList.remove('is-copied');
        }, 1600);
      };

      const fallbackCopy = (text) => {
        const textarea = document.createElement('textarea');
        textarea.value = text;
        textarea.setAttribute('readonly', 'readonly');
        textarea.style.position = 'fixed';
        textarea.style.left = '-9999px';
        document.body.appendChild(textarea);
        textarea.select();
        document.execCommand('copy');
        document.body.removeChild(textarea);
      };

      document.querySelectorAll('[data-copy-target]').forEach((button) => {
        button.addEventListener('click', async () => {
          const store = document.getElementById(button.dataset.copyTarget);
          if (!store) return;
          const text = store.value || store.textContent || '';
          try {
            if (navigator.clipboard && window.isSecureContext) {
              await navigator.clipboard.writeText(text);
            } else {
              fallbackCopy(text);
            }
            setCopiedState(button, button.dataset.copyLabel || '内容');
          } catch (error) {
            fallbackCopy(text);
            setCopiedState(button, button.dataset.copyLabel || '内容');
          }
        });
      });

      document.querySelectorAll('[data-print-page]').forEach((button) => {
        button.addEventListener('click', () => window.print());
      });
    })();
  </script>
</body>
</html>
"""

    return (
        template.replace("__PREVIEW_DATE__", html_escape(preview_date))
        .replace("__ACTION_BAR_HTML__", action_bar_html)
        .replace("__NAV_HTML__", nav_html)
        .replace("__STATUS_HTML__", status_html)
        .replace("__PACKAGE_DIR__", html_escape(display_package_dir))
        .replace("__PREVIEW_MD__", html_escape(display_preview_path))
        .replace("__PREVIEW_HTML__", html_escape(display_html_path))
        .replace("__INDEX_HTML__", html_escape(display_index_path))
        .replace("__SUMMARY_HTML__", summary_html)
        .replace("__OVERVIEW_ROWS__", overview_rows)
        .replace("__ITEM_SECTIONS__", "".join(item_sections))
        .replace("__COPY_STORE_HTML__", copy_store_html)
    )


whiteboard = load_json(whiteboard_path)
select_block = whiteboard.get("select", {})
copy_block = whiteboard.get("copy", {})
package_block = whiteboard.get("package", {})
selected_items = select_block.get("output", [])
copy_items = copy_block.get("output", [])
copy_by_id = {item.get("product_id"): item for item in copy_items}

preview_date = whiteboard.get("date") or datetime.now().strftime("%Y-%m-%d")
package_dir = package_block.get("output_path", "")
preview_dir = package_dir or os.path.dirname(whiteboard_path)
preview_path = os.path.join(preview_dir, "内容预览.md")
html_preview_path = os.path.join(preview_dir, "内容预览.html")
index_path = os.path.join(preview_dir, "内容包首页.html")
display_package_dir = display_path(package_dir) if package_dir else "未生成"
display_preview_path = display_path(preview_path)
display_html_path = display_path(html_preview_path)
display_index_path = display_path(index_path)
summary_message = read_optional_text(message_path)
package_files = package_block.get("files", [])

index_content = build_package_index(
  preview_date,
  preview_dir,
  display_package_dir,
  display_preview_path,
  display_html_path,
  display_index_path,
  summary_message,
  selected_items,
  package_files,
  select_block,
  copy_block,
  package_block,
)
write_text(index_path, index_content)

markdown_content = build_markdown_preview(
    preview_date,
    display_package_dir,
    display_preview_path,
    selected_items,
    copy_by_id,
    select_block,
    copy_block,
    package_block,
    summary_message,
)
write_text(preview_path, markdown_content)

html_content = build_html_preview(
    preview_date,
    display_package_dir,
    display_preview_path,
    display_html_path,
  display_index_path,
  relative_href(preview_dir, index_path),
    summary_message,
    selected_items,
    copy_by_id,
    select_block,
    copy_block,
    package_block,
)
write_text(html_preview_path, html_content)
print(display_html_path)
PY

status=$?
if [ "$status" -ne 0 ]; then
  log "内容预览生成失败"
  exit "$status"
fi

log "内容预览已生成"
