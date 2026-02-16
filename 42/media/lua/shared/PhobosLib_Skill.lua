---------------------------------------------------------------
-- PhobosLib_Skill.lua
-- Generic perk/skill utilities for Project Zomboid Build 42.
-- Provides safe wrappers for perk queries, XP awards, and
-- cross-skill XP mirroring (e.g., awarding Science XP when
-- a custom skill gains XP).
--
-- Part of PhobosLib — shared by all Phobos PZ mods.
---------------------------------------------------------------

PhobosLib = PhobosLib or {}


---------------------------------------------------------------
-- Perk Existence Check
---------------------------------------------------------------

--- Check whether a named perk exists in the Perks table.
--- Useful for verifying if a mod's custom perk is loaded.
---@param perkName string  The perk name (e.g. "AppliedChemistry", "Science")
---@return boolean
function PhobosLib.perkExists(perkName)
    if not perkName then return false end
    local ok, result = pcall(function()
        return Perks and Perks[perkName] ~= nil
    end)
    if ok then return result == true end
    return false
end


---------------------------------------------------------------
-- Safe Perk Level Query
---------------------------------------------------------------

--- Safely get a player's level in a perk.
--- Returns 0 on any failure (nil player, missing perk, API error).
---@param player any       IsoGameCharacter
---@param perkEnum any     A Perks enum value (e.g. Perks.AppliedChemistry)
---@return number          Skill level (0-10), or 0 on failure
function PhobosLib.getPerkLevel(player, perkEnum)
    if not player or not perkEnum then return 0 end
    local ok, level = pcall(function()
        return player:getPerkLevel(perkEnum)
    end)
    if ok and type(level) == "number" then return level end
    return 0
end


---------------------------------------------------------------
-- Safe XP Award
---------------------------------------------------------------

--- Safely award XP to a player for a given perk.
--- Wraps the call in pcall for resilience against API changes.
---@param player any       IsoGameCharacter
---@param perkEnum any     A Perks enum value
---@param amount number    XP amount to award (must be > 0)
---@return boolean         true if XP was successfully awarded
function PhobosLib.addXP(player, perkEnum, amount)
    if not player or not perkEnum or not amount then return false end
    if amount <= 0 then return false end
    local ok = pcall(function()
        player:getXp():AddXP(perkEnum, amount)
    end)
    return ok
end


---------------------------------------------------------------
-- Safe XP Query
---------------------------------------------------------------

--- Safely get a player's current XP total for a perk.
---@param player any       IsoGameCharacter
---@param perkEnum any     A Perks enum value
---@return number          Current XP amount, or 0 on failure
function PhobosLib.getXP(player, perkEnum)
    if not player or not perkEnum then return 0 end
    local ok, xp = pcall(function()
        return player:getXp():getXP(perkEnum)
    end)
    if ok and type(xp) == "number" then return xp end
    return 0
end


---------------------------------------------------------------
-- One-Shot XP Mirroring
---------------------------------------------------------------

--- Award XP to a target perk based on a source amount and ratio.
--- Standalone function — does NOT hook into events.
--- Use registerXPMirror() for persistent event-based mirroring.
---@param player any           IsoGameCharacter
---@param targetPerkEnum any   Target Perks enum value
---@param amount number        Source XP amount
---@param ratio number         Ratio to apply (e.g. 0.5 for 50%)
---@return boolean             true if XP was awarded
function PhobosLib.mirrorXP(player, targetPerkEnum, amount, ratio)
    if not player or not targetPerkEnum then return false end
    if not amount or amount <= 0 then return false end
    ratio = ratio or 1.0
    local mirrorAmount = math.floor(amount * ratio + 0.5)
    if mirrorAmount < 1 then return false end
    return PhobosLib.addXP(player, targetPerkEnum, mirrorAmount)
end


---------------------------------------------------------------
-- Persistent XP Mirror Registration
---------------------------------------------------------------

--- Internal: track registered mirrors and reentrance guard.
local _xpMirrors = {}
local _xpMirrorProcessing = false
local _xpMirrorHookRegistered = false

--- Internal: the Events.AddXP callback that processes all mirrors.
local function _onAddXP(character, perk, amount)
    if _xpMirrorProcessing then return end
    if not perk or not amount or amount <= 0 then return end

    _xpMirrorProcessing = true
    for _, mirror in ipairs(_xpMirrors) do
        if perk == mirror.sourcePerk then
            pcall(function()
                local targetAmount = math.floor(amount * mirror.ratio + 0.5)
                if targetAmount >= 1 and mirror.targetPerk then
                    character:getXp():AddXP(mirror.targetPerk, targetAmount)
                end
            end)
        end
    end
    _xpMirrorProcessing = false
end

--- Register a persistent XP mirror via Events.AddXP.
--- When XP is awarded to sourcePerk, automatically awards
--- ratio × amount to targetPerk (if the target perk exists).
---
--- Call once at game startup. Multiple mirrors can be registered.
--- Includes a reentrance guard to prevent infinite loops.
---
--- Example:
---   PhobosLib.registerXPMirror("AppliedChemistry", "Science", 0.5)
---   -- Now whenever Applied Chemistry gains XP, Science gets 50%.
---
---@param sourcePerkName string  Source perk name (e.g. "AppliedChemistry")
---@param targetPerkName string  Target perk name (e.g. "Science")
---@param ratio number           XP ratio (0.0-1.0+, e.g. 0.5 for 50%)
---@return boolean               true if mirror was registered
function PhobosLib.registerXPMirror(sourcePerkName, targetPerkName, ratio)
    if not sourcePerkName or not targetPerkName then return false end
    if not ratio or ratio <= 0 then return false end

    -- Verify both perks exist
    if not PhobosLib.perkExists(sourcePerkName) then return false end
    if not PhobosLib.perkExists(targetPerkName) then return false end

    local sourcePerk = Perks[sourcePerkName]
    local targetPerk = Perks[targetPerkName]

    -- Check for duplicate registration
    for _, mirror in ipairs(_xpMirrors) do
        if mirror.sourcePerk == sourcePerk and mirror.targetPerk == targetPerk then
            -- Already registered — update ratio
            mirror.ratio = ratio
            return true
        end
    end

    table.insert(_xpMirrors, {
        sourcePerk = sourcePerk,
        targetPerk = targetPerk,
        ratio = ratio,
    })

    -- Register the event hook once (first mirror registration)
    if not _xpMirrorHookRegistered then
        Events.AddXP.Add(_onAddXP)
        _xpMirrorHookRegistered = true
    end

    return true
end
