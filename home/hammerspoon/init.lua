-- Loaded for the message port alone, which is what lets `hs -c "..."` reach this
-- config from a shell. Without it the CLI answers "can't access Hammerspoon
-- message port Hammerspoon; is it running with the ipc module loaded?", and
-- there is then no way to tell a config that failed to reload from one that
-- reloaded and is behaving unexpectedly.
require("hs.ipc")

function bindHotkey(appName, appFileFinder, ctrlKey, key, hiddableAndResizable, wait)
	hs.hotkey.bind(
		ctrlKey,
		key,
		function()
			local app = hs.application.find(appName)
			-- print("application: ", tostring(app))
			local appStr = tostring(app)
			-- Sometimes the App found is 'ThemeWidgetControlViewService (Alacritty)'
			if not (app == nil) and not (string.find(appStr, "hs.window")) and app:name() == appName then
				if hiddableAndResizable then
					if app:isFrontmost() then
						app:hide()
					else
						resizeWindow(app)
					end
				end
			else
				app = open(appFileFinder, appName, hiddableAndResizable, wait)
			end
		end
	)
end

function resizeWindow(application)
	-- print("application: ",application)
	local nowspace = hs.spaces.focusedSpace()
	-- print("focused space:",nowspace)
	local screen = hs.screen.mainScreen()
	-- print("screen: ",screen)
	local app_window = application:mainWindow()
	-- print("app_window: ",app_window)
	hs.spaces.moveWindowToSpace(app_window, nowspace)
	local max = screen:fullFrame()
	-- Height of the status bar at the top of the screen, measured rather than
	-- hardcoded. fullFrame spans the whole display and frame is what is left once
	-- the system reserves the bar, so the difference between the two origins is
	-- the bar itself. It is not a constant: 33 points on this display, and
	-- different again on a notched panel or an external monitor, which is what a
	-- literal 32 would have got wrong the moment the window opened elsewhere.
	local high_bar = screen:frame().y - max.y
	local f = app_window:frame()
	f.x = max.x + 2
	f.y = max.y + high_bar + 2
	f.w = max.w - 3
	f.h = max.h/2
	hs.timer.doAfter(
		0.2,
		function()
			app_window:setFrame(f)
			-- The border is placed from here, not left to the window filter alone.
			-- This is the moment the geometry is final, and the filter reports no
			-- windowMoved for this setFrame, so nothing else would reposition it.
			showBorder(app_window)
		end
	)
	app_window:focus()
end

function open(appPathFinder, appName, hiddableAndResizable, waiting)
	if type(appPathFinder)~='string' then error('app must be a string',2) end
	local r= hs.application.launchOrFocus(appPathFinder) or hs.application.launchOrFocusByBundleID(appPathFinder)
	if not r then
		-- print("r is nil")
		return nil
	else
		if not hiddableAndResizable then
			return nil
		end

		wait = waiting or 2
		wait=(wait or 0)*1000000
		local CHECK_INTERVAL=100000

		find = nil
		mainWindow = nil

		hs.timer.doUntil(
		    function()
		      return (find and mainWindow) or wait<=0
		    end,
		    function()
	            find = hs.application.find(appName)
	            -- print("find value for AppName = ", appName," is: ", find)
	            if (find) then
	              mainWindow = find:mainWindow()
	              if (mainWindow) then
	                resizeWindow(find)
	                find:activate()
	              end
	            end
	            wait=wait-CHECK_INTERVAL
		    end,
		    0.1
		)

		return find
	end
end

function hideWhenUnFocus(applicationName)
	hs.window.filter.default:subscribe(
		hs.window.filter.windowUnfocused,
		function(window, appName)
			if (appName == applicationName) then
				local app = hs.application.find(appName)
				if (app) then
					-- print("hide app: ", appName, " parameter window: ", window, " focused window: ", hs.window.frontmostWindow(), " fontApplication: ", hs.application.frontmostApplication():title())
					if not string.find(hs.application.frontmostApplication():title(), appName) then
						app:hide()
					end
				end
			end
		end
	)
end

-- A thin border of its own around Alacritty, drawn here.
--
-- JankyBorders used to draw every window and this drew Alacritty, which was
-- blacklisted there so the two would not overlap. JankyBorders is gone now --
-- stopped and unregistered -- and OmniWM paints the borders instead.
--
-- OmniWM has no per-application blacklist, so it paints Alacritty too and this
-- one is drawn on top of it. Keeping both is deliberate: OmniWM's is a flat 5.0
-- points in a single colour with no distinction between focused and unfocused,
-- and this adds the thin orange line that marks the terminal out.
local BORDER_APP = "Alacritty"
-- Measured rather than derived, on a 2x display, back when JankyBorders drew the
-- 6.0-point band this was meant to halve: that band ran from 1 point inside the
-- frame to 3 points outside it, pure #FF9300 in the middle four device pixels
-- and antialiased at both ends. The stroke below lies entirely outside the
-- window, which is why 2.0 points of visible line comes out of a 0.75 width.
local BORDER_WIDTH = 0.75
-- The active_color from bordersrc, 0xffff9300, so the two borders match.
local BORDER_COLOR = { hex = "#FF9300", alpha = 1.0 }
-- macOS rounds window corners at 10 points. This is the one number here that is
-- a constant rather than a measurement: JankyBorders asks the window server for
-- each window's real radius and falls back to 9 when it cannot, and Hammerspoon
-- has no equivalent query.
local BORDER_RADIUS = 10

local borderCanvas = nil

function hideBorder()
	if borderCanvas then
		borderCanvas:hide()
	end
end

function showBorder(window)
	if not window then
		hideBorder()
		return
	end

	local f = window:frame()
	local half = BORDER_WIDTH / 2

	-- The stroke is placed entirely outside the window. hs.canvas centres a
	-- stroke on its path, so the path is the window frame grown by half the
	-- width; drawn on the frame itself, half the border would sit on top of the
	-- terminal's own first pixels. The canvas is then a full width larger than
	-- the window on every side, which is what the outer half needs.
	local canvasFrame = {
		x = f.x - BORDER_WIDTH,
		y = f.y - BORDER_WIDTH,
		w = f.w + 2 * BORDER_WIDTH,
		h = f.h + 2 * BORDER_WIDTH
	}

	if not borderCanvas then
		borderCanvas = hs.canvas.new(canvasFrame)
		-- Above the terminal, matching the order JankyBorders draws in, and on
		-- whatever space resizeWindow moved the window to.
		borderCanvas:level(hs.canvas.windowLevels.floating)
		borderCanvas:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces)
		borderCanvas:clickActivating(false)
		borderCanvas[1] = {
			type = "rectangle",
			action = "stroke",
			strokeWidth = BORDER_WIDTH,
			strokeColor = BORDER_COLOR,
			-- The radius belongs to the path, which is half a width outside the
			-- window, so the inner edge of the stroke is the one that ends up
			-- following the window's own 10 point corner.
			roundedRectRadii = { xRadius = BORDER_RADIUS + half, yRadius = BORDER_RADIUS + half }
		}
	else
		borderCanvas:frame(canvasFrame)
	end

	-- Element coordinates are relative to the canvas, not to the screen.
	borderCanvas[1].frame = {
		x = half,
		y = half,
		w = f.w + BORDER_WIDTH,
		h = f.h + BORDER_WIDTH
	}
	borderCanvas:show()
end

--
-- Both windowUnfocused and windowHidden are subscribed because they are not the
-- same event here: hideWhenUnFocus hides the whole application on unfocus, and
-- the hotkey hides it while it is still frontmost.
function borderWhenFocused(applicationName)
	local filter = hs.window.filter.new(false):setAppFilter(applicationName)
	filter:subscribe(hs.window.filter.windowFocused, function(window) showBorder(window) end)
	filter:subscribe(hs.window.filter.windowMoved, function(window) showBorder(window) end)
	-- windowVisible is the one that matters for the hotkey, and subscribing to it
	-- is not belt and braces. Logging every event of an ALT+D cycle produced only
	-- `unfocused`, `hidden`, then `visible`: bringing the terminal back emits no
	-- windowFocused and no windowMoved at all, so with the two above alone the
	-- border was never drawn on the one path that matters.
	filter:subscribe(hs.window.filter.windowVisible, function(window) showBorder(window) end)
	filter:subscribe(hs.window.filter.windowUnfocused, hideBorder)
	filter:subscribe(hs.window.filter.windowHidden, hideBorder)
	filter:subscribe(hs.window.filter.windowDestroyed, hideBorder)
end


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

-- OmniWM: hotkeys, listeners and everything that talks to omniwmctl.
-- Self-contained, see omniwm.lua.
--
-- Commented on purpose: OmniWM drives itself with its own bindings, and loading
-- this file would put a second handler on the same keys. Uncomment to get the
-- hotkeys and listeners this repo adds on top of it.
-- require("omniwm")

hs.application.enableSpotlightForNameSearches(true)
bindHotkey("Alacritty", "/Applications/Alacritty.app", { "Alt" }, "d", true)
bindHotkey("Alacritty", "/Applications/Alacritty.app", { "Alt" }, "a", true)
bindHotkey("Alacritty", "/Applications/Alacritty.app", { "Ctrl" }, "a", true)
bindHotkey("Alacritty", "/Applications/Alacritty.app", { "Ctrl","Alt" }, "a", true)
bindHotkey("IntelliJ IDEA", "/IntelliJ IDEA.app", { "Alt" }, "i", false)
-- hideWhenUnFocus('Alacritty')

borderWhenFocused(BORDER_APP)
