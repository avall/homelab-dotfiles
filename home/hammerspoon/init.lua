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
	local f = app_window:frame()
	f.x = max.x
	f.y = max.y
	f.w = max.w
	f.h = max.h/2
	hs.timer.doAfter(
		0.2,
		function()
			app_window:setFrame(f)
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

hs.application.enableSpotlightForNameSearches(true)
bindHotkey("Alacritty", "/Applications/Alacritty.app", { "Alt" }, "d", true)
bindHotkey("Alacritty", "/Applications/Alacritty.app", { "Alt" }, "a", true)
bindHotkey("IntelliJ IDEA", "/IntelliJ IDEA.app", { "Alt" }, "i", false)
hideWhenUnFocus('Alacritty')
