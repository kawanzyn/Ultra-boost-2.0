--[[
	ULTRABOOST PREMIUM DEV v2.0.0-alpha.2 (internal test build)
	Unified dashboard, reversible visual tuning, Custom Mode, Auto Optimizer,
	Performance Lab, Smart Restore and Server Finder.

	Visual changes are client-side. Server Finder probes runtime HTTP/teleport
	capabilities and may be unavailable in some executors. No account cookies,
	anti-cheat bypass, hidden APIs, server mutation or remote-event abuse.
	Internal DEV build: no key authentication or monetized license backend.
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

local GUI_NAME = "UltraBoost_Premium_DEV_GUI"
if playerGui:FindFirstChild(GUI_NAME) then
	warn("[UltraBoost] Already running. Close the existing panel first.")
	return
end

local Terrain = Workspace:FindFirstChildOfClass("Terrain")
local WHITE = Color3.new(1, 1, 1)
local SMOOTH = Enum.Material.SmoothPlastic

local destroyed = false
local activeMode = nil
local customSettings = nil
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

local restoreTerrainColors

local function restoreStoreMatching(store, predicate)
	for instance, values in pairs(store) do
		for property, saved in pairs(values) do
			local matches = false
			local ok, result = pcall(predicate, instance, property)
			if ok and result then matches = true end
			if matches then
				pcall(function() instance[property] = saved.value end)
				values[property] = nil
			end
		end
		if next(values) == nil then store[instance] = nil end
	end
end

local function restoreTextures()
	restoreStoreMatching(visualSaved, function(instance, property)
		return (instance:IsA("Decal") or instance:IsA("Texture") or instance:IsA("SurfaceAppearance"))
			and (property == "Transparency" or property == "ColorMap" or property == "NormalMap"
				or property == "RoughnessMap" or property == "MetalnessMap")
	end)
end

local function restoreMaterials()
	restoreStoreMatching(visualSaved, function(instance, property)
		return property == "Material" or property == "MaterialVariant"
	end)
end

local function restoreLighting()
	restoreStoreMatching(visualSaved, function(instance, property)
		return instance == Lighting or instance == Terrain or instance:IsDescendantOf(Lighting)
	end)
	restoreTerrainColors()
end

restoreTerrainColors = function()
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

local vegetationNameParts = { "tree", "grass", "leaf", "leaves", "bush", "plant", "flower", "vegetation", "foliage" }

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

local function isVegetationPart(part)
	local current = part
	while current and current ~= Workspace do
		if containsAny(current.Name, vegetationNameParts) then return true end
		current = current.Parent
	end
	return false
end

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
		if customSettings then
			if isPart and (ground or environment) then
				if customSettings.simplifyMaterials then
					rememberAndSet(visualSaved, instance, "Material", SMOOTH)
					rememberAndSet(visualSaved, instance, "MaterialVariant", "")
				end
				if customSettings.hideEnvironment and environment then
					rememberAndSet(visualSaved, instance, "LocalTransparencyModifier", 1)
				end
				if customSettings.hideVegetation and environment and isVegetationPart(instance) then
					rememberAndSet(visualSaved, instance, "LocalTransparencyModifier", 1)
				end
				if customSettings.hideShadows then
					rememberAndSet(visualSaved, instance, "CastShadow", false)
				end
			elseif isTextureObject and textureEligible then
				if (className == "Decal" and customSettings.hideDecals)
					or ((className == "Texture" or className == "SurfaceAppearance") and customSettings.hideTextures) then
					hideTexture(instance)
				end
			elseif isEffect and customSettings.hideEffects then
				rememberAndSet(visualSaved, instance, "Enabled", false)
			end
		elseif isPart and (ground or environment) then
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
	customSettings = nil
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

local function applyCustom(settings)
	if operationBusy or type(settings) ~= "table" then return false end
	operationBusy = true
	activeMode = nil
	table.clear(scanSerial)
	restoreStore(visualSaved)
	restoreTerrainColors()
	customSettings = {
		hideTextures = settings.hideTextures == true,
		hideDecals = settings.hideDecals == true,
		hideEffects = settings.hideEffects == true,
		hideVegetation = settings.hideVegetation == true,
		simplifyMaterials = settings.simplifyMaterials == true,
		hideShadows = settings.hideShadows == true,
		hideEnvironment = settings.hideEnvironment == true,
	}
	activeMode = "Custom"
	if customSettings.hideShadows then
		rememberAndSet(visualSaved, Lighting, "GlobalShadows", false)
	end
	if customSettings.hideVegetation and Terrain then
		rememberAndSet(visualSaved, Terrain, "Decoration", false)
	end
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
	customSettings = nil
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
panel.Visible = false
miniButton.Visible = false


--[[ Premium Server Finder bundle. Generated from src/ServerFinder modules.
     Internal DEV build only: no key authentication or monetized unlock is active. ]]
local HttpClient = (function()
--!nonstrict
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
--!nonstrict
-- Public server discovery, pagination, cache, ranking and local session history.
-- Oldest Empty is based only on this client's observations, never a claimed server age.

local HttpClient = require(script.Parent.HttpClient)
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
	elseif state == "started" then
		self.stats.teleportStarted += 1
	elseif state == "failed" then
		self.stats.failures += 1
		self.failed[server.id] = { untilAt = now + self.failureCooldown }
	elseif state == "completed" then
		self.stats.successes += 1
		self.visited[server.id] = { at = now }
	end
	self.stats.visitedServers = 0
	for _ in pairs(self.visited) do self.stats.visitedServers += 1 end
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
--!nonstrict
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
				if string.find(text, "Completed", 1, true) then
					self:_emit("completed", { jobId = self.lastRequested.jobId, placeId = placeId, state = text })
				elseif string.find(text, "Started", 1, true) or string.find(text, "InProgress", 1, true) then
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
local PremiumDashboardModule = (function()
--!nonstrict
-- UltraBoost Premium DEV dashboard. UI only; actions are injected from the bundled client.
local Dashboard = {}
Dashboard.__index = Dashboard

local C = {
	bg = Color3.fromRGB(12, 16, 24),
	panel = Color3.fromRGB(20, 27, 39),
	card = Color3.fromRGB(27, 36, 51),
	card2 = Color3.fromRGB(34, 45, 62),
	line = Color3.fromRGB(54, 69, 91),
	text = Color3.fromRGB(238, 243, 250),
	muted = Color3.fromRGB(153, 169, 190),
	blue = Color3.fromRGB(49, 143, 224),
	cyan = Color3.fromRGB(77, 201, 216),
	green = Color3.fromRGB(52, 164, 119),
	orange = Color3.fromRGB(211, 145, 61),
	red = Color3.fromRGB(190, 76, 85),
}

local function make(className, parent, properties)
	local object = Instance.new(className)
	for key, value in pairs(properties or {}) do
		object[key] = value
	end
	object.Parent = parent
	return object
end

local function corner(parent, radius)
	make("UICorner", parent, { CornerRadius = UDim.new(0, radius or 10) })
end

local function stroke(parent, color, transparency)
	make("UIStroke", parent, {
		Color = color or C.line,
		Transparency = transparency or 0.25,
		Thickness = 1,
	})
end

local function label(parent, value, size, color, bold)
	return make("TextLabel", parent, {
		BackgroundTransparency = 1,
		Size = size or UDim2.new(1, 0, 0, 22),
		AutomaticSize = Enum.AutomaticSize.Y,
		Text = value or "",
		TextColor3 = color or C.text,
		TextSize = 12,
		Font = bold and Enum.Font.GothamSemibold or Enum.Font.Gotham,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextWrapped = true,
	})
end

local function button(parent, value, color, size, callback)
	local b = make("TextButton", parent, {
		Size = size or UDim2.new(1, 0, 0, 36),
		BackgroundColor3 = color or C.card2,
		BorderSizePixel = 0,
		AutoButtonColor = true,
		Text = value,
		TextColor3 = C.text,
		TextSize = 11,
		Font = Enum.Font.GothamSemibold,
		TextWrapped = true,
	})
	corner(b, 8)
	b.Activated:Connect(callback)
	return b
end

local function card(parent, height)
	local f = make("Frame", parent, {
		Size = UDim2.new(1, 0, 0, height),
		BackgroundColor3 = C.card,
		BorderSizePixel = 0,
	})
	corner(f, 12)
	stroke(f, C.line, 0.45)
	return f
end

local function addPadding(parent, left, right, top, bottom)
	make("UIPadding", parent, {
		PaddingLeft = UDim.new(0, left or 12),
		PaddingRight = UDim.new(0, right or 12),
		PaddingTop = UDim.new(0, top or 10),
		PaddingBottom = UDim.new(0, bottom or 10),
	})
end

local function timeText(seconds)
	seconds = math.max(0, math.floor(seconds or 0))
	return string.format("%02d:%02d", math.floor(seconds / 60), seconds % 60)
end

function Dashboard.new(screen, api)
	local self = setmetatable({}, Dashboard)
	self.screen = screen
	self.api = api
	self.destroyed = false
	self.activePage = "Home"
	self.mode = api.getMode and (api.getMode() or "Original") or "Original"
	self.lastMode = nil
	self.collisionEnabled = false
	self.targetFps = 45
	self.autoEnabled = false
	self.autoProtection = true
	self.autoLowCount = 0
	self.autoHighCount = 0
	self.autoModeIndex = 1
	self.autoModes = { "Light", "Balanced", "Ultra" }
	self.sampleFrames = 0
	self.sampleElapsed = 0
	self.currentFps = 0
	self.samples = {}
	self.sessionMin = math.huge
	self.sessionMax = 0
	self.sessionTotal = 0
	self.sessionSampleCount = 0
	self.sessionStarted = os.clock()
	self.baseline = nil
	self.optimizedMark = nil
	self.quickHudEnabled = true
	self.profileStore = {}
	self.customSettings = {
		hideTextures = true,
		hideDecals = true,
		hideEffects = true,
		hideVegetation = false,
		simplifyMaterials = true,
		hideShadows = true,
		hideEnvironment = false,
	}
	self.finderMode = "Empty Server"
	self.finderServers = {}
	self.finderFiltered = {}
	self.finderAuto = false
	self.finderIgnoreRecent = true
	self.finderMaxPopulation = 3
	self.finderPending = nil
	self.finderCandidates = {}
	self.finderCandidateIndex = 1
	self.finderAttempts = 0
	self.finderMaxAttempts = 3
	self.finderStatusText = "Pronto para buscar servidores"
	self.connections = {}

	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(390, 780)
	local width = math.clamp(viewport.X - 20, 320, 700)
	local height = math.clamp(viewport.Y - 36, 430, 760)
	self.width, self.height = width, height
	local compact = width < 480
	self.compact = compact
	self.navWidth = compact and 88 or 126

	local root = make("Frame", screen, {
		Name = "PremiumDashboard",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(width, height),
		BackgroundColor3 = C.bg,
		BorderSizePixel = 0,
	})
	corner(root, 16)
	stroke(root, C.line, 0.12)
	self.root = root

	local top = make("Frame", root, {
		Name = "Topbar",
		Size = UDim2.new(1, 0, 0, 58),
		BackgroundColor3 = C.panel,
		BorderSizePixel = 0,
	})
	corner(top, 16)
	make("Frame", top, {
		Position = UDim2.new(0, 0, 1, -14),
		Size = UDim2.new(1, 0, 0, 14),
		BackgroundColor3 = C.panel,
		BorderSizePixel = 0,
	})
	label(top, "ULTRABOOST", UDim2.new(0, 145, 0, 22), C.cyan, true).Position = UDim2.fromOffset(15, 8)
	local version = label(top, "PREMIUM DEV 2.0  •  CLIENT", UDim2.new(0, 200, 0, 16), C.muted, false)
	version.Position = UDim2.fromOffset(15, 31)
	version.TextSize = 8
	self.headerStatus = label(top, "● ONLINE", UDim2.new(0, 70, 0, 18), C.green, true)
	self.headerStatus.Position = UDim2.new(1, -112, 0, 20)
	self.headerStatus.TextSize = 9
	self.minimizeButton = button(top, "—", C.card2, UDim2.fromOffset(28, 28), function()
		self.root.Visible = false
		self.quickButton.Visible = true
	end)
	self.minimizeButton.Position = UDim2.new(1, -38, 0, 15)
	self.minimizeButton.TextSize = 15

	local body = make("Frame", root, {
		Position = UDim2.fromOffset(0, 58),
		Size = UDim2.new(1, 0, 1, -58),
		BackgroundTransparency = 1,
	})
	local nav = make("Frame", body, {
		Name = "Navigation",
		Size = UDim2.new(0, self.navWidth, 1, 0),
		BackgroundColor3 = C.panel,
		BorderSizePixel = 0,
	})
	self.nav = nav
	local navList = make("Frame", nav, {
		Position = UDim2.fromOffset(7, 12),
		Size = UDim2.new(1, -14, 1, -24),
		BackgroundTransparency = 1,
	})
	make("UIListLayout", navList, {
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
	self.navButtons = {}
	local pages = {
		{ "Home", "⌂  Início" },
		{ "Optimizer", "⚡  Visual" },
		{ "Auto", "◉  Automático" },
		{ "Lab", "▥  Lab" },
		{ "Finder", "◎  Servidores" },
		{ "Restore", "↶  Restaurar" },
		{ "Profiles", "▣  Perfis" },
		{ "Settings", "⚙  Ajustes" },
	}
	for index, item in ipairs(pages) do
		local pageName, pageLabel = item[1], item[2]
		local navButton = button(navList, pageLabel, C.card, UDim2.new(1, 0, 0, compact and 36 or 40), function()
			self:ShowPage(pageName)
		end)
		navButton.Name = "Nav_" .. pageName
		navButton.LayoutOrder = index
		navButton.TextSize = compact and 9 or 10
		self.navButtons[pageName] = navButton
	end
	local navFooter = label(nav, "BUILD 2.0-DEV", UDim2.new(1, -12, 0, 22), C.muted, true)
	navFooter.Position = UDim2.new(0, 7, 1, -27)
	navFooter.TextSize = 8
	navFooter.TextXAlignment = Enum.TextXAlignment.Center

	local content = make("Frame", body, {
		Name = "Content",
		Position = UDim2.new(0, self.navWidth, 0, 0),
		Size = UDim2.new(1, -self.navWidth, 1, 0),
		BackgroundTransparency = 1,
	})
	self.content = content
	self.pageTitle = label(content, "Overview", UDim2.new(1, -22, 0, 25), C.text, true)
	self.pageTitle.Position = UDim2.fromOffset(12, 9)
	self.pageTitle.TextSize = 17
	self.pageSubtitle = label(content, "Desempenho e controles da sessão", UDim2.new(1, -22, 0, 20), C.muted, false)
	self.pageSubtitle.Position = UDim2.fromOffset(12, 34)
	self.pageSubtitle.TextSize = 9

	self.pageHost = make("Frame", content, {
		Position = UDim2.fromOffset(10, 60),
		Size = UDim2.new(1, -20, 1, -70),
		BackgroundTransparency = 1,
	})
	self.pages = {}
	for _, item in ipairs(pages) do
		local scroller = make("ScrollingFrame", self.pageHost, {
			Name = "Page_" .. item[1],
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollBarThickness = 3,
			ScrollBarImageColor3 = C.blue,
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			Visible = false,
		})
		addPadding(scroller, 1, 5, 2, 10)
		make("UIListLayout", scroller, {
			Padding = UDim.new(0, 9),
			SortOrder = Enum.SortOrder.LayoutOrder,
		})
		self.pages[item[1]] = scroller
	end

	self:_BuildHome()
	self:_BuildOptimizer()
	self:_BuildAuto()
	self:_BuildLab()
	self:_BuildFinder()
	self:_BuildRestore()
	self:_BuildProfiles()
	self:_BuildSettings()

	self.quickButton = button(screen, "UB", C.blue, UDim2.fromOffset(48, 44), function()
		self.root.Visible = true
		self.quickButton.Visible = false
	end)
	self.quickButton.Name = "PremiumQuickOpen"
	self.quickButton.Position = UDim2.new(0, 12, 0, 100)
	self.quickButton.Visible = false
	self.quickHud = make("Frame", screen, {
		Name = "QuickHUD",
		Position = UDim2.new(1, -126, 0, 12),
		Size = UDim2.fromOffset(114, 36),
		BackgroundColor3 = C.panel,
		BackgroundTransparency = 0.08,
		BorderSizePixel = 0,
		Visible = true,
	})
	corner(self.quickHud, 9)
	stroke(self.quickHud, C.line, 0.35)
	self.hudText = label(self.quickHud, "FPS --  •  ORIGINAL", UDim2.new(1, -12, 1, 0), C.text, true)
	self.hudText.Position = UDim2.fromOffset(7, 0)
	self.hudText.TextSize = 8
	self.hudText.TextXAlignment = Enum.TextXAlignment.Center

	-- Drag the dashboard with mouse or touch from its top bar.
	local userInput = game:GetService("UserInputService")
	local dragging, dragInput, dragStart, rootStart = false, nil, nil, nil
	top.Active = true
	table.insert(self.connections, top.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragInput = input
			dragStart = input.Position
			rootStart = Vector2.new(root.AbsolutePosition.X + width / 2, root.AbsolutePosition.Y + height / 2)
		end
	end))
	table.insert(self.connections, userInput.InputChanged:Connect(function(input)
		if not dragging then return end
		if input.UserInputType ~= Enum.UserInputType.MouseMovement and input ~= dragInput then return end
		local delta = input.Position - dragStart
		local currentCamera = workspace.CurrentCamera
		local bounds = currentCamera and currentCamera.ViewportSize or viewport
		local centerX = math.clamp(rootStart.X + delta.X, width / 2, math.max(width / 2, bounds.X - width / 2))
		local centerY = math.clamp(rootStart.Y + delta.Y, height / 2, math.max(height / 2, bounds.Y - height / 2))
		root.Position = UDim2.fromOffset(centerX, centerY)
	end))
	table.insert(self.connections, userInput.InputEnded:Connect(function(input)
		if input == dragInput or input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = false
			dragInput = nil
		end
	end))

	self:ShowPage("Home")
	self:_StartSampling()
	self:RefreshHome()
	return self
end

function Dashboard:_Page(name)
	return self.pages[name]
end

function Dashboard:_Card(pageName, height)
	local f = card(self:_Page(pageName), height)
	addPadding(f, 12, 12, 10, 10)
	return f
end

function Dashboard:_BuildHome()
	local page = "Home"
	local hero = self:_Card(page, 110)
	label(hero, "UltraBoost Intelligence", UDim2.new(1, 0, 0, 22), C.cyan, true).Position = UDim2.fromOffset(0, 0)
	self.homeInsight = label(hero, "Analisando a estabilidade da sessão...", UDim2.new(1, 0, 0, 44), C.text, false)
	self.homeInsight.Position = UDim2.fromOffset(0, 28)
	self.homeInsight.TextSize = 10
	self.homeMode = label(hero, "Modo: Original", UDim2.new(1, 0, 0, 18), C.muted, true)
	self.homeMode.Position = UDim2.fromOffset(0, 78)

	local stats = self:_Card(page, 102)
	label(stats, "SESSÃO ATUAL", UDim2.new(1, 0, 0, 16), C.muted, true).Position = UDim2.fromOffset(0, 0)
	self.homeFps = label(stats, "-- FPS", UDim2.new(0.5, -4, 0, 35), C.text, true)
	self.homeFps.Position = UDim2.fromOffset(0, 24)
	self.homeFps.TextSize = 22
	self.homeAvg = label(stats, "Média: --", UDim2.new(0.5, -4, 0, 20), C.muted, false)
	self.homeAvg.Position = UDim2.new(0.5, 0, 0, 30)
	self.homeAvg.TextSize = 10
	self.homeTime = label(stats, "Tempo: 00:00", UDim2.new(0.5, -4, 0, 18), C.muted, false)
	self.homeTime.Position = UDim2.new(0.5, 0, 0, 52)
	self.homeTime.TextSize = 10

	local quick = self:_Card(page, 126)
	label(quick, "AÇÕES RÁPIDAS", UDim2.new(1, 0, 0, 16), C.muted, true).Position = UDim2.fromOffset(0, 0)
	local modes = { { "ULTRA", "Ultra", C.blue }, { "EQUILIBRADO", "Balanced", C.card2 }, { "LEVE", "Light", C.green } }
	for index, item in ipairs(modes) do
		local modeLabel, modeName, modeColor = item[1], item[2], item[3]
		local b = button(quick, modeLabel, modeColor, UDim2.new(1, 0, 0, 27), function()
			self:ApplyMode(modeName)
		end)
		b.Position = UDim2.fromOffset(0, 23 + (index - 1) * 31)
		b.TextSize = 9
	end
end

function Dashboard:_BuildOptimizer()
	local page = "Optimizer"
	local modeCard = self:_Card(page, 140)
	label(modeCard, "MODOS VISUAIS", UDim2.new(1, 0, 0, 18), C.cyan, true).Position = UDim2.fromOffset(0, 0)
	local modes = {
		{ "Ultra", "Ambiente mínimo", C.blue },
		{ "Balanced", "Equilíbrio visual", C.card2 },
		{ "Light", "Redução leve", C.green },
	}
	for index, item in ipairs(modes) do
		local modeName, description, tint = item[1], item[2], item[3]
		local y = 24 + (index - 1) * 34
		local b = button(modeCard, modeName .. "  •  " .. description, tint, UDim2.new(1, 0, 0, 29), function()
			self:ApplyMode(modeName)
		end)
		b.Position = UDim2.fromOffset(0, y)
		b.TextXAlignment = Enum.TextXAlignment.Left
		b.TextSize = 9
	end

	local custom = self:_Card(page, 360)
	label(custom, "CUSTOM MODE", UDim2.new(1, 0, 0, 18), C.cyan, true).Position = UDim2.fromOffset(0, 0)
	label(custom, "Monte sua própria combinação. As alterações são locais e reversíveis quando o valor original foi registrado.", UDim2.new(1, 0, 0, 34), C.muted, false).Position = UDim2.fromOffset(0, 22)
	local toggleItems = {
		{ "hideTextures", "Texturas" },
		{ "hideDecals", "Decalques" },
		{ "hideEffects", "Efeitos" },
		{ "hideVegetation", "Vegetação" },
		{ "simplifyMaterials", "Materiais simples" },
		{ "hideShadows", "Sombras" },
		{ "hideEnvironment", "Esconder cenário" },
	}
	self.customButtons = {}
	for index, item in ipairs(toggleItems) do
		local settingKey, settingTitle = item[1], item[2]
		local col = (index - 1) % 2
		local row = math.floor((index - 1) / 2)
		local toggle = button(custom, "", C.green, UDim2.new(0.5, -4, 0, 34), function()
			self.customSettings[settingKey] = not self.customSettings[settingKey]
			self:_UpdateCustomButton(settingKey, settingTitle)
		end)
		toggle.Position = UDim2.new(col * 0.5, col == 1 and 4 or 0, 0, 66 + row * 39)
		toggle.TextSize = 8
		self.customButtons[settingKey] = { button = toggle, title = settingTitle }
		self:_UpdateCustomButton(settingKey, settingTitle)
	end
	self.customApply = button(custom, "APLICAR MEU CUSTOM MODE", C.blue, UDim2.new(1, 0, 0, 32), function()
		self:ApplyCustom()
	end)
	self.customApply.Position = UDim2.fromOffset(0, 224)
	self.collisionButton = button(custom, "COLISÃO AMBIENTAL: OFF", C.card2, UDim2.new(1, 0, 0, 30), function()
		self.collisionEnabled = not self.collisionEnabled
		local ok = self.api.setCollisionEnabled(self.collisionEnabled)
		if not ok then
			self.collisionEnabled = not self.collisionEnabled
		end
		self.collisionButton.Text = "COLISÃO AMBIENTAL: " .. (self.collisionEnabled and "ON" or "OFF")
		self.collisionButton.BackgroundColor3 = self.collisionEnabled and C.orange or C.card2
	end)
	self.collisionButton.Position = UDim2.fromOffset(0, 266)
end

function Dashboard:_UpdateCustomButton(key, title)
	local item = self.customButtons[key]
	if not item then return end
	local enabled = self.customSettings[key]
	item.button.Text = (enabled and "ON  •  " or "OFF •  ") .. title
	item.button.BackgroundColor3 = enabled and C.green or C.card2
end

function Dashboard:_BuildAuto()
	local page = "Auto"
	local info = self:_Card(page, 100)
	label(info, "AUTO OPTIMIZER", UDim2.new(1, 0, 0, 18), C.cyan, true).Position = UDim2.fromOffset(0, 0)
	label(info, "Ajusta o modo em etapas quando a média de FPS cai ou se recupera. Usa histerese para evitar trocas constantes.", UDim2.new(1, 0, 0, 53), C.muted, false).Position = UDim2.fromOffset(0, 25)
	self.autoStatus = label(info, "Status: DESLIGADO", UDim2.new(1, 0, 0, 18), C.orange, true)
	self.autoStatus.Position = UDim2.fromOffset(0, 76)

	local target = self:_Card(page, 152)
	label(target, "META DE FPS", UDim2.new(1, 0, 0, 18), C.muted, true).Position = UDim2.fromOffset(0, 0)
	local choices = { 30, 45, 60 }
	for index, fps in ipairs(choices) do
		local selectedTarget = fps
		local b = button(target, tostring(selectedTarget) .. " FPS", C.card2, UDim2.new(1 / 3, -5, 0, 35), function()
			self.targetFps = selectedTarget
			self:_RefreshTargetButtons()
		end)
		b.Position = UDim2.new((index - 1) / 3, (index - 1) * 3, 0, 28)
		b.Name = "Target_" .. tostring(fps)
		self.targetButtons = self.targetButtons or {}
		self.targetButtons[selectedTarget] = b
	end
	self:_RefreshTargetButtons()
	self.autoProtectionButton = button(target, "PROTEÇÃO DE ESTABILIDADE: ON", C.green, UDim2.new(1, 0, 0, 31), function()
		self.autoProtection = not self.autoProtection
		self.autoProtectionButton.Text = "PROTEÇÃO DE ESTABILIDADE: " .. (self.autoProtection and "ON" or "OFF")
		self.autoProtectionButton.BackgroundColor3 = self.autoProtection and C.green or C.card2
	end)
	self.autoProtectionButton.Position = UDim2.fromOffset(0, 72)
	self.targetCustom = make("TextBox", target, {
		Name = "CustomTargetFPS",
		Position = UDim2.fromOffset(0, 111),
		Size = UDim2.new(1, 0, 0, 27),
		BackgroundColor3 = C.card2,
		BorderSizePixel = 0,
		Text = "",
		PlaceholderText = "Meta personalizada (10–240 FPS)",
		TextColor3 = C.text,
		PlaceholderColor3 = C.muted,
		TextSize = 9,
		Font = Enum.Font.Gotham,
		ClearTextOnFocus = false,
	})
	corner(self.targetCustom, 7)
	self.targetCustom.FocusLost:Connect(function()
		local value = tonumber(self.targetCustom.Text)
		if value then
			self.targetFps = math.clamp(math.floor(value), 10, 240)
			self:_RefreshTargetButtons()
			self.autoStatus.Text = "Meta personalizada: " .. tostring(self.targetFps) .. " FPS"
		else
			self.targetCustom.Text = ""
		end
	end)

	local toggle = self:_Card(page, 72)
	self.autoToggle = button(toggle, "ATIVAR AUTO OPTIMIZER", C.blue, UDim2.new(1, 0, 0, 42), function()
		self.autoEnabled = not self.autoEnabled
		self.autoLowCount, self.autoHighCount = 0, 0
		if self.autoEnabled then
			self.autoModeIndex = self.mode == "Ultra" and 3 or (self.mode == "Balanced" and 2 or 1)
		end
		self.autoToggle.Text = self.autoEnabled and "DESATIVAR AUTO OPTIMIZER" or "ATIVAR AUTO OPTIMIZER"
		self.autoToggle.BackgroundColor3 = self.autoEnabled and C.red or C.blue
		self.autoStatus.Text = "Status: " .. (self.autoEnabled and "ATIVO" or "DESLIGADO")
		self.autoStatus.TextColor3 = self.autoEnabled and C.green or C.orange
	end)
end

function Dashboard:_RefreshTargetButtons()
	for fps, b in pairs(self.targetButtons or {}) do
		b.BackgroundColor3 = fps == self.targetFps and C.blue or C.card2
	end
end

function Dashboard:_BuildLab()
	local page = "Lab"
	local metrics = self:_Card(page, 132)
	label(metrics, "PERFORMANCE LAB", UDim2.new(1, 0, 0, 18), C.cyan, true).Position = UDim2.fromOffset(0, 0)
	self.labCurrent = label(metrics, "FPS atual: --", UDim2.new(1, 0, 0, 25), C.text, true)
	self.labCurrent.Position = UDim2.fromOffset(0, 24)
	self.labCurrent.TextSize = 18
	self.labAverage = label(metrics, "Média: --  •  Mínimo: --  •  Máximo: --", UDim2.new(1, 0, 0, 20), C.muted, false)
	self.labAverage.Position = UDim2.fromOffset(0, 53)
	self.labFrame = label(metrics, "Frame time estimado: -- ms", UDim2.new(1, 0, 0, 18), C.muted, false)
	self.labFrame.Position = UDim2.fromOffset(0, 77)
	self.labDuration = label(metrics, "Duração: 00:00", UDim2.new(1, 0, 0, 18), C.muted, false)
	self.labDuration.Position = UDim2.fromOffset(0, 99)

	local graph = self:_Card(page, 84)
	label(graph, "ESTABILIDADE RECENTE", UDim2.new(1, 0, 0, 16), C.muted, true).Position = UDim2.fromOffset(0, 0)
	self.graphLabel = label(graph, "Aguardando amostras...", UDim2.new(1, 0, 0, 35), C.cyan, true)
	self.graphLabel.Position = UDim2.fromOffset(0, 26)
	self.graphLabel.TextSize = 12

	local bench = self:_Card(page, 132)
	label(bench, "BENCHMARK COMPARATIVO", UDim2.new(1, 0, 0, 18), C.cyan, true).Position = UDim2.fromOffset(0, 0)
	self.benchmarkInfo = label(bench, "Marque uma linha de base e depois registre o resultado com a otimização aplicada.", UDim2.new(1, 0, 0, 35), C.muted, false)
	self.benchmarkInfo.Position = UDim2.fromOffset(0, 22)
	self.baselineButton = button(bench, "MARCAR BASELINE", C.card2, UDim2.new(0.5, -4, 0, 34), function()
		self.baseline = self:_Average(10)
		self:_RefreshBenchmark()
	end)
	self.baselineButton.Position = UDim2.fromOffset(0, 72)
	self.optimizedButton = button(bench, "MARCAR OTIMIZADO", C.blue, UDim2.new(0.5, -4, 0, 34), function()
		self.optimizedMark = self:_Average(10)
		self:_RefreshBenchmark()
	end)
	self.optimizedButton.Position = UDim2.new(0.5, 4, 0, 72)
end

function Dashboard:_Average(limit)
	local total, count = 0, 0
	for i = math.max(1, #self.samples - (limit or 10) + 1), #self.samples do
		total += self.samples[i]
		count += 1
	end
	if count == 0 then return nil end
	return math.floor(total / count + 0.5)
end

function Dashboard:_RefreshBenchmark()
	local base = self.baseline and (tostring(self.baseline) .. " FPS") or "--"
	local optimized = self.optimizedMark and (tostring(self.optimizedMark) .. " FPS") or "--"
	local delta = ""
	if self.baseline and self.optimizedMark and self.baseline > 0 then
		local percent = (self.optimizedMark - self.baseline) / self.baseline * 100
		delta = string.format("  •  %+.1f%%", percent)
	end
	self.benchmarkInfo.Text = "Baseline: " .. base .. "  |  Otimizado: " .. optimized .. delta
end

function Dashboard:_BuildFinder()
	local page = "Finder"
	local controls = self:_Card(page, 204)
	label(controls, "SERVER FINDER", UDim2.new(1, 0, 0, 18), C.cyan, true).Position = UDim2.fromOffset(0, 0)
	label(controls, "Filtros locais sobre a lista pública. População e ping podem mudar antes da entrada.", UDim2.new(1, 0, 0, 30), C.muted, false).Position = UDim2.fromOffset(0, 22)
	local modes = { "Empty Server", "Low Population", "Oldest Empty", "Low Ping", "Balanced" }
	self.finderModeButtons = {}
	for index, modeName in ipairs(modes) do
		local selectedMode = modeName
		local col = (index - 1) % 2
		local row = math.floor((index - 1) / 2)
		local b = button(controls, selectedMode, C.card2, UDim2.new(0.5, -4, 0, 27), function()
			self.finderMode = selectedMode
			self:_RenderFinder()
			self:_RefreshFinderModeButtons()
		end)
		b.Position = UDim2.new(col * 0.5, col == 1 and 4 or 0, 0, 56 + row * 31)
		b.TextSize = 8
		self.finderModeButtons[selectedMode] = b
	end
	self:_RefreshFinderModeButtons()
	self.finderPopulation = make("TextBox", controls, {
		Name = "MaxPopulation",
		Position = UDim2.fromOffset(0, 151),
		Size = UDim2.fromOffset(64, 25),
		BackgroundColor3 = C.card2,
		BorderSizePixel = 0,
		Text = tostring(self.finderMaxPopulation),
		PlaceholderText = "Max pop",
		TextColor3 = C.text,
		PlaceholderColor3 = C.muted,
		TextSize = 9,
		Font = Enum.Font.Gotham,
		ClearTextOnFocus = false,
	})
	corner(self.finderPopulation, 7)
	self.finderPopulation.FocusLost:Connect(function()
		local value = tonumber(self.finderPopulation.Text)
		if value then
			self.finderMaxPopulation = math.clamp(math.floor(value), 0, 100)
		else
			self.finderPopulation.Text = tostring(self.finderMaxPopulation)
		end
		self:_RenderFinder()
	end)
	local options = self:_Card(page, 72)
	self.recentButton = button(options, "IGNORAR VISITADOS: ON", C.green, UDim2.new(0.5, -4, 0, 30), function()
		self.finderIgnoreRecent = not self.finderIgnoreRecent
		self.recentButton.Text = "IGNORAR VISITADOS: " .. (self.finderIgnoreRecent and "ON" or "OFF")
		self.recentButton.BackgroundColor3 = self.finderIgnoreRecent and C.green or C.card2
		self:_RenderFinder()
	end)
	self.recentButton.Position = UDim2.fromOffset(0, 10)
	self.finderRefreshButton = button(options, "ATUALIZAR", C.blue, UDim2.new(0.5, -4, 0, 30), function()
		self:RefreshFinder()
	end)
	self.finderRefreshButton.Position = UDim2.new(0.5, 4, 0, 10)
	self.finderAutoButton = button(options, "AUTO: OFF", C.card2, UDim2.new(1, 0, 0, 24), function()
		self.finderAuto = not self.finderAuto
		if self.finderAuto then
			self.api.serverService:StartAutoRefresh(game.PlaceId, function(servers, metadata)
				if self.destroyed then return end
				if servers then
					self.finderServers = servers
					self.finderStatusText = "Atualizado automaticamente"
					self:_RenderFinder()
				else
					self.finderStatusText = "Falha no auto-refresh; mantendo resultados anteriores"
					self:_RefreshFinderStats()
				end
			end, 30)
		else
			self.api.serverService:StopAutoRefresh()
		end
		self.finderAutoButton.Text = self.finderAuto and "AUTO: ON • 30s" or "AUTO: OFF"
		self.finderAutoButton.BackgroundColor3 = self.finderAuto and C.green or C.card2
	end)
	self.finderAutoButton.Position = UDim2.fromOffset(0, 44)

	local status = self:_Card(page, 78)
	self.finderStatus = label(status, self.finderStatusText, UDim2.new(1, 0, 0, 34), C.muted, false)
	self.finderStatus.Position = UDim2.fromOffset(0, 0)
	self.finderStatus.TextSize = 9
	self.finderStats = label(status, "Encontrados 0 • filtrados 0 • visitados 0", UDim2.new(1, 0, 0, 34), C.muted, true)
	self.finderStats.Position = UDim2.fromOffset(0, 35)
	self.finderStats.TextSize = 7

	self.finderListCard = self:_Card(page, 260)
	label(self.finderListCard, "RESULTADOS", UDim2.new(1, 0, 0, 17), C.muted, true).Position = UDim2.fromOffset(0, 0)
	self.finderList = make("ScrollingFrame", self.finderListCard, {
		Position = UDim2.fromOffset(0, 25),
		Size = UDim2.new(1, 0, 1, -25),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
	})
	make("UIListLayout", self.finderList, {
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
	local history = self:_Card(page, 100)
	label(history, "HISTÓRICO RECENTE", UDim2.new(1, 0, 0, 17), C.muted, true).Position = UDim2.fromOffset(0, 0)
	self.finderHistory = label(history, "Nenhuma tentativa nesta sessão.", UDim2.new(1, 0, 0, 58), C.muted, false)
	self.finderHistory.Position = UDim2.fromOffset(0, 23)
	self.finderHistory.TextSize = 8
end

function Dashboard:_RefreshFinderModeButtons()
	for modeName, b in pairs(self.finderModeButtons or {}) do
		b.BackgroundColor3 = modeName == self.finderMode and C.blue or C.card2
	end
end

function Dashboard:_RefreshFinderStats()
	local stats = self.api.serverService:GetStats()
	self.finderStats.Text = string.format(
		"Únicos %d • filtrados %d • visitados %d\nTentativas %d • início %d • sucesso %d • falhas %d • erros %d",
		stats.serversFound or 0, stats.discardedByFilters or 0, stats.visitedServers or 0,
		stats.attempts or 0, stats.teleportStarted or 0, stats.successes or 0,
		stats.failures or 0, stats.requestErrors or 0
	)
	local history = self.api.serverService:GetHistory(3)
	if #history > 0 then
		local rows = {}
		for index, record in ipairs(history) do
			table.insert(rows, string.sub(record.id, 1, 12) .. " • " .. tostring(record.state))
		end
		self.finderHistory.Text = table.concat(rows, "\n")
	else
		self.finderHistory.Text = "Nenhuma tentativa nesta sessão."
	end
end

function Dashboard:_ClearFinderList()
	for _, child in ipairs(self.finderList:GetChildren()) do
		if not child:IsA("UIListLayout") then child:Destroy() end
	end
end

function Dashboard:_RenderFinder()
	if not self.finderList then return end
	self.finderFiltered = self.api.serverService:FilterServers(self.finderServers, self.finderMode, {
		maxPopulation = self.finderMaxPopulation,
		ignoreRecentlyVisited = self.finderIgnoreRecent,
	})
	self:_ClearFinderList()
	if #self.finderFiltered == 0 then
		local empty = label(self.finderList, "Nenhum servidor corresponde aos filtros atuais.", UDim2.new(1, -8, 0, 42), C.muted, false)
		empty.LayoutOrder = 1
		empty.TextSize = 10
	end
	for index, server in ipairs(self.finderFiltered) do
		local candidate, candidateIndex = server, index
		local item = make("Frame", self.finderList, {
			Size = UDim2.new(1, -5, 0, 56),
			BackgroundColor3 = C.card2,
			BorderSizePixel = 0,
			LayoutOrder = index,
		})
		corner(item, 8)
		local pop = server.playing ~= nil and (tostring(server.playing) .. "/" .. tostring(server.maxPlayers or "?") .. " jogadores") or "População indisponível"
		local ping = server.ping ~= nil and (tostring(math.floor(server.ping + 0.5)) .. " ms") or "ping n/d"
		local fps = server.fps ~= nil and (tostring(math.floor(server.fps + 0.5)) .. " FPS") or "FPS n/d"
		local first = label(item, pop .. "  •  " .. ping .. "  •  " .. fps, UDim2.new(1, -82, 0, 19), C.text, true)
		first.Position = UDim2.fromOffset(7, 5)
		first.TextSize = 8
		local observation = server.emptyObservedSince and ("Vazio observado há " .. timeText(os.time() - server.emptyObservedSince)) or "Observações: " .. tostring(server.observations or 1)
		local second = label(item, observation, UDim2.new(1, -82, 0, 17), C.muted, false)
		second.Position = UDim2.fromOffset(7, 29)
		second.TextSize = 8
		local join = button(item, candidate.isCurrent and "ATUAL" or "ENTRAR", candidate.isCurrent and C.card or C.blue, UDim2.fromOffset(67, 34), function()
			if not candidate.isCurrent then
				self.finderCandidates = self.finderFiltered
				self.finderCandidateIndex = candidateIndex
				self.finderAttempts = 0
				self.finderPending = nil
				self:_AttemptNextServer()
			end
		end)
		join.Position = UDim2.new(1, -73, 0, 11)
		join.TextSize = 8
		join.Active = not candidate.isCurrent
	end
	self.finderStatus.Text = tostring(#self.finderFiltered) .. " servidores • " .. self.finderMode .. " • " .. self.finderStatusText
	self:_RefreshFinderStats()
end

function Dashboard:RefreshFinder()
	if self.destroyed then return end
	self.finderStatusText = "Consultando lista pública..."
	self.finderStatus.Text = self.finderStatusText
	self.finderRefreshButton.Text = "BUSCANDO..."
	self.finderRefreshButton.Active = false
	task.spawn(function()
		local servers, metadata = self.api.serverService:FetchServers(game.PlaceId)
		if self.destroyed then return end
		self.finderRefreshButton.Text = "ATUALIZAR"
		self.finderRefreshButton.Active = true
		if not servers then
			self.finderStatusText = "Erro: " .. tostring(metadata and metadata.error or "resposta indisponível")
			self.finderStatus.Text = self.finderStatusText
			self:_RefreshFinderStats()
			return
		end
		self.finderServers = servers
		self.finderStatusText = string.format("%d página(s) • dados atualizados", metadata.pages or 0)
		self:_RenderFinder()
	end)
end

function Dashboard:_AttemptNextServer()
	if self.destroyed then return end
	while self.finderCandidateIndex <= #self.finderCandidates and self.finderAttempts < self.finderMaxAttempts do
		local candidate = self.finderCandidates[self.finderCandidateIndex]
		self.finderCandidateIndex += 1
		if candidate and candidate.id ~= game.JobId then
			self.finderAttempts += 1
			self.finderPending = candidate
			self.api.serverService:RecordAttempt(candidate, "requested")
			self.finderStatusText = "Solicitando entrada " .. tostring(self.finderAttempts) .. "/" .. tostring(self.finderMaxAttempts)
			self.finderStatus.Text = self.finderStatusText
			local ok, detail = self.api.entryAdapter:Join(game.PlaceId, candidate.id)
			if ok then
				self:_RefreshFinderStats()
				return
			end
			self.api.serverService:RecordAttempt(candidate, "failed", detail)
			self.finderPending = nil
		end
	end
	self.finderStatusText = "Sem outros candidatos disponíveis. Confira o suporte de teleporte do executor."
	self.finderStatus.Text = self.finderStatusText
	self:_RefreshFinderStats()
end

function Dashboard:_BuildRestore()
	local page = "Restore"
	local info = self:_Card(page, 75)
	label(info, "SMART RESTORE", UDim2.new(1, 0, 0, 18), C.cyan, true).Position = UDim2.fromOffset(0, 0)
	label(info, "Restaure grupos de propriedades registrados pelo UltraBoost. Objetos que não puderam ser lidos ou alterados podem não ser recuperáveis.", UDim2.new(1, 0, 0, 40), C.muted, false).Position = UDim2.fromOffset(0, 24)
	local actions = self:_Card(page, 208)
	local restoreItems = {
		{ "RESTORE TEXTURAS", "restoreTextures", C.card2 },
		{ "RESTORE MATERIAIS", "restoreMaterials", C.card2 },
		{ "RESTORE ILUMINAÇÃO", "restoreLighting", C.card2 },
	}
	for index, item in ipairs(restoreItems) do
		local actionLabel, actionName, actionColor = item[1], item[2], item[3]
		local b = button(actions, actionLabel, actionColor, UDim2.new(1, 0, 0, 34), function()
			self.api[actionName]()
		end)
		b.Position = UDim2.fromOffset(0, 22 + (index - 1) * 40)
		b.TextSize = 9
	end
	local undo = button(actions, "DESFAZER ÚLTIMO MODO", C.orange, UDim2.new(1, 0, 0, 34), function()
		self.api.restoreAll()
		self.collisionEnabled = false
		if self.collisionButton then
			self.collisionButton.Text = "COLISÃO AMBIENTAL: OFF"
			self.collisionButton.BackgroundColor3 = C.card2
		end
		if self.lastMode == "Custom" then
			self.api.applyCustom(self.customSettings)
			self.mode = "Custom"
		elseif self.lastMode and self.lastMode ~= "Original" then
			self.api.applyMode(self.lastMode)
			self.mode = self.lastMode
		else
			self.mode = "Original"
		end
		self:RefreshHome()
	end)
	undo.Position = UDim2.fromOffset(0, 148)
	undo.TextSize = 9
	local emergency = self:_Card(page, 76)
	self.restoreAllButton = button(emergency, "RESTORE ALL  •  EMERGÊNCIA", C.red, UDim2.new(1, 0, 0, 44), function()
		self.api.restoreAll()
		self.mode = "Original"
		self.lastMode = nil
		self.collisionEnabled = false
		if self.collisionButton then
			self.collisionButton.Text = "COLISÃO AMBIENTAL: OFF"
			self.collisionButton.BackgroundColor3 = C.card2
		end
		self:RefreshHome()
	end)
end

function Dashboard:_BuildProfiles()
	local page = "Profiles"
	local info = self:_Card(page, 88)
	label(info, "GAME PROFILES", UDim2.new(1, 0, 0, 18), C.cyan, true).Position = UDim2.fromOffset(0, 0)
	label(info, "Salva o modo e o Custom Mode para o PlaceId atual durante esta sessão do script. Não é armazenamento permanente.", UDim2.new(1, 0, 0, 48), C.muted, false).Position = UDim2.fromOffset(0, 25)
	local profile = self:_Card(page, 100)
	self.profileStatus = label(profile, "Nenhum perfil salvo para esta experiência.", UDim2.new(1, 0, 0, 34), C.muted, false)
	self.profileStatus.Position = UDim2.fromOffset(0, 0)
	button(profile, "SALVAR PERFIL DESTE JOGO", C.blue, UDim2.new(1, 0, 0, 34), function()
		self.profileStore[game.PlaceId] = {
			mode = self.mode,
			custom = table.clone(self.customSettings),
		}
		self.profileStatus.Text = "Perfil salvo nesta sessão • PlaceId " .. tostring(game.PlaceId)
	end).Position = UDim2.fromOffset(0, 47)
	local load = self:_Card(page, 70)
	button(load, "CARREGAR PERFIL SALVO", C.green, UDim2.new(1, 0, 0, 42), function()
		local profileData = self.profileStore[game.PlaceId]
		if not profileData then
			self.profileStatus.Text = "Ainda não existe perfil salvo para este jogo."
			return
		end
		self.customSettings = table.clone(profileData.custom or self.customSettings)
		for key, item in pairs(self.customButtons or {}) do
			self:_UpdateCustomButton(key, item.title)
		end
		if profileData.mode == "Custom" then
			self:ApplyCustom()
		elseif profileData.mode and profileData.mode ~= "Original" then
			self:ApplyMode(profileData.mode)
		else
			self.api.restoreAll()
		end
		self.mode = profileData.mode or "Original"
		self:RefreshHome()
		self.profileStatus.Text = "Perfil carregado para PlaceId " .. tostring(game.PlaceId)
	end)
end

function Dashboard:_BuildSettings()
	local page = "Settings"
	local quick = self:_Card(page, 110)
	label(quick, "QUICK PANEL", UDim2.new(1, 0, 0, 18), C.cyan, true).Position = UDim2.fromOffset(0, 0)
	self.hudToggle = button(quick, "HUD FLUTUANTE: ON", C.green, UDim2.new(1, 0, 0, 36), function()
		self.quickHudEnabled = not self.quickHudEnabled
		self.quickHud.Visible = self.quickHudEnabled
		self.hudToggle.Text = "HUD FLUTUANTE: " .. (self.quickHudEnabled and "ON" or "OFF")
		self.hudToggle.BackgroundColor3 = self.quickHudEnabled and C.green or C.card2
	end)
	self.hudToggle.Position = UDim2.fromOffset(0, 27)
	local update = self:_Card(page, 92)
	label(update, "UPDATE CENTER", UDim2.new(1, 0, 0, 18), C.cyan, true).Position = UDim2.fromOffset(0, 0)
	label(update, "Build local: Premium DEV 2.0 • alpha.2. Atualizações ainda são distribuídas pelo arquivo de teste.", UDim2.new(1, 0, 0, 50), C.muted, false).Position = UDim2.fromOffset(0, 25)
	local license = self:_Card(page, 116)
	label(license, "KEY SYSTEM", UDim2.new(1, 0, 0, 18), C.cyan, true).Position = UDim2.fromOffset(0, 0)
	label(license, "Modo DEV • autenticação e licenças ainda não estão conectadas a um backend. Nenhuma chave é solicitada nesta compilação.", UDim2.new(1, 0, 0, 56), C.muted, false).Position = UDim2.fromOffset(0, 26)
	local about = self:_Card(page, 80)
	label(about, "DIAGNÓSTICO", UDim2.new(1, 0, 0, 18), C.cyan, true).Position = UDim2.fromOffset(0, 0)
	self.diagnostic = label(about, "Cliente local • sem acesso a métricas internas do servidor.", UDim2.new(1, 0, 0, 38), C.muted, false)
	self.diagnostic.Position = UDim2.fromOffset(0, 25)
	local exit = self:_Card(page, 66)
	button(exit, "FECHAR E RESTAURAR TUDO", C.red, UDim2.new(1, 0, 0, 42), function()
		if self.api.close then self.api.close() end
	end)
end

function Dashboard:ApplyMode(modeName)
	self.lastMode = self.mode
	local ok = self.api.applyMode(modeName)
	if ok ~= false then
		self.mode = modeName
		self:RefreshHome()
	end
	return ok
end

function Dashboard:ApplyCustom()
	self.lastMode = self.mode
	local ok = self.api.applyCustom(self.customSettings)
	if ok ~= false then
		self.mode = "Custom"
		self:RefreshHome()
	end
	return ok
end

function Dashboard:ShowPage(name)
	if not self.pages[name] then return end
	self.activePage = name
	for pageName, page in pairs(self.pages) do
		page.Visible = pageName == name
	end
	for pageName, b in pairs(self.navButtons) do
		b.BackgroundColor3 = pageName == name and C.blue or C.card
	end
	local titles = {
		Home = { "Visão geral", "Desempenho e recomendações da sessão" },
		Optimizer = { "Otimizador visual", "Presets e configurações personalizadas" },
		Auto = { "Auto Optimizer", "Ajuste automático com proteção de estabilidade" },
		Lab = { "Performance Lab", "Amostras de FPS e comparação de benchmark" },
		Finder = { "Server Finder", "Filtros, observações e histórico de entrada" },
		Restore = { "Smart Restore", "Recuperação seletiva e restauração de emergência" },
		Profiles = { "Game Profiles", "Configurações por experiência nesta sessão" },
		Settings = { "Configurações", "Quick HUD, atualizações e licença" },
	}
	self.pageTitle.Text = titles[name][1]
	self.pageSubtitle.Text = titles[name][2]
	if name == "Finder" and #self.finderServers == 0 then
		self:RefreshFinder()
	end
end

function Dashboard:RefreshHome()
	if self.homeMode then
		self.homeMode.Text = "Modo ativo: " .. tostring(self.mode)
	end
end

function Dashboard:_UpdateSamples(fps)
	table.insert(self.samples, fps)
	while #self.samples > 120 do table.remove(self.samples, 1) end
	self.sessionTotal += fps
	self.sessionSampleCount += 1
	self.sessionMin = math.min(self.sessionMin, fps)
	self.sessionMax = math.max(self.sessionMax, fps)
	local avg = math.floor(self.sessionTotal / math.max(self.sessionSampleCount, 1) + 0.5)
	local minimum = self.sessionMin
	local maximum = self.sessionMax
	local duration = timeText(os.clock() - self.sessionStarted)
	if self.homeFps then
		self.homeFps.Text = tostring(fps) .. " FPS"
		self.homeAvg.Text = "Média: " .. tostring(avg)
		self.homeTime.Text = "Tempo: " .. duration
	end
	if self.labCurrent then self.labCurrent.Text = "FPS atual: " .. tostring(fps) end
	if self.labAverage then
		self.labAverage.Text = string.format("Média: %d  •  Mínimo: %d  •  Máximo: %d", avg, minimum, maximum)
	end
	if self.labFrame then
		self.labFrame.Text = string.format("Frame time estimado: %.1f ms", 1000 / math.max(fps, 1))
	end
	if self.labDuration then self.labDuration.Text = "Duração: " .. duration end
	if self.graphLabel then
		local chars = { "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█" }
		local graph = ""
		local startIndex = math.max(1, #self.samples - 19)
		local maxValue = math.max(maximum, 1)
		for i = startIndex, #self.samples do
			local level = math.clamp(math.floor((self.samples[i] / maxValue) * 7) + 1, 1, 8)
			graph ..= chars[level]
		end
		self.graphLabel.Text = graph
	end
	if self.homeInsight then
		if avg < self.targetFps - 8 then
			self.homeInsight.Text = "Oscilações detectadas. Considere reduzir a qualidade visual ou ativar o Auto Optimizer."
			self.homeInsight.TextColor3 = C.orange
		elseif minimum < avg - 12 then
			self.homeInsight.Text = "A sessão teve quedas pontuais. Observe o gráfico antes de mudar o modo."
			self.homeInsight.TextColor3 = C.text
		else
			self.homeInsight.Text = "A sessão está relativamente estável. Não há necessidade de reduzir mais elementos agora."
			self.homeInsight.TextColor3 = C.green
		end
	end
	if self.hudText then
		self.hudText.Text = tostring(fps) .. " FPS  •  " .. tostring(self.mode):upper()
	end
	self:RefreshHome()
end

function Dashboard:_AutoStep(fps, average)
	if not self.autoEnabled or self.destroyed then return end
	local target = self.targetFps
	if average < target - 8 then
		self.autoLowCount += 1
		self.autoHighCount = 0
	elseif average > target + (self.autoProtection and 10 or 5) then
		self.autoHighCount += 1
		self.autoLowCount = 0
	else
		self.autoLowCount = math.max(0, self.autoLowCount - 1)
		self.autoHighCount = math.max(0, self.autoHighCount - 1)
	end

	if self.autoLowCount >= (self.autoProtection and 3 or 2) and self.autoModeIndex < #self.autoModes then
		self.autoModeIndex += 1
		local nextMode = self.autoModes[self.autoModeIndex]
		self:ApplyMode(nextMode)
		self.autoLowCount, self.autoHighCount = 0, 0
		self.autoStatus.Text = "Status: ATIVO • aplicou " .. nextMode
	elseif self.autoHighCount >= (self.autoProtection and 8 or 5) and self.autoModeIndex > 1 then
		self.autoModeIndex -= 1
		local nextMode = self.autoModes[self.autoModeIndex]
		self:ApplyMode(nextMode)
		self.autoLowCount, self.autoHighCount = 0, 0
		self.autoStatus.Text = "Status: ATIVO • recuperou " .. nextMode
	end
end

function Dashboard:_StartSampling()
	local runService = game:GetService("RunService")
	table.insert(self.connections, runService.Heartbeat:Connect(function(dt)
		if self.destroyed then return end
		self.sampleFrames += 1
		self.sampleElapsed += dt
		if self.sampleElapsed >= 1 then
			local fps = math.floor(self.sampleFrames / math.max(self.sampleElapsed, 0.001) + 0.5)
			self.sampleFrames, self.sampleElapsed = 0, 0
			self.currentFps = fps
			self:_UpdateSamples(fps)
			self:_AutoStep(fps, self:_Average(5) or fps)
		end
	end))

	self.api.entryAdapter:SetResultHandler(function(stateName, payload)
		if self.destroyed or not self.finderPending or payload.jobId ~= self.finderPending.id then return end
		if stateName == "started" then
			self.api.serverService:RecordAttempt(self.finderPending, "started", payload.state)
			self.finderStatusText = "Teleporte iniciado • aguardando conclusão"
			self:_RefreshFinderStats()
		elseif stateName == "completed" then
			self.api.serverService:RecordAttempt(self.finderPending, "completed", payload.state)
			self.finderStatusText = "Entrada confirmada pelo runtime"
			self.finderPending = nil
			self:_RefreshFinderStats()
		elseif stateName == "failed" then
			self.api.serverService:RecordAttempt(self.finderPending, "failed", payload.message or payload.result or payload.state)
			self.finderStatusText = "Falha de entrada • tentando próximo candidato"
			self.finderPending = nil
			self:_RefreshFinderStats()
			task.defer(function() self:_AttemptNextServer() end)
		end
	end)
end

function Dashboard:Destroy()
	self.destroyed = true
	if self.api.serverService then self.api.serverService:StopAutoRefresh() end
	if self.api.entryAdapter then self.api.entryAdapter:SetResultHandler(nil) end
	for _, connection in ipairs(self.connections) do
		pcall(function() connection:Disconnect() end)
	end
	table.clear(self.connections)
end

return Dashboard

end)()

local serverFinderService = ServerFinderServiceModule.new()
local serverFinderEntry = EntryAdapterModule.new()
local dashboard = nil
local closeUltraBoost
dashboard = PremiumDashboardModule.new(screen, {
	applyMode = applyMode,
	applyCustom = applyCustom,
	setCollisionEnabled = setCollisionEnabled,
	restoreAll = restoreAll,
	restoreTextures = restoreTextures,
	restoreMaterials = restoreMaterials,
	restoreLighting = restoreLighting,
	getMode = function() return activeMode or "Original" end,
	serverService = serverFinderService,
	entryAdapter = serverFinderEntry,
	close = function() if closeUltraBoost then closeUltraBoost() end end,
})

closeUltraBoost = function()
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
	if dashboard then dashboard:Destroy() end
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

print("[UltraBoost Premium DEV] v2.0.0-alpha.2 loaded. Dashboard ready.")
