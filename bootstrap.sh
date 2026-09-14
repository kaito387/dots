#!/usr/bin/env bash
# bootstrap.sh — bootstrap for Kaito387/dots
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_HOME="$HOME"
CONFIG_SOURCES=(zsh/zshrc zsh/p10k.zsh tmux/tmux.conf tmux/clipboard-copy.sh)
CONFIG_TARGETS=(.zshrc .p10k.zsh .tmux.conf .tmux/clipboard-copy.sh)

# ── pretty logs ───────────────────────────────────────────────────────────────
info()    { printf '\033[1;34m[INFO]\033[0m  %s\n' "$*"; }
success() { printf '\033[1;32m[OK]\033[0m    %s\n' "$*"; }
warn()    { printf '\033[1;33m[WARN]\033[0m  %s\n' "$*"; }
error()   { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; }

need_cmd() {
  command -v "$1" &>/dev/null
}

# User files must be created by their owner; sudo is only used for system packages.
validate_user_context() {
  local uid
  uid="$(id -u)" || return $?
  TARGET_USER="$(id -un)" || return $?
  info "Target user: $TARGET_USER (uid $uid); home: $TARGET_HOME"
  if [ "$uid" = 0 ]; then
    error "Do not run bootstrap as root or with sudo. It would configure root, not your normal account."
    error "Log in as the intended user (for example: su - lht), then run ./bootstrap.sh without sudo."
    return 1
  fi
  if [[ "$TARGET_HOME" != /* ]] || [ ! -d "$TARGET_HOME" ] ||
     [ ! -O "$TARGET_HOME" ] || [ ! -w "$TARGET_HOME" ]; then
    error "Home directory must exist, be owned by $TARGET_USER, and be writable: $TARGET_HOME"
    error "Start a login session as the intended user so HOME and permissions are correct."
    return 1
  fi
  if [ -n "${ZDOTDIR:-}" ] && ! [ "$ZDOTDIR" -ef "$TARGET_HOME" ]; then
    error "ZDOTDIR points outside HOME: $ZDOTDIR. Zsh would not load $TARGET_HOME/.zshrc."
    error "Unset ZDOTDIR in this login environment before running bootstrap."
    return 1
  fi
}

# ── symlink helper (backup existing) ─────────────────────────────────────────
link() {
  local src="$1"
  local dst="$2"
  local backup=""

  [ -f "$src" ] || { error "Missing source: $src"; return 1; }

  mkdir -p "$(dirname "$dst")" || return $?

  if [ -e "$dst" ] || [ -L "$dst" ]; then
    # already points to src -> skip
    if [ -L "$dst" ] && [ "$dst" -ef "$src" ]; then
      success "Already linked: $dst"
      return
    fi
    backup="$(mktemp -d "${dst}.backup.XXXXXXXX")" || return $?
    warn "Backing up existing: $dst -> $backup/original"
    mv "$dst" "$backup/original" || return $?
  fi

  if ! ln -s "$src" "$dst"; then
    if [ -n "$backup" ]; then
      mv "$backup/original" "$dst"
    fi
    error "Could not link: $dst"
    return 1
  fi
  success "Linked: $dst -> $src"
}

# ── package install wrappers ─────────────────────────────────────────────────
install_pkg() {
  # usage: install_pkg <package>
  local pkg="$1"

  if need_cmd apt-get; then
    sudo apt-get update -y || return $?
    sudo apt-get install -y "$pkg"
    return
  fi

  if need_cmd pacman; then
    sudo pacman -S --noconfirm --needed "$pkg"
    return
  fi

  if need_cmd brew; then
    brew install "$pkg"
    return
  fi

  return 1
}

# ── installers ───────────────────────────────────────────────────────────────
install_zsh() {
  info "Checking zsh..."
  if ! need_cmd zsh; then
    info "Installing zsh..."
    install_pkg zsh || { error "Cannot auto-install zsh. Please install it manually."; exit 1; }
  fi
  success "zsh: $(zsh --version)"
}

install_tmux() {
  info "Checking tmux..."
  if ! need_cmd tmux; then
    info "Installing tmux..."
    install_pkg tmux || { error "Cannot auto-install tmux. Please install it manually."; exit 1; }
  fi
  success "tmux: $(tmux -V)"
}

install_omz() {
  local dir="$TARGET_HOME/.oh-my-zsh"
  info "Checking Oh My Zsh..."
  if [ -f "$dir/oh-my-zsh.sh" ]; then
    success "Oh My Zsh already installed."
    return
  fi
  if [ -e "$dir" ] || [ -L "$dir" ]; then
    error "Incomplete Oh My Zsh installation: $dir. Move it aside and retry."
    return 1
  fi

  info "Installing Oh My Zsh..."
  run_install_script https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh \
    env ZSH="$dir" ZDOTDIR="$TARGET_HOME" RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh || return $?
  [ -f "$dir/oh-my-zsh.sh" ] || { error "Oh My Zsh installation is incomplete: $dir"; return 1; }
  success "Oh My Zsh installed."
}

# Download completely before execution; clean up on success and failure.
run_install_script() (
  local url="$1" script
  shift
  script="$(mktemp)" || return $?
  trap 'rm -f "$script"' EXIT
  curl -fsSL "$url" -o "$script" || return $?
  [ -s "$script" ] || { error "Empty installer: $url"; return 1; }
  "$@" "$script"
)

install_p10k() {
  local dir="${ZSH_CUSTOM:-$TARGET_HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
  info "Checking Powerlevel10k..."
  if [ -f "$dir/powerlevel10k.zsh-theme" ]; then
    success "Powerlevel10k already installed."
    return
  fi
  info "Installing Powerlevel10k..."
  git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$dir"
  success "Powerlevel10k installed."
}

install_zsh_plugin() {
  # usage: install_zsh_plugin <name> <git_url>
  local name="$1"
  local url="$2"
  local dir="${ZSH_CUSTOM:-$TARGET_HOME/.oh-my-zsh/custom}/plugins/$name"

  info "Checking plugin $name..."
  if [ -f "$dir/$name.plugin.zsh" ]; then
    success "$name already installed."
    return
  fi

  info "Installing plugin $name..."
  git clone --depth=1 "$url" "$dir"
  success "$name installed."
}

install_zoxide() {
  export PATH="$TARGET_HOME/.local/bin:$PATH"
  info "Checking zoxide..."
  if need_cmd zoxide; then
    success "zoxide: $(zoxide --version)"
    return
  fi

  info "Installing zoxide..."
  if install_pkg zoxide; then
    success "zoxide: $(zoxide --version)"
    return
  fi

  warn "Package manager install failed; using upstream install script..."
  run_install_script https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh sh
  if ! need_cmd zoxide; then
    error "zoxide install script finished but zoxide isn't in PATH yet."
    error "Try restarting your shell, or ensure ~/.local/bin is on PATH."
    exit 1
  fi
  success "zoxide: $(zoxide --version)"
}

configure_eza_repo() (
  local tmp
  tmp="$(mktemp -d)" || return $?
  trap 'rm -rf "$tmp"' EXIT
  curl -fsSL https://raw.githubusercontent.com/eza-community/eza/main/deb.asc -o "$tmp/deb.asc" || return $?
  gpg --batch --dearmor -o "$tmp/gierens.gpg" "$tmp/deb.asc" || return $?
  printf '%s\n' 'deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main' > "$tmp/gierens.list"
  sudo install -d -m 755 /etc/apt/keyrings || return $?
  sudo install -m 644 "$tmp/gierens.gpg" /etc/apt/keyrings/gierens.gpg || return $?
  sudo install -m 644 "$tmp/gierens.list" /etc/apt/sources.list.d/gierens.list
)

install_eza() {
  info "Checking eza..."
  if need_cmd eza; then
    success "eza: $(eza --version | head -n1)"
    return
  fi

  info "Installing eza..."

  if need_cmd apt-get; then
    # Debian/Ubuntu: use gierens repo
    sudo apt-get update -y
    sudo apt-get install -y gpg
    configure_eza_repo

    sudo apt-get update -y
    sudo apt-get install -y eza
  elif need_cmd pacman; then
    sudo pacman -S --noconfirm --needed eza
  elif need_cmd brew; then
    brew install eza
  elif need_cmd cargo; then
    warn "No system package manager detected; installing eza with cargo..."
    cargo install eza
  else
    error "Cannot auto-install eza. See https://github.com/eza-community/eza/blob/main/INSTALL.md"
    exit 1
  fi

  success "eza: $(eza --version | head -n1)"
}

# ── deploy dotfiles ──────────────────────────────────────────────────────────
deploy_configs() {
  local i
  info "Deploying configs (symlinks)..."
  for i in "${!CONFIG_SOURCES[@]}"; do
    [ -f "$DOTFILES_DIR/${CONFIG_SOURCES[$i]}" ] || {
      error "Missing source: ${CONFIG_SOURCES[$i]}"; return 1;
    }
  done
  for i in "${!CONFIG_SOURCES[@]}"; do
    link "$DOTFILES_DIR/${CONFIG_SOURCES[$i]}" "$TARGET_HOME/${CONFIG_TARGETS[$i]}" || return $?
  done

  success "Configs deployed."
}

set_default_shell_to_zsh() {
  local zsh_path
  zsh_path="$(command -v zsh)"

  if [ "${SHELL:-}" = "$zsh_path" ]; then
    success "Default shell already zsh."
    return
  fi

  info "Changing default shell to zsh (requires password)..."
  if ! chsh -s "$zsh_path"; then
    error "chsh failed. Run it manually: chsh -s $zsh_path"
    return 1
  fi
  success "Default shell set to zsh (effective after re-login)."
}

install_dependencies() {
  # basic tools for cloning/install scripts
  if ! need_cmd git; then
    error "git is required. Please install git first."
    exit 1
  fi
  if ! need_cmd curl; then
    error "curl is required. Please install curl first."
    exit 1
  fi

  install_zsh
  install_tmux
  install_omz

  install_p10k
  install_zsh_plugin zsh-syntax-highlighting https://github.com/zsh-users/zsh-syntax-highlighting.git
  install_zsh_plugin zsh-autosuggestions https://github.com/zsh-users/zsh-autosuggestions.git

  install_zoxide
  install_eza

  check_clipboard
}

check_clipboard() {
  if ! need_cmd wl-copy && ! need_cmd xclip && ! need_cmd pbcopy; then
    warn "System clipboard unavailable: install wl-clipboard (Wayland) or xclip (X11). macOS uses pbcopy."
  fi
}

check_configs() {
  local i cmd dir failed=0
  for i in "${!CONFIG_SOURCES[@]}"; do
    if [ -L "$TARGET_HOME/${CONFIG_TARGETS[$i]}" ] &&
       [ "$TARGET_HOME/${CONFIG_TARGETS[$i]}" -ef "$DOTFILES_DIR/${CONFIG_SOURCES[$i]}" ]; then
      success "Linked: ${CONFIG_TARGETS[$i]}"
    else
      error "Missing or incorrect link: ${CONFIG_TARGETS[$i]}"
      failed=1
    fi
  done
  for cmd in zsh tmux zoxide eza; do
    if ! need_cmd "$cmd"; then error "Missing command: $cmd"; failed=1; fi
  done
  dir="${ZSH_CUSTOM:-$TARGET_HOME/.oh-my-zsh/custom}"
  for cmd in "$TARGET_HOME/.oh-my-zsh/oh-my-zsh.sh" \
    "$dir/themes/powerlevel10k/powerlevel10k.zsh-theme" \
    "$dir/plugins/zsh-autosuggestions/zsh-autosuggestions.plugin.zsh" \
    "$dir/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.plugin.zsh"; do
    if [ ! -f "$cmd" ] || [ ! -r "$cmd" ]; then error "Missing or unreadable file: $cmd"; failed=1; fi
  done
  if [ -e "$TARGET_HOME/.zsh_history" ] &&
     { [ ! -r "$TARGET_HOME/.zsh_history" ] || [ ! -w "$TARGET_HOME/.zsh_history" ]; }; then
    error "History file is not readable/writable by $TARGET_USER: $TARGET_HOME/.zsh_history"
    failed=1
  fi
  check_clipboard
  return "$failed"
}

usage() {
  cat <<'EOF'
Usage: ./bootstrap.sh [--install | --link-only | --check] [--chsh]
Run as the intended normal user, without sudo; root execution is rejected.
  (no mode)    Install dependencies and deploy configs.
  --install    Install dependencies only.
  --link-only  Deploy configs only; no downloads or sudo.
  --check      Check links and dependencies without changing anything.
  --chsh       Also change the login shell to zsh (explicit opt-in).
  --help       Show this help.
EOF
}

main() {
  local mode=all change_shell=0 arg
  for arg in "$@"; do
    case "$arg" in
      --install|--link-only|--check)
        [ "$mode" = all ] || { error "Choose only one mode."; return 2; }
        mode="$arg" ;;
      --chsh) change_shell=1 ;;
      --help|-h) usage; return ;;
      *) error "Unknown argument: $arg"; usage; return 2 ;;
    esac
  done
  if [ "$mode" = --check ] && [ "$change_shell" = 1 ]; then
    error "--check cannot be combined with --chsh."; return 2
  fi
  validate_user_context || return $?
  export PATH="$TARGET_HOME/.local/bin:$PATH"
  info "====== bootstrap Kaito387/dots ======"
  case "$mode" in
    all) install_dependencies; deploy_configs ;;
    --install) install_dependencies ;;
    --link-only) deploy_configs ;;
    --check)
      check_configs || return $?
      success "Links and dependencies checked for $TARGET_USER ($TARGET_HOME)."
      info "This does not check the active shell. Run exec zsh to load the configuration."
      return ;;
  esac
  if [ "$change_shell" = 1 ]; then set_default_shell_to_zsh; fi

  echo ""
  if [ "$mode" = --install ]; then
    success "Dependencies installed for $TARGET_USER. Configs have not been deployed by this run."
    info "Next: ./bootstrap.sh --link-only"
  else
    success "Configs deployed for $TARGET_USER ($TARGET_HOME)."
    info "In this user's terminal, run: exec zsh"
    if [ "$change_shell" = 0 ]; then
      info "The login shell was not changed. To change it: ./bootstrap.sh --link-only --chsh"
    fi
  fi
}

if [[ "${BASH_SOURCE[0]}" = "$0" ]]; then
  main "$@"
fi
