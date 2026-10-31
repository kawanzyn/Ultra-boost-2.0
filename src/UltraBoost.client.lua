--!strict
-- Place as a LocalScript in StarterPlayer > StarterPlayerScripts.
-- The modular source is intended for an experience you own or are authorized to edit.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("UltraBoost"):WaitForChild("Config"))
local Optimizer = require(ReplicatedStorage:WaitForChild("UltraBoost"):WaitForChild("Optimizer"))
local Monitor = require(ReplicatedStorage:WaitForChild("UltraBoost"):WaitForChild("Monitor"))

local profile = Config.Profiles[Config.Profile]
if not profile then
	warn("UltraBoost: unknown profile '" .. tostring(Config.Profile) .. "'; using Balanced")
	profile = Config.Profiles.Balanced
end

Optimizer.Apply(profile)
if Config.EnableEnvironmentCollision then
	Optimizer.SetCollisionEnabled(true)
end

if Config.EnableFpsMonitor then
	Monitor.Start(Config.FpsSampleInterval, function(fps)
		if fps < Config.LowFpsThreshold then
			warn(string.format(
				"UltraBoost: estimated client FPS is low (%d). Check rendering, scripts and physics bottlenecks.",
				fps
			))
		end
	end)
end

-- Call Optimizer.Restore() and Monitor.Stop() from your own disable/UI flow.
