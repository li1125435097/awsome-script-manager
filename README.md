# awsome-script-manager (`ase`)

纯 Bash 实现的命令行工具：从 Git 仓库的 **script-hub** 按需拉取脚本，安装到 `PATH`，并在本地目录统一管理。

## 特性

- 通过 `data/script-hub.list` 索引远程脚本，不一次性克隆整棵 script-hub 树
- `update` / `search` / `pull` 与 `install` / `remove` 分工清晰
- 用户级（`~/bin`）或系统级（`/usr/local/bin`）安装
- Bash Tab 补全（安装脚本可自动配置）
- `uninstallme` 可干净卸载 ase 本身（不删除你已拉取的脚本文件）

## 环境要求

- Bash
- Git（`update`、`pull` 需要）
- GNU `find`（`list` 等；Linux 常见环境即可）

## 快速开始

```bash
# 1. 安装 ase（见下方「安装」）
curl -fsSL https://raw.githubusercontent.com/li1125435097/awsome-script-manager/main/install.sh | bash

# 2. 首次运行任意需配置的命令会自动生成 ~/.config/ase/config
ase update                    # 同步远程 script-hub 索引到 data/script-hub.list
ase search port               # 在索引里模糊搜索
ase pull port-open            # 拉取脚本到 ASE_SCRIPTS_DIR
ase install port-open         # 链到 ~/bin，可直接运行 port-open
ase list                      # 查看本地脚本目录
```

典型工作流：**安装 ase → 配置 `ASE_GIT_ROOT` / `ASE_SCRIPTS_DIR` → `update` → `search` → `pull` → `install`**。

## 安装

### 一键安装（推荐）

```bash
curl -fsSL https://raw.githubusercontent.com/li1125435097/awsome-script-manager/main/install.sh | bash
```

安装程序会询问 bin 目录；不指定时可选 **当前用户**（`~/bin`）或 **全局**（`/usr/local/bin`）。  
程序文件默认落在 `~/.local/share/ase` 或 `/usr/local/share/ase`。**不会**复制远程 `script-hub` 大目录，脚本请用 `ase pull` 按需拉取。

管道安装会从终端读取选项；完全非交互可设置：

| 变量 | 说明 |
|------|------|
| `ASE_INSTALL_SCOPE` | `user` 或 `global` |
| `ASE_INSTALL_BIN` | 自定义 bin 目录 |
| `ASE_INSTALL_SHARE` | 自定义 share 目录 |
| `ASE_INSTALL_COMPLETION=0` | 跳过自动写入 Tab 补全 |

### 从源码安装

```bash
git clone https://github.com/li1125435097/awsome-script-manager.git
cd awsome-script-manager
./install.sh
```

### 开发 / 临时使用

将仓库加入 `PATH`，或只链入口：

```bash
ln -sf /path/to/awsome-script-manager/ase ~/bin/ase
source /path/to/awsome-script-manager/completions/ase.bash   # 可选：补全
```

## 配置

配置文件默认路径：`~/.config/ase/config`（可通过 `ASE_CONFIG` 覆盖）。  
**环境变量优先于配置文件**；首次缺少配置时，`ase` 会生成一份默认配置。

示例：

```bash
ASE_SCRIPTS_DIR="$HOME/.local/share/ase/scripts"
ASE_GIT_ROOT="$HOME/.local/share/ase"          # 或你的 git 克隆根目录
ASE_GIT_SCRIPTS_REL="script-hub"                 # 远程脚本在仓库中的相对路径
ASE_GIT_REMOTE="origin"
ASE_GIT_BRANCH="main"
ASE_BIN_USER="$HOME/bin"
```

| 变量 | 说明 |
|------|------|
| `ASE_SCRIPTS_DIR` | 本地存放已拉取脚本的目录（必填） |
| `ASE_GIT_ROOT` | Git 仓库根；默认尝试从 `ASE_SCRIPTS_DIR` 推断 |
| `ASE_GIT_SCRIPTS_REL` | 远程 script-hub 相对路径（默认 `script-hub`） |
| `ASE_GIT_REMOTE` | 远程名（默认 `origin`） |
| `ASE_GIT_BRANCH` | 分支（默认 `main`） |
| `ASE_BIN_USER` | 用户级 install 目标（默认 `~/bin`） |
| `ASE_CONFIG` | 配置文件路径 |

本地开发克隆本仓库时，常见布局为 `ASE_SCRIPTS_DIR=<repo>/scripts`，`ASE_GIT_ROOT=<repo>`。

## 命令

```text
ase list (ls, l)              列出 ASE_SCRIPTS_DIR 中的脚本及简介
ase update (ud, u)            从远程同步 data/script-hub.list
ase search (se, s) <query>    在 script-hub 索引中模糊搜索名称
ase pull (p) <name> [...]     从远程 script-hub 拉取脚本到本地目录
ase install (i) <name> [-a]   安装到 ~/bin；-a 为 /usr/local/bin
ase remove (uninstall, rm)    移除 bin 中的符号链接（保留本地脚本文件）
ase installed (id)            列出 data/install.list 中记录过的安装
ase run (r) <name> [-- args]  运行本地脚本
ase uninstallme [-y]          卸载 ase 程序本身
```

### `update`

对 `ASE_GIT_ROOT` 执行 `git fetch`，将远程 `data/script-hub.list` 写入本地同名路径。  
拉取具体脚本前请先 `update`，否则 `search` / `pull` 可能缺少最新索引。

### `pull`

从远程 `script-hub/<name>` 写入 `ASE_SCRIPTS_DIR/<name>`。  
本地已存在同名文件时，交互式终端会询问是否覆盖；非 TTY 环境下默认跳过。

### `install` / `remove`

- `install`：在 `ASE_BIN_USER` 或 `-a` 时的 `/usr/local/bin` 创建指向脚本文件的链接；无 shebang 时会生成 wrapper。
- `remove`：仅当 bin 中的入口指向该脚本时才删除链接；**不删除** `ASE_SCRIPTS_DIR` 中的文件。
- 全局安装示例：`sudo ASE_CONFIG=~/.config/ase/config ase install mytool -a`

### `run`

```bash
ase run mytool -- --verbose
```

## 脚本约定

- 第一行可为 shebang（如 `#!/usr/bin/env bash`），便于 `install` 后直接执行。
- **简介行**：有 shebang 时取第二行，否则取第一行，供 `ase list` 展示（勿与 shebang 混用）。

## Tab 补全

`install.sh` 默认配置 Bash 补全：

- 全局：`/etc/profile.d/ase-completion.sh`、`/etc/bash_completion.d/ase`
- 用户：`~/.bashrc` 中的 marked 块

新开 shell 或重新登录后，`ase pull <Tab>`、`ase install <Tab>` 等可用。  
升级旧版本时可再运行一次 `install.sh`，或手动 source `completions/ase.bash`。

## 卸载 ase（`uninstallme`）

移除 **ase 程序安装**，**不会**删除 `ASE_SCRIPTS_DIR` 里你已 pull 的脚本：

- `data/install.list` 中记录在 `~/bin`、`/usr/local/bin` 等的脚本链接
- `ase` 自身在 PATH 中的链接
- share 目录（`~/.local/share/ase` 或 `/usr/local/share/ase` 等）
- `~/.config/ase` 与补全相关文件

```bash
ase uninstallme      # 交互确认
ase uninstallme -y   # 非交互
```

涉及 `/etc` 的路径可能需要 `sudo`。share 目录会在命令退出后由后台任务删除（因当前进程可能正在该目录中运行）。

## 仓库布局（简要）

```text
ase                 CLI 入口
lib/ase-common.sh   公共函数
completions/        Bash 补全
data/
  script-hub.list   远程 script-hub 脚本名索引
  install.list      本机 install 记录
script-hub/         仓库内示例脚本（远程同源路径）
install.sh          安装脚本
```

## License

[MIT](LICENSE)
