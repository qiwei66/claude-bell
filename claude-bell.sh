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

# --- 日志函数 ---
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

# --- 读取 stdin (hook 输入) ---
INPUT=$(cat)

# --- 解析 JSON 输入 ---
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
EVENT_NAME=$(echo "$INPUT" | jq -r '.hook_event_name // "Stop"')

# --- 提取项目名 ---
if [[ -n "$CWD" ]]; then
    PROJECT_NAME=$(basename "$CWD" 2>/dev/null || echo "Claude")
else
    PROJECT_NAME="Claude"
fi

# --- 提取任务摘要 ---
extract_summary() {
    local transcript="$1"

    if [[ ! -f "$transcript" ]]; then
        echo "任务完成"
        return
    fi

    # 尝试使用 Python 摘要提取器
    if [[ -x "${SCRIPT_DIR}/extract-summary.py" ]]; then
        local summary
        summary=$("${SCRIPT_DIR}/extract-summary.py" "$transcript" 2>/dev/null) || true
        if [[ -n "$summary" ]]; then
            echo "$summary"
            return
        fi
    fi

    # 降级：简单提取
    local user_query
    user_query=$(grep -m1 '"type":"human"' "$transcript" 2>/dev/null | \
        jq -r '.message.content[0].text // empty' 2>/dev/null | \
        head -c 80) || true

    if [[ -n "$user_query" ]]; then
        echo "${user_query}..."
    else
        # 统计工具调用
        local tool_count
        tool_count=$(grep -c '"type":"tool_use"' "$transcript" 2>/dev/null || echo "0")
        echo "任务完成 (工具调用: ${tool_count} 次)"
    fi
}

# --- 获取摘要 ---
SUMMARY=$(extract_summary "$TRANSCRIPT_PATH")

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

    local title="🔔 Claude Bell"
    local subtitle="$PROJECT_NAME"
    local body="$SUMMARY"

    # 清理特殊字符
    body=$(echo "$body" | tr '\n' ' ' | sed 's/"/\\"/g')
    subtitle=$(echo "$subtitle" | sed 's/"/\\"/g')

    # 优先使用 terminal-notifier (点击后不会打开脚本编辑器)
    if command -v terminal-notifier &>/dev/null; then
        terminal-notifier \
            -title "$title" \
            -subtitle "$subtitle" \
            -message "$body" \
            -sound "default" \
            -group "claude-bell" \
            -ignoreDnD \
            2>/dev/null || true
        log "Mac notification sent (terminal-notifier): $subtitle - $body"
    else
        # 降级使用 osascript
        osascript -e "display notification \"$body\" with title \"$title\" subtitle \"$subtitle\" sound name \"$MAC_SOUND\"" 2>/dev/null || true
        log "Mac notification sent (osascript): $subtitle - $body"
    fi
}

# --- 发送 Bark 推送 (iOS) ---
send_bark_notification() {
    if [[ -z "$BARK_KEY" ]]; then
        log "Bark key not configured, skipping iOS notification"
        return
    fi

    local title="🔔 Claude Bell"
    local body="${PROJECT_NAME}: ${SUMMARY}"

    # 发送请求 (后台异步)
    curl -s -X POST "${BARK_SERVER}/${BARK_KEY}" \
        -H "Content-Type: application/json; charset=utf-8" \
        -d "$(jq -n \
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
            }')" &>/dev/null &

    log "Bark notification sent: $body"
}

# --- 主函数 ---
main() {
    log "=== Claude Bell triggered ==="
    log "Event: $EVENT_NAME | Project: $PROJECT_NAME | Session: $SESSION_ID"

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
