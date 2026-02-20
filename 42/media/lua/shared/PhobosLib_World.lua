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
-- PhobosLib_World.lua
-- World-scanning utilities: square iteration, object detection,
-- vehicle/generator finders for Project Zomboid Build 42.
---------------------------------------------------------------

PhobosLib = PhobosLib or {}


--- Safely get the IsoGridSquare a player is standing on.
---@param player any
---@return any|nil  IsoGridSquare or nil
function PhobosLib.getSquareFromPlayer(player)
    if not player or not player.getSquare then return nil end
    local ok, sq = pcall(function() return player:getSquare() end)
    if ok then return sq end
    return nil
end


--- Iterate all grid squares within a radius of an origin square.
--- Calls callback(square) for each valid square found.
--- The callback can return true to stop iteration early.
---@param originSquare any      IsoGridSquare to search around
---@param radius number         Search radius in tiles
---@param callback function     function(square) -> boolean|nil
---@return boolean              true if callback ever returned true
function PhobosLib.scanNearbySquares(originSquare, radius, callback)
    if not originSquare or not callback then return false end
    local ok, cx = pcall(function() return originSquare:getX() end)
    local ok2, cy = pcall(function() return originSquare:getY() end)
    local ok3, cz = pcall(function() return originSquare:getZ() end)
    if not (ok and ok2 and ok3) then return false end

    local cell = getCell()
    if not cell then return false end

    for dx = -radius, radius do
        for dy = -radius, radius do
            local nsq = cell:getGridSquare(cx + dx, cy + dy, cz)
            if nsq then
                local stop = callback(nsq)
                if stop == true then return true end
            end
        end
    end
    return false
end


--- Find the first IsoObject on nearby squares whose name or sprite
--- matches one of the given keywords (case-insensitive substring).
---@param originSquare any
---@param radius number
---@param keywords table    List of keyword strings
---@return any|nil          The matching IsoObject, or nil
function PhobosLib.findNearbyObjectByKeywords(originSquare, radius, keywords)
    if not keywords or #keywords == 0 then return nil end
    local found = nil

    PhobosLib.scanNearbySquares(originSquare, radius, function(sq)
        local objs = sq:getObjects()
        if not objs then return false end
        for i = 0, objs:size() - 1 do
            local obj = objs:get(i)
            if obj then
                local spriteName = ""
                local objName = ""
                pcall(function()
                    local sprite = obj:getSprite()
                    if sprite and sprite.getName then spriteName = sprite:getName() or "" end
                end)
                pcall(function()
                    if obj.getName then objName = obj:getName() or "" end
                end)
                local s = PhobosLib.lower(spriteName)
                local n = PhobosLib.lower(objName)
                for _, kw in ipairs(keywords) do
                    local k = PhobosLib.lower(kw)
                    if k ~= "" and (string.find(s, k, 1, true) or string.find(n, k, 1, true)) then
                        found = obj
                        return true  -- stop scanning
                    end
                end
            end
        end
        return false
    end)

    return found
end


--- Find ALL IsoObjects on nearby squares matching keywords.
---@param originSquare any
---@param radius number
---@param keywords table
---@return table
function PhobosLib.findAllNearbyObjectsByKeywords(originSquare, radius, keywords)
    local results = {}
    if not keywords or #keywords == 0 then return results end

    PhobosLib.scanNearbySquares(originSquare, radius, function(sq)
        local objs = sq:getObjects()
        if not objs then return false end
        for i = 0, objs:size() - 1 do
            local obj = objs:get(i)
            if obj then
                local spriteName = ""
                local objName = ""
                pcall(function()
                    local sprite = obj:getSprite()
                    if sprite and sprite.getName then spriteName = sprite:getName() or "" end
                end)
                pcall(function()
                    if obj.getName then objName = obj:getName() or "" end
                end)
                local s = PhobosLib.lower(spriteName)
                local n = PhobosLib.lower(objName)
                for _, kw in ipairs(keywords) do
                    local k = PhobosLib.lower(kw)
                    if k ~= "" and (string.find(s, k, 1, true) or string.find(n, k, 1, true)) then
                        table.insert(results, obj)
                        break  -- don't add same object twice
                    end
                end
            end
        end
        return false
    end)

    return results
end


--- Boolean convenience: is the player within radius of an object matching keywords?
---@param player any
---@param radius number
---@param keywords table
---@return boolean
function PhobosLib.isNearObjectType(player, radius, keywords)
    local sq = PhobosLib.getSquareFromPlayer(player)
    if not sq then return false end
    return PhobosLib.findNearbyObjectByKeywords(sq, radius, keywords) ~= nil
end


--- Find an active IsoGenerator near a square.
--- "Active" means fuel > 0 and activated (running).
---@param square any        IsoGridSquare to search around
---@param radius number     Search radius in tiles
---@return any|nil          The IsoGenerator object, or nil
function PhobosLib.findNearbyGenerator(square, radius)
    if not square then return nil end
    local found = nil

    PhobosLib.scanNearbySquares(square, radius, function(sq)
        local gen = nil
        pcall(function() gen = sq:getGenerator() end)
        if gen then
            local activated = false
            local hasFuel = false
            pcall(function() activated = gen:isActivated() end)
            pcall(function() hasFuel = (gen:getFuel() > 0) end)
            if activated and hasFuel then
                found = gen
                return true  -- stop scanning
            end
        end
        return false
    end)

    return found
end


--- Find any IsoGenerator near a square (regardless of whether it's running).
---@param square any
---@param radius number
---@return any|nil
function PhobosLib.findAnyNearbyGenerator(square, radius)
    if not square then return nil end
    local found = nil

    PhobosLib.scanNearbySquares(square, radius, function(sq)
        local gen = nil
        pcall(function() gen = sq:getGenerator() end)
        if gen then
            found = gen
            return true
        end
        return false
    end)

    return found
end


--- Find the nearest vehicle within radius tiles of a player.
--- Uses the getCell():getVehicles() approach.
---@param player any
---@param radius number
---@return any|nil  The BaseVehicle, or nil
function PhobosLib.findNearbyVehicle(player, radius)
    if not player then return nil end
    local sq = PhobosLib.getSquareFromPlayer(player)
    if not sq then return nil end

    local ok, px = pcall(function() return sq:getX() end)
    local ok2, py = pcall(function() return sq:getY() end)
    if not (ok and ok2) then return nil end

    -- Try to get vehicles from the cell
    local cell = getCell()
    if not cell then return nil end

    local vehicles = nil
    pcall(function() vehicles = cell:getVehicles() end)
    if not vehicles then return nil end

    local bestDist = radius * radius + 1
    local bestVehicle = nil

    for i = 0, vehicles:size() - 1 do
        local v = vehicles:get(i)
        if v then
            local vok, vx = pcall(function() return v:getX() end)
            local vok2, vy = pcall(function() return v:getY() end)
            if vok and vok2 then
                local dx = vx - px
                local dy = vy - py
                local distSq = dx * dx + dy * dy
                if distSq < bestDist then
                    bestDist = distSq
                    bestVehicle = v
                end
            end
        end
    end

    if bestDist <= radius * radius then
        return bestVehicle
    end
    return nil
end


--- Safe check whether a vehicle's engine is currently running.
--- Probes multiple possible method names.
---@param vehicle any
---@return boolean
function PhobosLib.isVehicleRunning(vehicle)
    if not vehicle then return false end

    -- Try direct boolean methods
    local probes = {"isEngineRunning", "getEngineRunning", "isRunning"}
    for _, m in ipairs(probes) do
        local ok, v = PhobosLib.pcallMethod(vehicle, m)
        if ok and v == true then return true end
    end

    -- Try engine speed > 0 as a fallback heuristic
    local ok, speed = PhobosLib.pcallMethod(vehicle, "getEngineSpeed")
    if ok and type(speed) == "number" and speed > 0 then return true end

    return false
end
