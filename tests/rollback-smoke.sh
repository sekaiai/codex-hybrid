#!/usr/bin/env bash
set -euo pipefail

root_dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
sandbox_dir="$(mktemp -d "${TMPDIR:-/tmp}/codex-hybrid-rollback.XXXXXX")"
trap 'rm -rf "$sandbox_dir"' EXIT
export CODEX_HYBRID_TEST_MODE=1
export HOME="$sandbox_dir/home"
export CODEX_HOME="$sandbox_dir/codex"
export CODEX_HYBRID_SKILLS_DIR="$CODEX_HOME/skills"
export ZAI_API_KEY="test-key-value"
mkdir -p "$HOME" "$CODEX_HOME"
cat > "$CODEX_HOME/config.toml" <<'EOF'
model = "existing-model"

[model_providers.zai_coding_plan]
name = "unmanaged"
EOF
before_hash="$(shasum -a 256 "$CODEX_HOME/config.toml" | awk '{print $1}')"
if bash "$root_dir/install.sh"; then
  echo "回滚冒烟测试：安装器意外成功" >&2
  exit 1
fi
after_hash="$(shasum -a 256 "$CODEX_HOME/config.toml" | awk '{print $1}')"
[[ "$before_hash" == "$after_hash" ]]
[[ ! -e "$CODEX_HOME/secrets/zai_api_key" ]]
[[ ! -e "$CODEX_HOME/agents/luna_worker.toml" ]]
echo "回滚冒烟测试：PASS"
