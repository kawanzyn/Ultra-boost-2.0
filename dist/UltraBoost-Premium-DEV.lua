--[[
	ULTRABOOST BASIC v2.0.0-alpha.1 (visual engine based on v0.4.0)
	Client-side visual tuning with reversible Ultra, Balanced and Light modes.

	Uses standard client-side Roblox/Luau APIs only. No HTTP loader, executor-only
	APIs, hidden APIs, remote calls, instance deletion, or anti-cheat bypasses.
	Use only where local scripts are permitted. Results vary by experience/device.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
if not player then
	warn("[UltraBoost] LocalPlayer unavailable. Run in a client context.")
	return
end

local playerGui = player:WaitForChild("PlayerGui", 15)
if not playerGui then
	warn("[UltraBoost] PlayerGui unavailable.")
	return
end

local GUI_NAME = "UltraBoost_Basic_GUI"
if playerGui:FindFirstChild(GUI_NAME) then
	warn("[UltraBoost] Already running. Close the existing panel first.")
	return
end

local Terrain = Workspace:FindFirstChildOfClass("Terrain")
local WHITE = Color3.new(1, 1, 1)
local SMOOTH = Enum.Material.SmoothPlastic

local destroyed = false
local activeMode = nil
local collisionEnabled = false
local monitorEnabled = true
local watchersActive = false
local operationBusy = false

-- Separate snapshots keep visual mode switching independent from collision.
-- Strong keys keep temporarily reparented instances available for reliable restore.
local visualSaved = {}
local collisionSaved = {}
local terrainColorsSaved = {}
local watcherConnections = {}
local scanSerial = {}
local scanCounter = 0
local monitorConnection = nil

local function rememberAndSet(store, instance, property, value)
	local values = store[instance]
	if not values then
		values = {}
		store[instance] = values
	end

	-- A wrapper preserves even nil originals as a recorded value.
	if values[property] == nil then
		local ok, original = pcall(function()
			return instance[property]
		end)
		if not ok then
			return false
		end
		values[property] = { value = original }
	end

	return pcall(function()
		instance[property] = value
	end)
end

local function restoreStore(store)
	local entries = {}
	for instance, values in pairs(store) do
		table.insert(entries, { instance = instance, values = values })
	end
	table.clear(store)

	-- Restore in small batches to avoid a large one-frame spike.
	local processed = 0
	for _, entry in ipairs(entries) do
		for property, saved in pairs(entry.values) do
			pcall(function()
				entry.instance[property] = saved.value
			end)
		end
		processed += 1
		if processed % 80 == 0 then
			task.wait()
		end
	end
end

local function restoreTerrainColors()
	if not Terrain then
		table.clear(terrainColorsSaved)
		return
	end

	for material, originalColor in pairs(terrainColorsSaved) do
		pcall(function()
			Terrain:SetMaterialColor(material, originalColor)
		end)
	end
	table.clear(terrainColorsSaved)
end

local function applyWhiteTerrain()
	if not Terrain then
		return
	end

	local ok, materials = pcall(function()
		return Enum.Material:GetEnumItems()
	end)
	if not ok then
		return
	end

	for _, material in ipairs(materials) do
		local gotColor, originalColor = pcall(function()
			return Terrain:GetMaterialColor(material)
		end)
		if gotColor and terrainColorsSaved[material] == nil then
			terrainColorsSaved[material] = originalColor
		end
		pcall(function()
			Terrain:SetMaterialColor(material, WHITE)
		end)
	end
end

local protectedNameParts = {
	"player", "character", "npc", "enemy", "boss", "humanoid",
	"tool", "weapon", "item", "pickup", "collect", "coin", "egg",
	"objective", "quest", "checkpoint", "spawn", "portal", "button",
	"switch", "lever", "door", "vehicle", "pet", "shop", "gui",
}

local groundNameParts = {
	"ground", "floor", "baseplate", "terrain", "road", "path",
	"sidewalk", "pavement", "walkway",
}

local function containsAny(text, fragments)
	local lowered = string.lower(text)
	for _, fragment in ipairs(fragments) do
		if string.find(lowered, fragment, 1, true) then
			return true
		end
	end
	return false
end

local function isProtectedSelf(instance)
	local className = instance.ClassName
	if className == "Model" and instance:FindFirstChildOfClass("Humanoid") then
		return true
	end
	if className == "Tool" or className == "Accessory" then
		return true
	end

	-- Only inspect names on objects that can contain or represent gameplay objects.
	if className == "Model" or className == "Folder"
		or className == "Tool" or className == "Accessory"
		or instance:IsA("BasePart") then
		return containsAny(instance.Name, protectedNameParts)
	end
	return false
end

local function isProtectedObject(instance)
	local current = instance
	while current and current ~= Workspace and current ~= Lighting do
		if isProtectedSelf(current) then
			return true
		end
		current = current.Parent
	end
	return false
end

local function isGroundPart(part)
	local current = part
	while current and current ~= Workspace do
		if containsAny(current.Name, groundNameParts) then
			return true
		end
		current = current.Parent
	end

	-- Conservative fallback for large, thin, upward-facing anchored surfaces.
	local size = part.Size
	local area = size.X * size.Z
	local thinLimit = math.max(4, math.min(size.X, size.Z) * 0.08)
	return part.Anchored
		and area >= 400
		and size.Y <= thinLimit
		and part.CFrame.UpVector.Y >= 0.85
end

-- Environment classification is performed once per relevant instance in applyInstance.

local function hideTexture(instance)
	if instance:IsA("Decal") or instance:IsA("Texture") then
		rememberAndSet(visualSaved, instance, "Transparency", 1)
	elseif instance:IsA("SurfaceAppearance") then
		-- Clearing maps exposes the underlying part color/material where supported.
		for _, property in ipairs({ "ColorMap", "NormalMap", "RoughnessMap", "MetalnessMap" }) do
			rememberAndSet(visualSaved, instance, property, "")
		end
	end
end

local function isEffectObject(instance)
	local className = instance.ClassName
	return className == "ParticleEmitter"
		or className == "Trail"
		or className == "Beam"
		or className == "BloomEffect"
		or className == "BlurEffect"
		or className == "ColorCorrectionEffect"
		or className == "DepthOfFieldEffect"
		or className == "SunRaysEffect"
		or className == "Fire"
		or className == "Smoke"
		or className == "Sparkles"
end

local function applyInstance(instance, knownProtected)
	if destroyed then
		return
	end

	local className = instance.ClassName
	local isPart = instance:IsA("BasePart")
	local isTextureObject = className == "Decal"
		or className == "Texture"
		or className == "SurfaceAppearance"
	local isEffect = isEffectObject(instance)

	if not isPart and not isTextureObject and not isEffect then
		return
	end

	local mode = activeMode
	if not mode and not (collisionEnabled and isPart) then
		return
	end

	local protected = knownProtected
	if protected == nil then
		protected = isProtectedObject(instance)
	end

	local ground = false
	local environment = false
	local textureEligible = false

	if not protected and isPart and instance:IsDescendantOf(Workspace) then
		ground = isGroundPart(instance)
		environment = instance.Anchored and not ground
	elseif not protected and isTextureObject then
		local parentPart = instance:FindFirstAncestorWhichIsA("BasePart")
		if parentPart and parentPart:IsDescendantOf(Workspace) then
			ground = isGroundPart(parentPart)
			environment = parentPart.Anchored and not ground
			textureEligible = ground or environment
		elseif instance:IsDescendantOf(Lighting) then
			textureEligible = true
		end
	end

	if mode and not protected then
		if isPart and (ground or environment) then
			rememberAndSet(visualSaved, instance, "Material", SMOOTH)
			rememberAndSet(visualSaved, instance, "MaterialVariant", "")

			if mode == "Ultra" then
				if environment then
					rememberAndSet(visualSaved, instance, "LocalTransparencyModifier", 1)
					rememberAndSet(visualSaved, instance, "CastShadow", false)
				end
			elseif mode == "Balanced" then
				rememberAndSet(visualSaved, instance, "Color", WHITE)
				rememberAndSet(visualSaved, instance, "CastShadow", false)
			end
		elseif isTextureObject and textureEligible then
			hideTexture(instance)
		elseif isEffect and mode ~= "Light" then
			rememberAndSet(visualSaved, instance, "Enabled", false)
		end
	end

	-- Ground, characters, tools and gameplay-named objects are never eligible.
	if collisionEnabled and isPart and environment then
		rememberAndSet(collisionSaved, instance, "CanCollide", false)
	end
end

local function scanRoot(root)
	if not root then
		return
	end

	scanCounter += 1
	local serial = scanCounter
	scanSerial[root] = serial

	task.spawn(function()
		local ok, initialChildren = pcall(function()
			return root:GetChildren()
		end)
		if not ok then
			return
		end

		-- Skip protected subtrees instead of inspecting every descendant of characters/NPCs.
		local stack = {}
		for _, child in ipairs(initialChildren) do
			table.insert(stack, child)
		end

		local sliceStarted = os.clock()
		local processed = 0
		while #stack > 0 do
			if destroyed or scanSerial[root] ~= serial then
				return
			end
			if not activeMode and not collisionEnabled then
				return
			end

			local instance = table.remove(stack)
			local protected = isProtectedSelf(instance)
			applyInstance(instance, protected)

			if not protected then
				local childOk, children = pcall(function()
					return instance:GetChildren()
				end)
				if childOk then
					for _, child in ipairs(children) do
						table.insert(stack, child)
					end
				end
			end

			processed += 1
			-- Bound each scan slice to reduce frame-time spikes on large maps.
			if os.clock() - sliceStarted >= 0.0015 or processed % 60 == 0 then
				task.wait()
				sliceStarted = os.clock()
			end
		end
	end)
end

local function disconnectWatchers()
	for _, connection in ipairs(watcherConnections) do
		pcall(function()
			connection:Disconnect()
		end)
	end
	table.clear(watcherConnections)

	watchersActive = false
	table.clear(scanSerial)
end

local function ensureWatchers()
	if watchersActive or (not activeMode and not collisionEnabled) then
		return
	end

	watchersActive = true
	-- CurrentCamera is already under Workspace, so scanning it separately duplicates work.
	table.insert(watcherConnections, Workspace.DescendantAdded:Connect(applyInstance))
	table.insert(watcherConnections, Lighting.DescendantAdded:Connect(applyInstance))
end

local function updateWatchers()
	if activeMode or collisionEnabled then
		ensureWatchers()
	else
		disconnectWatchers()
	end
end

local function applyTerrain(mode)
	if not Terrain then
		return
	end

	if mode == "Ultra" or mode == "Balanced" then
		rememberAndSet(visualSaved, Terrain, "Decoration", false)
		applyWhiteTerrain()
	end
end

local function applyMode(mode)
	if operationBusy or (mode ~= "Ultra" and mode ~= "Balanced" and mode ~= "Light") then
		return false
	end
	operationBusy = true

	-- Pause visual edits and invalidate any scan using the previous mode.
	activeMode = nil
	table.clear(scanSerial)

	-- Restore only visual properties; independent collision settings stay active.
	restoreStore(visualSaved)
	restoreTerrainColors()
	activeMode = mode

	if mode == "Ultra" or mode == "Balanced" then
		rememberAndSet(visualSaved, Lighting, "GlobalShadows", false)
	end

	applyTerrain(mode)
	updateWatchers()
	scanRoot(Workspace)
	scanRoot(Lighting)

	operationBusy = false
	return true
end

local function setCollisionEnabled(enabled)
	if operationBusy then
		return false
	end
	operationBusy = true
	collisionEnabled = enabled
	if not enabled then
		restoreStore(collisionSaved)
	else
		updateWatchers()
		scanRoot(Workspace)
	end
	updateWatchers()
	operationBusy = false
	return true
end

local function restoreAll()
	if operationBusy then
		return false
	end
	operationBusy = true
	activeMode = nil
	collisionEnabled = false
	disconnectWatchers()
	restoreStore(visualSaved)
	restoreStore(collisionSaved)
	restoreTerrainColors()
	operationBusy = false
	return true
end

-- Touch-friendly panel.
local screen = Instance.new("ScreenGui")
screen.Name = GUI_NAME
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = true
screen.DisplayOrder = 100
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.Size = UDim2.fromOffset(252, 322)
panel.Position = UDim2.new(0, 12, 0, 92)
panel.BackgroundColor3 = Color3.fromRGB(22, 25, 33)
panel.BackgroundTransparency = 0.06
panel.BorderSizePixel = 0
panel.Parent = screen

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 12)
panelCorner.Parent = panel

local panelStroke = Instance.new("UIStroke")
panelStroke.Color = Color3.fromRGB(70, 82, 105)
panelStroke.Transparency = 0.25
panelStroke.Thickness = 1
panelStroke.Parent = panel

local function makeLabel(name, text, position, size, fontSize)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Position = position
	label.Size = size
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = Color3.fromRGB(238, 241, 248)
	label.TextSize = fontSize
	label.Font = Enum.Font.GothamSemibold
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextWrapped = true
	label.Parent = panel
	return label
end

local title = makeLabel("Title", "ULTRABOOST  •  CLIENT", UDim2.fromOffset(10, 7), UDim2.fromOffset(174, 22), 13)
title.TextColor3 = Color3.fromRGB(112, 190, 255)
title.Active = true

local function makeSmallButton(name, text, x, color)
	local button = Instance.new("TextButton")
	button.Name = name
	button.Position = UDim2.fromOffset(x, 7)
	button.Size = UDim2.fromOffset(22, 22)
	button.BackgroundColor3 = color
	button.Text = text
	button.TextColor3 = Color3.new(1, 1, 1)
	button.TextSize = 17
	button.Font = Enum.Font.GothamBold
	button.BorderSizePixel = 0
	button.Parent = panel
	Instance.new("UICorner", button).CornerRadius = UDim.new(0, 6)
	return button
end

local closeButton = makeSmallButton("Close", "×", 220, Color3.fromRGB(145, 55, 65))
local minimizeButton = makeSmallButton("Minimize", "−", 194, Color3.fromRGB(65, 75, 92))

local fpsLabel = makeLabel("FPS", "FPS: --", UDim2.fromOffset(10, 33), UDim2.fromOffset(228, 18), 12)
fpsLabel.TextColor3 = Color3.fromRGB(190, 200, 215)

local statusLabel = makeLabel("Status", "Pronto • alterações locais", UDim2.fromOffset(10, 51), UDim2.fromOffset(230, 18), 10)
statusLabel.TextColor3 = Color3.fromRGB(160, 175, 195)

local function makeButton(name, text, y, height, color, callback)
	local button = Instance.new("TextButton")
	button.Name = name
	button.Position = UDim2.fromOffset(10, y)
	button.Size = UDim2.new(1, -20, 0, height)
	button.BackgroundColor3 = color
	button.BorderSizePixel = 0
	button.AutoButtonColor = true
	button.Text = text
	button.TextColor3 = Color3.new(1, 1, 1)
	button.TextSize = 13
	button.Font = Enum.Font.GothamSemibold
	button.Parent = panel
	Instance.new("UICorner", button).CornerRadius = UDim.new(0, 7)
	button.Activated:Connect(callback)
	return button
end

makeButton("Ultra", "⚡  ULTRA • ambiente mínimo", 75, 30, Color3.fromRGB(37, 103, 166), function()
	if applyMode("Ultra") then
		statusLabel.Text = "Ultra aplicado • cenário simplificado"
	else
		statusLabel.Text = "Aguarde a operação atual terminar"
	end
end)

makeButton("Balanced", "⚖  EQUILIBRADO • mapa branco", 109, 30, Color3.fromRGB(75, 91, 115), function()
	if applyMode("Balanced") then
		statusLabel.Text = "Equilibrado aplicado • mapa branco"
	else
		statusLabel.Text = "Aguarde a operação atual terminar"
	end
end)

makeButton("Light", "🪶  LEVE • plástico + sem texturas", 143, 30, Color3.fromRGB(53, 112, 91), function()
	if applyMode("Light") then
		statusLabel.Text = "Leve aplicado • cores preservadas"
	else
		statusLabel.Text = "Aguarde a operação atual terminar"
	end
end)

local collisionButton
collisionButton = makeButton("Collision", "COLISÃO AMBIENTAL: OFF", 179, 28, Color3.fromRGB(91, 78, 111), function()
	local nextState = not collisionEnabled
	if setCollisionEnabled(nextState) then
		collisionButton.Text = collisionEnabled and "COLISÃO AMBIENTAL: ON" or "COLISÃO AMBIENTAL: OFF"
		statusLabel.Text = collisionEnabled
			and "Colisão local desativada em peças ambientais elegíveis"
			or "Colisão original restaurada"
	else
		statusLabel.Text = "Aguarde a operação atual terminar"
	end
end)

local monitorButton
monitorButton = makeButton("Monitor", "MONITOR FPS: ON", 211, 28, Color3.fromRGB(75, 79, 96), function()
	monitorEnabled = not monitorEnabled
	monitorButton.Text = monitorEnabled and "MONITOR FPS: ON" or "MONITOR FPS: OFF"
	if not monitorEnabled then
		if monitorConnection then
			monitorConnection:Disconnect()
			monitorConnection = nil
		end
		fpsLabel.Text = "FPS: monitor desligado"
	else
		fpsLabel.Text = "FPS: --"
	end
end)

makeButton("Restore", "↩  RESTAURAR ORIGINAL", 243, 29, Color3.fromRGB(105, 68, 62), function()
	if restoreAll() then
		collisionButton.Text = "COLISÃO AMBIENTAL: OFF"
		statusLabel.Text = "Configurações originais restauradas"
	else
		statusLabel.Text = "Aguarde a operação atual terminar"
	end
end)

local footnote = makeLabel(
	"Footnote",
	"FPS estimado • colisão local não garantida pelo servidor",
	UDim2.fromOffset(10, 278),
	UDim2.fromOffset(230, 34),
	9
)
footnote.TextColor3 = Color3.fromRGB(145, 157, 177)

local miniButton = Instance.new("TextButton")
miniButton.Name = "ShowPanel"
miniButton.Size = UDim2.fromOffset(48, 42)
miniButton.Position = UDim2.new(0, 12, 0, 92)
miniButton.BackgroundColor3 = Color3.fromRGB(28, 105, 165)
miniButton.Text = "UB"
miniButton.TextColor3 = Color3.new(1, 1, 1)
miniButton.TextSize = 16
miniButton.Font = Enum.Font.GothamBold
miniButton.Visible = false
miniButton.BorderSizePixel = 0
miniButton.Parent = screen
Instance.new("UICorner", miniButton).CornerRadius = UDim.new(0, 10)

local consumeMiniDrag = function()
	return false
end

miniButton.Active = true
miniButton.Activated:Connect(function()
	if consumeMiniDrag() then
		return
	end
	panel.Visible = true
	miniButton.Visible = false
end)

minimizeButton.Activated:Connect(function()
	panel.Visible = false
	miniButton.Visible = true
end)

local dragConnections = {}


--[[ Premium Server Finder bundle. Generated from src/ServerFinder modules.
     Internal DEV build only: no key authentication or monetized unlock is active. ]]
local HttpClient = (function()
-- HTTP capability adapter for Premium Server Finder.
-- Public GET only. No account cookies, credentials or authenticated requests.

local HttpClient = {}
HttpClient.__index = HttpClient

local function getExecutorEnvironment()
	local env = _G
	local getter = rawget(_G, "getgenv")
	if type(getter) == "function" then
		local ok, result = pcall(getter)
		if ok and type(result) == "table" then env = result end
	end
	return env
end

local function normalizeResponse(response)
	if type(response) == "string" then
		return { StatusCode = 200, Body = response }
	end
	if type(response) ~= "table" then
		return nil, "HTTP provider returned an unsupported response"
	end
	local body = response.Body or response.body or response.ResponseBody
	local status = tonumber(response.StatusCode or response.Status or response.status_code) or 200
	if type(body) ~= "string" then
		return nil, "HTTP provider response did not contain a text body"
	end
	return { StatusCode = status, Body = body, Headers = response.Headers or response.headers }
end

function HttpClient.new(options)
	options = options or {}
	return setmetatable({
		_requestOverride = options.request,
		_httpService = game:GetService("HttpService"),
	}, HttpClient)
end

function HttpClient:Request(url)
	if type(self._requestOverride) == "function" then
		local ok, response = pcall(self._requestOverride, url)
		if not ok then return nil, tostring(response) end
		return normalizeResponse(response)
	end

	local env = getExecutorEnvironment()
	local candidates = {}
	local requestFunction = rawget(env, "request") or rawget(env, "http_request")
	if type(requestFunction) == "function" then table.insert(candidates, requestFunction) end

	local synTable = rawget(env, "syn")
	if type(synTable) == "table" and type(synTable.request) == "function" then
		table.insert(candidates, synTable.request)
	end
	local httpTable = rawget(env, "http")
	if type(httpTable) == "table" and type(httpTable.request) == "function" then
		table.insert(candidates, httpTable.request)
	end

	local lastProviderError = nil
	for _, provider in ipairs(candidates) do
		local ok, response = pcall(provider, {
			Url = url,
			Method = "GET",
			Headers = { Accept = "application/json" },
		})
		if ok then
			local normalized, normalizeError = normalizeResponse(response)
			if normalized then return normalized end
			lastProviderError = normalizeError
		else
			lastProviderError = tostring(response)
		end
	end

	local getOk, body = pcall(function() return game:HttpGet(url) end)
	if getOk and type(body) == "string" then
		return { StatusCode = 200, Body = body }
	end

	local serviceOk, serviceBody = pcall(function()
		return self._httpService:GetAsync(url, false)
	end)
	if serviceOk and type(serviceBody) == "string" then
		return { StatusCode = 200, Body = serviceBody }
	end

	local detail = "No compatible HTTP request provider is available"
	if lastProviderError then detail = detail .. ": " .. tostring(lastProviderError) end
	return nil, detail
end

function HttpClient:Decode(body)
	local ok, decoded = pcall(function() return self._httpService:JSONDecode(body) end)
	if not ok then return nil, "Invalid JSON response: " .. tostring(decoded) end
	if type(decoded) ~= "table" then return nil, "JSON response was not an object" end
	return decoded
end

return HttpClient

end)()
local ServerFinderServiceModule = (function(HttpClient)
-- Public server discovery, pagination, cache, ranking and local session history.
-- Oldest Empty is based only on this client's observations, never a claimed server age.

local Service = {}
Service.__index = Service

local API_ROOT = "https://games.roblox.com/v1/games/"
local DEFAULT_PAGE_LIMIT = 100

local function finiteNumber(value)
	local number = tonumber(value)
	if not number or number ~= number or number == math.huge or number == -math.huge then return nil end
	return number
end

local function safeInteger(value)
	local number = finiteNumber(value)
	if not number then return nil end
	return math.floor(number)
end

local function encodeCursor(value)
	if not value then return nil end
	local ok, encoded = pcall(function()
		return game:GetService("HttpService"):UrlEncode(value)
	end)
	if ok and type(encoded) == "string" then return encoded end
	return value
end

local function normalizeServer(raw)
	if type(raw) ~= "table" or type(raw.id) ~= "string" or raw.id == "" then return nil end
	local playing = safeInteger(raw.playing)
	local maxPlayers = safeInteger(raw.maxPlayers)
	local ping = finiteNumber(raw.ping)
	local fps = finiteNumber(raw.fps)
	if playing and playing < 0 then playing = nil end
	if maxPlayers and maxPlayers < 1 then maxPlayers = nil end
	if ping and ping < 0 then ping = nil end
	if fps and fps < 0 then fps = nil end
	return { id = raw.id, playing = playing, maxPlayers = maxPlayers, ping = ping, fps = fps }
end

function Service.new(options)
	options = options or {}
	local self = setmetatable({}, Service)
	self.http = options.httpClient or HttpClient.new(options.httpOptions)
	self.cacheTtl = math.max(tonumber(options.cacheTtl) or 15, 0)
	self.maxPages = math.max(1, math.floor(tonumber(options.maxPages) or 10))
	self.pageLimit = math.clamp(math.floor(tonumber(options.pageLimit) or DEFAULT_PAGE_LIMIT), 1, 100)
	self.recentVisitWindow = math.max(tonumber(options.recentVisitWindow) or 300, 0)
	self.failureCooldown = math.max(tonumber(options.failureCooldown) or 300, 0)
	self.retryCount = math.clamp(math.floor(tonumber(options.retryCount) or 4), 0, 6)
	self.cache, self.observations, self.visited, self.failed, self.history, self.uniqueIds = {}, {}, {}, {}, {}, {}
	self.busy = false
	self.autoToken = 0
	self.stats = {
		serversFound = 0, discardedByFilters = 0, visitedServers = 0,
		attempts = 0, teleportStarted = 0, successes = 0, failures = 0,
		requestErrors = 0, pagesFetched = 0, lastUpdated = nil,
	}
	return self
end

function Service:_requestPage(placeId, cursor)
	local cacheKey = tostring(placeId) .. "|" .. (cursor or "<first>")
	local cached = self.cache[cacheKey]
	if cached and os.clock() - cached.at <= self.cacheTtl then return cached.data, nil, true end

	local url = API_ROOT .. tostring(placeId) .. "/servers/Public?sortOrder=Asc&limit=" .. tostring(self.pageLimit)
	if cursor then url = url .. "&cursor=" .. encodeCursor(cursor) end

	local lastError = nil
	for attempt = 0, self.retryCount do
		local response, requestError = self.http:Request(url)
		if not response then
			lastError = requestError or "HTTP request failed"
			break
		end
		local status = tonumber(response.StatusCode) or 0
		if status == 429 or status >= 500 then
			lastError = "HTTP " .. tostring(status)
			if attempt < self.retryCount then task.wait(math.min(2 ^ attempt, 16)) end
		elseif status < 200 or status >= 300 then
			lastError = "HTTP " .. tostring(status)
			break
		else
			local decoded, decodeError = self.http:Decode(response.Body)
			if not decoded then
				lastError = decodeError
				break
			end
			if type(decoded.data) ~= "table" then
				lastError = "Server API response did not contain a data array"
				break
			end
			self.cache[cacheKey] = { at = os.clock(), data = decoded }
			return decoded, nil, false
		end
	end
	return nil, lastError or "Request failed", false
end

function Service:_observe(server, now)
	local observation = self.observations[server.id]
	if not observation then
		observation = {
			firstSeen = now, lastSeen = now, lastPlaying = server.playing,
			emptyObservedSince = if server.playing == 0 then now else nil,
			observations = 0,
		}
		self.observations[server.id] = observation
	else
		if server.playing == 0 then
			if observation.lastPlaying ~= 0 or not observation.emptyObservedSince then
				observation.emptyObservedSince = now
			end
		elseif server.playing ~= nil then
			observation.emptyObservedSince = nil
		end
		observation.lastSeen = now
		observation.lastPlaying = server.playing
	end
	observation.observations += 1
	server.firstSeen = observation.firstSeen
	server.lastSeen = observation.lastSeen
	server.emptyObservedSince = observation.emptyObservedSince
	server.observations = observation.observations
	local visit = self.visited[server.id]
	server.lastVisitedAt = visit and visit.at or nil
	local failure = self.failed[server.id]
	server.failedUntil = failure and failure.untilAt or nil
	server.isCurrent = game.JobId ~= "" and server.id == game.JobId
	if not self.uniqueIds[server.id] then
		self.uniqueIds[server.id] = true
		self.stats.serversFound += 1
	end
end

function Service:FetchServers(placeId, options)
	placeId = safeInteger(placeId or game.PlaceId)
	if not placeId or placeId <= 0 then return nil, { error = "A valid PlaceId is required" } end
	if self.busy then return nil, { error = "A server scan is already running", busy = true } end
	self.busy = true

	local ok, result, metadata = pcall(function()
		local all, unique, cursors = {}, {}, {}
		local cursor, pages, cacheHits = nil, 0, 0
		local now = os.time()
		repeat
			pages += 1
			local page, pageError, wasCached = self:_requestPage(placeId, cursor)
			if not page then error(pageError or "Could not retrieve a server page") end
			if wasCached then cacheHits += 1 end
			for _, raw in ipairs(page.data) do
				local server = normalizeServer(raw)
				if server and not unique[server.id] then
					unique[server.id] = true
					self:_observe(server, now)
					table.insert(all, server)
				elseif server then
					for _, existing in ipairs(all) do
						if existing.id == server.id then
							existing.playing, existing.maxPlayers = server.playing, server.maxPlayers
							existing.ping, existing.fps = server.ping, server.fps
							self:_observe(existing, now)
							break
						end
					end
				end
			end
			local nextCursor = page.nextPageCursor
			if type(nextCursor) ~= "string" or nextCursor == "" then
				cursor = nil
			elseif cursors[nextCursor] then
				error("Repeated pagination cursor detected; scan stopped to prevent a loop")
			else
				cursors[nextCursor] = true
				cursor = nextCursor
			end
		until not cursor or pages >= self.maxPages

		self.stats.pagesFetched = pages
		self.stats.lastUpdated = now
		return all, {
			pages = pages, cacheHits = cacheHits, hasMore = cursor ~= nil,
			placeId = placeId, updatedAt = now,
		}
	end)

	self.busy = false
	if not ok then
		self.stats.requestErrors += 1
		return nil, { error = tostring(result) }
	end
	return result, metadata
end

local function populationRatio(server)
	if server.playing == nil or not server.maxPlayers or server.maxPlayers <= 0 then return nil end
	return math.clamp(server.playing / server.maxPlayers, 0, 1)
end

function Service:FilterServers(servers, mode, options)
	options = options or {}
	local now = os.time()
	local maxPopulation = math.max(0, math.floor(tonumber(options.maxPopulation) or 3))
	local ignoreRecent = options.ignoreRecentlyVisited ~= false
	local recentWindow = math.max(tonumber(options.recentVisitWindow) or self.recentVisitWindow, 0)
	local eligible, discarded = {}, 0

	for _, server in ipairs(servers or {}) do
		local keep = not server.isCurrent
		if keep and ignoreRecent and server.lastVisitedAt and now - server.lastVisitedAt < recentWindow then keep = false end
		if keep and server.failedUntil and server.failedUntil > now then keep = false end
		if keep then
			if mode == "Empty Server" or mode == "Oldest Empty" then
				keep = server.playing == 0
			elseif mode == "Low Population" then
				keep = server.playing ~= nil and server.playing <= maxPopulation
			elseif mode == "Low Ping" or mode == "Balanced" then
				keep = true
			else
				keep = false
			end
		end
		if keep then table.insert(eligible, server) else discarded += 1 end
	end

	local minPing, maxPing, maxRatio = math.huge, -math.huge, 0
	for _, server in ipairs(eligible) do
		if server.ping ~= nil then
			minPing = math.min(minPing, server.ping)
			maxPing = math.max(maxPing, server.ping)
		end
		local ratio = populationRatio(server)
		if ratio ~= nil then maxRatio = math.max(maxRatio, ratio) end
	end

	if mode == "Low Ping" then
		table.sort(eligible, function(a, b)
			if a.ping == nil then return false end
			if b.ping == nil then return true end
			if a.ping == b.ping then return a.id < b.id end
			return a.ping < b.ping
		end)
	elseif mode == "Oldest Empty" then
		table.sort(eligible, function(a, b)
			local at = a.emptyObservedSince or a.firstSeen or math.huge
			local bt = b.emptyObservedSince or b.firstSeen or math.huge
			if at == bt then return a.id < b.id end
			return at < bt
		end)
	elseif mode == "Balanced" then
		for _, server in ipairs(eligible) do
			local sum, weight = 0, 0
			local ratio = populationRatio(server)
			if ratio ~= nil and maxRatio > 0 then
				sum += (1 - ratio / maxRatio) * 0.60
				weight += 0.60
			end
			if server.ping ~= nil and maxPing > minPing then
				sum += ((maxPing - server.ping) / (maxPing - minPing)) * 0.40
				weight += 0.40
			end
			server._balancedScore = if weight > 0 then sum / weight else nil
		end
		table.sort(eligible, function(a, b)
			if a._balancedScore == nil then return false end
			if b._balancedScore == nil then return true end
			if a._balancedScore == b._balancedScore then
				local ap, bp = a.playing or math.huge, b.playing or math.huge
				if ap == bp then return a.id < b.id end
				return ap < bp
			end
			return a._balancedScore > b._balancedScore
		end)
	elseif mode == "Low Population" then
		table.sort(eligible, function(a, b)
			local ap, bp = a.playing or math.huge, b.playing or math.huge
			if ap == bp then return a.id < b.id end
			return ap < bp
		end)
	else
		table.sort(eligible, function(a, b)
			local at, bt = a.firstSeen or math.huge, b.firstSeen or math.huge
			if at == bt then return a.id < b.id end
			return at < bt
		end)
	end

	self.stats.discardedByFilters = discarded
	self.stats.visitedServers = 0
	for _ in pairs(self.visited) do self.stats.visitedServers += 1 end
	return eligible, discarded
end

function Service:RecordAttempt(server, state, detail)
	if not server or type(server.id) ~= "string" then return false end
	local now = os.time()
	table.insert(self.history, 1, {
		id = server.id, playing = server.playing, maxPlayers = server.maxPlayers,
		ping = server.ping, at = now, state = state, detail = detail,
	})
	while #self.history > 30 do table.remove(self.history) end

	if state == "requested" then
		self.stats.attempts += 1
		self.visited[server.id] = { at = now }
	elseif state == "started" then
		self.stats.teleportStarted += 1
	elseif state == "failed" then
		self.stats.failures += 1
		self.failed[server.id] = { untilAt = now + self.failureCooldown }
	elseif state == "completed" then
		self.stats.successes += 1
	end
	return true
end

function Service:GetHistory(limit)
	local result = {}
	local maximum = math.clamp(math.floor(tonumber(limit) or 10), 1, 30)
	for index = 1, math.min(maximum, #self.history) do table.insert(result, self.history[index]) end
	return result
end

function Service:GetStats()
	local copy = {}
	for key, value in pairs(self.stats) do copy[key] = value end
	return copy
end

function Service:StartAutoRefresh(placeId, callback, interval, options)
	self:StopAutoRefresh()
	self.autoToken += 1
	local token = self.autoToken
	local delaySeconds = math.clamp(tonumber(interval) or 30, 10, 300)
	task.spawn(function()
		while token == self.autoToken do
			task.wait(delaySeconds)
			if token ~= self.autoToken then break end
			local servers, metadata = self:FetchServers(placeId, options)
			if token == self.autoToken and type(callback) == "function" then
				task.spawn(function() pcall(callback, servers, metadata) end)
			end
		end
	end)
	return true
end

function Service:StopAutoRefresh()
	self.autoToken += 1
end

function Service:Destroy()
	self:StopAutoRefresh()
	table.clear(self.cache)
end

return Service

end)(HttpClient)
local EntryAdapterModule = (function()
-- Best-effort standard TeleportService adapter.
-- A successful method call means "requested", not "destination entered".

local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")

local EntryAdapter = {}
EntryAdapter.__index = EntryAdapter

function EntryAdapter.new()
	local self = setmetatable({}, EntryAdapter)
	self.player = Players.LocalPlayer
	self.teleportService = TeleportService
	self.lastRequested = nil
	self.resultHandler = nil
	self.connections = {}

	local failedOk, failedSignal = pcall(function() return TeleportService.TeleportInitFailed end)
	if failedOk and failedSignal then
		local ok, connection = pcall(function()
			return failedSignal:Connect(function(player, result, message, placeId)
				if player == self.player and self.lastRequested then
					self:_emit("failed", {
						jobId = self.lastRequested.jobId,
						placeId = placeId,
						result = tostring(result),
						message = tostring(message),
					})
				end
			end)
		end)
		if ok and connection then table.insert(self.connections, connection) end
	end

	local teleportOk, teleportSignal = pcall(function() return self.player and self.player.OnTeleport end)
	if teleportOk and teleportSignal then
		local ok, connection = pcall(function()
			return teleportSignal:Connect(function(state, placeId)
				local text = tostring(state)
				if not self.lastRequested then return end
				if string.find(text, "Started", 1, true) or string.find(text, "InProgress", 1, true) then
					self:_emit("started", { jobId = self.lastRequested.jobId, placeId = placeId, state = text })
				elseif string.find(text, "Failed", 1, true) or string.find(text, "Cancelled", 1, true) then
					self:_emit("failed", { jobId = self.lastRequested.jobId, placeId = placeId, state = text })
				end
			end)
		end)
		if ok and connection then table.insert(self.connections, connection) end
	end
	return self
end

function EntryAdapter:SetResultHandler(callback)
	self.resultHandler = callback
end

function EntryAdapter:_emit(state, payload)
	if type(self.resultHandler) == "function" then
		task.spawn(function() pcall(self.resultHandler, state, payload) end)
	end
end

function EntryAdapter:GetCapabilities()
	local available, note = false, "Teleport method unavailable in this runtime"
	local ok, method = pcall(function() return self.teleportService.TeleportToPlaceInstance end)
	if ok and type(method) == "function" and self.player then
		available = true
		note = "Method exposed; actual permission is known only after an entry attempt"
	elseif not self.player then
		note = "LocalPlayer is unavailable"
	end
	return {
		teleportMethodAvailable = available,
		playerAvailable = self.player ~= nil,
		note = note,
	}
end

function EntryAdapter:Join(placeId, jobId)
	local capability = self:GetCapabilities()
	if not capability.teleportMethodAvailable then return false, capability.note end
	if type(jobId) ~= "string" or jobId == "" then return false, "Invalid JobId" end
	self.lastRequested = { placeId = placeId, jobId = jobId, at = os.time() }
	local ok, err = pcall(function()
		self.teleportService:TeleportToPlaceInstance(placeId, jobId, self.player)
	end)
	if not ok then return false, tostring(err) end
	return true, {
		state = "requested",
		jobId = jobId,
		note = "Teleport request submitted; destination entry is not yet confirmed",
	}
end

function EntryAdapter:Destroy()
	for _, connection in ipairs(self.connections) do
		pcall(function() connection:Disconnect() end)
	end
	table.clear(self.connections)
	self.lastRequested = nil
	self.resultHandler = nil
end

return EntryAdapter

end)()
local ServerFinderControllerModule = (function()
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
		local updated = stats.lastUpdated and os.date("%H:%M:%S", stats.lastUpdated) or "--"
		statsLabel.Text = string.format("Unique %d • filtered %d • visited %d\nTry %d • started %d • OK %d • failed %d • errors %d • %s",
			stats.serversFound or 0, stats.discardedByFilters or 0, stats.visitedServers or 0,
			stats.attempts or 0, stats.teleportStarted or 0, stats.successes or 0,
			stats.failures or 0, stats.requestErrors or 0, updated)
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

		local statsNow = service:GetStats()
		local updatedAt = statsNow.lastUpdated and os.date("%H:%M:%S", statsNow.lastUpdated) or "--"
		resultLabel.Text = string.format("%d servers • %s • current excluded • updated %s",
			#self.filtered, self.mode, updatedAt)
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

end)()
local serverFinderService = ServerFinderServiceModule.new()
local serverFinderEntry = EntryAdapterModule.new()
local serverFinderController = ServerFinderControllerModule.new(screen, serverFinderService, serverFinderEntry)


local function closeUltraBoost()
	if destroyed then
		return
	end
	if operationBusy then
		statusLabel.Text = "Aguarde a operação atual terminar"
		return
	end
	destroyed = true
	for _, connection in ipairs(dragConnections) do
		pcall(function()
			connection:Disconnect()
		end)
	end
	table.clear(dragConnections)
	if serverFinderController then serverFinderController:Destroy() end
	if serverFinderEntry then serverFinderEntry:Destroy() end
	if serverFinderService then serverFinderService:Destroy() end
	restoreAll()
	if monitorConnection then
		monitorConnection:Disconnect()
		monitorConnection = nil
	end
	screen:Destroy()
end

closeButton.Activated:Connect(closeUltraBoost)
screen.Parent = playerGui

-- Drag with mouse or finger. The title moves the full panel; the minimized
-- floating button can be repositioned independently and remains tappable.
local function makeDraggable(target, handle)
	handle.Active = true
	local dragging = false
	local dragInput = nil
	local dragStart = nil
	local startPosition = nil
	local moved = false
	local movedAt = 0

	table.insert(dragConnections, handle.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragInput = input
			dragStart = input.Position
			startPosition = target.Position
			moved = false
		end
	end))

	table.insert(dragConnections, UserInputService.InputChanged:Connect(function(input)
		if not dragging then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseMovement and input ~= dragInput then
			return
		end

		local delta = input.Position - dragStart
		if delta.Magnitude > 6 then
			moved = true
			movedAt = os.clock()
		end

		local x = startPosition.X.Offset + delta.X
		local y = startPosition.Y.Offset + delta.Y
		local camera = Workspace.CurrentCamera
		if camera then
			local viewport = camera.ViewportSize
			x = math.clamp(x, 0, math.max(0, viewport.X - target.AbsoluteSize.X))
			y = math.clamp(y, 0, math.max(0, viewport.Y - target.AbsoluteSize.Y))
		end
		target.Position = UDim2.fromOffset(x, y)
	end))

	table.insert(dragConnections, UserInputService.InputEnded:Connect(function(input)
		if input == dragInput or input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = false
			dragInput = nil
		end
	end))

	return function()
		local didMove = moved and (os.clock() - movedAt < 0.5)
		moved = false
		return didMove
	end
end

consumeMiniDrag = makeDraggable(miniButton, miniButton)
makeDraggable(panel, title)

local frames = 0
local elapsed = 0

local function startMonitor()
	if monitorConnection or not monitorEnabled or destroyed then
		return
	end

	monitorConnection = RunService.Heartbeat:Connect(function(deltaTime)
		if destroyed or not monitorEnabled then
			return
		end

		frames += 1
		elapsed += deltaTime
		if elapsed >= 1 then
			local fps = math.floor(frames / elapsed + 0.5)
			fpsLabel.Text = "FPS: " .. tostring(fps) .. " • estimativa local"
			frames = 0
			elapsed = 0
		end
	end)
end

monitorButton.Activated:Connect(function()
	if monitorEnabled then
		-- The callback above toggles the state; this branch is reached when re-enabled.
		startMonitor()
	else
		frames = 0
		elapsed = 0
	end
end)

startMonitor()
print("[UltraBoost Basic] v2.0.0-alpha.1 loaded. Choose Ultra, Equilibrado or Leve.")
