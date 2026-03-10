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
-- PhobosLib_Fluid.lua
-- Build 42 fluid container helpers.
-- Provides pcall-safe probing for the B42 fluid system which
-- may change method signatures between beta builds.
--
-- MP: Functions modify item/fluid state via engine APIs that auto-sync in MP.
-- NPC: All methods called exist on IsoGameCharacter (safe for IsoNpcPlayer).
---------------------------------------------------------------

PhobosLib = PhobosLib or {}


--- Attempt to retrieve a fluid container object from an item.
--- Tries multiple known method names to handle API changes.
---@param item any  A PZ inventory item
---@return any|nil  The fluid container, or nil if not found/supported
function PhobosLib.tryGetFluidContainer(item)
    if not item then return nil end
    return PhobosLib.probeMethodAny(item, {
        "getFluidContainer",
        "getFluidContainerItem",
        "getFluid",
    })
end


--- Probe the capacity (in litres) of a fluid container.
---@param fc any    A fluid container object
---@return number|nil
function PhobosLib.tryGetCapacity(fc)
    if not fc then return nil end
    return PhobosLib.probeMethod(fc, {
        "getCapacity",
        "getMaxCapacity",
        "getMaxAmount",
        "getCapacityLiters",
        "getMax",
    })
end


--- Probe the current amount (in litres) in a fluid container.
---@param fc any
---@return number|nil
function PhobosLib.tryGetAmount(fc)
    if not fc then return nil end
    return PhobosLib.probeMethod(fc, {
        "getAmount",
        "getCurrentAmount",
        "getQuantity",
    })
end


--- Attempt to add fluid to a container using multiple strategies.
--- Returns true if any strategy succeeded.
---
--- NOTE: The B42 Java addFluid() method requires a FluidType Java object,
--- NOT a raw string. When a string is passed, this function resolves it via
--- FluidType.FromNameLower() first. Without this resolution, fluid is added
--- but the recipe system's -fluid matching cannot find it.
---@param fc any            The fluid container object
---@param fluidType string  The fluid's full type identifier (e.g. "Brine", "Petrol")
---@param liters number     Amount to add in litres (must be > 0)
---@return boolean
function PhobosLib.tryAddFluid(fc, fluidType, liters)
    if not fc or not fluidType or liters <= 0 then return false end

    -- Resolve string to FluidType Java object (required for recipe system matching)
    local ftObj = nil
    pcall(function()
        ftObj = FluidType.FromNameLower(string.lower(fluidType))
    end)

    local strategies = {
        -- Strategy 1: addFluid(FluidType, amount) — preferred, vanilla pattern
        function()
            if fc.addFluid then
                if ftObj then return fc:addFluid(ftObj, liters) end
                return fc:addFluid(fluidType, liters)
            end
        end,
        -- Strategy 2: add(FluidType, amount)
        function()
            if fc.add then
                if ftObj then return fc:add(ftObj, liters) end
                return fc:add(fluidType, liters)
            end
        end,
        -- Strategy 3: setFluid + setAmount
        function()
            if fc.setFluid then
                fc:setFluid(ftObj or fluidType)
                if fc.setAmount then fc:setAmount(liters) end
                return true
            end
        end,
        -- Strategy 4: setFluidType + setAmount
        function()
            if fc.setFluidType then
                fc:setFluidType(ftObj or fluidType)
                if fc.setAmount then fc:setAmount(liters) end
                return true
            end
        end,
    }

    for _, fn in ipairs(strategies) do
        local ok, res = pcall(fn)
        if ok and (res == true or res == nil) then return true end
    end
    return false
end


--- Probe the name of the fluid currently stored in a fluid container.
--- Returns a plain string (e.g. "CrudeVegetableOil"), or nil if empty/unknown.
---@param fc any    A fluid container object
---@return string|nil
function PhobosLib.tryGetFluidName(fc)
    if not fc then return nil end
    -- Strategy 1: getPrimaryFluid() -> FluidType -> getName()
    local ok, name = pcall(function()
        local ft = fc:getPrimaryFluid()
        if ft then return ft:getName() end
    end)
    if ok and name then return tostring(name) end
    -- Strategy 2: getFluidType() -> FluidType -> getName()
    ok, name = pcall(function()
        local ft = fc:getFluidType()
        if ft then return ft:getName() end
    end)
    if ok and name then return tostring(name) end
    -- Strategy 3: direct string accessor
    local direct = PhobosLib.probeMethod(fc, {
        "getContainedFluidName",
        "getFluidName",
        "getFluidTypeName",
    })
    if direct then return tostring(direct) end
    return nil
end


--- Find the first empty FluidContainer in the player's inventory
--- whose fullType matches an entry in the accepted-types whitelist.
--- Searches main inventory only (not nested bags).
---@param player any           IsoGameCharacter
---@param acceptedTypes table  Array of fullType strings, e.g. {"Base.EmptyJar", "Base.BucketForged"}
---@return any|nil             The inventory item, or nil if none found
function PhobosLib.findEmptyFluidContainer(player, acceptedTypes)
    if not player or not acceptedTypes then return nil end

    -- Build a set for O(1) lookup
    local allowed = {}
    for _, ft in ipairs(acceptedTypes) do allowed[ft] = true end

    local result = nil
    pcall(function()
        local inv = player:getInventory()
        if not inv then return end
        local items = inv:getItems()
        for i = 0, items:size() - 1 do
            local item = items:get(i)
            if item and allowed[item:getFullType()] then
                local fc = PhobosLib.tryGetFluidContainer(item)
                if fc then
                    local amt = PhobosLib.tryGetAmount(fc)
                    if not amt or amt <= 0 then
                        result = item
                        return
                    end
                end
            end
        end
    end)
    return result
end


--- Attempt to drain/remove fluid from a container.
---@param fc any
---@param liters number
---@return boolean
function PhobosLib.tryDrainFluid(fc, liters)
    if not fc or liters <= 0 then return false end

    local strategies = {
        function()
            if fc.removeFluid then return fc:removeFluid(liters) end
        end,
        function()
            if fc.drain then return fc:drain(liters) end
        end,
        function()
            if fc.setAmount then
                local cur = PhobosLib.tryGetAmount(fc) or 0
                fc:setAmount(math.max(0, cur - liters))
                return true
            end
        end,
    }

    for _, fn in ipairs(strategies) do
        local ok, res = pcall(fn)
        if ok and (res == true or res == nil) then return true end
    end
    return false
end
