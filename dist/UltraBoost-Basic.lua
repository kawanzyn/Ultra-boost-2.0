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
