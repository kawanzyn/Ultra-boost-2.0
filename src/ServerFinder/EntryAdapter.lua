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
