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
    local ok, _ = pcall(function()
        for i = 0, items:size() - 1 do
            local item = items:get(i)
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
    end)
    if count == 0 then return default end
    return total / count
end


---------------------------------------------------------------
-- Quality Calculation
---------------------------------------------------------------

--- Calculate output quality from input quality, equipment factor, and variance.
---@param inputQuality number  Average input quality
---@param factor number        Equipment factor (e.g. 0.90 for mortar, 1.25 for chromatograph)
---@param variance number      Random variance range (e.g. 5 for ±5)
---@return number              Output quality (clamped 0-100)
function PhobosLib.calculateOutputQuality(inputQuality, factor, variance)
    variance = variance or 5
    local randomOffset = ZombRand(variance * 2 + 1) - variance  -- e.g. -5 to +5
    local result = inputQuality * factor + randomOffset
    return math.max(0, math.min(100, math.floor(result + 0.5)))
end


--- Generate a random base quality for source recipes (no tracked inputs).
---@param min number  Minimum quality (e.g. 30)
---@param max number  Maximum quality (e.g. 50)
---@return number     Random quality in [min, max]
function PhobosLib.randomBaseQuality(min, max)
    if min >= max then return min end
    return min + ZombRand(max - min + 1)
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
