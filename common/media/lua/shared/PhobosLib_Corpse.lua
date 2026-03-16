--  ________________________________________________________________________
-- / Copyright (c) 2026 Phobos A. D'thorga                                \
-- |                                                                        |
-- |           /\_/\                                                         |
-- |         =/ o o \=    Phobos' PZ Modding                                |
-- |          (  V  )     All rights reserved.                              |
-- |     /\  / \   / \                                                      |
-- |    /  \/   '-'   \   This source code is part of the Phobos            |
-- |   /  /  \  ^  /\  \  mod suite for Project Zomboid (Build 42).         |
-- |  (__/    \_/ \/  \__)                                                  |
-- |     |   | |  | |     Unauthorised copying, modification, or            |
-- |     |___|_|  |_|     distribution of this file is prohibited.          |
-- |                                                                        |
-- \________________________________________________________________________/
--

---------------------------------------------------------------
-- PhobosLib_Corpse.lua
-- Corpse/dead-body utilities for Project Zomboid Build 42.
---------------------------------------------------------------

PhobosLib = PhobosLib or {}


--- Get hours since a corpse died.
---@param corpse any  IsoDeadBody
---@return number  hours since death, or math.huge if unknown
function PhobosLib.getCorpseAge(corpse)
    if not corpse then return math.huge end

    local deathTime = nil
    pcall(function() deathTime = corpse:getDeathTime() end)
    if not deathTime then return math.huge end

    local worldAge = nil
    pcall(function() worldAge = GameTime:getInstance():getWorldAgeHours() end)
    if not worldAge then return math.huge end

    return worldAge - deathTime
end


--- Get all corpses (IsoDeadBody) on a given tile.
---@param square any  IsoGridSquare
---@return table  array of IsoDeadBody (empty if none)
function PhobosLib.getCorpsesOnSquare(square)
    local results = {}
    if not square then return results end

    local bodies = nil
    pcall(function() bodies = square:getDeadBodys() end)
    if not bodies then return results end

    for i = 0, bodies:size() - 1 do
        local body = bodies:get(i)
        if body then
            table.insert(results, body)
        end
    end

    return results
end


--- Get all corpses (IsoDeadBody) within a radius of a square.
--- Uses scanNearbySquares to iterate tiles, collecting corpses from each.
---@param square any      IsoGridSquare origin
---@param radius number   Search radius in tiles
---@return table  array of {corpse=IsoDeadBody, square=IsoGridSquare}
function PhobosLib.getCorpsesInRadius(square, radius)
    local results = {}
    if not square or not radius then return results end

    PhobosLib.scanNearbySquares(square, radius, function(sq)
        local corpses = PhobosLib.getCorpsesOnSquare(sq)
        for _, corpse in ipairs(corpses) do
            table.insert(results, { corpse = corpse, square = sq })
        end
        return false
    end)

    return results
end
