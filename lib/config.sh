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
  local backend="$1"
  local worker_path="${2-}"
  local worker_path_quoted=""
  local backend_instructions
  local backend_settings=""
  if [[ "$backend" == "opencode" ]]; then
    printf -v worker_path_quoted '%q' "$worker_path"
    backend_settings=$'sandbox_mode = "workspace-write"\nsandbox_workspace_write.network_access = true'
    backend_instructions="适合外部 OpenCode 的独立实现或评审，必须通过绝对路径执行 OpenCode worker：$worker_path_quoted。该 worker 使用独立 OpenCode 配置和固定的 Z.AI GLM 模型，在当前工作目录执行；返回结果后由你检查 diff、运行验证并整合。不要把 OpenCode 当作主控，也不要绕过任务简报、owned_files 和验收条件。"
  else
    backend_instructions="适合外部 GLM 的独立实现或评审交给 glm_worker。"
  fi
  cat <<EOF
# codex-hybrid:managed
# Sol 主控配置档案。服务提供商配置块保留在 config.toml 中。
model = "gpt-5.6-sol"
model_reasoning_effort = "xhigh"
$backend_settings
developer_instructions = """
你是 Sol 主控。使用已安装的 hybrid-dev 协作契约拆解、分派、整合并验证任务；边界清晰的小任务交给 luna_worker。$backend_instructions 执行代理不得共享文件所有权，最终结论由你验证。
"""
EOF
}

render_opencode_config() {
  local model_name="$1"
  cat <<EOF
{
  "\$schema": "https://opencode.ai/config.json",
  "enabled_providers": ["$hybrid_opencode_provider_id"],
  "disabled_providers": [],
  "model": "$hybrid_opencode_provider_id/$model_name",
  "provider": {
    "$hybrid_opencode_provider_id": {
      "options": {
        "apiKey": "{env:ZHIPU_API_KEY}"
      }
    }
  }
}
EOF
}

render_codex_launcher() {
  local codex_home_path="$1"
  local profile_name="$2"
  local codex_home_quoted
  printf -v codex_home_quoted '%q' "$codex_home_path"
  cat <<EOF
#!/usr/bin/env bash
# codex-hybrid:managed
set -euo pipefail
export CODEX_HOME=$codex_home_quoted
exec codex --profile $profile_name "\$@"
EOF
}

render_gpt_glm_launcher() {
  render_codex_launcher "$1" sol-luna
}

render_gpt_opencode_launcher() {
  render_codex_launcher "$1" sol-opencode
}

render_opencode_worker() {
  local config_path="$1"
  local key_path="$2"
  local model_name="$3"
  local installed_opencode_path="$4"
  local config_path_quoted
  local key_path_quoted
  local installed_opencode_quoted
  printf -v config_path_quoted '%q' "$config_path"
  printf -v key_path_quoted '%q' "$key_path"
  printf -v installed_opencode_quoted '%q' "$installed_opencode_path"
cat <<EOF
#!/usr/bin/env bash
# codex-hybrid:managed
set -euo pipefail
opencode_path=$installed_opencode_quoted
[[ -n "\$opencode_path" && -x "\$opencode_path" ]] || {
  printf '[gpt-opencode][错误] 未安装 OpenCode CLI；请重新运行 codex-hybrid install.sh。\n' >&2
  exit 127
}
key_path=$key_path_quoted
config_path=$config_path_quoted
[[ -r "\$key_path" ]] || {
  printf '[gpt-opencode][错误] 无法读取 ZAI API 密钥：%s\n' "\$key_path" >&2
  exit 1
}
IFS= read -r ZHIPU_API_KEY < "\$key_path"
[[ -n "\$ZHIPU_API_KEY" ]] || {
  printf '[gpt-opencode][错误] ZAI API 密钥为空。\n' >&2
  exit 1
}
export ZHIPU_API_KEY
export OPENCODE_CONFIG="\$config_path"
OPENCODE_CONFIG_CONTENT="\$(<"\$config_path")"
export OPENCODE_CONFIG_CONTENT
for argument in "\$@"; do
  case "\$argument" in
    --model|--model=*)
      printf '[codex-hybrid][错误] OpenCode worker 不允许覆盖固定模型。\n' >&2
      exit 2
      ;;
  esac
done
exec "\$opencode_path" run --dir "\$PWD" --model "$hybrid_opencode_provider_id/$model_name" "\$@"
EOF
}

render_manifest() {
  local codex_home_path="$1"
  local skills_path="$2"
  local commands_path="$3"
  local opencode_worker_path="$4"
  cat <<EOF
# codex-hybrid:managed
version=$hybrid_version
provider_id=$hybrid_provider_id
config_path=$codex_home_path/config.toml
profile_path=$codex_home_path/sol-luna.config.toml
opencode_profile_path=$codex_home_path/sol-opencode.config.toml
luna_agent_path=$codex_home_path/agents/luna_worker.toml
glm_agent_path=$codex_home_path/agents/glm_worker.toml
token_helper_path=$codex_home_path/bin/codex-hybrid-token
secret_path=$codex_home_path/secrets/zai_api_key
skill_path=$skills_path/hybrid-dev
opencode_config_path=$codex_home_path/opencode/opencode.json
opencode_marker_path=$codex_home_path/opencode/.codex-hybrid-managed
opencode_worker_path=$opencode_worker_path
gpt_glm_path=$commands_path/gpt-glm
gpt_opencode_path=$commands_path/gpt-opencode
EOF
}
