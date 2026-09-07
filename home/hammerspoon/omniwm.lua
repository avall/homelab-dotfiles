-- Everything in this Hammerspoon configuration that talks to OmniWM.
--
-- Loaded from init.lua with `require("omniwm")`. Kept apart from it because the
-- rest of that file -- the application hotkeys, the Alacritty border, the quake
-- terminal geometry -- would work unchanged with no window manager at all,
-- while none of this would.
--
-- What is NOT here, deliberately, because OmniWM does it natively since its
-- settings.toml started decoding again:
--
--   Control+Option+Command+X       expel a window from its column
--   Control+Option+Command+Left    move the window to the left monitor
--   Control+Option+Command+Right   move it to the right monitor
--   Control+Tab                    focus the other monitor
--   Control+Option+Command+L       toggle the workspace layout
--
-- Those live in ~/.config/omniwm/settings.toml and are kept there by
-- home/omniwm/omniwm-mode.sh, which a launchd agent runs every 120 seconds.
-- Binding any of them here as well would put a second handler on the same key.
--
-- The floating rules and Terminal's Secure Keyboard Entry are handled by that
-- same agent and by com.avall.terminal-secure-entry, not from here.

-- Column width on ALT plus the keys the keycaps read as `-` and `=`.
--
-- The chord is not the same on both layouts, and that is the keyboard rather
-- than the software. On US both characters have a key of their own: `-` on
-- keycode 27, `=` on 24. A Spanish ISO number row is `1..0 ' ¡`, so only the
-- minus has one, on keycode 44, and the equals sign is the shifted face of `0`,
-- keycode 29 -- exactly the keys you press to type either character on that
-- keyboard. A single chord cannot cover both because the unshifted `=` does not
-- exist on an ISO Spanish board.
--
-- `hs.keycodes.map` is no help: asked for "=" under Spanish ISO it answers 24,
-- the US position, which on that layout prints `¡`. So the mapping is by layout,
-- and `hs.keycodes.inputSourceChanged` reapplies it -- plug in a US keyboard and
-- the keys become plain Alt+- and Alt+= with no Shift, with nothing to change.
local OMNIWMCTL_PATH = nil
for _, candidate in ipairs({ "/opt/homebrew/bin/omniwmctl", "/usr/local/bin/omniwmctl" }) do
	if hs.fs.attributes(candidate) then
		OMNIWMCTL_PATH = candidate
		break
	end
end

-- Sends an absolute share rather than a relative step, and that is not a
-- refinement: `set-container-primary-span +10%` simply does not move some
-- windows. Measured on a Terminal.app window, three relative steps left it at
-- 748 points throughout, while `70%` took it to 1044 and `60%` to 900 on the
-- same window seconds later. Reading the current share and sending the target
-- works everywhere.
--
-- The share is read against `frameWidth - 2 * gap`, not the raw display width:
-- a lone column at 100% measured 2540 on a 2560-point display with a 9-point
-- gap, and two at 50% measured 1268 each, and only that denominator turns both
-- back into the percentages that produced them.
local function resizeSpan(delta)
	if not OMNIWMCTL_PATH then return end

	local function run(args, callback)
		local out = {}
		hs.task.new(OMNIWMCTL_PATH, function(_, stdout)
			if callback then callback(stdout) end
		end, args):start()
		return out
	end

	run({ "query", "displays", "--fields", "name,frame,inner-gap", "--format", "json" },
		function(displaysOut)
			local okD, displays = pcall(hs.json.decode, displaysOut or "")
			if not okD or not displays or not displays.ok then return end

			run({ "query", "windows", "--focused", "--fields", "mode,display,frame",
				"--format", "json" }, function(windowsOut)
				local okW, decoded = pcall(hs.json.decode, windowsOut or "")
				if not okW or not decoded or not decoded.ok then return end
				local window = decoded.result.payload.windows[1]
				if not window or window.mode ~= "tiling" or not window.frame then return end

				local name = type(window.display) == "table" and window.display.name
					or tostring(window.display)
				local frameWidth, gap
				for _, entry in ipairs(displays.result.payload.displays) do
					if entry.name == name and entry.frame then
						frameWidth, gap = entry.frame.width, entry.innerGap or 0
					end
				end
				if not frameWidth then return end

				local percent = window.frame.width / (frameWidth - 2 * gap) * 100
				-- Snapped to the step first, so a column left on an odd width by
				-- something else lands back on the grid rather than carrying the
				-- oddness forward.
				local target = math.floor(percent / 10 + 0.5) * 10 + delta
				target = math.max(10, math.min(100, target))
				run({ "command", "set-container-primary-span", target .. "%" })
			end)
		end)
end

local spanHotkeys = {}

local function bindSpanHotkeys()
	for _, hotkey in ipairs(spanHotkeys) do hotkey:delete() end
	spanHotkeys = {}
	if not OMNIWMCTL_PATH then return end

	local spanish = hs.keycodes.currentSourceID():find("Spanish", 1, true) ~= nil

	-- { modifiers, keycode, amount }
	local bindings = spanish
		and {
			{ { "alt" }, 44, -10 },              -- the `-` key
			{ { "alt", "shift" }, 29, 10 },      -- `=` is Shift+0
		}
		or {
			{ { "alt" }, 27, -10 },              -- the `-` key
			{ { "alt" }, 24, 10 },               -- the `=` key
		}

	for _, binding in ipairs(bindings) do
		local mods, code, delta = binding[1], binding[2], binding[3]
		spanHotkeys[#spanHotkeys + 1] = hs.hotkey.bind(mods, code, function()
			resizeSpan(delta)
		end)
	end
end

bindSpanHotkeys()
hs.keycodes.inputSourceChanged(bindSpanHotkeys)

-- Minimize the focused window on Control+Option+Command+M, in two steps, and the
-- first one is not optional.
--
-- OmniWM has no minimize of its own: it is absent from every hotkey id the app
-- serialises into settings.toml and from the omniwmctl command reference. macOS
-- offers nothing else either -- Command+M is the only standard shortcut that
-- minimizes a single window, Command+Option+M minimizes every window of the
-- front application and Command+H hides the application as a whole.
--
-- A plain minimize leaves the layout wrong. OmniWM goes on reserving the
-- window's slot and the columns beside it never grow, and it reports the window
-- as `mode=tiling, isVisible=false, hiddenReason=null`: a minimize through the
-- accessibility API is simply not something it observes. Neither `balance-sizes`
-- nor `rescue-offscreen-windows` forces a reflow afterwards; both were measured
-- and neither moved anything.
--
-- Floating the window first is what releases the slot, which is what takes it
-- out of the niri strip. Measured on a column holding a Finder and a Terminal:
-- the Terminal went from 643 to 1289 points tall the moment Finder floated, and
-- stayed there once Finder was minimized.
--
-- The ordering between the two steps is the hs.task callback, which fires when
-- omniwmctl exits, and nothing else. There is deliberately no wait in between:
-- the minimize was first written behind a 0.15 second timer to let OmniWM
-- reflow, and removing it changed nothing -- three runs on a five column strip
-- each left the window minimized and the four survivors at 1268 points.
--
-- The window comes back from the Dock still floating, so returning it to the
-- tiling layout is OmniWM's own toggle. Nothing can intercept a click on the
-- Dock icon to do that automatically.
local MINIMIZE_MOD = { "ctrl", "alt", "cmd" }

hs.hotkey.bind(MINIMIZE_MOD, "m", function()
	local window = hs.window.focusedWindow()
	if not window then return end

	if not OMNIWMCTL_PATH then
		window:minimize()
		return
	end

	-- Already-floating windows are left alone: toggling one of those would tile
	-- it, which is the opposite of what this key is for. Alacritty is the case
	-- that matters, since an appRule keeps it floating at all times.
	hs.task.new(OMNIWMCTL_PATH, function(_, stdout)
		if (stdout or ""):find('"floating"', 1, true) then
			window:minimize()
		else
			hs.task.new(OMNIWMCTL_PATH, function()
				window:minimize()
			end, { "command", "toggle-focused-window-floating" }):start()
		end
	end, { "query", "windows", "--focused", "--fields", "mode", "--format", "json" }):start()
end)

-- Put a window back in the scrolling strip when it returns from the Dock.
--
-- The minimize above floats the window to free its slot, and nothing undoes that
-- on the way back: it reappears floating, outside the layout, which is not what
-- minimizing a tiled window is supposed to mean.
--
-- `omniwmctl rule apply --window <id>` looked like the tidy way to do it and is
-- not: measured on a floated Slack window, it printed the rule table and left
-- `manualOverride=force-float` exactly as it was. Toggling is the only way back,
-- and the toggle acts on the focused window, so the window has to be focused
-- first.
--
-- Only windows this key floated are touched. OmniWM reports ours as
-- `manualOverride=force-float` and the ones an appRule floats -- Alacritty,
-- Stickies, Screen Sharing -- as `manualOverride=None`, so tiling those on the
-- way back, which would be wrong, cannot happen by accident.
--
-- The filter is `hs.window.filter.new(true)` rather than the default one. That
-- is not a stylistic choice: subscribing windowUnminimized on
-- hs.window.filter.default was measured firing zero times. Both it and the
-- subscription are held in upvalues, or they are collected and the callback
-- never runs again.
local unminimizeFilter = hs.window.filter.new(true)

local function retileOnUnminimize(window)
	if not OMNIWMCTL_PATH or not window then return end
	local windowID = window:id()
	if not windowID then return end

	hs.task.new(OMNIWMCTL_PATH, function(_, stdout)
		local ok, decoded = pcall(hs.json.decode, stdout or "")
		if not ok or type(decoded) ~= "table" or not decoded.ok then return end
		local windows = decoded.result and decoded.result.payload
			and decoded.result.payload.windows
		if not windows then return end

		for _, entry in ipairs(windows) do
			if entry.windowId == windowID then
				if entry.mode == "floating" and entry.manualOverride == "force-float" then
					-- Focus first, toggle second, ordered by the task callback
					-- rather than by a wait.
					hs.task.new(OMNIWMCTL_PATH, function()
						hs.task.new(OMNIWMCTL_PATH, nil,
							{ "command", "toggle-focused-window-floating" }):start()
					end, { "window", "focus", entry.id }):start()
				end
				return
			end
		end
	end, { "query", "windows", "--fields", "id,window-id,mode,manual-override",
		"--format", "json" }):start()
end

unminimizeFilter:subscribe(hs.window.filter.windowUnminimized, retileOnUnminimize)
