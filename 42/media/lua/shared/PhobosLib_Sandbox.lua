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

--- Safely set a sandbox variable value.
--- Used to auto-reset one-shot cleanup options back to false.
--- @param modId   string  The mod namespace (e.g. "PCP")
--- @param varName string  The variable name
--- @param value   any     The value to set
--- @return boolean        true if set succeeded
function PhobosLib.setSandboxVar(modId, varName, value)
    local ok = pcall(function()
        if SandboxVars and SandboxVars[modId] then
            SandboxVars[modId][varName] = value
        end
    end)
    return ok
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

--- Mark a one-shot sandbox boolean as consumed.
--- Clears the in-memory value AND records a world modData flag so the
--- value can be re-cleared on next game start (belt-and-suspenders).
--- @param modId   string  The mod namespace (e.g. "PCP")
--- @param varName string  The boolean sandbox variable name
--- @return boolean        true if both operations succeeded
function PhobosLib.consumeSandboxFlag(modId, varName)
    local ok = pcall(function()
        if SandboxVars and SandboxVars[modId] then
            SandboxVars[modId][varName] = false
        end
        local md = getGameTime():getModData()
        md["PhobosLib_consumed_" .. modId .. "_" .. varName] = true
    end)
    if ok then
        print("[PhobosLib:Sandbox] consumed flag " .. modId .. "." .. varName)
    end
    return ok
end

--- Re-apply all previously consumed sandbox flags from world modData.
--- Called automatically via Events.OnGameStart so that one-shot options
--- remain cleared even after a game restart.
function PhobosLib.reapplyConsumedFlags()
    local count = 0
    pcall(function()
        local md = getGameTime():getModData()
        local prefix = "PhobosLib_consumed_"
        for key, val in pairs(md) do
            if type(key) == "string" and key:sub(1, #prefix) == prefix and val == true then
                local rest = key:sub(#prefix + 1)       -- "PCP_ResetStripPurity"
                local modId, varName = rest:match("^([^_]+)_(.+)$")
                if modId and varName and SandboxVars and SandboxVars[modId] then
                    SandboxVars[modId][varName] = false
                    count = count + 1
                end
            end
        end
    end)
    if count > 0 then
        print("[PhobosLib:Sandbox] reapplied " .. count .. " consumed flag(s)")
    end
end

Events.OnGameStart.Add(PhobosLib.reapplyConsumedFlags)

--- Create (or retrieve) a named global callback table.
--- PZ's built-in callback tables (RecipeCodeOnTest, RecipeCodeOnCreate, etc.)
--- are Java-exposed; Lua-defined additions are invisible to callLuaBool().
--- This function creates a mod-owned global Lua table that the engine CAN
--- resolve, following the same pattern vanilla mods use for OnCreate.
--- @param name string  The global table name (e.g. "PCP_RecipeOnTest")
--- @return table       The global table (created if it did not exist)
function PhobosLib.createCallbackTable(name)
    if type(name) ~= "string" or name == "" then
        print("[PhobosLib:Sandbox] createCallbackTable: invalid name")
        return {}
    end
    if not _G[name] then
        _G[name] = {}
        print("[PhobosLib:Sandbox] created callback table: " .. name)
    end
    return _G[name]
end

--- Register a single OnTest callback in a named global table.
--- Convenience wrapper around createCallbackTable + assignment.
--- Recipe scripts reference callbacks as "TableName.funcName".
--- @param tableName string    The global table name (e.g. "PCP_RecipeOnTest")
--- @param funcName  string    The callback name (e.g. "pcpHeatRequiredCheck")
--- @param func      function  The callback function(params) → boolean
--- @return string             Fully-qualified reference for recipe scripts
function PhobosLib.registerOnTest(tableName, funcName, func)
    local tbl = PhobosLib.createCallbackTable(tableName)
    tbl[funcName] = func
    return tableName .. "." .. funcName
end
