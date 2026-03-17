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
-- PhobosLib_Quality.lua
-- Generic quality/purity tracking system for crafted items.
-- Uses modData (persistent key-value storage on items) to track
-- a 0-100 quality score through recipe chains.
--
-- Designed to be mod-agnostic: all functions accept configuration
-- as parameters (tier tables, yield tables, modData keys) so any
-- Phobos mod can define its own quality system.
--
-- MP: modData writes sync automatically. ZombRand runs in server-side OnCreate context.
-- NPC: Uses getInventory() and modData — both available on IsoGameCharacter.
--
-- Part of PhobosLib — shared by all Phobos PZ mods.
---------------------------------------------------------------

PhobosLib = PhobosLib or {}


---------------------------------------------------------------
-- OnCreate Items Iteration
---------------------------------------------------------------

--- Safely iterate items from OnCreate callbacks.
--- Handles both Java ArrayList (size/get, pre-42.15) and Lua table/KahluaTable
--- (ipairs, 42.15+) formats. Returns iterator yielding (index, item) pairs.
---@param items any  Items parameter from OnCreate callback
---@return function  Iterator returning (index, item) pairs
function PhobosLib.iterateItems(items)
    if not items then return function() return nil end end
    -- Try Java ArrayList (pre-42.15): has size() and get() methods
    if type(items) == "userdata" then
        local szFn = items.size
        if szFn then
            local ok, sz = pcall(szFn, items)
            if ok and sz and sz > 0 then
                local i = -1
                return function()
                    i = i + 1
                    if i >= sz then return nil end
                    local iok, item = pcall(items.get, items, i)
                    if iok then return i, item end
                    return nil
                end
            end
        end
    end
    -- Try Lua table / KahluaTable (42.15+): use # and numeric indexing
    if type(items) == "table" then
        local i = 0
        local len = #items
        return function()
            i = i + 1
            if i > len then return nil end
            return i - 1, items[i]
        end
    end
    -- Not iterable
    return function() return nil end
end


---------------------------------------------------------------
-- Core Quality Get/Set
---------------------------------------------------------------

--- Read a quality value from an item's modData.
---@param item any       A PZ inventory item
---@param key string     The modData key (e.g. "PCP_Purity")
---@param default number Fallback if key is missing (e.g. 50)
---@return number        Quality value 0-100
function PhobosLib.getQuality(item, key, default)
    local val = PhobosLib.getModDataValue(item, key, default)
    if type(val) ~= "number" then return default end
    return val
end


--- Write a clamped 0-100 quality value to an item's modData.
---@param item any
---@param key string
---@param value number
---@return boolean  true on success
function PhobosLib.setQuality(item, key, value)
    value = math.max(0, math.min(100, math.floor(value + 0.5)))
    return PhobosLib.setModDataValue(item, key, value)
end


---------------------------------------------------------------
-- Tier Lookup
---------------------------------------------------------------

--- Look up the tier name and RGB colour for a quality value.
-- Tiers table must be sorted highest-min-first:
--   { {name="Best", min=80, r=0.4, g=0.6, b=1.0}, {name="Good", min=60, ...}, ... }
---@param value number       The quality value (0-100)
---@param tiers table        Tier definition table
---@return table             {name=string, r=number, g=number, b=number}
function PhobosLib.getQualityTier(value, tiers)
    if not tiers then return {name = "Unknown", r = 1, g = 1, b = 1} end
    for _, tier in ipairs(tiers) do
        if value >= tier.min then
            return {name = tier.name, r = tier.r, g = tier.g, b = tier.b}
        end
    end
    -- Fallback to last tier
    local last = tiers[#tiers]
    if last then return {name = last.name, r = last.r, g = last.g, b = last.b} end
    return {name = "Unknown", r = 1, g = 1, b = 1}
end


---------------------------------------------------------------
-- Input Quality Averaging
---------------------------------------------------------------

--- Average quality across all items in a recipe's consumed inputs.
-- Reads the given modData key from each item that has it.
-- Items without the key are treated as the default value.
---@param items any       Java ArrayList of consumed items from OnCreate
---@param key string      The modData key to read
---@param default number  Default quality for items without the key
---@return number         Average quality (0-100)
function PhobosLib.averageInputQuality(items, key, default)
    if not items then return default end
    local total = 0
    local count = 0
    for i, item in PhobosLib.iterateItems(items) do
        if item then
            local val = PhobosLib.getModDataValue(item, key, nil)
            if val ~= nil and type(val) == "number" then
                total = total + val
                count = count + 1
            else
                -- Check if this is a PZ mod item (has modData capability)
                -- Only count items that could plausibly carry quality
                local md = PhobosLib.getModData(item)
                if md then
                    total = total + default
                    count = count + 1
                end
            end
        end
    end
    if count == 0 then return default end
    return total / count
end


---------------------------------------------------------------
-- Quality Calculation
---------------------------------------------------------------

--- Calculate output quality from input quality, equipment factor, and variance.
--- @deprecated Use calculateOutputQualityV2 for multiplicative skill + variance.
---@param inputQuality number  Average input quality
---@param factor number        Equipment factor (e.g. 0.90 for mortar, 1.25 for chromatograph)
---@param variance number      Random variance range (e.g. 5 for ±5)
---@param skillBonus number    Optional additive bonus from player skill (default 0)
---@return number              Output quality (clamped 0-100)
function PhobosLib.calculateOutputQuality(inputQuality, factor, variance, skillBonus)
    variance = variance or 5
    skillBonus = skillBonus or 0
    local randomOffset = ZombRand(variance * 2 + 1) - variance  -- e.g. -5 to +5
    local result = inputQuality * factor + randomOffset + skillBonus
    return math.max(0, math.min(100, math.floor(result + 0.5)))
end


--- Calculate output quality using multiplicative skill and variance.
--- Formula: clamp(floor(inputQuality * factor * skillMultiplier * varianceMult), 0, 99)
--- where varianceMult = 1.0 + random(-variancePct, +variancePct) / 100.
---@param inputQuality number     Average input quality (0-100)
---@param factor number           Equipment factor (e.g. 0.90 mortar, 1.25 chromatograph)
---@param skillMultiplier number  Multiplicative skill bonus (default 1.0; e.g. 1.44 at L10/Standard)
---@param variancePct number      ±percentage variance (default 15 for ±15%)
---@return number                 Output quality (clamped 0-99)
function PhobosLib.calculateOutputQualityV2(inputQuality, factor, skillMultiplier, variancePct)
    skillMultiplier = skillMultiplier or 1.0
    variancePct     = variancePct or 15
    local varianceRoll = ZombRand(variancePct * 2 + 1) - variancePct  -- e.g. -15 to +15
    local varianceMult = 1.0 + varianceRoll / 100.0                   -- e.g. 0.85 to 1.15
    local result = inputQuality * factor * skillMultiplier * varianceMult
    return math.max(0, math.min(99, math.floor(result + 0.5)))
end


--- Generate a random base quality for source recipes (no tracked inputs).
---@param min number  Minimum quality (e.g. 30)
---@param max number  Maximum quality (e.g. 50)
---@return number     Random quality in [min, max]
function PhobosLib.randomBaseQuality(min, max)
    if min >= max then return min end
    return min + ZombRand(max - min + 1)
end


--- Convert a perk level into a small quality bonus.
--- @deprecated Use getSkillMultiplier for multiplicative skill scaling.
---@param player any       IsoPlayer (or IsoGameCharacter)
---@param perk any         Perks enum value (e.g. Perks.AppliedChemistry)
---@param divisor number   Integer divisor (default 2 → level 10 = +5 bonus)
---@return number          Integer bonus (0-based)
function PhobosLib.getSkillBonus(player, perk, divisor)
    if not player or not perk then return 0 end
    divisor = divisor or 2
    local level = player:getPerkLevel(perk)
    return math.floor(level / divisor)
end


--- Skill-aware variant of randomBaseQuality for source recipes.
--- Adds a small bonus based on the player's skill level.
--- @deprecated Use randomBaseQualityV2 for multiplicative skill + variance.
---@param min number       Minimum quality (e.g. 30)
---@param max number       Maximum quality (e.g. 50)
---@param player any       IsoPlayer
---@param perk any         Perks enum value
---@param divisor number   Skill divisor (default 2)
---@return number          Random quality in [min, max+bonus], capped at 99
function PhobosLib.randomBaseQualityWithSkill(min, max, player, perk, divisor)
    local base = PhobosLib.randomBaseQuality(min, max)
    local bonus = PhobosLib.getSkillBonus(player, perk, divisor)
    return math.min(99, base + bonus)  -- cap at 99 to avoid condition sentinel
end


--- Convert a perk level into a multiplicative quality bonus.
--- Returns a multiplier: 1.0 at level 0, (1.0 + maxEffect) at level 10.
--- Sliding scale: multiplier = 1.0 + (level / 10.0) * maxEffect.
---@param player any       IsoPlayer (or IsoGameCharacter)
---@param perk any         Perks enum value (e.g. Perks.AppliedChemistry)
---@param maxEffect number Maximum effect at level 10 (default 0.66 → ×1.66)
---@return number          Multiplier (≥1.0)
function PhobosLib.getSkillMultiplier(player, perk, maxEffect)
    maxEffect = maxEffect or 0.66
    if not player or not perk or maxEffect <= 0 then return 1.0 end
    local ok, level = pcall(function() return player:getPerkLevel(perk) end)
    if not ok or not level then return 1.0 end
    return 1.0 + (level / 10.0) * maxEffect
end


--- Skill-aware source quality with multiplicative skill and variance.
--- Generates random base in [min, max], applies skill multiplier, then ±variance%.
---@param min number             Minimum quality (e.g. 30)
---@param max number             Maximum quality (e.g. 50)
---@param skillMultiplier number Multiplicative skill bonus (default 1.0)
---@param variancePct number     ±percentage variance (default 15)
---@return number                Random quality, capped at 99
function PhobosLib.randomBaseQualityV2(min, max, skillMultiplier, variancePct)
    skillMultiplier = skillMultiplier or 1.0
    variancePct     = variancePct or 15
    local base = PhobosLib.randomBaseQuality(min, max)
    local varianceRoll = ZombRand(variancePct * 2 + 1) - variancePct
    local varianceMult = 1.0 + varianceRoll / 100.0
    local result = base * skillMultiplier * varianceMult
    return math.max(0, math.min(99, math.floor(result + 0.5)))
end


--- Average condition-percent of stamped items only (condition < conditionMax).
--- Unstamped/vanilla items (condition == conditionMax) are excluded.
--- Designed for condition-based purity tracking where conditionMax is the
--- "unstamped" sentinel value.
---@param items any        Java ArrayList of InventoryItem
---@param default number   Fallback if no stamped items found (default 50)
---@return number          Averaged quality (0-99)
function PhobosLib.averageStampedQuality(items, default)
    default = default or 50
    if not items then return default end
    local total, count = 0, 0
    for i, item in PhobosLib.iterateItems(items) do
        if item then
            local maxCond = item:getConditionMax()
            if maxCond and maxCond > 0 then
                local cond = item:getCondition()
                if cond < maxCond then  -- only stamped items
                    total = total + math.floor(cond / maxCond * 100 + 0.5)
                    count = count + 1
                end
            end
        end
    end
    if count == 0 then return default end
    return math.floor(total / count + 0.5)
end


--- Adjust an equipment factor based on severity setting.
-- Severity 1 (Mild): amplify improvements by 15%, halve degradation.
-- Severity 2 (Standard): no change.
-- Severity 3 (Harsh): halve improvements, amplify degradation by 15%.
---@param factor number    The base equipment factor
---@param severity number  1=Mild, 2=Standard, 3=Harsh
---@return number          Adjusted factor
function PhobosLib.adjustFactorBySeverity(factor, severity)
    if severity == 1 then -- Mild
        if factor > 1.0 then
            return factor * 1.15  -- amplify improvements
        elseif factor < 1.0 then
            return 1.0 - (1.0 - factor) * 0.5  -- halve degradation
        end
    elseif severity == 3 then -- Harsh
        if factor > 1.0 then
            return 1.0 + (factor - 1.0) * 0.5  -- halve improvements
        elseif factor < 1.0 then
            return factor * 0.85  -- amplify degradation
        end
    end
    return factor  -- Standard (2) or neutral (1.0)
end


---------------------------------------------------------------
-- Player Feedback
---------------------------------------------------------------

--- Announce quality via player speech bubble.
---@param player any      The player character
---@param value number    The quality value (0-100)
---@param tiers table     Tier definition table
---@param prefix string   Label prefix (e.g. "Purity", "Quality")
function PhobosLib.announceQuality(player, value, tiers, prefix)
    local tier = PhobosLib.getQualityTier(value, tiers)
    local msg = (prefix or "Quality") .. ": " .. tier.name .. " (" .. tostring(math.floor(value)) .. "%)"
    PhobosLib.say(player, msg)
end


---------------------------------------------------------------
-- Yield and Penalty Functions
---------------------------------------------------------------

--- Look up a yield multiplier from a quality value.
-- Yield table must be sorted highest-min-first:
--   { {min=80, mult=1.00}, {min=60, mult=0.90}, ... }
---@param value number      Quality value (0-100)
---@param yieldTable table  Yield definition table
---@return number           Multiplier (0.0-1.0)
function PhobosLib.getQualityYield(value, yieldTable)
    if not yieldTable then return 1.0 end
    for _, entry in ipairs(yieldTable) do
        if value >= entry.min then
            return entry.mult
        end
    end
    -- Fallback to last entry
    local last = yieldTable[#yieldTable]
    if last then return last.mult end
    return 1.0
end


--- Look up yield multiplier and apply a global sandbox multiplier.
--- Combines tier lookup with server-configurable yield scaling.
---@param value number          Quality value (0-100)
---@param yieldTable table      Yield definition table (sorted highest-min-first)
---@param globalMult number     Global sandbox multiplier (default 1.0)
---@return number               Effective multiplier (clamped ≥0.0)
function PhobosLib.getEffectiveYield(value, yieldTable, globalMult)
    globalMult = globalMult or 1.0
    local baseMult = PhobosLib.getQualityYield(value, yieldTable)
    return math.max(0, baseMult * globalMult)
end


--- Apply a fluid-based yield penalty by draining fluid from a FluidContainer.
-- Used for recipes that output fuel in a can — lower quality = less fuel.
---@param result any        The output item (must have FluidContainer)
---@param value number      Quality value (0-100)
---@param yieldTable table  Yield definition table
function PhobosLib.applyFluidQualityPenalty(result, value, yieldTable)
    local yieldMult = PhobosLib.getQualityYield(value, yieldTable)
    if yieldMult >= 1.0 then return end  -- no penalty

    local fc = PhobosLib.tryGetFluidContainer(result)
    if not fc then return end

    local capacity = PhobosLib.tryGetCapacity(fc) or 5.0
    local drainAmount = capacity * (1.0 - yieldMult)

    if drainAmount > 0 then
        PhobosLib.tryDrainFluid(fc, drainAmount)
    end
end


--- Remove excess items from player inventory for yield penalties.
-- Used for recipes that output N discrete items (e.g. 10 GunPowder)
-- where low quality means fewer should be kept.
---@param player any        The player character
---@param itemType string   Full item type (e.g. "Base.GunPowder")
---@param baseCount number  How many items the recipe nominally produces
---@param keepCount number  How many items to keep (rest are removed)
function PhobosLib.removeExcessItems(player, itemType, baseCount, keepCount)
    local removeCount = baseCount - keepCount
    if removeCount <= 0 then return end
    if not player then return end

    local ok, _ = pcall(function()
        local inv = player:getInventory()
        if not inv then return end
        local items = inv:getItems()
        local removed = 0
        -- Remove from END of inventory (most recently added by recipe)
        for i = items:size() - 1, 0, -1 do
            if removed >= removeCount then break end
            local it = items:get(i)
            if it and it:getFullType() == itemType then
                inv:Remove(it)
                removed = removed + 1
            end
        end
    end)
end


--- Stamp a modData quality value on recently-filled FluidContainers by fluid name.
--- B42's `+fluid` recipe syntax fills generic containers (EmptyJar, Bucket, etc.)
--- with named fluids. Since OnCreate's `result` no longer references these filled
--- containers, this function scans inventory for containers holding the named fluid
--- and stamps modData on up to `count` unstamped matches.
---
--- Companion to recoverDrainedFluidQuality(): stamp fills containers after crafting,
--- recover reads them when a downstream recipe drains the fluid.
---
---@param player any        The player character
---@param fluidName string  The fluid name to search for (e.g. "CrudeBiodiesel")
---@param modDataKey string The modData key to stamp (e.g. "PCP_Purity_CrudeBiodiesel")
---@param value number      The quality value to stamp (0-100)
---@param count number      Max containers to stamp (e.g. 3 for 3× jar outputs)
---@return number           Number of containers actually stamped
function PhobosLib.stampFluidContainerQuality(player, fluidName, modDataKey, value, count)
    if not player or not fluidName or not modDataKey then return 0 end
    count = count or 1
    local stamped = 0
    pcall(function()
        local inv = player:getInventory()
        if not inv then return end
        local items = inv:getItems()
        for i = 0, items:size() - 1 do
            if stamped >= count then break end
            local it = items:get(i)
            if it then
                local fc = PhobosLib.tryGetFluidContainer(it)
                if fc then
                    local fname = PhobosLib.tryGetFluidName(fc)
                    if fname and fname == fluidName then
                        -- Only stamp if not already stamped (avoid double-counting)
                        local existing = PhobosLib.getModDataValue(it, modDataKey, nil)
                        if existing == nil then
                            PhobosLib.setModDataValue(it, modDataKey, value)
                            stamped = stamped + 1
                        end
                    end
                end
            end
        end
    end)
    return stamped
end


--- Recover a quality value from a recently-drained FluidContainer's modData.
--- B42's `-fluid` recipe syntax drains fluid from containers without consuming
--- them, so OnCreate's `items` list does not include the drained container.
--- This scans inventory for items carrying the given modData key, preferring
--- empty/drained FluidContainers (recently drained) over full ones.
--- Reads the first match and removes the key to prevent double-counting.
---
--- Companion to averageInputQuality(): use averageInputQuality for `item`
--- inputs (consumed, present in OnCreate items list), and this function
--- for `-fluid` inputs (drained, NOT present in OnCreate items list).
---
---@param player any        The player character
---@param modDataKey string The modData key to search for (e.g. "PCP_FluidPurity")
---@param default number    Fallback if no match found
---@return number           The recovered quality value, or default
function PhobosLib.recoverDrainedFluidQuality(player, modDataKey, default)
    if not player then return default end
    local result = default
    pcall(function()
        local inv = player:getInventory()
        if not inv then return end
        local items = inv:getItems()

        -- Two-pass: prefer empty/drained FluidContainers, fall back to any match
        local drainedMatch, anyMatch
        for i = 0, items:size() - 1 do
            local it = items:get(i)
            if it then
                local md = PhobosLib.getModData(it)
                if md and md[modDataKey] ~= nil then
                    anyMatch = anyMatch or it
                    local fc = PhobosLib.tryGetFluidContainer(it)
                    if fc and (PhobosLib.tryGetAmount(fc) or 0) < 0.01 then
                        drainedMatch = it
                        break
                    end
                end
            end
        end

        local target = drainedMatch or anyMatch
        if target then
            local md = PhobosLib.getModData(target)
            local val = md[modDataKey]
            md[modDataKey] = nil  -- cleanup to prevent double-counting
            if type(val) == "number" then result = val end
        end
    end)
    return result
end


--- Stamp quality on all unstamped items of a given type in player inventory.
-- Handles multi-output recipes where OnCreate only receives the first result.
---@param player any         The player character
---@param resultType string  Full item type to stamp
---@param key string         The modData key
---@param value number       The quality value to stamp
function PhobosLib.stampAllOutputs(player, resultType, key, value)
    if not player then return end
    local ok, _ = pcall(function()
        local inv = player:getInventory()
        if not inv then return end
        local items = inv:getItems()
        for i = 0, items:size() - 1 do
            local it = items:get(i)
            if it and it:getFullType() == resultType then
                local existing = PhobosLib.getModDataValue(it, key, nil)
                if existing == nil then
                    PhobosLib.setQuality(it, key, value)
                end
            end
        end
    end)
end
