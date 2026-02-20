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
-- Client-side empty vessel replacement for FluidContainers.
--
-- Provides a registry for mods that define custom FluidContainer
-- items which should revert to their base vanilla vessel when
-- emptied.  When a container is opened in the inventory UI, all
-- empty FluidContainer items matching a registered mapping are
-- removed and replaced with the corresponding vanilla vessel.
--
-- Mappings can be either:
--   string  -> simple replacement  ("Base.BottleCrafted")
--   table   -> vessel + bonus items
--              { vessel = "Base.EmptyJar", bonus = {"Base.JarLid"} }
--              Bonus items have their condition set to match the
--              vessel's condition value (clamped to their ConditionMax).
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
--
-- Part of PhobosLib >= 1.10.0
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

--- Whether the event hook has been installed.
local _hookInstalled = false

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
---@param inventoryPage any  ISInventoryPage
---@param stage string       Refresh stage
local function onRefreshContainers(inventoryPage, stage)
    if stage ~= "end" then return end

    pcall(function()
        if not inventoryPage or not inventoryPage.backpacks then return end

        local totalReplaced = 0

        for _, entry in ipairs(PhobosLib._vesselReplaceEntries) do
            -- Check guard function
            local shouldRun = true
            if entry.guard then
                local guardOk, guardResult = pcall(entry.guard)
                if not guardOk or guardResult ~= true then
                    shouldRun = false
                end
            end

            if shouldRun then
                -- Iterate all visible containers
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
        -- player sees the vanilla vessel immediately, not the stale
        -- PCP item.  Our hook fires AFTER refreshContainer() has
        -- already rebuilt the item list (ISInventoryPage line 1875
        -- vs 1890), so we set the dirty flag for the render loop.
        if totalReplaced > 0 then
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
