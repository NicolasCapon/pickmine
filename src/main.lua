local Miner = require("miner")
local turtle_tools = require("turtle_tools")

-- MAIN

local miner = Miner:new()
if miner:isBusy() then
    miner:resumePendingTasks()
else
    for _ = 1, 2 do
        miner:addTask({ fn = "travelBy",
            params = { { x = 4, y = 1, z = 0 }, "refuelOnLava", "inspectUpDown", "verifyFuelLevel", "verifyInventoryLevel" } })
        miner:addTask({ fn = "travelBy",
            params = { { x = -4, y = 1, z = 0 }, "refuelOnLava", "inspectUpDown", "verifyFuelLevel", "verifyInventoryLevel" } })
    end
    miner:addTask({ fn = "travelTo", params = { miner.home } })
    local requiredFuel, _ = miner:getTasksFuelAndPos()

    local function askForFuel(fuelLvl, m)
        local refuelLvl = fuelLvl - turtle.getFuelLevel()
        if refuelLvl > 0 then
            -- Prompt for manuel refuel
            print("Missing " .. math.ceil(refuelLvl / 80) .. " minecraft:coal for this job.")
            print("Would you like to refuel ? [y/n]")
            print("If yes then place coal then answer y")
            local answer = read()
            if answer == "n" then
                m:execTasks()
            else
                turtle_tools.refuelTo(fuelLvl)
                askForFuel(fuelLvl, m)
            end
        else
            m:execTasks()
        end
    end

    askForFuel(requiredFuel, miner)
end
