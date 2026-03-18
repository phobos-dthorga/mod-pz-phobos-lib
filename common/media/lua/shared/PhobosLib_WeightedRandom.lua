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
-- PhobosLib_WeightedRandom.lua
-- Weighted random selection utilities.
--
-- Provides reusable weighted random selection for any table of
-- items with a weight accessor function. Avoids duplicating
-- weighted selection logic across multiple mods.
---------------------------------------------------------------

local WEIGHT_PRECISION = 1000

--- Select a single random item from a weighted table.
---
--- Each item's probability of selection is proportional to its weight.
--- Items with higher weights are selected more frequently.
---
--- @param items table Array of items to select from (must be non-empty)
--- @param weightFn function(item) → number  Weight accessor; must return > 0
--- @return any The selected item, or nil if items is empty
function PhobosLib.weightedRandom(items, weightFn)
    if not items or #items == 0 then return nil end
    if #items == 1 then return items[1] end

    local totalWeight = 0
    for i = 1, #items do
        local w = weightFn(items[i]) or 1
        totalWeight = totalWeight + w
    end

    if totalWeight <= 0 then
        return items[ZombRand(#items) + 1]
    end

    local roll = ZombRand(math.floor(totalWeight * WEIGHT_PRECISION)) / WEIGHT_PRECISION
    local acc = 0
    for i = 1, #items do
        acc = acc + (weightFn(items[i]) or 1)
        if roll < acc then return items[i] end
    end

    return items[#items]
end

--- Select multiple unique random items from a weighted table.
---
--- Items are selected without replacement — each item can appear at most once.
--- If count >= #items, returns a shuffled copy of the full table.
---
--- @param items table Array of items to select from
--- @param count number Number of unique items to select
--- @param weightFn function(item) → number  Weight accessor; must return > 0
--- @return table Array of selected items (length = min(count, #items))
function PhobosLib.weightedRandomMultiple(items, count, weightFn)
    if not items or #items == 0 then return {} end

    local n = math.min(count, #items)
    if n == #items then
        -- Return shuffled copy of full table
        local copy = {}
        for i = 1, #items do copy[i] = items[i] end
        for i = #copy, 2, -1 do
            local j = ZombRand(i) + 1
            copy[i], copy[j] = copy[j], copy[i]
        end
        return copy
    end

    -- Build working pool with indices
    local pool = {}
    for i = 1, #items do
        pool[i] = { item = items[i], weight = weightFn(items[i]) or 1 }
    end

    local selected = {}
    for _ = 1, n do
        local totalWeight = 0
        for i = 1, #pool do
            totalWeight = totalWeight + pool[i].weight
        end

        if totalWeight <= 0 then break end

        local roll = ZombRand(math.floor(totalWeight * WEIGHT_PRECISION)) / WEIGHT_PRECISION
        local acc = 0
        local chosenIdx = #pool
        for i = 1, #pool do
            acc = acc + pool[i].weight
            if roll < acc then
                chosenIdx = i
                break
            end
        end

        selected[#selected + 1] = pool[chosenIdx].item
        table.remove(pool, chosenIdx)
    end

    return selected
end
