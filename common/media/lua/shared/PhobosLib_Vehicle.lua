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
-- PhobosLib_Vehicle.lua
-- Vehicle utilities for Project Zomboid Build 42.
---------------------------------------------------------------

PhobosLib = PhobosLib or {}


--- Find all vehicles within radius tiles of a player.
--- Uses the getCell():getVehicles() approach.
---@param player any
---@param radius number
---@return table  array of BaseVehicle (empty if none)
function PhobosLib.findAllNearbyVehicles(player, radius)
    local results = {}
    if not player then return results end
    local sq = PhobosLib.getSquareFromPlayer(player)
    if not sq then return results end

    local ok, px = pcall(function() return sq:getX() end)
    local ok2, py = pcall(function() return sq:getY() end)
    if not (ok and ok2) then return results end

    local cell = getCell()
    if not cell then return results end

    local vehicles = nil
    pcall(function() vehicles = cell:getVehicles() end)
    if not vehicles then return results end

    local radiusSq = radius * radius

    for i = 0, vehicles:size() - 1 do
        local v = vehicles:get(i)
        if v then
            local vok, vx = pcall(function() return v:getX() end)
            local vok2, vy = pcall(function() return v:getY() end)
            if vok and vok2 then
                local dx = vx - px
                local dy = vy - py
                if (dx * dx + dy * dy) <= radiusSq then
                    table.insert(results, v)
                end
            end
        end
    end

    return results
end
