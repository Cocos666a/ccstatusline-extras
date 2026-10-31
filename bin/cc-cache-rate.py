#!/usr/bin/env python3
"""统计 Claude Code 真实缓存命中率，供 ccstatusline custom-command 使用。

口径与 Claude Code 官方 prompt_cache.hit_ratio 一致：
    cache_read / (cache_read + cache_creation + uncached_input)

数据来源：状态栏 stdin JSON 的 prompt_cache.hit_ratio；
缺失或为 null 时回退到解析 transcript_path 的 JSONL 会话记录。

输出：Cache Hit: 46.9%（无数据时为 Cache Hit: n/a）
"""
from __future__ import annotations

import json
import sys


def ratio_from_transcript(path: str) -> "float | None":
    read = uncached = creation = 0
    try:
        handle = open(path, "rb")
    except OSError:
        return None
    with handle:
        for raw in handle:
            if b'"usage"' not in raw:
                continue
            try:
                record = json.loads(raw)
            except ValueError:
                continue
            message = record.get("message")
            usage = message.get("usage") if isinstance(message, dict) else None
            if not isinstance(usage, dict):
                usage = record.get("usage")
            if not isinstance(usage, dict):
                continue
            read += usage.get("cache_read_input_tokens") or 0
            uncached += usage.get("input_tokens") or 0
            creation += usage.get("cache_creation_input_tokens") or 0
    total = read + uncached + creation
    return read / total if total > 0 else None


def main() -> int:
    try:
        data = json.load(sys.stdin)
    except (ValueError, OSError):
        data = None
    if not isinstance(data, dict):
        print("Cache Hit: n/a")
        return 0

    ratio = None
    prompt_cache = data.get("prompt_cache")
    if isinstance(prompt_cache, dict):
        raw_ratio = prompt_cache.get("hit_ratio")
        if isinstance(raw_ratio, (int, float)) and not isinstance(raw_ratio, bool):
            ratio = float(raw_ratio)

    if ratio is None:
        transcript = data.get("transcript_path")
        if isinstance(transcript, str) and transcript:
            ratio = ratio_from_transcript(transcript)

    if ratio is None:
        print("Cache Hit: n/a")
    else:
        print(f"Cache Hit: {ratio * 100:.1f}%")
    return 0


if __name__ == "__main__":
    sys.exit(main())
