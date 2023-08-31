--###READ###
--This code was to handle the player data


local options = {

	kickIfDataFailed = true, -- If a players data doesn't load it will kick them and wont save, if this is false it will give them default values and wont save upon leaving (initializePlayers second return value will be true if data failed to load)

	runInStudio = false, -- If this is false while in Roblox Studio no API calls will be made, no data will be retrieved or saved, default values will be used

	autoSaveOnLeave = false, -- Save when player leaves without needing to call the exit function, it is reccomended to keep this off and call the exit function manually to make sure you know everything is ready before removing the data table

	autoLoadOnJoin = false, -- Loads data without needing to call initializePlayer

	retryCount = 3 -- The amount of times to retry an api call if it errors, it is not recommended to change this value
}



local runService = game:GetService("RunService")

local defaults = require(script.Defaults)
local onUpdate = require(script.OnUpdate)


local store = runService:IsStudio() and options["runInStudio"] and game:GetService("DataStoreService"):GetDataStore("Store") or nil


local dataCache = {}
local metaCache = {}
local failedCache = {}


function dunpack(dict) --Unpack function for default values (to prevent multiple users using the same data table)

	if typeof(dict) ~= "table" then 
		return dict 
	end

	local pack = {}
	for key, value in pairs(dict) do
		pack[key] = dunpack(value)
	end
	return pack
end


Data = {
	initializePlayer = function(player : Player)
		local success, data
		local fail = 0
		if options["runInStudio"] or not runService:IsStudio() then
			repeat 
				success, data = pcall(function()
					return store:GetAsync(tostring(player.UserId))
				end)
				fail = fail + 1
			until success or fail == options["retryCount"]
			if not success then
				if options["kickIfDataFailed"] then  -- if data failed to load and kickIfDataFailed is true then kick the player
					failedCache[player.Name] = true
					player:Kick("Data failed to load, you have been kicked to prevent data loss")
					return false, failedCache[player.Name]
				else -- if data failed to load and kickIfDataFailed was false then give the player default data and add them to the failedCache to make sure they dont save the broken data
					warn("Data failed to load for player: "..player.Name..". Giving default values |nothing will be saved|")
					warn("Error Message for data error: "..data)
					data = nil
					failedCache[player.Name] = true
				end
			end
		else
			warn("Data will not be saved since runInStudio is false")
		end
		if data ~= nil then -- Removing old keys and values if we remove one of the default values
			for key,value in pairs(data) do 
				if defaults[key] == nil then
					print("DATA KEY REMOVED FROM "..player.Name.." TO MATCH DEFAULTS. KEY: "..tostring(key))
					data[key] = nil
				end
			end
			dataCache[player.Name] = data
		else
			dataCache[player.Name] = dunpack(defaults)
		end

		local dataObject = {}
		local meta = setmetatable(dataObject, {
			__call = function()
				return dataCache[player.Name] --Calling the data table (eg. table()) will return the whole user data table
			end,
			__index = function(self, index)
				if dataCache[player.Name][index] == nil then
					dataCache[player.Name][index] = dunpack(defaults[index]) --Adding missing data keys
				end
				return dataCache[player.Name][index]
			end,
			__newindex = function(self, index, value)
				if dataCache[player.Name][index] == nil then
					dataCache[player.Name][index] = dunpack(defaults[index]) --Adding missing data keys
				end
				dataCache[player.Name][index] = value
				onUpdate[index](player, value, index) --Calls onUpdate function for the key specified in script.OnUpdate. If nothing is found it will default to the default update function
				return
			end})
		metaCache[player.Name] = meta
		return meta, failedCache[player.Name]
	end,


	getDataTable = function(player : Player)
		local name = player.Name
		if metaCache[name] == nil then
			local i = 0
			repeat task.wait(1) i = i + 1 until metaCache[name] ~= nil or i == options["retryCount"] + 2
			if metaCache[name] == nil then warn("FAILED TO GET DATA TABLE FOR PLAYER "..name) end
		end
		return metaCache[name]
	end,


	save = function(player : Player) -- Saving player data
		local success, data
		local fail = 0
		
		if failedCache[player.Name] then -- Do not save if data was not loaded correctly
			warn("Data was not saved for player "..player.Name.." since data failed to load")
			return false
		end
		
		if not options["runInStudio"] and runService:IsStudio() then -- If runInStudio is set to false and we are running in studio then do not save
			warn("Data was not saved since runInStudio is false")
			return false
		end
		
		if dataCache[player.Name] == nil then -- if the data table was nil do not save
			warn("Data was not saved for player "..player.Name.." since data table was nil")
			return false
		end
		
		repeat 
			success, data = pcall(function()
				store:SetAsync(tostring(player.UserId), dataCache[player.Name])
			end)
		until success or fail == options["retryCount"] -- Try to save data. If it fails, retry until we hit the max retry count
		print("Data "..(success and " saved " or " failed to save with error: "..tostring(data)).." for player: "..player.Name)
	end,
	
	exit = function(player : Player) -- Saves player data and removes data tables (for a leaving player)
		Data.save(player)
		failedCache[player.Name] = nil
		metaCache[player.Name] = nil
		dataCache[player.Name] = nil
	end
}
-- Automation settings
if options["autoSaveOnLeave"] then
	game.Players.PlayerRemoving:Connect(Data.exit)
end
if options["autoLoadOnJoin"] then
	game.Players.PlayerAdded:Connect(Data.initializePlayer)
end

return Data
