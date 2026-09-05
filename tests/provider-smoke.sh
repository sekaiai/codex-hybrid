#!/usr/bin/env bash
set -euo pipefail

confirm_network=0
model="glm-5.2"
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --confirm-network) confirm_network=1 ;;
    --model)
      [[ "$#" -ge 2 ]] || { echo "--model 需要参数值" >&2; exit 2; }
      model="$2"
      shift
      ;;
    *) echo "未知选项：$1" >&2; exit 2 ;;
  esac
  shift
done

if [[ "$confirm_network" != "1" ]]; then
  echo "此测试会发送真实请求，可能产生服务提供商费用。" >&2
  echo "运行：$0 --confirm-network" >&2
  exit 2
fi

codex_home_dir="${CODEX_HOME:-$HOME/.codex}"
[[ -x "$codex_home_dir/bin/codex-hybrid-token" ]] ||
  { echo "请先安装协作包" >&2; exit 1; }
command -v codex >/dev/null 2>&1 || { echo "需要 codex 命令" >&2; exit 1; }

CODEX_HOME="$codex_home_dir" codex exec \
  --sandbox read-only \
  --skip-git-repo-check \
  --model "$model" \
  --config model_provider='"zai_coding_plan"' \
  "请只回复 OK。"
