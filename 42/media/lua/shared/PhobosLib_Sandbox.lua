---------------------------------------------------------------
-- PhobosLib_Sandbox.lua
-- Safe sandbox variable access and mod detection utilities.
-- Part of PhobosLib — shared by all Phobos PZ mods.
---------------------------------------------------------------

PhobosLib = PhobosLib or {}

--- Safely retrieve a sandbox variable with a fallback default.
-- @param modId   string  The mod namespace (e.g. "PCP")
-- @param varName string  The variable name (e.g. "YieldMultiplier")
-- @param default any     Value returned if the variable is missing or nil
-- @return any            The sandbox value or the default
function PhobosLib.getSandboxVar(modId, varName, default)
    local ok, result = pcall(function()
        if SandboxVars and SandboxVars[modId] then
            local val = SandboxVars[modId][varName]
            if val ~= nil then
                return val
            end
        end
        return nil
    end)
    if ok and result ~= nil then
        return result
    end
    return default
end

--- Check whether a mod is currently active in the loaded mod list.
-- Useful for optional cross-mod tie-ins that should only activate
-- when both mods are present.
-- @param modId string  The mod ID to check (e.g. "PhobosChemistryPathways")
-- @return boolean      true if the mod is active
function PhobosLib.isModActive(modId)
    local ok, result = pcall(function()
        local mods = getActivatedMods()
        if mods and mods.contains then
            return mods:contains(modId)
        end
        return false
    end)
    if ok then
        return result == true
    end
    return false
end

--- Apply a numeric multiplier from a sandbox variable to a base amount.
-- Rounds to the nearest integer (minimum 1).
-- @param baseAmount number  The unmodified output quantity
-- @param modId      string  The mod namespace for the sandbox var
-- @param varName    string  The multiplier variable name
-- @return number            The scaled amount (integer, >= 1)
function PhobosLib.applyYieldMultiplier(baseAmount, modId, varName)
    local mult = PhobosLib.getSandboxVar(modId, varName, 1.0)
    if type(mult) ~= "number" or mult <= 0 then
        mult = 1.0
    end
    local result = math.floor(baseAmount * mult + 0.5)
    if result < 1 then result = 1 end
    return result
end
