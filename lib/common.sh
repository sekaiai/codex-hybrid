#!/usr/bin/env bash
set -euo pipefail

hybrid_version="0.3.0"
hybrid_provider_id="zai_coding_plan"
hybrid_opencode_provider_id="zai-coding-plan"
hybrid_glm_model="glm-5.2"
hybrid_sol_model="gpt-5.6-sol"
hybrid_luna_model="gpt-5.6-luna"
hybrid_begin_provider="# codex-hybrid:begin provider v0.2"
hybrid_end_provider="# codex-hybrid:end provider"
hybrid_managed_marker="# codex-hybrid:managed"

lib_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/lib"
hybrid_root_dir="$(CDPATH= cd -- "$lib_dir/.." && pwd)"

log() {
  printf '[codex-hybrid] %s\n' "$*" >&2
}

warn() {
  printf '[codex-hybrid][警告] %s\n' "$*" >&2
}

die() {
  printf '[codex-hybrid][错误] %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "缺少必要命令：$1"
}

is_test_mode() {
  [[ "${CODEX_HYBRID_TEST_MODE:-0}" == "1" ]]
}

check_platform() {
  case "$(uname -s)" in
    Darwin|Linux) ;;
    *)
      is_test_mode || die "仅支持 macOS、Linux 和 Windows WSL；Windows 原生 PowerShell/CMD 不受支持"
      ;;
  esac
}

absolute_path() {
  local input_path="$1"
  if [[ "$input_path" = /* ]]; then
    printf '%s\n' "$input_path"
  else
    printf '%s/%s\n' "$(pwd)" "$input_path"
  fi
}

ensure_parent_dir() {
  mkdir -p "$(dirname -- "$1")"
}

file_has_marker() {
  local candidate="$1"
  local marker="$2"
  [[ -f "$candidate" ]] && awk -v marker="$marker" '$0 == marker { found=1 } END { exit(found ? 0 : 1) }' "$candidate"
}

copy_tree_backup() {
  local source_path="$1"
  local backup_path="$2"
  if [[ -d "$source_path" ]]; then
    cp -R "$source_path" "$backup_path"
  else
    cp -p "$source_path" "$backup_path"
  fi
}

backup_existing() {
  local source_path="$1"
  local backup_root="$2"
  local label="$3"
  [[ -e "$source_path" ]] || return 0
  mkdir -p "$backup_root"
  copy_tree_backup "$source_path" "$backup_root/$label"
}

install_file_atomic() {
  local source_path="$1"
  local target_path="$2"
  local mode="$3"
  local target_dir
  local temporary_path
  target_dir="$(dirname -- "$target_path")"
  mkdir -p "$target_dir"
  temporary_path="$(mktemp "$target_dir/.codex-hybrid.XXXXXX")"
  cp -p "$source_path" "$temporary_path"
  chmod "$mode" "$temporary_path"
  mv -f "$temporary_path" "$target_path"
}

timestamp_id() {
  printf '%s-%s\n' "$(date '+%Y%m%d-%H%M%S')" "$$"
}
