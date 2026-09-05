#!/usr/bin/env bash
set -euo pipefail

validate_json_file() {
  local json_path="$1"
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$json_path" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as handle:
    json.load(handle)
PY
  elif command -v node >/dev/null 2>&1; then
    node -e 'JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"))' "$json_path"
  else
    die "无法验证 JSON：需要 python3 或 node"
  fi
}

validate_secret_file() {
  local secret_path="$1"
  [[ -f "$secret_path" ]] || die "密钥文件不存在：$secret_path"
  [[ "$(stat -f '%Lp' "$secret_path" 2>/dev/null || stat -c '%a' "$secret_path")" == "600" ]] ||
    die "密钥文件权限必须为 600：$secret_path"
  [[ -s "$secret_path" ]] || die "密钥文件为空：$secret_path"
}

validate_helper() {
  local helper_path="$1"
  [[ -x "$helper_path" ]] || die "认证辅助程序不可执行：$helper_path"
  local token
  token="$("$helper_path")"
  [[ -n "$token" ]] || die "认证辅助程序返回了空令牌"
}

validate_managed_file() {
  local file_path="$1"
  [[ -f "$file_path" ]] || die "受管文件不存在：$file_path"
  awk -v marker="$hybrid_managed_marker" '$0 == marker { found=1 } END { exit(found ? 0 : 1) }' "$file_path" ||
    die "受管标记在 $file_path 中不存在"
  ! rg -q '__[A-Z0-9_]+__' "$file_path" || die "$file_path 中仍存在未渲染的占位符"
}

validate_agent_dir() {
  local agents_dir="$1"
  local expected_glm_model="${2-}"
  if [[ -z "$expected_glm_model" ]]; then
    expected_glm_model="glm-5.2"
  fi
  local luna_agent="$agents_dir/luna_worker.toml"
  local glm_agent="$agents_dir/glm_worker.toml"
  [[ -f "$luna_agent" ]] || luna_agent="$agents_dir/luna-worker.toml"
  [[ -f "$glm_agent" ]] || glm_agent="$agents_dir/glm-worker.toml"
  if [[ "$luna_agent" == *luna-worker.toml ]]; then
    awk -v marker="$hybrid_managed_marker" '$0 == marker { found=1 } END { exit(found ? 0 : 1) }' "$luna_agent" ||
      die "受管标记在 $luna_agent 中不存在"
  else
    validate_managed_file "$luna_agent"
  fi
  if [[ "$glm_agent" == *glm-worker.toml ]]; then
    awk -v marker="$hybrid_managed_marker" '$0 == marker { found=1 } END { exit(found ? 0 : 1) }' "$glm_agent" ||
      die "受管标记在 $glm_agent 中不存在"
  else
    validate_managed_file "$glm_agent"
  fi
  rg -q '^model = "gpt-5\.6-luna"$' "$luna_agent" ||
    die "Luna 模型未正确配置"
  rg -q '^model_provider = "zai_coding_plan"$' "$glm_agent" ||
    die "GLM 服务提供商未正确配置"
  if [[ "$glm_agent" == *glm-worker.toml ]]; then
    rg -F -q 'model = "__GLM_MODEL__"' "$glm_agent" ||
      die "GLM 模型占位符未正确配置"
  else
    rg -F -q "model = \"$expected_glm_model\"" "$glm_agent" ||
      die "GLM 模型未正确配置"
  fi
}

validate_codex_home() {
  local codex_home_path="$1"
  local require_codex="$2"
  if [[ -z "$require_codex" ]]; then
    require_codex="1"
  fi
  validate_managed_file "$codex_home_path/agents/luna_worker.toml"
  validate_managed_file "$codex_home_path/agents/glm_worker.toml"
  validate_secret_file "$codex_home_path/secrets/zai_api_key"
  validate_helper "$codex_home_path/bin/codex-hybrid-token"

  if [[ "$require_codex" == "1" ]] && command -v codex >/dev/null 2>&1; then
    CODEX_HOME="$codex_home_path" codex --strict-config --help >/dev/null
  elif [[ "$require_codex" == "1" ]]; then
    warn "未安装 Codex，跳过 Codex 配置解析验证"
  fi
}
