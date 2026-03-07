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
-- PhobosLib_Fermentation.lua
-- Generic fermentation / positive-rot registry and progress API.
--
-- B42 uses ReplaceOnRotten to auto-transform food items when
-- they reach DaysTotallyRotten. For fermentation items this is
-- a beneficial transformation, not spoilage. This module lets
-- mods register such items and query their progress.
--
-- Pure data — no events, no hooks, safe in shared/ context.
-- Part of PhobosLib — shared by all Phobos PZ mods.
---------------------------------------------------------------

PhobosLib = PhobosLib or {}

local _TAG = "[PhobosLib:Ferment]"

---------------------------------------------------------------
-- Internal registry
---------------------------------------------------------------

local _registry = {}

local _MONTH_SHORT = {
    "Jan", "Feb", "Mar", "Apr", "May", "Jun",
    "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
}

---------------------------------------------------------------
-- Registration API
---------------------------------------------------------------

--- Register an item type as a "positive rot" fermentation item.
--- Items registered here have their ReplaceOnRotten transformation
--- treated as a beneficial process (fermentation, curing, aging)
--- rather than spoilage.
---
--- Call at file-load time (no OnGameStart dependency).
---
---@param fullType string  Full item type (e.g. "PhobosChemistryPathways.CannedHempBuds")
---@param config   table   Configuration:
---   config.label          string   Process name (e.g. "Curing")
---   config.totalHours     number   Hours from creation to ReplaceOnRotten
---   config.translationKey string?  Optional getText() key for the label
function PhobosLib.registerFermentation(fullType, config)
    if type(fullType) ~= "string" or fullType == "" then
        print(_TAG .. " registerFermentation: invalid fullType")
        return
    end
    if type(config) ~= "table" then
        print(_TAG .. " registerFermentation: config must be a table")
        return
    end
    if type(config.label) ~= "string" or config.label == "" then
        print(_TAG .. " registerFermentation: config.label required")
        return
    end
    if type(config.totalHours) ~= "number" or config.totalHours <= 0 then
        print(_TAG .. " registerFermentation: config.totalHours must be > 0")
        return
    end

    _registry[fullType] = {
        label          = config.label,
        totalHours     = config.totalHours,
        translationKey = config.translationKey,
    }

    print(_TAG .. " registered: " .. fullType
          .. " (" .. config.label .. ", " .. config.totalHours .. "h)")
end

---------------------------------------------------------------
-- Query API
---------------------------------------------------------------

--- Check if an item type is registered as a fermentation item.
---@param fullType string
---@return boolean
function PhobosLib.isFermentationItem(fullType)
    return _registry[fullType] ~= nil
end

--- Get the raw registry entry for a fermentation item type.
---@param fullType string
---@return table|nil
function PhobosLib.getFermentationConfig(fullType)
    return _registry[fullType]
end

--- Query fermentation progress for a specific item instance.
--- Returns nil if the item's fullType is not registered or if
--- age data is unavailable.
---
---@param item any  A PZ InventoryItem (food with age tracking)
---@return table|nil  { percent, remainingHours, remainingDays, label, complete }
function PhobosLib.getFermentationProgress(item)
    if not item then return nil end

    local result = nil
    pcall(function()
        local fullType = item:getFullType()
        local config = _registry[fullType]
        if not config then return end

        local age = item:getAge()
        if type(age) ~= "number" then return end

        local totalH = config.totalHours
        local pct = math.min(100, math.floor(age / totalH * 100 + 0.5))
        local remaining = math.max(0, totalH - age)
        local complete = (age >= totalH)

        local label = config.label
        if config.translationKey then
            local ok, translated = pcall(getText, config.translationKey)
            if ok and translated and translated ~= config.translationKey then
                label = translated
            end
        end

        result = {
            percent        = pct,
            remainingHours = remaining,
            remainingDays  = math.ceil(remaining / 24),
            label          = label,
            complete       = complete,
        }
    end)

    return result
end

---------------------------------------------------------------
-- Date stamping API
---------------------------------------------------------------

--- Stamp the current game date into item modData.
--- Call from OnCreate callbacks on fermentation recipes.
---@param item any  The output InventoryItem
function PhobosLib.stampFermentationDate(item)
    pcall(function()
        if not item then return end
        local gt = getGameTime()
        item:getModData().PhobosLib_FermentStart = {
            y = gt:getYear(),
            m = gt:getMonth(),  -- 0-indexed (0=Jan)
            d = gt:getDay(),
        }
    end)
end

--- Read the fermentation date stamp from item modData.
---@param item any  The InventoryItem to check
---@return table|nil  { year, month, day } (month 1-indexed) or nil
function PhobosLib.getFermentationDate(item)
    local result = nil
    pcall(function()
        if not item then return end
        local stamp = item:getModData().PhobosLib_FermentStart
        if type(stamp) ~= "table" then return end
        if stamp.y and stamp.m and stamp.d then
            result = {
                year  = stamp.y,
                month = stamp.m + 1,  -- convert 0-indexed to 1-indexed
                day   = stamp.d,
            }
        end
    end)
    return result
end

--- Format a date table as a short display string (e.g. "Jul 12").
---@param dateTable table  { year, month, day } with month 1-indexed
---@return string
function PhobosLib.formatGameDate(dateTable)
    if type(dateTable) ~= "table" then return "?" end
    local m = dateTable.month or 1
    local d = dateTable.day or 1
    local monthName = _MONTH_SHORT[m] or "???"
    return monthName .. " " .. tostring(d)
end

print(_TAG .. " Fermentation module loaded")
