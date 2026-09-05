#!/usr/bin/env bash
set -euo pipefail

root_dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
sandbox_dir="$(mktemp -d "${TMPDIR:-/tmp}/codex-hybrid-launcher.XXXXXX")"
trap 'rm -rf "$sandbox_dir"' EXIT
export CODEX_HYBRID_TEST_MODE=1
export HOME="$sandbox_dir/home"
export CODEX_HOME="$sandbox_dir/codex"
export CODEX_HYBRID_SKILLS_DIR="$CODEX_HOME/skills"
export CODEX_HYBRID_BIN_DIR="$sandbox_dir/bin"
export ZAI_API_KEY="test-key-value"
export LAUNCHER_LOG="$sandbox_dir/launcher.log"
stub_dir="$sandbox_dir/stubs"
mkdir -p "$HOME" "$stub_dir"

cat > "$stub_dir/codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1-}" == "--version" ]]; then
  echo "codex-cli test"
  exit 0
fi
if [[ "${1-}" == "--strict-config" ]]; then
  exit 0
fi
printf 'codex' > "$LAUNCHER_LOG"
printf '\t%s' "$@" >> "$LAUNCHER_LOG"
printf '\n' >> "$LAUNCHER_LOG"
EOF

cat > "$stub_dir/opencode" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1-}" == "--version" ]]; then
  echo "1.0.0-test"
  exit 0
fi
if [[ "${1-}" == "run" ]]; then
  [[ "${OPENCODE_CONFIG_CONTENT-}" == *'"model": "zai-coding-plan/glm-5.2"'* ]]
fi
printf 'opencode\t%s\t%s' "${OPENCODE_CONFIG-}" "${ZHIPU_API_KEY-}" > "$LAUNCHER_LOG"
printf '\t%s' "$@" >> "$LAUNCHER_LOG"
printf '\n' >> "$LAUNCHER_LOG"
EOF
chmod +x "$stub_dir/codex" "$stub_dir/opencode"
export PATH="$stub_dir:$PATH"

bash "$root_dir/install.sh"

"$CODEX_HYBRID_BIN_DIR/gpt-glm" "修复测试"
[[ "$(awk -F '\t' '{print $1}' "$LAUNCHER_LOG")" == "codex" ]]
rg -F -q $'codex\t--profile\tsol-luna\t修复测试' "$LAUNCHER_LOG"

"$CODEX_HYBRID_BIN_DIR/gpt-opencode" "实现测试"
rg -F -q $'codex\t--profile\tsol-opencode\t实现测试' "$LAUNCHER_LOG"

"$CODEX_HOME/bin/codex-hybrid-opencode-worker" "实现测试"
rg -F -q $'opencode\t'"$CODEX_HOME/opencode/opencode.json"$'\ttest-key-value\trun\t--dir\t'"$PWD" "$LAUNCHER_LOG"
rg -F -q -- $'--model\tzai-coding-plan/glm-5.2\t实现测试' "$LAUNCHER_LOG"
if "$CODEX_HOME/bin/codex-hybrid-opencode-worker" --model hacked "实现测试"; then
  echo "OpenCode worker 允许覆盖固定模型" >&2
  exit 1
fi

rg -F -q '"model": "zai-coding-plan/glm-5.2"' "$CODEX_HOME/opencode/opencode.json"
rg -F -q '"enabled_providers": ["zai-coding-plan"]' "$CODEX_HOME/opencode/opencode.json"
[[ -f "$CODEX_HOME/opencode/.codex-hybrid-managed" ]]
! rg -q 'test-key-value' "$CODEX_HOME/opencode/opencode.json"

echo "启动命令冒烟测试：PASS"
