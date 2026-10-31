# ccstatusline-extras

给 Claude Code 底栏整合三个「会话健康」指标 —— 基于 [ccstatusline](https://github.com/sirmalloc/ccstatusline) 的预设组合包：

- **Cache Hit**：当前会话真实缓存命中率（口径与 Claude Code 官方 `prompt_cache.hit_ratio` 一致）
- **In: X**：会话累计输入 token（transcript 全量统计，含压缩前历史，不随压缩归零）
- **↻ N**：当前会话的上下文压缩（compact）次数

**解决什么问题**：ccstatusline 默认不显示缓存命中率，也不告诉你这个会话已经被压缩过几次——长会话里，这两项直接决定成本和剩余上下文。本包补上这两个部件，并附一份开箱即用的两行预设，不需要改 ccstatusline 源码。

两行布局示例（真实渲染）：

```text
cwd: /home/dev/ccstatusline-extras ⎇ main | Opus 4.6
Total: 344.3M | Out: — | Cache Hit: 49.4% | In: 174.1M | Ctx Used: 90.7% | ↻ 2
```

> 其中 `Out` 为近 30 秒输出速率，空闲或无近期数据时显示 `—`；`In` 为会话累计输入 token，含压缩前历史。

## 组件

| 组件 | 说明 |
| --- | --- |
| `preset/settings.json` | ccstatusline 预设（两行布局）：行一 cwd / git 分支 / 模型；行二 Total / Out / Cache Hit / In / Ctx% / ↻ |
| `bin/cc-cache-rate.py` | 命中率小脚本；优先读 stdin JSON 的 `prompt_cache.hit_ratio`，缺失时回退解析 transcript JSONL；无数据时输出 `Cache Hit: n/a` |
| `install.sh` | 一键安装：装小脚本 → 写预设 → 接线 statusLine，全部先备份 |
| `uninstall.sh` | 按安装时记录的恢复点还原 / 清理 |
| `test/smoke.sh` | 不触碰真实 HOME 的冒烟自测 |

## 环境要求

- Claude Code（状态栏 stdin JSON 协议）
- [ccstatusline](https://github.com/sirmalloc/ccstatusline)：`npm install -g ccstatusline`（Node.js 18+）；缺失时安装脚本会询问是否代为安装
- `python3`（安装脚本合并 JSON 与小脚本统计命中率均需）
- Linux / macOS；Windows 未验证（WSL / Git Bash 理论可用）

## 安装

```bash
cd ccstatusline-extras
bash install.sh
```

脚本会做四件事：

1. 安装小脚本到 `~/.local/bin/cc-cache-rate.py`
2. 写入 ccstatusline 预设到 `~/.config/ccstatusline/settings.json`（已存在且与预设逐字节一致时跳过；否则先备份再覆盖）
3. 在 `~/.claude/settings.json` 写入 statusLine 配置（`ccstatusline`，刷新间隔 10s）；**其余键与 hooks 原样保留**，修改前先备份
4. 把全部恢复点写入 `${XDG_DATA_HOME:-~/.local/share}/ccstatusline-extras/state.json`

完成后重启 Claude Code（或等最多 10 秒）即可看到新底栏。重复执行 `install.sh` 是安全的（幂等，已有恢复点不会被覆盖）。

### 选项

| 选项 | 说明 |
| --- | --- |
| `--yes` | 所有交互直接同意（脚本 / CI 场景） |
| `--no-preset` | 不动 ccstatusline 配置，只装小脚本 + 接线 statusLine |
| `-h`, `--help` | 帮助 |

## 快速开始

**方式一（推荐）**：直接跑安装脚本，预设与接线一次到位。

```bash
git clone https://github.com/Cocos666a/ccstatusline-extras.git ccstatusline-extras && cd ccstatusline-extras
bash install.sh --yes
```

不需要 sudo：只写当前用户的 `~/.local/bin`、`~/.config`、`~/.claude` 三个目录，且每个文件改动前都会备份。

**方式二（手动接线）**：只想用命中率小脚本，或想保留自己的 ccstatusline 布局。

```bash
# 1. 装小脚本
mkdir -p ~/.local/bin
cp bin/cc-cache-rate.py ~/.local/bin/cc-cache-rate.py
chmod 755 ~/.local/bin/cc-cache-rate.py

# 2. 把预设写进 ccstatusline 配置（先把占位符换成真实路径）
mkdir -p ~/.config/ccstatusline
sed "s|__CC_CACHE_RATE__|$HOME/.local/bin/cc-cache-rate.py|" \
  preset/settings.json > ~/.config/ccstatusline/settings.json
```

```jsonc
// 3. 把 statusLine 指向 ccstatusline（编辑 ~/.claude/settings.json，只加这一个键）
{
  "statusLine": {
    "type": "command",
    "command": "ccstatusline",
    "refreshInterval": 10
  }
}
```

改完重启 Claude Code，或等最多 10 秒刷新。手动方式没有 state 文件，`uninstall.sh` 无法还原，卸载需自行把备份复制回去。

## 卸载

```bash
bash uninstall.sh          # 交互式确认
bash uninstall.sh --yes    # 全部同意
```

- **ccstatusline 配置**：有备份则从备份恢复；无备份（安装前不存在）且当前内容与安装时一致则删除；被手动改过则保留并警告
- **statusLine**：恢复为安装前原值（安装前没有该键则删除）；若安装后又被手动改过则保留并警告
- **小脚本**：有备份则恢复备份，无备份则删除
- **state 目录**：删除
- 备份文件（`*.bak.<时间戳>`）不会被自动清理，便于事后人工核对
- ccstatusline 包本身不会被卸载；若是安装脚本代为安装的，会提示 `npm uninstall -g ccstatusline`

## 备份与恢复

安装 / 卸载涉及的每个文件在改动前都会生成时间戳备份（同一秒内冲突自动追加 `-N`）：

```text
~/.config/ccstatusline/settings.json.bak.20261017103930
~/.claude/settings.json.bak.20261017103930
~/.local/bin/cc-cache-rate.py.bak.20261017103930
```

手动回滚：把对应 `.bak.*` 文件复制回原路径即可。

## 常见问题

**Q：会覆盖我现有的 ccstatusline 配置吗？**
A：写入前一定先备份；若当前内容与预设逐字节一致则完全跳过。预设写入后你可以在 ccstatusline 的 TUI 里随意调整，卸载时仍可从备份恢复安装前的版本。

**Q：Cache Hit 的口径是什么？**
A：与 Claude Code 的 `prompt_cache.hit_ratio` 一致：`cache_read ÷ (cache_read + cache_creation + uncached_input)`。若 stdin 无该字段（旧版 Claude Code），回退解析 transcript JSONL 做统计；完全无数据时显示 `n/a`。

**Q：`In:` 的口径是什么？压缩后会归零吗？**
A：`In:` 是 ccstatusline 内置的 `tokens-input` 部件：对会话 transcript 做全量累计（所有 `input_tokens` 之和，不含缓存命中的读取量——那部分体现在 `Total` 与 `Cache Hit`）。压缩不会重置累计值，因此包含已被压缩掉的历史；看整个会话的输入总量用 `In`，看压缩次数用 `↻`。

**Q：为什么 `↻` 一直是 0？**
A：表示当前会话还没发生过上下文压缩。发生一次自动压缩或 `/compact` 后计数 +1；计数来自 transcript 中的 `compact_boundary` 记录（排除 sidechain）。

**Q：statusLine 里我原来的其他配置（hooks 等）会丢吗？**
A：不会。安装脚本只更新 `statusLine` 一个键，其余内容原样保留。

**Q：Windows 支持吗？**
A：暂未验证。脚本是 bash + python3，Git Bash / WSL 理论可用，欢迎反馈。

**Q：怎么自测这套脚本？**
A：`bash test/smoke.sh`，会在临时目录里模拟一个假 HOME 完整跑通「安装 → 重装 → 卸载」，不触碰你的真实配置。

## 目录结构

```text
ccstatusline-extras/
├── bin/cc-cache-rate.py     # 命中率小脚本；读 stdin JSON，回退解析 transcript
├── preset/settings.json     # ccstatusline 预设（schema v4，含 __CC_CACHE_RATE__ 占位符）
├── install.sh               # 安装：小脚本 → 预设 → statusLine 接线，全程先备份
├── uninstall.sh             # 按 state.json 还原，只动自己碰过的文件
├── test/smoke.sh            # 冒烟自测：假 HOME 里跑通 安装 → 重装 → 卸载
├── README.md
└── LICENSE
```

## 兼容性

| 依赖 | 说明 |
| --- | --- |
| ccstatusline | 在 `2.2.32`（Node 18+）上实测通过，含真实渲染断言；预设按 ccstatusline settings schema **version 4** 编写 |
| Claude Code | 需要状态栏 stdin JSON 协议（提供 `prompt_cache.hit_ratio` 或 `transcript_path`）；无 `prompt_cache` 的旧版会自动回退解析 transcript |
| 平台 | Linux / macOS 已验证；Windows 未验证 |
| 工具 | `bash`、`python3`（安装脚本合并 JSON 与小脚本统计均需） |

## 已知限制

- **Windows 未验证**：脚本是 bash + python3，Git Bash / WSL 理论可用，欢迎反馈。
- **命中率回退口径**：走 transcript 回退时统计的是整个会话的累计比例，不是「当前请求」的瞬时命中率；只有在 stdin 带 `prompt_cache.hit_ratio` 时才与官方逐次口径一致。
- **超大 transcript 可能超时**：预设给 custom-command 的 `timeout` 是 2000ms，回退解析要逐行扫完整个 JSONL；几十万行的会话可能来不及算，此时显示 `Cache Hit: n/a`。
- **预设会整体覆盖**：`install.sh` 写入的是完整预设文件（覆盖前必先备份）。想保留自己的布局就加 `--no-preset`，只装小脚本 + 接线。
- **`In:` 不是总成本**：该部件只累计 `input_tokens`，不含缓存命中的读取量（那部分看 `Total` 与 `Cache Hit:`）。

## 贡献

欢迎 issue / PR。提交前请：

1. 跑一遍 `bash test/smoke.sh`——它只建临时假 HOME，不会读写你的真实配置；
2. 保持 `install.sh` 幂等，并遵守「只改 `~/.claude/settings.json` 的 `statusLine` 一个键、其余键与 hooks 原样保留」的约定；
3. 新增交互或改动备份/还原路径时，同步更新 `uninstall.sh` 与本文档。

## English (brief)

ccstatusline-extras is a tiny preset package for [ccstatusline](https://github.com/sirmalloc/ccstatusline) that adds two widgets to the Claude Code status line — **cache hit ratio** (same formula as Claude Code's `prompt_cache.hit_ratio`, with transcript fallback) and **compaction count ↻ N** — and ships a two-line preset whose second line also shows session-cumulative input tokens (`In:`, counted across the whole transcript including compacted history) and context usage. `bash install.sh` backs up every file it touches, leaves `~/.claude/settings.json` intact apart from the `statusLine` key, and is idempotent (`--yes` / `--no-preset` supported). `bash uninstall.sh` restores previous configs from timestamped backups.

## License

MIT
