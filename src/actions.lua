local config = require "src.config"
local lib = {}

-- Action to check for blocks above and below turtle for block of interest
-- Then check for inventory and fuel level, if too low try to drop items and
-- refuel, if cannot then return home
-- function lib.inspectUpDown(miner)
--     local directionsFn = { { dig = turtle.digUp, inspect = turtle.inspectUp },
--         { dig = turtle.digDown, inspect = turtle.inspectDown } }
--     for _, direction in ipairs(directionsFn) do
--         local ok, info = direction.inspect()
--         if ok and not config.isTrash[info.name] then
--             direction.dig()
--         end
--     end
--     -- Verify if turtle is able to continue
--     if not miner:verifyInventoryLevel() or not self:verifyFuelLevel() then
--         self:travelTo(self.home)
--         os.reboot()
--     end
-- end

function lib.inspectUpDown(miner)
    local directionsFn = { { dig = turtle.digUp, inspect = turtle.inspectUp },
        { dig = turtle.digDown, inspect = turtle.inspectDown } }
    for _, direction in ipairs(directionsFn) do
        local ok, info = direction.inspect()
        if ok and not config.isTrash[info.name] then
            direction.dig()
        end
    end
end

function lib.verifyFuelLevel(miner)
    miner:travelTo(miner.home)
    os.reboot()
end

function lib.verifyInventoryLevel(miner)
    miner:travelTo(miner.home)
    os.reboot()
end

return lib
