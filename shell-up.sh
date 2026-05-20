#!/usr/bin/env bash
set -Eeuo pipefail

APP_NAME="szalik.dev's independency installation tool"
LOG_FILE="${SHELL_UP_LOG:-$HOME/.shell-up.log}"
ZSHRC="${ZDOTDIR:-$HOME}/.zshrc"
OMZ_DIR="${ZSH:-$HOME/.oh-my-zsh}"
OMZ_CUSTOM="${ZSH_CUSTOM:-$OMZ_DIR/custom}"
P10K_DIR="$OMZ_CUSTOM/themes/powerlevel10k"

YES_MODE=0
DRY_RUN=0
APT_UPDATED=0
BREW_UPDATED=0
ZSH_DEFAULT_PROMPTED=0
ZSHRC_BACKED_UP=0
SYSTEM_TYPE="unknown"
GROUP_SELECT_MODE=1
SCAN_PACKAGE_MANAGER="unknown"
SCAN_PERMISSION="unknown"
SCAN_ZSHRC_STATUS="unknown"
SCAN_FOUND_TOOLS="none"
SCAN_MISSING_TOOLS="none"
CHOICES=()
INSTALLED=()
SKIPPED=()
WARNINGS=()

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

setup_logging() {
  mkdir -p "$(dirname "$LOG_FILE")"
  touch "$LOG_FILE"
}

print_and_log() {
  local message="$1"
  printf "%b" "$message"
  printf "%b" "$message" >>"$LOG_FILE"
}

log() {
  print_and_log "${BLUE}==>${NC} ${BOLD}$*${NC}\n"
}

success() {
  print_and_log "${GREEN}OK:${NC} $*\n"
}

warn() {
  WARNINGS+=("$*")
  print_and_log "${YELLOW}WARN:${NC} $*\n"
}

fail() {
  print_and_log "${RED}ERROR:${NC} $*\n" >&2
  exit 1
}

record_installed() {
  INSTALLED+=("$1")
}

record_skipped() {
  SKIPPED+=("$1")
}

say_goodbye() {
  printf "\n${CYAN}See you next time, %s.${NC}\n" "${USER:-friend}"
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

run_cmd() {
  if [[ "$DRY_RUN" == "1" ]]; then
    printf "${DIM}[dry-run] %s${NC}\n" "$*"
    return 0
  fi

  "$@"
}

sudo_cmd() {
  if [[ "$DRY_RUN" == "1" ]]; then
    printf "${DIM}[dry-run] sudo/root: %s${NC}\n" "$*"
    return 0
  fi

  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

confirm() {
  local prompt="$1"

  if [[ "$YES_MODE" == "1" ]]; then
    return 0
  fi

  printf "%s [y/N]: " "$prompt"
  read -r answer
  [[ "$answer" =~ ^[Yy]$ ]]
}

should_install_item() {
  local label="$1"

  if [[ "$GROUP_SELECT_MODE" != "1" ]]; then
    return 0
  fi

  if [[ "$YES_MODE" == "1" ]]; then
    return 0
  fi

  if confirm "Install $label?"; then
    return 0
  fi

  record_skipped "$label declined by user"
  return 1
}

require_sudo() {
  if [[ "$SYSTEM_TYPE" == "macos" ]]; then
    return
  fi

  if [[ "$DRY_RUN" == "1" ]]; then
    return
  fi

  if [[ "${EUID:-$(id -u)}" -ne 0 ]] && ! command_exists sudo; then
    fail "This script needs sudo. Please install sudo or run the script as root."
  fi
}

detect_os() {
  OS_ID="unknown"
  OS_VERSION_ID="unknown"
  OS_PRETTY_NAME="unknown system"
  SYSTEM_TYPE="unknown"

  if [[ "$(uname -s)" == "Darwin" ]]; then
    SYSTEM_TYPE="macos"
    OS_ID="macos"
    OS_VERSION_ID="$(sw_vers -productVersion 2>/dev/null || printf 'unknown')"
    OS_PRETTY_NAME="macOS $OS_VERSION_ID"
    success "Detected $OS_PRETTY_NAME"
    return
  fi

  if [[ ! -r /etc/os-release ]]; then
    warn "Cannot read /etc/os-release. Linux support expects an APT-based system; macOS is supported via Homebrew."
    return
  fi

  # shellcheck disable=SC1091
  source /etc/os-release
  OS_ID="${ID:-unknown}"
  OS_VERSION_ID="${VERSION_ID:-unknown}"
  OS_PRETTY_NAME="${PRETTY_NAME:-unknown system}"

  if [[ "$OS_ID" == "debian" && "$OS_VERSION_ID" == "12" ]]; then
    SYSTEM_TYPE="apt"
    success "Detected Debian 12"
  elif [[ "$OS_ID" == "debian" ]]; then
    SYSTEM_TYPE="apt"
    success "Detected Debian $OS_VERSION_ID"
  elif [[ "$OS_ID" == "ubuntu" ]]; then
    SYSTEM_TYPE="apt"
    success "Detected $OS_PRETTY_NAME"
  else
    warn "Detected $OS_PRETTY_NAME. Linux support currently expects an APT-based system; macOS is supported via Homebrew."
  fi
}

loading_phase() {
  local installed_tools=()
  local missing_tools=()
  local tool

  clear 2>/dev/null || true
  printf "${CYAN}"
  cat <<'EOF'
       __       ____                    __ 
  ___ / /  ___ / / /_____ _____    ___ / / 
 (_-</ _ \/ -_) / /___/ // / _ \_ (_-</ _ \
/___/_//_/\__/_/_/    \_,_/ .__(_)___/_//_/
                         /_/               
EOF
  printf "${NC}\n"
  printf "${BOLD}Loading shell-up...${NC}\n"
  printf "${DIM}Scanning your system before showing the menu.${NC}\n\n"

  printf "  ${CYAN}*${NC} Reading operating system info\n"
  detect_os

  printf "  ${CYAN}*${NC} Checking package manager: "
  if [[ "$SYSTEM_TYPE" == "macos" ]] && command_exists brew; then
    SCAN_PACKAGE_MANAGER="Homebrew"
    printf "${GREEN}Homebrew found${NC}\n"
  elif [[ "$SYSTEM_TYPE" == "macos" ]]; then
    SCAN_PACKAGE_MANAGER="Homebrew missing"
    printf "${YELLOW}Homebrew not found${NC}\n"
    warn "Homebrew is required for package installation on macOS. Install it from https://brew.sh"
  elif command_exists apt-get; then
    SCAN_PACKAGE_MANAGER="APT"
    printf "${GREEN}apt-get found${NC}\n"
  else
    SCAN_PACKAGE_MANAGER="missing"
    printf "${YELLOW}apt-get not found${NC}\n"
    warn "APT was not found. Linux package installation currently expects an APT-based system; macOS uses Homebrew."
  fi

  printf "  ${CYAN}*${NC} Checking permissions: "
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    SCAN_PERMISSION="root"
    printf "${GREEN}running as root${NC}\n"
  elif command_exists sudo; then
    SCAN_PERMISSION="sudo available"
    printf "${GREEN}sudo available${NC}\n"
  else
    SCAN_PERMISSION="sudo missing"
    printf "${YELLOW}sudo missing${NC}\n"
    warn "sudo is not installed. Run as root or install sudo before installing packages."
  fi

  printf "  ${CYAN}*${NC} Locating zsh config: "
  if [[ -f "$ZSHRC" ]]; then
    SCAN_ZSHRC_STATUS="$ZSHRC"
    printf "${GREEN}%s${NC}\n" "$ZSHRC"
  else
    SCAN_ZSHRC_STATUS="$ZSHRC (will be created)"
    printf "${YELLOW}%s will be created if needed${NC}\n" "$ZSHRC"
  fi

  printf "  ${CYAN}*${NC} Checking current shell: %s\n" "${SHELL:-unknown}"

  printf "  ${CYAN}*${NC} Checking installed tools\n"
  for tool in zsh git curl wget gpg eza fzf bat batcat zoxide rg fd fdfind tmux fastfetch htop; do
    if command_exists "$tool"; then
      installed_tools+=("$tool")
    else
      missing_tools+=("$tool")
    fi
  done

  printf "    ${GREEN}Found:${NC} %s\n" "${installed_tools[*]:-none}"
  printf "    ${YELLOW}Missing:${NC} %s\n" "${missing_tools[*]:-none}"
  SCAN_FOUND_TOOLS="${installed_tools[*]:-none}"
  SCAN_MISSING_TOOLS="${missing_tools[*]:-none}"

  printf "  ${CYAN}*${NC} Checking package visibility\n"
  if [[ "$SYSTEM_TYPE" == "macos" ]] && command_exists brew; then
    printf "    ${GREEN}Homebrew ready${NC}; formulas will be resolved during installation\n"
  elif command_exists apt-cache; then
    for tool in zsh fzf bat zoxide ripgrep fd-find tmux fastfetch htop; do
      if apt-cache show "$tool" >/dev/null 2>&1; then
        printf "    ${GREEN}available${NC} %s\n" "$tool"
      else
        printf "    ${YELLOW}not visible${NC} %s\n" "$tool"
      fi
    done
  else
    printf "    ${YELLOW}package visibility scan skipped${NC}\n"
  fi

  printf "\n${GREEN}Loading complete.${NC}\n\n"

  if [[ "${#CHOICES[@]}" -eq 0 && -t 0 ]]; then
    printf "${DIM}Press Enter to continue to the menu...${NC}"
    read -r _
  fi
}

backup_zshrc() {
  if [[ "$ZSHRC_BACKED_UP" == "1" ]]; then
    return
  fi

  ZSHRC_BACKED_UP=1

  if [[ "$DRY_RUN" == "1" ]]; then
    log "Would create a backup of $ZSHRC before editing it"
    return
  fi

  if [[ -f "$ZSHRC" ]]; then
    local backup_path
    backup_path="$ZSHRC.shell-up.$(date +%Y%m%d-%H%M%S).bak"
    cp "$ZSHRC" "$backup_path"
    success "Backed up $ZSHRC to $backup_path"
  fi
}

apt_update_once() {
  if [[ "$APT_UPDATED" != "1" ]]; then
    log "Refreshing APT package index"
    sudo_cmd apt-get update
    APT_UPDATED=1
  fi
}

brew_update_once() {
  if [[ "$BREW_UPDATED" != "1" ]]; then
    log "Refreshing Homebrew package index"
    run_cmd brew update
    BREW_UPDATED=1
  fi
}

install_apt_packages() {
  require_sudo
  apt_update_once
  log "Installing APT packages: $*"
  sudo_cmd apt-get install -y "$@"
}

install_brew_packages() {
  if ! command_exists brew; then
    fail "Homebrew is required on macOS. Install it from https://brew.sh and run shell-up again."
  fi

  brew_update_once
  log "Installing Homebrew packages: $*"
  run_cmd brew install "$@"
}

install_packages() {
  if [[ "$SYSTEM_TYPE" == "macos" ]]; then
    install_brew_packages "$@"
  else
    install_apt_packages "$@"
  fi
}

install_optional_package() {
  local package="$1"
  local binary="$2"

  if command_exists "$binary"; then
    success "$package is already installed"
    record_skipped "$package already installed"
    return
  fi

  if [[ "$SYSTEM_TYPE" == "macos" ]]; then
    if [[ "$DRY_RUN" == "1" ]]; then
      log "Would install optional Homebrew package: $package"
      record_installed "$package"
      return
    fi

    if ! command_exists brew; then
      warn "Homebrew is required to install $package on macOS."
      record_skipped "$package unavailable"
      return
    fi

    if brew info "$package" >/dev/null 2>&1; then
      install_brew_packages "$package"
      success "$package installed"
      record_installed "$package"
    else
      warn "$package is not available in Homebrew."
      record_skipped "$package unavailable"
    fi
    return
  fi

  require_sudo
  apt_update_once

  if [[ "$DRY_RUN" == "1" ]]; then
    log "Would install optional package: $package"
    record_installed "$package"
    return
  fi

  if apt-cache show "$package" >/dev/null 2>&1; then
    sudo_cmd apt-get install -y "$package"
    success "$package installed"
    record_installed "$package"
  else
    warn "$package is not available in current APT sources. Try enabling backports or install it manually."
    record_skipped "$package unavailable"
  fi
}

install_base_tools() {
  local selected=()

  log "Installing base tools"
  if [[ "$SYSTEM_TYPE" == "macos" ]]; then
    should_install_item "git" && selected+=("git")
    should_install_item "curl" && selected+=("curl")
    should_install_item "wget" && selected+=("wget")
    should_install_item "gnupg" && selected+=("gnupg")
    should_install_item "ca-certificates" && selected+=("ca-certificates")
  else
    should_install_item "git" && selected+=("git")
    should_install_item "curl" && selected+=("curl")
    should_install_item "wget" && selected+=("wget")
    should_install_item "ca-certificates" && selected+=("ca-certificates")
    should_install_item "gpg" && selected+=("gpg")
  fi

  if [[ "${#selected[@]}" -eq 0 ]]; then
    warn "No base tools selected."
    return
  fi

  install_packages "${selected[@]}"
  success "Base tools are installed"
  record_installed "base tools: ${selected[*]}"
}

install_zsh() {
  if command_exists zsh; then
    success "zsh is already installed"
    record_skipped "zsh already installed"
  else
    log "Installing zsh"
    install_packages zsh
    success "zsh installed"
    record_installed "zsh"
  fi

  maybe_make_zsh_default
}

maybe_make_zsh_default() {
  local zsh_path
  zsh_path="$(command -v zsh || true)"

  if [[ "$DRY_RUN" == "1" ]]; then
    log "Would ask whether zsh should become the default shell"
    return
  fi

  if [[ -z "$zsh_path" ]]; then
    warn "zsh is not available in PATH, skipping default shell setup"
    return
  fi

  if [[ "${SHELL:-}" == "$zsh_path" ]]; then
    success "zsh is already your default shell"
    return
  fi

  if [[ "$ZSH_DEFAULT_PROMPTED" == "1" ]]; then
    return
  fi

  ZSH_DEFAULT_PROMPTED=1

  if confirm "Do you want to make zsh your default shell?"; then
    if [[ ! -r /etc/shells ]] || ! grep -qx "$zsh_path" /etc/shells; then
      log "Adding $zsh_path to /etc/shells"
      printf '%s\n' "$zsh_path" | sudo_cmd tee -a /etc/shells >/dev/null
    fi

    log "Changing default shell to zsh"
    chsh -s "$zsh_path" || sudo_cmd chsh -s "$zsh_path" "$USER"
    success "Default shell changed. Log out and back in for it to take effect."
    record_installed "zsh default shell"
  fi
}

install_oh_my_zsh() {
  install_zsh
  GROUP_SELECT_MODE=0 install_base_tools

  if [[ -d "$OMZ_DIR/.git" ]]; then
    success "oh-my-zsh is already installed at $OMZ_DIR"
    record_skipped "oh-my-zsh already installed"
  else
    log "Installing oh-my-zsh"
    run_cmd git clone --depth=1 https://github.com/ohmyzsh/ohmyzsh.git "$OMZ_DIR"
    success "oh-my-zsh installed"
    record_installed "oh-my-zsh"
  fi

  backup_zshrc

  if [[ "$DRY_RUN" == "1" ]]; then
    log "Would ensure oh-my-zsh is loaded from $ZSHRC"
    return
  fi

  if [[ ! -f "$ZSHRC" ]]; then
    log "Creating $ZSHRC from oh-my-zsh template"
    cp "$OMZ_DIR/templates/zshrc.zsh-template" "$ZSHRC"
  elif ! grep -q "source \\$ZSH/oh-my-zsh.sh" "$ZSHRC" 2>/dev/null; then
    log "Adding oh-my-zsh loader to $ZSHRC"
    {
      printf '\n# Path to your oh-my-zsh installation.\n'
      printf 'export ZSH="%s"\n' "$OMZ_DIR"
      printf 'ZSH_THEME="robbyrussell"\n'
      printf 'plugins=(git)\n'
      printf 'source $ZSH/oh-my-zsh.sh\n'
    } >>"$ZSHRC"
  fi
}

clone_or_update() {
  local name="$1"
  local repo="$2"
  local dir="$3"

  if [[ -d "$dir/.git" ]]; then
    log "Updating $name"
    run_cmd git -C "$dir" pull --ff-only
    record_skipped "$name already installed"
  else
    log "Installing $name"
    run_cmd git clone --depth=1 "$repo" "$dir"
    record_installed "$name"
  fi
}

install_powerlevel10k() {
  install_oh_my_zsh
  clone_or_update "powerlevel10k" "https://github.com/romkatv/powerlevel10k.git" "$P10K_DIR"
  set_zsh_theme "powerlevel10k/powerlevel10k"
  success "powerlevel10k installed and selected"
  warn "For the best prompt icons, install a Nerd Font in your terminal, for example MesloLGS NF."
}

set_zsh_theme() {
  local theme="$1"

  backup_zshrc

  if [[ "$DRY_RUN" == "1" ]]; then
    log "Would set ZSH_THEME to $theme in $ZSHRC"
    return
  fi

  touch "$ZSHRC"

  if grep -q '^ZSH_THEME=' "$ZSHRC"; then
    sed -i.bak "s|^ZSH_THEME=.*|ZSH_THEME=\"$theme\"|" "$ZSHRC"
  else
    printf '\nZSH_THEME="%s"\n' "$theme" >>"$ZSHRC"
  fi
}

install_eza() {
  GROUP_SELECT_MODE=0 install_base_tools

  if command_exists eza; then
    success "eza is already installed"
    record_skipped "eza already installed"
    return
  fi

  if [[ "$SYSTEM_TYPE" == "macos" ]]; then
    install_packages eza
    success "eza installed"
    record_installed "eza"
    return
  fi

  log "Installing eza from the official eza APT repository"

  if [[ "$DRY_RUN" == "1" ]]; then
    log "Would add the eza APT repository and install eza"
    record_installed "eza"
    return
  fi

  sudo_cmd mkdir -p /etc/apt/keyrings
  sudo_cmd rm -f /etc/apt/keyrings/gierens.gpg
  wget -qO- https://raw.githubusercontent.com/eza-community/eza/main/deb.asc \
    | sudo_cmd gpg --dearmor --yes -o /etc/apt/keyrings/gierens.gpg
  echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main" \
    | sudo_cmd tee /etc/apt/sources.list.d/gierens.list >/dev/null
  sudo_cmd chmod 644 /etc/apt/keyrings/gierens.gpg /etc/apt/sources.list.d/gierens.list

  APT_UPDATED=0
  install_apt_packages eza
  success "eza installed"
  record_installed "eza"
}

write_managed_block() {
  local start_marker="$1"
  local end_marker="$2"
  local content="$3"
  local tmp_file

  backup_zshrc

  if [[ "$DRY_RUN" == "1" ]]; then
    log "Would update managed block in $ZSHRC: $start_marker"
    return
  fi

  tmp_file="$(mktemp)"
  touch "$ZSHRC"

  if grep -qF "$start_marker" "$ZSHRC"; then
    sed "/$start_marker/,/$end_marker/d" "$ZSHRC" >"$tmp_file"
    mv "$tmp_file" "$ZSHRC"
  else
    rm -f "$tmp_file"
  fi

  printf '\n%s\n%s\n%s\n' "$start_marker" "$content" "$end_marker" >>"$ZSHRC"
}

install_eza_aliases() {
  install_eza
  install_oh_my_zsh

  write_managed_block \
    "# >>> shell-up eza aliases >>>" \
    "# <<< shell-up eza aliases <<<" \
    "if command -v eza >/dev/null 2>&1; then
  alias ls='eza --icons=auto --group-directories-first'
  alias l='eza --icons=auto --group-directories-first'
  alias ll='eza -lah --icons=auto --group-directories-first --git'
  alias la='eza -a --icons=auto --group-directories-first'
  alias lt='eza --tree --level=2 --icons=auto --group-directories-first'
  alias tree='eza --tree --icons=auto --group-directories-first'
fi"

  if [[ "$DRY_RUN" == "1" ]]; then
    success "eza aliases would be added to $ZSHRC"
  else
    success "eza aliases added to $ZSHRC"
  fi
  record_installed "eza aliases"
}

install_modern_cli_tools() {
  local selected=()
  local include_fastfetch=0

  GROUP_SELECT_MODE=0 install_base_tools
  if [[ "$SYSTEM_TYPE" == "macos" ]]; then
    should_install_item "fzf" && selected+=("fzf")
    should_install_item "bat" && selected+=("bat")
    should_install_item "zoxide" && selected+=("zoxide")
    should_install_item "ripgrep" && selected+=("ripgrep")
    should_install_item "fd" && selected+=("fd")
    should_install_item "tmux" && selected+=("tmux")
    should_install_item "fastfetch" && selected+=("fastfetch")
    should_install_item "htop" && selected+=("htop")

    if [[ "${#selected[@]}" -gt 0 ]]; then
      install_packages "${selected[@]}"
    else
      warn "No modern CLI tools selected."
    fi
  else
    should_install_item "fzf" && selected+=("fzf")
    should_install_item "bat" && selected+=("bat")
    should_install_item "zoxide" && selected+=("zoxide")
    should_install_item "ripgrep" && selected+=("ripgrep")
    should_install_item "fd-find" && selected+=("fd-find")
    should_install_item "tmux" && selected+=("tmux")
    should_install_item "fastfetch" && include_fastfetch=1
    should_install_item "htop" && selected+=("htop")

    if [[ "${#selected[@]}" -gt 0 ]]; then
      install_packages "${selected[@]}"
    else
      warn "No required modern CLI tools selected."
    fi

    if [[ "$include_fastfetch" == "1" ]]; then
      install_optional_package fastfetch fastfetch
    fi
  fi
  add_modern_cli_aliases
  if [[ "$DRY_RUN" == "1" ]]; then
    success "Modern CLI tools would be installed"
  else
    success "Modern CLI tools are installed"
  fi
  record_installed "modern CLI tools"
}

add_modern_cli_aliases() {
  GROUP_SELECT_MODE=0 install_oh_my_zsh

  write_managed_block \
    "# >>> shell-up modern cli aliases >>>" \
    "# <<< shell-up modern cli aliases <<<" \
    "if command -v batcat >/dev/null 2>&1 && ! command -v bat >/dev/null 2>&1; then
  alias bat='batcat'
fi

if command -v fdfind >/dev/null 2>&1 && ! command -v fd >/dev/null 2>&1; then
  alias fd='fdfind'
fi

if command -v zoxide >/dev/null 2>&1; then
  eval \"\$(zoxide init zsh)\"
fi"

  if [[ "$DRY_RUN" == "1" ]]; then
    success "Modern CLI aliases would be added to $ZSHRC"
  else
    success "Modern CLI aliases added to $ZSHRC"
  fi
  record_installed "modern CLI aliases"
}

install_zsh_plugins() {
  local plugins_to_enable=("git")

  GROUP_SELECT_MODE=0 install_oh_my_zsh

  if should_install_item "zsh-autosuggestions"; then
    clone_or_update "zsh-autosuggestions" \
      "https://github.com/zsh-users/zsh-autosuggestions.git" \
      "$OMZ_CUSTOM/plugins/zsh-autosuggestions"
    plugins_to_enable+=("zsh-autosuggestions")
  fi

  if should_install_item "zsh-syntax-highlighting"; then
    clone_or_update "zsh-syntax-highlighting" \
      "https://github.com/zsh-users/zsh-syntax-highlighting.git" \
      "$OMZ_CUSTOM/plugins/zsh-syntax-highlighting"
    plugins_to_enable+=("zsh-syntax-highlighting")
  fi

  if should_install_item "zsh-completions"; then
    clone_or_update "zsh-completions" \
      "https://github.com/zsh-users/zsh-completions.git" \
      "$OMZ_CUSTOM/plugins/zsh-completions"
    plugins_to_enable+=("zsh-completions")
  fi

  should_install_item "colored-man-pages" && plugins_to_enable+=("colored-man-pages")
  should_install_item "extract" && plugins_to_enable+=("extract")
  should_install_item "sudo" && plugins_to_enable+=("sudo")

  if [[ "${#plugins_to_enable[@]}" -gt 1 ]]; then
    ensure_omz_plugins "${plugins_to_enable[@]}"
  else
    warn "No extra ZSH plugins selected."
  fi

  if [[ "$DRY_RUN" == "1" ]]; then
    success "ZSH plugins would be installed and enabled"
  else
    success "ZSH plugins are installed and enabled"
  fi
}

ensure_omz_plugins() {
  local wanted=("$@")
  local current_line current_plugins plugin new_plugins

  backup_zshrc

  if [[ "$DRY_RUN" == "1" ]]; then
    log "Would enable oh-my-zsh plugins: ${wanted[*]}"
    return
  fi

  touch "$ZSHRC"
  current_line="$(grep -E '^plugins=\(' "$ZSHRC" | head -n 1 || true)"

  if [[ -n "$current_line" ]]; then
    current_plugins="${current_line#plugins=(}"
    current_plugins="${current_plugins%)}"
  else
    current_plugins=""
  fi

  new_plugins="$current_plugins"

  for plugin in "${wanted[@]}"; do
    if [[ " $new_plugins " != *" $plugin "* ]]; then
      new_plugins="${new_plugins:+$new_plugins }$plugin"
    fi
  done

  if [[ -n "$current_line" ]]; then
    sed -i.bak "0,/^plugins=(/s|^plugins=.*|plugins=($new_plugins)|" "$ZSHRC"
  else
    printf '\nplugins=(%s)\n' "$new_plugins" >>"$ZSHRC"
  fi

  record_installed "zsh plugins enabled"
}

restore_default_aliases() {
  backup_zshrc

  if [[ "$DRY_RUN" == "1" ]]; then
    log "Would remove shell-up alias blocks from $ZSHRC"
    record_installed "restore default aliases"
    return
  fi

  touch "$ZSHRC"
  sed -i.bak '/# >>> shell-up eza aliases >>>/,/# <<< shell-up eza aliases <<</d' "$ZSHRC"
  sed -i.bak '/# >>> shell-up modern cli aliases >>>/,/# <<< shell-up modern cli aliases <<</d' "$ZSHRC"
  success "Removed shell-up alias blocks from $ZSHRC"
  record_installed "default aliases restored"
}

show_install_plan() {
  printf "\n${BOLD}Install plan${NC}\n"
  printf "  Core:\n"
  printf "    - zsh\n"
  printf "    - oh-my-zsh\n"
  printf "    - powerlevel10k\n\n"
  printf "  Modern CLI:\n"
  printf "    - eza\n"
  printf "    - fzf\n"
  printf "    - bat\n"
  printf "    - zoxide\n"
  printf "    - ripgrep\n"
  printf "    - fd on macOS / fd-find on Debian\n"
  printf "    - tmux\n"
  printf "    - fastfetch\n"
  printf "    - htop\n\n"
  printf "  ZSH plugins:\n"
  printf "    - zsh-autosuggestions\n"
  printf "    - zsh-syntax-highlighting\n"
  printf "    - zsh-completions\n"
  printf "    - colored-man-pages\n"
  printf "    - extract\n"
  printf "    - sudo\n\n"
  printf "  Safety:\n"
  printf "    - creates a backup before editing %s\n" "$ZSHRC"
  printf "    - writes log to %s\n" "$LOG_FILE"
  printf "    - supports APT-based Linux systems and macOS via Homebrew\n"
  printf "    - supports --dry-run and --yes\n"
}

update_installed_tools() {
  log "Updating installed tools"
  install_base_tools
  if [[ "$SYSTEM_TYPE" == "macos" ]]; then
    brew_update_once
    run_cmd brew upgrade eza fzf bat zoxide ripgrep fd tmux fastfetch htop zsh || true
  else
    apt_update_once
    sudo_cmd apt-get install --only-upgrade -y eza fzf bat zoxide ripgrep fd-find tmux fastfetch htop zsh || true
  fi

  [[ -d "$OMZ_DIR/.git" ]] && run_cmd git -C "$OMZ_DIR" pull --ff-only
  [[ -d "$P10K_DIR/.git" ]] && run_cmd git -C "$P10K_DIR" pull --ff-only
  [[ -d "$OMZ_CUSTOM/plugins/zsh-autosuggestions/.git" ]] && run_cmd git -C "$OMZ_CUSTOM/plugins/zsh-autosuggestions" pull --ff-only
  [[ -d "$OMZ_CUSTOM/plugins/zsh-syntax-highlighting/.git" ]] && run_cmd git -C "$OMZ_CUSTOM/plugins/zsh-syntax-highlighting" pull --ff-only
  [[ -d "$OMZ_CUSTOM/plugins/zsh-completions/.git" ]] && run_cmd git -C "$OMZ_CUSTOM/plugins/zsh-completions" pull --ff-only

  success "Update check finished"
  record_installed "updates checked"
}

install_developer_essentials() {
  install_base_tools
  install_modern_cli_tools
  install_zsh_plugins
  success "Developer essentials are installed"
}

install_all() {
  install_base_tools
  install_oh_my_zsh
  install_powerlevel10k
  install_eza_aliases
  install_modern_cli_tools
  install_zsh_plugins
}

print_menu() {
  clear 2>/dev/null || true
  printf "${CYAN}"
  cat <<'EOF'
       __       ____                    __ 
  ___ / /  ___ / / /_____ _____    ___ / / 
 (_-</ _ \/ -_) / /___/ // / _ \_ (_-</ _ \
/___/_//_/\__/_/_/    \_,_/ .__(_)___/_//_/
                         /_/               
EOF
  printf "${NC}\n"
  printf "${BOLD}Hello %s,${NC}\n\n" "${USER:-there}"
  printf " Welcome to ${MAGENTA}%s${NC}.\n" "$APP_NAME"
  printf " Pick what you want to install, then press ${BOLD}Enter${NC}.\n\n"

  printf " ${DIM}Detected${NC}\n"
  printf "   ${CYAN}OS${NC}: %s\n" "$OS_PRETTY_NAME"
  printf "   ${CYAN}Packages${NC}: %s    ${CYAN}Access${NC}: %s\n" "$SCAN_PACKAGE_MANAGER" "$SCAN_PERMISSION"
  printf "   ${CYAN}Shell${NC}: %s    ${CYAN}Config${NC}: %s\n" "${SHELL:-unknown}" "$SCAN_ZSHRC_STATUS"
  printf "   ${CYAN}Found${NC}: %s\n" "$SCAN_FOUND_TOOLS"
  printf "   ${YELLOW}Missing${NC}: %s\n\n" "$SCAN_MISSING_TOOLS"

  printf " ${DIM}Pick From The Grid${NC}\n"
  printf "   ${CYAN}1${NC}) %-34s ${CYAN}2${NC}) %-34s\n" "zsh" "oh-my-zsh"
  printf "   ${CYAN}3${NC}) %-34s ${CYAN}4${NC}) %-34s\n" "powerlevel10k" "eza"
  printf "   ${CYAN}5${NC}) %-34s ${CYAN}6${NC}) %-34s\n" "eza aliases" "base tools"
  printf "   ${CYAN}7${NC}) %-34s ${CYAN}8${NC}) %-34s\n" "modern CLI tools" "zsh plugins"
  printf "   ${CYAN}9${NC}) %-34s ${CYAN}10${NC}) %-34s\n" "developer essentials" "restore default aliases"
  printf "   ${CYAN}11${NC}) %-33s ${CYAN}u${NC}) %-34s\n" "show install plan" "update installed tools"
  printf "   ${GREEN}a${NC}) %-34s ${RED}q${NC}) %-34s\n\n" "all of the above" "quit"

  printf " ${DIM}Groups 6, 7 and 8 ask package-by-package unless ${BOLD}--yes${DIM} is used.${NC}\n"

  printf " ${DIM}Flags:${NC} ${BOLD}--dry-run${NC} preview only, ${BOLD}--yes${NC} skip confirmations\n"
  printf " ${DIM}Tip: you can pick one or many options, for example:${NC} ${BOLD}1 3 5 8${NC}\n\n"
  printf "${BOLD} Please press number to pick, or q to quit:${NC} "
}

run_choice() {
  case "$1" in
    1) install_zsh ;;
    2) install_oh_my_zsh ;;
    3) install_powerlevel10k ;;
    4) install_eza ;;
    5) install_eza_aliases ;;
    6) install_base_tools ;;
    7) install_modern_cli_tools ;;
    8) install_zsh_plugins ;;
    9) install_developer_essentials ;;
    10) restore_default_aliases ;;
    11) show_install_plan ;;
    a | A) install_all ;;
    u | U) update_installed_tools ;;
    q | Q)
      say_goodbye
      exit 0
      ;;
    *) warn "Skipping unknown option: $1" ;;
  esac
}

parse_args() {
  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --yes | -y)
        YES_MODE=1
        ;;
      --dry-run | -n)
        DRY_RUN=1
        ;;
      --help | -h)
        print_help
        exit 0
        ;;
      *)
        CHOICES+=("$1")
        ;;
    esac
    shift
  done
}

print_help() {
  cat <<EOF
Usage:
  ./shell-up.sh [--dry-run] [--yes] [choices...]

Examples:
  ./shell-up.sh
  ./shell-up.sh --dry-run a
  ./shell-up.sh --yes 7 8

Choices:
  1 zsh
  2 oh-my-zsh
  3 powerlevel10k
  4 eza
  5 eza aliases
  6 base tools
  7 modern CLI tools
  8 zsh plugins
  9 developer essentials
  10 restore default aliases
  11 show install plan
  a all of the above
  u update installed tools
  q quit
EOF
}

print_summary() {
  printf "\n${BOLD}Summary${NC}\n"
  printf "  Log file: ${CYAN}%s${NC}\n" "$LOG_FILE"

  if [[ "$DRY_RUN" == "1" ]]; then
    printf "  Mode: ${YELLOW}dry-run${NC}, no installation or config changes were made.\n"
  fi

  if [[ "${#INSTALLED[@]}" -gt 0 ]]; then
    if [[ "$DRY_RUN" == "1" ]]; then
      printf "\n  ${GREEN}Planned / would change${NC}\n"
    else
      printf "\n  ${GREEN}Installed / changed${NC}\n"
    fi
    printf "   - %s\n" "${INSTALLED[@]}"
  fi

  if [[ "${#SKIPPED[@]}" -gt 0 ]]; then
    printf "\n  ${YELLOW}Skipped${NC}\n"
    printf "   - %s\n" "${SKIPPED[@]}"
  fi

  if [[ "${#WARNINGS[@]}" -gt 0 ]]; then
    printf "\n  ${YELLOW}Warnings${NC}\n"
    printf "   - %s\n" "${WARNINGS[@]}"
  fi

  printf "\n"
  success "Done. Restart your terminal or run: exec zsh"
}

main() {
  parse_args "$@"
  setup_logging
  loading_phase

  if [[ "${#CHOICES[@]}" -eq 0 ]]; then
    print_menu
    read -r choices_input
    # shellcheck disable=SC2206
    CHOICES=($choices_input)
  fi

  if [[ "${#CHOICES[@]}" -eq 0 ]]; then
    fail "No option selected."
  fi

  if [[ "${CHOICES[*]}" =~ ^[[:space:]]*[Qq][[:space:]]*$ ]]; then
    say_goodbye
    exit 0
  fi

  for choice in "${CHOICES[@]}"; do
    run_choice "$choice"
  done

  print_summary
}

main "$@"
