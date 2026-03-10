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
-- PhobosLib_Moodle.lua
-- Client-side wrapper for the Moodle Framework soft dependency.
--
-- Provides a safe, generic API for registering custom moodles,
-- setting/clearing/stacking values, and auto-decaying them
-- over game time.
--
-- All functions no-op gracefully when Moodle Framework is
-- absent — consuming mods never need to guard calls.
--
-- Moodle Framework: Workshop ID 3396446795
--   API: MF.createMoodle(name), MF.getMoodle(name, playerNum)
--   Values: 0.0-1.0, where 0.5 = neutral (no moodle shown)
--          >0.5 = good moodle levels, <0.5 = bad moodle levels
--
-- Time model:
--   Decay durations are in GAME MINUTES (not real-time).
--   1 game day = 1 real hour at default Day Length.
--   getGameTime():getWorldAgeHours() accounts for all
--   Day Length multiplier settings automatically.
--
-- Part of PhobosLib >= 1.17.0
---------------------------------------------------------------

PhobosLib = PhobosLib or {}

local _TAG = "[PhobosLib:Moodle]"

---------------------------------------------------------------
-- Internal state
---------------------------------------------------------------

--- Cached Moodle Framework detection result.
local _mfChecked = false
local _mfActive  = false

--- Active decay entries, keyed by "playerNum:moodleName".
--- Each entry: {startTime, startValue, endTime, playerNum, moodleName}
local _decayEntries = {}

--- Whether the EveryOneMinute decay tick has been installed.
local _tickInstalled = false

---------------------------------------------------------------
-- Internal helpers
---------------------------------------------------------------

--- Build the decay registry key for a (playerNum, moodleName) pair.
---@param playerNum number
---@param name string
---@return string
local function decayKey(playerNum, name)
    return tostring(playerNum) .. ":" .. name
end

--- Apply a value to a Moodle Framework moodle, safely.
--- All MF API calls are pcall-wrapped against version changes.
---@param playerNum number
---@param name string
---@param value number  0.0-1.0
local function applyMoodleValue(playerNum, name, value)
    pcall(function()
        local moodle = MF.getMoodle(name, playerNum)
        if moodle then
            moodle:setValue(value)
        end
    end)
end

--- Install the EveryOneMinute decay tick (once).
--- Linearly interpolates each active entry from startValue → 0.5
--- over [startTime, endTime] world-age hours, then removes it.
local function installDecayTick()
    if _tickInstalled then return end
    _tickInstalled = true

    Events.EveryOneMinute.Add(function()
        if not _mfActive then return end

        local ok, now = pcall(function()
            return getGameTime():getWorldAgeHours()
        end)
        if not ok or not now then return end

        local toRemove = {}

        for key, entry in pairs(_decayEntries) do
            if now >= entry.endTime then
                -- Decay complete: reset to neutral
                applyMoodleValue(entry.playerNum, entry.moodleName, 0.5)
                table.insert(toRemove, key)
            else
                -- Linear interpolation: startValue → 0.5
                local duration = entry.endTime - entry.startTime
                if duration > 0 then
                    local elapsed = now - entry.startTime
                    local t = elapsed / duration
                    local current = entry.startValue + (0.5 - entry.startValue) * t
                    applyMoodleValue(entry.playerNum, entry.moodleName, current)
                end
            end
        end

        for _, key in ipairs(toRemove) do
            _decayEntries[key] = nil
        end
    end)

    print(_TAG .. " decay tick installed")
end

---------------------------------------------------------------
-- Public API
---------------------------------------------------------------

--- Check if the Moodle Framework mod is active.
--- Result is cached after the first call.
---@return boolean  true if MoodleFramework is loaded
function PhobosLib.isMoodleFrameworkActive()
    if _mfChecked then return _mfActive end
    _mfChecked = true

    local ok, result = pcall(function()
        return getActivatedMods():contains("MoodleFramework")
    end)
    _mfActive = ok and result == true

    if _mfActive then
        print(_TAG .. " Moodle Framework detected")
    end

    return _mfActive
end


--- Register a custom moodle via Moodle Framework.
--- No-ops gracefully if Moodle Framework is not available.
---
---@param config table  Configuration:
---   name     (string)   Moodle identifier (e.g. "Medicated")       [required]
---   goodOnly (boolean)  If true, only good (>0.5) levels are used  [optional]
function PhobosLib.registerMoodle(config)
    if not PhobosLib.isMoodleFrameworkActive() then return end
    if not config or not config.name then
        print(_TAG .. " registerMoodle: config.name required")
        return
    end

    pcall(function()
        require "MF_ISMoodle"
        MF.createMoodle(config.name)
        print(_TAG .. " registered moodle: " .. config.name)
    end)
end


--- Set a moodle value with auto-decay back to neutral (0.5).
--- The value decays linearly over durationMinutes game minutes.
--- No-ops if Moodle Framework is not active.
---
---@param playerNum number        Player index (0-based; 0 for SP)
---@param name string             Moodle name (must be registered first)
---@param value number            Target value (0.0-1.0; >0.5 for good moodles)
---@param durationMinutes number  Decay duration in game minutes
function PhobosLib.setMoodleValue(playerNum, name, value, durationMinutes)
    if not PhobosLib.isMoodleFrameworkActive() then return end
    if not name or not value then return end
    playerNum = playerNum or 0
    durationMinutes = durationMinutes or 60

    -- Apply value immediately
    applyMoodleValue(playerNum, name, value)

    -- Register decay entry
    local ok, now = pcall(function()
        return getGameTime():getWorldAgeHours()
    end)
    if not ok or not now then return end

    local durationHours = durationMinutes / 60.0
    local key = decayKey(playerNum, name)
    _decayEntries[key] = {
        startTime  = now,
        startValue = value,
        endTime    = now + durationHours,
        playerNum  = playerNum,
        moodleName = name,
    }

    -- Install tick on first use
    installDecayTick()
end


--- Get the current value of a custom moodle.
--- Returns 0.5 (neutral) if Moodle Framework is absent or moodle not found.
---
---@param playerNum number  Player index (0-based)
---@param name string       Moodle name
---@return number           Current value (0.0-1.0), 0.5 if unavailable
function PhobosLib.getMoodleValue(playerNum, name)
    if not PhobosLib.isMoodleFrameworkActive() then return 0.5 end
    if not name then return 0.5 end
    playerNum = playerNum or 0

    local ok, result = pcall(function()
        local moodle = MF.getMoodle(name, playerNum)
        if moodle then
            return moodle:getValue()
        end
        return 0.5
    end)
    if ok and type(result) == "number" then return result end
    return 0.5
end


--- Clear a moodle back to neutral (0.5) and cancel any pending decay.
---
---@param playerNum number  Player index (0-based)
---@param name string       Moodle name
function PhobosLib.clearMoodle(playerNum, name)
    if not name then return end
    playerNum = playerNum or 0

    -- Cancel decay
    local key = decayKey(playerNum, name)
    _decayEntries[key] = nil

    -- Reset to neutral
    if PhobosLib.isMoodleFrameworkActive() then
        applyMoodleValue(playerNum, name, 0.5)
    end
end


--- Stack a moodle value: apply only if higher than current.
--- If the new value exceeds the current moodle value, it is applied
--- and the decay timer starts fresh. Otherwise, no change is made
--- (the existing stronger effect continues its own decay).
---
---@param playerNum number        Player index (0-based)
---@param name string             Moodle name
---@param value number            Target value (0.0-1.0)
---@param durationMinutes number  Decay duration in game minutes
function PhobosLib.stackMoodleValue(playerNum, name, value, durationMinutes)
    if not PhobosLib.isMoodleFrameworkActive() then return end
    if not name or not value then return end
    playerNum = playerNum or 0

    local current = PhobosLib.getMoodleValue(playerNum, name)
    if value > current then
        PhobosLib.setMoodleValue(playerNum, name, value, durationMinutes)
    end
end


print(_TAG .. " loaded")
