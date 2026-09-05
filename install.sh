#!/usr/bin/env bash
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
source "$script_dir/lib/common.sh"
source "$script_dir/lib/config.sh"
source "$script_dir/lib/validate.sh"

dry_run=0
force=0
skip_opencode_install=0
catalog_path=""
glm_model="${GLM_MODEL:-$hybrid_glm_model}"
requested_version="$hybrid_version"

usage() {
  cat <<EOF
用法：$0 [选项]

将 Sol-Luna-GLM 协作包安装到 CODEX_HOME。

选项：
  --dry-run                 验证并打印写入计划，不实际写入。
  --force                   替换已有的 codex-hybrid 管理文件。
  --set-default             兼容选项；Sol 配置档案现在始终安装。
  --skip-opencode-install   不自动安装缺失的 OpenCode CLI。
  --glm-model MODEL         配置 GLM 执行代理使用的模型（默认：$hybrid_glm_model）。
  --catalog-path PATH       为 GLM 代理显式启用 Codex 模型目录。
  --version VERSION         要求安装包版本（当前为 $hybrid_version）。
  -h, --help                显示此帮助信息。
EOF
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --dry-run) dry_run=1 ;;
    --force) force=1 ;;
    --set-default) : ;;
    --skip-opencode-install) skip_opencode_install=1 ;;
    --glm-model)
      [[ "$#" -ge 2 ]] || die "--glm-model 需要模型名称"
      glm_model="$2"
      shift
      ;;
    --catalog-path)
      [[ "$#" -ge 2 ]] || die "--catalog-path 需要文件路径"
      catalog_path="$2"
      shift
      ;;
    --version)
      [[ "$#" -ge 2 ]] || die "--version 需要版本值"
      requested_version="$2"
      shift
      ;;
    -h|--help) usage; exit 0 ;;
    *) die "未知选项：$1" ;;
  esac
  shift
done

[[ "$requested_version" == "$hybrid_version" ]] ||
  if [[ "$requested_version" == "v$hybrid_version" ]]; then
    requested_version="$hybrid_version"
  else
    die "不支持的安装包版本：$requested_version（应为 $hybrid_version 或 v$hybrid_version）"
  fi

[[ "$glm_model" =~ ^[A-Za-z0-9._-]+$ ]] || die "GLM 模型名称无效：$glm_model"

check_platform
require_cmd awk
require_cmd chmod
require_cmd cp
require_cmd find
require_cmd mktemp
require_cmd mv
require_cmd rg
require_cmd stat
if ! is_test_mode; then
  require_cmd codex
fi
codex_version="not-installed"

codex_home_dir="${CODEX_HOME:-$HOME/.codex}"
skills_dir="${CODEX_HYBRID_SKILLS_DIR:-$HOME/.agents/skills}"
default_commands_dir="$HOME/.local/bin"
if command -v codex >/dev/null 2>&1; then
  codex_command_dir="$(dirname -- "$(command -v codex)")"
  [[ -w "$codex_command_dir" ]] && default_commands_dir="$codex_command_dir"
fi
commands_dir="${CODEX_HYBRID_BIN_DIR:-$default_commands_dir}"
config_path="$codex_home_dir/config.toml"
secret_path="$codex_home_dir/secrets/zai_api_key"
helper_path="$codex_home_dir/bin/codex-hybrid-token"
profile_path="$codex_home_dir/sol-luna.config.toml"
opencode_profile_path="$codex_home_dir/sol-opencode.config.toml"
luna_agent_path="$codex_home_dir/agents/luna_worker.toml"
glm_agent_path="$codex_home_dir/agents/glm_worker.toml"
skill_path="$skills_dir/hybrid-dev"
manifest_path="$codex_home_dir/codex-hybrid.manifest"
opencode_config_path="$codex_home_dir/opencode/opencode.json"
opencode_marker_path="$codex_home_dir/opencode/.codex-hybrid-managed"
opencode_worker_path="$codex_home_dir/bin/codex-hybrid-opencode-worker"
gpt_glm_path="$commands_dir/gpt-glm"
gpt_opencode_path="$commands_dir/gpt-opencode"

[[ -d "$codex_home_dir" || ! -e "$codex_home_dir" ]] ||
  die "CODEX_HOME 不是目录：$codex_home_dir"
if [[ -d "$codex_home_dir" ]] && command -v codex >/dev/null 2>&1; then
  codex_version="$(codex --version)"
fi

catalog_abs=""
if [[ -n "$catalog_path" ]]; then
  [[ -f "$catalog_path" ]] || die "模型目录文件不存在：$catalog_path"
  catalog_abs="$(absolute_path "$catalog_path")"
  validate_json_file "$catalog_abs"
fi

check_conflict() {
  local target_path="$1"
  local marker="$2"
  [[ -e "$target_path" ]] || return 0
  if file_has_marker "$target_path" "$marker"; then
    return 0
  fi
  [[ "$force" == "1" ]] ||
    die "已有未受管文件与 $target_path 冲突；只有明确要替换时才使用 --force"
}

check_skill_conflict() {
  [[ -e "$skill_path" ]] || return 0
  if file_has_marker "$skill_path/SKILL.md" "$hybrid_managed_marker"; then
    return 0
  fi
  [[ "$force" == "1" ]] ||
    die "已有未受管技能与 $skill_path 冲突；只有明确要替换时才使用 --force"
}

read_api_key() {
  local api_key_value=""
  if [[ -n "${ZAI_API_KEY:-}" ]]; then
    api_key_value="$ZAI_API_KEY"
  elif [[ -r "$secret_path" ]] && [[ -s "$secret_path" ]]; then
    api_key_value="$(awk 'NR == 1 { print; exit }' "$secret_path")"
  elif [[ -r /dev/tty ]]; then
    printf 'ZAI API 密钥（输入不可见）：' >&2
    IFS= read -r -s api_key_value < /dev/tty
    printf '\n' >&2
  else
    die "未提供 API 密钥；非交互安装请设置 ZAI_API_KEY，或在终端中运行"
  fi
  [[ -n "$api_key_value" ]] || die "API 密钥不能为空"
  printf '%s' "$api_key_value"
}

ensure_opencode_cli() {
  if command -v opencode >/dev/null 2>&1; then
    return 0
  fi
  if [[ "$skip_opencode_install" == "1" ]]; then
    warn "未安装 OpenCode CLI；gpt-opencode 会在安装 CLI 前拒绝运行"
    return 0
  fi
  if is_test_mode; then
    warn "测试模式下跳过 OpenCode CLI 自动安装"
    return 0
  fi

  log "未检测到 OpenCode CLI，正在使用官方安装渠道安装"
  if command -v brew >/dev/null 2>&1; then
    brew install anomalyco/tap/opencode
  elif command -v npm >/dev/null 2>&1; then
    npm install -g opencode-ai@latest
  else
    require_cmd curl
    local installer_path
    installer_path="$(mktemp "${TMPDIR:-/tmp}/opencode-install.XXXXXX")"
    if ! curl -fsSL https://opencode.ai/install -o "$installer_path"; then
      rm -f "$installer_path"
      die "无法下载 OpenCode 官方安装脚本"
    fi
    if ! bash "$installer_path"; then
      rm -f "$installer_path"
      die "OpenCode 官方安装脚本执行失败"
    fi
    rm -f "$installer_path"
  fi

  if ! command -v opencode >/dev/null 2>&1 && [[ -x "$HOME/.opencode/bin/opencode" ]]; then
    export PATH="$HOME/.opencode/bin:$PATH"
  fi
  command -v opencode >/dev/null 2>&1 ||
    die "OpenCode 已安装但当前 PATH 尚不可见；请重新打开终端后再次运行安装器"
}

render_agent() {
  local source_path="$1"
  local target_path="$2"
  local catalog_line="$3"
  local model_name="$4"
  awk -v catalog_line="$catalog_line" -v model_name="$model_name" '
    {
      gsub("__CATALOG_LINE__", catalog_line)
      gsub("__GLM_MODEL__", model_name)
      print
    }
  ' "$source_path" > "$target_path"
}

render_helper() {
  local output_path="$1"
  local key_path="$2"
  cat > "$output_path" <<EOF
#!/usr/bin/env bash
# codex-hybrid:managed
set -euo pipefail
key_path="$key_path"
[[ -r "\$key_path" ]] || exit 1
IFS= read -r token < "\$key_path"
[[ -n "\$token" ]] || exit 1
printf '%s\n' "\$token"
EOF
  chmod 700 "$output_path"
}

check_conflict "$luna_agent_path" "$hybrid_managed_marker"
check_conflict "$glm_agent_path" "$hybrid_managed_marker"
check_conflict "$helper_path" "$hybrid_managed_marker"
check_conflict "$profile_path" "$hybrid_managed_marker"
check_conflict "$opencode_profile_path" "$hybrid_managed_marker"
check_conflict "$manifest_path" "$hybrid_managed_marker"
check_conflict "$gpt_glm_path" "$hybrid_managed_marker"
check_conflict "$gpt_opencode_path" "$hybrid_managed_marker"
check_conflict "$opencode_worker_path" "$hybrid_managed_marker"
if [[ -e "$opencode_config_path" ]] && ! file_has_marker "$opencode_marker_path" "$hybrid_managed_marker"; then
  [[ "$force" == "1" ]] ||
    die "已有未受管文件与 $opencode_config_path 冲突；只有明确要替换时才使用 --force"
fi
check_conflict "$opencode_marker_path" "$hybrid_managed_marker"
check_skill_conflict
assert_provider_safe_to_edit "$config_path"

if [[ "$dry_run" == "1" ]]; then
  validate_json_file "$script_dir/models/manifest.json"
  validate_json_file "$script_dir/models/glm-5.2.json"
  validate_agent_dir "$script_dir/agents"
  log "预演：不会写入任何文件"
  log "CODEX_HOME：$codex_home_dir"
  log "服务提供商配置：$config_path"
  log "Luna 代理：$luna_agent_path"
  log "GLM 代理：$glm_agent_path"
  log "技能：$skill_path"
  log "命令：$gpt_glm_path、$gpt_opencode_path"
  log "OpenCode 配置：$opencode_config_path"
  log "OpenCode worker：$opencode_worker_path"
  log "Codex：$codex_version"
  command -v opencode >/dev/null 2>&1 || [[ "$skip_opencode_install" == "1" ]] ||
    log "OpenCode CLI：缺失，正式安装时将自动安装"
  log "Sol 配置档案：$profile_path"
  [[ -n "$catalog_abs" ]] && log "GLM 模型目录：$catalog_abs"
  exit 0
fi

ensure_opencode_cli
opencode_command="$(command -v opencode 2>/dev/null || true)"
api_key="$(read_api_key)"
mkdir -p "$codex_home_dir"
if [[ "$codex_version" == "not-installed" ]] && command -v codex >/dev/null 2>&1; then
  codex_version="$(codex --version)"
fi
lock_path="$codex_home_dir/.codex-hybrid.install.lock"
mkdir "$lock_path" 2>/dev/null || die "另一个 codex-hybrid 安装操作正在运行：$lock_path"
stage_root="$(mktemp -d "${TMPDIR:-/tmp}/codex-hybrid-install.XXXXXX")"
trap 'rm -rf "$stage_root"; rmdir "$lock_path" 2>/dev/null || true' EXIT
stage_codex="$stage_root/codex"
stage_agents="$stage_codex/agents"
stage_skills="$stage_codex/skills"
stage_secret_dir="$stage_codex/secrets"
stage_bin="$stage_codex/bin"
stage_config="$stage_codex/config.toml"
stage_helper="$stage_bin/codex-hybrid-token"
stage_secret="$stage_secret_dir/zai_api_key"
stage_profile="$stage_codex/sol-luna.config.toml"
stage_opencode_profile="$stage_codex/sol-opencode.config.toml"
stage_manifest="$stage_codex/codex-hybrid.manifest"
stage_opencode_config="$stage_codex/opencode/opencode.json"
stage_opencode_marker="$stage_codex/opencode/.codex-hybrid-managed"
stage_gpt_glm="$stage_bin/gpt-glm"
stage_gpt_opencode="$stage_bin/gpt-opencode"
stage_opencode_worker="$stage_bin/codex-hybrid-opencode-worker"
stage_skill="$stage_skills/hybrid-dev"
mkdir -p "$stage_agents" "$stage_secret_dir" "$stage_bin" "$stage_skill" "$(dirname -- "$stage_opencode_config")"

if [[ -f "$config_path" ]]; then
  cp -p "$config_path" "$stage_config"
else
  : > "$stage_config"
fi

printf '%s\n' "$api_key" > "$stage_secret"
chmod 600 "$stage_secret"
render_helper "$stage_helper" "$stage_secret"
catalog_line=""
if [[ -n "$catalog_abs" ]]; then
  catalog_line="model_catalog_json = \"$catalog_abs\""
fi
render_agent "$script_dir/agents/luna-worker.toml" "$stage_agents/luna_worker.toml" "" "$hybrid_luna_model"
render_agent "$script_dir/agents/glm-worker.toml" "$stage_agents/glm_worker.toml" "$catalog_line" "$glm_model"
render_provider_block "$helper_path" > "$stage_root/provider.block"
upsert_provider_block "$stage_config" "$stage_root/provider.block"
cp -p "$script_dir/skills/hybrid-dev/SKILL.md" "$stage_skill/SKILL.md"
render_profile glm > "$stage_profile"
render_profile opencode "$opencode_worker_path" > "$stage_opencode_profile"
render_opencode_config "$glm_model" > "$stage_opencode_config"
printf '%s\n' "$hybrid_managed_marker" > "$stage_opencode_marker"
render_gpt_glm_launcher "$codex_home_dir" > "$stage_gpt_glm"
render_gpt_opencode_launcher "$codex_home_dir" > "$stage_gpt_opencode"
render_opencode_worker "$opencode_config_path" "$secret_path" "$glm_model" "$opencode_command" > "$stage_opencode_worker"
chmod 700 "$stage_gpt_glm" "$stage_gpt_opencode" "$stage_opencode_worker"
render_manifest "$codex_home_dir" "$skills_dir" "$commands_dir" "$opencode_worker_path" > "$stage_manifest"

validate_json_file "$script_dir/models/manifest.json"
validate_json_file "$script_dir/models/glm-5.2.json"
validate_agent_dir "$stage_agents" "$glm_model"
validate_opencode_config "$stage_opencode_config" "$glm_model"
validate_opencode_cli "$stage_opencode_config" "$api_key"
validate_managed_file "$stage_opencode_marker"
validate_managed_file "$stage_opencode_profile"
validate_managed_file "$stage_skill/SKILL.md"
validate_codex_home "$stage_codex" "1"
render_helper "$stage_helper" "$secret_path"

backup_root="$codex_home_dir/backups/codex-hybrid/$(timestamp_id)"
mkdir -p "$backup_root" "$codex_home_dir/agents" "$codex_home_dir/bin" "$codex_home_dir/secrets" "$skills_dir"
chmod 700 "$codex_home_dir/bin" "$codex_home_dir/secrets"
backup_existing "$config_path" "$backup_root" "config.toml"
backup_existing "$luna_agent_path" "$backup_root" "luna_worker.toml"
backup_existing "$glm_agent_path" "$backup_root" "glm_worker.toml"
backup_existing "$helper_path" "$backup_root" "codex-hybrid-token"
backup_existing "$secret_path" "$backup_root" "zai_api_key"
backup_existing "$profile_path" "$backup_root" "sol-luna.config.toml"
backup_existing "$opencode_profile_path" "$backup_root" "sol-opencode.config.toml"
backup_existing "$manifest_path" "$backup_root" "codex-hybrid.manifest"
backup_existing "$opencode_config_path" "$backup_root" "opencode.json"
backup_existing "$opencode_marker_path" "$backup_root" "opencode-managed-marker"
backup_existing "$gpt_glm_path" "$backup_root" "gpt-glm"
backup_existing "$gpt_opencode_path" "$backup_root" "gpt-opencode"
backup_existing "$opencode_worker_path" "$backup_root" "codex-hybrid-opencode-worker"
backup_existing "$skill_path" "$backup_root" "hybrid-dev"

transaction_targets=(
  "$config_path"
  "$luna_agent_path"
  "$glm_agent_path"
  "$helper_path"
  "$secret_path"
  "$profile_path"
  "$opencode_profile_path"
  "$opencode_config_path"
  "$opencode_marker_path"
  "$gpt_glm_path"
  "$gpt_opencode_path"
  "$opencode_worker_path"
  "$skill_path"
  "$manifest_path"
)
transaction_labels=(
  "config.toml"
  "luna_worker.toml"
  "glm_worker.toml"
  "codex-hybrid-token"
  "zai_api_key"
  "sol-luna.config.toml"
  "sol-opencode.config.toml"
  "opencode.json"
  "opencode-managed-marker"
  "gpt-glm"
  "gpt-opencode"
  "codex-hybrid-opencode-worker"
  "hybrid-dev"
  "codex-hybrid.manifest"
)
transaction_existed=()
for transaction_target in "${transaction_targets[@]}"; do
  if [[ -e "$transaction_target" ]]; then
    transaction_existed+=(1)
  else
    transaction_existed+=(0)
  fi
done
transaction_active=1

rollback_install() {
  local exit_status="${1:-1}"
  [[ "${transaction_active:-0}" == "1" ]] || exit "$exit_status"
  transaction_active=0
  set +e
  local index target backup_path
  for ((index=${#transaction_targets[@]} - 1; index >= 0; index--)); do
    target="${transaction_targets[$index]}"
    backup_path="$backup_root/${transaction_labels[$index]}"
    if [[ -d "$target" ]] && [[ ! -L "$target" ]]; then
      rm -rf -- "$target"
    elif [[ -e "$target" || -L "$target" ]]; then
      rm -f -- "$target"
    fi
    if [[ "${transaction_existed[$index]}" == "1" ]] && [[ -e "$backup_path" ]]; then
      ensure_parent_dir "$target"
      mv "$backup_path" "$target"
    fi
  done
  warn "安装失败；已回滚本次文件变更"
  exit "$exit_status"
}
trap 'rollback_install $?' ERR
trap 'rollback_install 130' INT TERM

install_file_atomic "$stage_config" "$config_path" 600
install_file_atomic "$stage_agents/luna_worker.toml" "$luna_agent_path" 600
install_file_atomic "$stage_agents/glm_worker.toml" "$glm_agent_path" 600
install_file_atomic "$stage_helper" "$helper_path" 700
install_file_atomic "$stage_secret" "$secret_path" 600
install_file_atomic "$stage_profile" "$profile_path" 600
install_file_atomic "$stage_opencode_profile" "$opencode_profile_path" 600
install_file_atomic "$stage_opencode_config" "$opencode_config_path" 600
install_file_atomic "$stage_opencode_marker" "$opencode_marker_path" 600
install_file_atomic "$stage_gpt_glm" "$gpt_glm_path" 700
install_file_atomic "$stage_gpt_opencode" "$gpt_opencode_path" 700
install_file_atomic "$stage_opencode_worker" "$opencode_worker_path" 700
if [[ -e "$skill_path" ]]; then
  mv "$skill_path" "$backup_root/hybrid-dev-live"
fi
mv "$stage_skill" "$skill_path"
install_file_atomic "$stage_manifest" "$manifest_path" 600
transaction_active=0
trap - ERR INT TERM
unset api_key

log "已安装 Sol-Luna-GLM 协作包 v$hybrid_version"
log "备份位置：$backup_root"
log "Sol 配置档案：codex --profile sol-luna"
log "OpenCode 主控档案：codex --profile sol-opencode"
log "Codex：$codex_version"
log "执行后端：luna_worker + glm_worker / OpenCode worker"
log "服务提供商：$hybrid_provider_id / $glm_model"
log "命令：gpt-glm、gpt-opencode"
if [[ ":$PATH:" != *":$commands_dir:"* ]]; then
  warn "$commands_dir 不在 PATH 中；请将它加入 shell PATH 后使用两个命令"
fi
