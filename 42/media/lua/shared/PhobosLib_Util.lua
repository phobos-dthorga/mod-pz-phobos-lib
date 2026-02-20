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


--- Safe lowercase conversion. Returns "" for nil/non-string input.
---@param s any
---@return string
function PhobosLib.lower(s)
    return string.lower(tostring(s or ""))
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


--- Find the first item in an inventory whose fullType or displayName
--- matches one of the given keywords.
---@param inventory any     A PZ ItemContainer
---@param keywords table    List of keyword strings
---@return any|nil          The matching item, or nil
function PhobosLib.findItemByKeywords(inventory, keywords)
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
---@param inventory any
---@param keywords table
---@return table            List of matching items (may be empty)
function PhobosLib.findAllItemsByKeywords(inventory, keywords)
    local results = {}
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
---@param inventory any
---@param fullType string
---@return any|nil
function PhobosLib.findItemByFullType(inventory, fullType)
    if not inventory or not fullType then return nil end
    local ok, result = pcall(function()
        return inventory:FindAndReturn(fullType)
    end)
    if ok then return result end
    return nil
end


--- Find ALL items matching an exact fullType string.
---@param inventory any
---@param fullType string
---@return table
function PhobosLib.findAllItemsByFullType(inventory, fullType)
    local results = {}
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


--- Safe player:Say() wrapper. Does nothing if player is nil or Say is unavailable.
---@param player any
---@param msg string
function PhobosLib.say(player, msg)
    if player and player.Say then
        pcall(function() player:Say(msg) end)
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
        ok = select(1, pcall(function() item:setUsedDelta(value) end))
    end
    if not ok and item.setUseDelta then
        ok = select(1, pcall(function() item:setUseDelta(value) end))
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
            pcall(function() inv:AddItem(it:getFullType()) end)
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
    local ok = pcall(function() item:setCondition(math.floor(value)) end)
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
    local ok, md = pcall(function() return item:getModData() end)
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
