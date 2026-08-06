# Bash completion for ase (also asm, sm)
# Usage: source /path/to/completions/ase.bash

# zsh: strip stale bash-completion hooks (may persist across reloads).
if [[ -n ${ZSH_VERSION:-} ]]; then
  for _ase_name in sm ase asm; do
    unfunction "$_ase_name" 2>/dev/null
    complete -r "$_ase_name" 2>/dev/null
    compdef -d "$_ase_name" 2>/dev/null
  done
  unfunction _ase _ase_canonical_cmd _ase_cli_dispatch _ase_init_words 2>/dev/null
  return 0
fi

[[ -n ${_ASE_COMPLETION_LOADED:-} ]] && return 0
_ASE_COMPLETION_LOADED=1

_ase_completion_script() {
  if [[ -n ${BASH_SOURCE[0]:-} ]]; then
    printf '%s\n' "${BASH_SOURCE[0]}"
  else
    printf '%s\n' "$0"
  fi
}

_ASE_COMPLETION_DIR=$(cd "$(dirname "$(_ase_completion_script)")" && pwd)
_ASE_ROOT=$(cd "$_ASE_COMPLETION_DIR/.." && pwd)

_ase_executable_path() {
  local name=$1
  local path=""

  if type -P "$name" >/dev/null 2>&1; then
    path=$(type -P "$name")
  else
    path=$(command -v "$name" 2>/dev/null) || return 1
    [[ $(type -t "$name" 2>/dev/null) == function ]] && return 1
    [[ -n $path && $path != "$name" && -x $path ]] || return 1
  fi
  [[ -n $path && -x $path ]] && printf '%s\n' "$path"
}

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
  _ase_executable_path "$invoked"
}

_ase_script_names() {
  local ase_cmd names
  ase_cmd=$(_ase_cmd_path "${words[0]}") || return 1
  names=$(command "$ase_cmd" __complete_names 2>/dev/null) || return 1
  printf '%s\n' "$names"
}

_ase_hub_names() {
  local ase_cmd names
  ase_cmd=$(_ase_cmd_path "${words[0]}") || return 1
  names=$(command "$ase_cmd" __complete_hub_names 2>/dev/null) || return 1
  printf '%s\n' "$names"
}

_ase_canonical_cmd() {
  case "$1" in
    if) echo info ;;
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
    COMPREPLY=($(compgen -W "list ls l info if update ud u search se s pull p install i remove uninstall rm ui installed id run r uninstallme help" -- "$cur"))
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
    info)
      if (( cword > 2 )); then
        return 0
      fi
      local names
      names=$(_ase_script_names) || return 0
      mapfile -t COMPREPLY < <(compgen -W "$names" -- "$cur")
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
    target=$(_ase_executable_path "$name") || true
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
  local name path
  for name in "${_ASE_CLI_NAMES[@]}"; do
    path=$(_ase_executable_path "$name") || continue
    printf '%s\n' "$path"
    return 0
  done
  return 1
}

_ase_cli_on_path() {
  local name
  for name in "${_ASE_CLI_NAMES[@]}"; do
    _ase_executable_path "$name" >/dev/null && return 0
  done
  return 1
}

_ase_cli_dispatch() {
  local _ase_sub
  _ase_sub=$(_ase_canonical_cmd "${1:-}")
  if [[ $_ase_sub == remove && $# -ge 2 ]]; then
    local _ase_remove_name=$2
    command "$_ASE_CLI_BIN" "$@"
    local _ase_remove_status=$?
    hash -d "$_ase_remove_name" 2>/dev/null || true
    return "$_ase_remove_status"
  fi
  command "$_ASE_CLI_BIN" "$@"
}

_ase_install_cli_wrapper() {
  _ase_cli_on_path && return 0
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
