# Bash completion for ase (also asm, sm)
# Usage: source /path/to/completions/ase.bash

_ASE_COMPLETION_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
_ASE_ROOT=$(cd "$_ASE_COMPLETION_DIR/.." && pwd)

_ase_init_words() {
  if declare -F _init_completion >/dev/null 2>&1; then
    _init_completion -n : || return 1
    return 0
  fi
  words=("${COMP_WORDS[@]}")
  cword=$COMP_CWORD
  cur=${COMP_WORDS[COMP_CWORD]}
  prev=${COMP_WORDS[COMP_CWORD - 1]}
  return 0
}

_ase_cmd_path() {
  local invoked=$1
  if [[ $invoked == /* && -x $invoked ]]; then
    printf '%s\n' "$invoked"
    return 0
  fi
  if [[ $invoked == ./* ]]; then
    local dir base abs
    dir=$(dirname "$invoked")
    base=$(basename "$invoked")
    abs=$(cd "$dir" 2>/dev/null && pwd) || return 1
    [[ -x $abs/$base ]] && printf '%s\n' "$abs/$base"
    return 0
  fi
  command -v "$invoked" 2>/dev/null
}

_ase_script_names() {
  local ase_cmd names
  ase_cmd=$(_ase_cmd_path "${words[0]}") || return 1
  names=$("$ase_cmd" __complete_names 2>/dev/null) || return 1
  printf '%s\n' "$names"
}

_ase_hub_names() {
  local ase_cmd names
  ase_cmd=$(_ase_cmd_path "${words[0]}") || return 1
  names=$("$ase_cmd" __complete_hub_names 2>/dev/null) || return 1
  printf '%s\n' "$names"
}

_ase_canonical_cmd() {
  case "$1" in
    i) echo install ;;
    ls | l) echo list ;;
    ud | u) echo update ;;
    p) echo pull ;;
    uninstall | rm | ui) echo remove ;;
    r) echo run ;;
    se | s) echo search ;;
    id) echo installed ;;
    *) echo "$1" ;;
  esac
}

_ase() {
  local cur prev words cword
  _ase_init_words || return 0

  local cmd
  cmd=$(_ase_canonical_cmd "${words[1]:-}")

  if (( cword == 1 )); then
    COMPREPLY=($(compgen -W "list ls l update ud u search se s pull p install i remove uninstall rm ui installed id run r uninstallme help" -- "$cur"))
    return 0
  fi

  case "$cmd" in
    search)
      return 0
      ;;
    pull)
      if (( cword > 2 )); then
        return 0
      fi
      local hub_names
      hub_names=$(_ase_hub_names) || return 0
      mapfile -t COMPREPLY < <(compgen -W "$hub_names" -- "$cur")
      ;;
    uninstallme)
      if [[ $cur == -* ]]; then
        COMPREPLY=($(compgen -W "-y --yes" -- "$cur"))
      fi
      ;;
    install)
      local names
      names=$(_ase_script_names) || return 0
      if [[ $cur == -* ]]; then
        COMPREPLY=($(compgen -W "-a" -- "$cur"))
      else
        mapfile -t COMPREPLY < <(compgen -W "$names" -- "$cur")
      fi
      ;;
    remove | run)
      if [[ ${prev:-} == -- ]]; then
        return 0
      fi
      if (( cword > 2 )); then
        return 0
      fi
      local names
      names=$(_ase_script_names) || return 0
      mapfile -t COMPREPLY < <(compgen -W "$names" -- "$cur")
      ;;
  esac
}

_ASE_CLI_NAMES=(ase asm sm)

_ase_register_completions() {
  local name target
  for name in "${_ASE_CLI_NAMES[@]}"; do
    complete -F _ase -o nospace "$name" 2>/dev/null || \
      complete -F _ase "$name" 2>/dev/null || true
    target=$(command -v "$name" 2>/dev/null) || true
    if [[ -n $target && $target != "$name" ]]; then
      complete -F _ase -o nospace "$target" 2>/dev/null || \
        complete -F _ase "$target" 2>/dev/null || true
    fi
  done
  for target in "$_ASE_ROOT/ase" ./ase; do
    complete -F _ase -o nospace "$target" 2>/dev/null || \
      complete -F _ase "$target" 2>/dev/null || true
  done
}

_ase_cli_binary() {
  if [[ -x "$_ASE_ROOT/ase" ]]; then
    printf '%s\n' "$_ASE_ROOT/ase"
    return 0
  fi
  local name
  for name in "${_ASE_CLI_NAMES[@]}"; do
    command -v "$name" 2>/dev/null && return 0
  done
  return 1
}

_ase_cli_dispatch() {
  local _ase_sub
  _ase_sub=$(_ase_canonical_cmd "${1:-}")
  if [[ $_ase_sub == remove && $# -ge 2 ]]; then
    local _ase_remove_name=$2
    "$_ASE_CLI_BIN" "$@"
    local _ase_remove_status=$?
    hash -d "$_ase_remove_name" 2>/dev/null || true
    return "$_ase_remove_status"
  fi
  "$_ASE_CLI_BIN" "$@"
}

_ase_install_cli_wrapper() {
  local bin name
  bin=$(_ase_cli_binary) || return 0
  _ASE_CLI_BIN=$bin
  for name in "${_ASE_CLI_NAMES[@]}"; do
    [[ $(type -t "$name" 2>/dev/null) == function ]] && continue
    eval "$name() { _ase_cli_dispatch \"\$@\"; }"
  done
}

_ase_install_cli_wrapper
_ase_register_completions
