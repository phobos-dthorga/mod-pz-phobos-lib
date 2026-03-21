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
-- PhobosLib_Util.lua
-- General-purpose utility functions for Project Zomboid B42 mods.
-- Written fresh for PhobosLib v1.0.0.
---------------------------------------------------------------

PhobosLib = PhobosLib or {}


--- Safe getText wrapper — returns the key itself on failure.
--- Wraps PZ's getText() in pcall to prevent crashes on missing keys.
---@param key string Translation key
---@return string
function PhobosLib.safeGetText(key, ...)
    local ok, result = PhobosLib.safecall(getText, key, ...)
    if ok and result then return result end
    return key
end


--- Safe lowercase conversion. Returns "" for nil/non-string input.
---@param s any
---@return string
function PhobosLib.lower(s)
    return string.lower(tostring(s or ""))
end


--- Split a string by a literal single-character separator.
--- Unlike PZ's global splitString(input, maxSize) which takes an int,
--- this splits on an actual delimiter character.
---@param str string  Input string
---@param sep string  Single-character separator (e.g. "|")
---@return string[]   List of parts (may be empty)
function PhobosLib.split(str, sep)
    if type(str) ~= "string" then return {} end
    if type(sep) ~= "string" or sep == "" then return { str } end
    local parts = {}
    local pattern = "([^" .. sep .. "]*)"
    for part in string.gmatch(str .. sep, pattern) do
        parts[#parts + 1] = part
    end
    -- gmatch produces a trailing empty from the appended sep; trim it
    if #parts > 0 and parts[#parts] == "" then
        parts[#parts] = nil
    end
    return parts
end


--- Safe method call via pcall. Returns ok, result.
---@param obj any       The object to call the method on
---@param methodName string  The method name to call
---@return boolean ok, any result
function PhobosLib.pcallMethod(obj, methodName, ...)
    if not obj or not obj[methodName] then return false, nil end
    local args = {...}
    return pcall(function()
        return obj[methodName](obj, unpack(args))
    end)
end


--- Try a list of method names on an object. Returns the first result
--- that is a number. Useful for probing API methods that may differ
--- across PZ builds.
---@param obj any
---@param methodNames table   List of method name strings to try
---@return number|nil
function PhobosLib.probeMethod(obj, methodNames)
    if not obj then return nil end
    for _, m in ipairs(methodNames) do
        local ok, v = PhobosLib.pcallMethod(obj, m)
        if ok and type(v) == "number" then return v end
    end
    return nil
end


--- Try a list of method names on an object. Returns the first non-nil
--- result of any type (not restricted to numbers).
---@param obj any
---@param methodNames table
---@return any|nil
function PhobosLib.probeMethodAny(obj, methodNames)
    if not obj then return nil end
    for _, m in ipairs(methodNames) do
        local ok, v = PhobosLib.pcallMethod(obj, m)
        if ok and v ~= nil then return v end
    end
    return nil
end


--- Check whether an item's fullType or displayName contains any of the
--- given keywords (case-insensitive plain substring match).
---@param item any          A PZ inventory item
---@param keywords table    List of keyword strings
---@return boolean
function PhobosLib.matchesKeywords(item, keywords)
    if not item or not keywords then return false end
    local ft = (item.getFullType and PhobosLib.lower(item:getFullType())) or ""
    local dn = (item.getDisplayName and PhobosLib.lower(item:getDisplayName())) or ""
    for _, kw in ipairs(keywords) do
        local k = PhobosLib.lower(kw)
        if k ~= "" and (string.find(ft, k, 1, true) or string.find(dn, k, 1, true)) then
            return true
        end
    end
    return false
end


--- Resolve an inventory-or-player argument to an ItemContainer.
--- If the argument has getInventory() (e.g. IsoGameCharacter), call
--- it to get the main inventory.  Otherwise return as-is.
--- This lets all find* functions accept either a player or a container.
---@param inventoryOrPlayer any  ItemContainer or IsoGameCharacter
---@return any  The resolved ItemContainer (or original arg on failure)
local function resolveInventory(inventoryOrPlayer)
    if not inventoryOrPlayer then return nil end
    local ok, inv = PhobosLib.safecall(function()
        if inventoryOrPlayer.getInventory then
            return inventoryOrPlayer:getInventory()
        end
        return inventoryOrPlayer
    end)
    return ok and inv or inventoryOrPlayer
end


--- Find the first item in an inventory whose fullType or displayName
--- matches one of the given keywords.
---@param inventory any     A PZ ItemContainer or IsoGameCharacter
---@param keywords table    List of keyword strings
---@return any|nil          The matching item, or nil
function PhobosLib.findItemByKeywords(inventory, keywords)
    inventory = resolveInventory(inventory)
    if not inventory or not keywords then return nil end
    local items = inventory:getItems()
    for i = 0, items:size() - 1 do
        local it = items:get(i)
        if it and PhobosLib.matchesKeywords(it, keywords) then
            return it
        end
    end
    return nil
end


--- Find ALL items in an inventory matching the given keywords.
---@param inventory any     A PZ ItemContainer or IsoGameCharacter
---@param keywords table
---@return table            List of matching items (may be empty)
function PhobosLib.findAllItemsByKeywords(inventory, keywords)
    local results = {}
    inventory = resolveInventory(inventory)
    if not inventory or not keywords then return results end
    local items = inventory:getItems()
    for i = 0, items:size() - 1 do
        local it = items:get(i)
        if it and PhobosLib.matchesKeywords(it, keywords) then
            table.insert(results, it)
        end
    end
    return results
end


--- Find an item by exact fullType string.
---@param inventory any     A PZ ItemContainer or IsoGameCharacter
---@param fullType string
---@return any|nil
function PhobosLib.findItemByFullType(inventory, fullType)
    inventory = resolveInventory(inventory)
    if not inventory or not fullType then return nil end
    local ok, result = PhobosLib.safecall(function()
        return inventory:FindAndReturn(fullType)
    end)
    if ok then return result end
    return nil
end


--- Find ALL items matching an exact fullType string.
---@param inventory any     A PZ ItemContainer or IsoGameCharacter
---@param fullType string
---@return table
function PhobosLib.findAllItemsByFullType(inventory, fullType)
    local results = {}
    inventory = resolveInventory(inventory)
    if not inventory or not fullType then return results end
    local items = inventory:getItems()
    for i = 0, items:size() - 1 do
        local it = items:get(i)
        if it and it.getFullType and it:getFullType() == fullType then
            table.insert(results, it)
        end
    end
    return results
end


--- Find the first item whose fullType matches any entry in the given list.
--- Searches main inventory only (not nested bags).
---@param inventory any    A PZ ItemContainer or IsoGameCharacter
---@param typeList table   Array of fullType strings, e.g. {"Base.Garbagebag", "Base.Bag_TrashBag"}
---@return any|nil         The inventory item, or nil if none found
function PhobosLib.findItemFromTypeList(inventory, typeList)
    inventory = resolveInventory(inventory)
    if not inventory or not typeList then return nil end
    local allowed = {}
    for _, ft in ipairs(typeList) do allowed[ft] = true end
    local items = inventory:getItems()
    for i = 0, items:size() - 1 do
        local it = items:get(i)
        if it and it.getFullType and allowed[it:getFullType()] then
            return it
        end
    end
    return nil
end


--- Count all items whose fullType matches any entry in the given list.
--- Searches main inventory only (not nested bags).
---@param inventory any    A PZ ItemContainer or IsoGameCharacter
---@param typeList table   Array of fullType strings
---@return number          Total count of matching items
function PhobosLib.countItemsFromTypeList(inventory, typeList)
    inventory = resolveInventory(inventory)
    if not inventory or not typeList then return 0 end
    local allowed = {}
    for _, ft in ipairs(typeList) do allowed[ft] = true end
    local count = 0
    local items = inventory:getItems()
    for i = 0, items:size() - 1 do
        local it = items:get(i)
        if it and it.getFullType and allowed[it:getFullType()] then
            count = count + 1
        end
    end
    return count
end


--- Find the first FluidContainer in the player's inventory that holds
--- at least minAmount of any of the named fluids.
--- Searches main inventory only (not nested bags).
---@param inventory any        A PZ ItemContainer or IsoGameCharacter
---@param fluidNames table     Array of fluid name strings, e.g. {"Bleach", "CleaningLiquid"}
---@param minAmount number     Minimum fluid amount in litres
---@return any|nil             The inventory item, or nil if none found
function PhobosLib.findFluidContainerWithMin(inventory, fluidNames, minAmount)
    inventory = resolveInventory(inventory)
    if not inventory or not fluidNames or not minAmount then return nil end
    local allowed = {}
    for _, fn in ipairs(fluidNames) do allowed[fn] = true end
    local result = nil
    PhobosLib.safecall(function()
        local items = inventory:getItems()
        for i = 0, items:size() - 1 do
            local item = items:get(i)
            if item then
                local fc = PhobosLib.tryGetFluidContainer(item)
                if fc then
                    local name = PhobosLib.tryGetFluidName(fc)
                    if name and allowed[name] then
                        local amt = PhobosLib.tryGetAmount(fc)
                        if amt and amt >= minAmount then
                            result = item
                            return
                        end
                    end
                end
            end
        end
    end)
    return result
end


---------------------------------------------------------------
-- Recursive inventory search (main + equipped bags/backpacks)
---------------------------------------------------------------

--- Extract the short type name from a fullType string.
--- e.g. "Base.Garbagebag" → "Garbagebag"
---@param fullType string
---@return string
local function toShortType(fullType)
    return fullType:match("%.(.+)$") or fullType
end


--- Find an item by exact fullType, searching main inventory + equipped bags.
---@param inventory any     A PZ ItemContainer or IsoGameCharacter
---@param fullType string
---@return any|nil
function PhobosLib.findItemByFullTypeRecurse(inventory, fullType)
    inventory = resolveInventory(inventory)
    if not inventory or not fullType then return nil end
    local ok, result = PhobosLib.safecall(function()
        local item = inventory:getFirstTypeRecurse(toShortType(fullType))
        if item and item.getFullType and item:getFullType() == fullType then
            return item
        end
        return nil
    end)
    if ok then return result end
    return nil
end


--- Find the first item whose fullType matches any entry in the given list.
--- Searches main inventory + equipped bags/backpacks (recursive).
---@param inventory any    A PZ ItemContainer or IsoGameCharacter
---@param typeList table   Array of fullType strings, e.g. {"Base.Garbagebag", "Base.Bag_TrashBag"}
---@return any|nil         The inventory item, or nil if none found
function PhobosLib.findItemFromTypeListRecurse(inventory, typeList)
    inventory = resolveInventory(inventory)
    if not inventory or not typeList then return nil end
    for _, ft in ipairs(typeList) do
        local ok, item = PhobosLib.safecall(function()
            return inventory:getFirstTypeRecurse(toShortType(ft))
        end)
        if ok and item and item.getFullType and item:getFullType() == ft then
            return item
        end
    end
    return nil
end


--- Count all items whose fullType matches any entry in the given list.
--- Searches main inventory + equipped bags/backpacks (recursive).
---@param inventory any    A PZ ItemContainer or IsoGameCharacter
---@param typeList table   Array of fullType strings
---@return number          Total count of matching items
function PhobosLib.countItemsFromTypeListRecurse(inventory, typeList)
    inventory = resolveInventory(inventory)
    if not inventory or not typeList then return 0 end
    local count = 0
    for _, ft in ipairs(typeList) do
        local ok, n = PhobosLib.safecall(function()
            return inventory:getItemCountRecurse(toShortType(ft))
        end)
        if ok and n then count = count + n end
    end
    return count
end


--- Find the first FluidContainer in the player's inventory (including
--- equipped bags) that holds at least minAmount of any of the named fluids.
---@param inventory any        A PZ ItemContainer or IsoGameCharacter
---@param fluidNames table     Array of fluid name strings, e.g. {"Bleach", "CleaningLiquid"}
---@param minAmount number     Minimum fluid amount in litres
---@return any|nil             The inventory item, or nil if none found
function PhobosLib.findFluidContainerWithMinRecurse(inventory, fluidNames, minAmount)
    inventory = resolveInventory(inventory)
    if not inventory or not fluidNames or not minAmount then return nil end
    local allowed = {}
    for _, fn in ipairs(fluidNames) do allowed[fn] = true end

    -- Scan a single container for a matching fluid item
    local function scanContainer(container)
        local items = container:getItems()
        for i = 0, items:size() - 1 do
            local item = items:get(i)
            if item then
                local fc = PhobosLib.tryGetFluidContainer(item)
                if fc then
                    local name = PhobosLib.tryGetFluidName(fc)
                    if name and allowed[name] then
                        local amt = PhobosLib.tryGetAmount(fc)
                        if amt and amt >= minAmount then
                            return item
                        end
                    end
                end
            end
        end
        return nil
    end

    local result = nil
    PhobosLib.safecall(function()
        -- Search main inventory first
        result = scanContainer(inventory)
        if result then return end

        -- Search equipped bags/backpacks (one level deep)
        local items = inventory:getItems()
        for i = 0, items:size() - 1 do
            local item = items:get(i)
            if item and item.getItemContainer then
                local sub = item:getItemContainer()
                if sub then
                    result = scanContainer(sub)
                    if result then return end
                end
            end
        end
    end)
    return result
end


--- Safe player:Say() wrapper. Does nothing if player is nil or Say is unavailable.
---@param player any
---@param msg string
function PhobosLib.say(player, msg)
    if player and player.Say then
        PhobosLib.safecall(function() player:Say(msg) end)
    end
end


--- Safe item weight getter. Probes getActualWeight then getWeight.
---@param item any
---@return number
function PhobosLib.getItemWeight(item)
    return PhobosLib.probeMethod(item, {"getActualWeight", "getWeight"}) or 0
end


--- Safe UseDelta getter for Drainable items.
---@param item any
---@return number   0.0-1.0 range, or 0 if not drainable
function PhobosLib.getItemUseDelta(item)
    return PhobosLib.probeMethod(item, {"getUsedDelta", "getUseDelta"}) or 0
end


--- Safe UseDelta setter for Drainable items. Clamps to [0, 1].
---@param item any
---@param value number
---@return boolean  true if successfully set
function PhobosLib.setItemUseDelta(item, value)
    if not item then return false end
    value = math.max(0, math.min(1, value))
    local ok = false
    -- Try setUsedDelta first (standard PZ method)
    if item.setUsedDelta then
        ok = select(1, PhobosLib.safecall(function() item:setUsedDelta(value) end))
    end
    if not ok and item.setUseDelta then
        ok = select(1, PhobosLib.safecall(function() item:setUseDelta(value) end))
    end
    return ok
end


--- Re-add consumed recipe items to a player's inventory (for refunding
--- failed crafting operations).
---@param items any     The Java ArrayList of consumed items from a recipe
---@param player any    The player to refund to
function PhobosLib.refundItems(items, player)
    if not items or not player then return end
    local inv = player:getInventory()
    if not inv then return end
    for i = 0, items:size() - 1 do
        local it = items:get(i)
        if it and it.getFullType then
            PhobosLib.safecall(function() inv:AddItem(it:getFullType()) end)
        end
    end
end


--- Safe item condition getter.
---@param item any
---@return number|nil
function PhobosLib.getItemCondition(item)
    return PhobosLib.probeMethod(item, {"getCondition"})
end


--- Safe item condition setter.
---@param item any
---@param value number
---@return boolean
function PhobosLib.setItemCondition(item, value)
    if not item or not item.setCondition then return false end
    local ok = PhobosLib.safecall(function() item:setCondition(math.floor(value)) end)
    return ok
end


--- Get item condition as a percentage (0-100), normalised to ConditionMax.
--- Useful for mods that store metadata in condition (e.g. purity tracking).
--- Returns nil if item has no ConditionMax or ConditionMax <= 0.
---@param item any
---@return number|nil  Percentage 0-100, or nil
function PhobosLib.getConditionPercent(item)
    if not item then return nil end
    local ok, result = PhobosLib.safecall(function()
        local maxCond = item:getConditionMax()
        if not maxCond or maxCond <= 0 then return nil end
        return math.floor(item:getCondition() / maxCond * 100 + 0.5)
    end)
    if ok then return result end
    return nil
end


--- Set item condition from a percentage (0-100), scaled to ConditionMax.
--- Clamps to [0, ConditionMax]. Calls sendItemStats for MP sync.
--- Useful for mods that store metadata in condition (e.g. purity tracking).
---@param item any
---@param percent number  Value 0-100
---@return boolean  true on success
function PhobosLib.setConditionPercent(item, percent)
    if not item then return false end
    percent = math.max(0, math.min(100, math.floor(percent + 0.5)))
    local ok = PhobosLib.safecall(function()
        local maxCond = item:getConditionMax()
        if maxCond and maxCond > 0 then
            local scaled = math.floor(percent / 100 * maxCond + 0.5)
            scaled = math.max(0, math.min(maxCond - 1, scaled))
            item:setCondition(scaled)
            PhobosLib.safecall(sendItemStats, item)
        end
    end)
    return ok
end


---------------------------------------------------------------
-- modData Helpers
-- Safe wrappers around PZ's item:getModData() for persistent
-- key-value storage on items. Used by quality/purity systems.
---------------------------------------------------------------

--- Safe modData table getter. Returns the modData table or nil.
---@param item any  A PZ inventory item
---@return table|nil
function PhobosLib.getModData(item)
    if not item or not item.getModData then return nil end
    local ok, md = PhobosLib.safecall(function() return item:getModData() end)
    if ok and md then return md end
    return nil
end


--- Read a single value from an item's modData with a default fallback.
---@param item any
---@param key string
---@param default any
---@return any
function PhobosLib.getModDataValue(item, key, default)
    local md = PhobosLib.getModData(item)
    if md and md[key] ~= nil then return md[key] end
    return default
end


--- Write a single value to an item's modData. Returns true on success.
---@param item any
---@param key string
---@param value any
---@return boolean
function PhobosLib.setModDataValue(item, key, value)
    local md = PhobosLib.getModData(item)
    if not md then return false end
    md[key] = value
    return true
end


---------------------------------------------------------------
-- Player Utilities
---------------------------------------------------------------

--- Check if a player has a specific trait by string ID.
--- Handles PZ B42's CharacterTrait enum lookup correctly.
--- player:getTraits() returns Map<CharacterTrait, Boolean> (no contains()),
--- so we resolve the enum constant first and use SurvivorDesc:hasTrait().
---@param player any     IsoPlayer
---@param traitId string Trait ID (e.g. "pos:POS_AnalyticalMind")
---@return boolean
function PhobosLib.hasTrait(player, traitId)
    if not player or type(traitId) ~= "string" then return false end
    local ok, result = PhobosLib.safecall(function()
        -- Look up the CharacterTrait enum constant by name
        local traitEnum = CharacterTrait[traitId]
        if traitEnum then
            -- SurvivorDesc:hasTrait(CharacterTrait) is the correct B42 API
            return player:getDescriptor():hasTrait(traitEnum)
        end
        -- Fallback: iterate known traits list (handles edge cases where
        -- enum lookup fails, e.g. traits registered by other mods)
        local known = player:getCharacterTraits():getKnownTraits()
        if known then
            for i = 0, known:size() - 1 do
                local t = known:get(i)
                if t and tostring(t) == traitId then return true end
            end
        end
        return false
    end)
    return ok and result == true
end


--- Check if a player has admin-level access.
--- Returns true for singleplayer, co-op host, or dedicated server admins.
--- Generic utility — any Phobos mod can use this for privilege gating.
---@param player any  IsoPlayer
---@return boolean
function PhobosLib.isPlayerAdmin(player)
    if not player then return false end
    -- Singleplayer or co-op host: not a network client
    if not isClient() then return true end
    -- Dedicated server client: check access level
    local ok, level = PhobosLib.safecall(function() return player:getAccessLevel() end)
    if ok and type(level) == "string" then
        return string.lower(level) == "admin"
    end
    return false
end


--- Ensure a named sub-table exists in a player's modData and return it.
--- Creates the sub-table if it doesn't exist. Safe wrapper that avoids
--- the repetitive `md[key] = md[key] or {}` pattern.
---@param player any     IsoPlayer (or any object with getModData())
---@param key string     The modData sub-table key
---@return table|nil     The sub-table, or nil if modData is inaccessible
function PhobosLib.getPlayerModDataTable(player, key)
    local md = PhobosLib.getModData(player)
    if not md or not key then return nil end
    if not md[key] then md[key] = {} end
    return md[key]
end


--- Generate a unique identifier string.
--- Combines the current game time (milliseconds) with a random suffix to produce
--- a collision-resistant ID suitable for tagging items and event log entries.
--- Format: "<timestamp>-<random5>" e.g. "1710934200000-47823"
---@return string  Unique identifier
function PhobosLib.generateId()
    local ts = getTimestampMs and getTimestampMs() or (os.time() * 1000)
    local suffix = ZombRand(10000, 99999)
    return tostring(ts) .. "-" .. tostring(suffix)
end


--- Find all items in an inventory that have a specific tag.
--- Uses PZ B42 item:hasTag() for tag-based inventory queries.
---@param inventory any     A PZ ItemContainer or IsoGameCharacter
---@param tagName string    Tag name (e.g. "POS_RawIntel", "pcp:protectivegloves")
---@return table            List of matching items (may be empty)
function PhobosLib.findItemsByTag(inventory, tagName)
    local results = {}
    inventory = resolveInventory(inventory)
    if not inventory or not tagName then return results end
    local items = inventory:getItems()
    for i = 0, items:size() - 1 do
        local it = items:get(i)
        if it and it.hasTag then
            local ok, has = PhobosLib.safecall(it.hasTag, it, tagName)
            if ok and has then
                table.insert(results, it)
            end
        end
    end
    return results
end


--- Count all items in an inventory that have a specific tag.
--- Uses PZ B42 item:hasTag() for tag-based inventory queries.
---@param inventory any     A PZ ItemContainer or IsoGameCharacter
---@param tagName string    Tag name (e.g. "POS_RawIntel", "pcp:protectivegloves")
---@return number           Total count of matching items
function PhobosLib.countItemsByTag(inventory, tagName)
    inventory = resolveInventory(inventory)
    if not inventory or not tagName then return 0 end
    local count = 0
    local items = inventory:getItems()
    for i = 0, items:size() - 1 do
        local it = items:get(i)
        if it and it.hasTag then
            local ok, has = PhobosLib.safecall(it.hasTag, it, tagName)
            if ok and has then
                count = count + 1
            end
        end
    end
    return count
end


--- Resolve a full item type string to its localized display name.
--- Uses ScriptManager to look up the item script and return its display name.
--- Falls back to stripping the module prefix (e.g. "Base.Pen" → "Pen").
---@param fullType string  Full item type (e.g. "Base.Pen")
---@return string          Localized display name, or stripped type name as fallback
function PhobosLib.getItemDisplayName(fullType)
    if not fullType then return "" end
    if ScriptManager and ScriptManager.instance then
        local script = ScriptManager.instance:getItem(fullType)
        if script then
            local dn = script:getDisplayName()
            if dn then return dn end
        end
    end
    return fullType:match("[^.]+$") or fullType
end
