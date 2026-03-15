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
-- Monkey-patches are deferred to Events.OnGameStart so that
-- ISFarmingMenu, CFarming_Interact, and all related classes
-- are guaranteed to be loaded.
--
-- Usage:
--   require "PhobosLib"
--   PhobosLib.registerFarmingSpray(
--       "MyMod.MySulphurSpray", "Mildew")
--
-- Valid cure types: "Mildew", "Flies", "Aphids", "Slugs"
--
-- Part of PhobosLib >= 1.21.0
---------------------------------------------------------------

PhobosLib = PhobosLib or {}

local _TAG = "[PhobosLib:FarmingSpray]"

---------------------------------------------------------------
-- 1. Registry & Constants
---------------------------------------------------------------

--- Internal registry: { {fullType, shortType, cureType, guard}, ... }
PhobosLib._farmingSprayEntries = PhobosLib._farmingSprayEntries or {}

--- Whether the monkey-patches have been installed.
local _patchesInstalled = false

--- Valid cure types (matches ISCurePlantAction cure strings).
local _validCureTypes = {
    Mildew = true,
    Flies  = true,
    Aphids = true,
    Slugs  = true,
}

--- Map cure types to their getText key for fallback labels.
local _cureTextKeys = {
    Mildew = "Farming_Mildew",
    Flies  = "Farming_Pest_Flies",
    Aphids = "Farming_Aphids",
    Slugs  = "Farming_Slugs",
}

--- Map cure types to the plant field that tracks disease level.
--- Used by ISFarmingCursorMouse validation to check if the
--- plant actually has this disease.
local _diseaseLvlFields = {
    Mildew = "mildewLvl",
    Flies  = "fliesLvl",
    Aphids = "aphidLvl",
    Slugs  = "slugsLvl",
}

---------------------------------------------------------------
-- 2. Helper: find spray item in player inventory
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
-- 3. Helper: find the crops submenu in the context menu
---------------------------------------------------------------

--- Find the crops submenu that vanilla doFarmingMenu2 created.
--- Vanilla names the option after the plant using
--- farming_vegetableconf.getObjectName(plant).  We match that
--- by scanning top-level context options for the plant's name.
---@param context any   ISContextMenu
---@param plantName string  The plant display name
---@return any|nil      The crops submenu, or nil
local function findCropsSubmenu(context, plantName)
    if not plantName or plantName == "" then return nil end
    for _, opt in ipairs(context.options) do
        if opt.name == plantName and opt.subOption then
            local sub = context:getSubMenu(opt.subOption)
            if sub then return sub end
        end
    end
    return nil
end

---------------------------------------------------------------
-- 4. Helper: find or create the "Treat Problem" submenu
---------------------------------------------------------------

--- Find the "Treat Problem" submenu inside the crops submenu,
--- or create it if vanilla didn't (e.g. no vanilla sprays in
--- inventory, but we have custom ones).
---@param cropsMenu any        The crops submenu
---@param context any          Top-level ISContextMenu (for getNew)
---@param worldobjects table   The worldobjects array
---@return any|nil             The "Treat Problem" submenu
local function findOrCreateTreatSubmenu(cropsMenu, context, worldobjects)
    local treatText = getText("ContextMenu_Treat_Problem")
    local treatOpt = cropsMenu:getOptionFromName(treatText)

    if treatOpt and treatOpt.subOption then
        return cropsMenu:getSubMenu(treatOpt.subOption)
    end

    -- Create it ourselves
    treatOpt = cropsMenu:addOption(treatText, worldobjects, nil)
    local diseaseSubMenu = context:getNew(cropsMenu)
    context:addSubMenu(treatOpt, diseaseSubMenu)
    return diseaseSubMenu
end

---------------------------------------------------------------
-- 5. Factory: ISFarmingCursorMouse validation function
---------------------------------------------------------------

--- Create a validation function for ISFarmingCursorMouse that
--- checks whether a plant square has the relevant disease and
--- the player still has spray uses left.
---
--- Matches vanilla pattern (e.g. ISFarmingMenu.isMildewCureValid).
---@param shortType string       Item short type
---@param diseaseLvlField string Plant field name (e.g. "mildewLvl")
---@return function              validFn(sq) -> boolean
local function createCureValidFn(shortType, diseaseLvlField)
    return function(sq)
        if not sq then return false end
        local plant = CFarmingSystem.instance:getLuaObjectOnSquare(sq)
        if not plant then return false end
        if plant.state ~= "seeded" then return false end
        -- Check if this plant actually has the disease
        local lvl = plant[diseaseLvlField]
        if not lvl or lvl <= 0 then return false end
        return true
    end
end

---------------------------------------------------------------
-- 6. Factory: ISFarmingCursorMouse square-selected callback
---------------------------------------------------------------

--- Create a square-selected callback for ISFarmingCursorMouse
--- that applies the spray to the next plant the cursor selects.
---
--- Matches vanilla pattern (e.g. ISFarmingMenu.onMildewCureSquareSelected).
---@param shortType string  Item short type
---@param cureType string   Cure type string ("Mildew", etc.)
---@return function         squareSelectedFn(sq)
local function createCureSquareSelectedFn(shortType, cureType)
    return function(sq)
        if not sq then return end
        if not ISFarmingMenu.cursor then return end

        local playerObj = ISFarmingMenu.cursor.character
        if not playerObj then return end

        local spray = ISFarmingMenu.cursor.handItem
        if not spray then return end
        if spray:getCurrentUses() <= 0 then return end

        local uses = ISFarmingMenu.cursor.uses or 1
        local plant = CFarmingSystem.instance:getLuaObjectOnSquare(sq)
        if not plant then return end

        if not ISFarmingMenu.walkToPlant(playerObj, sq) then return end

        if not isJoypadCharacter(playerObj) then
            ISWorldObjectContextMenu.equip(
                playerObj, playerObj:getPrimaryHandItem(), spray, true)
            ISTimedActionQueue.add(ISCurePlantAction:new(
                playerObj, spray, uses, plant,
                10 * (uses * 10), cureType))
        end
    end
end

---------------------------------------------------------------
-- 7. Factory: context menu cure callback
---------------------------------------------------------------

--- Create the cure callback that fires when the player selects
--- a spray option from the "Treat Problem" context menu.
---
--- Replicates the exact vanilla pattern from ISFarmingMenu.lua
--- lines 613-626 (onMildewCure), including the critical
--- ISFarmingCursorMouse setup for drag-to-next-plant.
---@param entry table           Registry entry
---@param validFn function      Cursor validation function
---@param squareSelectedFn function  Cursor square-selected callback
---@return function             cureCallback(worldobjects, uses, sq, playerObj)
local function createCureCallback(entry, validFn, squareSelectedFn)
    return function(worldobjects, uses, sq, playerObj)
        if not playerObj then return end
        if not sq then return end

        -- Re-find the spray item from inventory at execution time
        -- (the item reference from menu-build time may be stale)
        local playerInv = playerObj:getInventory()
        if not playerInv then return end
        local spray = findSprayInInventory(
            playerInv, entry.shortType, playerObj:getPrimaryHandItem())
        if not spray or spray:getCurrentUses() <= 0 then return end

        if not ISFarmingMenu.walkToPlant(playerObj, sq) then return end

        local plant = CFarmingSystem.instance:getLuaObjectOnSquare(sq)
        if not plant then return end

        if not isJoypadCharacter(playerObj) then
            ISWorldObjectContextMenu.equip(
                playerObj, playerObj:getPrimaryHandItem(), spray, true)
            ISTimedActionQueue.add(ISCurePlantAction:new(
                playerObj, spray, uses, plant,
                10 * (uses * 10), entry.cureType))
        end

        -- Set up cursor for drag-to-next-plant (vanilla lines 622-625)
        ISFarmingMenu.cursor = ISFarmingCursorMouse:new(
            playerObj, squareSelectedFn, validFn)
        getCell():setDrag(ISFarmingMenu.cursor, playerObj:getPlayerNum())
        ISFarmingMenu.cursor.handItem = spray
        ISFarmingMenu.cursor.uses = uses
    end
end

---------------------------------------------------------------
-- 8. Monkey-patch: ISFarmingMenu.doFarmingMenu2
---------------------------------------------------------------

--- Wrap the vanilla doFarmingMenu2 to inject custom spray
--- options into the "Treat Problem" submenu.
local function patchFarmingMenu()
    if not ISFarmingMenu or not ISFarmingMenu.doFarmingMenu2 then
        print(_TAG .. " ERROR: ISFarmingMenu.doFarmingMenu2 not found")
        return false
    end

    local _original_doFarmingMenu2 = ISFarmingMenu.doFarmingMenu2

    ISFarmingMenu.doFarmingMenu2 = function(player, context, worldobjects, test)
        -- Call the original function first (builds vanilla menu)
        local result = _original_doFarmingMenu2(player, context, worldobjects, test)

        -- Early exit if no custom sprays registered
        if #PhobosLib._farmingSprayEntries == 0 then
            return result
        end

        -- Wrap our injection in pcall so we never break the vanilla menu
        local injectionOk, injectionErr = pcall(function()
            -- Get the player object and their inventory
            local playerObj = getSpecificPlayer(player)
            if not playerObj then return end
            local playerInv = playerObj:getInventory()
            if not playerInv then return end
            local primaryHandItem = playerObj:getPrimaryHandItem()

            -- Find the crop square and plant (same scan vanilla uses)
            local sq = nil
            local currentPlant = nil
            for i = 1, #worldobjects do
                local obj = worldobjects[i]
                if obj then
                    local objSq = obj:getSquare()
                    if objSq then
                        local plant = CFarmingSystem.instance:getLuaObjectOnSquare(objSq)
                        if plant and plant.state == "seeded" then
                            sq = objSq
                            currentPlant = plant
                            break
                        end
                    end
                end
            end

            if not sq or not currentPlant then return end
            if test then return end

            -- Find custom sprays the player has in inventory
            local customSprays = {}
            for _, entry in ipairs(PhobosLib._farmingSprayEntries) do
                local shouldRun = true
                if entry.guard then
                    local guardOk, guardResult = pcall(entry.guard)
                    if not guardOk or guardResult ~= true then
                        shouldRun = false
                    end
                end
                if shouldRun then
                    local sprayItem = findSprayInInventory(
                        playerInv, entry.shortType, primaryHandItem)
                    if sprayItem and sprayItem:getCurrentUses() > 0 then
                        table.insert(customSprays, {
                            entry = entry, item = sprayItem })
                    end
                end
            end

            if #customSprays == 0 then return end

            -- Find the crops submenu by matching the plant's display name
            local plantName = farming_vegetableconf.getObjectName(currentPlant)
            local cropsMenu = findCropsSubmenu(context, plantName)
            if not cropsMenu then return end

            -- Find or create the "Treat Problem" submenu
            local diseaseSubMenu = findOrCreateTreatSubmenu(
                cropsMenu, context, worldobjects)
            if not diseaseSubMenu then return end

            -- Add each custom spray as a cure option
            for _, sprayData in ipairs(customSprays) do
                local entry = sprayData.entry
                local sprayItem = sprayData.item
                local diseaseLvlField = _diseaseLvlFields[entry.cureType]

                -- Create factory-generated functions for this spray
                local validFn = createCureValidFn(
                    entry.shortType, diseaseLvlField)
                local squareSelectedFn = createCureSquareSelectedFn(
                    entry.shortType, entry.cureType)
                local cureCallback = createCureCallback(
                    entry, validFn, squareSelectedFn)

                -- Use the item's display name as the label
                local label = sprayItem:getDisplayName()
                if not label or label == "" then
                    local textKey = _cureTextKeys[entry.cureType]
                    label = textKey and getText(textKey) or entry.cureType
                end

                -- Create quantity submenu (matching vanilla Aphids pattern)
                local availableUses = sprayItem:getCurrentUses()
                if availableUses > 1 then
                    local sprayOpt = diseaseSubMenu:addOption(
                        label, worldobjects, cureCallback,
                        1, sq, playerObj)
                    local quantityMenu = context:getNew(diseaseSubMenu)
                    local maxUses = math.min(availableUses, 10)
                    for i = 1, maxUses do
                        quantityMenu:addOption(
                            i .. "", worldobjects, cureCallback,
                            i, sq, playerObj)
                    end
                    context:addSubMenu(sprayOpt, quantityMenu)
                else
                    diseaseSubMenu:addOption(
                        label, worldobjects, cureCallback,
                        1, sq, playerObj)
                end
            end
        end)

        if not injectionOk then
            print(_TAG .. " WARNING: menu injection error: "
                .. tostring(injectionErr))
        end

        return result
    end

    print(_TAG .. " ISFarmingMenu.doFarmingMenu2 patched")
    return true
end

---------------------------------------------------------------
-- 9. Monkey-patch: CFarming_Interact.onContextKey
---------------------------------------------------------------

--- Wrap the vanilla onContextKey to also check for custom
--- sprays when the player presses Interact near a plant.
local function patchFarmingInteract()
    if not CFarming_Interact or not CFarming_Interact.onContextKey then
        print(_TAG .. " ERROR: CFarming_Interact.onContextKey not found")
        return false
    end

    local _original_onContextKey = CFarming_Interact.onContextKey

    CFarming_Interact.onContextKey = function(player, timePressedContext)
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
                local shouldRun = true
                if entry.guard then
                    local guardOk, guardResult = pcall(entry.guard)
                    if not guardOk or guardResult ~= true then
                        shouldRun = false
                    end
                end
                if shouldRun then
                    matchedEntry = entry
                    break
                end
            end
        end

        if not matchedEntry then
            return _original_onContextKey(player, timePressedContext)
        end

        -- Check if we're near a seeded plant with the relevant disease
        local diseaseLvlField = _diseaseLvlFields[matchedEntry.cureType]
        local handled = false

        local ok, err = pcall(function()
            local square = player:getSquare()
            if not square then return end

            -- Check player's square and the square they're facing
            local checkSquares = { square }
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
                    -- Check if plant actually has this disease
                    local lvl = plant[diseaseLvlField]
                    if lvl and lvl > 0 then
                        if not ISFarmingMenu.walkToPlant(player, sq) then
                            return
                        end
                        if not isJoypadCharacter(player) then
                            ISWorldObjectContextMenu.equip(
                                player, player:getPrimaryHandItem(),
                                item, true)
                            ISTimedActionQueue.add(ISCurePlantAction:new(
                                player, item, 1, plant,
                                100, matchedEntry.cureType))
                        end

                        -- Set up cursor for drag-to-next-plant
                        local validFn = createCureValidFn(
                            matchedEntry.shortType, diseaseLvlField)
                        local squareSelectedFn = createCureSquareSelectedFn(
                            matchedEntry.shortType, matchedEntry.cureType)
                        ISFarmingMenu.cursor = ISFarmingCursorMouse:new(
                            player, squareSelectedFn, validFn)
                        getCell():setDrag(
                            ISFarmingMenu.cursor, player:getPlayerNum())
                        ISFarmingMenu.cursor.handItem = item
                        ISFarmingMenu.cursor.uses = 1

                        handled = true
                        return
                    end
                end
            end
        end)

        if not ok then
            print(_TAG .. " WARNING: onContextKey error: " .. tostring(err))
        end

        if handled then return end

        -- Didn't find a matching plant — let vanilla handle it
        return _original_onContextKey(player, timePressedContext)
    end

    print(_TAG .. " CFarming_Interact.onContextKey patched")
    return true
end

---------------------------------------------------------------
-- 10. Deferred patch installation (Events.OnGameStart)
---------------------------------------------------------------

--- Install all monkey-patches once ISFarmingMenu and related
--- classes are guaranteed to be loaded.
local function onGameStart()
    if _patchesInstalled then return end
    if #PhobosLib._farmingSprayEntries == 0 then
        print(_TAG .. " no sprays registered, skipping patches")
        return
    end

    print(_TAG .. " installing patches (" ..
        #PhobosLib._farmingSprayEntries .. " spray(s) registered)")

    local menuOk, menuErr = pcall(patchFarmingMenu)
    local interactOk, interactErr = pcall(patchFarmingInteract)

    if menuOk then
        print(_TAG .. " ISFarmingMenu patch: OK")
    else
        print(_TAG .. " ERROR: ISFarmingMenu patch failed: "
            .. tostring(menuErr))
    end

    if interactOk then
        print(_TAG .. " CFarming_Interact patch: OK")
    else
        print(_TAG .. " ERROR: CFarming_Interact patch failed: "
            .. tostring(interactErr))
    end

    _patchesInstalled = menuOk or interactOk
end

Events.OnGameStart.Add(onGameStart)

---------------------------------------------------------------
-- 11. Public API
---------------------------------------------------------------

--- Register a custom farming spray that cures a vanilla plant
--- disease.
---
--- @deprecated v1.21.0 — Output vanilla spray items directly from
--- recipes instead.  Vanilla B42 gardening sprays are:
---   Base.GardeningSprayMilk       (Mildew)
---   Base.GardeningSprayAphids     (Aphids)
---   Base.GardeningSprayCigarettes (Flies)
---   Base.SlugRepellent            (Slugs)
--- This function still works but will be removed in a future release.
---
--- When the player right-clicks a seeded crop or uses the
--- Interact key, the registered spray will appear in the
--- "Treat Problem" submenu and trigger the corresponding plant
--- cure action, complete with drag-to-next-plant cursor.
---
--- Valid cure types match vanilla plant diseases:
---   "Mildew"  -> plant:cureMildew()
---   "Flies"   -> plant:cureFlies()
---   "Aphids"  -> plant:cureAphids()
---   "Slugs"   -> plant:cureSlugs()
---
--- The spray must be a drainable item (ItemType = base:drainable)
--- with UseDelta and getCurrentUses() support.
---
--- Registrations are collected and patches are installed once at
--- Events.OnGameStart, so this can be called at any time during
--- mod loading.
---
---@param fullType  string        Full item type (e.g. "MyMod.MySpray")
---@param cureType  string        "Mildew", "Flies", "Aphids", or "Slugs"
---@param guardFunc function|nil  Optional guard: function() -> boolean.
---                                 Spray only active when guard returns true.
local _deprecationWarned = false
function PhobosLib.registerFarmingSpray(fullType, cureType, guardFunc)
    if not _deprecationWarned then
        _deprecationWarned = true
        print(_TAG .. " WARNING: registerFarmingSpray() is deprecated (v1.21.0). "
            .. "Output vanilla spray items directly from recipes instead.")
    end
    if type(fullType) ~= "string" or fullType == "" then
        print(_TAG .. " registerFarmingSpray: invalid fullType")
        return
    end
    if not _validCureTypes[cureType] then
        print(_TAG .. " registerFarmingSpray: invalid cureType '"
            .. tostring(cureType)
            .. "' (must be Mildew, Flies, Aphids, or Slugs)")
        return
    end
    if guardFunc ~= nil and type(guardFunc) ~= "function" then
        print(_TAG .. " registerFarmingSpray: guardFunc must be a function or nil")
        return
    end

    -- Extract the short type (after the last dot)
    local shortType = fullType:match("%.([^%.]+)$") or fullType

    -- Check for duplicate registration
    for _, existing in ipairs(PhobosLib._farmingSprayEntries) do
        if existing.fullType == fullType and existing.cureType == cureType then
            print(_TAG .. " WARNING: duplicate registration ignored: "
                .. fullType .. " -> " .. cureType)
            return
        end
    end

    table.insert(PhobosLib._farmingSprayEntries, {
        fullType  = fullType,
        shortType = shortType,
        cureType  = cureType,
        guard     = guardFunc,
    })

    print(_TAG .. " registered spray '" .. shortType
        .. "' -> cures " .. cureType)
end
