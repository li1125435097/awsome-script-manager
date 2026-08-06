#!/usr/bin/env bash
# Install ase: clone or copy repo, symlink ase into a bin directory.
# Local:  ./install.sh
# Remote: curl -fsSL https://raw.githubusercontent.com/li1125435097/awsome-script-manager/main/install.sh | bash
set -euo pipefail

REPO_URL="${ASE_INSTALL_REPO:-https://github.com/li1125435097/awsome-script-manager.git}"
REPO_BRANCH="${ASE_INSTALL_BRANCH:-main}"

GLOBAL_BIN="/usr/local/bin"
GLOBAL_SHARE="/usr/local/share/ase"
USER_BIN="${HOME}/bin"

install_user_share_default() {
  if [[ -n ${XDG_DATA_HOME:-} ]]; then
    printf '%s/ase' "${XDG_DATA_HOME%/}"
  elif [[ $(uname -s) == Darwin ]]; then
    printf '%s/Library/Application Support/ase' "$HOME"
  else
    printf '%s/.local/share/ase' "$HOME"
  fi
}

USER_SHARE=$(install_user_share_default)
SHARE_SCRIPTS_REL="scripts"
# script-hub 为远程脚本树，体积可能很大；安装时不复制/检出，用 ase pull 按需拉取 (remote script tree; not copied at install — use ase pull)
INSTALL_SHARE_COPY_ITEMS=(ase lib completions data algorithm LICENSE README.md)
# Root-level files need a leading slash in non-cone sparse checkout (ase is a file, not a dir).
INSTALL_SHARE_SPARSE_PATHS=(/ase /lib /completions /data /algorithm /LICENSE /README.md /install.sh)

die() {
  echo "install: $*" >&2
  exit 1
}

tolower() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

# curl | bash 时 stdin 是管道；交互从 /dev/tty 读，且不能 exec 替换 stdin（否则管道未读完会卡住 curl）(pipe install: read prompts from /dev/tty)
install_can_prompt() {
  [[ -t 0 ]] && return 0
  [[ -r /dev/tty && -w /dev/tty ]]
}

install_read() {
  if [[ -t 0 ]]; then
    read -r "$@"
  elif [[ -r /dev/tty ]]; then
    read -r "$@" </dev/tty
  else
    return 1
  fi
}

prompt_yn() {
  local question=$1
  local default=${2:-n}
  local hint answer
  if [[ $default == y ]]; then
    hint="[Y/n]"
  else
    hint="[y/N]"
  fi
  while true; do
    install_read -p "$question $hint " answer || true
    answer=${answer:-$default}
    case $(tolower "$answer") in
      y|yes) return 0 ;;
      n|no) return 1 ;;
      *) echo "请输入 y 或 n。(Please enter y or n.)" ;;
    esac
  done
}

read_nonempty() {
  local prompt=$1
  local value=""
  while [[ -z $value ]]; do
    install_read -p "$prompt" value || true
    value=${value/#"${value%%[![:space:]]*}"}
    value=${value%"${value##*[![:space:]]}"}
    [[ -n $value ]] || echo "路径不能为空。(Path cannot be empty.)"
  done
  printf '%s\n' "$value"
}

expand_home() {
  local p=$1
  if [[ $p == "~" ]]; then
    printf '%s\n' "$HOME"
  elif [[ $p == "~/"* ]]; then
    printf '%s\n' "${HOME}/${p#~/}"
  else
    printf '%s\n' "$p"
  fi
}

# Managed scripts live under ASE_GIT_ROOT (override with ASE_INSTALL_SCRIPTS).
install_default_scripts_dir() {
  local git_root=$1
  expand_home "${ASE_INSTALL_SCRIPTS:-$git_root/$SHARE_SCRIPTS_REL}"
}

install_user_scripts_dir() {
  local share_dir=$1
  local dir="$share_dir/scripts"
  if install_dir_writable "$dir"; then
    printf '%s\n' "$dir"
    return 0
  fi
  dir="$share_dir/user-scripts"
  install_dir_writable "$dir" || \
    die "无法写入脚本目录 ${share_dir}/scripts 或 ${share_dir}/user-scripts (Cannot write scripts directory)"
  printf '%s\n' "$dir"
}

install_config_get_scripts_dir() {
  local cfg=$1
  local line
  [[ -f $cfg ]] || return 1
  line=$(grep -E '^ASE_SCRIPTS_DIR=' "$cfg" 2>/dev/null | tail -1) || return 1
  line=${line#ASE_SCRIPTS_DIR=}
  line=${line#\"}
  line=${line%\"}
  printf '%s\n' "$line"
}

install_update_config_scripts_dir() {
  local cfg=$1
  local scripts_dir=$2
  local tmp
  tmp=$(mktemp)
  while IFS= read -r line || [[ -n $line ]]; do
    if [[ $line == ASE_SCRIPTS_DIR=* ]]; then
      printf 'ASE_SCRIPTS_DIR=%q\n' "$scripts_dir"
    else
      printf '%s\n' "$line"
    fi
  done < "$cfg" > "$tmp"
  mv "$tmp" "$cfg"
}

detect_src_root() {
  local script=$1
  [[ -n $script && -f $script ]] || return 1
  local dir
  dir=$(cd "$(dirname "$script")" && pwd)
  [[ -f "$dir/ase" && -f "$dir/lib/ase-common.sh" ]] || return 1
  printf '%s\n' "$dir"
}

path_under_home() {
  local path=$1
  [[ $path == "$HOME"/* || $path == "$HOME" ]]
}

is_system_bin_dir() {
  local bin_dir=$1
  [[ $bin_dir == "$GLOBAL_BIN" || $bin_dir == /usr/local/bin || $bin_dir == /usr/bin ]]
}

run_as_root() {
  if [[ $(id -u) -eq 0 ]]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  else
    die "需要 root 权限写入 $*，请使用 sudo 或以 root 运行此脚本。(Root privileges required; use sudo or run as root.)"
  fi
}

install_apply_sparse_checkout() {
  local dest=$1
  local as_root=${2:-0}
  if [[ $as_root -eq 1 ]]; then
    run_as_root git -C "$dest" sparse-checkout init --no-cone
    run_as_root git -C "$dest" sparse-checkout set "${INSTALL_SHARE_SPARSE_PATHS[@]}"
    run_as_root rm -rf "$dest/script-hub"
  else
    git -C "$dest" sparse-checkout init --no-cone
    git -C "$dest" sparse-checkout set "${INSTALL_SHARE_SPARSE_PATHS[@]}"
    rm -rf "$dest/script-hub"
  fi
}

copy_tree() {
  local src=$1
  local dest=$2
  mkdir -p "$dest"
  local item
  for item in "${INSTALL_SHARE_COPY_ITEMS[@]}"; do
    if [[ -e "$src/$item" ]]; then
      cp -a "$src/$item" "$dest/"
    fi
  done
  chmod +x "$dest/ase" 2>/dev/null || true
}

# True if the current user can create/write under dir.
install_dir_writable() {
  local dir=$1
  local parent probe

  if [[ $(id -u) -eq 0 ]]; then
    return 0
  fi

  parent=$(dirname "$dir")
  if ! mkdir -p "$parent" 2>/dev/null; then
    return 1
  fi

  if [[ -e $dir ]]; then
    [[ -w $dir ]] || return 1
  elif ! [[ -w $parent ]]; then
    return 1
  fi

  if ! mkdir -p "$dir" 2>/dev/null; then
    return 1
  fi
  probe="$dir/.ase-install-probe.$$"
  if : >"$probe" 2>/dev/null; then
    rm -f "$probe"
    return 0
  fi
  return 1
}

install_share_writable() {
  install_dir_writable "$1"
}

install_path_owner() {
  local path=$1
  if stat -c '%U' "$path" >/dev/null 2>&1; then
    stat -c '%U' "$path"
  elif stat -f '%Su' "$path" >/dev/null 2>&1; then
    stat -f '%Su' "$path"
  else
    return 1
  fi
}

install_share_write_die() {
  local share_path=${1:?install_share_write_die: missing share path}
  local parent owner msg
  parent=$(dirname "$share_path")
  msg="无法写入 ${share_path}（请检查磁盘空间与目录权限）(Cannot write to ${share_path}; check disk space and permissions)"
  if [[ -d $parent ]]; then
    msg=$msg$'\n'"install: 父目录权限 (parent): $(ls -ld "$parent" 2>/dev/null || echo '?')"
  fi
  if [[ -e $share_path ]]; then
    msg=$msg$'\n'"install: 目标路径 (target): $(ls -ld "$share_path" 2>/dev/null || echo '?')"
  fi
  if [[ -e $parent || -e $share_path ]]; then
    owner=$(install_path_owner "$share_path" 2>/dev/null || install_path_owner "$parent" 2>/dev/null || true)
    if [[ -n $owner && $owner != "$(id -un)" ]]; then
      msg=$msg$'\n'"install: 目录属主为 ${owner}，当前用户为 $(id -un)。可尝试：(Owner is ${owner}; current user is $(id -un). Try:)"
      msg=$msg$'\n'"install:   sudo chown -R $(id -un):$(id -gn) $(printf '%q' "$parent")"
      msg=$msg$'\n'"install: 或删除后重装 (or remove and reinstall): sudo rm -rf $(printf '%q' "$share_path")"
    elif [[ -e $parent && ! -w $parent ]]; then
      msg=$msg$'\n'"install: 父目录不可写 (parent not writable)。若 ~/.local 属主为 root，可执行：(If ~/.local is root-owned, run:)"
      msg=$msg$'\n'"install:   sudo chown -R $(id -un):$(id -gn) $(printf '%q' "$parent")"
    fi
  fi
  die "$msg"
}

install_mac_share_fallback() {
  printf '%s/Library/Application Support/ase' "$HOME"
}

install_resolve_share_dir() {
  local preferred=$1 fallback
  preferred=$(expand_home "$preferred")
  if install_share_writable "$preferred"; then
    printf '%s\n' "$preferred"
    return 0
  fi
  fallback=$(install_user_share_default)
  if [[ $preferred != "$fallback" ]] && install_share_writable "$fallback"; then
    echo "install: ${preferred} 不可写，改用 ${fallback} (${preferred} not writable; using ${fallback})" >&2
    printf '%s\n' "$fallback"
    return 0
  fi
  if [[ $(uname -s) == Darwin ]]; then
    fallback=$(install_mac_share_fallback)
    if [[ $preferred != "$fallback" ]] && install_share_writable "$fallback"; then
      echo "install: ${preferred} 不可写，改用 ${fallback} (${preferred} not writable; using ${fallback})" >&2
      printf '%s\n' "$fallback"
      return 0
    fi
  fi
  if path_under_home "$preferred"; then
    install_share_write_die "$preferred"
  fi
  printf '%s\n' "$preferred"
}

install_user_bin_fallback() {
  printf '%s/bin' "$(install_user_share_default)"
}

install_resolve_bin_dir() {
  local preferred=$1
  preferred=$(expand_home "$preferred")
  if is_system_bin_dir "$preferred"; then
    printf '%s\n' "$preferred"
    return 0
  fi
  if install_dir_writable "$preferred"; then
    printf '%s\n' "$preferred"
    return 0
  fi
  if [[ $(uname -s) == Darwin ]]; then
    local fallback
    fallback=$(install_user_bin_fallback)
    if [[ $preferred != "$fallback" ]] && install_dir_writable "$fallback"; then
      echo "install: ${preferred} 不可写，改用 ${fallback} (${preferred} not writable; using ${fallback})" >&2
      printf '%s\n' "$fallback"
      return 0
    fi
  fi
  die "无法写入 ${preferred}（请检查目录权限）(Cannot write to ${preferred}; check permissions)"
}

clone_repo() {
  local dest=$1
  if ! command -v git >/dev/null 2>&1; then
    die "未找到 git，请先安装 git 或在本仓库目录内运行 ./install.sh。(git not found; install git or run ./install.sh from a clone.)"
  fi
  mkdir -p "$(dirname "$dest")"
  if [[ -d "$dest/.git" ]]; then
    git -C "$dest" fetch origin "$REPO_BRANCH"
    git -C "$dest" checkout "$REPO_BRANCH" 2>/dev/null || git -C "$dest" checkout -B "$REPO_BRANCH" "origin/$REPO_BRANCH"
    install_apply_sparse_checkout "$dest" 0
    git -C "$dest" pull --ff-only origin "$REPO_BRANCH" 2>/dev/null || \
      git -C "$dest" reset --hard "origin/$REPO_BRANCH"
    install_apply_sparse_checkout "$dest" 0
  else
    rm -rf "$dest"
    if git clone --depth 1 --branch "$REPO_BRANCH" --filter=blob:none --sparse "$REPO_URL" "$dest" 2>/dev/null; then
      install_apply_sparse_checkout "$dest" 0
    elif git clone --depth 1 --branch "$REPO_BRANCH" "$REPO_URL" "$dest"; then
      install_apply_sparse_checkout "$dest" 0
    else
      die "git clone 失败 (git clone failed): $REPO_URL"
    fi
  fi
  chmod +x "$dest/ase" 2>/dev/null || true
}

clone_repo_as_root() {
  local dest=$1
  if ! command -v git >/dev/null 2>&1; then
    die "未找到 git，请先安装 git。(git not found; install git first.)"
  fi
  run_as_root mkdir -p "$(dirname "$dest")"
  if run_as_root test -d "$dest/.git"; then
    run_as_root git -C "$dest" fetch origin "$REPO_BRANCH"
    run_as_root git -C "$dest" checkout "$REPO_BRANCH" 2>/dev/null || \
      run_as_root git -C "$dest" checkout -B "$REPO_BRANCH" "origin/$REPO_BRANCH"
    install_apply_sparse_checkout "$dest" 1
    run_as_root git -C "$dest" pull --ff-only origin "$REPO_BRANCH" 2>/dev/null || \
      run_as_root git -C "$dest" reset --hard "origin/$REPO_BRANCH"
    install_apply_sparse_checkout "$dest" 1
  else
    run_as_root rm -rf "$dest"
    if run_as_root git clone --depth 1 --branch "$REPO_BRANCH" --filter=blob:none --sparse "$REPO_URL" "$dest" 2>/dev/null; then
      install_apply_sparse_checkout "$dest" 1
    elif run_as_root git clone --depth 1 --branch "$REPO_BRANCH" "$REPO_URL" "$dest"; then
      install_apply_sparse_checkout "$dest" 1
    else
      die "git clone 失败 (git clone failed): $REPO_URL"
    fi
  fi
  run_as_root chmod +x "$dest/ase" 2>/dev/null || true
}

copy_tree_as_root() {
  local src=$1
  local dest=$2
  local item
  run_as_root mkdir -p "$dest"
  for item in "${INSTALL_SHARE_COPY_ITEMS[@]}"; do
    if [[ -e "$src/$item" ]]; then
      run_as_root cp -a "$src/$item" "$dest/"
    fi
  done
  run_as_root chmod +x "$dest/ase" 2>/dev/null || true
}

install_to_share() {
  local share=$1
  local src=${2:-}

  if [[ -n $src ]]; then
    echo "install: 从本地复制到 $share (copying from local tree to $share)"
    if install_share_writable "$share"; then
      copy_tree "$src" "$share"
    elif path_under_home "$share"; then
      install_share_write_die "$share"
    else
      copy_tree_as_root "$src" "$share"
    fi
  else
    echo "install: 从 $REPO_URL ($REPO_BRANCH) 安装到 $share (installing from remote to $share)"
    if install_share_writable "$share"; then
      clone_repo "$share"
    elif path_under_home "$share"; then
      install_share_write_die "$share"
    else
      clone_repo_as_root "$share"
    fi
  fi
}

install_write_ase_config() {
  local git_root=$1
  local bin_dir=$2
  local share_dir=${3:-}
  local cfg scripts_dir prev_scripts
  cfg=$(expand_home "${ASE_CONFIG:-$HOME/.config/ase/config}")

  if [[ -f $cfg ]]; then
    prev_scripts=$(install_config_get_scripts_dir "$cfg" 2>/dev/null) || prev_scripts=""
    if [[ -n $share_dir && -n $prev_scripts && ! -w $prev_scripts ]]; then
      share_dir=$(expand_home "$share_dir")
      scripts_dir=$(install_user_scripts_dir "$share_dir")
      install_update_config_scripts_dir "$cfg" "$scripts_dir"
      echo "install: 已将脚本目录改为 ${scripts_dir}（原 ${prev_scripts} 不可写）(Updated scripts dir; previous path not writable)"
    else
      echo "install: 保留已有配置 ${cfg} (keeping existing config)"
    fi
    return 0
  fi

  if command -v git >/dev/null 2>&1; then
    git_root=$(git -C "$git_root" rev-parse --show-toplevel 2>/dev/null) || true
  fi
  if [[ -n $share_dir ]]; then
    share_dir=$(expand_home "$share_dir")
    scripts_dir=$(install_user_scripts_dir "$share_dir")
  else
    scripts_dir=$(install_default_scripts_dir "$git_root")
  fi
  mkdir -p "$(dirname "$cfg")"
  mkdir -p "$scripts_dir"
  {
    echo '# Generated by install.sh — edit as needed'
    printf 'ASE_SCRIPTS_DIR=%q\n' "$scripts_dir"
    printf 'ASE_GIT_ROOT=%q\n' "$git_root"
    echo 'ASE_GIT_SCRIPTS_REL="script-hub"'
    echo 'ASE_GIT_REMOTE="origin"'
    echo 'ASE_GIT_BRANCH="main"'
    if [[ $(id -u) -eq 0 ]]; then
      printf 'ASE_BIN_USER=%q\n' "$GLOBAL_BIN"
    else
      printf 'ASE_BIN_USER=%q\n' "$bin_dir"
    fi
  } >"$cfg"
  echo "install: 已写入 ${cfg}（脚本目录 ${scripts_dir}）(wrote config; scripts dir: ${scripts_dir})"
}

link_ase() {
  local share=$1
  local bin_dir=$2
  local name link

  if is_system_bin_dir "$bin_dir"; then
    run_as_root mkdir -p "$bin_dir"
  else
    mkdir -p "$bin_dir" || die "无法创建目录 $bin_dir (Cannot create directory $bin_dir)"
    [[ -w "$bin_dir" ]] || die "无法写入 $bin_dir (Cannot write to $bin_dir)"
  fi

  for name in ase asm sm; do
    link="$bin_dir/$name"
    if is_system_bin_dir "$bin_dir"; then
      run_as_root ln -sfn "$share/ase" "$link"
    else
      ln -sfn "$share/ase" "$link"
    fi
    echo "install: $name -> $link (指向 $share/ase) (symlink points to $share/ase)"
  done
}

path_in_path() {
  local bin_dir=$1
  case ":${PATH}:" in
    *":$bin_dir:"*) return 0 ;;
    *) return 1 ;;
  esac
}

install_rc_update_block() {
  local rc_file=$1
  local begin=$2
  local end=$3
  local content=$4
  local tmp in_block=0 line

  mkdir -p "$(dirname "$rc_file")"
  touch "$rc_file"

  if grep -qF "$begin" "$rc_file" 2>/dev/null; then
    tmp=$(mktemp)
    while IFS= read -r line || [[ -n $line ]]; do
      if [[ $line == "$begin" ]]; then
        in_block=1
        printf '%s\n' "$begin"
        while IFS= read -r line || [[ -n $line ]]; do
          printf '%s\n' "$line"
        done <<< "$content"
        printf '%s\n' "$end"
        continue
      fi
      if (( in_block )); then
        [[ $line == "$end" ]] && in_block=0
        continue
      fi
      printf '%s\n' "$line"
    done < "$rc_file" > "$tmp"
    mv "$tmp" "$rc_file"
  else
    {
      echo ""
      echo "$begin"
      while IFS= read -r line || [[ -n $line ]]; do
        printf '%s\n' "$line"
      done <<< "$content"
      echo "$end"
    } >> "$rc_file"
  fi
}

install_user_rc_files() {
  local -a rcs=()
  [[ -f ${HOME}/.bashrc || ${SHELL:-} == */bash ]] && rcs+=("${HOME}/.bashrc")
  if [[ ${SHELL:-} == */zsh || -f ${HOME}/.zshrc ]]; then
    rcs+=("${HOME}/.zshrc")
  fi
  ((${#rcs[@]})) || rcs+=("${HOME}/.bashrc")
  printf '%s\n' "${rcs[@]}"
}

install_bashrc_path() {
  local bin_dir=$1
  local begin='# >>> ase path >>>'
  local end='# <<< ase path <<<'
  local export_line rc written=0

  path_in_path "$bin_dir" && return 0
  is_system_bin_dir "$bin_dir" && return 0

  export_line="export PATH=\"$bin_dir:\$PATH\""
  while IFS= read -r rc; do
    [[ -n $rc ]] || continue
    install_rc_update_block "$rc" "$begin" "$end" "$export_line"
    echo "install: 已将 ${bin_dir} 加入 PATH（写入 ${rc}）(Added ${bin_dir} to PATH in ${rc})"
    written=1
  done < <(install_user_rc_files)
  if (( written )); then
    echo "install: 新开 shell 生效；zsh 用户请 source ~/.zshrc，bash 用户请 source ~/.bashrc (Open a new shell, or source your shell rc file)"
  fi
}

path_hint() {
  local bin_dir=$1
  if path_in_path "$bin_dir"; then
    return 0
  fi
  if is_system_bin_dir "$bin_dir"; then
    echo "install: 请将 $bin_dir 加入 PATH。(Add $bin_dir to PATH.)"
    return 0
  fi
  install_bashrc_path "$bin_dir"
}

install_completion_wrapper_content() {
  local comp_file=$1
  local q
  q=$(printf '%q' "$comp_file")
  cat <<EOF
# ase completion (awsome-script-manager install.sh)
case \$- in
  *i*) ;;
  *) return 0 ;;
esac
_comp=$q
[[ -f \$_comp ]] && . "\$_comp"
EOF
}

install_global_completion() {
  local share_dir=$1
  local comp_file="$share_dir/completions/ase.bash"
  local profile_d="/etc/profile.d/ase-completion.sh"
  local bash_comp_d="/etc/bash_completion.d/ase"
  local content

  content=$(install_completion_wrapper_content "$comp_file")
  run_as_root mkdir -p /etc/profile.d /etc/bash_completion.d
  printf '%s\n' "$content" | run_as_root tee "$profile_d" >/dev/null
  run_as_root chmod 755 "$profile_d"
  printf '%s\n' "$content" | run_as_root tee "$bash_comp_d" >/dev/null
  echo "install: 已配置 Tab 补全（登录后自动生效）(Tab completion enabled for login shells):"
  echo "  $profile_d"
  echo "  $bash_comp_d"
}

install_bashrc_completion() {
  local share_dir=$1
  local comp_file="$share_dir/completions/ase.bash"
  local bashrc="${HOME}/.bashrc"
  local begin='# >>> ase completion >>>'
  local end='# <<< ase completion <<<'
  local content_line

  content_line=$(printf '[[ -n ${ZSH_VERSION:-} ]] || { [[ -f %q ]] && . %q; }' "$comp_file" "$comp_file")
  install_rc_update_block "$bashrc" "$begin" "$end" "$content_line"
  echo "install: 已配置 Tab 补全（写入 ${bashrc}，仅 bash 生效）(Tab completion added to ${bashrc}; bash only)"
}

install_zshrc_completion() {
  local share_dir=$1
  local comp_dir="$share_dir/completions"
  local zshrc="${HOME}/.zshrc"
  local begin='# >>> ase completion >>>'
  local end='# <<< ase completion <<<'
  local -a lines=()
  local q_comp_dir

  [[ -f $comp_dir/_ase ]] || return 0
  [[ ${SHELL:-} == */zsh || -f $zshrc ]] || return 0

  q_comp_dir=$(printf '%q' "$comp_dir")
  lines+=('unfunction _ase _ase_init_words _ase_canonical_cmd _ase_cli_dispatch 2>/dev/null')
  lines+=('for _ase_name in sm ase asm; do')
  lines+=('  unfunction "$_ase_name" 2>/dev/null')
  lines+=('  complete -r "$_ase_name" 2>/dev/null')
  lines+=('done')
  lines+=("fpath=($q_comp_dir \$fpath)")
  lines+=('autoload -Uz _ase')
  lines+=('compdef _ase ase asm sm')

  install_rc_update_block "$zshrc" "$begin" "$end" "$(printf '%s\n' "${lines[@]}")"
  echo "install: 已配置 zsh Tab 补全（写入 ${zshrc}）(zsh Tab completion added to ${zshrc})"
}

install_enable_completion() {
  local share_dir=$1
  local comp_file="$share_dir/completions/ase.bash"

  [[ -f $comp_file ]] || {
    echo "install: 跳过补全（未找到 ${comp_file}）(Skipping completion; file not found)"
    return 0
  }

  if path_under_home "$share_dir"; then
    install_bashrc_completion "$share_dir"
    install_zshrc_completion "$share_dir"
  else
    install_global_completion "$share_dir"
  fi
}

warn_root_user_install() {
  local bin_dir=$1
  if [[ $(id -u) -eq 0 ]] && ! is_system_bin_dir "$bin_dir"; then
    echo "install: 警告：当前以 root 运行且为用户级安装，文件将归 root 所有；请改用 bash install.sh（勿加 sudo）(Warning: root + user install; files will be root-owned. Use: bash install.sh without sudo)" >&2
  fi
}

main() {
  local src_root bin_dir share_dir custom scope

  src_root=$(detect_src_root "${BASH_SOURCE[0]:-}") || src_root=""

  if [[ -n ${ASE_INSTALL_BIN:-} ]]; then
    bin_dir=$(expand_home "$ASE_INSTALL_BIN")
    if [[ $bin_dir == "$GLOBAL_BIN" || $bin_dir == /usr/local/bin ]]; then
      share_dir="${ASE_INSTALL_SHARE:-$GLOBAL_SHARE}"
    else
      share_dir="${ASE_INSTALL_SHARE:-$USER_SHARE}"
    fi
  elif [[ -n ${ASE_INSTALL_SCOPE:-} ]]; then
    case $(tolower "$ASE_INSTALL_SCOPE") in
      global|system)
        bin_dir=$GLOBAL_BIN
        share_dir="${ASE_INSTALL_SHARE:-$GLOBAL_SHARE}"
        ;;
      user|local)
        bin_dir=$(expand_home "${ASE_BIN_USER:-$USER_BIN}")
        share_dir="${ASE_INSTALL_SHARE:-$USER_SHARE}"
        ;;
      *) die "ASE_INSTALL_SCOPE 应为 global 或 user (ASE_INSTALL_SCOPE must be global or user)" ;;
    esac
  elif install_can_prompt; then
    echo "awsome-script-manager (ase) 安装程序 (installer)"
    echo

    if prompt_yn "是否指定安装位置？默认否 (Specify a custom install location? default: no)" n; then
      custom=$(read_nonempty "请输入 bin 目录路径，例如 /opt/bin 或 ~/bin (Enter bin directory path, e.g. /opt/bin or ~/bin): ")
      bin_dir=$(expand_home "$custom")
      if [[ $bin_dir == "$GLOBAL_BIN" || $bin_dir == /usr/local/bin || $bin_dir == /usr/bin ]]; then
        share_dir=$GLOBAL_SHARE
      else
        share_dir=$USER_SHARE
      fi
    else
      echo "  1) 当前用户 — 安装到 ~/bin (Current user — install to ~/bin)"
      echo "  2) 全局     — 安装到 /usr/local/bin（可能需要 sudo）(System-wide — /usr/local/bin, may need sudo)"
      while true; do
        install_read -p "请选择 [1/2]，默认 1 (Choose [1/2], default 1): " scope || true
        scope=${scope:-1}
        case $scope in
          1)
            bin_dir=$(expand_home "$USER_BIN")
            share_dir=$USER_SHARE
            break
            ;;
          2)
            bin_dir=$GLOBAL_BIN
            share_dir=$GLOBAL_SHARE
            break
            ;;
          *) echo "请输入 1 或 2。(Please enter 1 or 2.)" ;;
        esac
      done
    fi
  else
    bin_dir=$(expand_home "$USER_BIN")
    share_dir=$USER_SHARE
    echo "install: 非交互模式，默认安装到 ${bin_dir}（可设置 ASE_INSTALL_SCOPE 或 ASE_INSTALL_BIN）(Non-interactive; default install to ${bin_dir}; set ASE_INSTALL_SCOPE or ASE_INSTALL_BIN)"
  fi

  if [[ -n ${ASE_INSTALL_SHARE:-} ]]; then
    share_dir=$(expand_home "$ASE_INSTALL_SHARE")
  else
    share_dir=$(install_resolve_share_dir "$share_dir")
  fi

  if ! is_system_bin_dir "$bin_dir"; then
    bin_dir=$(install_resolve_bin_dir "$bin_dir")
  fi

  warn_root_user_install "$bin_dir"
  install_to_share "$share_dir" "$src_root"
  link_ase "$share_dir" "$bin_dir"
  if [[ -n $src_root ]]; then
    install_write_ase_config "$src_root" "$bin_dir" "$share_dir"
  else
    install_write_ase_config "$share_dir" "$bin_dir" "$share_dir"
  fi
  path_hint "$bin_dir"
  if [[ ${ASE_INSTALL_COMPLETION:-1} != 0 ]]; then
    install_enable_completion "$share_dir"
  fi

  echo
  local scripts_dir_hint
  scripts_dir_hint=$(install_config_get_scripts_dir "${ASE_CONFIG:-$HOME/.config/ase/config}" 2>/dev/null) || \
    scripts_dir_hint=$(install_user_scripts_dir "$share_dir")
  echo "安装完成。(Installation complete.)"
  if [[ ${ASE_INSTALL_COMPLETION:-1} == 0 ]]; then
    echo "补全未自动配置（ASE_INSTALL_COMPLETION=0）。可手动：(Completion not configured; load manually:)"
    echo "  source \"$share_dir/completions/ase.bash\""
  else
    echo "若 Tab 补全无效，请确认是交互式 bash 且补全文件存在；当前 shell 可执行：(If Tab completion fails, use an interactive bash; for this shell:)"
    echo "  source \"$share_dir/completions/ase.bash\""
  fi
  echo "脚本目录为 ${scripts_dir_hint}。(Scripts directory: ${scripts_dir_hint})"
  echo "安装未包含 script-hub；请先 ase update，再用 ase pull <name> 按需拉取脚本。(script-hub not included; run ase update, then ase pull <name> as needed.)"
}

main "$@"
