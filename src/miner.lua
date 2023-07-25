local gps_tools    = require("gps_tools")
local turtle_tools = require("turtle_tools")
local actions      = require("actions")

-- Unserialize tasks and turtle position to a variable
-- See also Miner:saveState
local function loadState()
    local file = io.open("state.txt", "r")
    local state
    if file then
        state = textutils.unserialize(file:read())
        file:close()
        -- Sort unserialized tasks table
        local indexes = {}
        for key, value in pairs(state.tasks) do
            table.insert(indexes, key)
        end
        table.sort(indexes)
        local sorted = {}
        for k, value in pairs(indexes) do
            table.insert(sorted, state.tasks[value])
        end
        state.tasks = sorted
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

-- Remove all pending tasks
function Miner:removeAllTasks()
    self.tasks = {}
end

-- Execute all tasks and update task list
function Miner:execTasks()
    for key, task in pairs(self.tasks) do
        -- In case tasks become empty due to some actions
        if self:getTasksLength() == 0 then break end
        self.jobStartingPos = {
            x = self.position.x,
            y = self.position.y,
            z = self.position.z,
            d = self.position.d
        }
        -- call function on Miner by its name and give it params
        self[task.fn](self, table.unpack(task.params))
        -- Once task is complete, set it to nil
        self.tasks[key] = nil
        self:saveState()
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

-- Return number of tasks for current miner.
-- This function was created because we dynamically remove element during
-- execution, perturbing indexes of the table
-- TODO improve ?
function Miner:getTasksLength()
    local cpt = 0
    for k, v in pairs(self.tasks) do
        cpt = cpt + 1
    end
    return cpt
end

-- Return true if Miner has at least one pending task
function Miner:isBusy()
    return next(self.tasks) ~= nil
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
        file:write(textutils.serialize(state, { compact = true }))
        file:close()
    end
end

-- if Miner has unfinished tasks, execute them and update if necessary the
-- interrupted task
function Miner:resumePendingTasks()
    if self:isBusy() then
        local firstTask
        for k, value in pairs(self.tasks) do
            firstTask = value
            break
        end
        if firstTask.fn == "travelBy" then
            -- Only update the first task which was interrupted
            -- For travelBy task, update the position with current position
            local pos = firstTask.params[1]
            firstTask.params[1] = gps_tools.addPosition(pos, self.jobStartingPos)
            firstTask.fn = "travelTo"
        end
        self:execTasks()
    end
end

function Miner:move(axis, distance, ...)
    if distance == 0 then return true end
    local posUpdate, movement, miningDir
    local dirs = {
        x = {
            pos = { name = "N", movement = turtle.forward, mine = "forward" },
            neg = { name = "S", movement = turtle.forward, mine = "forward" }
        },
        y = {
            pos = { name = "E", movement = turtle.forward, mine = "forward" },
            neg = { name = "W", movement = turtle.forward, mine = "forward" }
        },
        z = {
            pos = { name = "U", movement = turtle.up, mine = "up" },
            neg = { name = "D", movement = turtle.down, mine = "down" }
        }
    }
    if distance > 0 then
        self:setDirection(dirs[axis].pos.name)
        movement = dirs[axis].pos.movement
        posUpdate = -1
        miningDir = dirs[axis].pos.mine
    elseif distance < 0 then
        self:setDirection(dirs[axis].neg.name)
        movement = dirs[axis].neg.movement
        posUpdate = 1
        miningDir = dirs[axis].neg.mine
    end
    while distance ~= 0 do
        if self.force then
            turtle_tools.mine(miningDir)
        end
        if movement() then
            distance = distance + posUpdate
            local currentPos = self.position[axis]
            self.position[axis] = currentPos - posUpdate
            self:saveState()
            self:doActions(...)
        end
    end
    return distance
end

-- Travel by given positions and stand in given direction
-- First travel on X then Y, then Z and finally set direction
-- position {x = int, y = int, z = int, d = "N"}
-- direction is a coordinal direction between N, S, E, W
-- return true if travel was ok, else return false
function Miner:travelBy(position, ...)
    local ok, _ = self:move("x", position.x, ...)
    if ok then
        ok, _ = self:move("y", position.y, ...)
        if ok then
            ok, _ = self:move("z", position.z, ...)
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

-- Experimental feature
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

-- execute additionnal action functions passed in varargs by their name (string)
function Miner:doActions(...)
    local varargs = { ... }
    for _, action in pairs(varargs) do
        actions[action](self)
    end
end

-- Turn the turtle left or right
-- Keep track of the turtle direction accordingly
function Miner:turn(side)
    local ind = gps_tools.directionIndex[self.position.d]
    local action
    if side == "left" then
        -- ok, _ = turtle.turnLeft()
        action = turtle.turnLeft
        ind = ind - 1
    else
        action = turtle.turnRight
        ind = ind + 1
    end
    if ind == 0 then
        self.position.d = "W"
    elseif ind == 5 then
        self.position.d = "N"
    else
        self.position.d = gps_tools.directions[ind]
    end
    self:saveState()
    -- Turn last because it take time and turtle could most likely be
    -- interrupted during that time
    local ok, _ = action()
    return ok
end

-- Turn the turtle to face a specific direction in space
-- Position can be N, S, E or W
function Miner:setDirection(direction)
    if not direction then return true end
    local currentDirIndex = gps_tools.directionIndex[self.position.d]
    local targetDirIndex = gps_tools.directionIndex[direction]
    if not targetDirIndex then return true end
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
    -- self.position.d = direction
    return true
end

return Miner
