#!/usr/bin/env bash
set -euo pipefail

root_dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
skill="$root_dir/skills/hybrid-dev/SKILL.md"
sol="$root_dir/agents/sol.toml"
luna="$root_dir/agents/luna-worker.toml"

[[ -f "$skill" ]] || { echo "缺少 hybrid-dev Skill" >&2; exit 1; }
[[ -f "$sol" ]] || { echo "缺少 Sol 主控定义" >&2; exit 1; }
[[ -f "$luna" ]] || { echo "缺少 Luna 执行代理定义" >&2; exit 1; }

rg -F -q 'Codex CLI 主控' "$sol"
rg -F -q 'luna_worker' "$sol"
rg -F -q 'claude' "$skill"
rg -F -q 'opencode' "$skill"
rg -F -q 'Provider、订阅、API Key 和模型切换由用户' "$skill"
rg -F -q '默认执行代理' "$skill"

echo "手动协作模式静态检查：PASS"
