--!strict
-- Lightweight client-side FPS sampler. This is an estimate, not a benchmark.

local RunService = game:GetService("RunService")
local Monitor = {}

local connection: RBXScriptConnection? = nil
local frames = 0
local elapsed = 0
local currentFps = 0

function Monitor.Start(interval: number?, onSample: ((number) -> ())?)
	if connection then
		return
	end

	local sampleInterval = math.max(interval or 1, 0.5)
	frames = 0
	elapsed = 0

	connection = RunService.Heartbeat:Connect(function(dt)
		frames += 1
		elapsed += dt

		if elapsed >= sampleInterval then
			currentFps = math.floor(frames / math.max(elapsed, 0.001) + 0.5)
			if onSample then
				task.spawn(function()
					local ok, err = pcall(onSample, currentFps)
					if not ok then
						warn("UltraBoost FPS callback failed: " .. tostring(err))
					end
				end)
			end
			frames = 0
			elapsed = 0
		end
	end)
end

function Monitor.GetFps(): number
	return currentFps
end

function Monitor.Stop()
	if connection then
		connection:Disconnect()
		connection = nil
	end
	frames = 0
	elapsed = 0
end

return Monitor
