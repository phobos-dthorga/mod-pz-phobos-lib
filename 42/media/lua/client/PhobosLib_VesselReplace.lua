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

---------------------------------------------------------------
-- PhobosLib_VesselReplace.lua
-- Client-side empty FluidContainer lifecycle management.
--
-- Two complementary systems for handling emptied FluidContainers:
--
-- 1. CONDITION RESET (Part of PhobosLib >= 1.15.0)
--    Mods that repurpose item condition as a metadata channel
--    (e.g. purity) can register a condition reset so that empty
--    FluidContainers revert to ConditionMax.  This removes the
--    "(Worn)" suffix from items whose condition was modified as
--    a metadata channel and were then drained.
--
-- 2. VESSEL REPLACEMENT (Part of PhobosLib >= 1.10.0)
--    Mods that define custom FluidContainer items can register
--    mappings so empty containers revert to their base vanilla
--    vessel.  Mappings can be either:
--      string  -> simple replacement  ("Base.BottleCrafted")
--      table   -> vessel + bonus items
--                 { vessel = "Base.EmptyJar", bonus = {"Base.JarLid"} }
--                 Bonus items have their condition set to match the
--                 vessel's condition value (clamped to their ConditionMax).
--
-- Condition reset runs BEFORE vessel replacement in the same event
-- handler, guaranteeing correct execution order.
--
-- B42 FluidContainers have no built-in ReplaceOnEmpty property
-- and no event fires when fluid amount reaches zero, so this
-- system uses the same OnRefreshInventoryWindowContainers hook
-- as PhobosLib_LazyStamp to detect empty items on container open.
--
-- MP: Uses sendRemoveItemFromContainer / sendAddItemToContainer /
--     sendItemStats to sync container changes to the server.
--
-- Hook: Events.OnRefreshInventoryWindowContainers
--   Fires when the inventory panel refreshes its container list
--   (opening loot panel, approaching containers, etc.)
---------------------------------------------------------------

PhobosLib = PhobosLib or {}

local _TAG = "[PhobosLib:VesselReplace]"

--- Empty threshold in litres.  Anything below this is considered empty.
--- Handles float rounding from Java-side DrinkFluid calls.
local _EMPTY_THRESHOLD = 0.001

---------------------------------------------------------------
-- Replacement registry
---------------------------------------------------------------

--- Internal registry: { {prefix=string, mappings=table, guard=function|nil}, ... }
PhobosLib._vesselReplaceEntries = PhobosLib._vesselReplaceEntries or {}

--- Internal registry: { {prefix=string, guard=function|nil}, ... }
PhobosLib._conditionResetEntries = PhobosLib._conditionResetEntries or {}

--- Whether the event hook has been installed.
local _hookInstalled = false

---------------------------------------------------------------
-- Condition reset logic
---------------------------------------------------------------

--- Reset condition to ConditionMax on all empty FluidContainer items
--- in a single container that match a registered prefix.
---@param container any   ItemContainer
---@param entry table     {prefix, guard}
---@return number         Count of items reset
local function resetEmptyInContainer(container, entry)
    local items = container:getItems()
    if not items then return 0 end

    local count = 0
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item then
            local fullType = item:getFullType()
            if fullType and string.find(fullType, entry.prefix, 1, true) then
                local ok, didReset = pcall(function()
                    -- Only FluidContainer items
                    local fc = PhobosLib.tryGetFluidContainer(item)
                    if not fc then return false end

                    -- Only empty containers
                    local amount = PhobosLib.tryGetAmount(fc)
                    if not amount or amount >= _EMPTY_THRESHOLD then return false end

                    -- Only items whose condition is below max
                    local maxCond = item:getConditionMax()
                    if not maxCond or maxCond <= 0 then return false end
                    if item:getCondition() >= maxCond then return false end

                    -- Reset condition to ConditionMax
                    item:setCondition(maxCond)
                    pcall(sendItemStats, item)
                    return true
                end)
                if ok and didReset then
                    count = count + 1
                end
            end
        end
    end
    return count
end

---------------------------------------------------------------
-- Replacement logic
---------------------------------------------------------------

--- Replace all empty FluidContainer items in a single container
--- that match a registered entry.
---@param container any   ItemContainer
---@param entry table     {prefix, mappings, guard}
---@return number         Count of items replaced
local function replaceEmptyInContainer(container, entry)
    local items = container:getItems()
    if not items then return 0 end

    -- Collect phase: find empty items that have a mapping
    local toReplace = {}
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item then
            local fullType = item:getFullType()
            if fullType and string.find(fullType, entry.prefix, 1, true) then
                local mappingValue = entry.mappings[fullType]
                if mappingValue then
                    local ok, isEmpty = pcall(function()
                        local fc = PhobosLib.tryGetFluidContainer(item)
                        if not fc then return false end
                        local amount = PhobosLib.tryGetAmount(fc)
                        if amount ~= nil and amount < _EMPTY_THRESHOLD then
                            return true
                        end
                        return false
                    end)
                    if ok and isEmpty then
                        -- Parse mapping: string or { vessel = ..., bonus = {...} }
                        local vesselType, bonusItems
                        if type(mappingValue) == "string" then
                            vesselType = mappingValue
                        elseif type(mappingValue) == "table" then
                            vesselType = mappingValue.vessel
                            bonusItems = mappingValue.bonus
                        end
                        if vesselType then
                            table.insert(toReplace, {
                                item       = item,
                                vesselType = vesselType,
                                bonusItems = bonusItems,
                            })
                        end
                    end
                end
            end
        end
    end

    -- Replace phase: remove PCP items, add vanilla vessels + bonus items
    local count = 0
    for _, replacement in ipairs(toReplace) do
        local ok, err = pcall(function()
            -- Create the replacement vessel
            local newItem = instanceItem(replacement.vesselType)
            if not newItem then
                print(_TAG .. " failed to create " .. tostring(replacement.vesselType))
                return
            end

            -- Drain any fluid the replacement spawned with (e.g. PetrolCan)
            pcall(function()
                local newFc = PhobosLib.tryGetFluidContainer(newItem)
                if newFc then
                    local newAmount = PhobosLib.tryGetAmount(newFc)
                    if newAmount and newAmount > 0 then
                        PhobosLib.tryDrainFluid(newFc, newAmount)
                    end
                end
            end)

            -- Remove the PCP item and sync to server
            container:Remove(replacement.item)
            pcall(sendRemoveItemFromContainer, container, replacement.item)

            -- Insert the vanilla vessel and sync to server
            container:AddItem(newItem)
            pcall(sendAddItemToContainer, container, newItem)
            pcall(sendItemStats, newItem)

            -- Create and add bonus items (e.g. JarLid for jar vessels)
            if replacement.bonusItems then
                local vesselCond = newItem:getCondition()

                for _, bonusType in ipairs(replacement.bonusItems) do
                    pcall(function()
                        local bonusItem = instanceItem(bonusType)
                        if bonusItem then
                            -- Match bonus item condition to vessel condition
                            local bonusMax = bonusItem:getConditionMax()
                            if bonusMax and bonusMax > 0 then
                                local cond = math.min(vesselCond, bonusMax)
                                bonusItem:setCondition(cond)
                            end
                            container:AddItem(bonusItem)
                            pcall(sendAddItemToContainer, container, bonusItem)
                            pcall(sendItemStats, bonusItem)
                        end
                    end)
                end
            end

            count = count + 1
        end)
        if not ok then
            print(_TAG .. " replacement error: " .. tostring(err))
        end
    end

    return count
end

--- Event handler for OnRefreshInventoryWindowContainers.
--- Two-phase processing: condition reset runs BEFORE vessel replacement.
---@param inventoryPage any  ISInventoryPage
---@param stage string       Refresh stage
local function onRefreshContainers(inventoryPage, stage)
    if stage ~= "end" then return end

    pcall(function()
        if not inventoryPage or not inventoryPage.backpacks then return end

        local totalReset = 0
        local totalReplaced = 0

        -- Phase 1: Condition reset (runs BEFORE vessel replacement)
        for _, entry in ipairs(PhobosLib._conditionResetEntries) do
            local shouldRun = true
            if entry.guard then
                local guardOk, guardResult = pcall(entry.guard)
                if not guardOk or guardResult ~= true then
                    shouldRun = false
                end
            end

            if shouldRun then
                for _, backpack in ipairs(inventoryPage.backpacks) do
                    if backpack and backpack.inventory then
                        local count = resetEmptyInContainer(backpack.inventory, entry)
                        if count > 0 then
                            totalReset = totalReset + count
                            print(_TAG .. " reset condition on " .. count .. " empty container(s) for prefix '" .. entry.prefix .. "'")
                        end
                    end
                end
            end
        end

        -- Phase 2: Vessel replacement (runs AFTER condition reset)
        for _, entry in ipairs(PhobosLib._vesselReplaceEntries) do
            local shouldRun = true
            if entry.guard then
                local guardOk, guardResult = pcall(entry.guard)
                if not guardOk or guardResult ~= true then
                    shouldRun = false
                end
            end

            if shouldRun then
                for _, backpack in ipairs(inventoryPage.backpacks) do
                    if backpack and backpack.inventory then
                        local count = replaceEmptyInContainer(backpack.inventory, entry)
                        if count > 0 then
                            totalReplaced = totalReplaced + count
                            print(_TAG .. " replaced " .. count .. " empty vessel(s) in container for prefix '" .. entry.prefix .. "'")
                        end
                    end
                end
            end
        end

        -- Force inventory UI to refresh on the next frame so the
        -- player sees changes immediately.  Our hook fires AFTER
        -- refreshContainer() has already rebuilt the item list
        -- (ISInventoryPage line 1875 vs 1890), so we set the dirty
        -- flag for the render loop.
        if totalReset > 0 or totalReplaced > 0 then
            pcall(function()
                if inventoryPage.inventoryPane and inventoryPage.inventoryPane.inventory then
                    inventoryPage.inventoryPane.inventory:setDrawDirty(true)
                end
            end)
        end
    end)
end

---------------------------------------------------------------
-- Hook installation
---------------------------------------------------------------

--- Install the event hook (once).
local function installHook()
    if _hookInstalled then return end
    Events.OnRefreshInventoryWindowContainers.Add(onRefreshContainers)
    _hookInstalled = true
    print(_TAG .. " OnRefreshInventoryWindowContainers hook installed")
end

---------------------------------------------------------------
-- Public API
---------------------------------------------------------------

--- Register empty vessel replacements for FluidContainer items.
---
--- When the player opens or views a container, any item whose fullType
--- is in the mappings table AND whose FluidContainer is empty (amount
--- below threshold) will be removed and replaced with the corresponding
--- vanilla vessel item.
---
--- Mapping values can be either:
---   string  -> simple replacement ("Base.BottleCrafted")
---   table   -> { vessel = "Base.EmptyJar", bonus = {"Base.JarLid"} }
---              Bonus items have their condition matched to the vessel.
---
--- Use this for mods that define custom FluidContainer items which
--- should revert to their base vessel when emptied (e.g. "Jar of
--- Glycerol" -> mason jar + lid after drinking/dumping).
---
---@param modulePrefix string       Item fullType prefix for fast filtering
---                                  (e.g. "PhobosChemistryPathways.")
---@param mappings     table        Map of fullType -> replacement (string or table)
---                                  e.g. { ["Mod.Item"] = "Base.BottleCrafted" }
---                                  or   { ["Mod.Item"] = { vessel = "Base.EmptyJar", bonus = {"Base.JarLid"} } }
---@param guardFunc    function|nil Optional guard: function() -> boolean.
---                                  Replacement only occurs when guard returns true.
function PhobosLib.registerEmptyVesselReplacement(modulePrefix, mappings, guardFunc)
    if type(modulePrefix) ~= "string" or modulePrefix == "" then
        print(_TAG .. " registerEmptyVesselReplacement: invalid modulePrefix")
        return
    end
    if type(mappings) ~= "table" then
        print(_TAG .. " registerEmptyVesselReplacement: mappings must be a table")
        return
    end
    if guardFunc ~= nil and type(guardFunc) ~= "function" then
        print(_TAG .. " registerEmptyVesselReplacement: guardFunc must be a function or nil")
        return
    end

    table.insert(PhobosLib._vesselReplaceEntries, {
        prefix   = modulePrefix,
        mappings = mappings,
        guard    = guardFunc,
    })

    -- Install hook on first registration
    installHook()

    -- Count mappings for the log
    local mapCount = 0
    for _ in pairs(mappings) do mapCount = mapCount + 1 end
    print(_TAG .. " registered " .. mapCount .. " vessel mapping(s) for prefix '" .. modulePrefix .. "'")
end

--- Register condition reset for empty FluidContainer items.
---
--- When the player opens or views a container, any FluidContainer item
--- whose fullType matches the modulePrefix AND whose fluid amount is
--- below the empty threshold will have its condition restored to
--- ConditionMax.  This removes the "(Worn)" suffix from items that
--- used condition as a metadata channel (e.g. purity) and were then
--- drained.
---
--- Condition reset runs BEFORE vessel replacement in the same event
--- handler, so items that are subsequently replaced by vessel mappings
--- will have had their condition harmlessly reset first.
---
---@param modulePrefix string       Item fullType prefix for fast filtering
---                                  (e.g. "PhobosChemistryPathways.")
---@param guardFunc    function|nil Optional guard: function() -> boolean.
---                                  Reset only occurs when guard returns true.
---                                  Use for sandbox option checks (e.g. impurity enabled).
function PhobosLib.registerEmptyConditionReset(modulePrefix, guardFunc)
    if type(modulePrefix) ~= "string" or modulePrefix == "" then
        print(_TAG .. " registerEmptyConditionReset: invalid modulePrefix")
        return
    end
    if guardFunc ~= nil and type(guardFunc) ~= "function" then
        print(_TAG .. " registerEmptyConditionReset: guardFunc must be a function or nil")
        return
    end

    table.insert(PhobosLib._conditionResetEntries, {
        prefix = modulePrefix,
        guard  = guardFunc,
    })

    -- Install hook on first registration (shared with vessel replacement)
    installHook()

    print(_TAG .. " registered condition reset for prefix '" .. modulePrefix .. "'")
end
