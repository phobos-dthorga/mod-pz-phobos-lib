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
-- Provides transmit range lookup, device category detection,
-- and radio proximity scanning for both inventory items and
-- world-placed radio objects.
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
    -- Television sets (listen-only, grid-powered)
    ["Base.TvAntique"]            = 0,
    ["Base.TvBlack"]              = 0,
    ["Base.TvWideScreen"]         = 0,
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
    ["Base.TvAntique"]            = "tv",
    ["Base.TvBlack"]              = "tv",
    ["Base.TvWideScreen"]         = "tv",
}

---------------------------------------------------------------
-- Defaults
---------------------------------------------------------------

--- Default tile radius for world radio scanning.
PhobosLib_Radio.DEFAULT_SCAN_RADIUS = 20

--- Default minimum volume for a radio to count as hearable.
PhobosLib_Radio.DEFAULT_MIN_VOLUME  = 0.01

---------------------------------------------------------------
-- DeviceData helpers
---------------------------------------------------------------

--- Safely extract DeviceData from a radio object (inventory or world).
---@param radioObj any InventoryItem or IsoWaveSignal
---@return any|nil DeviceData
function PhobosLib_Radio.getDeviceData(radioObj)
    if not radioObj then return nil end
    -- Pre-filter: only Radio (inventory) and IsoWaveSignal (world) items
    -- have valid getDeviceData(). Calling it on other PZ objects throws
    -- Java RuntimeExceptions that Kahlua pcall cannot catch.
    if not instanceof(radioObj, "Radio") and not instanceof(radioObj, "IsoWaveSignal") then
        return nil
    end
    local ok, dd = pcall(function()
        return radioObj:getDeviceData()
    end)
    if ok and dd then return dd end
    return nil
end

--- Keep a local alias for internal use.
local function getDeviceData(radioObj)
    return PhobosLib_Radio.getDeviceData(radioObj)
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

---------------------------------------------------------------
-- Television detection
---------------------------------------------------------------

--- Check whether a radio object is a television set.
--- Uses TYPE_CATEGORY lookup first (fastest), falls back to
--- DeviceData.getIsTelevision() for unregistered types.
---@param radioObj any InventoryItem or IsoWaveSignal
---@return boolean
function PhobosLib_Radio.isTelevision(radioObj)
    if not radioObj then return false end
    -- Fast path: full type lookup
    if radioObj.getFullType then
        local ok, fullType = pcall(function() return radioObj:getFullType() end)
        if ok and fullType and TYPE_CATEGORY[fullType] == "tv" then
            return true
        end
    end
    -- Fallback: DeviceData property
    local dd = getDeviceData(radioObj)
    if dd and dd.getIsTelevision then
        local ok, isTV = pcall(function() return dd:getIsTelevision() end)
        if ok and isTV then return true end
    end
    return false
end

---------------------------------------------------------------
-- Receiver quality
---------------------------------------------------------------

--- Check whether an item's full type contains "MakeShift" (case-sensitive).
---@param radioObj any  InventoryItem or IsoWaveSignal
---@return boolean
local function isMakeshift(radioObj)
    if not radioObj or not radioObj.getFullType then return false end
    local ok, fullType = pcall(function() return radioObj:getFullType() end)
    if not ok or not fullType then return false end
    return fullType:find("MakeShift") ~= nil
end

--- Compute a receiver quality factor for a radio device.
--- Lower factor = better reception (0.0 = perfect, 1.0 = no benefit).
--- The factor is used as a multiplier on the ecology dropout rate.
---
--- opts fields (all required — PhobosLib has no built-in defaults):
---   profileLookup   function(fullType) → profile|nil  Registry callback
---   rangeNormaliser  number   Max transmit range for normalisation (e.g. 20000)
---   rangeWeight      number   How much range contributes to quality (e.g. 0.70)
---   hamBonus         number   Subtracted from factor for ham category (e.g. 0.10)
---   makeshiftPenalty number   Added to factor for makeshift items (e.g. 0.15)
---   commercialBase   number   Fixed factor for 0-range commercial/tv (e.g. 0.75)
---   factorMin        number   Absolute floor (e.g. 0.20)
---   factorMax        number   Absolute ceiling (e.g. 0.95)
---   conditionWeight  number   Minimum condition multiplier at 0% (e.g. 0.50)
---
---@param radioObj any   InventoryItem or IsoWaveSignal
---@param opts table     Tuning constants (see above)
---@return number factor Quality factor [factorMin..factorMax]
function PhobosLib_Radio.getReceiverQualityFactor(radioObj, opts)
    if not radioObj or not opts then
        return opts and opts.factorMax or 1.0
    end

    local factor

    -- 1. Try profile lookup (data-pack driven, exact per-type override)
    local fullType
    if radioObj.getFullType then
        local ok, ft = pcall(function() return radioObj:getFullType() end)
        if ok then fullType = ft end
    end
    if fullType and opts.profileLookup then
        local profile = opts.profileLookup(fullType)
        if profile and profile.baseFactor then
            factor = profile.baseFactor
        end
    end

    -- 2. Fallback: formula-based calculation for unregistered types
    if not factor then
        local transmitRange = PhobosLib_Radio.getTransmitRange(radioObj)
        local category = PhobosLib_Radio.getDeviceCategory(radioObj)

        if (category == "commercial" or category == "tv") and transmitRange == 0 then
            factor = opts.commercialBase or 0.75
        else
            local rangeNorm = PhobosLib.clamp(
                transmitRange / (opts.rangeNormaliser or 20000), 0, 1)
            factor = 1.0 - rangeNorm * (opts.rangeWeight or 0.70)

            if category == "ham" then
                factor = factor - (opts.hamBonus or 0.10)
            end
        end

        if isMakeshift(radioObj) then
            factor = factor + (opts.makeshiftPenalty or 0.15)
        end
    end

    -- 3. Item condition scaling
    local condWeight = opts.conditionWeight or 0.50
    if PhobosLib.getItemCondition then
        local condition = PhobosLib.getItemCondition(radioObj)
        if condition and condition >= 0 then
            -- conditionMult ranges from condWeight (wrecked) to 1.0 (pristine)
            local conditionMult = condWeight + (1.0 - condWeight) * condition
            factor = factor / conditionMult
        end
    end

    -- 4. Clamp to bounds
    local fMin = opts.factorMin or 0.20
    local fMax = opts.factorMax or 0.95
    return PhobosLib.clamp(factor, fMin, fMax)
end

---------------------------------------------------------------
-- Radio proximity detection
---------------------------------------------------------------

--- Check whether a DeviceData represents a powered, unmuted radio
--- tuned to a matching frequency.
---@param dd any          DeviceData from a radio
---@param opts table      { frequencyMatch, minVolume }
---@return boolean match
---@return any|nil matchResult   Return value from frequencyMatch
local function isRadioQualified(dd, opts)
    if not dd then return false, nil end

    -- Must be turned on
    local okOn, isOn = pcall(function() return dd:getIsTurnedOn() end)
    if not okOn or not isOn then return false, nil end

    -- Must be audible (volume above threshold)
    local okVol, volume = pcall(function() return dd:getDeviceVolume() end)
    if okVol and volume and volume <= (opts.minVolume or PhobosLib_Radio.DEFAULT_MIN_VOLUME) then
        return false, nil
    end

    -- Must have power (battery or grid)
    local hasPower = false
    pcall(function()
        if dd:getIsBatteryPowered() then
            local power = dd:getPower()
            if power and power > 0 then
                hasPower = true
            end
        end
    end)
    if not hasPower then
        pcall(function()
            local parent = dd:getParent()
            if parent then
                local sq = parent:getSquare()
                if sq and PhobosLib.hasPower(sq) then
                    hasPower = true
                end
            end
        end)
    end
    if not hasPower then return false, nil end

    -- Must match the caller's frequency filter
    if opts.frequencyMatch then
        local okCh, channel = pcall(function()
            if dd.getChannel then return dd:getChannel() end
            if dd.getFrequency then return dd:getFrequency() end
            return nil
        end)
        if not okCh or not channel then return false, nil end
        local matchResult = opts.frequencyMatch(channel)
        if not matchResult then return false, nil end
        return true, matchResult
    end

    return true, nil
end

--- Find the first powered, tuned, audible radio near a player.
--- Searches inventory radios, nearby world radios, and vehicle radios
--- in that order. Returns on the first qualifying match.
---
--- opts fields:
---   frequencyMatch  function(channel) → truthy|nil  Caller's frequency filter
---   scanRadius      number  Tile radius for world radios (default 20)
---   minVolume       number  Minimum getDeviceVolume() (default 0.01)
---
---@param player any       IsoPlayer
---@param opts table       Search options
---@return any|nil radioObj   The qualifying radio object, or nil
---@return any|nil dd         Its DeviceData, or nil
function PhobosLib_Radio.findNearbyTunedRadio(player, opts)
    if not player then return nil, nil end
    opts = opts or {}

    -- 1. Inventory radios (on person — always within hearing range if audible)
    local okInv, inv = pcall(function() return player:getInventory() end)
    if okInv and inv then
        local okItems, items = pcall(function() return inv:getItems() end)
        if okItems and items then
            for i = 0, items:size() - 1 do
                local item = items:get(i)
                if instanceof(item, "Radio") then
                    local dd = getDeviceData(item)
                    if dd then
                        local qualified, matchResult = isRadioQualified(dd, opts)
                        if qualified then return item, dd end
                    end
                end
            end
        end
    end

    -- 2. World radios (IsoWaveSignal objects in nearby tiles)
    local playerSquare = PhobosLib.getSquareFromPlayer(player)
    if playerSquare then
        local scanRadius = opts.scanRadius or PhobosLib_Radio.DEFAULT_SCAN_RADIUS
        local foundRadio, foundDD
        PhobosLib.scanNearbySquares(playerSquare, scanRadius, function(sq)
            local okObjs, objects = pcall(function() return sq:getObjects() end)
            if not okObjs or not objects then return false end
            for j = 0, objects:size() - 1 do
                local obj = objects:get(j)
                if instanceof(obj, "IsoWaveSignal")
                        and not PhobosLib_Radio.isTelevision(obj) then
                    local dd = getDeviceData(obj)
                    if dd then
                        local qualified, matchResult = isRadioQualified(dd, opts)
                        if qualified then
                            -- Use vanilla hearing check as final authority
                            local okHear, inRange = pcall(function()
                                return obj:HasPlayerInRange()
                            end)
                            if okHear and inRange then
                                foundRadio = obj
                                foundDD = dd
                                return true -- stop scanning
                            end
                        end
                    end
                end
            end
            return false
        end)
        if foundRadio then return foundRadio, foundDD end
    end

    -- 3. Vehicle radios (player seated in vehicle)
    local okVeh, vehicle = pcall(function() return player:getVehicle() end)
    if okVeh and vehicle then
        local okPart, radioPart = pcall(function()
            return vehicle:getPartById("Radio")
        end)
        if okPart and radioPart then
            local okItem, radioItem = pcall(function()
                return radioPart:getInventoryItem()
            end)
            if okItem and radioItem then
                local dd = getDeviceData(radioItem)
                if dd then
                    local qualified, matchResult = isRadioQualified(dd, opts)
                    if qualified then return radioItem, dd end
                end
            end
        end
    end

    return nil, nil
end
