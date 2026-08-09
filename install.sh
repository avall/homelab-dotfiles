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

    # Hyprland writes its own hyprland.lua the first time it starts with an
    # empty config directory. If it got there first, move it aside rather than
    # clobber it: a hyprland.lua always wins over a hyprland.conf, so leaving a
    # stray one would silently shadow everything in this repo. Only a real file
    # is backed up — re-running over our own symlink must stay idempotent.
    HYPR_LUA="$HOME/.config/hypr/hyprland.lua"
    if [ -e "$HYPR_LUA" ] && [ ! -L "$HYPR_LUA" ]; then
        HYPR_LUA_BACKUP="$HYPR_LUA.backup-$(date +%Y%m%d%H%M%S)"
        mv "$HYPR_LUA" "$HYPR_LUA_BACKUP"
        echo "Existing hyprland.lua backed up to $HYPR_LUA_BACKUP"
    fi
    ln -sf "$DOTFILES_DIR/home/hyprland/hyprland.lua" "$HYPR_LUA"

    # hyprland.lua is only an entry point; the configuration itself is here.
    # Split out because Hyprland's require() resolves against the config
    # directory, so every module needs its own symlink.
    ln -sf "$DOTFILES_DIR/home/hyprland/hypr_extra.lua" "$HOME/.config/hypr/hypr_extra.lua"

    # Monitor layout and workspace assignment, separate because they are the
    # only hardware-specific parts of the config and because nwg-displays owns
    # both files. hyprland.lua requires them unconditionally, so a missing file
    # is a config error and neither symlink is optional.
    ln -sf "$DOTFILES_DIR/home/hyprland/monitors.lua" "$HOME/.config/hypr/monitors.lua"
    ln -sf "$DOTFILES_DIR/home/hyprland/workspaces.lua" "$HOME/.config/hypr/workspaces.lua"

    # hyprpaper. The wallpaper directory is linked too because hyprpaper.conf
    # refers to images by ~/.config path rather than by repo path — hyprpaper
    # canonicalises symlinks, so the indirection costs nothing and keeps the
    # config readable.
    ln -sf "$DOTFILES_DIR/home/hyprland/hyprpaper.conf" "$HOME/.config/hypr/hyprpaper.conf"

    # Wallpapers. hyprpaper.conf refers to them by this ~/.config path rather
    # than by repo path, and hyprpaper canonicalises symlinks, so the
    # indirection costs nothing and keeps that config readable.
    ln -sfn "$DOTFILES_DIR/home/wallpapers" "$HOME/.config/wallpapers"
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
