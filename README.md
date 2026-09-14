# dots

Zsh（Oh My Zsh、Powerlevel10k、zoxide、eza）和 tmux 配置，通过软链接部署。
仓库需要保留在固定位置；移动仓库后重新运行 `--link-only`。

## 使用

先以需要配置的普通用户登录，安装 Git、curl 并把仓库克隆到该用户可访问的目录，再运行。
**不要使用 `sudo ./bootstrap.sh`，也不要在 root shell 中运行。** 脚本会显示实际用户和
目标 HOME，拒绝 root 身份，以及不存在、不属于当前用户或不可写的 HOME。
安装系统软件时，脚本内部会按需调用 sudo；用户配置由普通用户创建。
若导出了指向其他目录的 `ZDOTDIR`，脚本会报错，避免 zsh 跳过部署到 HOME 的 `.zshrc`。

```sh
./bootstrap.sh                 # 安装依赖并部署配置
./bootstrap.sh --install       # 只安装依赖
./bootstrap.sh --link-only     # 只部署，不下载、不调用 sudo
./bootstrap.sh --check         # 只检查，缺失依赖或链接错误时返回非零状态
./bootstrap.sh --chsh          # 安装、部署，并修改默认登录 shell
./bootstrap.sh --link-only --chsh  # 已安装依赖时，部署并修改默认 shell
```

默认不修改登录 shell；部署后可用 `exec zsh` 启动。`--check` 不能与 `--chsh` 同用。
“部署完成”表示配置文件已经链接，不代表当前 Bash 会话已切换成 zsh。
`--check` 检查当前用户的链接、依赖和已有默认历史文件的读写权限，不检查正在运行的 shell。
自动安装支持 apt-get（Debian/Ubuntu）、pacman（Arch）和 Homebrew；
apt/pacman 分支需要 sudo 权限。其他平台可手动安装依赖后使用 `--link-only`。
目前未做各平台全新系统的端到端验证。

Oh My Zsh、主题和插件首次安装从上游下载，已有完整安装会跳过，
bootstrap 不负责更新它们，也不固定上游版本。发现不完整的安装时，
先检查并移走对应目录，再重跑；不要直接删除可能包含个人修改的目录。

## 曾经误给 root 配置时

root 和普通用户各自拥有 HOME、Oh My Zsh、插件、配置及历史记录。
root 下安装成功不能说明 lht 已配置。系统包安装的 eza 通常可供其他用户使用，
但 root 私有目录中的二进制和 `.zshrc` 中的别名不会自动出现在 lht 的环境中。

如果当前在 root shell，先切换登录身份：

```sh
su - lht
```

然后在 lht 的终端里确认身份并运行更新后的仓库脚本（仓库路径不同则替换）：

```sh
id -un                         # 应为 lht
printf '%s\n' "$HOME"           # 应为 /home/lht
cd /home/lht/dev/dots
./bootstrap.sh --chsh           # 不加 sudo，为 lht 安装、部署并设置登录 shell
./bootstrap.sh --check
exec zsh                       # 加载当前终端；也可以重新登录
```

若仓库只在 `/root` 下，应先以 lht 身份克隆到自己的目录；不要把 lht 的配置链接到 `/root`。
也不要把 root 的 HOME 或整个 `.oh-my-zsh` 直接复制给 lht。
如果之前使用 `sudo -E` 等方式保留了 lht 的 HOME，检查报错路径的所有者和权限，
仅修复确认属于 lht 的文件；脚本不会递归更改整个 HOME 的所有权。

进入 zsh 后可用 `command -v eza`、`whence -w z` 验证命令，用
`(( $+functions[_zsh_autosuggest_start] ))` 检查历史建议插件是否加载。
新用户的历史建议需要先执行一些命令；不会自动继承 root 或 Bash 的历史记录。

## 部署与恢复

| 仓库文件 | 目标 |
| --- | --- |
| `zsh/zshrc` | `~/.zshrc` |
| `zsh/p10k.zsh` | `~/.p10k.zsh` |
| `tmux/tmux.conf` | `~/.tmux.conf` |
| `tmux/clipboard-copy.sh` | `~/.tmux/clipboard-copy.sh` |

正确的软链接会跳过。发生冲突时，原文件、目录或软链接会移入目标旁的
`<目标>.backup.XXXXXXXX/original`，日志会打印准确位置；已有 `.bak` 不会被覆盖。
恢复时先确认目标仍是本仓库部署的软链接，移除该链接，再把对应备份的
`original` 移回目标路径。多次备份需自行选择要恢复的版本。
一次部署中若后面的文件失败，前面已完成的链接仍会保留，可修复后重跑。

## 本机设置与剪贴板

机器专用配置放在 `~/.zshrc.local`，不纳入本仓库。它在 Oh My Zsh 和提示符配置之后、
zoxide 初始化之前加载，可用于设置 PATH、编辑器、别名或 zoxide 选项。
`~/.local/bin` 自动加入 PATH；未安装 eza 时不覆盖 `ls`。
终端的 Nerd Font 需自行安装和选择。

tmux 前缀是 `Ctrl-a`，按前缀后再按 `Ctrl-c` 可复制当前 tmux buffer：

- Wayland：安装 `wl-clipboard`，会话须有 `WAYLAND_DISPLAY`。
- X11：安装 `xclip`，会话须有 `DISPLAY`。
- macOS：使用系统 `pbcopy`。

剪贴板工具是可选依赖，bootstrap 只报告缺失；SSH 会话需要可用的显示转发或其他剪贴板方案。
修改 tmux 配置后，按前缀再按 `r` 重新加载。

## 验证

```sh
bash -n bootstrap.sh
sh -n tmux/clipboard-copy.sh
zsh -n zsh/zshrc
zsh -n zsh/p10k.zsh
python3 -m unittest discover -s tests -v
```

回归测试使用临时目录和模拟安装命令，不修改实际用户配置或系统软件。
