#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Claude Bell - 智能任务摘要提取器

从 Claude Code transcript 文件中提取任务摘要
"""

import json
import sys
from pathlib import Path
from datetime import datetime
from collections import Counter


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
        'total_messages': len(messages)
    }


def extract_user_query(messages: list) -> str:
    """提取用户的原始需求"""
    # 跳过的控制命令
    skip_commands = {'ultrawork', 'continue', 'ok', 'yes', 'no', 'y', 'n', '继续', '好的', '是'}

    for msg in messages:
        if msg.get('type') == 'user':
            content = msg.get('content', '')
            if isinstance(content, str):
                content_lower = content.strip().lower()
                # 跳过控制命令
                if content_lower in skip_commands:
                    continue
                # 跳过太短的内容
                if len(content.strip()) < 5:
                    continue
                # 返回截断的内容
                return content[:100] + ('...' if len(content) > 100 else '')

    return '任务已完成'


def calculate_duration(messages: list) -> str:
    """计算会话时长"""
    if len(messages) < 2:
        return ''

    try:
        first_ts = messages[0].get('timestamp', '')
        last_ts = messages[-1].get('timestamp', '')

        if first_ts and last_ts:
            # 解析 ISO 格式时间
            start = datetime.fromisoformat(first_ts.replace('Z', '+00:00'))
            end = datetime.fromisoformat(last_ts.replace('Z', '+00:00'))
            duration = end - start

            total_seconds = int(duration.total_seconds())
            if total_seconds < 0:
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


def generate_summary(transcript_path: str) -> str:
    """生成任务摘要"""
    data = parse_transcript(transcript_path)

    if 'error' in data:
        return '任务完成'

    messages = data['messages']
    tools = data['tools_used']
    files = data['files_modified']

    # 提取用户查询
    query = extract_user_query(messages)

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

    # 构建最终摘要
    summary_parts = []

    # 用户查询（截断到60字符用于通知）
    if query and query != '任务已完成':
        short_query = query[:60] + ('...' if len(query) > 60 else '')
        summary_parts.append(short_query)

    # 统计信息
    if stats_parts:
        summary_parts.append(' | '.join(stats_parts))

    # 时长
    if duration:
        summary_parts.append(f'耗时{duration}')

    if summary_parts:
        return ' · '.join(summary_parts)
    else:
        return '任务完成'


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
        summary = generate_summary(transcript_path)
        print(summary)
    else:
        print('任务完成')


if __name__ == '__main__':
    main()
