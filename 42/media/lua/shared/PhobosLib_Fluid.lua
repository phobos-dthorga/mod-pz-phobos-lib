---------------------------------------------------------------
-- PhobosLib_Fluid.lua
-- Build 42 fluid container helpers.
-- Provides pcall-safe probing for the B42 fluid system which
-- may change method signatures between beta builds.
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
---@param fc any            The fluid container object
---@param fluidType string  The fluid's full type identifier
---@param liters number     Amount to add in litres (must be > 0)
---@return boolean
function PhobosLib.tryAddFluid(fc, fluidType, liters)
    if not fc or not fluidType or liters <= 0 then return false end

    local strategies = {
        -- Strategy 1: addFluid(type, amount)
        function()
            if fc.addFluid then return fc:addFluid(fluidType, liters) end
        end,
        -- Strategy 2: add(type, amount)
        function()
            if fc.add then return fc:add(fluidType, liters) end
        end,
        -- Strategy 3: setFluid + setAmount
        function()
            if fc.setFluid then
                fc:setFluid(fluidType)
                if fc.setAmount then fc:setAmount(liters) end
                return true
            end
        end,
        -- Strategy 4: setFluidType + setAmount
        function()
            if fc.setFluidType then
                fc:setFluidType(fluidType)
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
