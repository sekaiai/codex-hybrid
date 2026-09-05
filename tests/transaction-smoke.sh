#!/usr/bin/env bash
set -euo pipefail

root_dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
sandbox_dir="$(mktemp -d "${TMPDIR:-/tmp}/codex-hybrid-transaction.XXXXXX")"
trap 'rm -rf "$sandbox_dir"' EXIT
export CODEX_HYBRID_TEST_MODE=1
export HOME="$sandbox_dir/home"
export CODEX_HOME="$sandbox_dir/codex"
export CODEX_HYBRID_SKILLS_DIR="$CODEX_HOME/skills"
export CODEX_HYBRID_BIN_DIR="$sandbox_dir/bin"
export ZAI_API_KEY="test-key-value"
export FAIL_TARGET="$CODEX_HYBRID_BIN_DIR/gpt-glm"
export FAIL_MARKER="$sandbox_dir/mv-failed-once"
stub_dir="$sandbox_dir/stubs"
mkdir -p "$HOME" "$CODEX_HOME" "$stub_dir"

cat > "$CODEX_HOME/config.toml" <<'EOF'
model = "existing-model"
EOF
before_hash="$(shasum -a 256 "$CODEX_HOME/config.toml" | awk '{print $1}')"

cat > "$stub_dir/codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ "${1-}" == "--version" ]] && { echo "codex-cli test"; exit 0; }
exit 0
EOF

cat > "$stub_dir/opencode" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

cat > "$stub_dir/mv" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
target=""
for argument in "$@"; do
  target="$argument"
done
if [[ "$target" == "$FAIL_TARGET" && ! -e "$FAIL_MARKER" ]]; then
  : > "$FAIL_MARKER"
  exit 1
fi
exec /bin/mv "$@"
EOF
chmod +x "$stub_dir/codex" "$stub_dir/opencode" "$stub_dir/mv"
export PATH="$stub_dir:$PATH"

if bash "$root_dir/install.sh"; then
  echo "事务回滚测试：安装器意外成功" >&2
  exit 1
fi

after_hash="$(shasum -a 256 "$CODEX_HOME/config.toml" | awk '{print $1}')"
[[ "$before_hash" == "$after_hash" ]]
[[ ! -e "$CODEX_HOME/secrets/zai_api_key" ]]
[[ ! -e "$CODEX_HOME/agents/luna_worker.toml" ]]
[[ ! -e "$CODEX_HOME/agents/glm_worker.toml" ]]
[[ ! -e "$CODEX_HOME/sol-luna.config.toml" ]]
[[ ! -e "$CODEX_HOME/sol-opencode.config.toml" ]]
[[ ! -e "$CODEX_HOME/opencode/opencode.json" ]]
[[ ! -e "$CODEX_HYBRID_BIN_DIR/gpt-glm" ]]
[[ ! -e "$CODEX_HYBRID_BIN_DIR/gpt-opencode" ]]
[[ ! -e "$CODEX_HOME/bin/codex-hybrid-opencode-worker" ]]

echo "事务回滚冒烟测试：PASS"
