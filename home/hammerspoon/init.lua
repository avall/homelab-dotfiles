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
-- So Alacritty is blacklisted in borders/bordersrc, and the border it loses is
-- redrawn below at half the width and the same colour.
--
-- OmniWM draws borders of its own and is the obvious candidate to take this
-- over, but it cannot: its whole [borders] section is enabled, width and one
-- colour -- no blacklist, and no separate colour for unfocused windows, both of
-- which bordersrc uses. With its borders on, Alacritty would carry OmniWM's
-- border and the one below at the same time. `borders.enabled` is therefore
-- false in both omniwm/modes/*.toml and JankyBorders stays the only one drawing.
local BORDER_APP = "Alacritty"
-- Half of what the other windows show, which is 4.0 points and not the 6.0 in
-- bordersrc. JankyBorders never paints its full width: it strokes the window frame
-- centred and then clips everything more than 1 point inside the window
-- (src/border.c, clipped against a rounded rect at CGRectInset(frame, 1.0, 1.0)),
-- so width=6.0 lands 3.0 outside the window and 1.0 over it.
--
-- Measured rather than derived, on a 2x display: the band runs from 1 point
-- inside the frame to 3 points outside it, pure #FF9300 in the middle four
-- device pixels and antialiased at both ends. The stroke below lies entirely
-- outside the window, so 2.0 is the number that halves what is on screen.
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

-- ---------------------------------------------------------------------------
-- OmniWM
--
-- Three things OmniWM cannot bind itself, so they live here instead. Hammerspoon
-- runs in both OmniWM modes, which is what makes it the right place for the two
-- window actions: they behave identically whether the layout engine is niri or
-- dwindle.
--
-- The modifier is Control+Option+Command throughout. Option alone is taken:
-- OmniWM already binds Option+1..9, Option+Shift+1..9 and Option+arrows, and the
-- application hotkeys at the bottom of this file take Option+D, A and I.
local WM_MOD = { "ctrl", "alt", "cmd" }

-- Resolved once, at load, rather than looked up per keypress. Both paths are
-- checked because OmniWM links its CLI into whichever Homebrew prefix the
-- machine uses -- /opt/homebrew on Apple Silicon, /usr/local on Intel.
local OMNIWMCTL = nil
for _, candidate in ipairs({ "/opt/homebrew/bin/omniwmctl", "/usr/local/bin/omniwmctl" }) do
	if hs.fs.attributes(candidate) then
		OMNIWMCTL = candidate
		break
	end
end

-- Run a command without blocking, and without a login shell.
--
-- `hs.execute(cmd, true)` was the obvious way to write this and it is the wrong
-- one: the second argument runs the command through an interactive login shell,
-- which sources the entire zsh configuration -- plugins, starship, atuin,
-- zsh-abbr -- before it gets anywhere near the binary. Measured on this machine:
-- 803 ms that way against 30 ms for the binary called directly. On a hotkey that
-- is the difference between instant and visibly late.
--
-- hs.task also returns immediately instead of holding up Hammerspoon's event
-- loop for the round trip, so the keypress never feels stuck.
local function run(path, args, callback)
	if not path then
		hs.alert.show("omniwmctl not found")
		return
	end
	hs.task.new(path, callback, args):start()
end

-- Decodes an omniwmctl --format json reply, or nil if it was not one.
local function payload(stdout, kind)
	local ok, decoded = pcall(hs.json.decode, stdout or "")
	if not ok or type(decoded) ~= "table" or not decoded.ok then return nil end
	local result = decoded.result
	if type(result) ~= "table" or type(result.payload) ~= "table" then return nil end
	return result.payload[kind]
end

-- Columns are identified by where their windows start, because omniwmctl reports
-- no column of its own. Two windows in one column share an x while their widths
-- differ by a few points -- 1252 against 1256, measured -- so the comparison is
-- on x alone, with room to spare.
local COLUMN_X_TOLERANCE = 60

-- Flip the layout engine of the current workspace between niri and dwindle,
-- leaving gaps, rules and mouse bindings alone. The lighter of the two switches;
-- Control+Option+Command+W below swaps the whole configuration.
hs.hotkey.bind(WM_MOD, "l", function()
	run(OMNIWMCTL, { "command", "toggle-workspace-layout" })
end)

-- Full mode swap: rewrites ~/.config/omniwm/settings.toml from one of the two
-- mode files.
hs.hotkey.bind(WM_MOD, "w", function()
	run("/bin/bash", { os.getenv("HOME") .. "/.config/omniwm/omniwm-mode.sh", "toggle" },
		function(code, stdout)
			hs.alert.show(code == 0 and (stdout or ""):gsub("%s+$", "") or "OmniWM mode switch failed")
		end)
end)

-- Minimize, in two steps, and the first one is not optional.
--
-- OmniWM has no minimize of its own: it is absent from every hotkey id the app
-- serialises into settings.toml and from the omniwmctl command reference. The
-- obvious fallback, a plain macOS minimize, leaves the layout wrong -- OmniWM
-- goes on reserving the window's slot and the ones beside it never grow. It
-- reports the window as `mode=tiling, isVisible=false, hiddenReason=null`: a
-- minimize through the accessibility API is simply not something it observes.
-- Neither `balance-sizes` nor `rescue-offscreen-windows` forces a reflow
-- afterwards; both were measured and neither moved anything.
--
-- Floating the window first is what releases the slot. Measured on a column
-- holding a Finder and a Terminal: the Terminal went from 643 to 1289 points
-- tall the moment Finder floated, and stayed there once Finder was minimized.
--
-- The window comes back from the Dock still floating, so returning it to the
-- tiling layout is Control+Option+Command+F. Nothing can intercept a click on
-- the Dock icon to do that automatically.
hs.hotkey.bind(WM_MOD, "m", function()
	local window = hs.window.focusedWindow()
	if not window then return end

	local display = window:screen() and window:screen():name()

	-- A column left alone on a display keeps the span it had -- half the screen,
	-- centred -- instead of growing into the space the minimized window freed.
	-- `singleWindowFit` is set to Fill in OmniWM's own settings and does not do
	-- it; neither does `expand-container-to-available-primary-span` nor
	-- `toggle-container-full-primary-span`, both of which reported `executed` and
	-- moved nothing. Setting the span outright does work, and it needs the column
	-- focused, which after a minimize it is not -- focus lands wherever macOS
	-- sends it, often on another display entirely.
	local function fillIfLastOnDisplay()
		if not display then return end
		run(OMNIWMCTL, { "query", "windows", "--fields",
			"id,mode,display,is-visible,frame", "--format", "json" },
			function(_, out)
				local windows = payload(out, "windows")
				if not windows then return end

				local remaining = {}
				for _, other in ipairs(windows) do
					local name = type(other.display) == "table" and other.display.name
						or tostring(other.display)
					if other.mode == "tiling" and other.isVisible and other.id
						and name == display then
						remaining[#remaining + 1] = other
					end
				end
				if #remaining ~= 1 then return end

				run(OMNIWMCTL, { "window", "focus", remaining[1].id }, function()
					run(OMNIWMCTL, { "command", "set-container-primary-span", "100%" })
				end)
			end)
	end

	local function minimize()
		-- A beat after the float, so OmniWM has re-laid out the column before the
		-- window disappears from under it.
		hs.timer.doAfter(0.15, function()
			window:minimize()
			-- Long enough for the window to be gone from OmniWM's layout, so the
			-- count below is of what is really left.
			hs.timer.doAfter(0.5, fillIfLastOnDisplay)
		end)
	end

	-- Already-floating windows are left alone: toggling one of those would tile
	-- it, which is the opposite of what this key is for. Alacritty is the case
	-- that matters, since an appRule keeps it floating at all times.
	run(OMNIWMCTL, { "query", "windows", "--focused", "--fields", "mode", "--format", "json" },
		function(_, stdout)
			if (stdout or ""):find('"floating"', 1, true) then
				-- Already outside the layout, so nothing has to be freed first --
				-- but the display can still be left with a single column, and that
				-- one has to be grown just the same.
				window:minimize()
				hs.timer.doAfter(0.5, fillIfLastOnDisplay)
			else
				run(OMNIWMCTL, { "command", "toggle-focused-window-floating" }, minimize)
			end
		end)
end)

-- Genuinely circular column navigation on Option+Left and Option+Right.
--
-- OmniWM's own `niri.infiniteLoop` wraps the focus but not the viewport. With
-- five columns it goes, pressing right:
--
--   chrome+terminal1 -> terminal1+finder -> finder+sublime ->
--   sublime+terminal2 -> chrome+terminal1
--
-- and the pair that closes the circle, terminal2+chrome, never appears. It
-- cannot: in a strip drawn as a bounded row those two columns sit at opposite
-- ends, so there is no scroll position that shows them side by side.
--
-- What does produce it is rotating the strip instead of scrolling the viewport.
-- At the right-hand edge, moving the first column to the end leaves the former
-- last column beside it, which is exactly the missing pair -- verified:
-- `sublime+terminal2` became `terminal2+chrome`. Repeated, this rotates the
-- strip endlessly while keeping every column's relative order, which is what a
-- circular strip is.
--
-- The cost is real and worth stating: rotating changes the actual order of the
-- columns, not just what is on screen, so absolute column keys (Option+1..9,
-- focusColumn.N) point at different windows after a lap. A circular strip has no
-- stable first column, so this is inherent rather than a flaw in the approach.
--
-- These two keys must be cleared in OmniWM's own settings (focus.left and
-- focus.right, both Unassigned) or both bindings fire and the focus jumps two
-- columns at a time.

-- Even out the columns sharing the monitor, which is how you get back to two
-- windows at half the width each.
--
-- A complementary resize was built here first: widen the focused column, narrow
-- its neighbour by the same amount, both shares always adding to 100. It was
-- removed because it cannot be made to hold. Giving two columns complementary
-- widths does not pin the viewport to those two -- OmniWM re-scrolls the strip
-- and a third column comes into view instead. Measured from a clean 50/50 pair,
-- one press left the focused column at 60% beside a window that had not been on
-- screen at all, while the one it had just resized was gone.
--
-- The strip also drifts into states there is no way back from, because the
-- columns nobody is resizing keep whatever width they had -- 1522, 1256 and 1252
-- points against a 2560-point display -- and tile nothing when they scroll in.
-- One column ends up filling the monitor with no way to bring a second back.
--
-- `balance-sizes` is OmniWM's own answer and it works: on a strip with one
-- column at 1268 and four stacked off-screen it put two back at 1267 and 1268,
-- both fully visible. OmniWM's Option+= and Option+- still resize a single
-- column; this is the way back to an even split.
hs.hotkey.bind(WM_MOD, "b", function()
	run(OMNIWMCTL, { "command", "balance-sizes" })
end)

-- Widen and narrow the focused column, on the keys OmniWM lists for the job.
--
-- Bound here because OmniWM's own binding for them does not exist: settings.toml
-- records `setContainerPrimarySpan.increase10Percent` on Option+= and
-- `.decrease10Percent` on Option+-, but that file is an export OmniWM never
-- reads back, so nothing registers them. The proof is what reaches the terminal:
-- pressing them types the characters Option+= and Option+- produce on this
-- layout, the not-equal sign and an en dash. A handler owning those keys would
-- have swallowed the event long before it became text.
--
-- This resizes the focused column only. The neighbour keeps its own width and
-- loses whatever no longer fits, which on screen looks like the two sharing the
-- space; a version that really resized both was built and removed, see the note
-- on Control+Option+Command+B above.
hs.hotkey.bind({ "alt" }, "=", function()
	run(OMNIWMCTL, { "command", "set-container-primary-span", "+10%" })
end)
hs.hotkey.bind({ "alt" }, "-", function()
	run(OMNIWMCTL, { "command", "set-container-primary-span", "-10%" })
end)

-- Move the focused window out of a shared column into one of its own.
--
-- The listener below does this by itself for windows as they appear, but only
-- for those: a column stacked deliberately afterwards, with
-- `consume-window-into-column`, stays stacked. This is the manual way out.
hs.hotkey.bind(WM_MOD, "e", function()
	run(OMNIWMCTL, { "command", "expel-window-from-column" })
end)

-- Return a window to the tiling layout, or take it out of it.
--
-- Bound here rather than in OmniWM, although OmniWM has the action and a slot
-- for a hotkey on it: bindings written into settings.toml are never registered,
-- the same way the appRules in that file never reach App Rules. OmniWM persists
-- the file without reading it back, so the only bindings that exist are the ones
-- set in its own interface -- and the ones set here.
--
-- Its job is the return leg of Control+Option+Command+M. A window restored from
-- the Dock comes back floating, and this puts it back in the column.
hs.hotkey.bind(WM_MOD, "f", function()
	run(OMNIWMCTL, { "command", "toggle-focused-window-floating" })
end)

-- Put a window back in the tiling layout by itself when it returns from the
-- Dock, so the manual Control+Option+Command+F above is only ever needed as a
-- fallback.
--
-- The minimize hotkey floats a window before minimizing it, because that is the
-- only way OmniWM gives up its slot. Restoring it from the Dock therefore brings
-- back a floating window, and nothing can intercept that click. Watching for the
-- window to come back is the next best thing.
--
-- Three conditions, all checked against OmniWM rather than assumed:
--
--   * the workspace is on the niri layout,
--   * no appRule floats this application -- Alacritty is floating on purpose and
--     must stay that way, and `layoutReason` cannot be used to tell the two
--     apart: it reads "standard" for a rule-floated window and a hand-floated
--     one alike, as does `manualOverride`,
--   * the window really did come back floating, since toggling a tiled one would
--     float it and do the exact opposite of what this is for.
--
-- Each check is a separate omniwmctl call, chained through callbacks so the
-- event handler never blocks. This runs on a window returning from the Dock,
-- which is rare enough that three round trips cost nothing.

-- True when one of OmniWM's rules floats this application. Rules match either on
-- the exact bundle identifier or on a substring of the application name, which is
-- how the Karabiner-Elements rule is written.
local function ruleFloats(rules, bundleID, appName)
	for _, rule in ipairs(rules or {}) do
		if rule.layout == "float" then
			if bundleID and rule.bundleId == bundleID then return true end
			if appName and rule.appNameSubstring
				and appName:find(rule.appNameSubstring, 1, true) then
				return true
			end
		end
	end
	return false
end

local function retileOnUnminimize(window)
	if not window or not OMNIWMCTL then return end
	local app = window:application()
	if not app then return end
	local bundleID, appName = app:bundleID(), app:name()

	local function toggleBackToTiling()
		run(OMNIWMCTL, { "query", "windows", "--focused", "--fields", "mode", "--format", "json" },
			function(_, out)
				local windows = payload(out, "windows")
				-- Only when OmniWM agrees the window in front is this one and that
				-- it is floating. Restoring from the Dock can leave focus
				-- elsewhere, and toggling then would move the wrong window.
				local focused = windows and windows[1]
				if not focused or focused.mode ~= "floating" then return end
				if focused.app and focused.app.bundleId ~= bundleID then return end
				run(OMNIWMCTL, { "command", "toggle-focused-window-floating" })
			end)
	end

	run(OMNIWMCTL, { "query", "rules", "--format", "json" }, function(_, rulesOut)
		if ruleFloats(payload(rulesOut, "rules"), bundleID, appName) then return end
		run(OMNIWMCTL, { "query", "workspaces", "--focused", "--fields", "layout", "--format", "json" },
			function(_, wsOut)
				local workspaces = payload(wsOut, "workspaces")
				if not workspaces or not workspaces[1] or workspaces[1].layout ~= "niri" then
					return
				end
				-- A beat for the window to finish being restored and for focus to
				-- settle before asking OmniWM what is in front.
				hs.timer.doAfter(0.25, toggleBackToTiling)
			end)
	end)
end

-- A filter of its own, and specifically not hs.window.filter.default. The
-- default one only tracks visible windows, so a minimized window falls outside
-- its scope entirely and it never reports the window coming back --
-- windowUnminimized subscribed there fires zero times, measured. A filter built
-- with `new(true)` allows every window, which is what it takes to observe a
-- transition that starts from an invisible state.
local unminimizeFilter = hs.window.filter.new(true)
unminimizeFilter:subscribe(hs.window.filter.windowUnminimized, function(window)
	retileOnUnminimize(window)
end)

-- Keep one window per column: never let two of them split a column's height.
--
-- niri columns hold a stack, and a new window often lands in the one already in
-- front instead of opening beside it. There is no setting for this -- the whole
-- [niri] section is visibleContainerCount, infiniteLoop, centerFocusedColumn,
-- alwaysCenterSingleColumn, singleWindowFit, containerPrimarySpanPresets and
-- defaultContainerPrimarySpan, and none of them bounds how many windows a column
-- may hold. `expel-window-from-column` does move the focused window out into its
-- own column, so the stack is undone here as soon as it forms.
--
-- Only in the niri layout. Splitting a pane in two is what the dwindle engine is
-- for, and undoing it there would fight the layout rather than fix it.
--
local function expelFocusedIfStacked()
	if not OMNIWMCTL then return end

	run(OMNIWMCTL, { "query", "workspaces", "--focused", "--fields", "layout", "--format", "json" },
		function(_, wsOut)
			local workspaces = payload(wsOut, "workspaces")
			if not workspaces or not workspaces[1] or workspaces[1].layout ~= "niri" then
				return
			end

			run(OMNIWMCTL, { "query", "windows", "--fields",
				"app,mode,display,is-visible,is-focused,frame", "--format", "json" },
				function(_, winOut)
					local windows = payload(winOut, "windows")
					if not windows then return end

					local focused
					for _, window in ipairs(windows) do
						if window.isFocused then focused = window end
					end
					if not focused or focused.mode ~= "tiling" or not focused.frame then return end

					local displayOf = function(window)
						local display = window.display
						return type(display) == "table" and display.name or tostring(display)
					end

					local sharing = 0
					for _, window in ipairs(windows) do
						if window.mode == "tiling" and window.isVisible and window.frame
							and displayOf(window) == displayOf(focused)
							and math.abs(window.frame.x - focused.frame.x) < COLUMN_X_TOLERANCE then
							sharing = sharing + 1
						end
					end

					-- The focused window counts itself, so anything above one means
					-- it is sharing its column with something.
					if sharing > 1 then
						run(OMNIWMCTL, { "command", "expel-window-from-column" })
					end
				end)
		end)
end

-- A window is not in the layout the instant it appears, so the check waits for
-- OmniWM to place it before asking where it landed.
local newWindowFilter = hs.window.filter.new(true)
newWindowFilter:subscribe(hs.window.filter.windowCreated, function()
	hs.timer.doAfter(0.4, expelFocusedIfStacked)
end)

-- And on the way back from the Dock, which is a second way a column ends up
-- holding two windows: a window restored into a workspace does not necessarily
-- return to a column of its own. Seen with a Sublime Text and a Terminal sharing
-- one, 2540 by 643 each, half the height apiece.
--
-- Subscribed on this filter rather than the one above it because
-- expelFocusedIfStacked is declared between the two, and a closure made earlier
-- would not see it. The later delay leaves room for the re-tiling that the same
-- event triggers to finish first.
newWindowFilter:subscribe(hs.window.filter.windowUnminimized, function()
	hs.timer.doAfter(1.2, expelFocusedIfStacked)
end)

-- Put the floating rules back whenever OmniWM starts.
--
-- They do not survive a restart. OmniWM keeps its real configuration in an
-- internal store, and rules added through its interface or with `omniwmctl rule
-- add` are gone the next time it launches -- measured: 21 rules before a
-- restart, 13 after, none of the eight floating ones left. Writing them into
-- settings.toml does not help either; that file is an export OmniWM never reads
-- back.
--
-- So the rules are reapplied from here instead, by the one process that is
-- already running whenever OmniWM is. The switcher's `rules` subcommand only
-- adds what is missing, so running it on every launch costs nothing.
--
-- IPC is the one thing this cannot fix: it also resets on restart and there is
-- no way to turn it on except the "Enable IPC" item in OmniWM's menu bar icon.
-- Until that is clicked the sync below reports it and does nothing.
local omniwmWatcher = hs.application.watcher.new(function(name, event)
	if name ~= "OmniWM" or event ~= hs.application.watcher.launched then return end
	-- Several seconds, not one: OmniWM has to finish starting, and IPC only
	-- comes up once its socket is created.
	hs.timer.doAfter(6, function()
		run("/bin/bash", { os.getenv("HOME") .. "/.config/omniwm/omniwm-mode.sh", "rules" },
			function(_, stdout)
				local message = (stdout or ""):gsub("%s+$", "")
				if message ~= "" then hs.alert.show(message) end
			end)
	end)
end)
omniwmWatcher:start()

-- Send the focused window to the other display. omniwmctl only moves in a
-- direction, so with two monitors the direction has to be worked out from where
-- they actually sit -- a fixed "right" does nothing once the window is already
-- on the right-hand screen. The axis with the larger separation decides, so a
-- stacked arrangement works the same as a side-by-side one.
hs.hotkey.bind(WM_MOD, "o", function()
	local window = hs.window.focusedWindow()
	if not window then return end

	local here = window:screen()
	local there = nil
	for _, screen in ipairs(hs.screen.allScreens()) do
		if screen:id() ~= here:id() then
			there = screen
			break
		end
	end
	if not there then
		hs.alert.show("Only one display")
		return
	end

	local a, b = here:frame(), there:frame()
	local dx = (b.x + b.w / 2) - (a.x + a.w / 2)
	local dy = (b.y + b.h / 2) - (a.y + a.h / 2)

	local direction
	if math.abs(dx) >= math.abs(dy) then
		direction = dx > 0 and "right" or "left"
	else
		direction = dy > 0 and "down" or "up"
	end

	run(OMNIWMCTL, { "command", "move-to-monitor", direction })
end)
-- ---------------------------------------------------------------------------

-- Keep Terminal.app's Secure Keyboard Entry switched off.
--
-- While it is on, Terminal takes secure input for as long as it is frontmost and
-- nothing else on the system sees the keyboard: not event taps, not registered
-- hotkeys. Every binding in this file dies inside Terminal and nowhere else,
-- which reads as Terminal having stolen those keys when it has really taken the
-- whole keyboard. `ioreg` names the culprit -- kCGSSessionSecureInputPID points
-- at Terminal's pid.
--
-- osx/config/terminal/apply-terminal-theme.sh turns it off at provisioning time,
-- and that is not enough: Terminal switches it back on by itself. Caught in the
-- act more than once -- the preference read back as 1, the menu item was ticked
-- again, and the preferences file had been rewritten two minutes earlier. What
-- triggers it was never found, so it is undone here whenever it reappears.
--
-- Watching rather than setting the preference, because Terminal writes its whole
-- preferences file from memory and puts its own value back over anything
-- written behind it. The menu item is the only thing it listens to.
--
-- Checking through accessibility rather than by shelling out to `defaults` or
-- `ioreg`: this runs on a timer for as long as Terminal is up, and it is a local
-- call rather than a process launched every time.
local SECURE_ENTRY_APPLESCRIPT = [[
tell application "System Events"
    tell process "Terminal"
        set entry to menu item "Secure Keyboard Entry" of menu 1 of menu bar item "Terminal" of menu bar 1
        if (value of attribute "AXMenuItemMarkChar" of entry as text) is not "missing value" then
            click menu bar item "Terminal" of menu bar 1
            delay 0.4
            click entry
        end if
    end tell
end tell
]]

local function untickSecureKeyboardEntry()
	if not hs.application.get("Terminal") then return end
	-- osascript as a separate process, not hs.osascript. That runs on
	-- Hammerspoon's main thread and blocks it for the whole round trip -- with the
	-- delay this script needs, long enough for `hs -c` to give up waiting. On a
	-- timer it would stall the event loop every time it fired.
	hs.task.new("/usr/bin/osascript", nil, { "-e", SECURE_ENTRY_APPLESCRIPT }):start()
end

-- On every activation, so the keys are alive by the time a window is used, and
-- on a slow timer for the case where it comes back while Terminal already has
-- focus.
local secureEntryWatcher = hs.application.watcher.new(function(name, event)
	if name == "Terminal" and (event == hs.application.watcher.activated
		or event == hs.application.watcher.launched) then
		hs.timer.doAfter(0.5, untickSecureKeyboardEntry)
	end
end)
secureEntryWatcher:start()
-- Held in a variable on purpose. Hammerspoon collects a timer nothing keeps a
-- reference to, and this one stopped firing within seconds of being created
-- when it was left anonymous.
secureEntryTimer = hs.timer.doEvery(20, untickSecureKeyboardEntry)

hs.application.enableSpotlightForNameSearches(true)
bindHotkey("Alacritty", "/Applications/Alacritty.app", { "Alt" }, "d", true)
bindHotkey("Alacritty", "/Applications/Alacritty.app", { "Alt" }, "a", true)
bindHotkey("IntelliJ IDEA", "/IntelliJ IDEA.app", { "Alt" }, "i", false)
hideWhenUnFocus('Alacritty')
borderWhenFocused(BORDER_APP)
