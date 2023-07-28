local config = require "config"
local turtle_tools = require "turtle_tools"
local gps_tools = require "gps_tools"

local lib = {}

-- Actions are function that can be executed by the miner after a move
-- Do not use turtle movement here, instead use turtle.move or add task to move
-- the miner accordingly

-- Inspect for bloc of interest above and under turtle, if interesting, mine it
function lib.inspectUpDown()
    local directionsFn = { { dig = turtle.digUp, inspect = turtle.inspectUp },
        { dig = turtle.digDown, inspect = turtle.inspectDown } }
    for _, direction in ipairs(directionsFn) do
        local ok, info = direction.inspect()
        if ok then
            if info.name == "minecraft:bedrock" then
                miner.travelTo(miner.home)
            elseif not config.isTrash[info.name] then
                direction.dig()
            end
        end
    end
end

-- Verify fuel level between current miner position and its home
-- If too low, go back home
function lib.verifyFuelLevel(miner)
    local consumption = gps_tools.getFuelBetweenPositions(miner.home, miner.position)
    local fuelLeft = turtle.getFuelLevel() - consumption
    if fuelLeft < config.FUEL_THRESHOLD then
        if not turtle_tools.refuelTo(consumption) then
            miner:travelTo(miner.home)
            os.reboot()
        end
    end
end

--  Verify inventory level, if no room for new blocs, return home
function lib.verifyInventoryLevel(miner)
    if not turtle_tools.verifyInventoryLevel() then
        miner:travelTo(miner.home)
        os.reboot()
    end
end

-- Ensure turtle collects lava as it moves
function lib.refuelOnLava()
    turtle_tools.collectLavaAndRefuel()
end

-- Find nearby chest, if not up or down, align to get it in front of the turtle
-- ready to drop()
-- return the direction where the found chest is compare to the turtle
function lib.alignAndGetChestDirection(miner)
    local positions = { "top", "bottom", "left", "right", "front" }
    local foundPos
    for _, position in pairs(positions) do
        local periph = peripheral.wrap(position)
        if periph then
            foundPos = position
            break
        end
    end
    if foundPos == "top" then
        return "up"
    elseif foundPos == "bottom" then
        return "down"
    elseif foundPos == "front" then
        return "forward"
    elseif foundPos == "left" then
        miner:turn("left")
        return "forward"
    elseif foundPos == "right" then
        miner:turn("right")
        return "forward"
    elseif foundPos == "back" then
        miner:turn("left"), miner:turn("left")
        return "forward"
    end
end

-- Return miner to home position and drop its inventory to nearby chest
function lib.returnHomeAndDrop(miner)
    miner:travelTo(miner.home)
    turtle_tools.emptyTurtleAndUpdateInv(
        nil, { "minecraft:bucket" }, lib.alignAndGetChestDirection()
    )
end

return lib
