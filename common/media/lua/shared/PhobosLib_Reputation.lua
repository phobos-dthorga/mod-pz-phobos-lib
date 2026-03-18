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
-- PhobosLib_Reputation.lua
-- Generic modData-backed reputation system for Phobos mods.
--
-- Supports multiple independent reputation tracks keyed by
-- modKey (e.g. "POS" for POSnet, "PIP" for Pathology).
-- Values are clamped integers stored in player modData.
---------------------------------------------------------------

PhobosLib = PhobosLib or {}

--- ModData key prefix for reputation storage.
local PREFIX = "PhobosLib_Reputation_"

--- Get a player's reputation for a given mod key.
---@param player any IsoPlayer
---@param modKey string Mod identifier (e.g. "POS")
---@param default number|nil Default value if not set (default 0)
---@return number Current reputation (integer)
function PhobosLib.getPlayerReputation(player, modKey, default)
    if not player or not modKey then return default or 0 end
    local md = player:getModData()
    if not md then return default or 0 end
    local val = md[PREFIX .. modKey]
    if val == nil then return default or 0 end
    return math.floor(val)
end

--- Set a player's reputation for a given mod key.
--- Value is clamped between minCap and maxCap.
---@param player any IsoPlayer
---@param modKey string Mod identifier
---@param value number New reputation value
---@param minCap number|nil Minimum allowed (default 0)
---@param maxCap number|nil Maximum allowed (default 999999)
function PhobosLib.setPlayerReputation(player, modKey, value, minCap, maxCap)
    if not player or not modKey then return end
    local md = player:getModData()
    if not md then return end
    local min = minCap or 0
    local max = maxCap or 999999
    local clamped = math.floor(math.max(min, math.min(max, value)))
    md[PREFIX .. modKey] = clamped
end

--- Add (or subtract) reputation for a player.
--- Result is clamped between minCap and maxCap.
---@param player any IsoPlayer
---@param modKey string Mod identifier
---@param delta number Amount to add (negative to subtract)
---@param minCap number|nil Minimum allowed (default 0)
---@param maxCap number|nil Maximum allowed (default 999999)
---@return number New reputation value after clamping
function PhobosLib.addPlayerReputation(player, modKey, delta, minCap, maxCap)
    if not player or not modKey then return 0 end
    local current = PhobosLib.getPlayerReputation(player, modKey, 0)
    local newVal = current + (delta or 0)
    PhobosLib.setPlayerReputation(player, modKey, newVal, minCap, maxCap)
    return PhobosLib.getPlayerReputation(player, modKey, 0)
end
