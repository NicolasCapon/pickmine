local config = require("config")
local lib = {}
local actions = {
    dig = {
        up = turtle.digUp,
        down = turtle.digDown,
        forward = turtle.dig
    },
    inspect = {
        up = turtle.inspectUp,
        down = turtle.inspectDown,
        forward = turtle.inspect
    },
    drop = {
        up = turtle.dropUp,
        down = turtle.dropDown,
        forward = turtle.drop
    },
    place = {
        up = turtle.placeUp,
        down = turtle.placeDown,
        forward = turtle.place
    }
}


-- A collection of usefull functions for handling turtles

-- Get item detail of all inventory slots group by item + list all empty slot
-- If no inventory name provided, scan own turtle inventory.
-- ex: { "empty" = {1, 5, 16},
--       "items" = { "minecraft:iron": {{pos=2, count=12, left=52},
--                                      {pos=3, count=15, left=48}}}
--     }
function lib.scanInventory(name)
    local inventory, inventory_size, limit
    if name then
        inventory = peripheral.find(name)
        -- TODO handle error if no inventory found
        inventory_size = inventory.size()
        limit = inventory.getItemLimit
    else
        inventory = turtle
        inventory_size = 16
        limit = turtle.getItemSpace
    end
    local fns = {}
    local scan = { empty = {}, items = {}, name = name }
    for i = 1, inventory_size do
        local fn = function()
            local item = inventory.getItemDetail(i)
            if item then
                if not scan.items[item.name] then
                    scan.items[item.name] = {}
                end
                table.insert(scan.items[item.name],
                    {
                        pos = i,
                        count = item.count,
                        left = limit(i)
                    }
                )
            else
                table.insert(scan.empty, i)
            end
        end
        table.insert(fns, fn)
    end
    parallel.waitForAll(table.unpack(fns))
    return scan
end

-- Group turtle slots by item
function lib.stackInventory(inventory)
    inventory = inventory or lib.scanInventory()
    -- For each type of item (ex: iron)
    for _, info in pairs(inventory.items) do
        -- For each slot containing this type of item
        for i = 1, #info do
            -- Test if this slot is empty
            -- (because we update the list dynamically)
            if info[i] then
                local n = 1
                -- While room in slot and another slot contains this item
                while info[i] and info[i].left > 0 and info[n + 1] do
                    turtle.select(info[n + 1].pos)
                    if info[n + 1].count <= info[i].left then
                        -- if there is enough item, transfer whole n+1 slot
                        if turtle.transferTo(info[i].pos, info[n + 1].count) then
                            -- Update inventory values
                            info[i].count = info[i].count + info[n + 1].count
                            info[i].left = info[i].left - info[n + 1].count
                            inventory.empty = info[n + 1].pos
                            info[n + 1] = nil
                        end
                    else
                        -- else transfert only a part of n+1 slot
                        if turtle.transferTo(info[i].pos, info[i].left) then
                            -- Update inventory values
                            info[i].count = info[i].count + info[i].left
                            info[i].left = 0
                            info[n + 1].count = info[n + 1].count - info[i].left
                            info[n + 1].left = info[n + 1].left + info[i].left
                        end
                    end
                    n = n + 1
                end
            end
        end
    end
    return inventory
end

-- Group inventory slots by item (Stack on left)
-- Return updated inventory
function lib.stackRemoteInventory(inventory)
    for _, slots in pairs(inventory.items) do
        for i = 1, #slots do
            if slots[i] then
                local n = 1
                -- While room in slot i and a next slot contains this item
                while slots[i] and slots[i].left > 0 and slots[n + 1] do
                    -- try to push all next slot to current
                    local t = inventory.pushItems(inventory.name,
                        n + 1,
                        nil,
                        i)
                    -- t is the number of item actually transfered
                    -- update inventory values
                    slots[i].count = slots[i].count + t
                    slots[i].left = slots[i].left - t
                    slots[n + 1].count = slots[n + 1].count - t
                    inventory.empty = slots[n + 1].pos
                    if slots[n+1].count = 0 then
                        -- if whole next slot was transferred, move it to empty
                        inventory.empty = slots[n + 1].pos
                        slots[n + 1] = nil
                    else
                        -- else only update the left value
                        slots[n + 1].left = slots[n + 1].left + t
                    end
                end
            end
        end
    end
    return inventory
end

-- Drop all turtle inventory to nearby inventory
-- turtleInv is the result of a scanInventory()
-- ignore is a list of item names to ignore
-- direction is the direction of the nearby chest { up, down, forward }
function lib.emptyTurtleAndUpdateInv(turtleInv, ignore, direction)
    turtleInv = turtleInv or lib.scanInventory()
    local action = actions.drop[direction] or turtle.drop
    local isExcluded = {}
    for _, itemName in pairs(ignore) do
        isExcluded[itemName] = true
    end
    for itemName, turtleSlots in pairs(turtleInv) do
        if not isExcluded[itemName] then
            for _, slot in pairs(turtleSlots) do
                turtle.select(slot.pos)
                local ok, msg = pcall(action)
                if ok and msg then
                    -- Update turtle inventory if transfer was ok
                    table.insert(turtleInv.empty, slot.pos)
                    slot = nil
                    if #turtleInv[itemName] == 0 then
                        turtleInv[itemName] = nil
                    end
                end
            end
        end
    end
    return turtleInv
end

-- Return true if turtle inventory contains at least one free slot
function lib.isInventorySlotsFull()
    local status = true
    local fns = {}
    for i = 1, 16 do
        local fn = function()
            if status and turtle.getItemCount(i) == 0 then
                status = false
            end
        end
        table.insert(fns, fn)
    end
    parallel.waitForAll(table.unpack(fns))
    return status
end

-- Return the minimum number of coal to have given level of fuel
function lib.getCoalNumForFuelLevel(fuel)
    return math.ceil(fuel / 80)
end

-- Refuel the turtle to given lvl at minimum (default is math.huge), using fuel
-- source from items in inventory. see config.authorizedFuelSource
-- Return tuple ok, fuelLevel
function lib.refuelTo(lvl)
    lvl = lvl or turtle.getFuelLimit()
    if lvl == "unlimited" then lvl = math.huge end
    local currentLvl = turtle.getFuelLevel()
    if currentLvl >= lvl then return true, currentLvl end
    local inventory = lib.scanInventory()
    local ok = false
    for _, item in ipairs(config.authorizedFuelSource) do
        local it = inventory.items[item]
        if it then
            lib.getCoalNumForFuelLevel(lvl - currentLvl)
            turtle.select(it[1].pos)
            ok = turtle.refuel(it[1].count)
            if ok then currentLvl = turtle.getFuelLevel() end
            if currentLvl >= lvl then
                break
            end
        end
    end
    return ok, currentLvl
end

-- Search item by name in turtle inventory
function lib.searchInventory(item)
    local inventory = lib.scanInventory()
    return inventory.items[item]
end

-- Mine block in front of the turtle.
-- Take gravel/sand piles into account
-- direction must be nil or string with value forward, up or down
function lib.mine(direction)
    direction = direction or "forward"
    local _, block = actions.inspect[direction]()
    local ok
    if config.isFallingEntity[block.name] then
        while config.isFallingEntity[block.name] do
            ok = actions.dig[direction]()
            if ok then
                _, block = actions.inspect[direction]()
            end
        end
    else
        ok = actions.dig[direction]()
    end
    return ok
end

-- Verify inventory level and try to compact it, if still full, drop garbage
-- and if no garbage was dropped then return false
function lib.verifyInventoryLevel()
    if lib.isInventorySlotsFull() then
        lib.dropGarbage("down")
        lib.stackInventory()
        if lib.isInventorySlotsFull() then
            return false
        end
    end
    return true
end

-- Drop all items in dict isTrash from turtle inventory
-- If at least one slot was drop, return true
-- Note: cannot use parallel since select and drop are not executed at the
-- same time
function lib.dropGarbage(direction)
    local action = actions.drop[direction] or turtle.drop
    local atLeastOne = false
    for i = 1, 16 do
        local slot = turtle.getItemDetail(i)
        if slot then
            if config.isTrash[slot.name] then
                turtle.select(i)
                action()
                atLeastOne = true
            end
        end
    end
    return atLeastOne
end

-- Select turtle slot by item name, if item exists in turtle inventory, select
-- first found slot
-- Return true if selected, nil or false otherwise
function lib.selectItemByName(name)
    local bucket = lib.searchInventory(name)
    if bucket then
        return turtle.select(bucket[1].pos)
    end
end

-- Inspect given directions (up, down and or forward) for lava, if found collect
-- it to empty bucket.
-- Warning, turtle need one bucket per lava source otherwise, lava source are
-- not collected
-- direction is a list of string directions ex: { "up", "down"}
-- Return true if lava was successfully collected, nil or false otherwise
function lib.collectLava(directions)
    directions = directions or { "forward", "up", "down" }
    local ok = false
    for _, direction in pairs(directions) do
        local has_block, block = actions.inspect[direction]()
        if has_block and block.name == "minecraft:lava" then
            if lib.selectItemByName("minecraft:bucket") then
                ok, _ = actions.place[direction]()
            end
        end
    end
    return ok
end

-- Inspect given directions (up, down and or forward) for lava, if found collect
-- it and refuel.
-- directions is a list of string directions ex: {"up", "down"}
-- return true if at least one refuel was successfull
function lib.collectLavaAndRefuel(directions)
    directions = directions or { "forward", "up", "down" }
    local status = false
    if lib.selectItemByName("minecraft:bucket") then
        for _, direction in pairs(directions) do
            local has_block, block = actions.inspect[direction]()
            if has_block and block.name == "minecraft:lava" then
                local ok, _ = actions.place[direction]()
                if ok then
                    status = turtle.refuel()
                end
            end
        end
    end
    return status
end

return lib
