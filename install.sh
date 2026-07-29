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
USER_SHARE="${HOME}/.local/share/ase"
SHARE_SCRIPTS_REL="scripts"
# script-hub 为远程脚本树，体积可能很大；安装时不复制/检出，用 ase pull 按需拉取
INSTALL_SHARE_COPY_ITEMS=(ase lib completions data LICENSE README.md)
INSTALL_SHARE_SPARSE_PATHS=(ase lib completions data LICENSE README.md install.sh)

die() {
  echo "install: $*" >&2
  exit 1
}

# curl | bash 时 stdin 是管道；交互从 /dev/tty 读，且不能 exec 替换 stdin（否则管道未读完会卡住 curl）。
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
    case ${answer,,} in
      y|yes) return 0 ;;
      n|no) return 1 ;;
      *) echo "请输入 y 或 n。" ;;
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
    [[ -n $value ]] || echo "路径不能为空。"
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
    die "需要 root 权限写入 $*，请使用 sudo 或以 root 运行此脚本。"
  fi
}

install_apply_sparse_checkout() {
  local dest=$1
  local as_root=${2:-0}
  if [[ $as_root -eq 1 ]]; then
    run_as_root git -C "$dest" sparse-checkout init --cone
    run_as_root git -C "$dest" sparse-checkout set "${INSTALL_SHARE_SPARSE_PATHS[@]}"
    run_as_root rm -rf "$dest/script-hub"
  else
    git -C "$dest" sparse-checkout init --cone
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

# True if the current user can create/write under share (parent may not exist yet).
install_share_writable() {
  local share=$1
  local parent
  if [[ $(id -u) -eq 0 ]]; then
    return 0
  fi
  parent=$(dirname "$share")
  mkdir -p "$parent" 2>/dev/null || return 1
  [[ -w "$parent" ]]
}

clone_repo() {
  local dest=$1
  if ! command -v git >/dev/null 2>&1; then
    die "未找到 git，请先安装 git 或在本仓库目录内运行 ./install.sh"
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
      die "git clone 失败: $REPO_URL"
    fi
  fi
  chmod +x "$dest/ase" 2>/dev/null || true
}

clone_repo_as_root() {
  local dest=$1
  if ! command -v git >/dev/null 2>&1; then
    die "未找到 git，请先安装 git"
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
      die "git clone 失败: $REPO_URL"
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
    echo "install: 从本地复制到 $share"
    if install_share_writable "$share"; then
      copy_tree "$src" "$share"
    elif path_under_home "$share"; then
      die "无法写入 $share（请检查磁盘空间与目录权限）"
    else
      copy_tree_as_root "$src" "$share"
    fi
  else
    echo "install: 从 $REPO_URL ($REPO_BRANCH) 安装到 $share"
    if install_share_writable "$share"; then
      clone_repo "$share"
    elif path_under_home "$share"; then
      die "无法写入 $share（请检查磁盘空间与目录权限）"
    else
      clone_repo_as_root "$share"
    fi
  fi
}

install_write_ase_config() {
  local git_root=$1
  local cfg scripts_dir
  cfg=$(expand_home "${ASE_CONFIG:-$HOME/.config/ase/config}")
  if [[ -f $cfg ]]; then
    echo "install: 保留已有配置 $cfg"
    return 0
  fi
  if command -v git >/dev/null 2>&1; then
    git_root=$(git -C "$git_root" rev-parse --show-toplevel 2>/dev/null) || true
  fi
  scripts_dir=$(install_default_scripts_dir "$git_root")
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
      echo 'ASE_BIN_USER="$HOME/bin"'
    fi
  } >"$cfg"
  echo "install: 已写入 $cfg（脚本目录 $scripts_dir）"
}

link_ase() {
  local share=$1
  local bin_dir=$2
  local link="$bin_dir/ase"

  if is_system_bin_dir "$bin_dir"; then
    run_as_root mkdir -p "$bin_dir"
    run_as_root ln -sfn "$share/ase" "$link"
  else
    mkdir -p "$bin_dir" || die "无法创建目录 $bin_dir"
    [[ -w "$bin_dir" ]] || die "无法写入 $bin_dir"
    ln -sfn "$share/ase" "$link"
  fi
  echo "install: ase -> $link (指向 $share/ase)"
}

path_hint() {
  local bin_dir=$1
  case ":${PATH}:" in
    *":$bin_dir:"*) ;;
    *)
      echo "install: 请将 $bin_dir 加入 PATH，例如在 ~/.bashrc 中加入："
      echo "  export PATH=\"$bin_dir:\$PATH\""
      ;;
  esac
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
  echo "install: 已配置 Tab 补全（登录后自动生效）："
  echo "  $profile_d"
  echo "  $bash_comp_d"
}

install_bashrc_completion() {
  local share_dir=$1
  local comp_file="$share_dir/completions/ase.bash"
  local bashrc="${HOME}/.bashrc"
  local begin='# >>> ase completion >>>'
  local end='# <<< ase completion <<<'
  local tmp in_block=0

  mkdir -p "$(dirname "$bashrc")"
  touch "$bashrc"

  if grep -qF "$begin" "$bashrc" 2>/dev/null; then
    tmp=$(mktemp)
    while IFS= read -r line || [[ -n $line ]]; do
      if [[ $line == "$begin" ]]; then
        in_block=1
        printf '%s\n' "$begin"
        printf '[[ -f %q ]] && . %q\n' "$comp_file" "$comp_file"
        printf '%s\n' "$end"
        continue
      fi
      if (( in_block )); then
        [[ $line == "$end" ]] && in_block=0
        continue
      fi
      printf '%s\n' "$line"
    done < "$bashrc" > "$tmp"
    mv "$tmp" "$bashrc"
  else
    {
      echo ""
      echo "$begin"
      printf '[[ -f %q ]] && . %q\n' "$comp_file" "$comp_file"
      echo "$end"
    } >> "$bashrc"
  fi
  echo "install: 已配置 Tab 补全（写入 $bashrc，新开 shell 生效）"
}

install_enable_completion() {
  local share_dir=$1
  local comp_file="$share_dir/completions/ase.bash"

  [[ -f $comp_file ]] || {
    echo "install: 跳过补全（未找到 $comp_file）"
    return 0
  }

  if path_under_home "$share_dir"; then
    install_bashrc_completion "$share_dir"
  else
    install_global_completion "$share_dir"
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
    case ${ASE_INSTALL_SCOPE,,} in
      global|system)
        bin_dir=$GLOBAL_BIN
        share_dir="${ASE_INSTALL_SHARE:-$GLOBAL_SHARE}"
        ;;
      user|local)
        bin_dir=$(expand_home "${ASE_BIN_USER:-$USER_BIN}")
        share_dir="${ASE_INSTALL_SHARE:-$USER_SHARE}"
        ;;
      *) die "ASE_INSTALL_SCOPE 应为 global 或 user" ;;
    esac
  elif install_can_prompt; then
    echo "awsome-script-manager (ase) 安装程序"
    echo

    if prompt_yn "是否指定安装位置（可执行文件目录）？" n; then
      custom=$(read_nonempty "请输入 bin 目录路径（例如 /opt/bin 或 ~/bin）：")
      bin_dir=$(expand_home "$custom")
      if [[ $bin_dir == "$GLOBAL_BIN" || $bin_dir == /usr/local/bin || $bin_dir == /usr/bin ]]; then
        share_dir=$GLOBAL_SHARE
      else
        share_dir=$USER_SHARE
      fi
    else
      echo "  1) 当前用户 — 安装到 ~/bin"
      echo "  2) 全局     — 安装到 /usr/local/bin（可能需要 sudo）"
      while true; do
        install_read -p "请选择 [1/2]（默认 1）：" scope || true
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
          *) echo "请输入 1 或 2。" ;;
        esac
      done
    fi
  else
    bin_dir=$(expand_home "$USER_BIN")
    share_dir=$USER_SHARE
    echo "install: 非交互模式，默认安装到 $bin_dir（可设置 ASE_INSTALL_SCOPE 或 ASE_INSTALL_BIN）"
  fi

  if [[ -n ${ASE_INSTALL_SHARE:-} ]]; then
    share_dir=$(expand_home "$ASE_INSTALL_SHARE")
  fi

  install_to_share "$share_dir" "$src_root"
  link_ase "$share_dir" "$bin_dir"
  if [[ -n $src_root ]]; then
    install_write_ase_config "$src_root"
  else
    install_write_ase_config "$share_dir"
  fi
  path_hint "$bin_dir"
  if [[ ${ASE_INSTALL_COMPLETION:-1} != 0 ]]; then
    install_enable_completion "$share_dir"
  fi

  echo
  echo "安装完成。"
  if [[ ${ASE_INSTALL_COMPLETION:-1} == 0 ]]; then
    echo "补全未自动配置（ASE_INSTALL_COMPLETION=0）。可手动："
    echo "  source \"$share_dir/completions/ase.bash\""
  else
    echo "若 Tab 补全无效，请确认是交互式 bash 且补全文件存在；当前 shell 可执行："
    echo "  source \"$share_dir/completions/ase.bash\""
  fi
  echo "脚本目录为 $(install_default_scripts_dir "${src_root:-$share_dir}")。"
  echo "安装未包含 script-hub；请先 ase update，再用 ase pull <name> 按需拉取脚本。"
}

main "$@"
