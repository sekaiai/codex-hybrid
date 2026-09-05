#!/usr/bin/env bash
set -euo pipefail

root_dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
sandbox_dir="$(mktemp -d "${TMPDIR:-/tmp}/codex-hybrid-uninstall.XXXXXX")"
trap 'rm -rf "$sandbox_dir"' EXIT
export CODEX_HYBRID_TEST_MODE=1
export HOME="$sandbox_dir/home"
export CODEX_HOME="$sandbox_dir/codex"
export CODEX_HYBRID_SKILLS_DIR="$CODEX_HOME/skills"
export ZAI_API_KEY="test-key-value"
mkdir -p "$HOME"

bash "$root_dir/install.sh" --set-default
bash "$root_dir/uninstall.sh"
[[ ! -e "$CODEX_HOME/secrets/zai_api_key" ]]
[[ ! -e "$CODEX_HOME/agents/luna_worker.toml" ]]
[[ ! -e "$CODEX_HOME/agents/glm_worker.toml" ]]
[[ ! -e "$CODEX_HOME/skills/hybrid-dev" ]]
[[ ! -e "$CODEX_HOME/sol-luna.config.toml" ]]
! rg -q 'zai_coding_plan' "$CODEX_HOME/config.toml"
[[ -n "$(find "$CODEX_HOME/backups/codex-hybrid-uninstall" -name zai_api_key -print -quit)" ]]

bash "$root_dir/install.sh"
bash "$root_dir/uninstall.sh" --purge-secret
[[ ! -e "$CODEX_HOME/secrets/zai_api_key" ]]

echo "卸载冒烟测试：PASS"
