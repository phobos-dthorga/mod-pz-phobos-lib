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
-- PhobosLib_Danger.lua
-- Threat/danger proximity detection for gameplay gates.
--
-- Provides a generic "is it safe here?" check that detects
-- nearby zombies, active fires, and player combat state.
-- Used to gate actions like intel gathering, crafting in labs,
-- and specimen collection that require relative safety.
---------------------------------------------------------------

local DEFAULT_RADIUS = 15

--- Check if there is immediate danger near the player.
---
--- Detects:
--- - Live zombies within radius (via cell zombie list, distance check)
--- - Player currently in combat (isInCombat if available)
--- - Active fire on nearby squares (grid scan within radius)
---
--- Performance: zombie list iteration is O(n) where n = all zombies
--- in the loaded cell. For typical gameplay, this is fast enough
--- for per-action checks (not per-tick). The fire scan is bounded
--- by radius² grid squares.
---
--- @param player any IsoPlayer
--- @param radius number|nil Detection radius in tiles (default 15)
--- @return boolean True if danger is detected
function PhobosLib.isDangerNearby(player, radius)
    if not player then return false end
    radius = radius or DEFAULT_RADIUS
    local radiusSq = radius * radius

    local px = player:getX()
    local py = player:getY()
    local pz = player:getZ()

    -- Check 1: Player in active combat
    if player.isInCombat then
        local ok, inCombat = pcall(function() return player:isInCombat() end)
        if ok and inCombat then return true end
    end

    -- Check 2: Zombies within radius
    local cell = getCell and getCell()
    if cell then
        local ok, zombieList = pcall(function() return cell:getZombieList() end)
        if ok and zombieList then
            for i = 0, zombieList:size() - 1 do
                local z = zombieList:get(i)
                if z then
                    local alive = false
                    pcall(function() alive = z:isAlive() end)
                    if alive then
                        local dx = z:getX() - px
                        local dy = z:getY() - py
                        if (dx * dx + dy * dy) <= radiusSq then
                            return true
                        end
                    end
                end
            end
        end
    end

    -- Check 3: Fire on nearby squares (bounded grid scan)
    -- Only scan a smaller radius for fire (performance)
    local fireRadius = math.min(radius, 10)
    if cell then
        for dx = -fireRadius, fireRadius do
            for dy = -fireRadius, fireRadius do
                if (dx * dx + dy * dy) <= (fireRadius * fireRadius) then
                    local checkSq = nil
                    pcall(function()
                        checkSq = cell:getGridSquare(px + dx, py + dy, pz)
                    end)
                    if checkSq then
                        local hasFire = false
                        pcall(function()
                            local fires = checkSq:getModData()
                            -- PZ B42: check for fire objects on the square
                            local objs = checkSq:getObjects()
                            if objs then
                                for j = 0, objs:size() - 1 do
                                    if instanceof(objs:get(j), "IsoFire") then
                                        hasFire = true
                                    end
                                end
                            end
                        end)
                        if hasFire then return true end
                    end
                end
            end
        end
    end

    return false
end
