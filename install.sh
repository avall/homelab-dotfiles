#!/usr/bin/env bash
set -euo pipefail

DOTFILES_DIR="$HOME/.dotfiles/homelab-dotfiles"
OS="$(uname -s)"

# ---- Make scripts/bin executable -----------------------------------------
chmod +x "$DOTFILES_DIR/scripts/bin"/*

# ---- Helpers -----------------------------------------------------------------

# Symlinks a directory, replacing whatever is already at the destination.
#
# `ln -sf` on its own is not idempotent for directories: when the destination is
# already a symlink to a directory, ln follows it and creates the new link
# *inside* the target -- GNU coreutils defaults dereference_dest_dir_symlinks to
# true (ln.c) and BSD ln behaves the same. A second run of this script therefore
# left a self-referencing symlink inside this repo, e.g. home/alacritty/alacritty.
#
# -n fixes the symlink case but not a pre-existing *real* directory: POSIX says
# a final operand naming a directory gets the link created inside it, so
# ln would quietly leave the user's own config in place and drop a stray
# alacritty/alacritty next to it -- no error, and the config this repo installs
# never gets read. Moving the real path aside first is what makes that visible,
# and it matches how homelab-os-install already handles ~/.zshrc and how the
# Hyprland block used to handle hyprland.lua.
#
# Only real paths are backed up: re-running over our own symlink has to stay a
# no-op, which is the whole point of -n above.
link_dir() {
    local src="$1" dest="$2"

    if [ -e "$dest" ] && [ ! -L "$dest" ]; then
        local backup="$dest.backup-$(date +%Y%m%d%H%M%S)"
        mv "$dest" "$backup"
        echo "Existing $dest backed up to $backup"
    fi

    ln -sfn "$src" "$dest"
}

# ---- Symlinks: cross-platform -----------------------------------------------

# A fresh macOS account has no ~/.config, so the symlinks below would fail.
mkdir -p "$HOME/.config"

# alacritty base config
link_dir "$DOTFILES_DIR/home/alacritty" "$HOME/.config/alacritty"

# alacritty themes (clone only if not already present)
if [ ! -d "$DOTFILES_DIR/home/alacritty/themes" ]; then
    git clone https://github.com/alacritty/alacritty-theme "$DOTFILES_DIR/home/alacritty/themes"
fi

# alacritty platform keybindings.
#
# alacritty.toml imports ~/.config/alacritty/keybindings.toml, and this picks
# which of the two platform files that name resolves to. The link is generated
# rather than versioned: it used to be committed, which meant the repo shipped an
# absolute /Users/... path that dangles on Arch until this script runs, and once
# it did run the rewritten link showed up as an unstageable permanent diff on
# every non-macOS machine. It is in .gitignore for that reason -- this line is
# the only thing that should ever create it.
if [ "$OS" = "Darwin" ]; then
    ln -sf "$DOTFILES_DIR/home/alacritty/keybindings-macos.toml" \
           "$DOTFILES_DIR/home/alacritty/keybindings.toml"
else
    ln -sf "$DOTFILES_DIR/home/alacritty/keybindings-linux.toml" \
           "$DOTFILES_DIR/home/alacritty/keybindings.toml"
fi

# starship
link_dir "$DOTFILES_DIR/home/starship" "$HOME/.config/starship"
ln -sf "$DOTFILES_DIR/home/starship/starship.toml" "$HOME/.config/starship.toml"

# git config
ln -sf "$DOTFILES_DIR/home/git/.gitconfig" "$HOME/.gitconfig"

# git scripts
link_dir "$DOTFILES_DIR/home/git-scripts" "$HOME/.config/git-scripts"

# steampipe
link_dir "$DOTFILES_DIR/home/steampipe" "$HOME/.steampipe"

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
#if [ "$OS" = "Linux" ] && [ -f /etc/arch-release ]; then
#    # hyprland (replaces yabai + skhd + borders + hammerspoon)
#    mkdir -p "$HOME/.config/hypr"
#
#    # Hyprland writes its own hyprland.lua the first time it starts with an
#    # empty config directory. If it got there first, move it aside rather than
#    # clobber it: a hyprland.lua always wins over a hyprland.conf, so leaving a
#    # stray one would silently shadow everything in this repo. Only a real file
#    # is backed up — re-running over our own symlink must stay idempotent.
#    HYPR_LUA="$HOME/.config/hypr/hyprland.lua"
#    if [ -e "$HYPR_LUA" ] && [ ! -L "$HYPR_LUA" ]; then
#        HYPR_LUA_BACKUP="$HYPR_LUA.backup-$(date +%Y%m%d%H%M%S)"
#        mv "$HYPR_LUA" "$HYPR_LUA_BACKUP"
#        echo "Existing hyprland.lua backed up to $HYPR_LUA_BACKUP"
#    fi
#    ln -sf "$DOTFILES_DIR/home/hyprland/hyprland.lua" "$HYPR_LUA"
#
#    # hyprland.lua is only an entry point; the configuration itself is here.
#    # Split out because Hyprland's require() resolves against the config
#    # directory, so every module needs its own symlink.
#    ln -sf "$DOTFILES_DIR/home/hyprland/hypr_extra.lua" "$HOME/.config/hypr/hypr_extra.lua"
#
#    # Monitor layout and workspace assignment, separate because they are the
#    # only hardware-specific parts of the config and because nwg-displays owns
#    # both files. hyprland.lua requires them unconditionally, so a missing file
#    # is a config error and neither symlink is optional.
#    ln -sf "$DOTFILES_DIR/home/hyprland/monitors.lua" "$HOME/.config/hypr/monitors.lua"
#    ln -sf "$DOTFILES_DIR/home/hyprland/workspaces.lua" "$HOME/.config/hypr/workspaces.lua"
#
#    # hyprpaper. The wallpaper directory is linked too because hyprpaper.conf
#    # refers to images by ~/.config path rather than by repo path — hyprpaper
#    # canonicalises symlinks, so the indirection costs nothing and keeps the
#    # config readable.
#    ln -sf "$DOTFILES_DIR/home/hyprland/hyprpaper.conf" "$HOME/.config/hypr/hyprpaper.conf"
#
#    # Wallpapers. hyprpaper.conf refers to them by this ~/.config path rather
#    # than by repo path, and hyprpaper canonicalises symlinks, so the
#    # indirection costs nothing and keeps that config readable.
#    ln -sfn "$DOTFILES_DIR/home/wallpapers" "$HOME/.config/wallpapers"
#fi

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
