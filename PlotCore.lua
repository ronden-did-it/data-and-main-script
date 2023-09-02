--###READ###
--This code was to handle the main functionality of the game
local datastoreService = game:GetService("DataStoreService")


local PlotService = require(script.Parent.PlotService)
local plots = workspace.Plots

local replicatedPlot = game.ReplicatedStorage.Plot
local syncing = game.ReplicatedStorage.Syncing

local prices = require(syncing.Scripts.StartingPrices)

local dustLeader = datastoreService:GetOrderedDataStore("TotalDustBoard")
local starsLeader = datastoreService:GetOrderedDataStore("TotalStarsBoard")

local gift = syncing.Gift

local loaded = {}
local availableDrops = {}
local mergeDelay = {}
local uniDelay = {}

local dataStore = require(game:GetService("ServerScriptService").Data)

local buttonFunctions = {}


local function makeHitBox(char) -- Creating a hitbox for collecting drops from stars
	local newHitBox = Instance.new("Part")
	local newWeld = Instance.new("Weld")
	newHitBox.Anchored = true
	newHitBox.CanCollide = false
	newHitBox.Name = "Hitbox"
	newHitBox.Transparency = 1
	newHitBox.Parent = char
	newHitBox:PivotTo(char:WaitForChild("HumanoidRootPart").CFrame)
	newHitBox.Size = Vector3.new(5, 7, 3)
	newWeld.Part0 = char.HumanoidRootPart
	newWeld.Part1 = newHitBox
	newWeld.Parent = newHitBox
	newHitBox.Anchored = false
	task.wait()
	char:PivotTo(workspace.Plots:WaitForChild(char.Name).Spawn.CFrame + Vector3.new(0, 2, 0)) -- Spawning player at their plot
end
local function removeCollision(char) -- Adding the characters parts to the "Players" collision group
	for i,v in pairs(char:GetChildren()) do
		if v:IsA("BasePart") then
			v.CollisionGroup = "Players"
		end
	end
end

-- buttons functions for when a player steps on a button
buttonFunctions.Star = function(player, value, data) 
	if value >= 1 and prices["Buy"..value.."STAR"] ~= nil then -- If the player has enough coins
		value = math.floor(value)
		local stars = data.purchasedStars
		local price = math.floor(stars + value > 15 and value * 14 * stars or value * 3 * stars) -- Getting the price based on how many stars they have already purchased
		if data.coins >= price then -- Checking player has enough coins
			data.coins = data.coins + -price
			data.purchasedStars = data.purchasedStars + value -- Increasing the total amount of purchased stars the player has

			PlotService.spawnStar(plots[player.Name], value, "T1", value >= 70) -- Spawn the star, 3rd arg is a bool that decides if the script should spawn in preformance mode or not (for large spawn amounts)
		end
	end
end

buttonFunctions.Merge = function(player, value, data) -- Merging the currently owned stars
	if table.find(mergeDelay, player.Name) == nil then
		table.insert(mergeDelay, player.Name)
		PlotService.merge(plots[player.Name], false) -- Merge function, second arg is preformance mode
		task.wait(0.2)
		table.remove(uniDelay, table.find(uniDelay, player.Name)) -- Prevent spamming of all buttons
		task.wait(0.8)
		table.remove(mergeDelay, table.find(mergeDelay, player.Name)) -- Prevent spamming of merge
	end
end

buttonFunctions.Rate = function(player, value, data)  -- Increasing the rate at which star dust is turned into coins
	local price = math.floor(5 * data.conversionRate)
	if data.coins >= price then 
		data.coins = data.coins + -price
		data.conversionRate = data.conversionRate + math.ceil(math.clamp(data.purchasedStars/15, 1, math.huge))
	end
end

buttonFunctions.Deposit = function(player, value, data) -- Depositing star dust into converter
	data.convertingStarDust = data.convertingStarDust + data.playerStarDust
	data.playerStarDust = 0
end




game.Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(makeHitBox)
	player.CharacterAppearanceLoaded:Connect(removeCollision)
	for i,v in ipairs(plots:GetChildren()) do -- Giving the player a plot
		if v:GetAttribute("occupied") == false then 
			v:SetAttribute("occupied", true)
			v.Name = player.Name
			break
		end
	end
	local plot = plots[player.Name]
	local functionality = plot.Functionality
	availableDrops[player.Name] = 0

	plot.Functionality.ObbyPort.Part.Transparency = 0.1

	local data = PlotService.loadData(player, plot) -- Loading data
	assert(data, "Player data was nil") -- Throwing and error if data is nil
	table.insert(loaded, player.Name)

	local loopIndex = 0
	while player ~= nil do -- Main game loop
		loopIndex = loopIndex + 1
		local available = data.convertingStarDust
		local converted = math.clamp(data.conversionRate, 0, available)
		if converted > 0 then
			data.convertingStarDust = data.convertingStarDust + -converted -- Removing star dust so they can be added to coins
			local multiply = data.gamePasses.dc.Purchased == true and 2 or 1
			data.coins = data.coins + converted * multiply -- Turning star dust into coins
		end
		data.timeInGame = data.timeInGame + 1 -- Increasing the time the player has been in game
		data.totalTime = data.totalTime + 1
		if os.time() - data.startTime >= 86400 then -- Starting the gifts again every day passed
			data.startTime = os.time()
			data.timeInGame = 0
			data.gifts = "f:f:f:f:f:f:f:f:f"
		end

		if not data.obbyStar and os.time() - data.obbyStartTime >= 3600 then -- Enabling the star at the end of the obby again every hour
			data.obbyStartTime = os.time()
			data.obbyStar = true
		end

		task.wait(1)
		if not availableDrops[player.Name] then break end
		if loopIndex == 5 then -- Dropping star drops
			loopIndex = 0
			availableDrops[player.Name] = availableDrops[player.Name] + functionality.Stars:GetAttribute("tick") -- Adding to the available amount of drops, tick is a precalculated value, it is the amount of drops all the stars combined make
			syncing.Drop:FireClient(player) -- Calling on the client to visualize the drops
			if PlotService.boost[player.Name] then -- If the players had a boost drop again after 2.5 seconds
				spawn(function()
					task.wait(2.5)
					if not availableDrops[player.Name] then return end
					availableDrops[player.Name] = availableDrops[player.Name] + functionality.Stars:GetAttribute("tick")
					syncing.Drop:FireClient(player)
				end)
			end
		end
	end
end)

game.Players.PlayerRemoving:Connect(function(player) 
	local plot = plots:FindFirstChild(player.Name)
	if plot == nil then -- If the player didn't load in, return
		return
	end
	if table.find(loaded, player.Name) then
		table.remove(loaded, table.find(loaded, player.Name))
		local data = dataStore.getDataTable(player)
		if PlotService.boost[player.Name] then
			data.boost = PlotService.boost[player.Name] -- Saving players boost on leave
		else
			data.boost = 0
		end
		PlotService.boost[player.Name] = nil -- Removing player from the boost list
		local stars = data.stars
		local save = {}
		for i,v in pairs(plot.Functionality.Stars:GetChildren()) do
			save[v.Name] = save[v.Name] ~= nil and save[v.Name] + 1 or 1 -- Adding owned stars to a table
		end
		data.stars = save -- Saving all the stars the player has

		local stars = data.purchasedStars
		local dust = data.totalStarDust
		if player.UserId > 0 then
			task.spawn(function()
				local id = player.UserId
				pcall(function()
					dustLeader:SetAsync(id, dust) -- Adding player to the leaderboard data store
				end)
				pcall(function()
					starsLeader:SetAsync(id, stars) -- Adding player to the leaderboard data store
				end)
			end)
		end
		dataStore.exit(player) -- Removing players data from cache
	end
	-- Reset plot
	plot.Functionality.Stars:ClearAllChildren() -- Removing all players stars
	plot.Functionality.Values.FloorIndex.Value = 1 
	plot.Functionality.Values.PositionIndex.Value = 1
	plot.Functionality.ObbyPort.Part.Transparency = 1
	plot.Functionality.StarToCoins.One.ParticleEmitter.Enabled = false
	plot.Functionality.StarToCoins.Two.ParticleEmitter.Enabled = false
	PlotService.removeFloor(plot, #plot.Functionality.Floors:GetChildren() - 1) -- Remving all the floors
	plot.Functionality.BestStarThing["tree stump"].Model.Part.SurfaceGui.TextLabel.Text = ""
	local star = plot.Functionality.BestStarThing:FindFirstChildOfClass("Model")
	local starc = workspace.Assets.CompanionStars:FindFirstChild(player.Name)
	if star then
		star:Destroy()
	end
	if starc then
		starc:Destroy()
	end
	plot:SetAttribute("occupied", false)
	plot.Name = "Plot"
	availableDrops[player.Name] = nil
end)



replicatedPlot.Collect.OnServerEvent:Connect(function(player, amount) -- When a player picks up a drop
	local data = dataStore.getDataTable(player)
	local taken = math.clamp(amount, 0, availableDrops[player.Name]) -- math.clamp to make sure exploiters cant take more than they have
	availableDrops[player.Name] = availableDrops[player.Name] - taken -- Changing the available  amount of drops

	local multiply = data.gamePasses.ds.Purchased == true and 2 or 1
	data.totalStarDust = data.totalStarDust + taken * multiply
	if data.gamePasses.ad.Purchased == false then -- If they dont own auto deposit
		data.playerStarDust = data.playerStarDust + taken * multiply  -- Add picked up drop to player star dust
	else
		data.convertingStarDust = data.convertingStarDust + taken * multiply -- Add picked up drop to converter
	end
end)

replicatedPlot.Button.OnServerEvent:Connect(function(player, button, value) -- When player steps on a button
	if table.find(uniDelay, player.Name) ~= nil then 
		return 
	end
	table.insert(uniDelay, player.Name)
	task.spawn(function()
		task.wait(0.25)
		table.remove(uniDelay, table.find(uniDelay, player.Name))
	end)
	local data = dataStore.getDataTable(player)
	if buttonFunctions[button] then
		buttonFunctions[button](player, value, data)
	end
end)
