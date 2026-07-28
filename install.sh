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

copy_tree() {
  local src=$1
  local dest=$2
  mkdir -p "$dest"
  local item
  for item in ase lib completions script-hub LICENSE README.md; do
    if [[ -e "$src/$item" ]]; then
      cp -a "$src/$item" "$dest/"
    fi
  done
  chmod +x "$dest/ase" 2>/dev/null || true
  local hub_script
  for hub_script in "$dest/script-hub"/*; do
    [[ -f $hub_script ]] || continue
    head -n1 "$hub_script" 2>/dev/null | grep -qE '^#!' && chmod +x "$hub_script" 2>/dev/null || true
  done
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
    git -C "$dest" pull --ff-only origin "$REPO_BRANCH" 2>/dev/null || \
      git -C "$dest" reset --hard "origin/$REPO_BRANCH"
  else
    rm -rf "$dest"
    git clone --depth 1 --branch "$REPO_BRANCH" "$REPO_URL" "$dest"
  fi
  chmod +x "$dest/ase" 2>/dev/null || true
  local hub_script
  for hub_script in "$dest/script-hub"/*; do
    [[ -f $hub_script ]] || continue
    head -n1 "$hub_script" 2>/dev/null | grep -qE '^#!' && chmod +x "$hub_script" 2>/dev/null || true
  done
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
    run_as_root git -C "$dest" pull --ff-only origin "$REPO_BRANCH" 2>/dev/null || \
      run_as_root git -C "$dest" reset --hard "origin/$REPO_BRANCH"
  else
    run_as_root rm -rf "$dest"
    run_as_root git clone --depth 1 --branch "$REPO_BRANCH" "$REPO_URL" "$dest"
  fi
  run_as_root chmod +x "$dest/ase" 2>/dev/null || true
  local hub_script
  for hub_script in "$dest/script-hub"/*; do
    [[ -f $hub_script ]] || continue
    head -n1 "$hub_script" 2>/dev/null | grep -qE '^#!' && run_as_root chmod +x "$hub_script" 2>/dev/null || true
  done
}

copy_tree_as_root() {
  local src=$1
  local dest=$2
  local item
  run_as_root mkdir -p "$dest"
  for item in ase lib completions script-hub LICENSE README.md; do
    if [[ -e "$src/$item" ]]; then
      run_as_root cp -a "$src/$item" "$dest/"
    fi
  done
  run_as_root chmod +x "$dest/ase" 2>/dev/null || true
  local hub_script
  for hub_script in "$dest/script-hub"/*; do
    [[ -f $hub_script ]] || continue
    head -n1 "$hub_script" 2>/dev/null | grep -qE '^#!' && run_as_root chmod +x "$hub_script" 2>/dev/null || true
  done
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
  path_hint "$bin_dir"

  echo
  echo "安装完成。可选：启用补全"
  echo "  source \"$share_dir/completions/ase.bash\""
  echo "首次运行 ase 时会生成 ~/.config/ase/config（默认 ASE_SCRIPTS_DIR 为 $share_dir/script-hub）。"
}

main "$@"
