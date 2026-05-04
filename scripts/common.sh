#!/usr/bin/env bash

COMMON_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(CDPATH= cd -- "${COMMON_DIR}/.." && pwd)"

ENV_FILE="${ENV_FILE:-${REPO_ROOT}/.env}"
WORKSPACE_DIR="${WORKSPACE_DIR:-${REPO_ROOT}/workspace}"
WHITEBOARD_FILE="${WHITEBOARD_FILE:-${WORKSPACE_DIR}/shared_whiteboard.json}"
WHITEBOARD_TEMPLATE="${WHITEBOARD_TEMPLATE:-${REPO_ROOT}/workspace/shared_whiteboard.json}"
CONTENT_WHITEBOARD_FILE="${CONTENT_WHITEBOARD_FILE:-${WORKSPACE_DIR}/content_whiteboard.json}"
CONTENT_WHITEBOARD_TEMPLATE="${CONTENT_WHITEBOARD_TEMPLATE:-${REPO_ROOT}/workspace/content_whiteboard.json}"
TMP_DIR="${TMP_DIR:-/tmp}"
BRIEFING_MSG_FILE="${BRIEFING_MSG_FILE:-${TMP_DIR}/daily_briefing_msg.txt}"
BRIEFING_TARGET_FILE="${BRIEFING_TARGET_FILE:-${TMP_DIR}/daily_briefing_target.txt}"
BRIEFING_PENDING_FILE="${BRIEFING_PENDING_FILE:-${TMP_DIR}/daily_briefing_pending.txt}"
DAILY_CONTENT_MSG_FILE="${DAILY_CONTENT_MSG_FILE:-${TMP_DIR}/daily_content_msg.txt}"
DAILY_CONTENT_TARGET_FILE="${DAILY_CONTENT_TARGET_FILE:-${TMP_DIR}/daily_content_target.txt}"
DAILY_CONTENT_PENDING_FILE="${DAILY_CONTENT_PENDING_FILE:-${TMP_DIR}/daily_content_pending.txt}"
CONTENT_PACKAGE_ROOT="${CONTENT_PACKAGE_ROOT:-${TMP_DIR}}"
CONTENT_PIPELINE_LOG_FILE="${CONTENT_PIPELINE_LOG_FILE:-${TMP_DIR}/content_pipeline.log}"

if [ -f "$ENV_FILE" ]; then
  set -a
  # shellcheck disable=SC1090
  . "$ENV_FILE"
  set +a
fi

to_host_path() {
  local path_value="$1"

  if command -v cygpath >/dev/null 2>&1; then
    cygpath -m "$path_value"
  else
    printf '%s\n' "$path_value"
  fi
}

normalize_runtime_paths() {
  if ! command -v cygpath >/dev/null 2>&1; then
    return 0
  fi

  REPO_ROOT="$(to_host_path "$REPO_ROOT")"
  ENV_FILE="$(to_host_path "$ENV_FILE")"
  WORKSPACE_DIR="$(to_host_path "$WORKSPACE_DIR")"
  WHITEBOARD_FILE="$(to_host_path "$WHITEBOARD_FILE")"
  WHITEBOARD_TEMPLATE="$(to_host_path "$WHITEBOARD_TEMPLATE")"
  CONTENT_WHITEBOARD_FILE="$(to_host_path "$CONTENT_WHITEBOARD_FILE")"
  CONTENT_WHITEBOARD_TEMPLATE="$(to_host_path "$CONTENT_WHITEBOARD_TEMPLATE")"
  TMP_DIR="$(to_host_path "$TMP_DIR")"
  BRIEFING_MSG_FILE="$(to_host_path "$BRIEFING_MSG_FILE")"
  BRIEFING_TARGET_FILE="$(to_host_path "$BRIEFING_TARGET_FILE")"
  BRIEFING_PENDING_FILE="$(to_host_path "$BRIEFING_PENDING_FILE")"
  DAILY_CONTENT_MSG_FILE="$(to_host_path "$DAILY_CONTENT_MSG_FILE")"
  DAILY_CONTENT_TARGET_FILE="$(to_host_path "$DAILY_CONTENT_TARGET_FILE")"
  DAILY_CONTENT_PENDING_FILE="$(to_host_path "$DAILY_CONTENT_PENDING_FILE")"
  CONTENT_PACKAGE_ROOT="$(to_host_path "$CONTENT_PACKAGE_ROOT")"
  CONTENT_PIPELINE_LOG_FILE="$(to_host_path "$CONTENT_PIPELINE_LOG_FILE")"
}

normalize_runtime_paths

has_real_config_value() {
  local raw_value="$1"
  local lowered

  if [ -z "$raw_value" ]; then
    return 1
  fi

  lowered="$(printf '%s' "$raw_value" | tr '[:upper:]' '[:lower:]')"

  case "$lowered" in
    *replace-with-*|*your-cloudbase-domain*|*'<gw_token>'*|*'<wecom_chat_id>'*|*'<deepseek api key>'*)
      return 1
      ;;
  esac

  return 0
}

ensure_dir() {
  mkdir -p "$1"
}

ensure_parent_dir() {
  ensure_dir "$(dirname "$1")"
}

ensure_whiteboard() {
  local target="${1:-$WHITEBOARD_FILE}"

  if [ -f "$target" ]; then
    return 0
  fi

  ensure_parent_dir "$target"

  if [ -f "$WHITEBOARD_TEMPLATE" ] && [ "$target" != "$WHITEBOARD_TEMPLATE" ]; then
    cp "$WHITEBOARD_TEMPLATE" "$target"
    return 0
  fi

  cat > "$target" <<'EOF'
{
  "schema_version": "1.0",
  "last_updated": "",
  "date": "",
  "sales": {
    "yesterday": {
      "amount_cent": 0,
      "order_count": 0,
      "avg_price_cent": 0,
      "refund_cent": 0
    },
    "today_target_cent": 300000,
    "today_current_cent": 0,
    "trend": "stable"
  },
  "inventory": {
    "total_stock": 0,
    "sku_count": 0,
    "out_of_stock_count": 0,
    "low_stock_items": [],
    "slow_moving_items": [],
    "overstock_items": []
  },
  "customers": {
    "new_members_today": 0,
    "new_members_pending_followup": [],
    "inactive_customers": [],
    "vip_customers": [],
    "birthday_today": []
  },
  "tasks": {
    "pending": [],
    "in_progress": [],
    "completed": [],
    "cancelled": []
  },
  "alerts": {
    "high_priority": [],
    "medium_priority": [],
    "low_priority": []
  }
}
EOF
}

ensure_content_whiteboard() {
  local target="${1:-$CONTENT_WHITEBOARD_FILE}"

  if [ -f "$target" ]; then
    return 0
  fi

  ensure_parent_dir "$target"

  if [ -f "$CONTENT_WHITEBOARD_TEMPLATE" ] && [ "$target" != "$CONTENT_WHITEBOARD_TEMPLATE" ]; then
    cp "$CONTENT_WHITEBOARD_TEMPLATE" "$target"
    return 0
  fi

  cat > "$target" <<'EOF'
{
  "version": "1.0",
  "date": "",
  "last_updated": "",
  "select": {
    "status": "pending",
    "output": []
  },
  "copy": {
    "status": "pending",
    "output": []
  },
  "package": {
    "status": "pending",
    "output_path": "",
    "files": []
  }
}
EOF
}

require_env() {
  local missing=()
  local name

  for name in "$@"; do
    if [ -z "${!name:-}" ]; then
      missing+=("$name")
    fi
  done

  if [ "${#missing[@]}" -gt 0 ]; then
    echo "Missing required environment variables: ${missing[*]}" >&2
    exit 1
  fi
}

write_pending_message() {
  local message="$1"
  local chat_id="$2"

  ensure_dir "$TMP_DIR"
  printf '%s\n' "$message" > "$BRIEFING_MSG_FILE"

  if has_real_config_value "$chat_id"; then
    printf '%s\n' "$chat_id" > "$BRIEFING_TARGET_FILE"
  else
    rm -f "$BRIEFING_TARGET_FILE"
  fi

  date +%s > "$BRIEFING_PENDING_FILE"
}

write_content_pending_message() {
  local message="$1"
  local chat_id="${2:-}"

  ensure_dir "$TMP_DIR"
  printf '%s\n' "$message" > "$DAILY_CONTENT_MSG_FILE"

  if has_real_config_value "$chat_id"; then
    printf '%s\n' "$chat_id" > "$DAILY_CONTENT_TARGET_FILE"
  else
    rm -f "$DAILY_CONTENT_TARGET_FILE"
  fi

  date +%s > "$DAILY_CONTENT_PENDING_FILE"
}