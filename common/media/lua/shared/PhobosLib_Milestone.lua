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
-- PhobosLib_Milestone.lua
-- Generic, mod-agnostic milestone tracker with per-player
-- persistence via modData and multiplayer sync.
-- Any Phobos mod can register, award, and query milestones.
---------------------------------------------------------------

local MODDATA_PREFIX = "PhobosLib_ms_"

--- Internal registry: milestones[modId][milestoneId] = { labelKey, group }
local milestones = {}

---------------------------------------------------------------
-- Registration
---------------------------------------------------------------

--- Register a named milestone for a mod.
--- No-op if already registered.
---@param modId string Mod identifier (e.g. "POS", "PCP")
---@param milestoneId string Unique milestone name within the mod
---@param options table|nil { labelKey = string, group = string|nil }
function PhobosLib.registerMilestone(modId, milestoneId, options)
    if not modId or not milestoneId then return end
    milestones[modId] = milestones[modId] or {}
    if milestones[modId][milestoneId] then return end -- already registered

    milestones[modId][milestoneId] = {
        labelKey = options and options.labelKey or nil,
        group = options and options.group or nil,
    }
end

---------------------------------------------------------------
-- Award & Query
---------------------------------------------------------------

--- Build the modData key for a milestone.
---@param modId string
---@param milestoneId string
---@return string
local function buildKey(modId, milestoneId)
    return MODDATA_PREFIX .. modId .. "_" .. milestoneId
end

--- Award a milestone to a player.
--- Returns true on first award, false if already earned.
--- Fires triggerEvent("PhobosLib_MilestoneAwarded", player, modId, milestoneId)
--- on first award. Calls transmitModData() for MP sync.
---@param player IsoPlayer
---@param modId string
---@param milestoneId string
---@return boolean newlyAwarded
function PhobosLib.awardMilestone(player, modId, milestoneId)
    if not player or not modId or not milestoneId then return false end

    local key = buildKey(modId, milestoneId)
    local modData = player:getModData()
    if not modData then return false end

    -- Already awarded?
    if modData[key] then return false end

    -- Award: store the game day
    local day = 0
    pcall(function()
        day = getGameTime():getNightsSurvived()
    end)
    modData[key] = day > 0 and day or 1

    -- MP sync
    pcall(function()
        player:transmitModData()
    end)

    -- Fire event for decoupled listeners
    pcall(function()
        triggerEvent("PhobosLib_MilestoneAwarded", player, modId, milestoneId)
    end)

    PhobosLib.debug("PhobosLib", "[Milestone]",
        "Awarded: " .. modId .. "." .. milestoneId .. " (day " .. tostring(modData[key]) .. ")")

    return true
end

--- Check if a player has earned a milestone.
---@param player IsoPlayer
---@param modId string
---@param milestoneId string
---@return boolean
function PhobosLib.hasMilestone(player, modId, milestoneId)
    if not player or not modId or not milestoneId then return false end
    local modData = player:getModData()
    if not modData then return false end
    return modData[buildKey(modId, milestoneId)] ~= nil
end

--- Get the game day a milestone was awarded.
---@param player IsoPlayer
---@param modId string
---@param milestoneId string
---@return number|nil Game day, or nil if not yet earned
function PhobosLib.getMilestoneDay(player, modId, milestoneId)
    if not player or not modId or not milestoneId then return nil end
    local modData = player:getModData()
    if not modData then return nil end
    local val = modData[buildKey(modId, milestoneId)]
    return val and tonumber(val) or nil
end

--- Count completed and total milestones for a mod.
---@param player IsoPlayer
---@param modId string
---@return number completed, number total
function PhobosLib.countMilestones(player, modId)
    if not modId then return 0, 0 end
    local registered = milestones[modId]
    if not registered then return 0, 0 end

    local total = 0
    local completed = 0
    for msId in pairs(registered) do
        total = total + 1
        if PhobosLib.hasMilestone(player, modId, msId) then
            completed = completed + 1
        end
    end
    return completed, total
end

--- Get all completed milestones for a mod.
---@param player IsoPlayer
---@param modId string
---@return table Array of { milestoneId = string, awardedDay = number }
function PhobosLib.getMilestones(player, modId)
    if not player or not modId then return {} end
    local registered = milestones[modId]
    if not registered then return {} end

    local result = {}
    for msId in pairs(registered) do
        local day = PhobosLib.getMilestoneDay(player, modId, msId)
        if day then
            result[#result + 1] = { milestoneId = msId, awardedDay = day }
        end
    end
    return result
end
