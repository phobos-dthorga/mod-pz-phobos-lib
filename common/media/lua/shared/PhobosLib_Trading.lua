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
-- PhobosLib_Trading.lua
-- Generic wrapper for Dynamic Trading mod (DynamicTradingCommon)
-- API for registering items, tags, and archetypes with NPC
-- traders when the Dynamic Trading mod is installed.
--
-- All functions are no-ops when DynamicTrading is not active.
-- All DT calls are pcall-wrapped for safety if the mod is
-- removed mid-save.
--
-- Detection is lazy: the first call to any function checks
-- whether the DynamicTrading global and its RegisterBatch
-- method exist. This avoids load-order issues where DT's
-- 00_DT_Core.lua might not have loaded yet at require time.
--
-- Part of PhobosLib >= 1.7.0
---------------------------------------------------------------

PhobosLib = PhobosLib or {}

local _dtChecked  = false
local _dtAvailable = false

local _prefix = "[PhobosLib:Trading]"

--- Lazy detection: check once whether DynamicTrading API is available.
local function _ensureChecked()
    if _dtChecked then return end
    _dtChecked = true

    local ok, result = pcall(function()
        return DynamicTrading
            and DynamicTrading.RegisterBatch
            and DynamicTrading.RegisterTag
            and DynamicTrading.RegisterArchetype
            and DynamicTrading.AddItem
    end)

    _dtAvailable = ok and (result ~= nil and result ~= false)

    if _dtAvailable then
        print(_prefix .. " Dynamic Trading API detected [" .. (isServer() and "server" or "local") .. "]")
    end
end

---------------------------------------------------------------
--- Check if Dynamic Trading is available at runtime.
--- @return boolean
---------------------------------------------------------------
function PhobosLib.isDynamicTradingActive()
    _ensureChecked()
    return _dtAvailable
end

---------------------------------------------------------------
--- Register a custom tag with price multiplier and spawn weight.
--- No-op if DynamicTrading is not active. Pcall-wrapped.
--- @param tag string         Tag name (e.g. "Chemical")
--- @param data table         { priceMult = number, weight = number }
--- @return boolean success
---------------------------------------------------------------
function PhobosLib.registerTradeTag(tag, data)
    _ensureChecked()
    if not _dtAvailable then return false end

    local ok, err = pcall(function()
        DynamicTrading.RegisterTag(tag, data)
    end)

    if ok then
        print(_prefix .. " Tag registered: " .. tostring(tag) .. " [" .. (isServer() and "server" or "local") .. "]")
    else
        print(_prefix .. " Tag registration failed (" .. tostring(tag) .. "): " .. tostring(err))
    end

    return ok
end

---------------------------------------------------------------
--- Register a trader archetype (NPC trader persona).
--- No-op if DynamicTrading is not active. Pcall-wrapped.
--- @param id string          Unique archetype ID (e.g. "PCP_Chemist")
--- @param data table         { name, allocations, wants, forbid }
--- @return boolean success
---------------------------------------------------------------
function PhobosLib.registerTradeArchetype(id, data)
    _ensureChecked()
    if not _dtAvailable then return false end

    local ok, err = pcall(function()
        DynamicTrading.RegisterArchetype(id, data)
    end)

    if ok then
        print(_prefix .. " Archetype registered: " .. tostring(id) .. " [" .. (isServer() and "server" or "local") .. "]")
    else
        print(_prefix .. " Archetype registration failed (" .. tostring(id) .. "): " .. tostring(err))
    end

    return ok
end

---------------------------------------------------------------
--- Register items for trading (batch).
--- No-op if DynamicTrading is not active. Pcall-wrapped.
--- @param list table         Array of { item, basePrice, tags, stockRange }
--- @return boolean success, number count
---------------------------------------------------------------
function PhobosLib.registerTradeItems(list)
    _ensureChecked()
    if not _dtAvailable then return false, 0 end
    if not list or #list == 0 then return false, 0 end

    local count = #list

    local ok, err = pcall(function()
        DynamicTrading.RegisterBatch(list)
    end)

    if ok then
        print(_prefix .. " " .. tostring(count) .. " items registered [" .. (isServer() and "server" or "local") .. "]")
    else
        print(_prefix .. " Batch registration failed (" .. tostring(count) .. " items): " .. tostring(err))
        count = 0
    end

    return ok, count
end

---------------------------------------------------------------
--- Register a single item for trading.
--- No-op if DynamicTrading is not active. Pcall-wrapped.
--- @param uniqueID string    Unique key for lookup
--- @param data table         { item, basePrice, tags, stockRange }
--- @return boolean success
---------------------------------------------------------------
function PhobosLib.registerTradeItem(uniqueID, data)
    _ensureChecked()
    if not _dtAvailable then return false end

    local ok, err = pcall(function()
        DynamicTrading.AddItem(uniqueID, data)
    end)

    if not ok then
        print(_prefix .. " Item registration failed (" .. tostring(uniqueID) .. "): " .. tostring(err))
    end

    return ok
end
