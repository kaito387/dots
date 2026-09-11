# dots

Zsh（Oh My Zsh、Powerlevel10k、zoxide、eza）和 tmux 配置，通过软链接部署。
仓库需要保留在固定位置；移动仓库后重新运行 `--link-only`。

## 使用

先安装 Git、curl 并克隆仓库，再运行：

```sh
./bootstrap.sh                 # 安装依赖并部署配置
./bootstrap.sh --install       # 只安装依赖
./bootstrap.sh --link-only     # 只部署，不下载、不调用 sudo
./bootstrap.sh --check         # 只检查，缺失依赖或链接错误时返回非零状态
./bootstrap.sh --chsh          # 安装、部署，并修改默认登录 shell
./bootstrap.sh --link-only --chsh  # 已安装依赖时，部署并修改默认 shell
```

默认不修改登录 shell；部署后可用 `exec zsh` 启动。`--check` 不能与 `--chsh` 同用。
自动安装支持 apt-get（Debian/Ubuntu）、pacman（Arch）和 Homebrew；
apt/pacman 分支需要 sudo 权限。其他平台可手动安装依赖后使用 `--link-only`。
目前未做各平台全新系统的端到端验证。

Oh My Zsh、主题和插件首次安装从上游下载，已有完整安装会跳过，
bootstrap 不负责更新它们，也不固定上游版本。发现不完整的安装时，
先检查并移走对应目录，再重跑；不要直接删除可能包含个人修改的目录。

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
