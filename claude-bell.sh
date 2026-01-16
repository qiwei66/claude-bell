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

# --- 提取任务摘要 ---
extract_summary() {
    local transcript="$1"

    if [[ -z "$transcript" || ! -f "$transcript" ]]; then
        debug "No transcript file found"
        echo "任务已完成"
        return
    fi

    debug "Extracting summary from: $transcript"

    # 尝试使用 Python 摘要提取器
    if [[ -x "${SCRIPT_DIR}/extract-summary.py" ]]; then
        local summary
        summary=$("${SCRIPT_DIR}/extract-summary.py" "$transcript" 2>/dev/null) || true
        if [[ -n "$summary" && "$summary" != "任务完成" ]]; then
            debug "Python extractor returned: $summary"
            echo "$summary"
            return
        fi
    fi

    # 降级：从 transcript 提取最后的用户消息
    local user_query
    user_query=$(grep '"type":"user"' "$transcript" 2>/dev/null | tail -1 | jq -r '.content // empty' 2>/dev/null | head -c 80) || true

    if [[ -n "$user_query" ]]; then
        debug "Fallback extraction: $user_query"
        echo "${user_query}..."
    else
        # 统计工具调用
        local tool_count
        tool_count=$(grep -c '"type":"tool_use"' "$transcript" 2>/dev/null || echo "0")
        echo "任务完成 (工具调用: ${tool_count} 次)"
    fi
}

# --- 确定通知类型和图标 ---
get_notification_type() {
    local event="$1"
    local summary="$2"

    case "$event" in
        "Stop")
            echo "✅ 任务完成"
            ;;
        "Notification")
            if echo "$summary" | grep -qi "permission\|确认\|approve"; then
                echo "⚠️ 需要确认"
            elif echo "$summary" | grep -qi "error\|失败\|fail"; then
                echo "❌ 任务失败"
            else
                echo "💬 通知"
            fi
            ;;
        *)
            echo "🔔 Claude Bell"
            ;;
    esac
}

# --- 获取摘要 ---
ACTUAL_TRANSCRIPT=$(find_transcript "$SESSION_ID" "$TRANSCRIPT_PATH")
debug "Using transcript: $ACTUAL_TRANSCRIPT"

SUMMARY=$(extract_summary "$ACTUAL_TRANSCRIPT")
debug "Summary: $SUMMARY"

# 确保 SUMMARY 不为空
if [[ -z "$SUMMARY" ]]; then
    SUMMARY="任务已完成"
fi

NOTIFICATION_TYPE=$(get_notification_type "$EVENT_NAME" "$SUMMARY")

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

    local title="$NOTIFICATION_TYPE"
    local subtitle="$PROJECT_NAME"
    local body="$SUMMARY"

    # 清理特殊字符
    body=$(echo "$body" | tr '\n' ' ' | sed 's/"/\\"/g')
    subtitle=$(echo "$subtitle" | sed 's/"/\\"/g')

    # 优先使用 terminal-notifier
    if command -v terminal-notifier &>/dev/null; then
        terminal-notifier \
            -title "$title" \
            -subtitle "$subtitle" \
            -message "$body" \
            -sound "default" \
            -group "claude-bell" \
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

    local title="$NOTIFICATION_TYPE"
    local body="${PROJECT_NAME}: ${SUMMARY}"

    # 确保 body 不为空
    if [[ -z "$body" || "$body" == ": " ]]; then
        body="$PROJECT_NAME: 任务已完成"
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
    log "Summary: $SUMMARY"

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
