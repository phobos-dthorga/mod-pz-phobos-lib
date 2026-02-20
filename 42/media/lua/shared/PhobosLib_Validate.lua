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
-- PhobosLib_Validate.lua
-- Startup dependency validation for Project Zomboid Build 42.
-- Mods register expected items, fluids, and perks at file-load
-- time.  A single validateDependencies() call during OnGameStart
-- checks they all exist and logs any failures with the
-- requesting mod's ID for easy triage.
--
-- Part of PhobosLib — shared by all Phobos PZ mods.
---------------------------------------------------------------

PhobosLib = PhobosLib or {}


---------------------------------------------------------------
-- Internal: pending expectations
---------------------------------------------------------------

local _expectations = {
    items  = {},   -- { {modId, fullType}, ... }
    fluids = {},   -- { {modId, fluidName}, ... }
    perks  = {},   -- { {modId, perkName}, ... }
}

local _validated = false
local _TAG = "[PhobosLib:Validate]"


---------------------------------------------------------------
-- Registration API  (call at file-load time, before OnGameStart)
---------------------------------------------------------------

--- Register an expected item dependency.
--- If the item doesn't exist at validation time, a warning is logged.
---@param modId    string  Short mod identifier shown in logs (e.g. "PCP")
---@param fullType string  Full item type (e.g. "Base.Amplifier")
function PhobosLib.expectItem(modId, fullType)
    if not modId or not fullType then return end
    table.insert(_expectations.items, { modId = modId, key = fullType })
end

--- Register an expected fluid dependency.
---@param modId     string  Short mod identifier shown in logs
---@param fluidName string  Fluid script name (e.g. "Water", "SulphuricAcid")
function PhobosLib.expectFluid(modId, fluidName)
    if not modId or not fluidName then return end
    table.insert(_expectations.fluids, { modId = modId, key = fluidName })
end

--- Register an expected perk dependency.
---@param modId    string  Short mod identifier shown in logs
---@param perkName string  Perk name (e.g. "AppliedChemistry")
function PhobosLib.expectPerk(modId, perkName)
    if not modId or not perkName then return end
    table.insert(_expectations.perks, { modId = modId, key = perkName })
end


---------------------------------------------------------------
-- Internal: existence checks (pcall-guarded)
---------------------------------------------------------------

local function _itemExists(fullType)
    local ok, result = pcall(function()
        return ScriptManager.instance:FindItem(fullType) ~= nil
    end)
    return ok and result == true
end

local function _fluidExists(fluidName)
    local ok, result = pcall(function()
        return Fluid.Get(fluidName) ~= nil
    end)
    return ok and result == true
end

-- perkExists already lives in PhobosLib_Skill.lua; reuse it.


---------------------------------------------------------------
-- Validation API
---------------------------------------------------------------

--- Validate all registered dependencies.
--- Logs every missing item/fluid/perk with the registering mod's ID.
--- Returns a structured report table:
---   { items = { {modId, key}, ... }, fluids = { ... }, perks = { ... } }
--- Each sub-table lists only the MISSING entries.
---
--- Safe to call more than once (idempotent), but only logs on the
--- first invocation to avoid spamming the console.
---@return table  Report of missing dependencies
function PhobosLib.validateDependencies()
    local report = { items = {}, fluids = {}, perks = {} }
    local firstRun = not _validated
    _validated = true

    -- Items
    for _, e in ipairs(_expectations.items) do
        if not _itemExists(e.key) then
            table.insert(report.items, e)
            if firstRun then
                print(_TAG .. " [" .. e.modId .. "] MISSING ITEM: " .. e.key)
            end
        end
    end

    -- Fluids
    for _, e in ipairs(_expectations.fluids) do
        if not _fluidExists(e.key) then
            table.insert(report.fluids, e)
            if firstRun then
                print(_TAG .. " [" .. e.modId .. "] MISSING FLUID: " .. e.key)
            end
        end
    end

    -- Perks
    for _, e in ipairs(_expectations.perks) do
        if not PhobosLib.perkExists(e.key) then
            table.insert(report.perks, e)
            if firstRun then
                print(_TAG .. " [" .. e.modId .. "] MISSING PERK: " .. e.key)
            end
        end
    end

    -- Summary
    local totalMissing = #report.items + #report.fluids + #report.perks
    local totalChecked = #_expectations.items + #_expectations.fluids + #_expectations.perks
    if firstRun then
        if totalMissing == 0 then
            print(_TAG .. " All " .. totalChecked .. " dependencies OK.")
        else
            print(_TAG .. " " .. totalMissing .. " of " .. totalChecked
                  .. " dependencies MISSING — see above for details.")
        end
    end

    return report
end
