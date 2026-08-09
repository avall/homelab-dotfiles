-- Hyprland configuration — the port of the old hyprland.conf.
--
-- The .conf format is deprecated: Hyprland 0.56.1 added a startup notice
-- saying support is removed in 0.57, and a hyprland.lua always wins over a
-- hyprland.conf when both exist. Everything here is the same setup expressed
-- through the hl.* API.
--
-- Hyprland is the only compositor this repo provisions.

------------------------------------------------------------------- PROGRAMS --

local terminal = "alacritty"
local menu     = "hyprlauncher"
local browser  = "google-chrome-stable"
local editor   = "idea-ultimate"

-- Both come from archinstall's Hyprland profile rather than from a manifest
-- choice, and this config replaces the profile's own, which bound them to
-- SUPER+Q and SUPER+E. Those two keys mean something else here, so they are
-- rebound below instead of being left unreachable.
local altTerminal = "kitty"
local fileManager = "dolphin"

--------------------------------------------------------------- ENVIRONMENT --

-- Carried over from the stock config. The old .conf set no environment at all,
-- which left cursor size up to whatever each toolkit guessed.
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")

---------------------------------------------------------------- AUTOSTART ---

hl.on("hyprland.start", function()
    hl.exec_cmd("waybar")
    hl.exec_cmd("hyprpaper")
    hl.exec_cmd("gammastep -O 4000")

    -- Note: cliphist on its own only stores what is piped to it. The usual
    -- `wl-paste --watch cliphist store` wiring is missing on both compositors,
    -- so clipboard history stays inert until wl-clipboard is added.
    hl.exec_cmd("cliphist")

    -- Start the launcher's server without showing it. hyprlauncher is
    -- client/server: the first invocation builds the desktop, font and unicode
    -- indexes, later ones just talk to it over a socket. Without this the first
    -- Mod+R of the session pays for all that indexing.
    hl.exec_cmd("hyprlauncher --daemon")

    -- Dock, resident and hidden until the pointer reaches the bottom edge.
    --
    --   -d           auto-hide behind a hotspot, the way the macOS Dock behaves.
    --                Costs no screen space, which matters more with three
    --                monitors than with one.
    --   -c           command behind the launcher button. Points at hyprlauncher
    --                so the dock's optional nwg-drawer dependency is not needed.
    --   -iw special  keep the quake terminal out of the dock. It is spawned at
    --                startup and never exits, so it would otherwise sit there
    --                permanently. The value is "special", not "special:quake":
    --                nwg-dock cuts workspace names at the first colon before
    --                comparing.
    --
    -- Left at defaults: position bottom, icon size 48, 10 workspaces, overlay
    -- layer, centered.
    hl.exec_cmd("nwg-dock-hyprland -d -c hyprlauncher -iw special")

    -- The quake terminal, pre-spawned so its shell outlives every toggle.
    hl.exec_cmd(terminal .. " --class quake-alacritty")
end)

-------------------------------------------------------------------- INPUT ---

hl.config({
    input = {
        follow_mouse  = 1,
        mouse_refocus = false,
        sensitivity   = 0,

        touchpad = {
            -- Hyprland defaults this to false and the old .conf never set it,
            -- so the touchpad scrolled the opposite way to macOS. Set on
            -- purpose; this is the one input default worth overriding.
            natural_scroll = true,
        },
    },
})

-- Three-finger horizontal swipe to change workspace. From the stock config;
-- the old .conf had no gestures at all.
hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })

----------------------------------------------------------- LOOK AND FEEL ----

hl.config({
    general = {
        gaps_in     = 5,
        gaps_out    = 5,
        border_size = 5,

        col = {
            active_border   = "rgba(ff9300ff)",
            inactive_border = "rgba(414550ff)",
        },

        layout        = "dwindle",
        allow_tearing = false,
    },

    decoration = {
        rounding = 10,

        blur = {
            enabled  = true,
            size     = 6,
            passes   = 2,
            vibrancy = 0.1696,
        },

        -- The .conf used flat keys here — drop_shadow, shadow_range,
        -- shadow_render_power, col.shadow. All four were removed from
        -- Hyprland; the current names are nested under shadow. Colour is
        -- AARRGGBB as a number, so 0xee1a1a1a is the old rgba(1a1a1aee).
        shadow = {
            enabled      = true,
            range        = 8,
            render_power = 3,
            color        = 0xee1a1a1a,
        },
    },

    animations = { enabled = true },

    dwindle = {
        pseudotile     = false,
        preserve_split = true,
        split_ratio    = 0.6,

        -- Windows never lose half their height when a second program joins
        -- them on screen. Dwindle picks the split orientation from the
        -- container's own proportions, not from the app:
        --
        --   SIDEBYSIDE = box.w > box.h * split_width_multiplier
        --   splitTop   = !SIDEBYSIDE          (DwindleAlgorithm.cpp)
        --
        -- At the stock 1.0 the first split on a 2560x1440 screen is fine, but
        -- each half is then 1280x1440 — taller than wide — so the next window
        -- stacks and halves the height. That is what happens opening dolphin
        -- next to kitty, both of which come from archinstall's Hyprland
        -- profile rather than from this repo's manifests.
        --
        -- 0.1 means stacking would need a container under ~144px wide, so in
        -- practice everything tiles side by side at full height. The cost is
        -- narrow columns once several windows share a screen; raise this back
        -- toward 1.0 to trade height for width again.
        split_width_multiplier = 0.1,
    },

    misc = {
        -- Both differ from the stock config, which ships the anime mascot
        -- wallpapers enabled. hyprpaper draws the real background.
        force_default_wallpaper = 0,
        disable_hyprland_logo   = true,
    },
})

-- The old `master { new_is_master = false }` block is gone: that key no longer
-- exists, and its replacement master:new_status already defaults to "slave",
-- so the block only ever restated the default.

hl.curve("myBezier", { type = "bezier", points = { {0.05, 0.9}, {0.1, 1.05} } })

hl.animation({ leaf = "windows",    enabled = true, speed = 7,  bezier = "myBezier" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 7,  bezier = "default", style = "popin 80%" })
hl.animation({ leaf = "border",     enabled = true, speed = 10, bezier = "default" })
hl.animation({ leaf = "fade",       enabled = true, speed = 7,  bezier = "default" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 6,  bezier = "default" })

------------------------------------------------------------ WINDOW RULES ----

-- Ported from the .conf: apps that should never be tiled.
hl.window_rule({ name = "float-calculator", match = { class = "^(gnome-calculator)$" }, float = true })
hl.window_rule({ name = "float-kdiff3",     match = { class = "^(org.kde.kdiff3)$" },   float = true })
hl.window_rule({ name = "float-zoom",       match = { class = "^(zoom)$" },             float = true })

-- The quake terminal. Pre-spawned in autostart above, parked on a special
-- workspace, and toggled with Alt+D / Alt+A.
hl.window_rule({
    name      = "quake-terminal",
    match     = { class = "^(quake-alacritty)$" },
    workspace = "special:quake silent",
    size      = "100% 50%",
    move      = "0 0",
    animation = "popin",
})

-- Both carried over from the stock config; the old .conf had neither, and
-- neither is cosmetic.

-- Applications asking to maximize themselves are ignored.
hl.window_rule({
    name           = "suppress-maximize-events",
    match          = { class = ".*" },
    suppress_event = "maximize",
})

-- Known XWayland drag-and-drop fix: the transient, class-less floating window
-- XWayland creates mid-drag must not steal focus.
hl.window_rule({
    name  = "fix-xwayland-drags",
    match = { class = "^$", title = "^$", xwayland = true, float = true, fullscreen = false, pin = false },

    no_focus = true,
})

-------------------------------------------------------------- KEYBINDINGS ---

local mainMod = "SUPER"

-- Quake terminal — Alt+D / Alt+A, the same pair as Hammerspoon on macOS.
hl.bind("ALT + D", hl.dsp.workspace.toggle_special("quake"))
hl.bind("ALT + A", hl.dsp.workspace.toggle_special("quake"))

-- Application launchers.
hl.bind("ALT + E", hl.dsp.exec_cmd("wezterm"))
hl.bind("ALT + I", hl.dsp.exec_cmd(editor))

hl.bind("CTRL + SUPER + A", hl.dsp.exec_cmd(terminal))
hl.bind("CTRL + SUPER + C", hl.dsp.exec_cmd("code"))
hl.bind("CTRL + SUPER + I", hl.dsp.exec_cmd(editor))
hl.bind("CTRL + SUPER + B", hl.dsp.exec_cmd(browser))

-- Replacements for the two shortcuts archinstall's profile shipped. SUPER+Q is
-- close-window here and SUPER+E is unused, so neither original could be kept.
-- K and D are free: the only SUPER-plus-letter binds in this file are R, Q, F,
-- V, P and J, the focus loop uses arrow keys rather than hjkl, and the
-- workspace loop uses digits. ALT+D is the quake toggle — a different modifier.
hl.bind(mainMod .. " + K", hl.dsp.exec_cmd(altTerminal))
hl.bind(mainMod .. " + D", hl.dsp.exec_cmd(fileManager))

-- --toggle because hyprlauncher is client/server: a second press reaches the
-- running instance and closes it rather than being swallowed.
hl.bind(mainMod .. " + R", hl.dsp.exec_cmd(menu .. " --toggle"))

-- Window management.
hl.bind(mainMod .. " + Q", hl.dsp.window.close())
hl.bind(mainMod .. " + F", hl.dsp.window.fullscreen({ action = "toggle" }))
hl.bind(mainMod .. " + V", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + P", hl.dsp.window.pseudo())
hl.bind(mainMod .. " + J", hl.dsp.layout("togglesplit"))

-- Move focus.
for _, d in ipairs({ "left", "right", "up", "down" }) do
    hl.bind(mainMod .. " + " .. d, hl.dsp.focus({ direction = d }))
    hl.bind(mainMod .. " + SHIFT + " .. d, hl.dsp.window.move({ direction = d }))
end

-- Resize. The .conf used binde for auto-repeat; in Lua that is an option.
hl.bind(mainMod .. " + ALT + right", hl.dsp.window.resize({ x =  50, y =   0, relative = true }), { repeating = true })
hl.bind(mainMod .. " + ALT + left",  hl.dsp.window.resize({ x = -50, y =   0, relative = true }), { repeating = true })
hl.bind(mainMod .. " + ALT + up",    hl.dsp.window.resize({ x =   0, y = -50, relative = true }), { repeating = true })
hl.bind(mainMod .. " + ALT + down",  hl.dsp.window.resize({ x =   0, y =  50, relative = true }), { repeating = true })

-- Workspaces.
for i = 1, 10 do
    local key = i % 10 -- 10 is bound to the 0 key
    hl.bind(mainMod .. " + " .. key, hl.dsp.focus({ workspace = i }))
    hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
end

-- Scroll through workspaces with the mouse wheel. From the stock config.
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))

-- Multi-monitor. -1 / +1 are relative to the focused monitor and wrap, so two
-- keys walk any number of screens.
hl.bind(mainMod .. " + comma",  hl.dsp.focus({ monitor = "-1" }))
hl.bind(mainMod .. " + period", hl.dsp.focus({ monitor = "+1" }))

hl.bind(mainMod .. " + CTRL + comma",  hl.dsp.workspace.move({ monitor = "-1" }))
hl.bind(mainMod .. " + CTRL + period", hl.dsp.workspace.move({ monitor = "+1" }))

-- Sending a WINDOW to another monitor has no Lua equivalent: hl.dsp.window.move
-- takes direction, workspace, x, y, relative, follow and group_aware — there is
-- no monitor field, unlike focus and workspace.move. The dispatcher registry is
-- shared between both config formats, so the old dispatcher is still reachable
-- through hyprctl. Replace this with the native call if a monitor field lands.
hl.bind(mainMod .. " + SHIFT + comma",  hl.dsp.exec_cmd("hyprctl dispatch movewindow mon:-1"))
hl.bind(mainMod .. " + SHIFT + period", hl.dsp.exec_cmd("hyprctl dispatch movewindow mon:+1"))

-- Mouse. CTRL rather than SUPER, matching yabai's mouse_modifier on macOS;
-- the stock Hyprland config uses SUPER here.
hl.bind("CTRL + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind("CTRL + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Screenshots.
hl.bind("Print",         hl.dsp.exec_cmd("hyprshot -m output"))
hl.bind("SHIFT + Print", hl.dsp.exec_cmd("hyprshot -m region"))

-- Volume and microphone. wpctl comes from wireplumber, added to
-- pacman-packages.txt alongside the pipewire stack. locked = true keeps these
-- working while the screen is locked.
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),      { locked = true, repeating = true })
hl.bind("XF86AudioMute",        hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),     { locked = true })
hl.bind("XF86AudioMicMute",     hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),   { locked = true })

-- Screen brightness. brightnessctl goes through logind rather than writing to
-- sysfs, so no video group membership is needed. -e4 is a quartic curve, which
-- tracks perceived brightness better than a linear ramp at the dim end, and
-- -n2 clamps the minimum to 2 so the panel never goes fully black.
hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%+"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%-"), { locked = true, repeating = true })

-- Media transport over MPRIS. Play and Pause are separate keycodes on most
-- keyboards but both map to play-pause, matching the stock config.
hl.bind("XF86AudioNext",  hl.dsp.exec_cmd("playerctl next"),       { locked = true })
hl.bind("XF86AudioPrev",  hl.dsp.exec_cmd("playerctl previous"),   { locked = true })
hl.bind("XF86AudioPlay",  hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
