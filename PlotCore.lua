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

-- Creating a hitbox for collecting drops from stars.
-- The hitbox works by creating a weld on the hitbox and the 
-- players root part, then using .Touched to detect when it hits drops.
local function makeHitBox(char) 
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
-- Adding the characters parts to the "Players" collision group
-- to remove collisions with invisible walls for drops
-- Does this by looping through the players character and setting all 
-- BaseParts CollisionGroup property to "Players"
local function removeCollision(char)
	for i,v in pairs(char:GetChildren()) do
		if v:IsA("BasePart") then
			v.CollisionGroup = "Players"
		end
	end
end

-- buttons functions for when a player steps on a button

-- When a player steps on a button (detected with button.Touched) 
-- it fires an event to the server, it sends the button name
-- and the correlating function is called on line 342
buttonFunctions.Star = function(player, value, data) 
    -- Makes sure the amount of stars being purchased is valid by
    -- looking for the amount in the prices table
	if value >= 1 and prices["Buy"..value.."STAR"] ~= nil then 
		value = math.floor(value)
        local stars = data.purchasedStars
        -- Getting the price based on how many stars they have already purchased, does this my multiplying the amount of 
        -- stars the player is buying * 14 * starsOwned, 14 is just a multiplier that seemed to work well
		local price = math.floor(stars + value > 15 and value * 14 * stars or value * 3 * stars) 
        -- Checking player has enough coins by comparing the players coins to the price
        if data.coins >= price then
            data.coins = data.coins + -price
            -- Increasing the total amount of purchased stars the player has by adding "value" to the purchasedStars
            -- data key
			data.purchasedStars = data.purchasedStars + value
            -- Spawn the star, 3rd arg is a bool that decides if the script should spawn in preformance mode or not (for large spawn amounts)
            -- It spawns the star by checking an int value that holds the current floor number and
            -- checking another int value that holds the amount of stars on that floor
            -- it then creates a clone of the default star and positions it based on the floor and stars on it.
			PlotService.spawnStar(plots[player.Name], value, "T1", value >= 70)
		end
	end
end
-- Another button function, above comment applies
buttonFunctions.Merge = function(player, value, data) -- Merging the currently owned stars
	-- Checking if the player in on a cooldown by looking for their name in the mergeDelay table
	if table.find(mergeDelay, player.Name) == nil then
		-- Prevent spamming of all buttons by adding player to merge table
		table.insert(mergeDelay, player.Name)
		-- Merge function, second arg is preformance mode
		-- This will loop through all stars finding pairs of
		-- three, deleteing them and replacing with an upgraded star
		PlotService.merge(plots[player.Name], false)
		task.wait(0.2)
		table.remove(uniDelay, table.find(uniDelay, player.Name))
		task.wait(0.8)
		-- Removing player from the cooldown table
		table.remove(mergeDelay, table.find(mergeDelay, player.Name)) 
	end
end
-- Another button function, above comment applies
buttonFunctions.Rate = function(player, value, data)  -- Increasing the rate at which star dust is turned into coins
	-- Gets the price for the rate upgrade by multiplying the current rate * 5
	local price = math.floor(5 * data.conversionRate)
	if data.coins >= price then 
		-- Removes players coins by the price by subtracting the price from the players coins
		data.coins = data.coins - price 
		-- Increasing the rate by the players total stars / 15
		data.conversionRate = data.conversionRate + math.ceil(math.clamp(data.purchasedStars/15, 1, math.huge))
	end
end
-- Another button function, above comment applies
buttonFunctions.Deposit = function(player, value, data) -- Depositing star dust into converter
	-- Simply adds the players held star dust to the convertingStarDust value 
	-- then sets players star dust to 0
	data.convertingStarDust = data.convertingStarDust + data.playerStarDust
	data.playerStarDust = 0
end



-- This is to handle a new player joining
game.Players.PlayerAdded:Connect(function(player)
	-- Connects the hitbox creation function to the characterAdded event so that
	-- when the player spawns they will have a hitbox
	player.CharacterAdded:Connect(makeHitBox)
	player.CharacterAppearanceLoaded:Connect(removeCollision)
	-- Giving the player a plot by looping through all the plots
	-- and checking if the occupied attribute is false.
	-- Once it finds one it sets the occupied attribute to true
	-- and changes the plots name to match the players
	for i,v in ipairs(plots:GetChildren()) do 
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
    
	-- loads the data by calling on my data module
	local data = PlotService.loadData(player, plot)
	-- Throwing and error if data is nil
	assert(data, "Player data was nil")
	table.insert(loaded, player.Name)

	local loopIndex = 0
	-- This is the main game loop
	while player ~= nil do 
		loopIndex = loopIndex + 1
		-- Converting the star drops to coins
		-- using math.clamp to make sure the amount converted doesn't
		-- exceed the amount available
		local available = data.convertingStarDust
		local converted = math.clamp(data.conversionRate, 0, available)
		if converted > 0 then
			data.convertingStarDust = data.convertingStarDust - converted -- Removing star dust so they can be added to coins
			local multiply = data.gamePasses.dc.Purchased == true and 2 or 1
			-- Adding star dust to coins and if the player owns the double coins
			-- gamepass it will multiply by 2, otherwise it will multiply by 1
			-- we do this by setting "multiply" to 2 if they own it and 1 if they dont
			data.coins = data.coins + converted * multiply 
		end
		data.timeInGame = data.timeInGame + 1 -- Increasing the time the player has been in game
		data.totalTime = data.totalTime + 1
		-- Checking how many seconds have passed since the start
		-- by taking the start time away from the current time (in seconds)
		-- if it exceeds 86400 (1 day) then we set the start time to the current time and 
		-- set all the gifts back to unopened with the string "f:f:f:f:f:f:f:f:f" f for false
		if os.time() - data.startTime >= 86400 then 
			data.startTime = os.time()
			data.timeInGame = 0
			data.gifts = "f:f:f:f:f:f:f:f:f"
		end
        -- Enabling the star at the end of the obby again every hour by setting
		-- the players "obbyStar" data to true
		if not data.obbyStar and os.time() - data.obbyStartTime >= 3600 then
			data.obbyStartTime = os.time()
			data.obbyStar = true
		end

		task.wait(1)
		if not availableDrops[player.Name] then 
			break 
		end
        -- Every 5 ticks of the loop we start the star drops
		if loopIndex == 5 then
			loopIndex = 0
			-- Adding to the available amount of drops, tick is a precalculated value, 
			-- it is the amount of drops all the stars combined make, we add this value to the
			-- availableDrops table under the players name. This is just to prevent exploiters from
			-- taking what they dont have, since the drops are handled on the client, we have to keep
			-- track of how many drops the player should be able to collect and if they try collect more,
			-- do nothing
			availableDrops[player.Name] = availableDrops[player.Name] + functionality.Stars:GetAttribute("tick")
			-- Calling on the client to create the drops using a remote event
			syncing.Drop:FireClient(player)
			-- If the players name is in the boost table this means
			-- they currently have a 2x boost so we will drop again in 2.5 ticks instead of 5
			-- we do this by using spawn so we don't yield the current thread and can add
			-- add the extra drops without messing with the main tick
			if PlotService.boost[player.Name] then
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
	-- getting the players plot by looking for a plot with their name
	local plot = plots:FindFirstChild(player.Name)
	-- If the player didn't have a plot, they didn't load in correctly
	-- so we should not continue to make sure we dont save any
	-- broken data
	if plot == nil then
		return
	end
	-- Looking in the loaded table to make 100% sure the player
	-- was loaded into the game. The player is only added to the loaded table
	-- once they are completely loaded into the game successfully
	if table.find(loaded, player.Name) then
		table.remove(loaded, table.find(loaded, player.Name))
		local data = dataStore.getDataTable(player)
		if PlotService.boost[player.Name] then
			-- Saving players boost on leave by adding the amount of boost left
			-- to the players data.boost
			data.boost = PlotService.boost[player.Name]
		else
			data.boost = 0
		end
		-- Removing player from the boost list to clean up
		PlotService.boost[player.Name] = nil
		local stars = data.stars
		local save = {}
		for i,v in pairs(plot.Functionality.Stars:GetChildren()) do
			save[v.Name] = save[v.Name] ~= nil and save[v.Name] + 1 or 1 
		end
		-- Saving all the stars the player has by looping through their stars folder 
		-- and adding the stars name to the stars table, then setting data.stars to said table
		data.stars = save

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
		-- Removing players data from cache and saving using roblox data stores
		dataStore.exit(player)
	end
	-- Reset plot
	-- Removing all players stars by clearing the children of the stars folder
	plot.Functionality.Stars:ClearAllChildren()
	-- Setting all positioning values back to 1
	plot.Functionality.Values.FloorIndex.Value = 1 
	plot.Functionality.Values.PositionIndex.Value = 1
	plot.Functionality.ObbyPort.Part.Transparency = 1
	-- Turning off the plots particles
	plot.Functionality.StarToCoins.One.ParticleEmitter.Enabled = false
	plot.Functionality.StarToCoins.Two.ParticleEmitter.Enabled = false
	-- Remving all the floors, it does this by passing the amount of
	-- floors - 1 (- 1 for the first floor) to the removeFloor function. The function will find 
	-- the floors by number and destroy them
	PlotService.removeFloor(plot, #plot.Functionality.Floors:GetChildren() - 1)
	plot.Functionality.BestStarThing["tree stump"].Model.Part.SurfaceGui.TextLabel.Text = ""
	local star = plot.Functionality.BestStarThing:FindFirstChildOfClass("Model")
	local starc = workspace.Assets.CompanionStars:FindFirstChild(player.Name)
	if star then
		star:Destroy()
	end
	if starc then
		starc:Destroy()
	end
	-- Setting the plots occupied attribute to false so that
	-- new players can take it
	plot:SetAttribute("occupied", false)
	plot.Name = "Plot"
	-- Removing player from drops table for clean up
	availableDrops[player.Name] = nil
end)


-- When a player picks up a drop (hitbox .Touched) it fires the drop amount
-- to the server, here if where we handle the logic
replicatedPlot.Collect.OnServerEvent:Connect(function(player, amount) 
	local data = dataStore.getDataTable(player)
	-- math.clamp the amount they picked up to make sure they dont go over availableDrops so exploiters cant take more than they have
	local taken = math.clamp(amount, 0, availableDrops[player.Name]) 
	-- Subtracting the amount taken from the players availableDrops
	availableDrops[player.Name] = availableDrops[player.Name] - taken 

	-- Here we add the taken drops to the star dust
	-- We set multiply to 2 if they own the double star dust gamepass so that they get 2x the amount
	local multiply = data.gamePasses.ds.Purchased == true and 2 or 1
	data.totalStarDust = data.totalStarDust + taken * multiply
	-- We checked if they own auto deposit
	if data.gamePasses.ad.Purchased == false then 
		-- If not, we add the taken amount to the players StarDust
		data.playerStarDust = data.playerStarDust + taken * multiply 
	else
		-- If they do we add the taken amount straight to the convertingStarDust to be turned into coins
		data.convertingStarDust = data.convertingStarDust + taken * multiply
	end
end)

-- When player steps on a button (button.Touched) it will fire this event
replicatedPlot.Button.OnServerEvent:Connect(function(player, button, value)
	-- We make sure they are not on cooldown by checking if their name is inthe uniDelay table
	if table.find(uniDelay, player.Name) ~= nil then 
		return 
	end
	-- We put them on cooldown by adding their name to the uniDelay table
	table.insert(uniDelay, player.Name)
	task.spawn(function()
		task.wait(0.25)
		table.remove(uniDelay, table.find(uniDelay, player.Name))
	end)
	local data = dataStore.getDataTable(player)
	if buttonFunctions[button] then
		-- We call the function that matches the button name by indexing buttonFunctions with the buttons name
		buttonFunctions[button](player, value, data)
	end
end)
