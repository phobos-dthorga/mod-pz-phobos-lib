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
-- PhobosLib_LazyStamp.lua
-- Client-side lazy condition stamper for opened containers.
--
-- Provides a registry for mods that use item condition as a
-- metadata channel (e.g. purity, charge level).  When a
-- container is opened in the inventory UI, all items matching
-- a registered module prefix that still have condition ==
-- ConditionMax (unstamped) are stamped to the configured value.
--
-- This covers items in safehouse storage, vehicle trunks, and
-- other world containers that server-side OnGameStart migrations
-- cannot reach (because those cells may not be loaded).
--
-- MP: Uses sendItemStats to sync condition changes to the server.
--
-- Hook: Events.OnRefreshInventoryWindowContainers
--   Fires when the inventory panel refreshes its container list
--   (opening loot panel, approaching containers, etc.)
--
-- Part of PhobosLib >= 1.9.0
---------------------------------------------------------------

PhobosLib = PhobosLib or {}

local _TAG = "[PhobosLib:LazyStamp]"

---------------------------------------------------------------
-- Stamp registry
---------------------------------------------------------------

--- Internal registry: { {prefix=string, value=number, guard=function|nil}, ... }
PhobosLib._lazyStampEntries = PhobosLib._lazyStampEntries or {}

--- Whether the event hook has been installed.
local _hookInstalled = false

---------------------------------------------------------------
-- Stamping logic
---------------------------------------------------------------

--- Stamp all matching unstamped items in a single container.
---@param container any  ItemContainer
---@param entry table    {prefix, value, guard}
---@return number        Count of items stamped
local function stampContainer(container, entry)
    local items = container:getItems()
    if not items then return 0 end

    local count = 0
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item then
            local fullType = item:getFullType()
            if fullType and string.find(fullType, entry.prefix, 1, true) then
                local maxCond = item:getConditionMax()
                if maxCond and maxCond > 0 and item:getCondition() == maxCond then
                    -- Scale stampValue (percentage) to item's ConditionMax
                    local scaledValue = math.floor(entry.value / 100 * maxCond + 0.5)
                    scaledValue = math.min(maxCond - 1, scaledValue)
                    item:setCondition(scaledValue)
                    pcall(sendItemStats, item)
                    count = count + 1
                end
            end
        end
    end
    return count
end

--- Event handler for OnRefreshInventoryWindowContainers.
--- Event fires with (ISInventoryPage, stage_string) where stage is
--- "begin", "beforeFloor", "buttonsAdded", or "end".
--- We only stamp at "end" when all containers are finalized.
---@param inventoryPage any  ISInventoryPage
---@param stage string       Refresh stage
local function onRefreshContainers(inventoryPage, stage)
    if stage ~= "end" then return end

    pcall(function()
        if not inventoryPage or not inventoryPage.backpacks then return end

        for _, entry in ipairs(PhobosLib._lazyStampEntries) do
            -- Check guard function (e.g. sandbox option enabled)
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
                        local count = stampContainer(backpack.inventory, entry)
                        if count > 0 then
                            print(_TAG .. " stamped " .. count .. " item(s) in container for prefix '" .. entry.prefix .. "'")
                        end
                    end
                end
            end
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

--- Register a lazy condition stamper for items matching a module prefix.
---
--- When the player opens or views a container, any item whose fullType
--- starts with modulePrefix and whose condition equals ConditionMax
--- (unstamped) will have its condition set to stampValue.
---
--- Use this for mods that repurpose item condition as a metadata channel
--- (e.g. purity, charge level) and need to ensure pre-existing items
--- in world containers get stamped when first accessed.
---
---@param modulePrefix string     Item fullType prefix (e.g. "PhobosChemistryPathways.")
---@param stampValue   number     Purity percentage to stamp (e.g. 99 = 99%), scaled to ConditionMax
---@param guardFunc    function|nil  Optional guard: function() -> boolean.
---                                   Stamping only occurs when guard returns true.
---                                   Use for sandbox option checks.
function PhobosLib.registerLazyConditionStamp(modulePrefix, stampValue, guardFunc)
    if type(modulePrefix) ~= "string" or modulePrefix == "" then
        print(_TAG .. " registerLazyConditionStamp: invalid modulePrefix")
        return
    end
    if type(stampValue) ~= "number" then
        print(_TAG .. " registerLazyConditionStamp: stampValue must be a number")
        return
    end
    if guardFunc ~= nil and type(guardFunc) ~= "function" then
        print(_TAG .. " registerLazyConditionStamp: guardFunc must be a function or nil")
        return
    end

    table.insert(PhobosLib._lazyStampEntries, {
        prefix = modulePrefix,
        value  = stampValue,
        guard  = guardFunc,
    })

    -- Install hook on first registration
    installHook()

    print(_TAG .. " registered stamper for prefix '" .. modulePrefix .. "' -> condition " .. stampValue)
end
