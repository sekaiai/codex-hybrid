#!/usr/bin/env bash
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
source "$script_dir/lib/common.sh"
source "$script_dir/lib/config.sh"

purge_secret=0
usage() {
  cat <<EOF
用法：$0 [--purge-secret]

移除 codex-hybrid 管理的文件和服务提供商配置块。
已有文件会移动到 CODEX_HOME/backups 下按时间戳命名的备份目录。
--purge-secret 永久删除当前的 ZAI 密钥文件。
EOF
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --purge-secret) purge_secret=1 ;;
    -h|--help) usage; exit 0 ;;
    *) die "未知选项：$1" ;;
  esac
  shift
done

check_platform
require_cmd awk
require_cmd cp
require_cmd find
require_cmd mv
require_cmd stat
codex_home_dir="${CODEX_HOME:-$HOME/.codex}"
skills_dir="${CODEX_HYBRID_SKILLS_DIR:-$HOME/.agents/skills}"
config_path="$codex_home_dir/config.toml"
secret_path="$codex_home_dir/secrets/zai_api_key"
helper_path="$codex_home_dir/bin/codex-hybrid-token"
profile_path="$codex_home_dir/sol-luna.config.toml"
luna_agent_path="$codex_home_dir/agents/luna_worker.toml"
glm_agent_path="$codex_home_dir/agents/glm_worker.toml"
skill_path="$skills_dir/hybrid-dev"
manifest_path="$codex_home_dir/codex-hybrid.manifest"

[[ -d "$codex_home_dir" ]] || die "CODEX_HOME 不存在：$codex_home_dir"
lock_path="$codex_home_dir/.codex-hybrid.install.lock"
mkdir "$lock_path" 2>/dev/null || die "另一个 codex-hybrid 操作正在运行：$lock_path"
trap 'rmdir "$lock_path" 2>/dev/null || true' EXIT
backup_root="$codex_home_dir/backups/codex-hybrid-uninstall/$(timestamp_id)"
mkdir -p "$backup_root"

if [[ -f "$config_path" ]]; then
  provider_block_state "$config_path" || case "$?" in
    1) : ;;
    2) die "服务提供商标记在 $config_path 中不完整或重复" ;;
    3) die "发现未受管的服务提供商配置块，拒绝移除" ;;
    *) die "无法检查 $config_path" ;;
  esac
  if provider_block_state "$config_path"; then
    cp -p "$config_path" "$backup_root/config.toml"
    remove_provider_block "$config_path"
  fi
fi

move_managed_file() {
  local source_path="$1"
  local label="$2"
  [[ -e "$source_path" ]] || return 0
  if file_has_marker "$source_path" "$hybrid_managed_marker"; then
    mv "$source_path" "$backup_root/$label"
    log "已将 $source_path 移动到备份目录"
  else
    warn "保留未受管文件不变：$source_path"
  fi
}

move_managed_file "$luna_agent_path" "luna_worker.toml"
move_managed_file "$glm_agent_path" "glm_worker.toml"
move_managed_file "$helper_path" "codex-hybrid-token"
move_managed_file "$profile_path" "sol-luna.config.toml"
move_managed_file "$manifest_path" "codex-hybrid.manifest"

if [[ -d "$skill_path" ]]; then
  if file_has_marker "$skill_path/SKILL.md" "$hybrid_managed_marker"; then
    mv "$skill_path" "$backup_root/hybrid-dev"
    log "已将 $skill_path 移动到备份目录"
  else
    warn "保留未受管技能不变：$skill_path"
  fi
fi

if [[ -f "$secret_path" ]]; then
  if [[ "$purge_secret" == "1" ]]; then
    rm -f "$secret_path"
    log "已永久删除当前密钥：$secret_path"
  else
    mv "$secret_path" "$backup_root/zai_api_key"
    log "已将当前密钥移至备份目录；如需永久删除请使用 --purge-secret"
  fi
fi

log "卸载完成；可恢复备份位置：$backup_root"
