local FUEL_THRESHOLD = 10
local garbage = { "minecraft:water", "minecraft:lava", "minecraft:dirt", "minecraft:grass_block", "minecraft:stone",
    "minecraft:cobblestone", "minecraft:diorite", "twigs:pebble", "minecraft:granite", "minecraft:gravel",
    "minecraft:sand", "byg:soapstone", "minecraft:flint", "upgrade_aquatic:embedded_ammonite", "minecraft:torch",
    "minecraft:deepslate", "minecraft:cobbled_deepslate", "twigs:rhyolite", "forbidden_arcanus:darkstone", "tetra:geode",
    "silentgear:bort", "minecraft:tuff" }
local fallingEntities = { "minecraft:sand", "minecraft:gravel" }
local authorizedFuelSource = { "minecraft:coal" }

-- Unserialize tasks and turtle position to a variable
-- See also Miner:saveState
local function loadState()
    local file = io.open("state.txt", "r")
    local state
    if file then
        state = file:read(textutils.serialize(state))
        file:close()
    end
    return state
end

-- Compute the relative distance between two positions
local function getRelativeDistance(targetPos, currentPos)
    local pos = {}
    pos.x = targetPos.x - currentPos.x
    pos.y = targetPos.y - currentPos.y
    pos.z = targetPos.z - currentPos.z
    pos.d = targetPos.d
    return pos
end

-- Get fuel consumption to go from origin to given position
local function getFuelForPosition(pos)
    return math.abs(pos.x or 0) + math.abs(pos.y or 0) + math.abs(pos.z or 0)
end

-- Get fuel level to travel from current position to given position.
-- If no position was given, take home position as default
local function getFuelBetweenPositions(targetPos, currentPos)
    return getFuelForPosition(getRelativeDistance(targetPos, currentPos))
end

-- add a position to given position (sum of 2 positions)
local function addPosition(pos, addedPos)
    local sum = {}
    sum.x = pos.x + (addedPos.x or 0)
    sum.y = pos.y + (addedPos.y or 0)
    sum.z = pos.z + (addedPos.z or 0)
    sum.d = addedPos.d or pos.d
    return sum
end

-- Return the minimum number of coal to have given level of fuel
local function getCoalNumForFuelLevel(fuel)
    return math.ceil(fuel / 80)
end

local Miner = {}
Miner.__index = Miner

-- Miner constructor, can take a table as params
function Miner:new()
    local obj = {}
    setmetatable(obj, Miner)
    -- Load previous miner state from file if exist, otherwise load defaults
    local state = loadState()
    if state then
        obj.position = state.position or { x = 0, y = 0, z = 0, d = "N" }
        obj.force = state.force or true
        obj.tasks = state.tasks or {}
        obj.jobStartingPos = state.jobStartingPos or {}
    else
        obj.position = { x = 0, y = 0, z = 0, d = "N" }
        obj.force = true
        obj.tasks = {}
        obj.jobStartingPos = {}
    end
    obj.fuel = turtle.getFuelLevel()
    obj.home = { x = 0, y = 0, z = 0, d = "N" } -- Constant
    -- Constant loading
    -- Falling entities
    obj.isFallingEntity = {}
    for _, v in ipairs(fallingEntities) do
        obj.isFallingEntity[v] = true
    end
    -- fuel entities
    obj.isFuel = {}
    for _, v in ipairs(authorizedFuelSource) do
        obj.isFuel[v] = true
    end
    -- trash
    obj.isTrash = {}
    for _, g in ipairs(garbage) do
        obj.isTrash[g] = true
    end
    -- cardinal directions
    obj.directions = { "N", "E", "S", "W" }
    obj.directionIndex = {}
    for k, v in ipairs(obj.directions) do
        obj.directionIndex[v] = k
    end
    return obj
end

-- Add task ({fn: "travelBy", params: { {x = 0, y = 1}, "action" } }) to
-- task list
function Miner:addTask(task)
    table.insert(self.tasks, task)
end

-- Execute all tasks and update task list
function Miner:execTasks()
    for key, task in pairs(self.tasks) do
        self.jobStartingPos = {
            x = self.position.x,
            y = self.position.y,
            z = self.position.z,
            d = self.position.d
        }
        -- call function on Miner by its name and give it params
        self[task.fn](table.unpack(task.params))
        -- Once task is complete, set it to nil
        self.tasks[key] = nil
    end
end

-- compute the fuel needed to execute all tasks and the final position of miner
function Miner:getTasksFuelAndPos()
    local futurPos = { x = 0, y = 0, z = 0, d = 0 }
    local requiredFuel = 0
    for _, task in ipairs(self.tasks) do
        if task.fn == "travelTo" then
            local cons = getFuelBetweenPositions(task.params[1], futurPos)
            requiredFuel = requiredFuel + cons
            futurPos = task.params[1]
        elseif task.fn == "travelBy" then
            requiredFuel = requiredFuel + getFuelForPosition(task.params[1])
            futurPos = addPosition(futurPos, task.params[1])
        end
    end
    return requiredFuel, futurPos
end

-- Return true if Miner has at least one pending task
function Miner:isBusy()
    return #self.tasks > 0
end

-- Serialize tasks and turtle position to a file
function Miner:saveState()
    local file = io.open("state.txt", "w")
    if file then
        local state = {
            position = self.position,
            tasks = self.tasks,
            force = self.force,
            jobStartingPos = self.jobStartingPos
        }
        file:write(textutils.serialize(state))
        file:close()
    end
end

-- if Miner has unfinished tasks, execute them and update if necessary the
-- interrupted task
function Miner:resumePendingTasks()
    if self:isBusy() then
        if self.tasks[1].fn == "travelBy" then
            -- Only update the first task which was interrupted
            -- For travelBy task, update the position with current position
            local pos = self.tasks[1].params[1]
            self.tasks[1].params[1] = getRelativeDistance(pos, self.position)
        end
        self:execTasks()
    end
end

-- Check if miner has enough fuel to go to home position. Refuel if necessary
function Miner:verifyFuelLevel()
    local consumption = getFuelBetweenPositions(self.home, self.position)
    local fuelLeft = turtle.getFuelLevel() - consumption
    if fuelLeft < FUEL_THRESHOLD then
        if not self:refuelTo(consumption) then
            return false
        end
    end
    return true
end

-- Refuel the turtle to given lvl at minimum (default is math.huge)
-- Return tuple ok, fuelLevel
function Miner:refuelTo(lvl)
    lvl = lvl or math.huge
    local currentLvl = turtle.getFuelLevel()
    if currentLvl >= lvl then return true, currentLvl end
    local inventory = self:scanInventory()
    local ok = false
    for _, item in ipairs(authorizedFuelSource) do
        local it = inventory.items[item]
        if it then
            getCoalNumForFuelLevel(lvl - currentLvl)
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
function Miner:searchInventory(item)
    local inventory = self:scanInventory()
    return inventory.items[item]
end

-- Travel by given positions and stand in given direction
-- First travel on X then Y, then Z and finally set direction
-- position {x = int, y = int, z = int, d = "N"}
-- direction is a coordinal direction between N, S, E, W
-- return true if travel was ok, else return false
function Miner:travelBy(position, ...)
    local ok, _ = self:moveX(position.x, ...)
    if ok then
        ok, _ = self:moveY(position.y, ...)
        if ok then
            ok, _ = self:moveZ(position.z, ...)
            if ok then
                return self:setDirection(position.d)
            end
        end
    end
end

-- Move turtle to an absolute spatial position
-- position {x = int, y = int, z = int, direction = str}
-- direction is a coordinal direction between N, S, E, W
-- return true if travel was ok, else return false
function Miner:travelTo(position, ...)
    local relativePos = getRelativeDistance(position, self.position)
    return self:travelBy(relativePos, ...)
end

-- startPos = { x = 1, y = 1 }
-- map = { { ">", ">", ">", ">", "v"},
--         { "<", "v", "<", "<", "<"},
--         { "^", ">", ">", ">", "v"},
--         { "^", "<", "<", "<", "<"} }
function Miner:followMap(map, startPos)
    local index = startPos
    local dict = {}
    dict["^"] = "N"
    dict["v"] = "S"
    dict[">"] = "E"
    dict["<"] = "W"
    repeat
        local direction = dict[map[index.x][index.y]]
        if not direction then break end
        self:setDirection(direction)
        self:goForward()
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
function Miner:moveX(distance, ...)
    if distance == 0 then return true end
    local posUpdate
    if distance > 0 then
        self:setDirection("N")
        posUpdate = -1
    elseif distance < 0 then
        self:setDirection("S")
        posUpdate = 1
    end
    repeat
        if self:goForward(...) then
            distance = distance + posUpdate
        else
            return distance
        end
    until distance == 0
    return distance
end

-- Move on Y axis by given distance
function Miner:moveY(distance, ...)
    if distance == 0 then return true end
    local posUpdate
    if distance > 0 then
        self:setDirection("E")
        posUpdate = -1
    elseif distance < 0 then
        self:setDirection("W")
        posUpdate = 1
    end
    repeat
        if self:goForward(...) then
            distance = distance + posUpdate
        else
            return distance
        end
    until distance == 0
    return distance
end

-- Move on Z axis by given distance
function Miner:moveZ(distance, ...)
    if distance == 0 then return true end
    local posUpdate, movement, direction
    if distance > 0 then
        movement = turtle.up
        direction = "up"
        posUpdate = -1
    elseif distance < 0 then
        movement = turtle.down
        direction = "down"
        posUpdate = 1
    end
    while distance > 0 do
        self:mine(direction)
        if movement() then
            distance = distance + posUpdate
            self.position.z = self.position.z - posUpdate
            self:saveState()
            -- execute additionnal functions passed in varargs
            local varargs = { ... }
            for _, action in pairs(varargs) do
                action()
            end
        end
    end
    return distance
end

-- Turn the turtle left or right
-- Keep track of the turtle direction accordingly
function Miner:turn(side)
    local ind = self.directionIndex[self.position.d]
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
        self.position.d = "W"
    elseif ind == 5 then
        self.position.d = "N"
    else
        self.position.d = self.directions[ind]
    end
    return ok
end

-- Turn the turtle to face a specific direction in space
-- Position can be N, S, E or W
function Miner:setDirection(direction)
    if not direction then return true end
    local currentDirIndex = self.directionIndex[self.position.d]
    local targetDirIndex = self.directionIndex[direction]
    local turnNum = targetDirIndex - currentDirIndex
    if math.abs(turnNum) == 3 then
        turnNum = math.floor(turnNum / -3)
    end
    repeat
        if turnNum < 0 then
            local ok, _ = self:turn("left")
            if ok then
                turnNum = turnNum + 1
            else
                return ok
            end
        elseif turnNum > 0 then
            local ok, _ = self:turn("right")
            if ok then
                turnNum = turnNum - 1
            else
                return ok
            end
        end
    until turnNum == 0
    self.position.d = direction
    self:saveState()
    return true
end

-- Move turtle forward
-- force (boolean) if the turtle need to dig before moving
-- ... (list of fn) fonctions to call after turtle has moved
-- Return true if turtle successfully moved forward, else return false
function Miner:goForward(...)
    if self.force then
        self:mine()
    end
    local ok, _ = turtle.forward()
    if ok then
        self.fuel = self.fuel - 1
        self:updateXYPosition()
    end
    -- execute additionnal functions passed in varargs
    local varargs = { ... }
    for _, action in pairs(varargs) do
        action()
    end
    return ok
end

-- Mine block in front of the turtle.
-- Take gravel/sand piles into account
function Miner:mine(direction)
    direction = direction or "forward"
    local actions = {
        up = { inspect = turtle.inpectUp, dig = turtle.digUp },
        down = { inspect = turtle.inspectDown, dig = turtle.digDown },
        forward = { inspect = turtle.inspect, dig = turtle.dig }
    }
    local _, block = actions[direction].inspect()
    local ok
    if self.isFallingEntity[block.name] then
        while self.isFallingEntity[block.name] do
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

-- Update miner position according to current direction after a turtle.forward
function Miner:updateXYPosition()
    if self.position.d == "N" then
        self.position.x = self.position.x + 1
    elseif self.position.d == "S" then
        self.position.x = self.position.x - 1
    elseif self.position.d == "E" then
        self.position.y = self.position.y + 1
    elseif self.position.d == "W" then
        self.position.y = self.position.y - 1
    end
    self:saveState()
end

-- Get item detail of all turtle slots group by item and list of all empty slot
-- ex: { "empty" = {1, 5, 16},
--       "items" = { "minecraft:iron": {{pos=2, count=12, left=52},
--                          {pos=3, count=15, left=48}}}
--     }
function Miner:scanInventory()
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
function Miner:stackInventory(inventory)
    inventory = inventory or self:scanInventory()
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
function Miner:isInventorySlotsFull()
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
function Miner:verifyInventoryLevel()
    if self:isInventorySlotsFull() then
        self:dropGarbage()
        self:stackInventory()
        if self:isInventorySlotsFull() then
            return false
        end
    end
    return true
end

-- Drop all items in dict isTrash from turtle inventory
-- If at least one slot was drop, return true
-- Note: cannot use parallel since select and drop are not executed at the
-- same time
function Miner:dropGarbage()
    local atLeastOne = false
    for i = 1, 16 do
        local slot = turtle.getItemDetail(i)
        if slot then
            if self.isTrash[slot.name] then
                turtle.select(i)
                turtle.drop()
                atLeastOne = true
            end
        end
    end
    return atLeastOne
end

-- Action to check for blocks above and below turtle for block of interest
-- Then check for inventory and fuel level, if too low try to drop items and
-- refuel, if cannot then return home
function Miner:inspectUpDown()
    local directionsFn = { { dig = turtle.digUp, inspect = turtle.inspectUp },
        { dig = turtle.digDown, inspect = turtle.inspectDown } }
    for _, direction in ipairs(directionsFn) do
        local ok, info = direction.inspect()
        if ok and not self.isTrash[info.name] then
            direction.dig()
        end
    end
    -- Verify if turtle is able to continue
    if not self:verifyInventoryLevel() or not self:verifyFuelLevel() then
        self:travelTo(self.home)
        os.reboot()
    end
end

-- MAIN
local miner = Miner:new()
for _ = 1, 16 do
    miner:addTask({ fn = "travelBy", params = { { x = 32, y = 1, z = 0 }, miner.inspectUpDown } })
    miner:addTask({ fn = "travelBy", params = { { x = -32, y = 1, z = 0 }, miner.inspectUpDown } })
end
miner:addTask({ fn = "travelTo", params = { miner.home } })
local requiredFuel, _ = miner:getTasksFuelAndPos()

local function askForFuel(fuelLvl, m)
    local refuelLvl = fuelLvl - turtle.getFuelLevel()
    if refuelLvl > 0 then
        -- Prompt for manuel refuel
        print("Missing " .. getCoalNumForFuelLevel(refuelLvl) .. " minecraft:coal for this job.")
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
