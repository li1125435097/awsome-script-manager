# awsome-script-manager (ase)

Pure Bash CLI to manage a directory of scripts synced from a Git repository.

## Install `ase`

交互式安装（推荐）：

```bash
curl -fsSL https://raw.githubusercontent.com/li1125435097/awsome-script-manager/main/install.sh | bash
```

（管道安装会自动从终端读取选项；若需完全非交互可设 `ASE_INSTALL_SCOPE=user`。）

脚本会询问是否指定 bin 目录；不指定则选择「当前用户（`~/bin`）」或「全局（`/usr/local/bin`）」。程序文件默认放在 `~/.local/share/ase` 或 `/usr/local/share/ase`。

非交互环境变量：`ASE_INSTALL_SCOPE=user|global`、`ASE_INSTALL_BIN=/path/to/bin`、`ASE_INSTALL_SHARE=/path/to/share`。

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

Enable tab completion (Git Bash / Linux):

```bash
source /path/to/awsome-script-manager/completions/ase.bash
```

## Configuration

Set `ASE_SCRIPTS_DIR` (required). Optional variables can live in a config file.

Default config file: `~/.config/ase/config`

Example `~/.config/ase/config`:

```bash
ASE_SCRIPTS_DIR="$HOME/scripts"
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

## Tab completion

After sourcing `completions/ase.bash`, `ase run <Tab>` completes script names from `ASE_SCRIPTS_DIR`. `install`, `remove`, and subcommands are completed similarly.
