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


--- Safe wrapper for vehicle battery charge.
---@param vehicle any  BaseVehicle
---@return number  charge 0.0-1.0, or 0 on error
function PhobosLib.getVehicleBatteryCharge(vehicle)
    if not vehicle then return 0 end
    local ok, charge = pcall(function() return vehicle:getBatteryCharge() end)
    if ok and type(charge) == "number" then return charge end
    return 0
end


--- Drain vehicle battery safely (positive amount = drain).
---@param vehicle any  BaseVehicle
---@param amount number  positive value to drain
function PhobosLib.drainVehicleBattery(vehicle, amount)
    if not vehicle or not amount or amount <= 0 then return end
    pcall(function() VehicleUtils.chargeBattery(vehicle, -amount) end)
end


--- Runtime check that a vehicle template part exists on loaded vehicle scripts.
--- Call at OnGameBoot to detect template override conflicts.
---@param partId string  e.g. "PIPLabFridge"
---@param modPrefix string  e.g. "PIP" (for log messages)
---@return boolean  true if part found on at least one vehicle script
function PhobosLib.verifyVehicleTemplatePart(partId, modPrefix)
    local prefix = modPrefix or "PhobosLib"
    local scriptManager = getScriptManager()
    if not scriptManager then
        print("[" .. prefix .. "] WARNING: getScriptManager() returned nil, cannot verify part '" .. partId .. "'")
        return false
    end

    local allScripts = scriptManager:getAllVehicleScripts()
    if not allScripts or allScripts:size() == 0 then
        print("[" .. prefix .. "] WARNING: No vehicle scripts loaded, cannot verify part '" .. partId .. "'")
        return false
    end

    -- Check a few non-trailer vehicles for the part
    for i = 0, math.min(allScripts:size() - 1, 9) do
        local script = allScripts:get(i)
        if script then
            local name = script:getName() or ""
            if not string.match(string.lower(name), "trailer") then
                local part = script:getPartById(partId)
                if part then
                    print("[" .. prefix .. "] Vehicle part '" .. partId .. "' detected. OK.")
                    return true
                end
            end
        end
    end

    print("[" .. prefix .. "] WARNING: Part '" .. partId .. "' not found on any vehicle script. "
        .. "Another mod may override 'template vehicle Battery'. Check mod load order.")
    return false
end


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
