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
-- PhobosLib_Radio.lua
-- Reusable radio hardware utilities for PZ Build 42.
--
-- Provides transmit range lookup and device category detection
-- for both inventory items and world-placed radio objects.
-- Compatible with AZAS Frequency Index categorisation.
---------------------------------------------------------------

PhobosLib_Radio = {}

---------------------------------------------------------------
-- Vanilla PZ radio TransmitRange lookup table (from radio.txt)
---------------------------------------------------------------

PhobosLib_Radio.TRANSMIT_RANGE = {
    ["Base.WalkieTalkie1"]        = 750,
    ["Base.WalkieTalkie2"]        = 2000,
    ["Base.WalkieTalkie3"]        = 4000,
    ["Base.WalkieTalkie4"]        = 8000,
    ["Base.WalkieTalkie5"]        = 16000,
    ["Base.WalkieTalkieMakeShift"] = 1000,
    ["Base.HamRadio1"]            = 7500,
    ["Base.HamRadio2"]            = 20000,
    ["Base.HamRadioMakeShift"]    = 6000,
    ["Base.ManPackRadio"]         = 20000,
    -- Commercial receivers (listen-only)
    ["Base.RadioBlack"]           = 0,
    ["Base.RadioRed"]             = 0,
    ["Base.RadioMakeShift"]       = 0,
    ["Base.CDplayer"]             = 0,
}

--- Full type → device category mapping (mirrors AZAS deviceTypeMap).
local TYPE_CATEGORY = {
    ["Base.WalkieTalkie1"]        = "handheld",
    ["Base.WalkieTalkie2"]        = "handheld",
    ["Base.WalkieTalkie3"]        = "handheld",
    ["Base.WalkieTalkie4"]        = "handheld",
    ["Base.WalkieTalkie5"]        = "handheld",
    ["Base.WalkieTalkieMakeShift"] = "handheld",
    ["Base.HamRadio1"]            = "ham",
    ["Base.HamRadio2"]            = "ham",
    ["Base.HamRadioMakeShift"]    = "ham",
    ["Base.ManPackRadio"]         = "ham",
    ["Base.RadioBlack"]           = "commercial",
    ["Base.RadioRed"]             = "commercial",
    ["Base.RadioMakeShift"]       = "commercial",
    ["Base.CDplayer"]             = "commercial",
}

---------------------------------------------------------------
-- DeviceData helpers
---------------------------------------------------------------

--- Safely extract DeviceData from a radio object (inventory or world).
---@param radioObj any InventoryItem or IsoWaveSignal
---@return any|nil DeviceData
local function getDeviceData(radioObj)
    if not radioObj then return nil end
    local ok, dd = pcall(function()
        return radioObj:getDeviceData()
    end)
    if ok and dd then return dd end
    return nil
end

---------------------------------------------------------------
-- Public API
---------------------------------------------------------------

--- Get the transmit range (power) of a radio.
--- Works for both inventory items and world-placed radios.
--- Tries DeviceData first, then falls back to the lookup table.
---@param radioObj any InventoryItem or IsoWaveSignal
---@return number TransmitRange value, or 0 for receivers / unknown
function PhobosLib_Radio.getTransmitRange(radioObj)
    if not radioObj then return 0 end

    -- Try DeviceData.getTransmitRange() (may not exist on all builds)
    local dd = getDeviceData(radioObj)
    if dd then
        local ok, range = pcall(function()
            if dd.getTransmitRange then
                return dd:getTransmitRange()
            end
            return nil
        end)
        if ok and range and range > 0 then return range end
    end

    -- Fallback: full type lookup (inventory items)
    if radioObj.getFullType then
        local ok2, fullType = pcall(function() return radioObj:getFullType() end)
        if ok2 and fullType then
            local range = PhobosLib_Radio.TRANSMIT_RANGE[fullType]
            if range then return range end
        end
    end

    return 0
end

--- Get the AZAS-compatible device category for a radio.
--- Returns "ham", "handheld", "commercial", or "tv".
--- Mirrors AZAS_RadioAutotuneServer.getDeviceCategory() logic.
---@param radioObj any InventoryItem or IsoWaveSignal
---@return string category
function PhobosLib_Radio.getDeviceCategory(radioObj)
    if not radioObj then return "commercial" end

    -- Try full type lookup first (fastest for inventory items)
    if radioObj.getFullType then
        local ok, fullType = pcall(function() return radioObj:getFullType() end)
        if ok and fullType and TYPE_CATEGORY[fullType] then
            return TYPE_CATEGORY[fullType]
        end
    end

    -- Fallback: DeviceData property inspection (works for world radios)
    local dd = getDeviceData(radioObj)
    if dd then
        -- Television check
        if dd.getIsTelevision and dd:getIsTelevision() then
            return "tv"
        end

        -- Two-way check (ham vs handheld)
        if dd.getIsTwoWay and dd:getIsTwoWay() then
            if dd.getIsPortable and dd:getIsPortable() then
                return "handheld"
            end
            return "ham"
        end

        -- Channel range heuristic
        local minOk, minRange = pcall(function()
            return dd.getMinChannelRange and dd:getMinChannelRange()
        end)
        local maxOk, maxRange = pcall(function()
            return dd.getMaxChannelRange and dd:getMaxChannelRange()
        end)
        if minOk and maxOk and minRange and maxRange then
            if maxRange <= 120000 then
                return "commercial"
            end
            return "ham"
        end
    end

    return "commercial"
end
