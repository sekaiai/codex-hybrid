#!/usr/bin/env bash
set -euo pipefail

render_provider_block() {
  local helper_path="$1"
  cat <<EOF
# codex-hybrid:begin provider v0.2
[model_providers.zai_coding_plan]
name = "ZAI Coding Plan"
base_url = "https://open.bigmodel.cn/api/coding/paas/v4"
wire_api = "responses"
request_max_retries = 2
stream_idle_timeout_ms = 300000

[model_providers.zai_coding_plan.auth]
command = "$helper_path"
timeout_ms = 5000
refresh_interval_ms = 300000
# codex-hybrid:end provider
EOF
}

provider_block_state() {
  local config_path="$1"
  [[ -f "$config_path" ]] || return 1

  awk -v begin="$hybrid_begin_provider" -v end="$hybrid_end_provider" '
    $0 == begin { begin_count++; inside=1; next }
    $0 == end { end_count++; inside=0; next }
    !inside && $0 ~ /^[[:space:]]*\[model_providers\.zai_coding_plan\][[:space:]]*$/ { unmanaged=1 }
    END {
      if (begin_count > 1 || end_count > 1 || begin_count != end_count) exit 2
      if (unmanaged) exit 3
      if (begin_count == 1) exit 0
      exit 1
    }
  ' "$config_path"
}

assert_provider_safe_to_edit() {
  local config_path="$1"
  provider_block_state "$config_path" && return 0
  case "$?" in
    1) return 0 ;;
    2) die "服务提供商标记在 $config_path 中不完整或重复" ;;
    3) die "在 $config_path 中发现未受管的 [model_providers.zai_coding_plan] 配置块，拒绝合并" ;;
    *) die "无法检查 $config_path" ;;
  esac
}

upsert_provider_block() {
  local config_path="$1"
  local block_path="$2"
  local temporary_path
  temporary_path="$(mktemp "${TMPDIR:-/tmp}/codex-hybrid-config.XXXXXX")"

  awk -v begin="$hybrid_begin_provider" -v end="$hybrid_end_provider" -v block_file="$block_path" '
    BEGIN {
      while ((getline line < block_file) > 0) replacement = replacement line ORS
      close(block_file)
    }
    $0 == begin {
      if (!replaced) printf "%s", replacement
      inside=1
      replaced=1
      next
    }
    $0 == end { inside=0; next }
    !inside { print }
    END {
      if (!replaced) {
        if (NR > 0) print ""
        printf "%s", replacement
      }
    }
  ' "$config_path" > "$temporary_path"
  mv -f "$temporary_path" "$config_path"
}

remove_provider_block() {
  local config_path="$1"
  local temporary_path
  [[ -f "$config_path" ]] || return 0
  provider_block_state "$config_path" && true || {
    case "$?" in
      1) return 0 ;;
      2) die "服务提供商标记在 $config_path 中不完整或重复" ;;
      3) die "发现未受管的服务提供商配置块，拒绝移除" ;;
      *) die "无法检查 $config_path" ;;
    esac
  }

  temporary_path="$(mktemp "${TMPDIR:-/tmp}/codex-hybrid-config.XXXXXX")"
  awk -v begin="$hybrid_begin_provider" -v end="$hybrid_end_provider" '
    $0 == begin { inside=1; next }
    $0 == end { inside=0; next }
    !inside { print }
  ' "$config_path" > "$temporary_path"
  mv -f "$temporary_path" "$config_path"
}

render_profile() {
  cat <<EOF
# codex-hybrid:managed
# Sol 主控 / Luna 协作配置档案。服务提供商配置块保留在 config.toml 中。
model = "gpt-5.6-sol"
model_reasoning_effort = "xhigh"
EOF
}

render_manifest() {
  local codex_home_path="$1"
  local skills_path="$2"
  cat <<EOF
# codex-hybrid:managed
version=$hybrid_version
provider_id=$hybrid_provider_id
config_path=$codex_home_path/config.toml
profile_path=$codex_home_path/sol-luna.config.toml
luna_agent_path=$codex_home_path/agents/luna_worker.toml
glm_agent_path=$codex_home_path/agents/glm_worker.toml
token_helper_path=$codex_home_path/bin/codex-hybrid-token
secret_path=$codex_home_path/secrets/zai_api_key
skill_path=$skills_path/hybrid-dev
EOF
}
