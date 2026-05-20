# shell-up.sh

`shell-up.sh` is a public, interactive terminal setup tool for APT-based Linux systems and macOS.

It helps bootstrap a comfortable shell environment with `zsh`, `oh-my-zsh`, `powerlevel10k`, modern CLI tools, useful ZSH plugins, aliases, backups, dry runs, logging, and a system scan before installation.

```text
       __       ____                    __
  ___ / /  ___ / / /_____ _____    ___ / /
 (_-</ _ \/ -_) / /___/ // / _ \_ (_-</ _ \
/___/_//_/\__/_/_/    \_,_/ .__(_)___/_//_/
                         /_/
```

## Supported Systems

`shell-up.sh` currently supports:

- APT-based Linux systems, such as Debian and Ubuntu
- macOS through Homebrew

On macOS, Homebrew must already be installed. The script will not install Homebrew for you.

## What It Can Install

Core shell setup:

- `zsh`
- `oh-my-zsh`
- `powerlevel10k`

Modern CLI tools:

- `eza`
- `fzf`
- `bat`
- `zoxide`
- `ripgrep`
- `fd` on macOS / `fd-find` on Debian and Ubuntu
- `tmux`
- `fastfetch`
- `htop`

ZSH plugins:

- `zsh-autosuggestions`
- `zsh-syntax-highlighting`
- `zsh-completions`
- `colored-man-pages`
- `extract`
- `sudo`

It also adds optional aliases for `eza`, `bat`, `fd`, and initializes `zoxide` for ZSH.

## Quick Start

Clone the repo:

```bash
git clone https://github.com/szalikdev/shell-up.git
cd shell-up
chmod +x shell-up.sh
./shell-up.sh
```

Or run directly after reviewing the script:

```bash
curl -fsSL https://raw.githubusercontent.com/szalikdev/shell-up.sh/main/shell-up.sh -o shell-up.sh
chmod +x shell-up.sh
./shell-up.sh
```

If you publish the repository under a different GitHub account or organization, replace `szalikdev` in the URLs.

## Safer First Run

Use `--dry-run` to preview what would happen without installing packages or changing config files:

```bash
./shell-up.sh --dry-run
```

Preview a specific option:

```bash
./shell-up.sh --dry-run 11
```

Run everything without confirmations:

```bash
./shell-up.sh --yes a
```

## Menu

The interactive menu uses a compact grid:

```text
1) zsh                         2) oh-my-zsh
3) powerlevel10k               4) eza
5) eza aliases                 6) base tools
7) modern CLI tools            8) zsh plugins
9) developer essentials        10) restore default aliases
11) show install plan          u) update installed tools
a) all of the above            q) quit
```

Options `6`, `7`, and `8` ask package-by-package unless `--yes` is used.

## Flags

```text
--dry-run, -n   Preview actions without installing packages or editing config files
--yes, -y       Skip confirmations and accept defaults
--help, -h      Show help
```

Examples:

```bash
./shell-up.sh --dry-run a
./shell-up.sh --yes 7 8
./shell-up.sh --dry-run --yes 6
```

## Loading Phase

Before showing the menu, `shell-up.sh` scans the system and displays a short summary:

- operating system
- package manager
- sudo/root access
- current shell
- `.zshrc` location
- detected tools
- missing tools

The same scan data is shown again under the menu welcome text.

## Backups

Before editing `.zshrc`, the script creates a timestamped backup:

```text
~/.zshrc.shell-up.YYYYMMDD-HHMMSS.bak
```

This happens before managed alias blocks or ZSH plugin settings are changed.

## Logs

The script writes its own status messages to:

```text
~/.shell-up.log
```

You can override this path:

```bash
SHELL_UP_LOG=/tmp/shell-up.log ./shell-up.sh
```

## Managed ZSH Blocks

`shell-up.sh` writes managed blocks into `.zshrc` so they can be safely replaced or removed later.

Example:

```zsh
# >>> shell-up eza aliases >>>
...
# <<< shell-up eza aliases <<<
```

To remove shell-up alias blocks from `.zshrc`, run:

```bash
./shell-up.sh 10
```

## Recommended Fonts

`powerlevel10k` looks best with a Nerd Font. A good default is:

- MesloLGS NF

After installing a Nerd Font, set it as your terminal font and restart the terminal.

## Notes For Debian And Ubuntu

On APT-based Linux systems, the script uses:

```bash
apt-get update
apt-get install
```

For `eza`, it adds the official eza APT repository from the eza project.

Some distributions may not expose `fastfetch` in the default APT sources. If unavailable, shell-up skips it and reports that in the summary.

## Notes For macOS

On macOS, the script uses:

```bash
brew update
brew install
```

Homebrew must be installed first:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

The script does not install Homebrew automatically because that is a bigger system-level choice.

## Troubleshooting

If the script says Homebrew is missing on macOS, install Homebrew and run again.

If package installation fails on Linux, make sure you are using an APT-based system and have `sudo` access.

If the prompt icons look broken after installing `powerlevel10k`, install a Nerd Font and select it in your terminal.

If you want to see what changed, inspect:

```bash
cat ~/.shell-up.log
ls -la ~/.zshrc.shell-up.*.bak
```

## Development

Check shell syntax:

```bash
bash -n shell-up.sh
```

Test without making changes:

```bash
./shell-up.sh --dry-run 11
./shell-up.sh --dry-run --yes 7 8
```

## License

MIT
