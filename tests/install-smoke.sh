#!/usr/bin/env bash
set -euo pipefail

root_dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
sandbox_dir="$(mktemp -d "${TMPDIR:-/tmp}/codex-hybrid-test.XXXXXX")"
trap 'rm -rf "$sandbox_dir"' EXIT
export CODEX_HYBRID_TEST_MODE=1
export HOME="$sandbox_dir/home"
export CODEX_HOME="$sandbox_dir/codex"
export CODEX_HYBRID_SKILLS_DIR="$CODEX_HOME/skills"
export ZAI_API_KEY="test-key-value"
mkdir -p "$HOME"

bash "$root_dir/install.sh" --set-default
config_hash="$(shasum -a 256 "$CODEX_HOME/config.toml" | awk '{print $1}')"
bash "$root_dir/install.sh" --set-default
repeat_hash="$(shasum -a 256 "$CODEX_HOME/config.toml" | awk '{print $1}')"
[[ "$config_hash" == "$repeat_hash" ]] || { echo "服务提供商安装不具备幂等性" >&2; exit 1; }
bash "$root_dir/install.sh" --glm-model glm-4.7
rg -F -q 'model = "glm-4.7"' "$CODEX_HOME/agents/glm_worker.toml"

[[ "$(awk '{print}' "$CODEX_HOME/secrets/zai_api_key")" == "$ZAI_API_KEY" ]]
[[ "$(stat -f '%Lp' "$CODEX_HOME/secrets/zai_api_key" 2>/dev/null || stat -c '%a' "$CODEX_HOME/secrets/zai_api_key")" == "600" ]]
[[ "$("$CODEX_HOME/bin/codex-hybrid-token")" == "$ZAI_API_KEY" ]]
[[ "$(rg -c 'codex-hybrid:begin provider v0.2' "$CODEX_HOME/config.toml")" == "1" ]]
[[ -f "$CODEX_HOME/agents/luna_worker.toml" ]]
[[ -f "$CODEX_HOME/agents/glm_worker.toml" ]]
[[ -f "$CODEX_HOME/sol-luna.config.toml" ]]
[[ -f "$CODEX_HOME/skills/hybrid-dev/SKILL.md" ]]
! rg -q 'test-key-value' "$CODEX_HOME/config.toml" "$CODEX_HOME/agents" "$CODEX_HOME/skills"
[[ -n "$(find "$CODEX_HOME/backups/codex-hybrid" -mindepth 1 -maxdepth 1 -type d -print -quit)" ]]

echo "安装冒烟测试：PASS"
