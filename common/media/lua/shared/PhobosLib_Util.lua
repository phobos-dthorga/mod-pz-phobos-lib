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


--- Sanitise a player username for use as a filesystem path component
--- or ModData key. PZ's Java getFileReader/getFileWriter crash at the
--- JVM level (hard CTD, bypasses pcall) when the path contains certain
--- characters — notably apostrophes. This function strips everything
--- except alphanumeric characters, hyphens, and underscores.
---
--- All Phobos mods that use player:getUsername() in file paths, ModData
--- keys, or stored identifiers MUST call this to prevent silent crashes
--- on players with special characters in their names.
---@param raw string|nil  Raw username from player:getUsername()
---@param fallback string|nil  Fallback for nil/empty (default "singleplayer")
---@return string  Sanitised, filesystem-safe username
function PhobosLib.sanitiseUsername(raw, fallback)
    fallback = fallback or "singleplayer"
    if not raw or raw == "" then return fallback end
    local safe = string.gsub(raw, "[^%w%-_]", "_")
    if safe == "" then return fallback end
    return safe
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


--- Resolve a display name from a registry-backed definition.
--- Looks up the definition by ID, reads its displayNameKey field,
--- and returns the translated text via safeGetText.
--- Enforces convention: registry definitions should have a displayNameKey field.
---@param registry table     PhobosLib registry instance (from createRegistry)
---@param id string          Definition ID to look up
---@param fallback string|nil Fallback if definition not found (default: the ID itself)
---@return string            Localised display name, or fallback
function PhobosLib.getRegistryDisplayName(registry, id, fallback)
    fallback = fallback or id
    if not registry or not id then return fallback end
    local def = registry:get(id)
    if not def or not def.displayNameKey then return fallback end
    return PhobosLib.safeGetText(def.displayNameKey, id)
end


--- Returns the player's level in a given perk, or 0 on any failure.
--- Safe wrapper around player:getPerkLevel(Perks.FromString(perkId)).
--- @param player IsoPlayer
--- @param perkId string  -- e.g. "Electricity", "Passiv"
--- @return number level  -- 0..10, or 0 on nil/error
function PhobosLib.getPlayerPerkLevel(player, perkId)
    if not player or not perkId then return 0 end
    local ok, perk = PhobosLib.safecall(Perks.FromString, perkId)
    if not ok or not perk then return 0 end
    local ok2, level = PhobosLib.safecall(player.getPerkLevel, player, perk)
    if not ok2 or not level then return 0 end
    return level
end


---------------------------------------------------------------
-- Infrastructure Utilities
---------------------------------------------------------------

--- Compute Manhattan distance between two 3D points with optional Z-level penalty.
---@param x1 number Source X coordinate
---@param y1 number Source Y coordinate
---@param z1 number Source Z coordinate (floor level)
---@param x2 number Target X coordinate
---@param y2 number Target Y coordinate
---@param z2 number Target Z coordinate (floor level)
---@param zPenalty number|nil Extra cost per Z-level difference (default 1)
---@return number Total Manhattan distance including Z penalty
function PhobosLib.manhattanDistance(x1, y1, z1, x2, y2, z2, zPenalty)
    zPenalty = zPenalty or 1
    return math.abs(x2 - x1) + math.abs(y2 - y1) + (math.abs(z2 - z1) * zPenalty)
end


--- Consume N items of a given type from the player's main inventory.
--- Removes items one at a time via getFirstType/Remove loop.
---@param player IsoPlayer The player whose inventory to consume from
---@param fullType string Full item type (e.g. "Base.ElectricWire")
---@param count number Number of items to consume
---@return number Actual number consumed (may be less than count if inventory short)
function PhobosLib.consumeItems(player, fullType, count)
    if not player or not fullType or not count or count <= 0 then return 0 end
    local inv = player:getInventory()
    if not inv then return 0 end
    local consumed = 0
    for i = 1, count do
        local item = inv:getFirstType(fullType)
        if not item then break end
        inv:Remove(item)
        consumed = consumed + 1
    end
    return consumed
end


--- Grant N items of a given type to the player's main inventory.
---@param player IsoPlayer The player to grant items to
---@param fullType string Full item type (e.g. "Base.ElectricWire")
---@param count number Number of items to grant
---@return number Actual number granted
function PhobosLib.grantItems(player, fullType, count)
    if not player or not fullType or not count or count <= 0 then return 0 end
    local inv = player:getInventory()
    if not inv then return 0 end
    local granted = 0
    for i = 1, count do
        inv:AddItem(fullType)
        granted = granted + 1
    end
    return granted
end


--- Check whether a player meets a set of requirements (items, tools, skill).
--- Returns a structured result suitable for tooltip generation.
---@param player IsoPlayer The player to check
---@param opts table Requirements table:
---   items = {fullType, count} or nil — item type and quantity needed
---   tools = {"Base.Screwdriver", "Base.Pliers"} or nil — tool types that must be in inventory
---   minSkill = number or nil — minimum skill level required
---   skillType = string or nil — PZ perk name (e.g. "Electrical")
---@return table Result: { ok=bool, missingItems={type,need,have}, missingTools={type,...}, skillTooLow=bool, skillHave=n, skillNeed=n }
function PhobosLib.checkRequirements(player, opts)
    if not player or not opts then
        return { ok = false, missingItems = {}, missingTools = {}, skillTooLow = false, skillHave = 0, skillNeed = 0 }
    end

    local result = {
        ok = true,
        missingItems = {},
        missingTools = {},
        skillTooLow = false,
        skillHave = 0,
        skillNeed = 0,
    }

    local inv = player:getInventory()

    -- Check items
    if opts.items and inv then
        local itemType = opts.items[1]
        local itemNeed = opts.items[2] or 1
        local itemHave = inv:getCountType(itemType) or 0
        if itemHave < itemNeed then
            result.ok = false
            result.missingItems = { type = itemType, need = itemNeed, have = itemHave }
        end
    end

    -- Check tools
    if opts.tools and inv then
        for _, toolType in ipairs(opts.tools) do
            if not inv:containsType(toolType) then
                result.ok = false
                table.insert(result.missingTools, toolType)
            end
        end
    end

    -- Check skill
    if opts.minSkill and opts.skillType then
        local perk = Perks.FromString(opts.skillType)
        local skillHave = 0
        if perk then
            skillHave = player:getPerkLevel(perk)
        end
        result.skillHave = skillHave
        result.skillNeed = opts.minSkill
        if skillHave < opts.minSkill then
            result.ok = false
            result.skillTooLow = true
        end
    end

    return result
end


---------------------------------------------------------------
-- Math & Table Utilities
---------------------------------------------------------------

--- Clamp a numeric value to the range [min, max].
---@param value number  The value to clamp
---@param min   number  Lower bound
---@param max   number  Upper bound
---@return number       Clamped value
function PhobosLib.clamp(value, min, max)
    if value < min then return min end
    if value > max then return max end
    return value
end


--- Linearly interpolate between two values.
--- Returns a when t=0, b when t=1, and proportional values in between.
---@param a number  Start value
---@param b number  End value
---@param t number  Interpolation factor (typically 0..1, but not clamped)
---@return number   Interpolated value
function PhobosLib.lerp(a, b, t)
    return a + (b - a) * t
end


--- Generate a random float in the range [min, max) using ZombRand.
--- Uses 10000-step precision for smooth distribution.
---@param min number  Lower bound (inclusive)
---@param max number  Upper bound (exclusive)
---@return number     Random float in [min, max)
function PhobosLib.randFloat(min, max)
    local precision = 10000
    local raw = ZombRand(precision) / precision
    return min + raw * (max - min)
end


--- Round a number to a given number of decimal places.
--- Defaults to 0 decimal places (integer rounding).
---@param value    number         The value to round
---@param decimals number|nil     Decimal places (default 0)
---@return number                 Rounded value
function PhobosLib.round(value, decimals)
    local mult = 10 ^ (decimals or 0)
    return math.floor(value * mult + 0.5) / mult
end


--- Smoothly approach a target value at a given rate per tick.
--- Formula: current + (target - current) * rate
---@param current number  Current value
---@param target  number  Target value to approach
---@param rate    number  Approach rate (0.0 = no change, 1.0 = instant snap)
---@return number         New value closer to target
function PhobosLib.approach(current, target, rate)
    return current + (target - current) * rate
end


--- Transform each element of an array-style table using a function.
--- Returns a new table; the original is not modified.
---@param tbl table              Array-style table
---@param fn  fun(v:any, i:number):any  Transform function (value, index) → new value
---@return table                 New table with transformed elements
function PhobosLib.map(tbl, fn)
    local result = {}
    for i, v in ipairs(tbl) do
        result[i] = fn(v, i)
    end
    return result
end


--- Filter an array-style table, keeping only elements where predicate returns true.
--- Returns a new table; the original is not modified.
---@param tbl       table                    Array-style table
---@param predicate fun(v:any, i:number):boolean  Predicate function (value, index) → keep?
---@return table                             New table with matching elements
function PhobosLib.filter(tbl, predicate)
    local result = {}
    for i, v in ipairs(tbl) do
        if predicate(v, i) then
            result[#result + 1] = v
        end
    end
    return result
end

--- Filter an array by field equality.
--- Returns a new array containing only entries where entry[fieldName] == value.
--- Returns {} on nil input (§25.6 collection convention).
---@param array table Array of tables to filter
---@param fieldName string Field name to check on each entry
---@param value any Value to match (equality check)
---@return table[] Filtered results (new array, never nil)
function PhobosLib.filterByField(array, fieldName, value)
    if not array or not fieldName then return {} end
    local results = {}
    for i = 1, #array do
        if array[i] and array[i][fieldName] == value then
            results[#results + 1] = array[i]
        end
    end
    return results
end


---------------------------------------------------------------
-- Recipe & Configuration Utilities
---------------------------------------------------------------

--- Find the first item in a list matching the given full type.
--- Uses PhobosLib.iterateItems() for B42 ArrayList/table safety.
---@param items any   Items parameter (ArrayList or table) — nil-safe
---@param fullType string  Full item type to match (e.g. "Base.Screwdriver")
---@return InventoryItem|nil item  First matching item, or nil
---@return number|nil        index Index of the match, or nil
function PhobosLib.findItemInList(items, fullType)
    if not items or not fullType then return nil, nil end
    for i, item in PhobosLib.iterateItems(items) do
        if item then
            local ok, ft = PhobosLib.safecall(item.getFullType, item)
            if ok and ft == fullType then
                return item, i
            end
        end
    end
    return nil, nil
end

--- Get a configurable value from a module, with fallback.
--- Safely calls module[methodName]() and returns the result, or fallback
--- if module, method, or result is nil. Uses safecall internally.
---@param module table|nil   Module table (may be nil)
---@param methodName string  Name of the getter method on module
---@param fallback any       Value returned when module/method/result is nil
---@return any               The method's return value, or fallback
function PhobosLib.getConfigurable(module, methodName, fallback)
    if not module then return fallback end
    if not module[methodName] then return fallback end
    local ok, result = PhobosLib.safecall(module[methodName], module)
    if ok and result ~= nil then
        return result
    end
    return fallback
end

--- Resolve a value against a sorted threshold tier list.
--- Walks tiers in order; returns the result of the first tier where
--- value <= tier.threshold. Returns default if no tier matches.
--- Nil-safe on value and tiers (returns default).
---@param value number|nil     Value to test against thresholds
---@param tiers table[]|nil    Sorted array of {threshold=number, result=any}
---@param default any          Value returned when no tier matches
---@return any                 The matching tier's result, or default
function PhobosLib.resolveThresholdTier(value, tiers, default)
    if value == nil or not tiers then return default end
    for i = 1, #tiers do
        local tier = tiers[i]
        if tier and tier.threshold and value <= tier.threshold then
            return tier.result
        end
    end
    return default
end


---------------------------------------------------------------
-- Text Compositor
---------------------------------------------------------------

--- Replace {key} placeholders in text with values from a context table.
--- If ctx[key] is nil, the placeholder is left unreplaced.
--- Nil-safe on both args (returns "" if text is nil).
---@param text string|nil  Template string with {key} placeholders
---@param ctx table|nil    Key-value lookup table for replacements
---@return string          Resolved string with placeholders replaced
function PhobosLib.resolveTokens(text, ctx)
    if not text then return "" end
    if not ctx then return text end
    return text:gsub("{(.-)}", function(key)
        local val = ctx[key]
        if val == nil then return "{" .. key .. "}" end
        return tostring(val)
    end)
end


--- Check if an entry's conditions match a context.
--- Supports minDifficulty, maxDifficulty, and arbitrary keys where value
--- is an array of allowed values. Returns true if entry has no conditions
--- field. Nil-safe on both args (returns true if either is nil).
---@param entry table|nil  Entry with optional conditions field
---@param ctx table|nil    Context table to check against
---@return boolean         True if all conditions pass or none exist
function PhobosLib.conditionsPass(entry, ctx)
    if not entry or not entry.conditions then return true end
    if not ctx then return false end
    local cond = entry.conditions
    if cond.minDifficulty and (not ctx.difficulty or ctx.difficulty < cond.minDifficulty) then
        return false
    end
    if cond.maxDifficulty and (not ctx.difficulty or ctx.difficulty > cond.maxDifficulty) then
        return false
    end
    for key, allowed in pairs(cond) do
        if key ~= "minDifficulty" and key ~= "maxDifficulty" then
            if type(allowed) == "table" then
                local ctxVal = ctx[key]
                if ctxVal == nil then return false end
                local found = false
                for i = 1, #allowed do
                    if allowed[i] == ctxVal then
                        found = true
                        break
                    end
                end
                if not found then return false end
            end
        end
    end
    return true
end


--- Select a random entry from a weighted pool.
--- Filters entries by conditionsPass(entry, ctx), sums remaining weights,
--- picks via ZombRand and walks cumulative weights.
--- Nil-safe on entries (returns nil).
---@param entries table[]|nil  Array of {text=string, weight=number, id=string, conditions=table|nil}
---@param ctx table|nil        Context table passed to conditionsPass
---@return table|nil           The selected entry table, or nil if no valid entries
function PhobosLib.pickWeighted(entries, ctx)
    if not entries then return nil end
    local valid = {}
    local totalWeight = 0
    for i = 1, #entries do
        local e = entries[i]
        if e and e.weight and PhobosLib.conditionsPass(e, ctx) then
            valid[#valid + 1] = e
            totalWeight = totalWeight + e.weight
        end
    end
    if totalWeight <= 0 or #valid == 0 then return nil end
    local roll = ZombRand(totalWeight)
    local cumulative = 0
    for i = 1, #valid do
        cumulative = cumulative + valid[i].weight
        if roll < cumulative then
            return valid[i]
        end
    end
    return valid[#valid]
end


--- Anti-repetition guard. Returns false if entryId is already in history.
--- Otherwise appends entryId to history, trims to maxSize, and returns true.
--- Nil-safe on history (returns true if nil).
---@param entryId string       ID to check and record
---@param history table|nil    Array of recent IDs (mutated in place)
---@param maxSize number|nil   Maximum history size (default 10)
---@return boolean             True if entryId was NOT recently used
function PhobosLib.avoidRecent(entryId, history, maxSize)
    if not history then return true end
    maxSize = maxSize or 10
    for i = 1, #history do
        if history[i] == entryId then return false end
    end
    history[#history + 1] = entryId
    while #history > maxSize do
        table.remove(history, 1)
    end
    return true
end


---------------------------------------------------------------
-- Terminal UI Utilities
---------------------------------------------------------------

--- Default colours for terminal UI elements.
local DEFAULT_TAB_ACTIVE_COLOUR   = { r = 0.9, g = 0.9, b = 0.9, a = 1.0 }
local DEFAULT_TAB_INACTIVE_COLOUR = { r = 0.5, g = 0.5, b = 0.5, a = 1.0 }
local DEFAULT_TAB_HEIGHT          = 25
local DEFAULT_TAB_WIDTH           = 100
local DEFAULT_TAB_GAP             = 2
local DEFAULT_BADGE_FONT          = UIFont.Small


--- Create a tabbed view with tab header buttons and a content panel.
--- Returns a controller table for switching tabs and cleanup.
---@param panel  table   ISPanel parent to add children to
---@param tabs   table[] Array of { id=string, labelKey=string, renderFn=function(contentPanel, y) }
---@param opts   table|nil  Optional: { x, y, width, height, activeTab, colours }
---@return table controller { switchTab(id), getActiveTab(), contentPanel, destroy() }
function PhobosLib.createTabbedView(panel, tabs, opts)
    if not panel or not tabs or #tabs == 0 then return nil end
    opts = opts or {}

    local x       = opts.x or 0
    local y       = opts.y or 0
    local width   = opts.width or panel:getWidth()
    local height  = opts.height or (panel:getHeight() - y)
    local colours = opts.colours or {}
    local activeColour   = colours.active or DEFAULT_TAB_ACTIVE_COLOUR
    local inactiveColour = colours.inactive or DEFAULT_TAB_INACTIVE_COLOUR

    local activeTabId = opts.activeTab or tabs[1].id
    local tabButtons  = {}

    -- Content panel below tab headers
    local contentY = y + DEFAULT_TAB_HEIGHT + DEFAULT_TAB_GAP
    local contentPanel = ISPanel:new(x, contentY, width, height - DEFAULT_TAB_HEIGHT - DEFAULT_TAB_GAP)
    contentPanel:initialise()
    contentPanel:instantiate()
    panel:addChild(contentPanel)

    --- Remove all children from the content panel.
    local function clearContent()
        local children = contentPanel:getControls()
        if children then
            for i = children:size() - 1, 0, -1 do
                local child = children:get(i)
                contentPanel:removeChild(child)
            end
        end
    end

    --- Render the active tab's content using safecall.
    local function renderActiveTab()
        clearContent()
        for i = 1, #tabs do
            if tabs[i].id == activeTabId and tabs[i].renderFn then
                PhobosLib.safecall(tabs[i].renderFn, contentPanel, 0)
                break
            end
        end
    end

    --- Update button colours to reflect active state.
    local function updateButtonColours()
        for id, btn in pairs(tabButtons) do
            if id == activeTabId then
                btn:setTextureColor(ColorInfo.new(activeColour.r, activeColour.g, activeColour.b, activeColour.a))
                btn.textColor = activeColour
            else
                btn:setTextureColor(ColorInfo.new(inactiveColour.r, inactiveColour.g, inactiveColour.b, inactiveColour.a))
                btn.textColor = inactiveColour
            end
        end
    end

    -- Create tab header buttons
    local btnX = x
    for i = 1, #tabs do
        local tab = tabs[i]
        local label = PhobosLib.safeGetText(tab.labelKey)
        local btn = ISButton:new(btnX, y, DEFAULT_TAB_WIDTH, DEFAULT_TAB_HEIGHT, label, nil, nil)
        btn:initialise()
        btn:instantiate()
        btn.internal = tab.id
        btn.onclick = function()
            activeTabId = tab.id
            updateButtonColours()
            renderActiveTab()
        end
        panel:addChild(btn)
        tabButtons[tab.id] = btn
        btnX = btnX + DEFAULT_TAB_WIDTH + DEFAULT_TAB_GAP
    end

    -- Initial render
    updateButtonColours()
    renderActiveTab()

    -- Controller
    local controller = {}

    --- Switch to a tab by id.
    ---@param id string Tab id to switch to
    function controller.switchTab(id)
        if not id then return end
        for i = 1, #tabs do
            if tabs[i].id == id then
                activeTabId = id
                updateButtonColours()
                renderActiveTab()
                return
            end
        end
    end

    --- Get the currently active tab id.
    ---@return string
    function controller.getActiveTab()
        return activeTabId
    end

    --- Reference to the content panel for direct access.
    controller.contentPanel = contentPanel

    --- Destroy all created UI elements and clean up.
    function controller.destroy()
        for _, btn in pairs(tabButtons) do
            panel:removeChild(btn)
        end
        panel:removeChild(contentPanel)
        tabButtons = {}
    end

    return controller
end


--- Create a coloured text label for status/type indicators.
--- Simple wrapper that enforces consistent badge sizing and font.
---@param panel  table   ISPanel parent
---@param x      number  X position
---@param y      number  Y position
---@param text   string  Text to display
---@param colour table   { r, g, b, a } text colour
---@return table         The ISLabel element
function PhobosLib.createStatusBadge(panel, x, y, text, colour)
    if not panel then return nil end
    text = text or ""
    colour = colour or DEFAULT_TAB_ACTIVE_COLOUR

    local label = ISLabel:new(x, y, DEFAULT_TAB_HEIGHT, text, colour.r, colour.g, colour.b, colour.a, DEFAULT_BADGE_FONT, true)
    label:initialise()
    label:instantiate()
    panel:addChild(label)
    return label
end


--- Create a collapsible row with a header panel and a detail panel.
--- The detail panel is hidden by default unless startExpanded is true.
--- Detail content is populated lazily on first expand.
---@param panel table  ISPanel parent
---@param opts  table  { x, y, width, headerHeight, detailHeight, headerFn, detailFn, startExpanded }
---@return table|nil   controller { toggle(), isExpanded(), destroy(), totalHeight() }
function PhobosLib.createExpandableRow(panel, opts)
    if not panel or not opts then return nil end

    local x             = opts.x or 0
    local y             = opts.y or 0
    local width         = opts.width or panel:getWidth()
    local headerHeight  = opts.headerHeight or DEFAULT_TAB_HEIGHT
    local detailHeight  = opts.detailHeight or 50
    local startExpanded = opts.startExpanded or false

    local expanded       = startExpanded
    local detailRendered = false

    -- Header panel
    local headerPanel = ISPanel:new(x, y, width, headerHeight)
    headerPanel:initialise()
    headerPanel:instantiate()
    panel:addChild(headerPanel)

    -- Detail panel (below header)
    local detailPanel = ISPanel:new(x, y + headerHeight, width, detailHeight)
    detailPanel:initialise()
    detailPanel:instantiate()
    detailPanel:setVisible(expanded)
    panel:addChild(detailPanel)

    -- Populate header content
    if opts.headerFn then
        PhobosLib.safecall(opts.headerFn, headerPanel)
    end

    --- Lazily render detail content on first expand.
    local function ensureDetailRendered()
        if detailRendered then return end
        detailRendered = true
        if opts.detailFn then
            PhobosLib.safecall(opts.detailFn, detailPanel)
        end
    end

    -- If starting expanded, render detail immediately
    if expanded then
        ensureDetailRendered()
    end

    -- Header click toggles detail visibility
    headerPanel.onMouseUp = function(self, mouseX, mouseY)
        expanded = not expanded
        if expanded then ensureDetailRendered() end
        detailPanel:setVisible(expanded)
    end

    -- Controller
    local controller = {}

    --- Toggle the expanded/collapsed state.
    function controller.toggle()
        expanded = not expanded
        if expanded then ensureDetailRendered() end
        detailPanel:setVisible(expanded)
    end

    --- Check if the row is currently expanded.
    ---@return boolean
    function controller.isExpanded()
        return expanded
    end

    --- Destroy all created UI elements.
    function controller.destroy()
        panel:removeChild(headerPanel)
        panel:removeChild(detailPanel)
    end

    --- Get the total height of the row (header only when collapsed, header + detail when expanded).
    ---@return number
    function controller.totalHeight()
        if expanded then
            return headerHeight + detailHeight
        end
        return headerHeight
    end

    return controller
end


---------------------------------------------------------------
-- Discovery & Selection Utilities
---------------------------------------------------------------

--- Pick N random entries from an array without replacement.
--- If count >= #pool, returns a copy of the entire pool.
--- Optional weightFn(entry) returns numeric weight (higher = more likely).
--- Uses ZombRand for PZ determinism. Never modifies the original pool.
---@param pool table|nil   Array of entries to select from
---@param count number     Number of entries to pick
---@param weightFn fun(entry):number|nil  Optional weight function (nil = equal weight)
---@return table           New array of selected entries (may be smaller than count)
function PhobosLib.selectRandomFromPool(pool, count, weightFn)
    if not pool or #pool == 0 then return {} end
    count = count or 1
    if count >= #pool then
        local copy = {}
        for i = 1, #pool do copy[i] = pool[i] end
        return copy
    end

    -- Build working list with indices so we can remove without mutating original
    local candidates = {}
    for i = 1, #pool do
        candidates[i] = { idx = i, entry = pool[i] }
    end

    local selected = {}
    for _ = 1, count do
        if #candidates == 0 then break end

        if weightFn then
            -- Weighted selection
            local totalWeight = 0
            for i = 1, #candidates do
                local w = weightFn(candidates[i].entry) or 1
                if w < 0 then w = 0 end
                totalWeight = totalWeight + w
            end
            if totalWeight <= 0 then break end

            local roll = ZombRand(math.floor(totalWeight * 1000)) / 1000
            local cumulative = 0
            local pickedIdx = 1
            for i = 1, #candidates do
                local w = weightFn(candidates[i].entry) or 1
                if w < 0 then w = 0 end
                cumulative = cumulative + w
                if roll < cumulative then
                    pickedIdx = i
                    break
                end
            end
            selected[#selected + 1] = candidates[pickedIdx].entry
            table.remove(candidates, pickedIdx)
        else
            -- Equal weight: simple ZombRand pick
            local pickedIdx = ZombRand(#candidates) + 1
            selected[#selected + 1] = candidates[pickedIdx].entry
            table.remove(candidates, pickedIdx)
        end
    end

    return selected
end


--- Track a discovery for a player within a namespace.
--- Uses PhobosLib.getPlayerModDataTable for storage. If the id already
--- exists in the namespace table, returns false (already discovered).
--- Otherwise stores metadata (or true if nil) and returns true.
---@param player any        IsoPlayer (or any object with getModData())
---@param namespace string  ModData sub-table key (e.g. "PIP_Discoveries")
---@param id string         Unique identifier for the discovery
---@param metadata any|nil  Data to store (defaults to true)
---@return boolean          true if newly discovered, false if already known
function PhobosLib.trackDiscovery(player, namespace, id, metadata)
    if not player or not namespace or not id then return false end
    local tbl = PhobosLib.getPlayerModDataTable(player, namespace)
    if not tbl then return false end
    if tbl[id] then return false end
    if metadata == nil then metadata = true end
    tbl[id] = metadata
    return true
end


--- Check whether a discovery has been made.
---@param player any        IsoPlayer
---@param namespace string  ModData sub-table key
---@param id string         Discovery identifier
---@return boolean          true if discovered
function PhobosLib.isDiscovered(player, namespace, id)
    if not player or not namespace or not id then return false end
    local tbl = PhobosLib.getPlayerModDataTable(player, namespace)
    if not tbl then return false end
    return tbl[id] ~= nil
end


--- Get all discoveries for a player within a namespace.
--- Returns the full table (id -> metadata) or {} if none.
---@param player any        IsoPlayer
---@param namespace string  ModData sub-table key
---@return table            id -> metadata mapping
function PhobosLib.getDiscoveries(player, namespace)
    if not player or not namespace then return {} end
    local tbl = PhobosLib.getPlayerModDataTable(player, namespace)
    return tbl or {}
end


---------------------------------------------------------------
-- Deferred initialisation & throttling
---------------------------------------------------------------

--- Create a lazy-init guard that runs initFn exactly once on first call.
--- Subsequent calls are a single boolean check (no-op).
--- Use to defer expensive module initialisation to first access.
---@param initFn fun() One-time initialisation function
---@return fun()        Guard function — call before accessing module state
function PhobosLib.lazyInit(initFn)
    local done = false
    return function()
        if done then return end
        done = true
        initFn()
    end
end


--- Wrap a function so it only executes once every N game-minutes.
--- Returns a new function suitable for Events.EveryOneMinute.Add().
--- The wrapped function fires immediately on first call, then skips
--- subsequent calls until intervalMinutes game-minutes have elapsed.
---@param fn               fun()   Function to throttle
---@param intervalMinutes  number  Minimum game-minutes between executions
---@return fun()                   Throttled wrapper function
function PhobosLib.throttle(fn, intervalMinutes)
    local lastMinute = -1
    return function()
        local gt = getGameTime and getGameTime()
        if not gt then return end
        local now = math.floor(gt:getWorldAgeHours() * 60)
        if lastMinute >= 0 and (now - lastMinute) < intervalMinutes then
            return
        end
        lastMinute = now
        fn()
    end
end


--- Create a stencil-clipped scrolling ISPanel.
--- Content taller than the panel height scrolls with mouse wheel.
--- The panel has transparent background and border so it blends with
--- any parent container. Use setScrollChildren(true) for child clipping.
---@param parent any   ISPanel parent to add the scroll panel to
---@param x      number X position relative to parent
---@param y      number Y position relative to parent
---@param w      number Width
---@param h      number Height
---@return any          ISPanel with scroll and stencil clipping enabled
function PhobosLib.createScrollPanel(parent, x, y, w, h)
    local panel = ISPanel:new(x, y, w, h)
    panel.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    panel.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    function panel:prerender()
        ISPanel.prerender(self)
        self:setStencilRect(0, 0, self.width, self.height)
    end
    function panel:postrender()
        self:clearStencilRect()
    end
    panel:setScrollChildren(true)
    panel:initialise()
    panel:instantiate()
    parent:addChild(panel)
    return panel
end
