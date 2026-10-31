--!strict
-- Reversible client-side visual optimization. Does not delete instances or
-- change server-authoritative state. Collision changes are local and optional.

local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")
local Terrain = Workspace:FindFirstChildOfClass("Terrain")

local Optimizer = {}

-- Strong keys preserve instances until their captured values are restored.
local visualSaved: {[Instance]: {[string]: any}} = {}
local collisionSaved: {[Instance]: {[string]: any}} = {}
local terrainColorsSaved: {[Enum.Material]: Color3} = {}
local connections: {RBXScriptConnection} = {}
local scanGeneration: {[Instance]: number} = {}
local scanSerialCounter = 0
local operationBusy = false
local activeMode: string? = nil
local collisionEnabled = false
local started = false

local WHITE = Color3.new(1, 1, 1)
local SMOOTH = Enum.Material.SmoothPlastic

local protectedNames = {
	"player", "character", "npc", "enemy", "boss", "humanoid", "tool",
	"weapon", "item", "pickup", "collect", "coin", "egg", "objective",
	"quest", "checkpoint", "spawn", "portal", "button", "switch", "lever",
	"door", "vehicle", "pet", "shop",
}

local groundNames = {
	"ground", "floor", "baseplate", "terrain", "road", "path",
	"sidewalk", "pavement", "walkway",
}

local function containsAny(value: string, fragments: {string}): boolean
	local lowered = string.lower(value)
	for _, fragment in ipairs(fragments) do
		if string.find(lowered, fragment, 1, true) then
			return true
		end
	end
	return false
end

local function rememberAndSet(
	store: {[Instance]: {[string]: any}},
	instance: Instance,
	property: string,
	value: any
)
	local values = store[instance]
	if not values then
		values = {}
		store[instance] = values
	end

	if values[property] == nil then
		local ok, original = pcall(function()
			return (instance :: any)[property]
		end)
		if not ok then
			return
		end
		values[property] = { value = original }
	end

	pcall(function()
		(instance :: any)[property] = value
	end)
end

local function restoreStore(store: {[Instance]: {[string]: any}})
	local entries = {}
	for instance, values in pairs(store) do
		table.insert(entries, { instance = instance, values = values })
	end
	table.clear(store)

	local processed = 0
	for _, entry in ipairs(entries) do
		for property, saved in pairs(entry.values) do
			pcall(function()
				(entry.instance :: any)[property] = saved.value
			end)
		end
		processed += 1
		if processed % 80 == 0 then
			task.wait()
		end
	end
end

local function restoreTerrainColors()
	if Terrain then
		for material, originalColor in pairs(terrainColorsSaved) do
			pcall(function()
				Terrain:SetMaterialColor(material, originalColor)
			end)
		end
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
		local colorOk, originalColor = pcall(function()
			return Terrain:GetMaterialColor(material)
		end)
		if colorOk and terrainColorsSaved[material] == nil then
			terrainColorsSaved[material] = originalColor
		end
		pcall(function()
			Terrain:SetMaterialColor(material, WHITE)
		end)
	end
end

local function isProtectedSelf(instance: Instance): boolean
	local className = instance.ClassName
	if className == "Model" and instance:FindFirstChildOfClass("Humanoid") then
		return true
	end
	if className == "Tool" or className == "Accessory" then
		return true
	end
	if className == "Model" or className == "Folder"
		or className == "Tool" or className == "Accessory"
		or instance:IsA("BasePart") then
		return containsAny(instance.Name, protectedNames)
	end
	return false
end

local function isProtected(instance: Instance): boolean
	local current: Instance? = instance
	while current and current ~= Workspace and current ~= Lighting do
		if isProtectedSelf(current) then
			return true
		end
		current = current.Parent
	end
	return false
end

local function isGround(part: BasePart): boolean
	local current: Instance? = part
	while current and current ~= Workspace do
		if containsAny(current.Name, groundNames) then
			return true
		end
		current = current.Parent
	end

	local size = part.Size
	return part.Anchored
		and size.X * size.Z >= 400
		and size.Y <= math.max(4, math.min(size.X, size.Z) * 0.08)
		and part.CFrame.UpVector.Y >= 0.85
end

local function isEnvironment(part: BasePart, alreadyKnownUnprotected: boolean?): boolean
	return part:IsDescendantOf(Workspace)
		and part.Anchored
		and (alreadyKnownUnprotected == true or not isProtected(part))
		and not isGround(part)
end

local function shouldSimplifyTexture(instance: Instance): boolean
	if isProtected(instance) then
		return false
	end
	local parentPart = instance:FindFirstAncestorWhichIsA("BasePart")
	if parentPart then
		return isGround(parentPart) or isEnvironment(parentPart)
	end
	return instance:IsDescendantOf(Lighting)
end

local function isEffectObject(instance: Instance): boolean
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

local function applyInstance(instance: Instance, knownProtected: boolean?)
	local className = instance.ClassName
	local isPart = instance:IsA("BasePart")
	local isTextureObject = className == "Decal"
		or className == "Texture"
		or className == "SurfaceAppearance"
		or className == "SpecialMesh"
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
		protected = isProtected(instance)
	end

	local ground = false
	local environment = false
	local textureEligible = false

	-- MeshPart geometry simplification can help GPU-bound mobile devices.
	-- It is local, opt-in through Ultra mode, and retained for Restore().
	if mode == "Ultra" and not protected and className == "MeshPart" then
		rememberAndSet(visualSaved, instance, "RenderFidelity", Enum.RenderFidelity.Performance)
	end

	if not protected and isPart and instance:IsDescendantOf(Workspace) then
		ground = isGround(instance)
		environment = instance.Anchored and not ground
	elseif not protected and isTextureObject then
		local parentPart = instance:FindFirstAncestorWhichIsA("BasePart")
		if parentPart and parentPart:IsDescendantOf(Workspace) then
			ground = isGround(parentPart)
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
			if className == "MeshPart" then
				rememberAndSet(visualSaved, instance, "TextureID", "")
			end
			if mode == "Ultra" and environment then
				rememberAndSet(visualSaved, instance, "LocalTransparencyModifier", 1)
				rememberAndSet(visualSaved, instance, "CastShadow", false)
			elseif mode == "Balanced" then
				rememberAndSet(visualSaved, instance, "Color", WHITE)
				rememberAndSet(visualSaved, instance, "CastShadow", false)
			end
		elseif isTextureObject and textureEligible then
			if className == "Decal" or className == "Texture" then
				rememberAndSet(visualSaved, instance, "Transparency", 1)
			elseif className == "SpecialMesh" then
				rememberAndSet(visualSaved, instance, "TextureId", "")
			else
				for _, property in ipairs({ "ColorMap", "NormalMap", "RoughnessMap", "MetalnessMap" }) do
					rememberAndSet(visualSaved, instance, property, "")
				end
			end
		elseif isEffect and mode ~= "Light" then
			rememberAndSet(visualSaved, instance, "Enabled", false)
		end
	end

	if collisionEnabled and isPart and environment then
		rememberAndSet(collisionSaved, instance, "CanCollide", false)
	end
end

local function invalidateScans()
	scanSerialCounter += 1
	for root in pairs(scanGeneration) do
		scanGeneration[root] = scanSerialCounter
	end
end

local function scanRoot(root: Instance?)
	if not root or (not activeMode and not collisionEnabled) then
		return
	end

	scanSerialCounter += 1
	local generation = scanSerialCounter
	scanGeneration[root] = generation

	task.spawn(function()
		local ok, initialChildren = pcall(function()
			return root:GetChildren()
		end)
		if not ok then
			return
		end

		local stack = {}
		for _, child in ipairs(initialChildren) do
			table.insert(stack, child)
		end

		local processed = 0
		local sliceStarted = os.clock()
		while #stack > 0 do
			if generation ~= scanGeneration[root] or (not activeMode and not collisionEnabled) then
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
			if os.clock() - sliceStarted >= 0.0015 or processed % 60 == 0 then
				task.wait()
				sliceStarted = os.clock()
			end
		end
	end)
end

local function disconnectWatchers()
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	table.clear(connections)

	started = false
	invalidateScans()
end

local function ensureWatchers()
	if started or (not activeMode and not collisionEnabled) then
		return
	end

	started = true
	table.insert(connections, Workspace.DescendantAdded:Connect(applyInstance))
	table.insert(connections, Lighting.DescendantAdded:Connect(applyInstance))
end

function Optimizer.Apply(profile: any)
	local mode = if type(profile) == "string" then profile else profile.Mode
	assert(mode == "Ultra" or mode == "Balanced" or mode == "Light", "UltraBoost: unsupported mode")
	if operationBusy then
		return
	end
	operationBusy = true

	activeMode = nil
	invalidateScans()
	restoreStore(visualSaved)
	restoreTerrainColors()
	activeMode = mode

	if mode == "Ultra" or mode == "Balanced" then
		rememberAndSet(visualSaved, Lighting, "GlobalShadows", false)
		if Terrain then
			rememberAndSet(visualSaved, Terrain, "Decoration", false)
			applyWhiteTerrain()
		end
	end

	ensureWatchers()
	scanRoot(Workspace)
	scanRoot(Lighting)
	operationBusy = false
end

function Optimizer.SetCollisionEnabled(enabled: boolean)
	if operationBusy then
		return
	end
	operationBusy = true
	collisionEnabled = enabled
	if not enabled then
		restoreStore(collisionSaved)
	else
		ensureWatchers()
		scanRoot(Workspace)
	end

	if not activeMode and not collisionEnabled then
		disconnectWatchers()
	else
		ensureWatchers()
	end
	operationBusy = false
end

function Optimizer.Restore()
	if operationBusy then
		return
	end
	operationBusy = true
	activeMode = nil
	collisionEnabled = false
	disconnectWatchers()
	restoreStore(visualSaved)
	restoreStore(collisionSaved)
	restoreTerrainColors()
	operationBusy = false
end

return Optimizer
