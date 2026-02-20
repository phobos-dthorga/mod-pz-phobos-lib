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
-- PhobosLib_Hazard.lua
-- Generic PPE detection and health hazard effect dispatch.
-- Part of PhobosLib — shared by all Phobos PZ mods.
--
-- Provides:
--   - Worn item detection (masks, goggles, gloves)
--   - Respiratory protection assessment
--   - Filter degradation on mask items
--   - EHR (Extensive Health Rework) soft-dependency dispatch
--   - Vanilla stat fallback when EHR is not active
--
-- MP: degradeFilterFromInputs operates on recipe items (server context).
--     applyHazardEffect uses player:getStats() (IsoGameCharacter).
-- NPC: getWornItems(), getStats(), Say() all exist on IsoGameCharacter base class.
---------------------------------------------------------------

PhobosLib = PhobosLib or {}


---------------------------------------------------------------
-- Worn Item Detection
---------------------------------------------------------------

--- Scan the player's worn items for any matching full type.
--- Returns the first matching worn item, or nil.
---@param player any          IsoGameCharacter
---@param itemTypes table     List of full type strings (e.g. {"Base.Hat_GasMask"})
---@return any|nil            The worn InventoryItem if found
function PhobosLib.findWornItem(player, itemTypes)
    if not player or not itemTypes then return nil end
    local ok, result = pcall(function()
        local worn = player:getWornItems()
        if not worn then return nil end
        for i = 0, worn:size() - 1 do
            local item = worn:get(i)
            if item then
                local ft = item:getFullType()
                for _, target in ipairs(itemTypes) do
                    if ft == target then return item end
                end
            end
        end
        return nil
    end)
    if ok then return result end
    return nil
end


---------------------------------------------------------------
-- Respiratory Protection Assessment
---------------------------------------------------------------

--- Protection level hierarchy for respiratory masks.
local RESP_HIERARCHY = {
    ["Base.Hat_NBCmask"]                     = "nbc",
    ["Base.Hat_NBCmask_nofilter"]            = "nbc",
    ["Base.Hat_GasMask"]                     = "gasmask",
    ["Base.Hat_GasMask_nofilter"]            = "gasmask",
    ["Base.Hat_BuildersRespirator"]           = "respirator",
    ["Base.Hat_BuildersRespirator_nofilter"]  = "respirator",
    ["Base.Hat_ImprovisedGasMask"]            = "improvised",
    ["Base.Hat_ImprovisedGasMask_nofilter"]   = "improvised",
    ["Base.Hat_DustMask"]                     = "dustmask",
}

--- Items that contain a filter (have a drainable component).
local FILTERED_MASKS = {
    ["Base.Hat_NBCmask"]            = true,
    ["Base.Hat_GasMask"]            = true,
    ["Base.Hat_BuildersRespirator"]  = true,
    ["Base.Hat_ImprovisedGasMask"]   = true,
}

--- Get the respiratory protection status of a player.
--- Scans worn items for known mask types and determines protection level.
---@param player any
---@return table {hasMask=bool, hasFilter=bool, maskItem=item|nil, protectionLevel=string}
function PhobosLib.getRespiratoryProtection(player)
    local result = {hasMask = false, hasFilter = false, maskItem = nil, protectionLevel = "none"}
    if not player then return result end

    local ok, _ = pcall(function()
        local worn = player:getWornItems()
        if not worn then return end
        for i = 0, worn:size() - 1 do
            local item = worn:get(i)
            if item then
                local ft = item:getFullType()
                local level = RESP_HIERARCHY[ft]
                if level then
                    result.hasMask = true
                    result.maskItem = item
                    result.protectionLevel = level
                    result.hasFilter = FILTERED_MASKS[ft] == true
                    return  -- take the first mask found
                end
            end
        end
    end)

    return result
end


---------------------------------------------------------------
-- Filter Degradation
---------------------------------------------------------------

--- Degrade the filter on a mask found in recipe input items.
--- Searches the items ArrayList for a mask matching any of the given types,
--- then reduces its drainable delta. Clamps to 0 (never negative).
---@param items any           Java ArrayList from OnCreate
---@param maskTypes table     List of full type strings to match
---@param amount number       Degradation amount (e.g. 0.025)
---@return boolean            true if degradation was applied
function PhobosLib.degradeFilterFromInputs(items, maskTypes, amount)
    if not items or not maskTypes or not amount then return false end
    if amount <= 0 then return false end

    local ok, applied = pcall(function()
        for i = 0, items:size() - 1 do
            local item = items:get(i)
            if item then
                local ft = item:getFullType()
                for _, target in ipairs(maskTypes) do
                    if ft == target then
                        -- Found the mask — degrade its drainable delta
                        local getDelta = item.getDelta or item.getUsedDelta
                        local setDelta = item.setDelta or item.setUsedDelta
                        if getDelta and setDelta then
                            local current = getDelta(item)
                            if type(current) == "number" then
                                local newDelta = math.max(0, current - amount)
                                setDelta(item, newDelta)
                                return true
                            end
                        end
                        return false
                    end
                end
            end
        end
        return false
    end)

    if ok then return applied == true end
    return false
end


---------------------------------------------------------------
-- EHR (Extensive Health Rework) Detection
---------------------------------------------------------------

--- Check if the EHR mod is active and its disease system is enabled.
--- Uses PhobosLib.isModActive for mod detection and pcall for API safety.
---@return boolean
function PhobosLib.isEHRActive()
    if not PhobosLib.isModActive("EHR") then return false end
    local ok, result = pcall(function()
        if EHR and EHR.Disease and EHR.Disease.IsEnabled then
            return EHR.Disease.IsEnabled() == true
        end
        return false
    end)
    if ok then return result == true end
    return false
end


---------------------------------------------------------------
-- Hazard Effect Dispatch
---------------------------------------------------------------

--- Apply a health hazard effect to a player.
--- Dispatches to EHR disease API if available, otherwise applies vanilla
--- stat penalties as a lightweight fallback.
---
--- All EHR calls are wrapped in pcall for safety against API changes.
---
---@param player any
---@param config table {
---   ehrDisease         = string,    -- EHR disease ID (e.g. "corpse_sickness")
---   ehrChance          = number,    -- Base chance 0.0-1.0
---   ehrSevereDisease   = string|nil,-- Rare severe disease (e.g. "pneumonia")
---   ehrSevereChance    = number|nil,-- Chance for severe (0.0-1.0)
---   vanillaSickness    = number,    -- Vanilla stat delta for sickness
---   vanillaPain        = number,    -- Vanilla stat delta for pain
---   vanillaStress      = number,    -- Vanilla stat delta for stress
---   protectionMultiplier = number,  -- 0.0-1.0, scales all chances (1.0 = no protection)
--- }
function PhobosLib.applyHazardEffect(player, config)
    if not player or not config then return end
    local protMult = config.protectionMultiplier or 1.0

    if PhobosLib.isEHRActive() then
        -- EHR path: trigger diseases with probability
        pcall(function()
            local scaledChance = (config.ehrChance or 0) * protMult
            if scaledChance > 0 and config.ehrDisease then
                EHR.Disease.TryContract(player, config.ehrDisease, scaledChance)
            end
            -- Rare severe disease (chance applied AFTER base trigger)
            if config.ehrSevereDisease and config.ehrSevereChance then
                local severeScaled = config.ehrSevereChance * protMult
                if severeScaled > 0 then
                    EHR.Disease.TryContract(player, config.ehrSevereDisease, severeScaled)
                end
            end
        end)
    else
        -- Vanilla fallback: apply stat penalties directly
        pcall(function()
            local stats = player:getStats()
            if not stats then return end

            local function addStat(statEnum, delta)
                if delta and delta > 0 and statEnum then
                    local current = stats:get(statEnum) or 0
                    stats:set(statEnum, math.min(1, current + (delta * protMult)))
                end
            end

            -- Apply vanilla stat effects
            if CharacterStat then
                addStat(CharacterStat.SICKNESS, config.vanillaSickness)
                addStat(CharacterStat.PAIN, config.vanillaPain)
                addStat(CharacterStat.STRESS, config.vanillaStress)
            end
        end)
    end
end


--- Show a warning speech bubble about hazard exposure.
--- Delegates to PhobosLib.say for the speech bubble.
---@param player any
---@param msg string  Warning message
function PhobosLib.warnHazard(player, msg)
    if not player or not msg then return end
    PhobosLib.say(player, msg)
end
