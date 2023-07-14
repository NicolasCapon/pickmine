local FUEL_THRESHOLD = 10
local avoid = { "minecraft:water", "minecraft:lava", "minecraft:dirt", "minecraft:grass_block", "minecraft:stone", "minecraft:cobblestone", "minecraft:diorite", "twigs:pebble", "minecraft:granite", "minecraft:gravel", "minecraft:sand", "byg:soapstone", "minecraft:flint", "upgrade_aquatic:embedded_ammonite", "minecraft:torch", "minecraft:deepslate", "minecraft:cobbled_deepslate", "twigs:rhyolite", "forbidden_arcanus:darkstone", "tetra:geode", "silentgear:bort", "minecraft:tuff"}
local garbage = avoid
local fallingEntities = { "minecraft:sand", "minecraft:gravel" }
local isFallingEntity = {}
for _, v in ipairs(fallingEntities) do
    isFallingEntity[v] = true
end
local home = { x = 0, y = 0, z = 0, d = "N" }
local filler = 1 -- slot with cobble to fill holes
local directions = { "N", "E", "S", "W" }
local authorizedFuelSource = { "minecraft:coal" }
local directionIndex = {}
for k, v in ipairs(directions) do
    directionIndex[v] = k
end
local isFuel = {}
for k, v in ipairs(authorizedFuelSource) do
    isFuel[v] = true
end

-- TODO:
-- handle fuel level:
--   - create function to get fuel from turtle inventory
--   - Handle fuel before travelling
--   - Fuel accordingly to travel distance ? 1 coal = 64 movement ?
-- create function mineRectangle or move over rectangle and take action for each movement

local isTrash = {}
for _, g in ipairs(garbage) do
    isTrash[g] = true
end

local miner = {}
miner.fuel = turtle.getFuelLevel()
miner.position = { x = 0, y = 0, z = 0, d = "N" }
miner.storagePosDir = { x = 0, y = 0, z = 0, d = "S" }

function miner.inspectUpDown()
    local directionsFn = { { dig = turtle.digUp, inspect = turtle.inspectUp },
        { dig = turtle.digDown, inspect = turtle.inspectDown } }
    for _, direction in ipairs(directionsFn) do
        local ok, info = direction.inspect()
        if ok and not isTrash[info.name] then
            direction.dig()
        end
    end
    -- Verify if turtle is able to continue
    if not miner.verifyInventoryLevel() or not miner.verifyFuelLevel() then
        miner.travelTo(home)
        os.reboot()
    end
end

function miner.verifyFuelLevel()
    if turtle.getFuelLevel() - math.abs(miner.position.x) + math.abs(miner.position.y) + math.abs(miner.position.z) < FUEL_THRESHOLD then
        if not miner.refuel() then
            return false
        end
    end
    return true
end

-- Refuel the turtle if able
-- Return tuple ok, fuelLevel
function miner.refuel()
    local inventory = miner.scanInventory()
    local ok = false
    for _, item in ipairs(authorizedFuelSource) do
        local it = inventory.items[item]
        if it then
            turtle.select(it[1].pos)
            ok = turtle.refuel(it[1].count)
            break
        end
    end
    return ok, turtle.getFuelLevel()
end

function miner.searchInventory(item)
    local inventory = miner.scanInventory()
    return inventory.items[item]
end

function miner.mineRectangle(x, y)
    local startPos = miner.getPosition()
    if x > y then
        local position = { x = x, y = 1, z = 0, d = "N" }
        miner.travelBy(position)
        local forth = { x = (position.x - 1) * -1, y = 1, z = 0, d = "E" }
        local back = { x = position.x - 1, y = 1, z = 0, d = "E" }
        for _ = 1, y do
            miner.travelBy(forth)
            miner.travelBy(back)
        end
    else
        local position = { x = 1, y = y - 1, z = 0, d = "N" }
        miner.travelBy(position)
        local forth = { x = 1, y = (position.y - 1) * -1, z = 0, d = "N" }
        local back = { x = 1, y = position.y - 1, z = 0, d = "N" }
        for _ = 1, x do
            miner.travelBy(forth)
            miner.travelBy(back)
        end
    end
    miner.travelTo(startPos)
    miner.refuel()
end

-- Travel by given positions and stand in given direction
-- position {x = int, y = int, z = int, d = "N"}
-- direction is a coordinal direction between N, S, E, W
-- return true if travel was ok, else return false
function miner.travelBy(position, force, action)
    local ok, _ = miner.moveX(position.x, force, action)
    if ok then
        ok, _ = miner.moveY(position.y, force, action)
        if ok then
            ok, _ = miner.moveZ(position.z, force, action)
            if ok then
                return miner.setDirection(position.d)
            end
        end
    end
end

-- Move turtle to an absolute spatial position
-- position {x = int, y = int, z = int, direction = str}
-- direction is a coordinal direction between N, S, E, W
-- return true if travel was ok, else return false
function miner.travelTo(position, force, action)
    local map = {}
    map.x = position.x - miner.position.x
    map.y = position.y - miner.position.y
    map.z = position.z - miner.position.z
    map.d = position.d
    return miner.travelBy(map, force, action)
end

-- startPos = { x = 1, y = 1 }
-- map = { { ">", ">", ">", ">", "v"},
--         { "<", "v", "<", "<", "<"},
--         { "^", ">", ">", ">", "v"},
--         { "^", "<", "<", "<", "<"} }
function miner.followMap(map, startPos)
    local index = startPos
    local dict = {}
    dict["^"] = "N"
    dict["v"] = "S"
    dict[">"] = "E"
    dict["<"] = "W"
    repeat
        local direction = dict[map[index.x][index.y]]
        if not direction then break end
        miner.setDirection(direction)
        miner.goForward()
        if direction == "N" then
            index.y = index.y - 1
        elseif direction == "S" then
            index.y = index.y + 1
        elseif direction == "E" then
            index.x = index.x + 1
        elseif direction == "W" then
            index.x = index.x - 1
        end
    until index.x > #map[y] or index.x == 0 or index.y > #map or index.y == 0
end

-- Move on X axis by given distance
function miner.moveX(distance, force, action)
    if distance == 0 then return true end
    local posUpdate
    if distance > 0 then
        miner.setDirection("N")
        posUpdate = -1
    elseif distance < 0 then
        miner.setDirection("S")
        posUpdate = 1
    end
    repeat
        if miner.goForward(force, action) then
            distance = distance + posUpdate
        else
            return distance
        end
    until distance == 0
    return distance
end

-- Move on Y axis by given distance
function miner.moveY(distance, force, action)
    if distance == 0 then return true end
    local posUpdate
    if distance > 0 then
        miner.setDirection("E")
        posUpdate = -1
    elseif distance < 0 then
        miner.setDirection("W")
        posUpdate = 1
    end
    repeat
        if miner.goForward(force, action) then
            distance = distance + posUpdate
        else
            return distance
        end
    until distance == 0
    return distance
end

-- Move on Z axis by given distance
function miner.moveZ(distance, force, action)
    if distance == 0 then return true end
    local posUpdate, movement, dig
    if distance > 0 then
        movement = turtle.up
        dig = turtle.digUp
        posUpdate = - 1
    elseif distance < 0 then
        movement = turtle.down
        dig = turtle.digDown
        posUpdate = 1
    end
    repeat
        dig()
        if movement() then
            distance = distance + posUpdate
            miner.position.z = miner.position.z - posUpdate
            if action then action() end
        end
    until distance == 0
    return distance
end

-- Turn the turtle left or right
-- Keep track of the turtle direction accordingly
function miner.turn(side)
    local ind = directionIndex[miner.position.d]
    local ok
    if side == "left" then
        ok, _ = turtle.turnLeft()
        if ok then
            ind = ind - 1
        end
    else
        ok, _ = turtle.turnRight()
        if ok then
            ind = ind + 1
        end
    end
    if ind == 0 then
        miner.position.d = "W"
    elseif ind == 5 then
        miner.position.d = "N"
    else
        miner.position.d = directions[ind]
    end
    return ok
end

-- Turn the turtle to face a specific direction in space
-- Position can be N, S, E or W
function miner.setDirection(direction)
    if not direction then return true end
    local currentDirIndex = directionIndex[miner.position.d]
    local targetDirIndex = directionIndex[direction]
    local turnNum = targetDirIndex - currentDirIndex
    if math.abs(turnNum) == 3 then
        turnNum = math.floor(turnNum / -3)
    end
    repeat
        if turnNum < 0 then
            local ok, _ = miner.turn("left")
            if ok then
                turnNum = turnNum + 1
            else
                return ok
            end
        elseif turnNum > 0 then
            local ok, _ = miner.turn("right")
            if ok then
                turnNum = turnNum - 1
            else
                return ok
            end
        end
    until turnNum == 0
    miner.position.d = direction
    return true
    -- index = currentDirIndex + (turnNum)
    -- print("turnNum", turnNum)
    -- if index == 5 then
    --     index = 1
    -- elseif index == 0 then
    --     index = 4
    -- end
    -- print("index", index)
    -- miner.position.d = directions[index]
end

function miner.getFuelToStorage()
    return miner.position.x + miner.position.y + miner.position.z
end

-- Move turtle forward
-- force (boolean) if the turtle need to dig before moving
-- action (fn) fonction to call after turtle has moved
-- Return true if turtle successfully moved forward, else return false
function miner.goForward(force, action)
    if force then
        local ok = miner.mine()
    end
    local ok, _ = turtle.forward()
    if ok then
        miner.fuel = miner.fuel - 1
        miner.updatePosition()
    end
    if action then action() end
    return ok
end

-- Mine block in front of the turtle.
-- Take gravel/sand piles into account
function miner.mine()
    local has_block, block = turtle.inspect()
    local ok
    if isFallingEntity[block.name] then
        while isFallingEntity[block.name] do
            ok = turtle.dig()
            if ok then
                has_block, block = turtle.inspect()
            end
        end
    else
        ok = turtle.dig()
    end
    return ok
end

function miner.updatePosition()
    if miner.position.d == "N" then
        miner.position.x = miner.position.x + 1
    elseif miner.position.d == "S" then
        miner.position.x = miner.position.x - 1
    elseif miner.position.d == "E" then
        miner.position.y = miner.position.y + 1
    elseif miner.position.d == "W" then
        miner.position.y = miner.position.y - 1
    end
end

local function isMinable()
    local has_block, data = turtle.inspect()
    if has_block and not avoid[data.name] then
        return true
    end
end

local function mine()
    if isMinable() then
        local ok, _ = turtle.dig()
        if ok then
            turtle.forward()
        end
    end
end

local function move()
    miner.inspectUpDown()
    turtle.dig()
    turtle.forward()
    local ok, info = turtle.inspect()
    if ok and avoid[info.name] then
        return true
    end
end

local function run()
    local n = 0
    while true do
        local turn = move()
        if turn then
            turtle.turnRight()
            move()
            turtle.turnRight()
            move()
        end
    end
end

local function row(size)
    local n = 0
    repeat
        local turn = move()
        coord.y = coord.y + 1
        n = n + 1
    until n == size or turn
    turtle.turnRight()
    move()
    coord.x = coord.x + 1
    turtle.turnRight()
    repeat
        move()
        coord.y = coord.y - 1
        n = n - 1
    until n == 0
end

local function fill()
    turtle.select(filler)
    local ok, err = turtle.place()
    return ok
end

-- Get item detail of all turtle slots group by item and list of all empty slot
-- ex: { "empty" = {1, 5, 16},
--       "items" = { "minecraft:iron": {{pos=2, count=12, left=52},
--                          {pos=3, count=15, left=48}}}
--     }
function miner.scanInventory()
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
function miner.stackInventory(inventory)
    inventory = inventory or miner.scanInventory()
    -- For each type of item (ex: iron)
    for name, info in pairs(inventory.items) do
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
function miner.isInventorySlotsFull()
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

-- Verify inventory level and try to compact it, if still full, drop garbage
-- and if no garbage was dropped then return false
function miner.verifyInventoryLevel()
    if miner.isInventorySlotsFull() then
        miner.dropGarbage()
        miner.stackInventory()
        if miner.isInventorySlotsFull() then
            return false
        end
    end
    return true
end

-- Drop all items in dict isTrash from turtle inventory
-- If at least one slot was drop, return true
function miner.dropGarbage()
    atLeastOne = false
    local fns = {}
    for i = 1, 16 do
        local slot = turtle.getItemDetail(i)
        if slot then
            if isTrash[slot.name] then
                turtle.select(i)
                turtle.drop()
                atLeastOne = true
            end
        end
    end
    return atLeastOne
end

-- Faire un tunnel de 1 block:
-- inspect creuse inspects creuse...
-- si trou on rebouche et on dig a droite ou a gauche, sinon demi tour
-- return miner
local ok, data = turtle.inspectDown()
print("fuel: ", turtle.getFuelLevel())
miner.refuel()
for i=1,16 do
    miner.travelBy({x=32, y=1, z=0}, true, miner.inspectUpDown)
    miner.travelBy({x=-32, y=1, z=0, d="N"}, true, miner.inspectUpDown)
end
miner.travelTo(home)
-- miner.dropGarbage()
