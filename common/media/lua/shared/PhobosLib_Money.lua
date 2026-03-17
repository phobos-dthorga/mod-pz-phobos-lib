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
-- PhobosLib_Money.lua
-- Vanilla currency utilities for Base.Money ($1) and
-- Base.MoneyBundle ($100). Provides atomic counting,
-- removal (with bundle-breaking), and addition.
-- Part of PhobosLib — shared by all Phobos PZ mods.
---------------------------------------------------------------

PhobosLib = PhobosLib or {}

local _TAG = "[PhobosLib:Money]"

local MONEY_TYPE  = "Base.Money"
local BUNDLE_TYPE = "Base.MoneyBundle"
local BUNDLE_VALUE = 100

---------------------------------------------------------------
-- Counting
---------------------------------------------------------------

--- Count total dollar value in a player's inventory (recursive).
--- Counts Base.Money ($1 each) and Base.MoneyBundle ($100 each).
---@param player IsoPlayer
---@return number Total dollar value
function PhobosLib.countPlayerMoney(player)
    if not player then return 0 end
    local inv = player:getInventory()
    if not inv then return 0 end
    local singles = inv:getCountTypeRecurse(MONEY_TYPE) or 0
    local bundles = inv:getCountTypeRecurse(BUNDLE_TYPE) or 0
    return singles + (bundles * BUNDLE_VALUE)
end

--- Check whether a player can afford a given dollar amount.
---@param player IsoPlayer
---@param amount number Dollar amount to check
---@return boolean True if player has sufficient funds
function PhobosLib.canAfford(player, amount)
    if not player or not amount or amount <= 0 then return true end
    return PhobosLib.countPlayerMoney(player) >= amount
end

---------------------------------------------------------------
-- Removal (atomic — pre-checks before modifying inventory)
---------------------------------------------------------------

--- Remove an exact dollar amount from a player's inventory.
--- Removes bundles first, breaks one bundle for change if needed,
--- then removes singles. Pre-checks total before any modifications
--- to guarantee atomicity (no partial removals).
---@param player IsoPlayer
---@param amount number Dollar amount to remove (must be > 0)
---@return boolean True if removal succeeded, false if insufficient funds
function PhobosLib.removeMoney(player, amount)
    if not player or not amount or amount <= 0 then return false end

    local inv = player:getInventory()
    if not inv then return false end

    -- Pre-check: can afford?
    local total = PhobosLib.countPlayerMoney(player)
    if total < amount then
        PhobosLib.debug("PhobosLib", _TAG,
            "removeMoney: insufficient funds ($" .. tostring(amount)
            .. " requested, $" .. tostring(total) .. " available)")
        return false
    end

    local remaining = amount

    -- Phase 1: remove whole bundles
    local bundlesNeeded = math.floor(remaining / BUNDLE_VALUE)
    local bundlesAvailable = inv:getCountTypeRecurse(BUNDLE_TYPE) or 0
    local bundlesToRemove = math.min(bundlesNeeded, bundlesAvailable)

    for _ = 1, bundlesToRemove do
        local item = inv:getFirstTypeRecurse(BUNDLE_TYPE)
        if item then
            inv:Remove(item)
            remaining = remaining - BUNDLE_VALUE
        end
    end

    -- Phase 2: if remaining >= 1 and we still have bundles, break one
    if remaining > 0 and remaining < BUNDLE_VALUE then
        local singlesAvailable = inv:getCountTypeRecurse(MONEY_TYPE) or 0
        if singlesAvailable < remaining then
            -- Need to break a bundle for change
            local bundle = inv:getFirstTypeRecurse(BUNDLE_TYPE)
            if bundle then
                inv:Remove(bundle)
                -- Add change as singles
                local change = BUNDLE_VALUE - remaining
                for _ = 1, change do
                    inv:AddItem(MONEY_TYPE)
                end
                remaining = 0
            end
        end
    end

    -- Phase 3: remove remaining as singles
    if remaining > 0 then
        for _ = 1, remaining do
            local item = inv:getFirstTypeRecurse(MONEY_TYPE)
            if item then
                inv:Remove(item)
            end
        end
    end

    PhobosLib.debug("PhobosLib", _TAG,
        "removeMoney: removed $" .. tostring(amount)
        .. " (remaining balance: $" .. tostring(PhobosLib.countPlayerMoney(player)) .. ")")

    return true
end

---------------------------------------------------------------
-- Addition
---------------------------------------------------------------

--- Add a dollar amount to a player's inventory.
--- Adds as many bundles as possible, then singles for the remainder.
---@param player IsoPlayer
---@param amount number Dollar amount to add (must be > 0)
function PhobosLib.addMoney(player, amount)
    if not player or not amount or amount <= 0 then return end

    local inv = player:getInventory()
    if not inv then return end

    local bundles = math.floor(amount / BUNDLE_VALUE)
    local singles = amount % BUNDLE_VALUE

    for _ = 1, bundles do
        inv:AddItem(BUNDLE_TYPE)
    end

    for _ = 1, singles do
        inv:AddItem(MONEY_TYPE)
    end

    PhobosLib.debug("PhobosLib", _TAG,
        "addMoney: added $" .. tostring(amount)
        .. " (" .. tostring(bundles) .. " bundles, " .. tostring(singles) .. " singles)")
end

---------------------------------------------------------------

print(_TAG .. " loaded [shared]")
