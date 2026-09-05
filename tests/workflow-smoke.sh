#!/usr/bin/env bash
set -euo pipefail

root_dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
skill_path="$root_dir/skills/hybrid-dev/SKILL.md"

rg -q 'owned_files' "$skill_path"
rg -q 'read_only_files' "$skill_path"
rg -q 'PRECHECK -> PLAN -> DISPATCH -> EXECUTE -> INTEGRATE -> REVIEW -> REPAIR -> DONE' "$skill_path"
rg -q 'REPAIR 最多执行三次' "$skill_path"
rg -q '执行代理结果契约' "$skill_path"
rg -q '两个执行代理不得同时拥有同一个文件' "$skill_path"
rg -q '默认只启用 Sol 和 Luna' "$skill_path"
echo "协作协议冒烟测试：PASS"
