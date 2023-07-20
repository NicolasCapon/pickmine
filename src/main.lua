local Miner = require("miner")
local actions = require("actions")
local turtle_tools = require("turtle_tools")

-- MAIN

local miner = Miner:new()
for _ = 1, 16 do
    miner:addTask({ fn = "travelBy", params = { { x = 32, y = 1, z = 0 }, "inspectUpDown", "verifyFuelLevel", "verifyInventoryLevel" } })
    miner:addTask({ fn = "travelBy", params = { { x = -32, y = 1, z = 0 }, "inspectUpDown", "verifyFuelLevel", "verifyInventoryLevel" } })
end
miner:addTask({ fn = "travelTo", params = { miner.home } })
local requiredFuel, _ = miner:getTasksFuelAndPos()

local function askForFuel(fuelLvl, m)
    local refuelLvl = fuelLvl - turtle.getFuelLevel()
    if refuelLvl > 0 then
        -- Prompt for manuel refuel
        print("Missing " .. turtle_tools.getCoalNumForFuelLevel(refuelLvl) .. " minecraft:coal for this job.")
        print("Would you like to refuel ? [y/n]")
        print("If yes then place coal then answer y")
        local answer = read()
        if answer == "n" then
            m:execTasks()
        else
            m:refuelTo(fuelLvl)
            askForFuel(fuelLvl)
        end
    else
        m:execTasks()
    end
end

askForFuel(requiredFuel)