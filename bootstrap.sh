#!/usr/bin/env bash
# bootstrap.sh — bootstrap for Kaito387/dots
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── pretty logs ───────────────────────────────────────────────────────────────
info()    { printf '\033[1;34m[INFO]\033[0m  %s\n' "$*"; }
success() { printf '\033[1;32m[OK]\033[0m    %s\n' "$*"; }
warn()    { printf '\033[1;33m[WARN]\033[0m  %s\n' "$*"; }
error()   { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; }

need_cmd() {
  command -v "$1" &>/dev/null
}

# ── symlink helper (backup existing) ─────────────────────────────────────────
link() {
  local src="$1"
  local dst="$2"

  mkdir -p "$(dirname "$dst")"

  if [ -e "$dst" ] || [ -L "$dst" ]; then
    # already points to src -> skip
    if [ "$(readlink -f "$dst" 2>/dev/null || true)" = "$(readlink -f "$src")" ]; then
      success "Already linked: $dst"
      return
    fi
    warn "Backing up existing: $dst -> ${dst}.bak"
    mv "$dst" "${dst}.bak"
  fi

  ln -s "$src" "$dst"
  success "Linked: $dst -> $src"
}

# ── package install wrappers ─────────────────────────────────────────────────
install_pkg() {
  # usage: install_pkg <apt|pacman|brew> <package>
  local pkg="$1"

  if need_cmd apt-get; then
    sudo apt-get update -y
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
  info "Checking Oh My Zsh..."
  if [ -d "$HOME/.oh-my-zsh" ]; then
    success "Oh My Zsh already installed."
    return
  fi

  info "Installing Oh My Zsh..."
  RUNZSH=no CHSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
  success "Oh My Zsh installed."
}

install_p10k() {
  local dir="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
  info "Checking Powerlevel10k..."
  if [ -d "$dir" ]; then
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
  local dir="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/$name"

  info "Checking plugin $name..."
  if [ -d "$dir" ]; then
    success "$name already installed."
    return
  fi

  info "Installing plugin $name..."
  git clone --depth=1 "$url" "$dir"
  success "$name installed."
}

install_zoxide() {
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
  curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh
  if ! need_cmd zoxide; then
    error "zoxide install script finished but zoxide isn't in PATH yet."
    error "Try restarting your shell, or ensure ~/.local/bin is on PATH."
    exit 1
  fi
  success "zoxide: $(zoxide --version)"
}

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
    sudo apt-get install -y gpg wget

    sudo mkdir -p /etc/apt/keyrings
    wget -qO- https://raw.githubusercontent.com/eza-community/eza/main/deb.asc \
      | sudo gpg --dearmor -o /etc/apt/keyrings/gierens.gpg

    echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main" \
      | sudo tee /etc/apt/sources.list.d/gierens.list >/dev/null

    sudo chmod 644 /etc/apt/keyrings/gierens.gpg /etc/apt/sources.list.d/gierens.list

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
  info "Deploying configs (symlinks)..."

  link "$DOTFILES_DIR/zsh/zshrc"      "$HOME/.zshrc"
  link "$DOTFILES_DIR/zsh/p10k.zsh"   "$HOME/.p10k.zsh"
  link "$DOTFILES_DIR/tmux/tmux.conf" "$HOME/.tmux.conf"

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
  chsh -s "$zsh_path" || warn "chsh failed. You may need to run it manually: chsh -s $zsh_path"
  success "Default shell set to zsh (effective after re-login)."
}

main() {
  info "====== bootstrap Kaito387/dots ======"

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

  deploy_configs
  set_default_shell_to_zsh

  echo ""
  success "Done. Run: exec zsh"
}

main "$@"
