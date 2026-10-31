--!nonstrict
-- Touch-friendly Premium Server Finder panel. Attach to the existing ScreenGui.

local Controller = {}
local MODES = { "Empty Server", "Low Population", "Oldest Empty", "Low Ping", "Balanced" }

local function make(className, properties, parent)
	local object = Instance.new(className)
	for key, value in pairs(properties) do object[key] = value end
	object.Parent = parent
	return object
end

local function rounded(gui, radius)
	make("UICorner", { CornerRadius = UDim.new(0, radius or 8) }, gui)
end

local function label(parent, name, text, position, size, fontSize)
	return make("TextLabel", {
		Name = name, Position = position, Size = size,
		BackgroundTransparency = 1, Text = text,
		TextColor3 = Color3.fromRGB(235, 240, 248),
		TextSize = fontSize or 11, Font = Enum.Font.Gotham,
		TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true,
	}, parent)
end

function Controller.new(screenGui, service, entryAdapter, options)
	options = options or {}
	local self = {
		screenGui = screenGui, service = service, entry = entryAdapter,
		mode = "Empty Server", servers = {}, filtered = {}, auto = false,
		ignoreRecent = true, maxPopulation = tonumber(options.maxPopulation) or 3,
		refreshInterval = tonumber(options.refreshInterval) or 30,
		retryCandidates = {}, retryIndex = 1, retryCount = 0,
		maxJoinAttempts = 3, pendingServer = nil, destroyed = false,
	}
	local openButton = make("TextButton", {
		Name = "ServerFinderOpen", Size = UDim2.fromOffset(58, 36),
		Position = UDim2.new(1, -70, 0, 12),
		BackgroundColor3 = Color3.fromRGB(31, 106, 168),
		BorderSizePixel = 0, Text = "SERVERS",
		TextColor3 = Color3.new(1, 1, 1), TextSize = 10, Font = Enum.Font.GothamBold,
	}, screenGui)
	rounded(openButton, 8)

	local panel = make("Frame", {
		Name = "ServerFinderPanel", Size = UDim2.fromOffset(300, 430),
		Position = UDim2.new(0, 10, 0, 120),
		BackgroundColor3 = Color3.fromRGB(20, 24, 32),
		BackgroundTransparency = 0.03, BorderSizePixel = 0, Visible = false,
	}, screenGui)
	rounded(panel, 12)
	make("UIStroke", { Color = Color3.fromRGB(70, 86, 110), Transparency = 0.25 }, panel)

	local title = label(panel, "Title", "ULTRABOOST • SERVER FINDER",
		UDim2.fromOffset(10, 8), UDim2.fromOffset(224, 22), 13)
	local closeButton = make("TextButton", {
		Name = "Close", Position = UDim2.fromOffset(266, 7), Size = UDim2.fromOffset(24, 24),
		BackgroundColor3 = Color3.fromRGB(139, 59, 69), Text = "×",
		TextColor3 = Color3.new(1, 1, 1), TextSize = 18, Font = Enum.Font.GothamBold,
		BorderSizePixel = 0,
	}, panel)
	rounded(closeButton, 6)

	local status = label(panel, "Status", "Ready • choose a search mode",
		UDim2.fromOffset(10, 34), UDim2.fromOffset(280, 22), 10)
	status.TextColor3 = Color3.fromRGB(167, 186, 208)

	local modeButtons = {}
	local widths = { 49, 54, 55, 45, 48 }
	local x = 10
	for index, name in ipairs(MODES) do
		local button = make("TextButton", {
			Name = "Mode" .. tostring(index), Position = UDim2.fromOffset(x, 60),
			Size = UDim2.fromOffset(widths[index], 32),
			BackgroundColor3 = name == self.mode and Color3.fromRGB(39, 111, 174) or Color3.fromRGB(54, 64, 82),
			BorderSizePixel = 0, Text = name == "Low Population" and "Low Pop" or name,
			TextColor3 = Color3.new(1, 1, 1), TextSize = 8,
			Font = Enum.Font.GothamSemibold, TextWrapped = true,
		}, panel)
		rounded(button, 6)
		modeButtons[name] = button
		x += widths[index] + 3
	end

	local populationBox = make("TextBox", {
		Name = "PopulationLimit", Position = UDim2.fromOffset(10, 99),
		Size = UDim2.fromOffset(55, 26), BackgroundColor3 = Color3.fromRGB(42, 50, 65),
		BorderSizePixel = 0, Text = tostring(self.maxPopulation), PlaceholderText = "Max",
		TextColor3 = Color3.new(1, 1, 1), TextSize = 11, Font = Enum.Font.Gotham,
		ClearTextOnFocus = false,
	}, panel)
	rounded(populationBox, 6)

	local ignoreButton = make("TextButton", {
		Name = "IgnoreRecent", Position = UDim2.fromOffset(72, 99),
		Size = UDim2.fromOffset(103, 26), BackgroundColor3 = Color3.fromRGB(51, 84, 72),
		BorderSizePixel = 0, Text = "Recent: ON", TextColor3 = Color3.new(1, 1, 1),
		TextSize = 9, Font = Enum.Font.GothamSemibold,
	}, panel)
	rounded(ignoreButton, 6)

	local refreshButton = make("TextButton", {
		Name = "Refresh", Position = UDim2.fromOffset(181, 99),
		Size = UDim2.fromOffset(51, 26), BackgroundColor3 = Color3.fromRGB(40, 101, 155),
		BorderSizePixel = 0, Text = "REFRESH", TextColor3 = Color3.new(1, 1, 1),
		TextSize = 8, Font = Enum.Font.GothamBold,
	}, panel)
	rounded(refreshButton, 6)

	local autoButton = make("TextButton", {
		Name = "AutoRefresh", Position = UDim2.fromOffset(238, 99),
		Size = UDim2.fromOffset(52, 26), BackgroundColor3 = Color3.fromRGB(77, 78, 94),
		BorderSizePixel = 0, Text = "AUTO OFF", TextColor3 = Color3.new(1, 1, 1),
		TextSize = 8, Font = Enum.Font.GothamBold,
	}, panel)
	rounded(autoButton, 6)

	local resultLabel = label(panel, "ResultCount", "No scan performed",
		UDim2.fromOffset(10, 130), UDim2.fromOffset(280, 18), 9)
	resultLabel.TextColor3 = Color3.fromRGB(161, 177, 199)

	local list = make("ScrollingFrame", {
		Name = "ServerList", Position = UDim2.fromOffset(10, 151),
		Size = UDim2.fromOffset(280, 210), BackgroundColor3 = Color3.fromRGB(27, 32, 42),
		BorderSizePixel = 0, ScrollBarThickness = 4, CanvasSize = UDim2.fromOffset(0, 0),
	}, panel)
	rounded(list, 7)
	local layout = make("UIListLayout", {
		Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder,
	}, list)
	make("UIPadding", {
		PaddingTop = UDim.new(0, 5), PaddingLeft = UDim.new(0, 5), PaddingRight = UDim.new(0, 5),
	}, list)
	layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		list.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y + 10)
	end)

	local historyLabel = label(panel, "History", "History: no entry attempts yet",
		UDim2.fromOffset(10, 366), UDim2.fromOffset(280, 24), 9)
	historyLabel.TextColor3 = Color3.fromRGB(160, 178, 200)
	local statsLabel = label(panel, "Stats", "Unique 0 • discarded 0 • visits 0 • tries 0 • errors 0",
		UDim2.fromOffset(10, 392), UDim2.fromOffset(280, 28), 8)
	statsLabel.TextColor3 = Color3.fromRGB(137, 154, 177)

	local function refreshStats()
		local stats = service:GetStats()
		statsLabel.Text = string.format("Unique %d • discarded %d • visits %d • tries %d • errors %d",
			stats.serversFound or 0, stats.discardedByFilters or 0,
			stats.visitedServers or 0, stats.attempts or 0, stats.requestErrors or 0)
		local history = service:GetHistory(1)
		historyLabel.Text = history[1]
			and ("Last: " .. history[1].id:sub(1, 12) .. " • " .. tostring(history[1].state))
			or "History: no entry attempts yet"
	end

	local function clearCards()
		for _, child in ipairs(list:GetChildren()) do
			if child ~= layout and not child:IsA("UIPadding") then child:Destroy() end
		end
	end

	local function filterOptions()
		local limit = tonumber(populationBox.Text)
		if limit then self.maxPopulation = math.clamp(math.floor(limit), 0, 100) end
		return { maxPopulation = self.maxPopulation, ignoreRecentlyVisited = self.ignoreRecent }
	end

	local function render()
		self.filtered = service:FilterServers(self.servers, self.mode, filterOptions())
		clearCards()
		if #self.filtered == 0 then
			label(list, "EmptyState", "No servers match these filters.",
				UDim2.fromOffset(8, 8), UDim2.fromOffset(250, 40), 10)
		end

		for index, server in ipairs(self.filtered) do
			local card = make("Frame", {
				Name = "Server_" .. tostring(index), Size = UDim2.new(1, -10, 0, 56),
				BackgroundColor3 = Color3.fromRGB(39, 47, 61), BorderSizePixel = 0,
				LayoutOrder = index,
			}, list)
			rounded(card, 6)
			local ping = server.ping ~= nil and (tostring(math.floor(server.ping + 0.5)) .. " ms") or "n/a"
			local fps = server.fps ~= nil and (tostring(math.floor(server.fps + 0.5)) .. " FPS") or "n/a"
			local population = server.playing ~= nil and server.maxPlayers ~= nil
				and (tostring(server.playing) .. "/" .. tostring(server.maxPlayers) .. " players")
				or (server.playing ~= nil and (tostring(server.playing) .. " players") or "population n/a")
			local current = server.isCurrent and " • CURRENT" or ""
			label(card, "Details", population .. " • ping " .. ping .. " • " .. fps .. current,
				UDim2.fromOffset(7, 5), UDim2.fromOffset(178, 18), 8)
			local age = "Observed " .. tostring(server.observations or 1) .. " time(s)"
			if server.emptyObservedSince then
				age = age .. " • empty observed " .. tostring(os.time() - server.emptyObservedSince) .. "s"
			end
			local observationLabel = label(card, "Observation", age,
				UDim2.fromOffset(7, 27), UDim2.fromOffset(178, 18), 8)
			observationLabel.TextColor3 = Color3.fromRGB(166, 183, 202)
			local join = make("TextButton", {
				Name = "Join", Position = UDim2.fromOffset(190, 12),
				Size = UDim2.fromOffset(78, 31),
				BackgroundColor3 = server.isCurrent and Color3.fromRGB(72, 75, 84) or Color3.fromRGB(36, 111, 169),
				BorderSizePixel = 0, Text = server.isCurrent and "CURRENT" or "JOIN",
				TextColor3 = Color3.new(1, 1, 1), TextSize = 9, Font = Enum.Font.GothamBold,
				Active = not server.isCurrent, AutoButtonColor = not server.isCurrent,
			}, card)
			rounded(join, 6)
			if not server.isCurrent then
				join.Activated:Connect(function()
					self.retryCandidates = self.filtered
					self.retryIndex = index
					self.retryCount = 0
					self.pendingServer = nil
					self:_attemptNext()
				end)
			end
		end

		resultLabel.Text = string.format("%d servers • mode: %s", #self.filtered, self.mode)
		refreshStats()
	end

	function self:_attemptNext()
		if self.destroyed then return end
		while self.retryIndex <= #self.retryCandidates and self.retryCount < self.maxJoinAttempts do
			local server = self.retryCandidates[self.retryIndex]
			self.retryIndex += 1
			if server and server.id ~= game.JobId then
				self.retryCount += 1
				self.pendingServer = server
				service:RecordAttempt(server, "requested")
				status.Text = "Requesting entry (" .. tostring(self.retryCount) .. "/" .. tostring(self.maxJoinAttempts) .. ")..."
				local ok, detail = entryAdapter:Join(game.PlaceId, server.id)
				if ok then
					status.Text = "Request sent • waiting for runtime result"
					refreshStats()
					return
				end
				service:RecordAttempt(server, "failed", detail)
				self.pendingServer = nil
				status.Text = "Entry failed: " .. tostring(detail)
			end
		end
		if self.pendingServer == nil then status.Text = "No more candidates • check runtime teleport support" end
		refreshStats()
	end

	local function refresh()
		if self.destroyed then return end
		status.Text = "Loading public server list..."
		task.spawn(function()
			local servers, metadata = service:FetchServers(game.PlaceId)
			if self.destroyed then return end
			if not servers then
				status.Text = "Search error: " .. tostring(metadata and metadata.error or "unknown")
				resultLabel.Text = "No fresh results"
				refreshStats()
				return
			end
			self.servers = servers
			status.Text = "Updated • " .. tostring(metadata.pages or 0) .. " page(s)"
			render()
		end)
	end

	for modeName, button in pairs(modeButtons) do
		button.Activated:Connect(function()
			self.mode = modeName
			for otherMode, otherButton in pairs(modeButtons) do
				otherButton.BackgroundColor3 = otherMode == modeName
					and Color3.fromRGB(39, 111, 174) or Color3.fromRGB(54, 64, 82)
			end
			render()
		end)
	end

	populationBox.FocusLost:Connect(render)
	ignoreButton.Activated:Connect(function()
		self.ignoreRecent = not self.ignoreRecent
		ignoreButton.Text = self.ignoreRecent and "Recent: ON" or "Recent: OFF"
		render()
	end)
	refreshButton.Activated:Connect(refresh)
	autoButton.Activated:Connect(function()
		self.auto = not self.auto
		if self.auto then
			autoButton.Text = "AUTO ON"
			autoButton.BackgroundColor3 = Color3.fromRGB(42, 111, 83)
			service:StartAutoRefresh(game.PlaceId, function(servers, metadata)
				if self.destroyed then return end
				if servers then
					self.servers = servers
					status.Text = "Auto-updated • " .. tostring(metadata.pages or 0) .. " page(s)"
					render()
				else
					status.Text = "Auto-refresh error • previous results kept"
					refreshStats()
				end
			end, self.refreshInterval)
		else
			service:StopAutoRefresh()
			autoButton.Text = "AUTO OFF"
			autoButton.BackgroundColor3 = Color3.fromRGB(77, 78, 94)
		end
	end)

	openButton.Activated:Connect(function()
		panel.Visible = not panel.Visible
		if panel.Visible and #self.servers == 0 then refresh() end
	end)
	closeButton.Activated:Connect(function() panel.Visible = false end)

	entryAdapter:SetResultHandler(function(stateName, payload)
		if self.destroyed or not self.pendingServer or payload.jobId ~= self.pendingServer.id then return end
		if stateName == "started" then
			service:RecordAttempt(self.pendingServer, "started", payload.state)
			status.Text = "Teleport started • arrival not confirmed"
			refreshStats()
		elseif stateName == "failed" then
			service:RecordAttempt(self.pendingServer, "failed", payload.message or payload.result or payload.state)
			status.Text = "Entry failed • trying another candidate"
			self.pendingServer = nil
			refreshStats()
			task.defer(function() self:_attemptNext() end)
		end
	end)

	self.openButton, self.panel, self.refresh = openButton, panel, refresh
	return self
end

function Controller:Destroy()
	self.destroyed = true
	self.service:StopAutoRefresh()
	self.entry:SetResultHandler(nil)
	if self.openButton then self.openButton:Destroy() end
	if self.panel then self.panel:Destroy() end
end

return Controller
