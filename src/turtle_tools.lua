local config = require("config")
local lib = {}

-- A collection of usefull functions for handling turtles

-- Get item detail of all turtle slots group by item and list of all empty slot
-- ex: { "empty" = {1, 5, 16},
--       "items" = { "minecraft:iron": {{pos=2, count=12, left=52},
--                          {pos=3, count=15, left=48}}}
--     }
function lib.scanInventory()
    local inventory = { empty = {}, items = {} }
    local fns = {}
    for i = 1, 16 do
        local fn = function()
            local slot = turtle.getItemDetail(i)
            if slot then
                if not inventory.items[slot.name] then
                    inventory.items[slot.name] = {}
                end
                table.insert(inventory.items[slot.name], {
                    pos = i,
                    count = slot.count,
                    left = turtle.getItemSpace(i)
                })
            else
                table.insert(inventory.empty, i)
            end
        end
        table.insert(fns, fn)
    end
    parallel.waitForAll(table.unpack(fns))
    return inventory
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
    lvl = lvl or math.huge
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
    local actions = {
        up = { inspect = turtle.inpectUp, dig = turtle.digUp },
        down = { inspect = turtle.inspectDown, dig = turtle.digDown },
        forward = { inspect = turtle.inspect, dig = turtle.dig }
    }
    local _, block = actions[direction].inspect()
    local ok
    if config.isFallingEntity[block.name] then
        while config.isFallingEntity[block.name] do
            ok = actions[direction].dig()
            if ok then
                _, block = actions[direction].inspect()
            end
        end
    else
        ok = actions[direction].dig()
    end
    return ok
end

-- Verify inventory level and try to compact it, if still full, drop garbage
-- and if no garbage was dropped then return false
function lib.verifyInventoryLevel()
    if lib.isInventorySlotsFull() then
        lib.dropGarbage()
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
function lib.dropGarbage()
    local atLeastOne = false
    for i = 1, 16 do
        local slot = turtle.getItemDetail(i)
        if slot then
            if config.isTrash[slot.name] then
                turtle.select(i)
                turtle.drop()
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

-- Scan up, down and forward for lava, if found then try to select a bucket and
-- collect lava
-- Return true if lava was successfully collected, nil or false otherwise
function lib.collectLava()
    local ok = false
    local directions = {
        up = { inspect = turtle.inspectUp, place = turtle.placeUp },
        down = { inspect = turtle.inspectDown, place = turtle.placeDown },
        forward = { inspect = turtle.inspect, place = turtle.place }
    }
    for _, action in pairs(directions) do
        local has_block, block = action.inspect()
        if has_block and block.name == "minecraft:lava" then
            if lib.selectItemByName("minecraft:bucket") then
                ok, _ = action.place()
            end
        end
    end
    return ok
end

return lib
