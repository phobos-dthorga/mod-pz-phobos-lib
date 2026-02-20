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
-- PhobosLib_Reset.lua
-- Generic inventory/recipe/skill reset utilities for PZ B42.
-- Provides mod-agnostic cleanup functions that any Phobos mod
-- can use to build tiered reset/maintenance systems.
--
-- All operations are pcall-wrapped for safety.
-- MP: Operations run on IsoGameCharacter (works for any player).
--     Caller must handle server/client context and transmitModData.
-- NPC: All methods use getInventory(), getKnownRecipes(), getXp()
--     which exist on IsoGameCharacter base class.
--
-- Part of PhobosLib -- shared by all Phobos PZ mods.
---------------------------------------------------------------

PhobosLib = PhobosLib or {}

---------------------------------------------------------------
-- Deep Inventory Iteration
---------------------------------------------------------------

--- Iterate all items in a player's inventory, including items
--- inside sub-containers (bags, backpacks, equipped containers).
--- Calls callback(item, container) for each item found.
---
--- @param player any         IsoGameCharacter
--- @param callback function  function(item, container) -> boolean|nil
---                            Return true to stop iteration early.
--- @return number            Total items visited
function PhobosLib.iterateInventoryDeep(player, callback)
    if not player or not callback then return 0 end

    local count = 0
    local visited = {}

    local function iterateContainer(container)
        if not container then return false end

        -- Guard against infinite loops
        local id = tostring(container)
        if visited[id] then return false end
        visited[id] = true

        local ok, stopped = pcall(function()
            local items = container:getItems()
            if not items then return false end

            for i = 0, items:size() - 1 do
                local item = items:get(i)
                if item then
                    count = count + 1
                    if callback(item, container) == true then
                        return true -- early exit
                    end

                    -- Recurse into sub-containers (bags, backpacks)
                    local subContainer = nil
                    pcall(function()
                        if item.getItemContainer then
                            subContainer = item:getItemContainer()
                        end
                    end)
                    if subContainer then
                        if iterateContainer(subContainer) then
                            return true
                        end
                    end
                end
            end
            return false
        end)

        if ok then return stopped end
        return false
    end

    pcall(function()
        local inv = player:getInventory()
        iterateContainer(inv)
    end)

    return count
end

---------------------------------------------------------------
-- Tier 1: Strip modData Key
---------------------------------------------------------------

--- Remove a specific modData key from all items in a player's
--- inventory, including items inside sub-containers.
---
--- @param player any     IsoGameCharacter
--- @param key string     The modData key to remove (e.g. "PCP_Purity")
--- @return number        Count of items that had the key stripped
function PhobosLib.stripModDataKey(player, key)
    if not player or not key then return 0 end

    local count = 0
    PhobosLib.iterateInventoryDeep(player, function(item)
        pcall(function()
            local md = item:getModData()
            if md and md[key] ~= nil then
                md[key] = nil
                count = count + 1
            end
        end)
    end)
    return count
end

---------------------------------------------------------------
-- Tier 2: Forget Recipes by Prefix
---------------------------------------------------------------

--- Forget all known recipes matching a prefix string.
--- Uses two-pass approach to avoid Java ConcurrentModificationException.
---
--- @param player any       IsoGameCharacter
--- @param prefix string    Recipe name prefix (e.g. "PCP")
--- @return number          Count of recipes forgotten
function PhobosLib.forgetRecipesByPrefix(player, prefix)
    if not player or not prefix then return 0 end

    local count = 0
    pcall(function()
        local known = player:getKnownRecipes()
        if not known then return end

        -- First pass: collect names to remove
        local toRemove = {}
        for i = 0, known:size() - 1 do
            local ok2, name = pcall(function() return known:get(i) end)
            if ok2 and name and type(name) == "string" then
                if string.sub(name, 1, #prefix) == prefix then
                    table.insert(toRemove, name)
                end
            end
        end

        -- Second pass: remove collected names
        for _, name in ipairs(toRemove) do
            pcall(function()
                known:remove(name)
                count = count + 1
            end)
        end
    end)
    return count
end

---------------------------------------------------------------
-- Tier 3: Reset Perk XP
---------------------------------------------------------------

--- Attempt to reset a perk's XP to 0 and level to 0.
--- Best-effort: PZ B42 may not expose a direct XP reset API.
--- Tries multiple strategies and returns true if any succeeds.
---
--- @param player any       IsoGameCharacter
--- @param perkEnum any     Perks enum value (e.g. Perks.AppliedChemistry)
--- @return boolean         true if reset appeared to succeed
function PhobosLib.resetPerkXP(player, perkEnum)
    if not player or not perkEnum then return false end

    local ok = false

    -- Strategy 1: Try player:getXp():setXP(perk, 0)
    pcall(function()
        local xpObj = player:getXp()
        if xpObj and xpObj.setXP then
            xpObj:setXP(perkEnum, 0)
            ok = true
        end
    end)

    -- Strategy 2: Set perk level to 0
    if not ok then
        pcall(function()
            if player.setPerkLevel then
                player:setPerkLevel(perkEnum, 0)
                ok = true
            end
        end)
    end

    if not ok then
        pcall(function()
            local xpObj = player:getXp()
            if xpObj and xpObj.setPerkLevel then
                xpObj:setPerkLevel(perkEnum, 0)
                ok = true
            end
        end)
    end

    -- Strategy 3: LoseLevel repeatedly until level is 0
    if not ok then
        pcall(function()
            local level = PhobosLib.getPerkLevel(player, perkEnum)
            if level > 0 and player.LoseLevel then
                for _ = 1, level do
                    player:LoseLevel(perkEnum)
                end
                ok = true
            end
        end)
    end

    return ok
end

---------------------------------------------------------------
-- Tier 4: Remove Items by Module
---------------------------------------------------------------

--- Remove all items belonging to a specific module from a player's
--- inventory, including items inside sub-containers.
---
--- @param player any         IsoGameCharacter
--- @param moduleId string    Module name (e.g. "PhobosChemistryPathways")
--- @return number            Count of items removed
function PhobosLib.removeItemsByModule(player, moduleId)
    if not player or not moduleId then return 0 end

    local toRemove = {}
    local prefix = moduleId .. "."

    PhobosLib.iterateInventoryDeep(player, function(item, container)
        local match = false

        -- Try getModule() first
        pcall(function()
            if item.getModule and item:getModule() == moduleId then
                match = true
            end
        end)

        -- Fallback: parse fullType "Module.ItemName"
        if not match then
            pcall(function()
                local ft = item:getFullType()
                if ft and string.sub(ft, 1, #prefix) == prefix then
                    match = true
                end
            end)
        end

        if match then
            table.insert(toRemove, { item = item, container = container })
        end
    end)

    -- Remove in reverse order to avoid index shifting issues
    local count = 0
    for i = #toRemove, 1, -1 do
        pcall(function()
            toRemove[i].container:Remove(toRemove[i].item)
            count = count + 1
        end)
    end
    return count
end

---------------------------------------------------------------
-- World modData Utilities
---------------------------------------------------------------

--- Read a single value from world modData with a default fallback.
--- World modData is accessed via getGameTime():getModData().
---
--- @param key string     The modData key to read
--- @param default any    Value returned if the key is missing or nil
--- @return any           The stored value or the default
function PhobosLib.getWorldModDataValue(key, default)
    local val = nil
    pcall(function()
        val = getGameTime():getModData()[key]
    end)
    if val ~= nil then return val end
    return default
end

--- Remove one or more keys from world modData.
--- Useful for cleaning up mod state after mod removal.
---
--- @param keys table    Array of string keys to remove
--- @return number       Count of keys that were actually present and removed
function PhobosLib.stripWorldModDataKeys(keys)
    if not keys or #keys == 0 then return 0 end

    local count = 0
    pcall(function()
        local md = getGameTime():getModData()
        if not md then return end
        for _, key in ipairs(keys) do
            if md[key] ~= nil then
                md[key] = nil
                count = count + 1
            end
        end
    end)
    return count
end
