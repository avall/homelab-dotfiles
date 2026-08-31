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

-- The border around the Alacritty windows below is drawn here rather than by
-- JankyBorders, and there is exactly one reason for that: in JankyBorders the
-- border width is a global setting. `man borders` (1.9.0) lists blacklist and
-- whitelist as the only per-application options, and running a second instance
-- with a different width does not work either -- "if an instance of borders is
-- already running, subsequent invocations will update the existing process".
-- A 3.0 border on Alacritty and the 6.0 every other window keeps therefore
-- cannot both come out of that tool.
--
-- So Alacritty is blacklisted in yabai/yabairc, where borders is started, and
-- the border it loses is redrawn below at half the width and the same colour.
local BORDER_APP = "Alacritty"
-- Half of what the other windows show, which is 4.0 points and not the 6.0 in
-- yabairc. JankyBorders never paints its full width: it strokes the window frame
-- centred and then clips everything more than 1 point inside the window
-- (src/border.c, clipped against a rounded rect at CGRectInset(frame, 1.0, 1.0)),
-- so width=6.0 lands 3.0 outside the window and 1.0 over it.
--
-- Measured rather than derived, on a 2x display: the band runs from 1 point
-- inside the frame to 3 points outside it, pure #FF9300 in the middle four
-- device pixels and antialiased at both ends. The stroke below lies entirely
-- outside the window, so 2.0 is the number that halves what is on screen.
local BORDER_WIDTH = 0.75
-- The active_color from yabairc, 0xffff9300, so the two borders match.
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

hs.application.enableSpotlightForNameSearches(true)
bindHotkey("Alacritty", "/Applications/Alacritty.app", { "Alt" }, "d", true)
bindHotkey("Alacritty", "/Applications/Alacritty.app", { "Alt" }, "a", true)
bindHotkey("IntelliJ IDEA", "/IntelliJ IDEA.app", { "Alt" }, "i", false)
hideWhenUnFocus('Alacritty')
borderWhenFocused(BORDER_APP)
