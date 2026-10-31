--!strict
-- UltraBoost configuration for the modular client implementation.

local Config = {}

-- Supported values: "Ultra", "Balanced", and "Light".
Config.Profile = "Balanced"
Config.EnableFpsMonitor = true
Config.FpsSampleInterval = 1
Config.LowFpsThreshold = 28

-- Local collision changes are optional and may not override server authority.
Config.EnableEnvironmentCollision = false

Config.Profiles = {
	Ultra = { Mode = "Ultra" },
	Balanced = { Mode = "Balanced" },
	Light = { Mode = "Light" },
}

return Config
