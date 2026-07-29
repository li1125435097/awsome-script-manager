# awsome-script-manager (ase)

Pure Bash CLI to manage a directory of scripts synced from a Git repository.

## Install `ase`

交互式安装（推荐）：

```bash
curl -fsSL https://raw.githubusercontent.com/li1125435097/awsome-script-manager/main/install.sh | bash
```

（管道安装会自动从终端读取选项；若需完全非交互可设 `ASE_INSTALL_SCOPE=user`。）

脚本会询问是否指定 bin 目录；不指定则选择「当前用户（`~/bin`）」或「全局（`/usr/local/bin`）」。程序文件默认放在 `~/.local/share/ase` 或 `/usr/local/share/ase`。

非交互环境变量：`ASE_INSTALL_SCOPE=user|global`、`ASE_INSTALL_BIN=/path/to/bin`、`ASE_INSTALL_SHARE=/path/to/share`、`ASE_INSTALL_COMPLETION=0`（跳过自动 Tab 补全配置）。

克隆仓库后也可本地安装：

```bash
git clone https://github.com/li1125435097/awsome-script-manager.git
cd awsome-script-manager
./install.sh
```

或手动将仓库加入 `PATH`，或只链入口脚本：

```bash
ln -sf /path/to/awsome-script-manager/ase ~/bin/ase
```

`install.sh` 默认会配置 Bash Tab 补全：全局安装写入 `/etc/profile.d/ase-completion.sh` 与 `/etc/bash_completion.d/ase`；用户安装写入 `~/.bashrc`。重新 SSH 登录或新开 shell 后，`ase install <Tab>` 等即可补全。

若从旧版本升级且未重装，可再运行一次 `install.sh`，或全局安装时手动：

```bash
sudo tee /etc/profile.d/ase-completion.sh <<'EOF'
# ase completion
case $- in *i*) ;; *) return 0 ;; esac
[[ -f /usr/local/share/ase/completions/ase.bash ]] && . /usr/local/share/ase/completions/ase.bash
EOF
sudo chmod 755 /etc/profile.d/ase-completion.sh
```

克隆仓库本地开发时仍可手动加载：

```bash
source /path/to/awsome-script-manager/completions/ase.bash
```

## Configuration

Set `ASE_SCRIPTS_DIR` (required). Optional variables can live in a config file.

Default config file: `~/.config/ase/config`

Example `~/.config/ase/config`:

```bash
ASE_SCRIPTS_DIR="$HOME/src/awsome-script-manager/scripts"
ASE_GIT_ROOT="$HOME/src/awsome-script-manager"
ASE_GIT_REMOTE="origin"
ASE_GIT_BRANCH="main"
ASE_BIN_USER="$HOME/bin"
```

Environment variables override the config file.

| Variable | Description |
|----------|-------------|
| `ASE_SCRIPTS_DIR` | Local folder containing managed scripts |
| `ASE_GIT_ROOT` | Git repo root (default: detected from `ASE_SCRIPTS_DIR`) |
| `ASE_GIT_REMOTE` | Remote name (default: `origin`) |
| `ASE_GIT_BRANCH` | Branch name (default: `main`) |
| `ASE_BIN_USER` | User install dir (default: `~/bin`) |
| `ASE_CONFIG` | Path to config file |

Each script’s **second line** (or first line if there is no shebang) is its short description for `ase list`. Use `#!/usr/bin/env bash` on the first line so installed commands can run directly.

## Commands

```bash
ase list
ase update          # new remote files added; same name keeps local copy
ase update -s       # same name: overwrite local with remote
ase install mytool           # symlink to ~/bin/mytool
ase install mytool -a        # symlink to /usr/local/bin/mytool
sudo ASE_CONFIG=~/.config/ase/config ase install mytool -a
ase remove mytool
ase run mytool -- --verbose
```

### `update` behavior

- Fetches from `ASE_GIT_REMOTE` and reads files under the scripts path in the repo (relative to `ASE_GIT_ROOT`).
- Remote file, no local file → write to `ASE_SCRIPTS_DIR` (basename only).
- Same basename locally → keep local unless `-s` (save remote).
- Local-only files are never deleted.

### `install` / `remove`

- `install` creates a symlink to the script file.
- `remove` removes symlinks in `~/bin` and `/usr/local/bin` only when they point at that script (the file in `ASE_SCRIPTS_DIR` is kept).

### `uninstallme`

Removes the packaged **ase** install (not your script files in `ASE_SCRIPTS_DIR`):

- Symlinks for scripts listed in `data/install.list` under `~/bin` and `/usr/local/bin`
- `ase` in `/usr/local/bin`, `/usr/bin`, and `~/bin` (when pointing at the share tree)
- Share tree (`/usr/local/share/ase` or `~/.local/share/ase`, plus paths from config / `which ase`)
- `~/.config/ase`
- Tab completion hooks: `/etc/profile.d/ase-completion.sh`, `/etc/bash_completion.d/ase`, and the `~/.bashrc` block from `install.sh`

```bash
ase uninstallme      # interactive confirm
ase uninstallme -y   # non-interactive
```

Global paths under `/etc` require `sudo` when not root. Share removal is deferred until after the command exits (the running `ase` binary lives in that tree).

## Tab completion

After install (or after sourcing `completions/ase.bash` in a dev checkout), `ase run <Tab>` completes script names from `ASE_SCRIPTS_DIR`. `install`, `remove`, `pull`, and subcommands are completed similarly. Set `ASE_INSTALL_COMPLETION=0` when running `install.sh` to skip writing profile/bashrc hooks.
