#!/usr/bin/env bash
# 任务管理脚本 - 用于更新任务状态
# 用法: ./task-manager.sh complete <task_id>
#       ./task-manager.sh list
#       ./task-manager.sh add <category> <title> <detail> <assignee> <deadline>

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "${SCRIPT_DIR}/common.sh"

WHITEBOARD="$WHITEBOARD_FILE"
ensure_whiteboard "$WHITEBOARD"

log() { echo "[$(date '+%H:%M:%S')] $1"; }

# 读取白板
read_wb() {
  python3 -c "import json; wb=json.load(open('$WHITEBOARD')); print(json.dumps(wb, ensure_ascii=False, indent=2))"
}

# 更新任务状态
update_task() {
  local task_id="$1"
  local new_status="$2"
  
  python3 -c "
import json
from datetime import datetime

wb = json.load(open('$WHITEBOARD'))
tasks = wb.get('tasks', {})

# 从 pending 移到 completed
if '$new_status' == 'completed':
    for i, t in enumerate(tasks.get('pending', [])):
        if t.get('id') == '$task_id':
            t['completed_at'] = datetime.now().isoformat()
            tasks['pending'].pop(i)
            tasks.setdefault('completed', []).append(t)
            print(f'✅ 任务完成: {t.get(\"title\")}')
            break
    else:
        print(f'❌ 任务未找到: $task_id')
        exit(1)

elif '$new_status' == 'cancelled':
    for i, t in enumerate(tasks.get('pending', [])):
        if t.get('id') == '$task_id':
            t['cancelled_at'] = datetime.now().isoformat()
            tasks['pending'].pop(i)
            tasks.setdefault('cancelled', []).append(t)
            print(f'🚫 任务取消: {t.get(\"title\")}')
            break
    else:
        print(f'❌ 任务未找到: $task_id')
        exit(1)

json.dump(wb, open('$WHITEBOARD', 'w'), ensure_ascii=False, indent=2)
"
}

# 列出任务
list_tasks() {
  python3 -c "
import json
wb = json.load(open('$WHITEBOARD'))
tasks = wb.get('tasks', {})

print('📋 任务列表')
print('=' * 40)

print('\n⏳ 待执行:')
for t in tasks.get('pending', []):
    prio = '🔴' if t.get('priority') == 'high' else '🟡'
    print(f\"  {prio} [{t.get('category')}] {t.get('title')}\")
    print(f\"     → {t.get('detail')}\")
    print(f\"     → 负责人: {t.get('assignee')} | 截止: {t.get('deadline')}\")

print('\n✅ 已完成:')
for t in tasks.get('completed', [])[-5:]:
    print(f\"  ✓ {t.get('title')} (完成于 {t.get('completed_at', '未知')})\")

print('\n🚫 已取消:')
for t in tasks.get('cancelled', []):
    print(f\"  ✗ {t.get('title')}\")
"
}

# 添加任务
add_task() {
  local category="$1"
  local title="$2"
  local detail="$3"
  local assignee="$4"
  local deadline="$5"
  
  python3 -c "
import json
from datetime import datetime

wb = json.load(open('$WHITEBOARD'))
tasks = wb.setdefault('tasks', {})
pending = tasks.setdefault('pending', [])

task = {
    'id': f\"manual_{datetime.now().strftime('%H%M%S')}\",
    'category': '$category',
    'title': '$title',
    'detail': '$detail',
    'assignee': '$assignee',
    'deadline': '$deadline',
    'priority': 'medium',
    'created_at': datetime.now().isoformat()
}
pending.append(task)

json.dump(wb, open('$WHITEBOARD', 'w'), ensure_ascii=False, indent=2)
print(f'✅ 任务添加: {task[\"title\"]}')
"
}

# 主逻辑
case "$1" in
  complete)
    update_task "$2" "completed"
    ;;
  cancel)
    update_task "$2" "cancelled"
    ;;
  list)
    list_tasks
    ;;
  add)
    add_task "$2" "$3" "$4" "$5" "$6"
    ;;
  *)
    echo "用法:"
    echo "  $0 list                    # 列出所有任务"
    echo "  $0 complete <task_id>      # 完成任务"
    echo "  $0 cancel <task_id>        # 取消任务"
    echo "  $0 add <分类> <标题> <详情> <负责人> <截止时间>"
    ;;
esac
