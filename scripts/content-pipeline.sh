#!/usr/bin/env bash

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "${SCRIPT_DIR}/common.sh"

# 自动加载 .env
set -a
if [ -f "${REPO_ROOT}/.env" ]; then . "${REPO_ROOT}/.env"; fi
set +a

ensure_content_whiteboard "$CONTENT_WHITEBOARD_FILE"
ensure_dir "$TMP_DIR"

log_pipeline() {
  local message="$1"
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$message" >> "$CONTENT_PIPELINE_LOG_FILE"
}

run_step() {
  local label="$1"
  local script_name="$2"

  log_pipeline "${label} 开始"
  if bash "${SCRIPT_DIR}/${script_name}" >> "$CONTENT_PIPELINE_LOG_FILE" 2>&1; then
    log_pipeline "${label} 完成"
  else
    log_pipeline "${label} 失败，但流水线继续"
  fi
}

log_pipeline "内容生产流水线启动"
run_step "Step 1 选品 Agent" "agent-selector.sh"
run_step "Step 2 文案 Agent" "agent-copywriter.sh"
run_step "Step 3 打包 Agent" "agent-packager.sh"
log_pipeline "内容生产流水线结束"