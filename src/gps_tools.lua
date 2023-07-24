local lib = {}

-- Set of function to handle coordinates in a 3D space

-- cardinal directions
lib.directions = { "N", "E", "S", "W" }
lib.directionIndex = {}
for k, v in ipairs(lib.directions) do
    lib.directionIndex[v] = k
end

-- Return origin
function lib.getHome()
    return { x = 0, y = 0, z = 0, d = "N" }
end

-- Compute the relative distance between two positions
function lib.getRelativeDistance(targetPos, currentPos)
    local pos = {}
    pos.x = targetPos.x - currentPos.x
    pos.y = targetPos.y - currentPos.y
    pos.z = targetPos.z - currentPos.z
    pos.d = targetPos.d
    return pos
end

-- Get fuel consumption to go from origin to given position
function lib.getFuelForPosition(pos)
    return math.abs(pos.x or 0) + math.abs(pos.y or 0) + math.abs(pos.z or 0)
end

-- Get fuel level to travel from current position to given position.
-- If no position was given, take home position as default
function lib.getFuelBetweenPositions(targetPos, currentPos)
    return lib.getFuelForPosition(lib.getRelativeDistance(targetPos, currentPos))
end

-- add a position to given position (sum of 2 positions)
function lib.addPosition(pos, addedPos)
    local sum = {}
    sum.x = pos.x + (addedPos.x or 0)
    sum.y = pos.y + (addedPos.y or 0)
    sum.z = pos.z + (addedPos.z or 0)
    sum.d = addedPos.d or pos.d
    return sum
end

return lib
