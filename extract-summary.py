#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Claude Bell - 智能任务摘要提取器

从 Claude Code transcript 文件中提取任务摘要
"""

import json
import sys
import re
from pathlib import Path
from datetime import datetime
from collections import Counter


# 错误关键词
ERROR_PATTERNS = [
    r'API Error',
    r'Error:',
    r'403',
    r'401',
    r'500',
    r'failed',
    r'失败',
    r'forbidden',
    r'unauthorized',
    r'timeout',
    r'connection refused',
    r'/login',
    r'permission denied',
]

# 需要用户操作的关键词
ACTION_PATTERNS = [
    r'please run',
    r'请运行',
    r'需要.*确认',
    r'waiting for',
    r'approve',
]


def detect_status(messages: list) -> str:
    """检测任务状态：success/error/action_needed"""
    # 检查最后几条消息
    recent_messages = messages[-10:] if len(messages) > 10 else messages

    for msg in reversed(recent_messages):
        content = ''

        # 获取消息内容
        if msg.get('type') == 'assistant':
            content = str(msg.get('content', ''))
        elif msg.get('type') == 'tool_result':
            content = str(msg.get('tool_output', ''))
        elif msg.get('type') == 'user':
            content = str(msg.get('content', ''))

        content_lower = content.lower()

        # 检查错误
        for pattern in ERROR_PATTERNS:
            if re.search(pattern, content, re.IGNORECASE):
                return 'error'

        # 检查需要操作
        for pattern in ACTION_PATTERNS:
            if re.search(pattern, content, re.IGNORECASE):
                return 'action_needed'

    return 'success'


def parse_transcript(transcript_path: str) -> dict:
    """解析 transcript JSONL 文件"""
    messages = []
    tools_used = Counter()
    files_modified = set()
    bash_commands = []

    try:
        with open(transcript_path, 'r', encoding='utf-8') as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    msg = json.loads(line)
                    messages.append(msg)

                    msg_type = msg.get('type', '')

                    # 统计工具使用
                    if msg_type == 'tool_use':
                        tool_name = msg.get('tool_name', 'unknown')
                        tools_used[tool_name] += 1

                        tool_input = msg.get('tool_input', {})
                        if isinstance(tool_input, dict):
                            # 提取修改的文件
                            file_path = tool_input.get('file_path') or tool_input.get('path')
                            if file_path and tool_name in ('Edit', 'Write'):
                                files_modified.add(Path(file_path).name)

                            # 提取 Bash 命令
                            if tool_name == 'Bash':
                                cmd = tool_input.get('command', '')
                                if cmd:
                                    bash_commands.append(cmd[:50])

                except json.JSONDecodeError:
                    continue
    except Exception as e:
        return {'error': str(e)}

    return {
        'messages': messages,
        'tools_used': dict(tools_used),
        'files_modified': list(files_modified)[:5],
        'bash_commands': bash_commands[:3],
        'total_messages': len(messages),
        'status': detect_status(messages)
    }


def extract_user_query(messages: list) -> str:
    """提取最后一个有意义的用户需求"""
    # 跳过的控制命令
    skip_commands = {'ultrawork', 'continue', 'ok', 'yes', 'no', 'y', 'n', '继续', '好的', '是', '好', '可以', '确认'}

    # 从后往前找最后一个有意义的用户消息
    for msg in reversed(messages):
        if msg.get('type') == 'user':
            content = msg.get('content', '')
            if isinstance(content, str):
                content_stripped = content.strip()
                content_lower = content_stripped.lower()
                # 跳过控制命令
                if content_lower in skip_commands:
                    continue
                # 跳过太短的内容
                if len(content_stripped) < 3:
                    continue
                # 返回截断的内容
                return content_stripped[:100] + ('...' if len(content_stripped) > 100 else '')

    return ''


def calculate_duration(messages: list) -> str:
    """计算最近一轮任务的时长"""
    if len(messages) < 2:
        return ''

    try:
        # 找到最后一个用户消息的位置
        last_user_idx = -1
        for i in range(len(messages) - 1, -1, -1):
            if messages[i].get('type') == 'user':
                last_user_idx = i
                break

        if last_user_idx < 0:
            return ''

        # 计算从最后一个用户消息到最后一条消息的时长
        first_ts = messages[last_user_idx].get('timestamp', '')
        last_ts = messages[-1].get('timestamp', '')

        if first_ts and last_ts:
            # 解析 ISO 格式时间
            start = datetime.fromisoformat(first_ts.replace('Z', '+00:00'))
            end = datetime.fromisoformat(last_ts.replace('Z', '+00:00'))
            duration = end - start

            total_seconds = int(duration.total_seconds())
            if total_seconds < 0 or total_seconds > 3600:  # 超过1小时可能是数据问题
                return ''

            if total_seconds < 5:  # 太短不显示
                return ''

            minutes = total_seconds // 60
            seconds = total_seconds % 60

            if minutes > 0:
                return f'{minutes}分{seconds}秒'
            else:
                return f'{seconds}秒'
    except Exception:
        pass

    return ''


def get_error_message(messages: list) -> str:
    """提取错误信息"""
    recent_messages = messages[-5:] if len(messages) > 5 else messages

    for msg in reversed(recent_messages):
        content = ''
        if msg.get('type') == 'assistant':
            content = str(msg.get('content', ''))
        elif msg.get('type') == 'tool_result':
            content = str(msg.get('tool_output', ''))

        # 查找 API Error 等错误信息
        match = re.search(r'(API Error[^\n]*|Error:[^\n]*|403[^\n]*|failed[^\n]*)', content, re.IGNORECASE)
        if match:
            return match.group(1)[:60]

    return ''


def generate_summary(transcript_path: str) -> dict:
    """生成任务摘要，返回 {status, summary}"""
    data = parse_transcript(transcript_path)

    if 'error' in data:
        return {'status': 'success', 'summary': '任务完成'}

    messages = data['messages']
    tools = data['tools_used']
    status = data.get('status', 'success')

    # 提取用户查询
    query = extract_user_query(messages)

    # 如果是错误状态，提取错误信息
    if status == 'error':
        error_msg = get_error_message(messages)
        if error_msg:
            return {'status': 'error', 'summary': error_msg}
        return {'status': 'error', 'summary': '任务执行出错'}

    if status == 'action_needed':
        return {'status': 'action_needed', 'summary': query or '需要用户操作'}

    # 生成工具统计
    stats_parts = []

    edit_count = tools.get('Edit', 0) + tools.get('Write', 0)
    if edit_count > 0:
        stats_parts.append(f"改{edit_count}文件")

    bash_count = tools.get('Bash', 0)
    if bash_count > 0:
        stats_parts.append(f"执行{bash_count}命令")

    read_count = tools.get('Read', 0)
    if read_count > 0:
        stats_parts.append(f"读{read_count}文件")

    # 计算时长（只有成功时才显示）
    duration = calculate_duration(messages)

    # 构建最终摘要
    summary_parts = []

    # 用户查询（截断到60字符用于通知）
    if query:
        short_query = query[:60] + ('...' if len(query) > 60 else '')
        summary_parts.append(short_query)

    # 统计信息
    if stats_parts:
        summary_parts.append(' | '.join(stats_parts))

    # 时长（仅当有效时添加）
    if duration:
        summary_parts.append(f'耗时{duration}')

    if summary_parts:
        return {'status': 'success', 'summary': ' · '.join(summary_parts)}
    else:
        return {'status': 'success', 'summary': '任务完成'}


def main():
    """主函数"""
    if len(sys.argv) < 2:
        # 从 stdin 读取（hook 模式）
        try:
            hook_input = json.loads(sys.stdin.read())
            transcript_path = hook_input.get('transcript_path', '')
        except Exception:
            transcript_path = ''
    else:
        # 命令行参数模式
        transcript_path = sys.argv[1]

    if transcript_path and Path(transcript_path).exists():
        result = generate_summary(transcript_path)
        # 输出格式: status|summary
        print(f"{result['status']}|{result['summary']}")
    else:
        print('success|任务完成')


if __name__ == '__main__':
    main()
