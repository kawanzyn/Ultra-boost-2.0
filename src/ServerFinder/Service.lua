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
	self.stats.requestErrors += 1
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
