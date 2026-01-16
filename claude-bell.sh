#!/bin/bash
# =============================================================================
# Claude Bell 🔔 - Task Completion Notifier
# https://github.com/qiwei66/claude-bell
#
# 当 Claude Code 任务完成时，发送通知到 Mac 和 iOS (Bark)
# =============================================================================

set -euo pipefail

# --- 配置路径 ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.json"
LOG_FILE="${SCRIPT_DIR}/notify.log"
DEBUG_FILE="${SCRIPT_DIR}/debug.log"

# --- 日志函数 ---
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

debug() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$DEBUG_FILE"
}

# --- 读取 stdin (hook 输入) ---
INPUT=$(cat)

# 记录原始输入用于调试
debug "=== Raw Input ==="
debug "$INPUT"

# --- 解析 JSON 输入 ---
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
EVENT_NAME=$(echo "$INPUT" | jq -r '.hook_event_name // "Stop"')

debug "Parsed: session=$SESSION_ID, transcript=$TRANSCRIPT_PATH, cwd=$CWD, event=$EVENT_NAME"

# --- 提取项目名 ---
if [[ -n "$CWD" ]]; then
    PROJECT_NAME=$(basename "$CWD" 2>/dev/null || echo "Claude")
else
    PROJECT_NAME="Claude"
fi

# --- 查找 transcript 文件 ---
find_transcript() {
    local session="$1"
    local provided_path="$2"

    # 如果提供了有效路径，直接使用
    if [[ -n "$provided_path" && -f "$provided_path" ]]; then
        echo "$provided_path"
        return
    fi

    # 尝试在 ~/.claude/transcripts 中查找
    local transcripts_dir="$HOME/.claude/transcripts"
    if [[ -d "$transcripts_dir" ]]; then
        # 查找最新的 transcript 文件
        local latest
        latest=$(ls -t "$transcripts_dir"/*.jsonl 2>/dev/null | head -1)
        if [[ -n "$latest" && -f "$latest" ]]; then
            echo "$latest"
            return
        fi
    fi

    echo ""
}

# --- 提取任务摘要和状态 ---
extract_summary_and_status() {
    local transcript="$1"

    if [[ -z "$transcript" || ! -f "$transcript" ]]; then
        debug "No transcript file found"
        echo "success|任务已完成"
        return
    fi

    debug "Extracting summary from: $transcript"

    # 使用 Python 摘要提取器（返回格式: status|summary）
    if [[ -x "${SCRIPT_DIR}/extract-summary.py" ]]; then
        local result
        result=$("${SCRIPT_DIR}/extract-summary.py" "$transcript" 2>/dev/null) || true
        if [[ -n "$result" ]]; then
            debug "Python extractor returned: $result"
            echo "$result"
            return
        fi
    fi

    # 降级：简单返回
    echo "success|任务完成"
}

# --- 根据状态确定通知类型（不带 emoji，emoji 在标题中显示）---
get_notification_type() {
    local status="$1"

    case "$status" in
        "error")
            echo "任务失败"
            ;;
        "action_needed")
            echo "需要操作"
            ;;
        "success")
            echo "任务完成"
            ;;
        *)
            echo "Claude Bell"
            ;;
    esac
}

# --- 获取摘要和状态 ---
ACTUAL_TRANSCRIPT=$(find_transcript "$SESSION_ID" "$TRANSCRIPT_PATH")
debug "Using transcript: $ACTUAL_TRANSCRIPT"

SUMMARY_RESULT=$(extract_summary_and_status "$ACTUAL_TRANSCRIPT")
debug "Summary result: $SUMMARY_RESULT"

# 解析输出（格式: status|query|stats）
TASK_STATUS=$(echo "$SUMMARY_RESULT" | cut -d'|' -f1)
TASK_QUERY=$(echo "$SUMMARY_RESULT" | cut -d'|' -f2)
TASK_STATS=$(echo "$SUMMARY_RESULT" | cut -d'|' -f3)

debug "Status: $TASK_STATUS, Query: $TASK_QUERY, Stats: $TASK_STATS"

# 确保 TASK_QUERY 不为空
if [[ -z "$TASK_QUERY" ]]; then
    TASK_QUERY="任务已完成"
fi

NOTIFICATION_TYPE=$(get_notification_type "$TASK_STATUS")

# --- 读取配置 ---
if [[ -f "$CONFIG_FILE" ]]; then
    BARK_KEY=$(jq -r '.bark_key // empty' "$CONFIG_FILE")
    BARK_SERVER=$(jq -r '.bark_server // "https://api.day.app"' "$CONFIG_FILE")
    BARK_SOUND=$(jq -r '.bark_sound // "minuet"' "$CONFIG_FILE")
    BARK_GROUP=$(jq -r '.bark_group // "claude"' "$CONFIG_FILE")
    MAC_NOTIFICATION=$(jq -r '.mac_notification // true' "$CONFIG_FILE")
    MAC_SOUND=$(jq -r '.mac_sound // "Glass"' "$CONFIG_FILE")
else
    BARK_KEY=""
    BARK_SERVER="https://api.day.app"
    BARK_SOUND="minuet"
    BARK_GROUP="claude"
    MAC_NOTIFICATION="true"
    MAC_SOUND="Glass"
fi

# --- 发送 Mac 系统通知 ---
send_mac_notification() {
    if [[ "$MAC_NOTIFICATION" != "true" ]]; then
        return
    fi

    # 格式仿照 Claude 官方通知风格:
    # 标题: 项目名
    # 副标题: 任务描述（用户原始需求）
    # 正文: 状态 + 统计信息
    local title="$PROJECT_NAME"
    local subtitle="$TASK_QUERY"
    local body="$NOTIFICATION_TYPE"

    # 如果有统计信息，添加到正文
    if [[ -n "$TASK_STATS" ]]; then
        body="$body · $TASK_STATS"
    fi

    # 清理特殊字符
    subtitle=$(echo "$subtitle" | tr '\n' ' ' | sed 's/"/\\"/g')
    body=$(echo "$body" | tr '\n' ' ' | sed 's/"/\\"/g')

    # 优先使用 terminal-notifier
    if command -v terminal-notifier &>/dev/null; then
        terminal-notifier \
            -title "$title" \
            -subtitle "$subtitle" \
            -message "$body" \
            -sound "default" \
            -group "claude-bell-${PROJECT_NAME}" \
            -ignoreDnD \
            2>/dev/null || true
        log "Mac notification sent (terminal-notifier): $title | $subtitle | $body"
    else
        osascript -e "display notification \"$body\" with title \"$title\" subtitle \"$subtitle\" sound name \"$MAC_SOUND\"" 2>/dev/null || true
        log "Mac notification sent (osascript): $title | $subtitle | $body"
    fi
}

# --- 发送 Bark 推送 (iOS) ---
send_bark_notification() {
    if [[ -z "$BARK_KEY" ]]; then
        log "Bark key not configured, skipping iOS notification"
        return
    fi

    # 格式仿照 Claude 官方通知风格:
    # 标题: 项目名
    # 正文: 任务描述 + 状态/统计
    local title="$PROJECT_NAME"
    local body="$TASK_QUERY"

    # 添加状态和统计信息
    if [[ -n "$TASK_STATS" ]]; then
        body="$body"$'\n'"$NOTIFICATION_TYPE · $TASK_STATS"
    else
        body="$body"$'\n'"$NOTIFICATION_TYPE"
    fi

    debug "Sending Bark: title=$title, body=$body"

    # 构建 JSON payload
    local payload
    payload=$(jq -n \
        --arg title "$title" \
        --arg body "$body" \
        --arg sound "$BARK_SOUND" \
        --arg group "$BARK_GROUP" \
        '{
            title: $title,
            body: $body,
            sound: $sound,
            group: $group,
            level: "timeSensitive",
            badge: 1,
            icon: "https://claude.ai/favicon.ico"
        }')

    debug "Bark payload: $payload"

    # 发送请求
    curl -s -X POST "${BARK_SERVER}/${BARK_KEY}" \
        -H "Content-Type: application/json; charset=utf-8" \
        -d "$payload" &>/dev/null &

    log "Bark notification sent: $title | $body"
}

# --- 主函数 ---
main() {
    log "=== Claude Bell triggered ==="
    log "Event: $EVENT_NAME | Project: $PROJECT_NAME | Session: $SESSION_ID"
    log "Query: $TASK_QUERY | Stats: $TASK_STATS | Status: $TASK_STATUS"

    # 发送 Mac 通知
    send_mac_notification

    # 发送 Bark 推送
    send_bark_notification

    log "=== Notifications sent ==="
}

# 运行
main

# 成功退出
exit 0
