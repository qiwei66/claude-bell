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


def extract_text_from_content(content) -> str:
    """从 content 中提取文本（支持字符串和数组格式）"""
    if isinstance(content, str):
        return content

    if isinstance(content, list):
        # content 是数组，提取所有 type="text" 的 text 字段
        texts = []
        for item in content:
            if isinstance(item, dict):
                if item.get('type') == 'text':
                    text = item.get('text', '')
                    if text:
                        texts.append(text)
        return '\n'.join(texts)

    return ''


def detect_status(messages: list) -> str:
    """检测任务状态：success/error/action_needed"""
    # 找到最后一个有内容的用户消息（跳过只有图片的消息）
    last_meaningful_user_idx = -1
    for i in range(len(messages) - 1, -1, -1):
        msg = messages[i]
        if msg.get('type') == 'user':
            # 检查是否有文本内容
            message_obj = msg.get('message', {})
            if isinstance(message_obj, dict):
                content = extract_text_from_content(message_obj.get('content', ''))
                if content and len(content.strip()) > 3:
                    last_meaningful_user_idx = i
                    break

    # 从最后一个有意义的用户消息开始检查
    start_idx = max(0, last_meaningful_user_idx)
    recent_messages = messages[start_idx:]

    for msg in reversed(recent_messages):
        msg_type = msg.get('type', '')

        # 快速检测：isApiErrorMessage 标志
        if msg.get('isApiErrorMessage'):
            return 'error'

        # 快速检测：error 字段
        if msg.get('error'):
            return 'error'

        content = ''

        # 获取消息内容（支持多种格式）
        if msg_type == 'assistant':
            message_obj = msg.get('message', {})
            if isinstance(message_obj, dict):
                content = extract_text_from_content(message_obj.get('content', ''))
            if not content:
                content = extract_text_from_content(msg.get('content', ''))
        elif msg_type == 'tool_result':
            content = str(msg.get('tool_output', '') or msg.get('content', ''))
        elif msg_type == 'user':
            message_obj = msg.get('message', {})
            if isinstance(message_obj, dict):
                content = extract_text_from_content(message_obj.get('content', ''))
            if not content:
                content = extract_text_from_content(msg.get('content', ''))

        if not content:
            continue

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
    # 跳过的控制命令（小写匹配）
    skip_commands = {
        'ultrawork', 'continue', 'ok', 'yes', 'no', 'y', 'n',
        '继续', '好的', '是', '好', '可以', '确认', '嗯', '行',
        'go', 'next', 'done', 'thanks', '谢谢', '感谢'
    }

    # 从后往前找最后一个有意义的用户消息
    for msg in reversed(messages):
        if msg.get('type') == 'user':
            # 尝试从 message.content 提取（新格式）
            message_obj = msg.get('message', {})
            if isinstance(message_obj, dict):
                content = extract_text_from_content(message_obj.get('content', ''))
            else:
                content = ''

            # 如果没找到，尝试直接从 content 提取（旧格式）
            if not content:
                content = extract_text_from_content(msg.get('content', ''))

            if not content:
                continue

            content_stripped = content.strip()
            content_lower = content_stripped.lower()

            # 跳过控制命令
            if content_lower in skip_commands:
                continue

            # 跳过太短的内容
            if len(content_stripped) < 5:
                continue

            # 跳过只有符号的内容
            if content_stripped in ['...', '。。。', '???', '！！！']:
                continue

            # 提取第一行作为摘要（通常是主要任务）
            first_line = content_stripped.split('\n')[0].strip()
            if len(first_line) > 5:
                return first_line[:80] + ('...' if len(first_line) > 80 else '')

            # 如果第一行太短，用完整内容
            return content_stripped[:80] + ('...' if len(content_stripped) > 80 else '')

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
    recent_messages = messages[-10:] if len(messages) > 10 else messages

    for msg in reversed(recent_messages):
        content = ''
        msg_type = msg.get('type', '')

        if msg_type == 'assistant':
            message_obj = msg.get('message', {})
            if isinstance(message_obj, dict):
                content = extract_text_from_content(message_obj.get('content', ''))
            if not content:
                content = extract_text_from_content(msg.get('content', ''))
        elif msg_type == 'tool_result':
            content = str(msg.get('tool_output', '') or msg.get('content', ''))

        if not content:
            continue

        # 查找 API Error 等错误信息
        match = re.search(r'(API Error[^\n]*|Error:[^\n]*|403[^\n]*|failed[^\n]*)', content, re.IGNORECASE)
        if match:
            return match.group(1)[:80]

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
        short_query = query[:60] + ('...' if len(query) > 60 else '') if query else ''
        return {
            'status': 'error',
            'query': short_query or '任务执行出错',
            'stats': error_msg or ''
        }

    if status == 'action_needed':
        short_query = query[:60] + ('...' if len(query) > 60 else '') if query else '需要用户操作'
        return {
            'status': 'action_needed',
            'query': short_query,
            'stats': ''
        }

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

    # 计算时长
    duration = calculate_duration(messages)

    # 构建统计信息
    if duration:
        stats_parts.append(f'耗时{duration}')

    stats = ' · '.join(stats_parts) if stats_parts else ''

    # 用户查询（截断到60字符用于通知）
    short_query = query[:60] + ('...' if len(query) > 60 else '') if query else '任务完成'

    return {
        'status': 'success',
        'query': short_query,
        'stats': stats
    }


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
        # 输出格式: status|query|stats
        print(f"{result['status']}|{result['query']}|{result.get('stats', '')}")
    else:
        print('success|任务完成|')


if __name__ == '__main__':
    main()
