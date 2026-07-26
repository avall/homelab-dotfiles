#!/usr/bin/env bash
set -euo pipefail

DOTFILES_DIR="$HOME/.dotfiles/homelab-dotfiles"
OS="$(uname -s)"

# ---- Make scripts/bin executable -----------------------------------------
chmod +x "$DOTFILES_DIR/scripts/bin"/*

# ---- Symlinks: cross-platform -----------------------------------------------

# A fresh macOS account has no ~/.config, so the symlinks below would fail.
mkdir -p "$HOME/.config"

# alacritty base config
ln -sf "$DOTFILES_DIR/home/alacritty" "$HOME/.config/alacritty"

# alacritty themes (clone only if not already present)
if [ ! -d "$DOTFILES_DIR/home/alacritty/themes" ]; then
    git clone https://github.com/alacritty/alacritty-theme "$DOTFILES_DIR/home/alacritty/themes"
fi

# alacritty platform keybindings
if [ "$OS" = "Darwin" ]; then
    ln -sf "$DOTFILES_DIR/home/alacritty/keybindings-macos.toml" \
           "$DOTFILES_DIR/home/alacritty/keybindings.toml"
else
    ln -sf "$DOTFILES_DIR/home/alacritty/keybindings-linux.toml" \
           "$DOTFILES_DIR/home/alacritty/keybindings.toml"
fi

# starship
ln -sf "$DOTFILES_DIR/home/starship" "$HOME/.config/starship"
ln -sf "$DOTFILES_DIR/home/starship/starship.toml" "$HOME/.config/starship.toml"

# git config
ln -sf "$DOTFILES_DIR/home/git/.gitconfig" "$HOME/.gitconfig"

# git scripts
ln -sf "$DOTFILES_DIR/home/git-scripts/" "$HOME/.config/git-scripts"

# wezterm
ln -sf "$DOTFILES_DIR/home/wezterm/.wezterm.lua" "$HOME/.wezterm.lua"

# steampipe
ln -sf "$DOTFILES_DIR/home/steampipe" "$HOME/.steampipe"

# ---- Symlinks: macOS-only ---------------------------------------------------
if [ "$OS" = "Darwin" ]; then
    # yabai
    ln -sf "$DOTFILES_DIR/home/yabai" "$HOME/.config/yabai"
    chmod +x "$DOTFILES_DIR/home/yabai/yabairc"

    # borders
    ln -sf "$DOTFILES_DIR/home/borders" "$HOME/.config/borders"

    # hammerspoon
    ln -sf "$DOTFILES_DIR/home/hammerspoon" "$HOME/.hammerspoon"

    # skhd
    ln -sf "$DOTFILES_DIR/home/skhd" "$HOME/.config/skhd"
fi

# ---- Symlinks: Arch Linux-only ----------------------------------------------
if [ "$OS" = "Linux" ] && [ -f /etc/arch-release ]; then
    # hyprland (replaces yabai + skhd + borders + hammerspoon)
    mkdir -p "$HOME/.config/hypr"
    ln -sf "$DOTFILES_DIR/home/hyprland/hyprland.conf" "$HOME/.config/hypr/hyprland.conf"
fi

# ---- Steampipe plugins (guarded) -----------------------------------------
if command -v steampipe &>/dev/null; then
    steampipe plugin install aws
    steampipe plugin install csv
    steampipe plugin install kubernetes
    steampipe plugin install jira
    steampipe plugin install cloudflare
else
    echo "steampipe not found — skipping plugin installs."
fi

# scripts/bin is added to PATH by homelab-os-install/zsh/export.sh, which is
# versioned. Appending it here left the entry in a generated file that was lost
# on the next checkout.

echo "homelab-dotfiles symlinks applied."
