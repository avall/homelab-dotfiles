#!/usr/bin/env bash
# Switches OmniWM between the two modes this repo ships, and keeps the floating
# rules in place.
#
#   niri      the scrolling column layout
#   hyprland  the binary-space-partition layout, closest to the yabai
#             configuration this setup used before OmniWM
#
# WHAT SETTINGS.TOML IS
#
# Nothing in this file is read while OmniWM is running. It is read once, at
# launch, and it is all or nothing: a single field OmniWM cannot decode makes it
# discard the entire file and keep its previous settings. So hotkeys can be
# scripted, but only for the next launch -- there is no omniwmctl command to bind
# one and no way to make OmniWM reload. That is what sync_hotkeys below is for.
#
# ALL OR NOTHING IS NOT A FIGURE OF SPEECH
#
# Three hotkeys were written here and none of them registered, and neither did
# OmniWM's own factory Control+Option+Command+L. It looked like a broken modifier
# for a while. It was not. Settings -> Troubleshooting had the answer:
#
#   Invalid settings left untouched
#   OmniWM could not decode ~/.config/omniwm/settings.toml and left the file
#   untouched: appRules[16].bundleId: Key 'bundleId' not found
#
# appRules[16] was the Karabiner-Elements entry from FLOAT_RULES below. `rule add
# --app-name-substring` creates a rule with no bundle identifier, an older OmniWM
# exported it with the key absent entirely, and its own decoder requires the key.
# It wrote a file it could not read, and every hotkey in it was ignored for it.
#
# 0.6.7 exports the same rule as `bundleId = ""` -- key present, value empty --
# which decodes. modes/*.toml were exported before that and had to be repaired by
# hand. repair_app_rules below is the guard against it coming back.
#
# The moral, for the next value someone scripts into this file: a settings.toml
# that fails to decode does not fail loudly. Everything simply stops taking
# effect, with the reason buried in a settings pane.
#
# The other values in modes/*.toml were measured on 0.6.5 and never re-tested
# against a fresh launch: gaps.size, borders.enabled, appRules and
# general.ipcEnabled all failed to take effect there. Treat those as a written
# record of what to set by hand in OmniWM's own settings until someone repeats
# the experiment.
#
# At runtime omniwmctl can change exactly two things: the layout of the focused
# workspace, and the rule list.
#
# Control+Option+Command+W calls this, from home/hammerspoon/omniwm.lua -- which
# init.lua deliberately does not load, so today the launchd agent and the
# installer are the only callers.
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
# bundle identifier could not be read from its own Info.plist. That is the entry
# that used to make OmniWM reject the whole of settings.toml -- read the note at
# the top of this file before adding another --app-name-substring rule.
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

SETTINGS="$HOME/.config/omniwm/settings.toml"

# Hotkeys this repo insists on, as `id=binding` pairs in OmniWM's own notation.
# They are the ones the application ships Unassigned and that nothing else here
# covers: taking a window out of a stacked column, and throwing it at the other
# monitor.
#
# Control+Option+Command, the same modifier home/hammerspoon/init.lua uses for
# its own window keys. These three were briefly moved to Control+Command while
# the settings.toml decode failure described at the top of this file was mistaken
# for a broken modifier. It was not: once the appRule was repaired,
# Control+Option+Command+X registered and worked. Do not move them again on that
# theory.
#
# focusMonitorNext is on plain Control+Tab, which is deliberate and is not free:
# it is the standard "next tab" in browsers, editors and terminals, and a global
# hotkey takes it from all of them. Chosen anyway, because moving the focus
# between two monitors is worth more here than tab switching.
#
# The Unassigned entries are as much a setting as the others, and they are the
# reason plain Option+arrow works again in every macOS text field. OmniWM ships
# focus.* on Option+arrow and move.* on Option+Shift+arrow, which are exactly
# the system shortcuts for moving and selecting by word and by paragraph:
#
#   Option+Left / Right          word left / right
#   Option+Up / Down             start / end of paragraph
#   Option+Shift+Left / Right    extend the selection by a word
#   Option+Shift+Up / Down       extend the selection by a paragraph
#
# So focus.* moves to Control+Option+arrow -- Control+Option+Shift+arrow is
# moveColumn and moveWindowToWorkspace, and Control+Option+Command+arrow is
# moveWindowToMonitor above -- and move.left/right go to Option+Command+L and R,
# on the letters rather than the arrows. Option+Command+Left and Right would
# have worked too, but they are "previous/next tab" in Safari and Chrome and
# Control+Tab already costs tab switching once.
#
# move.up and move.down stay pinned empty rather than merely left empty, so a
# settings reset or a future OmniWM default cannot quietly put them back on
# Option+Shift+arrow and take the paragraph selection with them.
OMNIWM_HOTKEYS=(
    "expelWindowFromColumn=Control+Option+Command+X"
    "moveWindowToMonitor.left=Control+Option+Command+Left Arrow"
    "moveWindowToMonitor.right=Control+Option+Command+Right Arrow"
    "focusMonitorNext=Control+Tab"
    "focus.left=Control+Option+Left Arrow"
    "focus.right=Control+Option+Right Arrow"
    "focus.up=Control+Option+Up Arrow"
    "focus.down=Control+Option+Down Arrow"
    "move.left=Option+Command+L"
    "move.right=Option+Command+R"
    "move.up=Unassigned"
    "move.down=Unassigned"
    # Workspace 2, and the id is base 0: switchWorkspace.0 is Option+1, so the
    # second workspace is index 1. Reads as Option+Command+Shift+2 on the keycaps.
    "moveToWorkspace.1=Option+Shift+Command+2"
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

# Chosen by whether it can parse TOML, not by path. macOS ships Python 3.9.6 at
# /usr/bin/python3 and tomllib only arrived in 3.11, so the system one is no good
# here and picking it by position would silently skip every sync.
python_with_tomllib() {
    local candidate
    for candidate in /opt/homebrew/bin/python3 /usr/local/bin/python3 /usr/bin/python3; do
        if [ -x "$candidate" ] && "$candidate" -c 'import tomllib' 2>/dev/null; then
            echo "$candidate"
            return 0
        fi
    done
    echo "No python3 with tomllib; leaving settings.toml alone." >&2
    return 1
}

# Gives a bundleId back to any appRule that lost it, so OmniWM can decode the
# file at all. See the note at the top: one such rule silently voids every other
# setting in it, hotkeys included.
repair_app_rules() {
    [ -f "$SETTINGS" ] || return 0
    local python
    python="$(python_with_tomllib)" || return 0

    "$python" - "$SETTINGS" <<'PY'
import pathlib, sys, tomllib

path = pathlib.Path(sys.argv[1])
lines = path.read_text().splitlines(keepends=True)
starts = [i for i, l in enumerate(lines) if l.strip() == "[[appRules]]"]
repaired = 0

for n in reversed(range(len(starts))):
    start = starts[n]
    end = starts[n + 1] if n + 1 < len(starts) else len(lines)
    block = lines[start:end]
    if any(l.strip().startswith("bundleId") for l in block):
        continue
    anchor = next((offset for offset, l in enumerate(block)
                   if l.strip().startswith("appNameSubstring")), 0)
    lines.insert(start + anchor + 1, 'bundleId = ""\n')
    repaired += 1

if not repaired:
    sys.exit(0)

text = "".join(lines)
try:
    tomllib.loads(text)
except tomllib.TOMLDecodeError as error:
    print(f"Refusing to write settings.toml: {error}", file=sys.stderr)
    sys.exit(1)

path.write_text(text)
print(f"Repaired {repaired} appRule(s) missing bundleId; OmniWM can decode "
      "settings.toml again from the next launch.")
PY
}

# Writes the bindings above into settings.toml if they are not already there.
#
# Edits the file in place instead of rewriting it from a TOML dump, so OmniWM's
# own comments, key order and the several hundred hotkeys this does not touch
# survive untouched. Every write is re-parsed before the script reports success:
# a settings.toml OmniWM cannot parse is renamed to settings.toml.corrupt and the
# whole configuration is replaced by defaults, which is not a failure mode worth
# risking for three keys.
#
# Takes effect at the next OmniWM launch, never in the running instance. Running
# it while OmniWM is up is still worth doing -- OmniWM only exports the file when
# its own settings change, so in practice the binding sits there waiting.
sync_hotkeys() {
    [ -f "$SETTINGS" ] || return 0
    PYTHON="$(python_with_tomllib)" || return 0

    "$PYTHON" - "$SETTINGS" "${OMNIWM_HOTKEYS[@]}" <<'PY'
import pathlib, sys, tomllib

path = pathlib.Path(sys.argv[1])
wanted = dict(pair.split("=", 1) for pair in sys.argv[2:])

lines = path.read_text().splitlines(keepends=True)
starts = [i for i, l in enumerate(lines) if l.strip() == "[[hotkeys]]"]
changed = []

for n, start in enumerate(starts):
    end = starts[n + 1] if n + 1 < len(starts) else len(lines)
    block = lines[start:end]
    ident = next((l.split("=", 1)[1].strip().strip('"')
                  for l in block if l.strip().startswith("id = ")), None)
    if ident not in wanted:
        continue
    for offset, line in enumerate(block):
        if not line.strip().startswith("binding = "):
            continue
        if line.split("=", 1)[1].strip().strip('"') != wanted[ident]:
            indent = line[:len(line) - len(line.lstrip())]
            lines[start + offset] = f'{indent}binding = "{wanted[ident]}"\n'
            changed.append(ident)
        break

if not changed:
    sys.exit(0)

text = "".join(lines)
# Parsed before it is written, not after: an unparseable settings.toml costs the
# whole configuration, so it never reaches disk in the first place.
try:
    tomllib.loads(text)
except tomllib.TOMLDecodeError as error:
    print(f"Refusing to write settings.toml: {error}", file=sys.stderr)
    sys.exit(1)

path.write_text(text)
print(f"Bound {len(changed)} hotkey(s), live at the next OmniWM launch: "
      + ", ".join(changed))
PY
}

apply() {
    local mode="$1" engine=niri
    [ "$mode" = hyprland ] && engine=dwindle

    # Before the IPC check, and that ordering is the whole point: the installer
    # runs this while OmniWM is still stopped, so IPC is necessarily down. Both
    # are file edits and need nothing running -- putting them after the guard
    # meant a fresh machine never got them.
    repair_app_rules
    sync_hotkeys

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
    hotkeys) sync_hotkeys ;;
    repair) repair_app_rules ;;
    # What the launchd agent runs. The three parts are independent: the rules
    # need IPC and are lost on every restart, the other two need only the file.
    # None failing stops the others.
    #
    # repair_app_rules runs first. A settings.toml OmniWM cannot decode is worth
    # nothing to write hotkeys into.
    sync)
        repair_app_rules
        sync_rules
        sync_hotkeys
        ;;
    status) current_mode ;;
    *)
        echo "Usage: ${0##*/} [niri|hyprland|toggle|rules|hotkeys|repair|sync|status]" >&2
        exit 1
        ;;
esac
