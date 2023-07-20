local gps_tools    = require("src.gps_tools")
local turtle_tools = require("src.turtle_tools")
local conf         = require("src.config")
local actions      = require("src.actions")
local config       = require("config")

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
    obj.home = gps_tools.getHome()
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
            local cons = gps_tools.getFuelBetweenPositions(task.params[1], futurPos)
            requiredFuel = requiredFuel + cons
            futurPos = task.params[1]
        elseif task.fn == "travelBy" then
            requiredFuel = requiredFuel + gps_tools.getFuelForPosition(task.params[1])
            futurPos = gps_tools.addPosition(futurPos, task.params[1])
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
            self.tasks[1].params[1] = gps_tools.getRelativeDistance(pos, self.position)
        end
        self:execTasks()
    end
end

-- Check if miner has enough fuel to go to home position. Refuel if necessary
function Miner:verifyFuelLevel()
    local consumption = gps_tools.getFuelBetweenPositions(self.home, self.position)
    local fuelLeft = turtle.getFuelLevel() - consumption
    if fuelLeft < config.FUEL_THRESHOLD then
        if not turtle_tools.refuelTo(consumption) then
            return false
        end
    end
    return true
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
    local relativePos = gps_tools.getRelativeDistance(position, self.position)
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

function Miner:move(axis, distance, ...)
    if distance == 0 then return true end
    local posUpdate
    local movement
    local dirs = {
        X = {
            pos = { name = "N", movement = turtle.forward },
            neg = { name = "S", movement = turtle.forward }
        },
        Y = {
            pos = { name = "E", movement = turtle.forward },
            neg = { name = "W", movement = turtle.forward }
        },
        Z = {
            pos = { name = "U", movement = turtle.up },
            neg = { name = "D", movement = turtle.down }
        }
    }
    if distance > 0 then
        self:setDirection(dirs[axis].pos)
        movement = dirs[axis].pos.movement
        posUpdate = -1
    elseif distance < 0 then
        self:setDirection(dirs[axis].neg)
        movement = dirs[axis].neg.movement
        posUpdate = 1
    end
    while distance ~= 0 do
        if self.force then
            turtle_tools.mine(direction) -- TODO
        end
        if movement() then
            distance = distance + posUpdate
            local currentPos = self.position[dirs[axis].name]
            currentPos = currentPos - posUpdate
            self:saveState()
            -- execute additionnal functions passed in varargs
            local varargs = { ... }
            for _, action in pairs(varargs) do
                actions[action]()
            end
        end
    end
    return distance
end

-- TODO factorize
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
                actions[action]()
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
    local currentDirIndex = gps_tools.directionIndex[self.position.d]
    local targetDirIndex = gps_tools.directionIndex[direction]
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
        turtle_tools.mine()
    end
    local ok, _ = turtle.forward()
    if ok then
        self:updateXYPosition()
    end
    -- execute additionnal functions passed in varargs
    local varargs = { ... }
    for _, action in pairs(varargs) do
        actions[action]()
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

return Miner
