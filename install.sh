#!/usr/bin/env bash
set -euo pipefail

DOTFILES_DIR="$HOME/.dotfiles/homelab-dotfiles"
OS="$(uname -s)"

# ---- Make scripts/bin executable -----------------------------------------
chmod +x "$DOTFILES_DIR/scripts/bin"/*

# ---- Symlinks: cross-platform -----------------------------------------------

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

# ---- Add scripts/bin to PATH in shell config ----------------------------
ZSHRC_DOTFILES="$HOME/.dotfiles/homelab-os-install/zsh/.zshrc-dotfiles"
SCRIPTS_BIN_LINE="export PATH=\"$DOTFILES_DIR/scripts/bin:\$PATH\""
if [ -f "$ZSHRC_DOTFILES" ]; then
    grep -qF 'scripts/bin' "$ZSHRC_DOTFILES" || echo "$SCRIPTS_BIN_LINE" >> "$ZSHRC_DOTFILES"
fi

echo "homelab-dotfiles symlinks applied."
