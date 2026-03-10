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
-- PhobosLib_FarmingSpray.lua
-- Client-side farming spray registration for custom crop cures.
--
-- B42's farming system recognises spray items entirely by
-- hardcoded type-string checks in ISFarmingMenu.doFarmingMenu2
-- and CFarming_Interact.onContextKey.  This module provides a
-- generic registration API so mods can add custom sprays that
-- cure vanilla plant diseases (Mildew, Flies, Aphids, Slugs)
-- without conflicting monkey-patches.
--
-- The monkey-patches are installed once on first registration
-- and are pcall-wrapped for resilience.
--
-- Usage:
--   require "PhobosLib"
--   PhobosLib.registerFarmingSpray(
--       "MyMod.MySulphurSpray", "Mildew")
--
-- Valid cure types: "Mildew", "Flies", "Aphids", "Slugs"
--
-- Part of PhobosLib >= 1.11.0
---------------------------------------------------------------

PhobosLib = PhobosLib or {}

local _TAG = "[PhobosLib:FarmingSpray]"

---------------------------------------------------------------
-- Registry
---------------------------------------------------------------

--- Internal registry: { {fullType=string, shortType=string, cureType=string, guard=function|nil}, ... }
PhobosLib._farmingSprayEntries = PhobosLib._farmingSprayEntries or {}

--- Whether the monkey-patches have been installed.
local _patchesInstalled = false

--- Valid cure types (matches ISCurePlantAction and SPlantGlobalObject methods).
local _validCureTypes = {
    Mildew = true,
    Flies  = true,
    Aphids = true,
    Slugs  = true,
}

--- Map cure types to their getText key for the submenu label.
local _cureTextKeys = {
    Mildew = "Farming_Mildew",
    Flies  = "Farming_Pest_Flies",
    Aphids = "Farming_Aphids",
    Slugs  = "Farming_Slugs",
}

---------------------------------------------------------------
-- Helper: find a spray item in player inventory by short type
---------------------------------------------------------------

--- Search player inventory (recursively) for a drainable item
--- with the given short type that has at least 1 use remaining.
---@param playerInv any      Player inventory (Java ItemContainer)
---@param shortType string   Item type name (without module prefix)
---@param primaryHandItem any|nil  Currently held item
---@return any|nil           The found spray item, or nil
local function findSprayInInventory(playerInv, shortType, primaryHandItem)
    -- Check primary hand first (avoids re-search if already holding it)
    if primaryHandItem
    and primaryHandItem:getType() == shortType
    and primaryHandItem:getCurrentUses() > 0 then
        return primaryHandItem
    end
    -- Predicate: item must have at least 1 use
    local function hasUses(item, count)
        return item:getCurrentUses() >= count
    end
    local found = playerInv:getFirstTypeEvalArgRecurse(shortType, hasUses, 1)
    return found
end

---------------------------------------------------------------
-- Monkey-patch: ISFarmingMenu.doFarmingMenu2
---------------------------------------------------------------

--- Wrap the vanilla doFarmingMenu2 to inject custom spray lookups
--- into the "Treat Problem" submenu.
local function patchFarmingMenu()
    if not ISFarmingMenu or not ISFarmingMenu.doFarmingMenu2 then
        print(_TAG .. " ISFarmingMenu.doFarmingMenu2 not found, skipping patch")
        return false
    end

    local _original_doFarmingMenu2 = ISFarmingMenu.doFarmingMenu2

    ISFarmingMenu.doFarmingMenu2 = function(player, context, worldobjects, test)
        -- Call the original function first (builds vanilla spray lookups + submenu)
        local result = _original_doFarmingMenu2(player, context, worldobjects, test)

        -- After vanilla finishes, inject custom sprays
        pcall(function()
            if #PhobosLib._farmingSprayEntries == 0 then return end

            -- Get the player object and their inventory
            local playerObj = getSpecificPlayer(player)
            if not playerObj then return end
            local playerInv = playerObj:getInventory()
            if not playerInv then return end
            local primaryHandItem = playerObj:getPrimaryHandItem()

            -- Find the crop square and check if there's a seeded plant
            -- We need the same sq that doFarmingMenu2 used — scan worldobjects
            local sq = nil
            local currentPlant = nil
            pcall(function()
                for i = 1, #worldobjects do
                    local obj = worldobjects[i]
                    if obj then
                        local objSq = obj:getSquare()
                        if objSq then
                            local plant = CFarmingSystem.instance:getLuaObjectOnSquare(objSq)
                            if plant and plant.state == "seeded" then
                                sq = objSq
                                currentPlant = plant
                                local shouldBreak = true
                                if shouldBreak then return end
                            end
                        end
                    end
                end
            end)

            if not sq or not currentPlant then return end
            if test then return end  -- In test mode, don't add our items

            -- Search for each registered custom spray
            local foundAny = false
            local customSprays = {}  -- { {entry=..., item=...}, ... }

            for _, entry in ipairs(PhobosLib._farmingSprayEntries) do
                -- Check guard function
                local shouldRun = true
                if entry.guard then
                    local guardOk, guardResult = pcall(entry.guard)
                    if not guardOk or guardResult ~= true then
                        shouldRun = false
                    end
                end

                if shouldRun then
                    local sprayItem = findSprayInInventory(playerInv, entry.shortType, primaryHandItem)
                    if sprayItem and sprayItem:getCurrentUses() > 0 then
                        table.insert(customSprays, { entry = entry, item = sprayItem })
                        foundAny = true
                    end
                end
            end

            if not foundAny then return end

            -- Find the crops submenu created by vanilla doFarmingMenu2.
            -- ISContextMenu stores options in self.options (1-indexed Lua table).
            -- We identify it by checking for farming-specific options.
            local cropsMenu = nil
            for _, opt in ipairs(context.options) do
                if opt.subOption then
                    local sub = context:getSubMenu(opt.subOption)
                    if sub and (
                        sub:getOptionFromName(getText("ContextMenu_Treat_Problem"))
                        or sub:getOptionFromName(getText("ContextMenu_Info"))
                        or sub:getOptionFromName(getText("ContextMenu_Water"))
                        or sub:getOptionFromName(getText("ContextMenu_Harvest"))
                        or sub:getOptionFromName(getText("ContextMenu_Remove"))
                    ) then
                        cropsMenu = sub
                        break
                    end
                end
            end

            if not cropsMenu then return end

            -- Find or create the "Treat Problem" submenu within cropsMenu
            local treatProblemText = getText("ContextMenu_Treat_Problem")
            local treatOpt = cropsMenu:getOptionFromName(treatProblemText)
            local diseaseSubMenu = nil

            if treatOpt and treatOpt.subOption then
                diseaseSubMenu = cropsMenu:getSubMenu(treatOpt.subOption)
            end

            if not diseaseSubMenu then
                treatOpt = cropsMenu:addOption(treatProblemText, worldobjects, nil)
                diseaseSubMenu = cropsMenu:getNew(cropsMenu)
                cropsMenu:addSubMenu(treatOpt, diseaseSubMenu)
            end

            -- Add each custom spray as a cure option in the submenu
            for _, sprayData in ipairs(customSprays) do
                local entry = sprayData.entry
                local sprayItem = sprayData.item

                -- Store the spray item reference on ISFarmingMenu for the cure callback
                local storageKey = "_phobosSpray_" .. entry.shortType
                ISFarmingMenu[storageKey] = sprayItem

                -- Create a closure-based cure callback
                local cureCallback = function(worldobjects2, uses, sq2, player2)
                    local theSpray = ISFarmingMenu[storageKey]
                    if not theSpray then return end
                    if not ISFarmingMenu.walkToPlant(player2, sq2) then return end
                    if not isJoypadCharacter(player2) then
                        ISWorldObjectContextMenu.equip(player2, player2:getPrimaryHandItem(), theSpray, true)
                        ISTimedActionQueue.add(ISCurePlantAction:new(
                            player2, theSpray, uses,
                            CFarmingSystem.instance:getLuaObjectOnSquare(sq2),
                            10 * (uses * 10), entry.cureType))
                    end
                end

                -- Use the item display name as the label, or fall back to cure type getText
                local label = sprayItem:getDisplayName()
                if not label or label == "" then
                    local textKey = _cureTextKeys[entry.cureType]
                    if textKey then
                        label = getText(textKey)
                    else
                        label = entry.cureType
                    end
                end

                diseaseSubMenu:addOption(label, worldobjects, cureCallback, 1, sq, playerObj)
            end
        end)

        return result
    end

    print(_TAG .. " ISFarmingMenu.doFarmingMenu2 patched")
    return true
end

---------------------------------------------------------------
-- Monkey-patch: CFarming_Interact.onContextKey
---------------------------------------------------------------

--- Wrap the vanilla onContextKey to also check for custom sprays
--- when the player presses the Interact key near a diseased plant.
local function patchFarmingInteract()
    if not CFarming_Interact or not CFarming_Interact.onContextKey then
        print(_TAG .. " CFarming_Interact.onContextKey not found, skipping patch")
        return false
    end

    local _original_onContextKey = CFarming_Interact.onContextKey

    CFarming_Interact.onContextKey = function(player, timePressedContext)
        -- Let vanilla handle its own logic first
        -- But we need to intercept BEFORE vanilla returns, if the held item
        -- is one of our custom sprays.
        --
        -- Strategy: Check if the held item matches any registered spray.
        -- If yes AND there's a seeded plant, queue the cure action.
        -- Otherwise, fall through to vanilla.

        -- Only intercept the Interact key
        if not getCore():isKey("Interact", timePressedContext) then
            return _original_onContextKey(player, timePressedContext)
        end

        local item = player:getPrimaryHandItem()
        if not item then
            return _original_onContextKey(player, timePressedContext)
        end

        -- Check if the held item is one of our registered sprays
        local matchedEntry = nil
        local itemType = item:getType()
        for _, entry in ipairs(PhobosLib._farmingSprayEntries) do
            if itemType == entry.shortType and item:getCurrentUses() > 0 then
                -- Check guard
                local shouldRun = true
                if entry.guard then
                    local guardOk, guardResult = pcall(entry.guard)
                    if not guardOk or guardResult ~= true then
                        shouldRun = false
                    end
                end
                if shouldRun then
                    matchedEntry = entry
                    local shouldBreak = true
                    if shouldBreak then break end
                end
            end
        end

        if not matchedEntry then
            -- Not one of our sprays — let vanilla handle it
            return _original_onContextKey(player, timePressedContext)
        end

        -- Check if we're near a seeded plant
        local ok, handled = pcall(function()
            local square = player:getSquare()
            if not square then return false end

            -- Check the player's current square and adjacent squares
            local checkSquares = { square }
            -- Also check facing direction
            local facingDir = player:getDir()
            if facingDir then
                local adjSq = square:getAdjacentSquare(facingDir)
                if adjSq then
                    table.insert(checkSquares, adjSq)
                end
            end

            for _, sq in ipairs(checkSquares) do
                local plant = CFarmingSystem.instance:getLuaObjectOnSquare(sq)
                if plant and plant.state == "seeded" and plant:isAlive() then
                    player:setIsFarming(true)
                    ISTimedActionQueue.add(ISCurePlantAction:new(
                        player, item, 1, plant, 100, matchedEntry.cureType))
                    return true
                end
            end
            return false
        end)

        if ok and handled then
            return
        end

        -- Didn't find a plant — let vanilla handle it
        return _original_onContextKey(player, timePressedContext)
    end

    print(_TAG .. " CFarming_Interact.onContextKey patched")
    return true
end

---------------------------------------------------------------
-- Patch installation
---------------------------------------------------------------

--- Install all monkey-patches (once).
local function installPatches()
    if _patchesInstalled then return end

    local menuOk = pcall(patchFarmingMenu)
    local interactOk = pcall(patchFarmingInteract)

    -- Only mark as installed if at least one patch succeeded
    _patchesInstalled = menuOk or interactOk

    if not menuOk then
        print(_TAG .. " WARNING: ISFarmingMenu patch failed (pcall error)")
    end
    if not interactOk then
        print(_TAG .. " WARNING: CFarming_Interact patch failed (pcall error)")
    end
end

---------------------------------------------------------------
-- Public API
---------------------------------------------------------------

--- Register a custom farming spray that cures a vanilla plant disease.
---
--- When the player right-clicks a seeded crop or uses the Interact key,
--- the registered spray will appear in the "Treat Problem" submenu and
--- trigger the corresponding plant cure action.
---
--- Valid cure types match vanilla plant diseases:
---   "Mildew"  -> plant:cureMildew()
---   "Flies"   -> plant:cureFlies()
---   "Aphids"  -> plant:cureAphids()
---   "Slugs"   -> plant:cureSlugs()
---
--- The spray must be a drainable item (ItemType = base:drainable) with
--- UseDelta and getCurrentUses() support.
---
---@param fullType  string        Full item type (e.g. "MyMod.MySulphurSpray")
---@param cureType  string        Vanilla cure type: "Mildew", "Flies", "Aphids", or "Slugs"
---@param guardFunc function|nil  Optional guard: function() -> boolean.
---                                 Spray only active when guard returns true.
function PhobosLib.registerFarmingSpray(fullType, cureType, guardFunc)
    if type(fullType) ~= "string" or fullType == "" then
        print(_TAG .. " registerFarmingSpray: invalid fullType")
        return
    end
    if not _validCureTypes[cureType] then
        print(_TAG .. " registerFarmingSpray: invalid cureType '" .. tostring(cureType)
            .. "' (must be Mildew, Flies, Aphids, or Slugs)")
        return
    end
    if guardFunc ~= nil and type(guardFunc) ~= "function" then
        print(_TAG .. " registerFarmingSpray: guardFunc must be a function or nil")
        return
    end

    -- Extract the short type (after the last dot)
    local shortType = fullType:match("%.([^%.]+)$") or fullType

    table.insert(PhobosLib._farmingSprayEntries, {
        fullType  = fullType,
        shortType = shortType,
        cureType  = cureType,
        guard     = guardFunc,
    })

    -- Install patches on first registration
    installPatches()

    print(_TAG .. " registered spray '" .. shortType .. "' -> cures " .. cureType)
end
