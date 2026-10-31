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
