#!/usr/bin/env bash
# Switches OmniWM between the two modes this repo ships, and keeps the floating
# rules in place.
#
#   niri      the scrolling column layout
#   hyprland  the binary-space-partition layout, closest to the yabai
#             configuration this setup used before OmniWM
#
# WHY THIS SCRIPT DOES SO LITTLE
#
# It used to copy modes/<mode>.toml over ~/.config/omniwm/settings.toml and trust
# OmniWM to pick it up. That does not work. OmniWM 0.6.5 keeps its configuration
# in an internal store and treats settings.toml as an export: it writes the file,
# and preserves whatever you put in it, but does not read it back. Measured
# against a running instance, and again against a freshly launched one:
#
#   gaps.size 16 -> 28   innerGap stayed 16
#   borders.enabled=false   borders kept being drawn
#   appRules                never reached App Rules, never floated anything
#   hotkeys[].binding       never registered
#   general.ipcEnabled      never started the IPC server
#
# omniwmctl is the only programmable surface, and it can change exactly two
# things: the layout of the focused workspace, and the rule list. Gaps, borders,
# gestures and focus behaviour have no command at all, so the per-mode values in
# modes/*.toml are a written record of what to set by hand in OmniWM's own
# settings -- not something any script can apply.
#
# Bound to Control+Option+Command+W in home/hammerspoon/init.lua.
set -euo pipefail

SELF="${BASH_SOURCE[0]}"
while [ -L "$SELF" ]; do
    TARGET="$(readlink "$SELF")"
    case "$TARGET" in
        /*) SELF="$TARGET" ;;
        *) SELF="$(cd -- "$(dirname -- "$SELF")" && pwd)/$TARGET" ;;
    esac
done
CONFIG_DIR="$(cd -- "$(dirname -- "$SELF")" && pwd)"

OMNIWMCTL=""
for candidate in /opt/homebrew/bin/omniwmctl /usr/local/bin/omniwmctl; do
    [ -x "$candidate" ] && OMNIWMCTL="$candidate" && break
done

# The windows that must never be tiled, one entry per line: a matcher flag and
# its value. The same list in both modes, because the reason each one is here has
# nothing to do with the layout engine -- Alacritty is positioned by Hammerspoon,
# and the rest are dialogs and panels a tiling engine only gets in the way of.
# Karabiner-Elements is matched by name because it is not installed here, so its
# bundle identifier could not be read from its own Info.plist.
FLOAT_RULES=(
    "--bundle-id org.alacritty"
    "--bundle-id org.hammerspoon.Hammerspoon"
    "--bundle-id com.stonerl.Thaw"
    "--bundle-id com.apple.ScreenSharing"
    "--bundle-id com.apple.systempreferences"
    "--bundle-id com.apple.calculator"
    "--bundle-id com.apple.Stickies"
    "--app-name-substring Karabiner-Elements"
)

ipc_up() {
    [ -n "$OMNIWMCTL" ] && "$OMNIWMCTL" ping &>/dev/null
}

ipc_warning() {
    echo "OmniWM IPC is not answering. Turn it on from the OmniWM menu bar icon:"
    echo '  "Enable IPC" -- it resets every time OmniWM restarts.'
}

# Read from OmniWM rather than from a file. The settings.toml on disk says
# nothing about what is actually running.
current_mode() {
    if ! ipc_up; then
        echo unknown
        return
    fi
    case "$("$OMNIWMCTL" query workspaces --focused --fields layout --format json 2>/dev/null)" in
        *'"dwindle"'*) echo hyprland ;;
        *) echo niri ;;
    esac
}

# Adds any float rule OmniWM does not already hold. Idempotent, and it has to be:
# `rule add` never deduplicates, so calling it blindly would pile up a copy of
# all eight every time.
#
# Run on every OmniWM launch from home/hammerspoon/init.lua, because the rules do
# not survive a restart -- 21 rules before one, 13 after, with none of the eight
# floating ones left.
sync_rules() {
    if ! ipc_up; then
        ipc_warning
        return 0
    fi

    local existing rule added=0
    existing="$("$OMNIWMCTL" query rules --format json 2>/dev/null || echo '{}')"

    for rule in "${FLOAT_RULES[@]}"; do
        # shellcheck disable=SC2086 -- the flag and its value are two arguments.
        set -- $rule
        # Matched against the raw JSON rather than parsed out of it: the value is
        # a bundle identifier or an application name, both of which appear
        # verbatim and nowhere else in that document.
        if ! printf '%s' "$existing" | grep -q "\"$2\""; then
            "$OMNIWMCTL" rule add "$1" "$2" --layout float &>/dev/null && added=$((added + 1))
        fi
    done

    [ "$added" -gt 0 ] && echo "Added $added floating rule(s)."
    return 0
}

apply() {
    local mode="$1" engine=niri
    [ "$mode" = hyprland ] && engine=dwindle

    if ! ipc_up; then
        ipc_warning
        exit 1
    fi

    # Only the workspace in front of you. Other existing workspaces keep the
    # engine they already had until each is switched in turn, which
    # Control+Option+Command+L does per workspace -- omniwmctl has no way to set
    # the layout of a workspace that is not focused.
    "$OMNIWMCTL" command set-workspace-layout "$engine" &>/dev/null ||
        echo "Warning: could not switch the focused workspace to $engine."

    sync_rules
    echo "OmniWM mode: $mode"
}

case "${1:-toggle}" in
    niri | hyprland) apply "$1" ;;
    toggle)
        if [ "$(current_mode)" = hyprland ]; then apply niri; else apply hyprland; fi
        ;;
    rules) sync_rules ;;
    status) current_mode ;;
    *)
        echo "Usage: ${0##*/} [niri|hyprland|toggle|rules|status]" >&2
        exit 1
        ;;
esac
