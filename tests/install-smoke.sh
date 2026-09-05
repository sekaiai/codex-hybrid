#!/usr/bin/env bash
set -euo pipefail

root_dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
sandbox_dir="$(mktemp -d "${TMPDIR:-/tmp}/codex-hybrid-test.XXXXXX")"
trap 'rm -rf "$sandbox_dir"' EXIT
export CODEX_HYBRID_TEST_MODE=1
export HOME="$sandbox_dir/home"
export CODEX_HOME="$sandbox_dir/codex"
export CODEX_HYBRID_SKILLS_DIR="$CODEX_HOME/skills"
export CODEX_HYBRID_BIN_DIR="$sandbox_dir/bin"
export ZAI_API_KEY="test-key-value"
mkdir -p "$HOME"

bash "$root_dir/install.sh" --set-default
config_hash="$(shasum -a 256 "$CODEX_HOME/config.toml" | awk '{print $1}')"
bash "$root_dir/install.sh" --set-default
repeat_hash="$(shasum -a 256 "$CODEX_HOME/config.toml" | awk '{print $1}')"
[[ "$config_hash" == "$repeat_hash" ]] || { echo "服务提供商安装不具备幂等性" >&2; exit 1; }
bash "$root_dir/install.sh" --glm-model glm-4.7
rg -F -q 'model = "glm-4.7"' "$CODEX_HOME/agents/glm_worker.toml"
rg -F -q '"model": "zai-coding-plan/glm-4.7"' "$CODEX_HOME/opencode/opencode.json"
rg -F -q -- '--profile sol-opencode' "$CODEX_HYBRID_BIN_DIR/gpt-opencode"
rg -F -q 'zai-coding-plan/glm-4.7' "$CODEX_HOME/bin/codex-hybrid-opencode-worker"

[[ "$(awk '{print}' "$CODEX_HOME/secrets/zai_api_key")" == "$ZAI_API_KEY" ]]
[[ "$(stat -f '%Lp' "$CODEX_HOME/secrets/zai_api_key" 2>/dev/null || stat -c '%a' "$CODEX_HOME/secrets/zai_api_key")" == "600" ]]
[[ "$("$CODEX_HOME/bin/codex-hybrid-token")" == "$ZAI_API_KEY" ]]
[[ "$(rg -c 'codex-hybrid:begin provider v0.2' "$CODEX_HOME/config.toml")" == "1" ]]
[[ -f "$CODEX_HOME/agents/luna_worker.toml" ]]
[[ -f "$CODEX_HOME/agents/glm_worker.toml" ]]
[[ -f "$CODEX_HOME/sol-luna.config.toml" ]]
[[ -f "$CODEX_HOME/sol-opencode.config.toml" ]]
rg -F -q 'luna_worker' "$CODEX_HOME/sol-luna.config.toml"
rg -F -q 'glm_worker' "$CODEX_HOME/sol-luna.config.toml"
rg -F -q 'codex-hybrid-opencode-worker' "$CODEX_HOME/sol-opencode.config.toml"
rg -F -q 'sandbox_workspace_write.network_access = true' "$CODEX_HOME/sol-opencode.config.toml"
[[ -x "$CODEX_HYBRID_BIN_DIR/gpt-glm" ]]
[[ -x "$CODEX_HYBRID_BIN_DIR/gpt-opencode" ]]
[[ -x "$CODEX_HOME/bin/codex-hybrid-opencode-worker" ]]
[[ -f "$CODEX_HOME/opencode/opencode.json" ]]
[[ -f "$CODEX_HOME/opencode/.codex-hybrid-managed" ]]
[[ -f "$CODEX_HOME/skills/hybrid-dev/SKILL.md" ]]
! rg -q 'test-key-value' "$CODEX_HOME/config.toml" "$CODEX_HOME/agents" "$CODEX_HOME/skills"
[[ -n "$(find "$CODEX_HOME/backups/codex-hybrid" -mindepth 1 -maxdepth 1 -type d -print -quit)" ]]

echo "安装冒烟测试：PASS"
