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
        if ok and not config.isTrash[info.name] then
            direction.dig()
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

function lib.refuelOnLava()
    if turtle_tools.collectLava() then
        print(turtle.getFuelLevel())
        turtle.refuel()
        print("lava", turtle.getFuelLevel())
    end
end

return lib
