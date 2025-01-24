return(function()
	local PROGRAM_NAME = "rbxm-suite"
	local PROGRAM_STORAGE = "Hellsing_Development_Items"
	local PROGRAM_TEMP = PROGRAM_STORAGE .. "/temp.dat"
	local HttpService = game:GetService("HttpService")
	local pathToUrl = getcustomasset or getsynasset or error("Failed to load model! (No custom asset loader found)")

	local function useGlobal(key, initialValue)
		local value = getgenv(key)["__rbxm_suite_" .. key]
		if value == nil then
			value = initialValue
			getgenv(key)["__rbxm_suite_" .. key] = value
		end
		return value
	end
	local function useOption(option, defaultValue)
		if option == nil then
			return defaultValue
		else
			return option
		end
	end
	local function httpGet(url)
		local response, code = game:HttpGetAsync(url)
		return assert(response, "Error " .. tostring(code) .. ": Failed to GET from " .. url)
	end
	local function log(message, isVerbose)
		if isVerbose then
			print(message)
		end
	end

	local github do
		github = {}
		local function init()
			if not isfolder(PROGRAM_STORAGE) then
				makefolder(PROGRAM_STORAGE)
				makefolder(PROGRAM_STORAGE .. "/models")
				writefile(PROGRAM_STORAGE .. "/latest.json", "{}")
			end
		end
		local function updateLatestJson(mutate)
			local data = readfile(PROGRAM_STORAGE .. "/latest.json")
			local versions = HttpService:JSONDecode(data)
			mutate(versions)
			writefile(PROGRAM_STORAGE .. "/latest.json", HttpService:JSONEncode(versions))
		end
		local function getLocalTag(id)
			local data = readfile(PROGRAM_STORAGE .. "/latest.json")
			local versions = HttpService:JSONDecode(data)

			return versions[id]
		end
		local function fetchLatestTag(user, repo)
			local response = httpGet("https://api.github.com/repos/" .. user .. "/" .. repo .. "/releases/latest")
			return HttpService:JSONDecode(response).tag_name
		end
		local function downloadLatest(user, repo, asset, id, path)
			local latestTag = fetchLatestTag(user, repo)
			if isfile(path) and getLocalTag(id) == latestTag then
				return path
			end
			local response = httpGet("https://github.com/" .. user .. "/" .. repo .. "/releases/latest/download/" .. asset)
			writefile(path, response)
			updateLatestJson(function(versions)
				versions[id] = latestTag
			end)
		end
		function github.download(user, repo, tag, asset)
			local id = string.gsub(table.concat({user, repo, tag, asset}, "-"), "[^a-zA-Z0-9_%-]", "_")
			local path = PROGRAM_STORAGE .. "/models/" .. id .. ".rbxm"
			if tag == "latest" then
				if isfile(path) then
					task.defer(downloadLatest, user, repo, asset, id, path)
				else
					downloadLatest(user, repo, asset, id, path)
				end
				return path
			end
			if isfile(path) then
				return path
			end
			local response = httpGet("https://github.com/" .. user .. "/" .. repo .. "/releases/download/" .. tag .. "/" .. asset)
			writefile(path, response)
			return path
		end
		function github.clearCache()
			delfolder(PROGRAM_STORAGE)
			init()
		end

		init()
	end

	local modules = useGlobal("modules", {})
	local currentlyLoading = {}

	local idToScript = useGlobal("idToScript", {})
	local scriptToId = useGlobal("scriptToId", {})
	local globalMap = useGlobal("globalMap", {})

	local function loadModule(object, caller, allowRecursion)
		local module = modules[object]
		if module.isLoaded then
			return module.data
		end
		if caller and not allowRecursion then
			currentlyLoading[caller] = object
			local currentObject = object
			local depth = 0
			while currentObject do
				depth = depth + 1
				currentObject = currentlyLoading[currentObject]
				if currentObject == object then
					local str = currentObject:GetFullName()
					for _ = 1, depth do
						currentObject = currentlyLoading[currentObject]
						str = str .. "  ⇒ " .. currentObject:GetFullName()
					end
					error("Failed to load '" .. object:GetFullName() .. "'! Detected a circular dependency chain: " .. str, 2)
				end
			end
		end
		local data = module.fn()
		if currentlyLoading[caller] == object then -- Thread-safe cleanup!
			currentlyLoading[caller] = nil
		end
		module.data = data
		module.isLoaded = true

		return data
	end
	local function createOutputStream()
		local output = {}
		local function push(str)
			table.insert(output, str)
		end
		local function concat()
			return table.concat(output)
		end
		return {
			push = push,
			concat = concat,
		}
	end
	local function registerModule(object, allowRecursion)
		local id = HttpService:GenerateGUID()
		local function requireImpl(target)
			if typeof(target) == "Instance" and modules[target] then
				return loadModule(target, object, allowRecursion)
			else
				return require(target)
			end
		end
		modules[object] = {
			data = nil,
			fn = nil,
			isLoaded = false,
		}
		idToScript[id] = object
		scriptToId[object] = id
		globalMap[id] = {object, requireImpl}
		return id
	end
	local function pushHeader(stream)
		stream.push("local modules, globalMap, idToScript = ...")
	end
	local function pushModule(object, stream, options)
		if not object:IsA("LocalScript") and not object:IsA("ModuleScript") then
			return
		end
		local id = string.format("%q", registerModule(object, not options.nocirculardeps))
		local path = string.format("%q", "@" .. PROGRAM_NAME .. "." .. object:GetFullName())
		if options.debug then
			object.Source = "local script, require = unpack((...)[" .. id .. "]); " .. object.Source
			stream.push(
				"modules[idToScript[" .. id .. "]].fn = function ()\n" ..
					"local fn, err = loadstring(idToScript[" .. id .. "].Source, " .. path .. ")\n" ..
					"return assert(fn, err)(globalMap)\n" ..
					"end\n"
			)

			return
		end
		object.Source = "local script, require = unpack(globalMap[" .. id .. "]); " .. object.Source
		stream.push("modules[idToScript[" .. id .. "]].fn = function ()\n" .. object.Source .. "\nend\n")
	end
	local function getObjectsNoCache(url, isVerbose)
		local assetId = string.match(url, "^rbxassetid://(%d+)$")
		if not assetId then
			return game:GetObjects(url)
		end
		local data = HttpService:JSONDecode(httpGet("https://assetdelivery.roblox.com/v2/assetId/" .. assetId))
		local rbxmData = httpGet(data.locations[1].location)

		if rbxmData == "" then
			log("⚠️ Model data for asset " .. assetId .. " is blank!", isVerbose)
			return game:GetObjects(url)
		end
		writefile(PROGRAM_TEMP, rbxmData)
		local success, result = pcall(function()
			return game:GetObjects(pathToUrl(PROGRAM_TEMP))
		end)
		delfile(PROGRAM_TEMP)
		if not success then
			log("⚠️ Model data for asset " .. assetId .. " failed to load! " .. tostring(result), isVerbose)
			return game:GetObjects(url)
		end

		return result
	end
	local function getObjects(url, options)
		if string.find(url, "^rbxassetid://") then
			if options.nocache then
				return getObjectsNoCache(url, options.verbose)
			end

			return game:GetObjects(url)
		else
			return game:GetObjects(pathToUrl(url))
		end
	end
	local function hydrate(stream, model, options)
		pushModule(model, stream, options)

		for _, object in ipairs(model:GetDescendants()) do
			pushModule(object, stream, options)
		end
	end
	local function initialize(stream)
		assert(loadstring(stream.concat(), "@" .. PROGRAM_NAME))(modules, globalMap, idToScript)
	end
	local function startScript(object, index, options)
		local spawn = options.deferred and task.defer or task.spawn

		spawn(function()
			log("ℹ️ " .. index .. " Running " .. object:GetFullName(), options.verbose)

			loadModule(object)

			log("✅ " .. index .. " Done!", options.verbose)
		end)
	end
	local function startScripts(model, options)
		local scripts = 0

		if model:IsA("LocalScript") and not model.Disabled then
			scripts = scripts + 1
			startScript(model, scripts, options)
		end

		for _, object in ipairs(model:GetDescendants()) do
			if object:IsA("LocalScript") and not object.Disabled then
				scripts = scripts + 1
				startScript(object, scripts, options)
			end
		end
	end
	local function launch(url, opt)
		assert(type(url) == "string", "The first argument 'url' must be a string.")
		assert(type(opt) == "table" or opt == nil, "The second argument 'options' must be a table or nil.")
		opt = opt or {}
		local options = {
			runscripts     = useOption(opt.runscripts, true),
			deferred       = useOption(opt.deferred, true),
			nocache        = useOption(opt.nocache, false),
			nocirculardeps = useOption(opt.nocirculardeps, true),
			debug          = useOption(opt.debug, false),
			verbose        = useOption(opt.verbose, false),
		}
		log("\n\n" .. utf8.char(0x1F680) .. " Launching file '" .. url .. "'\n", options.verbose)
		local clock = os.clock()
		local objects = getObjects(url, options)
		local stream = createOutputStream()
		pushHeader(stream)
		for _, model in ipairs(objects) do
			hydrate(stream, model, options)
		end
		initialize(stream)
		if options.runscripts then
			for _, model in ipairs(objects) do
				startScripts(model, options)
			end
		end

		log("\n\n" .. utf8.char(0x1F389) .. " Done! Took " .. string.format("%.2f", (os.clock() - clock) * 1000) .. " milliseconds.\n", options.verbose)

		return unpack(objects)
	end
	local function require(object)
		assert(typeof(object) == "Instance", "The script must be an Instance.")
		assert(object:IsA("LuaSourceContainer"), "The script must be a Lua module or script.")
		assert(modules[object], "The script must be registered with rbxmSuite.")

		return loadModule(object)
	end
	local function download(repository, asset)
		local user, repo, tag = string.match(repository, "([^/]+)/([^@]+)@?(.*)")

		assert(user and repo, "Invalid repository format.")
		assert(type(asset) == "string", "The asset must be a string.")

		if tag == "" or tag == nil then
			tag = "latest"
		end

		return github.download(user, repo, tag, asset)
	end
	local function clearCache()
		return github.clearCache()
	end
	local function Load_RbxAsset(releases,file)
		local path = download(releases,file)
		local model = launch(path)
		local runrbx = require(model)
		return require(runrbx)
	end
	return {
		launch = launch,
		require = require,
		download = download,
		clearCache = clearCache,
		load_rbxasset = Load_RbxAsset,
	}
end)()
